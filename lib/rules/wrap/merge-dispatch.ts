// Which way a PR is merged (lib/wrap/wrap-common.sh:_merge_pr, lines 112-152): the plain `gh pr merge` behind the
// retry, the project's `[merge] command`, or a refusal. A decision: one call, no state.
//
// The bash: with a repo dir, kit_merge_command <repo> answers 0 set / 1 unset / other unreadable; with only a slug,
// kit_merge_command_slug answers the same; with neither, refuse. rc 1 -> plain merge (WRAP_MERGE_PROJECT=0);
// rc 0 -> the project command, run once, unless there is no checkout (slug only) -> refuse; anything else -> refuse.
// WRAP_MERGE_PROJECT=1 on every path but the plain one, so a caller never tries a second way.
import {bool, fun, oneOf} from 'gdp-wired'

export const READS = ['set', 'unset', 'unreadable'] as const
export const ACTIONS = ['plain', 'project', 'refuse'] as const
export const Read = oneOf(...READS)

export type Variant = 'shipped' | 'fallback-on-unreadable' | 'slug-runs-project'
export const VARIANTS: Variant[] = ['fallback-on-unreadable', 'slug-runs-project']

export function mergeDispatch(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'merge-dispatch' : `merge-dispatch/${variant}`)
    .inputs({hasRepo: bool, hasSlug: bool, read: Read})
    .returns(({hasRepo, hasSlug, read}) => {
      const anywhere = hasRepo.or(hasSlug)
      const plain = variant === 'fallback-on-unreadable'
        ? anywhere.and(read.is('set').not())
        : anywhere.and(read.is('unset'))
      const project = variant === 'slug-runs-project'
        ? anywhere.and(read.is('set'))
        : hasRepo.and(read.is('set'))
      return {plain, project: plain.not().and(project), refuse: plain.not().and(project.not()), projectFlag: plain.not()}
    })
}

export function laws(f: ReturnType<typeof mergeDispatch>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('the plain squash runs only when no [merge] command is set', () => [],
        (out, {read}) => out.plain.implies(read.is('unset'))),
      f.law('a set [merge] command never falls back to the plain merge', ({read}) => [read.is('set')],
        (out) => out.plain.not()),
      f.law('an unreadable [merge] command refuses the merge', ({read}) => [read.is('unreadable')],
        (out) => out.refuse),
      f.law('a merge by slug with a set key refuses (no checkout to run it in)',
        ({hasRepo, read}) => [hasRepo.not(), read.is('set')], (out) => out.refuse),
      f.law('with no repo and no slug nothing merges', ({hasRepo, hasSlug}) => [hasRepo.not(), hasSlug.not()],
        (out) => out.refuse),
      f.law('WRAP_MERGE_PROJECT is 1 on every path but the plain merge', () => [],
        (out) => out.projectFlag.implies(out.plain.not()).and(out.plain.not().implies(out.projectFlag))),
    ],
  }
}
