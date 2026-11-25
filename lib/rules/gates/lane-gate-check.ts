// The lane gate's run ledger (lib/gate/gate-ledger.sh), as a gdp-wired rule.
//
// One request is one call of a ledger verb on one run id: `record <rid> <phase> ran|skipped|rejected [reason]`
// (gate-ledger.sh:record, :300), `override <rid> <phase> <reason>` (:_override_via, :591), or an additive marker
// verb (`action`, `tokens`, `debt`, `outcome`, `mutation`; :332, :368, :408, :510, :1233) that writes a non-GATE line.
// The state is what the readers derive from the append-only file:
//   Last[p]   the state of phase p's LATEST `| GATE |` row (check(), :684, awk `$2=="GATE" && $3==p {s=$4}`)
//   Disp[p]   whether progress() counts p disposed (:1127: ANY GATE row for p that is not a bare skip)
//   Owner[r]  which phase (1 + index) an override reason r was used on (the blanket-override guard, :604-613);
//             0 = the reason was never used on an override.
// A `skipped` row with an empty reason is a BARE skip (progress keeps it a gap).
// `check <lane> <rid>` passes iff every required phase has Last in {ran, override} (satisfied()).
import {forall, nat, oneOf, rule, when} from 'gdp-wired'

export const OPS = ['ran', 'skip', 'rejected', 'override', 'marker'] as const
export const STATES = ['none', 'ran', 'skipped', 'bare', 'rejected', 'override'] as const
export const Op = oneOf(...OPS)
export const St = oneOf(...STATES)

export type Variant = 'shipped' | 'any-row' | 'marker-counts' | 'no-reason-guard' | 'progress-latest'
export const VARIANTS: Variant[] = ['any-row', 'marker-counts', 'no-reason-guard', 'progress-latest']

export function laneGateCheck(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'lane-gate-check' : `lane-gate-check/${variant}`)
    // op: the verb; p: the phase (index into the lane's phases); r: the reason (1.. = distinct texts, 0 = empty)
    .inputs({op: Op, p: nat, r: nat})
    .maps({Last: St.from('none'), Disp: 0, Owner: 0})
    .flags(({op, p, r, Owner}) => ({
      // _override_via: refused (exit 65) when the reason already overrode a DIFFERENT phase; an empty reason is
      // refused (exit 64) before the guard.
      ovOk: op.is('override').and(r.gt(0)).and(
        variant === 'no-reason-guard' ? r.eq(r) : Owner.at(r).eq(0).or(Owner.at(r).eq(p.plus(1)))),
    }))
    .step(({op, p, r, Last, Disp, Owner, ovOk}) => {
      const cur = Last.at(p)
      // The bug the additive rule forbids: a marker whose text reads like a ran row counts for phase p.
      const forged = variant === 'marker-counts' ? op.is('marker') : op.is('marker').and(op.is('ran'))
      // Did the call append a GATE row for phase p? (record always does; override only when the guard allows.)
      const written = op.is('ran').or(op.is('skip')).or(op.is('rejected')).or(ovOk).or(forged)
      // check() reads the latest row; the any-row variant reads "some ran/override row ever" (a later fail row
      // would not undo it).
      const wasSat = cur.is('ran').or(cur.is('override'))
      const failRow = op.is('skip').or(op.is('rejected'))
      const keep = variant === 'any-row' ? wasSat.and(failRow) : wasSat.and(wasSat.not())
      const next = when(keep, cur,
        when(op.is('ran').or(forged), 'ran',
          when(op.is('skip').and(r.gt(0)), 'skipped',
            when(op.is('skip'), 'bare',
              when(op.is('rejected'), 'rejected',
                when(ovOk, 'override', cur))))))
      // progress(): disposed once ANY row for p is not a bare skip; the progress-latest variant reads the latest row.
      const dispNow = written.and(op.is('skip').and(r.eq(0)).not())
      const disp = variant === 'progress-latest'
        ? when(written, when(dispNow, 1, 0), Disp.at(p))
        : when(dispNow, 1, Disp.at(p))
      return {
        Last: Last.set(p, next),
        Disp: Disp.set(p, disp),
        Owner: Owner.set(r, when(ovOk.and(Owner.at(r).eq(0)), p.plus(1), Owner.at(r))),
      }
    })
}

export type LaneGateRule = ReturnType<typeof laneGateCheck>
export const satisfied = (s: {is: (v: string) => any}) => s.is('ran').or(s.is('override'))

export function laws(r: LaneGateRule) {
  return {
    laws: [
      r.law('a phase check() counts as satisfied is always shown disposed by progress',
        ({Last, Disp}) => forall(k => Last.at(k).is('ran').or(Last.at(k).is('override')).implies(Disp.at(k).eq(1)))),
      r.law('a rejected or skipped-with-reason phase is shown disposed by progress yet never satisfies check()',
        ({Last, Disp}) => forall(k => Last.at(k).is('rejected').or(Last.at(k).is('skipped')).implies(Disp.at(k).eq(1)))),
    ],
    stepLaws: [
      r.stepLaw('an additive marker (ACTION, TOKENS, DEBT, OUTCOME, MUTATION) never changes any gate state',
        (b, a) => forall(k => a.Last.at(k).eq(b.Last.at(k))), (b) => b.op.is('marker')),
      r.stepLaw('a later skipped or rejected row undoes an earlier ran',
        (b, a) => a.Last.at(b.p).is('ran').not().and(a.Last.at(b.p).is('override').not()),
        (b) => b.op.is('skip').or(b.op.is('rejected'))),
      r.stepLaw('a later ran clears a rejection', (b, a) => a.Last.at(b.p).is('ran'),
        (b) => b.op.is('ran')),
      r.stepLaw('a phase becomes satisfied only by a ran or an override row for that phase',
        (b, a) => forall(k => a.Last.at(k).is('ran').or(a.Last.at(k).is('override'))
          .implies(b.Last.at(k).is('ran').or(b.Last.at(k).is('override'))
            .or(k.eq(b.p).and(b.op.is('ran').or(b.op.is('override'))))))),
      r.stepLaw('a call on one phase never changes another phase',
        (b, a) => forall(k => k.eq(b.p).not().implies(a.Last.at(k).eq(b.Last.at(k))))),
      r.stepLaw('an override reason already used on a different phase is refused',
        (b, a) => a.Last.at(b.p).eq(b.Last.at(b.p)),
        (b) => b.op.is('override').and(b.Owner.at(b.r).gt(0)).and(b.Owner.at(b.r).eq(b.p.plus(1)).not())),
      r.stepLaw('an override needs a reason', (b, a) => a.Last.at(b.p).eq(b.Last.at(b.p)),
        (b) => b.op.is('override').and(b.r.eq(0))),
      r.stepLaw('progress never un-disposes a phase', (b, a) => forall(k => b.Disp.at(k).eq(1).implies(a.Disp.at(k).eq(1)))),
    ],
  }
}
