// Bridge: hold hooks/codex-hook-adapter.sh to the codex-hook-adapter rule with Codex-shaped payloads for each
// supported pair and some unsupported ones, a PATH without jq, malformed input, and a policy dir missing the script.
import {spawnSync} from 'node:child_process'
import {codexAdapter} from './codex-hook-adapter.ts'
import {HOOKS, KIT, pathWithout, rng, sandbox, Tally, tmp, write, join, type BridgeResult} from './_bridge.ts'

const CASES: {event: string, policy: string, payload: Record<string, unknown>, supported: boolean, blocks: boolean}[] = [
  {event: 'PreToolUse', policy: 'safety-gate.sh', payload: {tool_name: 'Bash', tool_input: {command: 'rm -rf src'}}, supported: true, blocks: true},
  {event: 'PreToolUse', policy: 'safety-gate.sh', payload: {tool_name: 'Bash', tool_input: {command: 'ls'}}, supported: true, blocks: false},
  {event: 'PreToolUse', policy: 'secrets-guard.sh', payload: {tool_name: 'Bash', tool_input: {command: 'cat ~/.ssh/id_rsa'}}, supported: true, blocks: true},
  {event: 'PreToolUse', policy: 'secrets-guard.sh', payload: {tool_name: 'Bash', tool_input: {command: 'cd proj && less .env'}}, supported: true, blocks: true},
  {event: 'PreToolUse', policy: 'secrets-guard.sh', payload: {tool_name: 'Bash', tool_input: {command: 'ls src'}}, supported: true, blocks: false},
  {event: 'PreToolUse', policy: 'commit-format.sh', payload: {tool_name: 'Bash', tool_input: {command: 'git status'}}, supported: true, blocks: false},
  {event: 'Stop', policy: 'anti-rationalization.sh', payload: {stop_hook_active: false, last_assistant_message: 'All good.'}, supported: true, blocks: false},
  {event: 'PreToolUse', policy: 'money-gate.sh', payload: {tool_name: 'Bash', tool_input: {command: 'ls'}}, supported: false, blocks: false},
  {event: 'Stop', policy: 'slop-cleaner.sh', payload: {stop_hook_active: false}, supported: false, blocks: false},
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = codexAdapter()
  const noJq = pathWithout('jq')
  const emptyRoot = tmp('kit-noplug'); write(emptyRoot, {'hooks/.keep': ''})
  const g = rng(53)
  for (let i = 0; i < 60; i++) {
    const c = g.pick(CASES)
    const s = sandbox()
    const jq = g.next() < 0.85, valid = g.next() < 0.85, policy = g.next() < 0.85
    const env: Record<string, string> = {...s.env, PLUGIN_ROOT: policy ? KIT : emptyRoot}
    if (!jq) env.PATH = noJq
    const payload = valid ? {hook_event_name: c.event, ...c.payload} : {hook_event_name: c.event === 'Stop' ? 'PreToolUse' : 'Stop', junk: 1}
    const out = f.run({supported: c.supported, jq, valid, policy, policyBlocks: c.blocks})
    const r = spawnSync('bash', [join(HOOKS, 'codex-hook-adapter.sh'), c.event, c.policy], {input: JSON.stringify(payload), env, cwd: s.home, encoding: 'utf8'})
    t.check(r.status === (out.block ? 2 : 0), () => ({case: i, c, jq, valid, policy, rule: out, hook: {code: r.status, stderr: r.stderr}}))
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
