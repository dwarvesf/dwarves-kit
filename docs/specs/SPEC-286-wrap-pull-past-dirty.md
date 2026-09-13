# SPEC-286: `wrap apply` pulls a checkout past a sibling session's dirty tracked files

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Sibling:** `docs/verification/wrap-union-safe-pull.md` (the union-marked half of the same pull path, shipped 2026-09-11). **Source:** the draft at `.claude/goals/wrap-pull-past-dirty.md`. **Board:** ID-874.

## Problem

`wrap apply` ends its pass with `git pull --ff-only` on the default branch. Several sessions
share one checkout, so the pull meets tracked files nobody committed yet. Git refuses, prints
`Your local changes to the following files would be overwritten by merge`, and the checkout
stays behind. `wrap` reports `FAILED` and exits 2, which is honest and useless: the operator
asked for a landing and got a stale tree.

The union-marked half of this problem is already solved. A file the repo declares `merge=union`
is saved aside, the pull runs, and the local lines come back. That path covers append-only logs
and nothing else. One dirty `README.md` from another session still parks the whole pull, and the
operator's own manual fix is always the same three commands: stash the file, pull, pop.

Those three commands are what a script must not guess at. A bare `git stash` takes every dirty
and untracked file in a checkout this session does not own. A bare `git stash pop` takes
whatever entry sits on top of the stack, which on a shared checkout is another session's stash.

## Decision

Add `wrap.pull_past_dirty`, a root-only `[wrap]` knob defaulting to `false`. With it on,
`_pull_default` stashes exactly the tracked files that block the fast-forward under a stash
named for the run, pulls, and pops that stash by ref.

### What the knob authorizes, and what it never touches

| Surface | Under the knob |
|---|---|
| A dirty tracked file the incoming commits also change | stashed by pathspec, restored after the pull |
| A dirty tracked file the incoming commits do not touch | untouched, still dirty after the run |
| An untracked file | never stashed; an incoming commit adding the same path still aborts the pull |
| Any staged change, anywhere in the checkout | the whole knob path is skipped for that repo, because a pop cannot restore an index it did not stash |
| A pre-existing stash | never popped, never dropped, never read |
| A `merge=union` file caught in the same pull | stashed with the rest; the union driver resolves it during the pop |

Two more preconditions gate the path. It runs only when at least one dirty file is NOT
`merge=union`, because a pull blocked only by union-marked files is already the carry path's
job. It runs only when `_write_guard` finds no foreign `index.lock`, the same guard every other
write in `apply` passes through.

### Which files git would name

The blocking set is computed before the pull rather than parsed out of git's refusal, so the
run makes one pull attempt and never retries a failed git call. A path qualifies when it is a
regular file, dirty in the worktree, and changed between `HEAD` and the upstream tip with
rename detection off. That is the same per-entry up-to-date test git applies while reading the
two trees of a fast-forward, under one precondition the knob path enforces separately: the
index must be clean, because git's test compares the index to `HEAD` as well.

Four exclusions are deliberate, and each one degrades to the knob-off behaviour rather than to
damage:

| Excluded | Why | Result |
|---|---|---|
| A path the worktree deleted | git rewrites it instead of refusing | the pull lands, nothing is stashed |
| A dirty submodule gitlink | no stash can hold it | the pull behaves as it does with the knob off |
| A path marked `assume-unchanged` or `skip-worktree` | git still blocks on it, `git diff` does not report it | the knob no-ops, the pull reports `FAILED` |
| The upstream unresolvable, or `HEAD` not an ancestor of it | a pull that refuses for divergence refuses for a reason no stash clears | nothing is stashed |

Rename detection is turned off for the incoming diff. With it on, a commit that renames a file
the worktree has dirty prints only the new name, and the intersection would miss the very path
git blocks on. The pop then follows the rename itself and lands the local edit on the incoming
path.

The upstream can also advance between the blocking-set computation and `git pull`'s own fetch.
The set is then incomplete, the pull fails, and the stash pops straight back: a `FAILED` run
that changed nothing, which is the same answer the knob-off path gives.

### The window between the stash and the pop

A pull is a network call. An interrupt between the stash push and the pop leaves the blocking
files only inside the stash. The stash name prints before the pull for exactly that reason, and
`commands/wrap.md` step 5 names the recovery. `wrap` installs no signal trap: a trap that pops
a stash while the shell is unwinding is a second write on a checkout whose state nobody has
looked at yet.

### The pop, and what a conflict means

The stash is popped by IDENTITY, never by position or by name. `_stash_blocked` records the
commit `refs/stash` moved to, and only the entry whose `%H` equals that commit is popped. A
positional `stash@{N}` resolved a moment earlier is not safe on a shared checkout: any session
pushing or dropping an entry shifts every index. A name is not safe either, because a name is a
substring match against a list this run does not own. The same recorded commit is what makes a
push that saved nothing detectable: `refs/stash` did not move, so no stash is recorded, and the
pull runs exactly as it would with the knob off.

