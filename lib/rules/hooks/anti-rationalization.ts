// anti-rationalization (hooks/anti-rationalization.sh, Stop) as a gdp-wired rule, with the host's stop loop around it.
//
// The hook (anti-rationalization.sh):
//   :19-20   stop_hook_active true            -> exit 0 (the loop guard)
//   :23-24   no response text                 -> exit 0
//   :29-38   gate-policy says understanding_gate is off (exit 1 only) -> exit 0
//   :48-68   an excuse phrase                 -> exit 2
//   :75-114  a .claude/debug ledger with an empty "## Root cause" AND a guess-fix phrase -> exit 2
//   :120-136 a completion claim, in a git work tree, and the diff adds a not-implemented stub -> exit 2
// The response text came from `.assistant_response` only. Claude Code's Stop payload carries the final message as
// `.last_assistant_message` (the Codex adapter maps that name onto assistant_response; Claude Code runs the hook
// directly), so under Claude Code the text was always empty and the hook never blocked. Fixed: the hook reads
// `.assistant_response // .last_assistant_message`; 'pre-fix' keeps the old read.
//
// The state is the host's: after a Stop hook blocks, Claude Code continues and sends the next Stop with
// stop_hook_active = true. That is why one rationalization can end a turn on the second try (see FINDINGS.md).
import {bool, fun, oneOf, rule, type Cond} from 'gdp-wired'
import {iff} from './_kit.ts'

// Which payload field carries the final message: the hook's own name, Claude Code's, or none.
export const Field = oneOf('assistant_response', 'last_assistant_message', 'none')
export const Autonomy = oneOf('propose', 'low', 'high', 'max')
const FACTS = {
  field: Field,
  excuse: bool,     // one of the five excuse phrases
  gateOff: bool,    // gate-policy enabled understanding_gate exits 1
  debugOpen: bool,  // some .claude/debug/*.md has an empty "## Root cause"
  guess: bool,      // a guess-fix phrase
  claim: bool,      // a completion claim
  inGit: bool,      // inside a git work tree
  phantom: bool,    // the uncommitted diff adds a not-implemented stub line
  autonomy: Autonomy,
}

export type Variant = 'shipped' | 'pre-fix' | 'no-loop-guard' | 'guess-anytime'
export const VARIANTS: Variant[] = ['pre-fix', 'no-loop-guard', 'guess-anytime']

type F = {[k in keyof typeof FACTS]: any}
function decision(v: Variant, e: F, continuing: Cond): Cond {
  const text: Cond = v === 'pre-fix' ? e.field.is('assistant_response') : e.field.is('none').not()
  const guessFix: Cond = v === 'guess-anytime' ? e.guess : e.debugOpen.and(e.guess)
  const fires = e.excuse.or(guessFix).or(e.claim.and(e.inGit).and(e.phantom))
  const guard: Cond = v === 'no-loop-guard' ? text.or(text.not()) : continuing.not()
  return guard.and(text).and(e.gateOff.not()).and(fires)
}

// The decision of one Stop, on its own (stop_hook_active is an input here).
export function antiRatDecision(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'anti-rationalization.decision' : `anti-rationalization.decision/${v}`)
    .inputs({...FACTS, active: bool})
    .returns((e) => ({block: decision(v, e as F, e.active)}))
}

// The stop loop: each request is one Stop event; `continuing` is the stop_hook_active the host will send.
export function antiRationalization(v: Variant = 'shipped') {
  return Object.assign(antiRatRule(v), {variant: v})
}
function antiRatRule(v: Variant) {
  return rule(v === 'shipped' ? 'anti-rationalization' : `anti-rationalization/${v}`)
    .inputs(FACTS)
    .state({continuing: bool.from(false), blocked: bool.from(false)})
    .flags((e) => ({fires: decision(v, e as F, e.continuing)}))
    .step(({fires}) => ({continuing: fires, blocked: fires}))
}

export function laws(r: ReturnType<typeof antiRationalization>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a stop that is already continuing is never blocked (the loop guard)',
        (b, a) => a.blocked.not(), (b) => b.continuing),
      r.stepLaw('an excuse phrase is refused on a fresh stop while the gate is on, whichever field carries the message',
        (b, a) => a.blocked, (b) => b.continuing.not().and(b.excuse).and(b.gateOff.not()).and(b.field.is('none').not())),
      r.stepLaw('the understanding gate off never blocks', (b, a) => a.blocked.not(), (b) => b.gateOff),
      r.stepLaw('a guess-fix is refused only during an open debug session',
        (b, a) => a.blocked.and(b.excuse.not()).and(b.claim.and(b.inGit).and(b.phantom).not()).implies(b.debugOpen.and(b.guess))),
      r.stepLaw('a completion claim over a diff that adds a stub is refused on a fresh stop while the gate is on',
        (b, a) => a.blocked, (b) => b.continuing.not().and(b.claim).and(b.inGit).and(b.phantom).and(b.gateOff.not()).and(b.field.is('none').not())),
      r.stepLaw('a stop with no message is never blocked', (b, a) => a.blocked.not(), (b) => b.field.is('none')),
      r.stepLaw('a block always hands the next stop stop_hook_active', (b, a) => iff(a.continuing, a.blocked)),
    ],
    decisions: [
      antiRatDecision(r.variant).relate(
        'the autonomy position never changes the decision',
        (a, b) => [a.field.eq(b.field), iff(a.excuse, b.excuse), iff(a.gateOff, b.gateOff), iff(a.debugOpen, b.debugOpen), iff(a.guess, b.guess),
          iff(a.claim, b.claim), iff(a.inGit, b.inGit), iff(a.phantom, b.phantom), iff(a.active, b.active)],
        (x, y) => iff(x.block, y.block)),
    ],
    // Promised by docs/guides/gates-and-proof.md ("these four are never waived") and autonomy.md ("stops at the four
    // hard stops at every position"), refuted by the code-faithful rule: the loop guard lets the same excuse end the
    // turn on the second Stop. Kept as a finding, not fixed: dropping the guard loops the session forever.
    refutedSteps: [
      r.stepLaw('an excuse phrase never ends a turn while the gate is on (the hard stop is never waived)',
        (b, a) => a.blocked, (b) => b.excuse.and(b.gateOff.not()).and(b.field.is('none').not())),
    ],
  }
}
export const make = antiRationalization
