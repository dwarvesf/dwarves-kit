// money-gate (hooks/money-gate.sh, PreToolUse Edit|Write|MultiEdit) as a gdp-wired decision. It always exits 0.
//
//   :27      MONEY_GATE_REPOS unset or empty                        -> inert (no log, no ask)
//   :42-53   stdin is not exactly one JSON object with a string path -> inert
//   :58-68   the path or cwd lies inside a named repo (/<name>/ or ending /<name>) -> else inert
//   :82-135  a money/auth term in the path or any string of tool_input -> else inert
//   :145-157 log one line (both modes)
//   :163-173 MONEY_GATE_STRICT truthy (1 true yes on, trimmed, any case) -> permissionDecision "ask"
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'asks-unarmed' | 'denies'
export const VARIANTS: Variant[] = ['asks-unarmed', 'denies']

export function moneyGate(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'money-gate' : `money-gate/${v}`)
    .inputs({repos: bool, payloadOk: bool, inRepo: bool, hits: bool, strict: bool})
    .returns(({repos, payloadOk, inRepo, hits, strict}) => {
      const fires = repos.and(payloadOk).and(inRepo).and(hits)
      const ask = fires.and(v === 'asks-unarmed' ? fires : strict)
      return {log: fires, ask, block: v === 'denies' ? ask : ask.and(ask.not())}
    })
}

export function laws(f: ReturnType<typeof moneyGate>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('the money gate never blocks an edit', () => [], (o) => o.block.not()),
      f.law('without MONEY_GATE_REPOS the gate is inert', (e) => [e.repos.not()], (o) => o.log.not().and(o.ask.not())),
      f.law('log-only mode never asks', (e) => [e.strict.not()], (o) => o.ask.not()),
      f.law('an ask needs a named repo and a money term', () => [], (o, e) => o.ask.implies(e.inRepo.and(e.hits).and(e.strict))),
      f.law('a money edit in a named repo asks once strict is armed', (e) => [e.repos, e.payloadOk, e.inRepo, e.hits, e.strict], (o) => o.ask),
      f.law('every ask is also logged', () => [], (o) => o.ask.implies(o.log)),
    ],
  }
}
export const make = moneyGate
