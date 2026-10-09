import Foundation
import AppKit
import Combine

struct PilotRuntimeSnapshot: Equatable {
    let statusText: String
    let isActive: Bool
    let isStatusBarAppEnabled: Bool
    let appVersionText: String
    let daemonVersionText: String
    let updatedAt: String?
}

private struct RuntimeFile: Decodable {
    let status: String?
    let packageVersion: String?
    let pid: Int?
    let updatedAt: String?
}

@MainActor
final class PilotRuntimeStore: ObservableObject {
    @Published private(set) var snapshot: PilotRuntimeSnapshot
    @Published private(set) var isReachable = false

    private var timer: Timer?
    private var consecutiveFailures = 0
    private let maxConsecutiveFailuresForStatus = 3
    private let maxConsecutiveFailuresForExit = 10  // 10 × 30s = 5 minutes

    private let runtimePath: String = {
        if let dataDir = ProcessInfo.processInfo.environment["LOONGSUITE_PILOT_DATA_DIR"], !dataDir.isEmpty {
            return (dataDir as NSString).appendingPathComponent("logs/runtime.json")
        }
        return NSString(string: "~/.loongsuite-pilot/logs/runtime.json").expandingTildeInPath
    }()

    init() {
        self.snapshot = PilotRuntimeSnapshot(
            statusText: "Connecting",
            isActive: false,
            isStatusBarAppEnabled: true,
            appVersionText: "v\(BuildInfo.version)",
            daemonVersionText: "v--",
            updatedAt: nil
        )
    }

    func start() {
        StatusBarLogger.info("runtime store started")
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        StatusBarLogger.info("runtime store stopped")
        timer?.invalidate()
        timer = nil
    }

    func refresh(forceReload: Bool = false) {
        let (loaded, pid) = loadSnapshot()
        var next = loaded
        let alive = next.isActive && isProcessAlive(pid)
        // Assigning a @Published value re-renders the panel even when it is
        // unchanged, and the panel open path calls this synchronously.
        if isReachable != alive { isReachable = alive }

        if alive {
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1

            if consecutiveFailures >= maxConsecutiveFailuresForStatus {
                next = PilotRuntimeSnapshot(
                    statusText: "Daemon not running",
                    isActive: false,
                    isStatusBarAppEnabled: next.isStatusBarAppEnabled,
                    appVersionText: next.appVersionText,
                    daemonVersionText: next.daemonVersionText,
                    updatedAt: next.updatedAt
                )
            }

            if consecutiveFailures >= maxConsecutiveFailuresForExit {
                StatusBarLogger.warning("daemon unreachable for 5 minutes, exiting status bar app")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.terminate(nil)
                }
            }
        }

        if snapshot != next { snapshot = next }
    }

    private func loadSnapshot() -> (PilotRuntimeSnapshot, Int?) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: runtimePath)),
              let file = try? JSONDecoder().decode(RuntimeFile.self, from: data) else {
            return (PilotRuntimeSnapshot(
                statusText: "No running service found",
                isActive: false,
                isStatusBarAppEnabled: true,
                appVersionText: "v\(BuildInfo.version)",
                daemonVersionText: "v--",
                updatedAt: nil
            ), nil)
        }

        let active = file.status == "active"
        let version = file.packageVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let daemonVersion = (version?.isEmpty == false) ? "v\(version!)" : "v--"
        let displayVersion = (version?.isEmpty == false) ? "v\(version!)" : "v\(BuildInfo.version)"

        return (PilotRuntimeSnapshot(
            statusText: active ? "Service running" : "Service status unknown",
            isActive: active,
            isStatusBarAppEnabled: true,
            appVersionText: displayVersion,
            daemonVersionText: daemonVersion,
            updatedAt: file.updatedAt
        ), file.pid)
    }

    private func isProcessAlive(_ pid: Int?) -> Bool {
        guard let pid, pid > 0 else { return false }
        return kill(Int32(pid), 0) == 0
    }
}
