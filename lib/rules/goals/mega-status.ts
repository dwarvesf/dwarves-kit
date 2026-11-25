// `mega status` drift classification of one ROADMAP sub-goal row (lib/mega/mega.sh: _classify L236-259, fed by
// _pr_state, _commit_count and _open_pr_for in cmd_status L307-336), as a gdp-wired decision.
// Inputs are what cmd_status gathers for the row:
//   box        the row's box (open, done, parked; lib/mega/box.tsv)
//   hasPr      the line cites `PR #N`;  prState: what `gh pr view N` says (none = unresolvable)
//   named      a branch name is known (the goal file's **Branch:** line, or an existing wave/sg-nn)
//   exists     that branch exists (local or origin);  baseOk: the base ref (--base, default master) exists
//   commits    `git rev-list --count base..branch` (read only when both exist; empty otherwise)
//   openPr     an OPEN PR has the branch as its head (looked up whenever a name is known)
import {bool, fun, nat, oneOf, when} from 'gdp-wired'

export const CLASSES = ['ok', 'claim-unverified', 'merged-unchecked', 'stalled', 'wip', 'pending', 'info'] as const
const C = (c: typeof CLASSES[number]) => CLASSES.indexOf(c)
export const Box = oneOf('open', 'done', 'parked')
export const PrState = oneOf('none', 'MERGED', 'OPEN', 'CLOSED')

export type Variant = 'shipped' | 'parked-flagged' | 'done-trusted'
export const VARIANTS: Variant[] = ['parked-flagged', 'done-trusted']

export function megaStatus(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'mega-status' : `mega-status/${variant}`)
    .inputs({box: Box, hasPr: bool, prState: PrState, named: bool, exists: bool, baseOk: bool, commits: nat, openPr: bool})
    .returns(({box, hasPr, prState, named, exists, baseOk, commits, openPr}) => {
      const hasOpen = named.and(openPr)
      const merged = hasPr.and(prState.is('MERGED'))
      const counted = named.and(exists).and(baseOk)        // _commit_count prints nothing otherwise
      const cls = when(box.is('done'), when(variant === 'done-trusted' ? box.is('done') : merged, C('ok'), C('claim-unverified')),
        when(box.is('parked'), variant === 'parked-flagged' ? C('stalled') : C('info'),
          when(merged, C('merged-unchecked'),
            when(counted.and(commits.eq(0)).and(hasOpen.not()), C('stalled'),
              when(counted.and(commits.atLeast(1)).or(hasOpen), C('wip'), C('pending'))))))
      return {cls, drift: when(cls.eq(C('claim-unverified')).or(cls.eq(C('merged-unchecked'))).or(cls.eq(C('stalled'))), 1, 0)}
    })
}

export type StatusFun = ReturnType<typeof megaStatus>

export function laws(f: StatusFun) {
  return [
    f.law('a checked box is OK only when its PR is verified MERGED', ({box}) => [box.is('done')],
      ({cls}, {hasPr, prState}) => cls.eq(C('ok')).iff(hasPr.and(prState.is('MERGED')))),
    f.law('a parked box is informational and never drift', ({box}) => [box.is('parked')], ({cls, drift}) => cls.eq(C('info')).and(drift.eq(0))),
    f.law('an unchecked box whose PR merged is flagged MERGED-UNCHECKED', ({box, hasPr, prState}) => [box.is('open'), hasPr, prState.is('MERGED')],
      ({cls}) => cls.eq(C('merged-unchecked'))),
    f.law('STALLED means the branch exists with no commits past base and no open PR', () => [],
      ({cls}, {named, exists, commits, openPr}) => cls.eq(C('stalled')).implies(named.and(exists).and(commits.eq(0)).and(named.and(openPr).not()))),
    f.law('a branch with commits past base, or an open PR, is never STALLED', ({named, exists, baseOk, commits, openPr}) =>
      [named, exists.and(baseOk).and(commits.atLeast(1)).or(openPr)], ({cls}) => cls.eq(C('stalled')).not()),
    f.law('only CLAIM-UNVERIFIED, MERGED-UNCHECKED and STALLED count as drift', () => [],
      ({cls, drift}) => drift.eq(1).iff(cls.eq(C('claim-unverified')).or(cls.eq(C('merged-unchecked'))).or(cls.eq(C('stalled'))))),
  ]
}

// The header's promise for PENDING ("[ ] and there is no branch, no PR at all"), which the code-faithful rule refutes
// twice (FINDINGS.md F6): a branch that exists is called PENDING when the base ref is missing (the commit count is
// empty), and a row citing an open or closed PR with no branch is PENDING too.
export function pendingLaws(f: StatusFun) {
  return [
    f.law('PENDING means no branch and no PR at all', () => [], ({cls}, {named, exists, hasPr}) => cls.eq(C('pending')).implies(named.and(exists).not().and(hasPr.not()))),
  ]
}
