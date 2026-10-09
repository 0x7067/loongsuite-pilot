import SwiftUI
import AppKit

final class FloatingPanel: NSPanel {
    // A plain rounded layer, not NSVisualEffectView: the SwiftUI root paints an
    // opaque background over the whole panel, so a behind-window blur was never
    // visible but was still recomputed on every key-state change and composited
    // continuously while the panel was open.
    private let containerView: NSView

    init(contentRect: NSRect) {
        containerView = NSView(frame: contentRect)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 420, height: 520)

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 18
        containerView.layer?.masksToBounds = true
        contentView = containerView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setRootView<Content: View>(_ rootView: Content) {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    func position(relativeTo statusButton: NSStatusBarButton) {
        guard
            let buttonWindow = statusButton.window,
            let screen = buttonWindow.screen ?? NSScreen.main
        else {
            return
        }

        let buttonFrameOnScreen = buttonWindow.convertToScreen(statusButton.convert(statusButton.bounds, to: nil))
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 10
        let spacing: CGFloat = 8

        var originX = buttonFrameOnScreen.midX - (frame.width / 2)
        originX = max(screenFrame.minX + margin, min(originX, screenFrame.maxX - frame.width - margin))

        var originY = buttonFrameOnScreen.minY - frame.height - spacing
        if originY < screenFrame.minY + margin {
            originY = buttonFrameOnScreen.maxY + spacing
        }
        if originY + frame.height > screenFrame.maxY - margin {
            originY = screenFrame.maxY - frame.height - margin
        }

        setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
