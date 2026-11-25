// Which lane a run owes: the `start` / `start --amend` writers (lib/gate/gate-ledger.sh:start, :227) and the one
// reader (lib/gate/lane-data.sh:lane_effective), as a gdp-wired rule.
//
// Requests are ledger writes through the sanctioned verbs:
//   start <rid> <lane> ...                       a plain START (refused, exit 64, for an undeclared lane)
//   start --amend [--lower --reason R] <rid> <lane> ...
//                                                a START-AMEND; refused (64) for a lane outside the five kit lanes or a
//                                                --lower without a reason; refused (65) when it lowers the ledger lane
//                                                without --lower; a lowering with --lower first appends
//                                                `GATE | lane-lower | override | <from> -> <to>: <reason> | via=lane-lower`
//   override <rid> lane-lower "<from> -> <to>: <text>"
//                                                the hand override verb naming the lane-lower phase (via=hand)
// The state is what lane_effective's awk keeps while it reads the file: the last valid amend lane `a`, the first
// START lane `first`, the pending lane-lower target `pend`, and `low` (the last amend was preceded by a lane-lower
// row naming its own lane). `sanct` is a ghost: the last amend was written by `start --amend --lower` with a real
// lowering. The spec `Lane:` header is a param. checkLane() is lane_effective's 4th column, what ship-gate checks.
import {bool, fun, oneOf, rule, when} from 'gdp-wired'

export const LANES = ['none', 'tiny', 'normal', 'bug', 'backfill', 'full', 'other'] as const
export const Lane = oneOf(...LANES)
export const OPS = ['start', 'amend', 'override_ll'] as const
export const Op = oneOf(...OPS)

// shipped = the code after the fix (lane-data.sh reads only a via=lane-lower row, and the target right after the
// first ' -> '); the two kept variants are the code before it.
export type Variant = 'shipped' | 'override-forges' | 'arrow-reason' | 'amend-unguarded'
export const VARIANTS: Variant[] = ['override-forges', 'arrow-reason', 'amend-unguarded']

// lane_rank_of: tiny 1, normal = bug = backfill 2, full 3; anything else has no rank (0 here).
export const rank = (l: any) => when(l.is('tiny'), 1, when(l.is('full'), 3, when(l.is('normal').or(l.is('bug')).or(l.is('backfill')), 2, 0)))

export function laneEffective(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'lane-effective' : `lane-effective/${variant}`)
    .params({hdr: Lane})
    // lane: the lane named; lower/reason: the --lower flag and a non-blank --reason; arrow: the reason holds ' -> '
    .inputs({op: Op, lane: Lane, lower: bool, reason: bool, arrow: bool})
    .state({a: Lane.from('none'), first: Lane.from('none'), pend: Lane.from('none'), low: bool.from(false), sanct: bool.from(false),
      ok: bool.from(false)})   // ok: the verb accepted the last request (exit 0)
    .flags(({op, lane, lower, reason, a, first}) => {
      const prev = when(a.is('none').not(), a, first)   // _effective_lane: last amend, else first START
      const lowers = rank(prev).gt(0).and(rank(lane).gt(0)).and(rank(lane).lt(rank(prev)))
      const five = lane.is('none').not().and(lane.is('other').not())
      return {
        startOk: op.is('start').and(five),
        amendOk: op.is('amend').and(five).and(lower.and(reason.not()).not())
          .and(variant === 'amend-unguarded' ? lowers.or(lowers.not()) : lowers.not().or(lower)),
        lowLine: op.is('amend').and(five).and(lowers).and(lower).and(reason),
      }
    })
    .step(({op, lane, arrow, a, first, pend, low, sanct, startOk, amendOk, lowLine}) => {
      // The lane-lower row the amend writes names its own lane; before the fix an arrow in the reason moved the
      // parsed target (awk took the LAST ' -> ' piece).
      const ownTarget = variant === 'arrow-reason' ? when(arrow, 'other', lane) : lane
      // A hand override row: before the fix it set the pending target like the amend's own row.
      const handRow = op.is('override_ll').and(lane.is('none').not())
      const pendNow = when(amendOk.and(lowLine), ownTarget,
        variant === 'override-forges' ? when(handRow, lane, pend) : pend)
      return {
        a: when(amendOk, lane, a),
        first: when(startOk.and(first.is('none')), lane, first),
        pend: when(amendOk, 'none', pendNow),
        low: when(amendOk, pendNow.eq(lane), low),
        sanct: when(amendOk, lowLine, sanct),
        ok: startOk.or(amendOk).or(op.is('override_ll')),
      }
    })
}

