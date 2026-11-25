// Bridge: run every advisory hook in hooks/ on hostile and ordinary input and hold each to "never exit 2". External
// tools a hook may start (osascript, notify-send, codebase-memory-mcp, formatters, claude) are stubs on PATH; the cwd
// is a temp git repo holding a recent source file that is sometimes unreadable, a spec, a debug ledger and a board.
import {chmodSync, utimesSync} from 'node:fs'
import {advisory, ADVISORY} from './advisory.ts'
import {gitRepo, rng, runHook, sandbox, stubs, Tally, write, join, type BridgeResult} from './_bridge.ts'

const EVENT: Record<string, string> = {'spec-drift-guard': 'PreToolUse', 'money-gate': 'PreToolUse', 'batch-debt-warn': 'PreToolUse',
  'output-offload': 'PostToolUse', 'context-budget': 'UserPromptSubmit', 'context-hints': 'UserPromptSubmit', 'prose-rag': 'UserPromptSubmit',
  'slop-cleaner': 'Stop', 'citation-guard': 'Stop', 'context-readiness': 'SessionStart', 'post-compact-reinject': 'SessionStart',
  'codebase-index': 'SessionStart', 'kit-update-notice': 'SessionStart', 'pre-compact-backup': 'PreCompact', 'auto-format': 'PostToolUse',
  'notification': 'Notification', 'permission-auto-approve': 'PermissionRequest', 'backlog-stage': 'SessionEnd', 'harvest': 'PreCompact', 'intake-sweep': 'SessionStart'}

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = advisory()
  const bin = stubs(Object.fromEntries(['osascript', 'notify-send', 'codebase-memory-mcp', 'prettier', 'npx', 'gofmt', 'ruff', 'black', 'rustfmt', 'claude', 'curl']
    .map((n) => [n, 'cat >/dev/null 2>&1; exit 0'])))
  const g = rng(59)
  for (let i = 0; i < 160; i++) {
    const hook = ADVISORY[i % ADVISORY.length]
    const feed = g.pick(['normal', 'empty', 'garbage', 'wrongTypes', 'unreadableFile'] as const)
    const dir = gitRepo({'CLAUDE.md': '## Project\nx\n', 'docs/specs/SPEC-001-a.md': '# a\nStatus: VALIDATED\n- [ ] t\n', '_meta/BACKLOG.md': '| ID-1 | t | queued |\n',
      '.claude/debug/b.md': '## Root cause\n\n', 'package.json': '{}'})
    const s = sandbox()
    const marker = join(s.home, 'marker')
    write(s.home, {marker: '', 't.jsonl': '{"type":"assistant","message":{"content":[{"type":"text","text":"see src/a.ts:99"}]}}\n'})
    utimesSync(marker, 1_000_000, 1_000_000)
    write(dir, {'src/a.ts': 'const a = 1\n'})
    if (feed === 'unreadableFile') chmodSync(join(dir, 'src/a.ts'), 0o000)
    const normal = {hook_event_name: EVENT[hook], session_id: 'adv', transcript_path: join(s.home, 't.jsonl'), cwd: dir, stop_hook_active: false,
      tool_name: 'Write', tool_input: {file_path: join(dir, 'src/a.ts'), content: 'amount', command: 'gh pr merge 1'}, tool_response: 'x'.repeat(9000), prompt: 'hi', type: 'idle_prompt'}
    const payload = feed === 'empty' ? '' : feed === 'garbage' ? '{not json' : feed === 'wrongTypes'
      ? {hook_event_name: 7, session_id: ['x'], transcript_path: {}, tool_input: 'str', stop_hook_active: 'yes', cwd: 3} : normal
    const env = {...s.env, PATH: `${bin}:${s.env.PATH}`, DWARVES_KIT_SESSION_MARKER: marker, MONEY_GATE_REPOS: dir.split('/').pop()!,
      OFFLOAD_MAX_TOKENS: '100', KIT_UPDATE_CHECK_URL: 'file:///nonexistent', HARVEST_EXTRACTOR: join(bin, 'claude'), HARVEST_SYNC: '1',
      BACKLOG_STAGE_EXTRACTOR: join(bin, 'claude'), BACKLOG_STAGE_SYNC: '1', PROSE_RAG_INJECT: '1'}
    const out = f.run({hook, feed, citationStrict: false})
    const r = runHook(`${hook}.sh`, payload, {env, cwd: dir, timeoutMs: 30000})
    t.check((r.code === 2) === out.block, () => ({hook, feed, rule: out, hook_exit: r.code, stderr: r.stderr.slice(0, 300)}))
    try { chmodSync(join(dir, 'src/a.ts'), 0o644) } catch {}
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
