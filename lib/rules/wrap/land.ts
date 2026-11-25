// `wrap land <worktree>`: one hand-made worktree from a committed branch to landed (lib/wrap/wrap-land.sh:_land_one
// 501-512 and _land_run 514-1093, its tail _land_tidy 1095-), as the order of its steps.
//
// One request is the outcome of the step the bash is on:
//   pre:        preflightFail (usage, dirty, detached, protected, no commits ahead, gh down, the ignored-file guard,
//               a draft refusal: exit 1/2/64) | already (the branch is proven landed: straight to the tidy)
//               | gatePass | gateBlock (_ship_gate_check before the push, exit 2)
//   pushing:    pushOk | pushFail                      (git push origin <branch>)
//   pr:         prOk | prFail                          (adopt or create the PR; with --draft the run ends here)
//   checks:     checksOk | checksFail                  (_land_pr_checks_gate, the ci label wait)
//   merging:    mergeOk | mergeFail | mergeProject (the project command refused: no other way is tried)
//               | mergeConflict (CONFLICTING at the pushed head: the merge cycle)
//   cycling:    cycleOk | cycleFail                    (_merge_verify_push, see merge-cycle.ts)
//   remerging:  mergeOk | mergeFail                    (the one second _merge_pr)
//   confirming: stateMerged | stateNot                 (gh pr view: MERGED?)
//   verifying:  treeOk | treeBad                       (_tree_verify; MISMATCH or UNVERIFIABLE exit 3)
//   tidying:    tidyOk | tidyFail                      (pull, remove the worktree, delete the branch)
import {bool, oneOf, rule, when} from 'gdp-wired'

export const EVENTS = ['preflightFail', 'already', 'gatePass', 'gateBlock', 'pushOk', 'pushFail', 'prOk', 'prFail',
  'checksOk', 'checksFail', 'mergeOk', 'mergeFail', 'mergeProject', 'mergeConflict', 'cycleOk', 'cycleFail',
  'stateMerged', 'stateNot', 'treeOk', 'treeBad', 'tidyOk', 'tidyFail'] as const
export const PHASES = ['pre', 'pushing', 'pr', 'checks', 'merging', 'cycling', 'remerging', 'confirming', 'verifying',
  'tidying', 'tidyingAlready', 'landed', 'alreadyLanded', 'draft', 'refused', 'mismatch'] as const

export type Variant = 'shipped' | 'push-before-gate' | 'draft-merges' | 'tidy-on-mismatch'
export const VARIANTS: Variant[] = ['push-before-gate', 'draft-merges', 'tidy-on-mismatch']

export function land(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'land' : `land/${variant}`)
    .params({draft: bool})
    .inputs({ev: oneOf(...EVENTS)})
    .state({phase: oneOf(...PHASES).from('pre'), gateOk: bool.from(false), pushed: bool.from(false),
      mergeDone: bool.from(false), confirmed: bool.from(false), treeOk: bool.from(false), wtRemoved: bool.from(false),
      already: bool.from(false)})
    .step(({draft, ev, phase, gateOk, pushed, mergeDone, confirmed, treeOk, wtRemoved, already}) => {
      const at = (p: typeof PHASES[number]) => phase.is(p)
      const e = (x: typeof EVENTS[number]) => ev.is(x)
      const gatePasses = variant === 'push-before-gate' ? at('pre').and(e('gatePass').or(e('gateBlock'))) : at('pre').and(e('gatePass'))
      const prDone = at('pr').and(e('prOk'))
      const toDraft = variant === 'draft-merges' ? prDone.and(prDone.not()) : prDone.and(draft)
      const merges = at('merging').or(at('remerging')).and(e('mergeOk'))
      const tidyOnBad = variant === 'tidy-on-mismatch' ? at('verifying').and(e('treeBad')) : at('verifying').and(at('pre'))
      const next = when(at('pre').and(e('preflightFail')), 'refused',
        when(at('pre').and(e('already')), 'tidyingAlready',
        when(gatePasses, 'pushing',
        when(at('pre').and(e('gateBlock')), 'refused',
        when(at('pushing').and(e('pushOk')), 'pr',
        when(at('pushing').and(e('pushFail')), 'refused',
        when(toDraft, 'draft',
        when(prDone, 'checks',
        when(at('pr').and(e('prFail')), 'refused',
        when(at('checks').and(e('checksOk')), 'merging',
        when(at('checks').and(e('checksFail')), 'refused',
        when(merges, 'confirming',
        when(at('merging').and(e('mergeConflict')), 'cycling',
        when(at('merging').or(at('remerging')).and(e('mergeFail').or(e('mergeProject'))), 'refused',
        when(at('cycling').and(e('cycleOk')), 'remerging',
        when(at('cycling').and(e('cycleFail')), 'refused',
        when(at('confirming').and(e('stateMerged')), 'verifying',
        when(at('confirming').and(e('stateNot')), 'refused',
        when(at('verifying').and(e('treeOk')).or(tidyOnBad), 'tidying',
        when(at('verifying').and(e('treeBad')), 'mismatch',
        when(at('tidying').and(e('tidyOk').or(e('tidyFail'))), 'landed',
        when(at('tidyingAlready').and(e('tidyOk').or(e('tidyFail'))), 'alreadyLanded',
          phase))))))))))))))))))))))
      const tidied = at('tidying').or(at('tidyingAlready')).and(e('tidyOk'))
      return {
        phase: next,
        gateOk: gateOk.or(gatePasses),
        pushed: pushed.or(at('pushing').and(e('pushOk'))),
        mergeDone: mergeDone.or(merges),
        confirmed: confirmed.or(at('confirming').and(e('stateMerged'))),
        treeOk: treeOk.or(at('verifying').and(e('treeOk'))),
        wtRemoved: wtRemoved.or(tidied),
        already: already.or(at('pre').and(e('already'))),
      }
    })
}

