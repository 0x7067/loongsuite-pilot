import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { JcodeLogInput } from '../../../src/inputs/jcode-log/jcode-log-input.js';
import { ClientType, type AgentActivityEntry } from '../../../src/types/index.js';
import { MockStateStore } from '../../helpers/mock-state-store.js';

describe('JcodeLogInput', () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'jcode-input-'));
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it('emits bridge-written jcode records as jcode activity with usage and workspace', async () => {
    const today = new Date();
    const date = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    await fs.writeFile(path.join(tmpDir, `jcode-${date}.jsonl`), `${JSON.stringify({
      time_unix_nano: '1791257727522000000',
      'event.id': 'jcode-event-1',
      'event.name': 'llm.response',
      'gen_ai.agent.type': 'jcode',
      'gen_ai.session.id': 'session_lobster_1',
      'gen_ai.request.model': 'gpt-6.1-sol',
      'gen_ai.usage.input_tokens': 1200,
      'gen_ai.usage.output_tokens': 34,
      'agent.jcode.cwd': tmpDir,
    })}\n`);

    const input = new JcodeLogInput({
      stateStore: new MockStateStore() as never,
      logDir: tmpDir,
      pollIntervalMs: 60_000,
    });
    const entries: AgentActivityEntry[] = [];
    input.on('entries', batch => entries.push(...batch));

    await input.start();
    await input.stop();

    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      'event.id': 'jcode-event-1',
      'gen_ai.agent.type': ClientType.Jcode,
      'gen_ai.session.id': 'session_lobster_1',
      'gen_ai.usage.input_tokens': 1200,
      'gen_ai.usage.output_tokens': 34,
      'workspace.path': tmpDir,
    });
  });
});
