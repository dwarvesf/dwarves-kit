// `board work` (lib/board/work.sh, the JOIN jq program) for one board row whose draft names a branch that has a
// worktree: what it derives, never stores.
//   - rung_of: the highest gate phase the run ledger shows `ran` (ship > review > build > validate > none), with
//     execute read as build and battery as review (src_ledger).
//   - the agent (agent_of): orca absent -> unknown (no-orca); an orca row `working` -> working; `inactive` with a
//     live terminal and a last-output time -> idle for now - last seconds; otherwise unknown (no-terminal).
//   - flags (rec): PARKED = the row is in progress (not `shipped`), the rung is not shipped, the agent is idle,
//     and idle at least --idle-min minutes; DONE-UNSEEN = the ledger holds a ship record; INDETERMINATE = a key is
//     missing (no-orca, no-terminal). The legend: "unknown = a key is missing, never idle or done".
import {bool, fun, nat, oneOf, when} from 'gdp-wired'
import {pick} from './util.ts'

export const RUNGS = ['shipped', 'reviewed', 'built', 'validated', 'none'] as const
export const LEADS = ['claimed', 'speccing', 'validated', 'executing', 'shipped'] as const
export const AGENTS = ['absent', 'working', 'idleLive', 'noLive'] as const
export type Variant = 'shipped' | 'parks-unknown' | 'rung-lowest-first' | 'parks-shipped-row'
export const VARIANTS: Variant[] = ['parks-unknown', 'rung-lowest-first', 'parks-shipped-row']

export function boardWork(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'board-work' : `board-work/${variant}`)
    .inputs({validate: bool, build: bool, review: bool, ship: bool, lead: oneOf(...LEADS), agent: oneOf(...AGENTS), age: nat, idleMin: nat})
    .returns(e => {
      const rung = variant === 'rung-lowest-first'
        ? when(e.validate, 3, when(e.build, 2, when(e.review, 1, when(e.ship, 0, 4))))
        : when(e.ship, 0, when(e.review, 1, when(e.build, 2, when(e.validate, 3, 4))))
      const inprog = variant === 'parks-shipped-row' ? e.lead.is('shipped').or(e.lead.is('shipped').not()) : e.lead.is('shipped').not()
      const idle = variant === 'parks-unknown' ? e.agent.is('working').not() : e.agent.is('idleLive')
      const parked = inprog.and(e.ship.not().or(variant === 'parks-shipped-row' ? e.ship : e.ship.not())).and(idle).and(e.age.atLeast(e.idleMin.times(60)))
      return {
        rung: pick(RUNGS, rung),
        parked,
        doneUnseen: e.ship,
        indeterminate: e.agent.is('absent').or(e.agent.is('noLive')),
        state: pick(['working', 'idle', 'unknown'] as const, when(e.agent.is('working'), 0, when(e.agent.is('idleLive'), 1, 2))),
      }
    })
}

export function laws(f: ReturnType<typeof boardWork>) {
  const rank = (r: any) => when(r.is('shipped'), 4, when(r.is('reviewed'), 3, when(r.is('built'), 2, when(r.is('validated'), 1, 0))))
  const same = (a: any, b: any) => a.implies(b).and(b.implies(a))
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('the rung is shipped exactly when the ledger holds a ship record', () => [],
        (o, e) => same(o.rung.is('shipped'), e.ship)),
      f.law('the rung is the highest phase the ledger shows ran', () => [],
        (o, e) => e.review.and(e.ship.not()).implies(o.rung.is('reviewed'))
          .and(e.build.and(e.review.not()).and(e.ship.not()).implies(o.rung.is('built')))
          .and(e.validate.or(e.build).or(e.review).or(e.ship).not().implies(o.rung.is('none')))),
      f.relate('another ran phase never lowers the rung',
        (a, b) => [a.validate.implies(b.validate), a.build.implies(b.build), a.review.implies(b.review), a.ship.implies(b.ship)],
        (x, y) => rank(x.rung).atMost(rank(y.rung))),
      f.law('a shipped row is never PARKED', (e) => e.lead.is('shipped'), (o) => o.parked.not()),
      f.law('a row the ledger shows shipped is never PARKED', (e) => e.ship, (o) => o.parked.not()),
      f.law('an agent whose state is unknown is never PARKED (unknown is never idle)', (e) => e.agent.is('absent').or(e.agent.is('noLive')),
        (o) => o.parked.not().and(o.state.is('unknown'))),
      f.law('PARKED needs the agent idle at least the threshold', () => [],
        (o, e) => o.parked.implies(e.agent.is('idleLive').and(e.age.atLeast(e.idleMin.times(60))))),
      f.law('an in-progress row whose agent sat idle past the threshold is PARKED',
        (e) => [e.lead.is('shipped').not(), e.ship.not(), e.agent.is('idleLive'), e.age.atLeast(e.idleMin.times(60))], (o) => o.parked),
      f.law('DONE-UNSEEN only with a ship record', () => [], (o, e) => o.doneUnseen.implies(e.ship)),
      f.law('a missing key always marks the row INDETERMINATE', (e) => e.agent.is('absent').or(e.agent.is('noLive')), (o) => o.indeterminate),
    ],
  }
}
