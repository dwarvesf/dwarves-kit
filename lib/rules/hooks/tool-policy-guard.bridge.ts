// Bridge: hold hooks/tool-policy-guard.sh to the tool-policy-guard rule with generated v1 and v2 policy files, a
// missing file, and broken JSON; the first matching rule is computed here the way the policy reads.
import {toolPolicyGuard} from './tool-policy-guard.ts'
import {rng, runHook, sandbox, Tally, write, join, type BridgeResult} from './_bridge.ts'

const TOOLS = ['mcp__claude-in-chrome__navigate', 'mcp__computer_use__click', 'Bash', 'WebFetch', 'mcp__playwright__click', '']
const MATCHES = ['chrome', 'computer_use', 'playwright', 'Web', 'mcp__', 'zzz']

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = toolPolicyGuard()
  const g = rng(3)
  for (let i = 0; i < 90; i++) {
    const s = sandbox()
    const kind = g.pick(['missing', 'broken', 'v1', 'v2', 'v2'])
    const rules = Array.from({length: g.int(4)}, () => ({match: g.pick(MATCHES), action: g.pick(['allow', 'ask', 'deny'])}))
    const policy = kind === 'v1' ? {browser: {prefer: 'webfetch', rules}}
      : {capabilities: {_meta: {x: 1}, browser: {preferred: 'webfetch', rules: rules.slice(0, 1), providers: rules.slice(1).map((r) => ({...r, note: 'n'}))}}}
    const path = join(s.home, 'tool-policy.json')
    if (kind === 'broken') write(s.home, {'tool-policy.json': '{"browser": '})
    else if (kind !== 'missing') write(s.home, {'tool-policy.json': JSON.stringify(policy)})
    const tool = g.pick(TOOLS)
    const ordered = kind === 'v1' ? rules : rules // rules then providers keeps the same order
    const hit = ordered.find((r) => r.match && tool.includes(r.match))
    const first = tool && (kind === 'v1' || kind === 'v2') && hit ? hit.action : 'none'
    const out = f.run({file: kind !== 'missing', valid: kind !== 'broken' && !!tool, first})
    const r = runHook('tool-policy-guard.sh', {tool_name: tool, tool_input: {}}, {env: {...s.env, KIT_TOOL_POLICY: path}})
    const warned = r.stderr.includes('is policy-controlled')
    t.check(r.code === (out.block ? 2 : 0) && warned === out.warn, () => ({case: i, kind, rules, tool, rule: out, hook: {code: r.code, warned, stderr: r.stderr}}))
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
