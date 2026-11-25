// The pre-PR merge (lib/gate/premerge.sh:cmd_check), a gdp-wired decision over what git reports.
//
// Facts in the script's order: the path is a git work tree; HEAD is detached; a default branch resolves
// (wrap.sh default-branch); the current branch IS the default; `git fetch origin <default>` worked; origin/<default>
// is already an ancestor of HEAD; `git merge --no-edit origin/<default>` succeeded.
// Result: the exit code is 0 (`ok`) or 1, and whether a merge commit was made (`merged`).
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'conflict-swallowed' | 'merge-on-default'
export const VARIANTS: Variant[] = ['conflict-swallowed', 'merge-on-default']

export function premerge(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'premerge' : `premerge/${variant}`)
    .inputs({repo: bool, detached: bool, resolved: bool, onDefault: bool, fetchOk: bool, current: bool, mergeOk: bool})
    .returns(({repo, detached, resolved, onDefault, fetchOk, current, mergeOk}) => {
      const skipDefault = variant === 'merge-on-default' ? onDefault.and(onDefault.not()) : onDefault
      const tries = repo.and(detached.not()).and(resolved).and(skipDefault.not()).and(fetchOk).and(current.not())
      const conflict = variant === 'conflict-swallowed' ? tries.and(tries.not()) : tries.and(mergeOk.not())
      return {ok: repo.and(conflict.not()), merged: tries.and(mergeOk)}
    })
}

export function laws(f: ReturnType<typeof premerge>) {
  return [
    f.law('a real conflict exits non-zero and is left for the human',
      (e) => [e.repo, e.detached.not(), e.resolved, e.onDefault.not(), e.fetchOk, e.current.not(), e.mergeOk.not()], (o) => o.ok.not().and(o.merged.not())),
    f.law('a branch already current with the default branch is a silent no-op', (e) => [e.repo, e.current], (o) => o.ok.and(o.merged.not())),
    f.law('nothing is merged on the default branch itself', (e) => [e.onDefault], (o) => o.merged.not()),
    f.law('a failed fetch or an unresolved default fails open', (e) => [e.repo, e.fetchOk.not().or(e.resolved.not())], (o) => o.ok.and(o.merged.not())),
    f.law('a path outside git is an error', (e) => [e.repo.not()], (o) => o.ok.not()),
  ]
}