export function laws(r: ReturnType<typeof land>) {
  const before = (p: {is: (x: string) => any}) => p.is('pre')
  return {
    laws: [
      r.law('the branch is pushed only after the ship-gate passed it', ({pushed, gateOk}) => pushed.implies(gateOk)),
      r.law('a PR is merged only after the ship-gate passed and the push landed', ({mergeDone, gateOk, pushed}) => mergeDone.implies(gateOk.and(pushed))),
      r.law('a --draft land never merges', ({draft, mergeDone}) => draft.implies(mergeDone.not())),
      r.law('the worktree is removed only once the tree is verified, or the branch was already landed',
        ({wtRemoved, treeOk, already}) => wtRemoved.implies(treeOk.or(already))),
      r.law('a TREE MISMATCH keeps the worktree', ({phase, wtRemoved}) => phase.is('mismatch').implies(wtRemoved.not())),
      r.law('a refused land keeps the worktree', ({phase, wtRemoved}) => phase.is('refused').implies(wtRemoved.not())),
      r.law('a land reported merged had GitHub confirm MERGED and the tree verified',
        ({phase, confirmed, treeOk}) => phase.is('landed').implies(confirmed.and(treeOk))),
      // helpers
      r.law('nothing is pushed, merged or removed before the gate', ({phase, pushed, mergeDone, wtRemoved, gateOk}) =>
        before(phase).implies(pushed.not().and(mergeDone.not()).and(wtRemoved.not()).and(gateOk.not()))),
      r.law('the steps after the push are reached only with the branch pushed', ({phase, pushed}) =>
        phase.is('pr').or(phase.is('checks')).or(phase.is('merging')).or(phase.is('cycling')).or(phase.is('remerging'))
          .or(phase.is('confirming')).or(phase.is('verifying')).or(phase.is('tidying')).or(phase.is('landed')).or(phase.is('mismatch')).or(phase.is('draft'))
          .implies(pushed)),
      r.law('the push phase is reached only through the gate', ({phase, gateOk}) => phase.is('pushing').implies(gateOk)),
      r.law('nothing merges before the merge phase', ({phase, mergeDone}) =>
        phase.is('pre').or(phase.is('pushing')).or(phase.is('pr')).or(phase.is('checks')).or(phase.is('merging'))
          .or(phase.is('cycling')).or(phase.is('remerging')).or(phase.is('draft')).or(phase.is('tidyingAlready')).or(phase.is('alreadyLanded'))
          .implies(mergeDone.not())),
      r.law('the tree is checked only after GitHub confirmed the merge', ({phase, confirmed, treeOk}) =>
        phase.is('verifying').or(phase.is('tidying')).or(phase.is('mismatch')).implies(confirmed).and(treeOk.implies(confirmed))),
      r.law('the tidy after a merge runs only on a verified tree', ({phase, treeOk}) => phase.is('tidying').or(phase.is('landed')).implies(treeOk)),
      r.law('the worktree stays until a tidy', ({phase, wtRemoved}) => wtRemoved.implies(phase.is('landed').or(phase.is('alreadyLanded')))),
      r.law('the already-landed tidy follows only the already proof', ({phase, already}) => phase.is('tidyingAlready').or(phase.is('alreadyLanded')).implies(already)),
      r.law('an already-landed run stays on the already path', ({phase, already}) => already.implies(phase.is('tidyingAlready').or(phase.is('alreadyLanded')))),
      r.law('an already-landed run neither pushes nor merges', ({already, pushed, mergeDone}) => already.implies(pushed.not().and(mergeDone.not()))),
      r.law('a draft run ends at the draft', ({draft, phase}) => draft.implies(
        phase.is('checks').or(phase.is('merging')).or(phase.is('cycling')).or(phase.is('remerging')).or(phase.is('confirming'))
          .or(phase.is('verifying')).or(phase.is('tidying')).or(phase.is('landed')).or(phase.is('mismatch')).not())),
      r.law('the phases after the merge are reached only with the merge made', ({phase, mergeDone}) =>
        phase.is('confirming').or(phase.is('verifying')).or(phase.is('tidying')).or(phase.is('landed')).or(phase.is('mismatch')).implies(mergeDone)),
      r.law('a confirmed merge was made', ({confirmed, mergeDone}) => confirmed.implies(mergeDone)),
      r.law('a verified tree was confirmed', ({treeOk, confirmed}) => treeOk.implies(confirmed)),
    ],
    stepLaws: [
      r.stepLaw('a blocked ship-gate ends the land before any push', (_b, a) => a.phase.is('refused').and(a.pushed.not()),
        (b) => b.phase.is('pre').and(b.ev.is('gateBlock')).and(b.pushed.not())),
      r.stepLaw('a project merge command that refuses ends the land: no other way to merge is tried',
        (_b, a) => a.phase.is('refused').and(a.mergeDone.not()), (b) => b.phase.is('merging').and(b.ev.is('mergeProject')).and(b.mergeDone.not())),
    ],
  }
}

export const KIND: Record<string, string> = {landed: 'merged', alreadyLanded: 'already', draft: 'draft', refused: 'refused', mismatch: 'refused'}