export type LaneRule = ReturnType<typeof laneEffective>

// lane_effective's columns from the reader state and the header.
export function columns(env: {hdr: any, a: any, first: any, low: any}) {
  const {hdr, a, first, low} = env
  const fromAmend = a.is('none').not()
  const fromStart = fromAmend.not().and(first.is('none').not())
  const lane = when(fromAmend, a, when(fromStart, first, hdr))
  const rh = rank(hdr), rl = rank(lane)
  const compares = hdr.is('none').not().and(fromAmend.and(low).not()).and(fromAmend.or(fromStart))
  const takeHdr = compares.and(rh.eq(0).and(fromStart).or(rh.gt(0).and(rl.eq(0).or(rh.gt(rl)).or(rh.eq(rl).and(fromStart)))))
  return {lane, fromAmend, fromStart, chk: when(takeHdr, hdr, lane)}
}

// The reader's columns as a pure function, so a bridge reads them from the rule's own terms.
export const laneColumns = fun('lane-columns').inputs({hdr: Lane, a: Lane, first: Lane, low: bool})
  .returns((env) => { const c = columns(env); return {lane: c.lane, chk: c.chk, fromAmend: c.fromAmend, fromStart: c.fromStart} })

export function laws(r: LaneRule) {
  return {
    laws: [
      r.law('the check lane is never lighter than a ranked spec header unless the last amend was a sanctioned --lower',
        (env) => {
          const {chk, fromAmend} = columns(env)
          return rank(env.hdr).gt(0).implies(rank(chk).atLeast(rank(env.hdr)).or(fromAmend.and(env.sanct)))
        }),
      r.law('an amend written through start --amend --lower --reason is the check lane',
        (env) => { const {chk, fromAmend} = columns(env); return fromAmend.and(env.sanct).implies(chk.eq(env.a)) }),
      r.law('a sanctioned lowering is the only way the reader marks an amend lowered',
        ({low, sanct, a}) => a.is('none').not().implies(low.implies(sanct).and(sanct.implies(low)))),
      r.law('the pending lane-lower target is never left set by a verb', ({pend}) => pend.is('none')),
      r.law('a sanctioned lowering always lands on a ranked lane', ({sanct, a}) => sanct.implies(rank(a).gt(0))),
    ],
    stepLaws: [
      r.stepLaw('an amend that lowers the ledger lane is refused unless written with --lower and a reason',
        (b, a) => {
          const prev = when(b.a.is('none').not(), b.a, b.first)
          return a.a.eq(b.lane).implies(rank(b.lane).atLeast(rank(prev)).or(rank(prev).eq(0)).or(rank(b.lane).eq(0))
            .or(b.lower.and(b.reason)))
        }, (b) => b.op.is('amend')),
      r.stepLaw('a plain START never changes the lane of a run that already has one',
        (b, a) => a.first.eq(b.first).and(a.a.eq(b.a)), (b) => b.op.is('start').and(b.first.is('none').not())),
      r.stepLaw('the override verb never changes the run\'s lane', (b, a) => a.a.eq(b.a).and(a.first.eq(b.first)).and(a.low.implies(b.low)).and(b.low.implies(a.low)),
        (b) => b.op.is('override_ll')),
      r.stepLaw('a lane outside the five kit lanes is never written', (b, a) => a.a.eq(b.a).and(a.first.eq(b.first)),
        (b) => b.lane.is('other').or(b.lane.is('none'))),
    ],
  }
}