A pop conflict keeps the stash, leaves the markers in the file, reports
`PULLED, POP CONFLICT: <files>, stash <name> kept`, and exits 2. `wrap` does not know which side
of a file it did not write is the right one, so it stops and names the recovery material. A pop
that refuses with no conflicted path is reported as its own failure, not as a conflict, and a
pop after a failed pull drops the `PULLED` prefix.

## Wiring (one edit per surface)

| Surface | Edit |
|---|---|
| `lib/wrap/wrap.sh` | `_pull_past_dirty_on`, `_ff_blocked_into`, `_stash_blocked`, `_unstash`, the knob branch inside `_pull_default`, the reworded blocking-file NOTE, and the stash named in the header's write-set enumeration |
| `kit.toml` | `pull_past_dirty = false` in `[wrap]` |
| `lib/config/module-registry.md` | one registry row plus a line in the root-only key table |
| `commands/wrap.md` | step 5 bullet naming the knob, the two settings, and the `POP CONFLICT` line |
| `tests/test-wrap.sh` | seven real-git cases plus the three config-fence assertions |
| `_meta/BACKLOG.md` | ID-874 flipped to shipped |

## Non-goals

- No untracked-file handling. Git blocks an ff pull on an untracked path only when an incoming
  commit adds that same path, and overwriting a file nobody tracks is a judgment.
- No index restoration. A dirty index skips the whole path.
- No `--all`, no `-u`, no bare `git stash`, no bare `git stash pop`, at any setting.
- No second pull attempt, no forced pull, no reset.
- No new verb and no new flag. The knob is the whole surface.
- No separate union-conflict resolver. The union merge driver runs during the pop, so a
  union-marked file never reaches the conflict branch.

## After state

- `wrap.pull_past_dirty` resolves `false` from the shipped `kit.toml`, `true` from an operator
  `kit.toml`, and `false` from a project `.kit.toml` that sets it to `true`.
- With the knob off, `apply` prints the same lines it printed before this spec.
- With the knob on, a checkout blocked by one dirty tracked file lands the pull, keeps its local
  edit, keeps every other dirty and untracked file, and leaves the stash list as it found it.
- A pop conflict exits 2 with the stash still listed.
- `bash tests/test-wrap.sh` is green.

## Test plan

| Category | Case | Where |
|---|---|---|
| Default off | knob off: exit 2, `FAILED pull --ff-only`, HEAD unmoved, both dirty files byte-identical, untracked file present, only the sibling stash listed | `tests/test-wrap.sh` |
| Happy path | knob on: exit 0, HEAD at the incoming commit, the incoming line and the local line both in the file, the file still unstaged and dirty | same |
| Scope | knob on: exactly one file stashed when one of two dirty files is in the incoming commit | same |
| Scope | knob on: the other dirty file keeps its local edit and stays dirty | same |
| Scope | knob on: the untracked file is byte-identical after the run | same |
| Stash safety | knob on: the pre-existing `sibling` stash is the only entry left | same |
| Pop conflict | knob on, overlapping edit: exit 2, `PULLED, POP CONFLICT: A.md, stash <name> kept`, markers in the file, both stashes listed, the pull still landed | same |
| Union | knob on, a union-marked file blocked by the same pull: two files stashed, no conflict, both sides kept, no stash left behind | same |
| Untracked block | knob on, an incoming commit adds a path that exists untracked: exit 2, pull failed, the stash came back, HEAD unmoved, the untracked file keeps its local content | same |
| Dirty index | knob on, a staged path: the index reason prints, nothing stashed, the path still staged | same |
| Dry run | knob on, no `--apply`: nothing stashed, no stash created, the dirty file byte-identical, and the NOTE says `--apply would stash` | same |
| Rename | knob on, the incoming commit renames the dirty file: it is still stashed, the pull lands, and the local edit follows the rename onto the new path | same |
| Deleted in worktree | knob on, the dirty path is deleted locally: nothing stashed, the pull lands, git rewrites the file, the index carries no unmerged path | same |
| Diverged | knob on, a local commit the remote never saw: nothing stashed, no stash created, HEAD unmoved, exit 2 | same |
| Odd path | knob on, a dirty path holding a space and a bracket glob: exactly one file stashed, the local edit restored, the path the glob would have matched untouched | same |
| Config fence | ships `false`; an operator `kit.toml` sets it; a project `.kit.toml` cannot | same |
| Negative control | replace the pop-by-ref with a bare `git stash pop`, the sibling-stash assertions go red, restore | `docs/verification/wrap-pull-past-dirty.md` |

## Verification

- `bash tests/test-wrap.sh` exits 0.
- `bash tests/run-all.sh` fails no suite that does not already fail on `master`.
- `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<bare-pop mutation>'` reports PASS.
