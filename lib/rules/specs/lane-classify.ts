// The risk-lane classifier, lib/classify/lane-classify.sh, as three decisions over the features its regexes find:
//   - classify / risk (lane-classify.sh:classify_core, main `risk`): first match wins:
//       1 backfill phrase: with any hard-gate subject the default lane plus a full suggestion, else `backfill`;
//       2 tiny phrase: `tiny` ("a typo about auth is still a typo");
//       3 --files with a hard path: `full` (the one route to full from classify);
//         the hard-gate flags (kit-machinery: a lib/ or hooks/ file with --files, else a mention) only SUGGEST;
//       4 doc-bootstrap phrase and no hard flag: `tiny`;
//       5 bug phrase: `bug`;
//       6 4+ soft flags: the default lane, suggestion = hard flags or the soft ones; 2-3: `normal`;
//       7 the default lane (kit.toml [lanes] default, never tiny).
//     `risk` prints full when the lane is full or a suggestion fired, else the lane.
//   - check <chosen> (lane_check): LANE-DOWNGRADE when the chosen lane's rank is below the classified lane's.
//   - escalate <current> <spec> (escalate): ESCALATE to the spec's lane when its rank is higher, else HOLD.
//   Ranks (lib/gate/lane-data.sh:lane_rank_of): tiny 1, normal/bug/backfill 2, full 3; unknown: LANE-UNKNOWN.
import {bool, fun, nat, oneOf, when} from 'gdp-wired'
import {pick} from './util.ts'

export const LANES = ['tiny', 'normal', 'full', 'bug', 'backfill'] as const
const Lane = oneOf(...LANES)
const rank = (l: any) => when(l.is('tiny'), 1, when(l.is('full'), 3, 2))

export type Variant = 'shipped' | 'words-pick-full' | 'hard-beats-tiny' | 'escalate-lowers'
export const VARIANTS: Variant[] = ['words-pick-full', 'hard-beats-tiny', 'escalate-lowers']

export function laneClassify(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'lane-classify' : `lane-classify/${variant}`)
    .inputs({
      backfill: bool, tiny: bool, hardText: bool, machText: bool, docBoot: bool, bug: bool, soft: nat,
      filesSet: bool, hardPath: bool, machFile: bool, def: oneOf('normal', 'full', 'bug', 'backfill'),
      chosen: oneOf(...LANES, 'unknown'), current: oneOf(...LANES, 'unknown'),
    })
    .assume(e => e.soft.atMost(5).and(e.filesSet.not().implies(e.hardPath.not().and(e.machFile.not()))))
    .returns(e => {
      const defIdx = when(e.def.is('normal'), 1, when(e.def.is('full'), 2, when(e.def.is('bug'), 3, 4)))
      const hb = e.hardText.or(e.machText)
      const hard = e.hardText.or(e.filesSet.and(e.machFile)).or(e.filesSet.not().and(e.machText))
      const hardPathFull = e.filesSet.and(e.hardPath)
      const wordsFull = variant === 'words-pick-full' ? hard : hard.and(hard.not())
      const tinyFirst = variant === 'hard-beats-tiny' ? e.tiny.and(hard.not()) : e.tiny
      // lane index into LANES, following the precedence above
      const lane = when(e.backfill, when(hb, defIdx, 4),
        when(tinyFirst, 0,
          when(hardPathFull.or(wordsFull), 2,
            when(e.docBoot.and(hard.not()), 0,
              when(e.bug, 3,
                when(e.soft.atLeast(4), defIdx,
                  when(e.soft.atLeast(2), 1, defIdx)))))))
      const later = e.backfill.not().and(tinyFirst.not()).and(hardPathFull.not()).and(e.docBoot.and(hard.not()).not())
      const suggest = e.backfill.and(hb).or(later.and(e.bug.and(hard).or(e.bug.not().and(e.soft.atLeast(4).or(hard)))))
      const L = pick(LANES, lane)
      const risk = pick(LANES, when(L.is('full').or(suggest), 2, lane))
      // check: chosen vs classified; escalate: current vs the spec's lane (the same classification)
      const chosenKnown = e.chosen.is('unknown').not()
      const downgrade = chosenKnown.and(rankOf(e.chosen).lt(rank(L)))
      const curKnown = e.current.is('unknown').not()
      const up = curKnown.and(variant === 'escalate-lowers' ? rankOf(e.current).eq(rank(L)).not() : rank(L).gt(rankOf(e.current)))
      const decision = pick(['ESCALATE', 'HOLD', 'UNKNOWN'] as const, when(curKnown.not(), 2, when(up, 0, 1)))
      return {lane: L, suggest, risk, downgrade, decision}
    })
}
const rankOf = (c: any) => when(c.is('tiny'), 1, when(c.is('full'), 3, 2))

export function laws(f: ReturnType<typeof laneClassify>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('words never pick full: the lane is full only from a hard path in --files or the configured default', () => [],
        (o, e) => o.lane.is('full').implies(e.filesSet.and(e.hardPath).or(e.def.is('full')))),
      f.law('a cosmetic task is tiny whatever its subject (a typo about auth is still a typo)', (e) => [e.tiny, e.backfill.not()],
        (o) => o.lane.is('tiny').and(o.risk.is('tiny'))),
      f.law('a backfill phrase with a hard-gate subject takes the default lane (not backfill) and a full risk',
        (e) => [e.backfill, e.hardText.or(e.machText)],
        (o, e) => (['normal', 'full', 'bug', 'backfill'] as const).map(d => e.def.is(d).implies(o.lane.is(d))).reduce((a, b) => a.and(b)).and(o.risk.is('full'))),
      f.law('a hard-gate subject on a non-cosmetic, non-backfill task always makes the risk full',
        (e) => [e.backfill.not(), e.tiny.not(), e.hardText], (o) => o.risk.is('full')),
      f.law('4 or more soft flags always make the risk full', (e) => [e.backfill.not(), e.tiny.not(), e.docBoot.not(), e.bug.not(), e.soft.atLeast(4)],
        (o) => o.risk.is('full')),
      f.law('the risk is never lighter than the lane', () => [], (o) => rank(o.risk).atLeast(rank(o.lane))),
      f.law('check warns only when the chosen lane is lighter than the classified one', () => [],
        (o, e) => o.downgrade.implies(e.chosen.is('unknown').not().and(rankOf(e.chosen).lt(rank(o.lane))))),
      f.law('check always warns when the chosen lane is lighter than the classified one', (e) => e.chosen.is('unknown').not(),
        (o, e) => rankOf(e.chosen).lt(rank(o.lane)).implies(o.downgrade)),
      f.law('escalate is up-only: it escalates only to a strictly heavier lane', () => [],
        (o, e) => o.decision.is('ESCALATE').implies(rank(o.lane).gt(rankOf(e.current)))),
      f.law('escalate never holds below a heavier spec lane', (e) => e.current.is('unknown').not(),
        (o, e) => rank(o.lane).gt(rankOf(e.current)).implies(o.decision.is('ESCALATE'))),
    ],
  }
}

// A reviewer law the faithful rule refutes, unfixed: the header documents "backfill > tiny > hard path in
// --files", so a cosmetic or backfill task whose --files hit a migration still classifies (and risks) light.
// The ship-time `floor` verb (and hooks/ship-gate) reads the diff, not the words, and still answers full there.
export function refuted(f: ReturnType<typeof laneClassify>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a hard path in --files always makes the risk full', (e) => [e.filesSet, e.hardPath], (o) => o.risk.is('full')),
    ],
  }
}
