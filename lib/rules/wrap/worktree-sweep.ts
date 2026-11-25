// Whether `wrap apply` removes one worktree (lib/wrap/wrap-apply.sh:_apply_worktrees 124-227, with run() and
// _write_guard from wrap-common.sh 290-331). The guards, in the order the bash checks them:
//   scope      --own names it, or --worktrees was given                 (else SKIP: --worktrees not given)
//   dirty      `git status --short` non-empty                           (SKIP dirty)
//   detached   no current branch                                        (SKIP detached HEAD)
//   protected  the branch is the default, main or master                (SKIP protected)
//   current    the branch is the main checkout's own                     (SKIP)
//   fetchOk    the repo's fetch succeeded                               (SKIP stale merge proof)
//   merged     branch_merged says SAFE                                  (SKIP not proven merged)
//   dirtyAfter dirty again after the proof was read                     (SKIP went dirty)
//   tipMoved   the tip moved since the run's snapshot                   (SKIP tip moved)
//   lockLive   a lock naming a pid that is alive                        (SKIP locked by live pid)
//   busy       a live process outside this run holds the path (lsof)    (SKIP busy)
//   apply      --apply given                                            (else WOULD remove: the dry run)
//   indexFree  no foreign index.lock (_write_guard)                     (SKIP index.lock held)
// then `git worktree remove -f -f`, and `git branch -D` only when the path and the list entry are both gone.
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'dirty-not-rechecked' | 'dry-run-writes' | 'lock-ignored'
export const VARIANTS: Variant[] = ['dirty-not-rechecked', 'dry-run-writes', 'lock-ignored']

export function worktreeSweep(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'worktree-sweep' : `worktree-sweep/${variant}`)
    .inputs({scope: bool, dirty: bool, detached: bool, protected: bool, current: bool, fetchOk: bool, merged: bool,
      dirtyAfter: bool, tipMoved: bool, lockLive: bool, busy: bool, apply: bool, indexFree: bool, cleared: bool})
    .returns(({scope, dirty, detached, protected: prot, current, fetchOk, merged, dirtyAfter, tipMoved, lockLive, busy, apply, indexFree, cleared}) => {
      const guards = scope.and(dirty.not()).and(detached.not()).and(prot.not()).and(current.not()).and(fetchOk).and(merged)
        .and(variant === 'dirty-not-rechecked' ? dirtyAfter.or(dirtyAfter.not()) : dirtyAfter.not()).and(tipMoved.not())
        .and(variant === 'lock-ignored' ? lockLive.or(lockLive.not()) : lockLive.not()).and(busy.not())
      const would = guards.and(apply.not())
      const remove = guards.and(variant === 'dry-run-writes' ? apply.or(apply.not()) : apply).and(indexFree)
      return {would, remove, deleteBranch: remove.and(cleared)}
    })
}

export function laws(f: ReturnType<typeof worktreeSweep>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a dirty worktree is never removed', () => [], (o, {dirty, dirtyAfter}) => o.remove.implies(dirty.not().and(dirtyAfter.not()))),
      f.law('a worktree is removed only when the operator asked for worktree cleanup', () => [], (o, {scope}) => o.remove.implies(scope)),
      f.law('a worktree is removed only when its branch is proven merged on a fresh fetch', () => [],
        (o, {merged, fetchOk}) => o.remove.implies(merged.and(fetchOk))),
      f.law('a worktree an agent still holds (live lock or busy) is never removed', () => [],
        (o, {lockLive, busy}) => o.remove.implies(lockLive.not().and(busy.not()))),
      f.law('the dry run never removes anything', ({apply}) => [apply.not()], (o) => o.remove.not()),
      f.law('a detached, protected or current-branch worktree is never removed', () => [],
        (o, {detached, protected: prot, current}) => o.remove.implies(detached.not().and(prot.not()).and(current.not()))),
      f.law('the branch is deleted only after its worktree is gone', () => [], (o, {cleared}) => o.deleteBranch.implies(o.remove.and(cleared))),
      f.law('no write while another writer holds the index', () => [], (o, {indexFree}) => o.remove.implies(indexFree)),
    ],
  }
}
