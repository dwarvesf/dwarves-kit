// Bridge: hold hooks/anti-rationalization.sh to the anti-rationalization rule, stop loop included.
//
// Each case is a fixture (a git repo or a plain dir, an open or diagnosed .claude/debug ledger, an uncommitted diff
// that adds a stub, the understanding gate on or off through the operator overlay) and a run of Stop events. The
// payload names the message the way Claude Code does (last_assistant_message), the way the Codex adapter does
// (assistant_response), or not at all. After the hook exits 2 the next Stop carries stop_hook_active = true, as the
// host sends it; the rule's machine is stepped beside it and both decisions are compared at every Stop.
import {antiRationalization} from './anti-rationalization.ts'
import {gitRepo, machine, rng, runHook, sandbox, tmp, Tally, write, type BridgeResult} from './_bridge.ts'

const TEXT = {
  excuse: 'The rest can land in a follow-up PR.',
  guess: 'Let me just try bumping the timeout; that should fix it.',
  claim: 'All done, the parser is implemented.',
  neutral: 'I traced the bug to the cache key.',
}
type Facts = {field: string, excuse: boolean, gateOff: boolean, debugOpen: boolean, guess: boolean, claim: boolean, inGit: boolean, phantom: boolean, autonomy: string}

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(7)
  for (let i = 0; i < 64; i++) {
    const inGit = g.bool(), debug = g.pick(['none', 'open', 'diagnosed'] as const), phantom = inGit && g.bool(), gateOn = g.next() < 0.75
    const dir = inGit ? gitRepo({'src/a.py': 'def f():\n    return 1\n'}) : tmp('kit-plain')
    if (debug !== 'none') write(dir, {'.claude/debug/bug.md': `# Bug\n## Symptom\nslow\n## Root cause\n${debug === 'open' ? '\n' : 'the cache key drops the tenant\n'}## Fix\n`})
    if (phantom) write(dir, {'src/a.py': 'def f():\n    return 1\n\ndef g():\n    raise NotImplementedError\n'})
    const s = sandbox()
    if (gateOn) write(s.home, {'op/kit.toml': '[gate]\nunderstanding_gate = true\n'})
    const env = {...s.env, KIT_CONFIG_OPERATOR: `${s.home}/op`}
    const m = machine(antiRationalization())
    let active = false
    for (let k = 0; k < 3; k++) {
      const parts = (['excuse', 'guess', 'claim', 'neutral'] as const).filter(() => g.next() < 0.35)
      const text = parts.length ? parts.map((p) => TEXT[p]).join(' ') : TEXT.neutral
      const field = g.pick(['assistant_response', 'last_assistant_message', 'last_assistant_message', 'none'] as const)
      const payload: Record<string, unknown> = {hook_event_name: 'Stop', session_id: 's1', stop_hook_active: active}
      if (field !== 'none') payload[field] = text
      const facts: Facts = {field, excuse: parts.includes('excuse'), gateOff: !gateOn, debugOpen: debug === 'open',
        guess: parts.includes('guess'), claim: parts.includes('claim'), inGit, phantom, autonomy: g.pick(['propose', 'low', 'high', 'max'])}
      const want = m.step(facts).blocked ? 2 : 0
      const r = runHook('anti-rationalization.sh', payload, {env, cwd: dir})
      t.check(r.code === want, () => ({case: i, stop: k, payload, fixture: {inGit, debug, phantom, gateOn}, rule: want, hook: r.code, stdout: r.stdout.trim()}))
      active = r.code === 2
    }
  }
  // The refuted promise, against the real hook: with the gate on, the same excuse is refused once and then ends the
  // turn on the second Stop (stop_hook_active: true).
  {
    const dir = gitRepo({'a.txt': 'x'})
    const s = sandbox(); write(s.home, {'op/kit.toml': '[gate]\nunderstanding_gate = true\n'})
    const env = {...s.env, KIT_CONFIG_OPERATOR: `${s.home}/op`}
    const msg = {hook_event_name: 'Stop', session_id: 's', last_assistant_message: TEXT.excuse}
    const first = runHook('anti-rationalization.sh', {...msg, stop_hook_active: false}, {env, cwd: dir}).code
    const second = runHook('anti-rationalization.sh', {...msg, stop_hook_active: true}, {env, cwd: dir}).code
    const m = machine(antiRationalization())
    const facts = {field: 'last_assistant_message', excuse: true, gateOff: false, debugOpen: false, guess: false, claim: false, inGit: true, phantom: false, autonomy: 'max'}
    const want = [m.step(facts).blocked ? 2 : 0, m.step(facts).blocked ? 2 : 0]
    t.check(first === want[0] && second === want[1], () => ({case: 'excuse twice', rule: want, hook: [first, second]}))
    if (first === 2 && second === 0) t.note('confirmed: the same excuse is refused on the first Stop (exit 2) and ends the turn on the second (stop_hook_active, exit 0)')
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
