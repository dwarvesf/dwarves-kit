# goal

State and merge helpers around the `/goal` loop: goal drafts, the cross-session running-goal registry, dispatch attempt state, and the mega-goal merge guard. Each piece records or compares. None launches a session.

**Entry points**
- `bin/goal` forwards to `lib/goal/goal.sh`, which hands each verb to the script that owns it.
- `goal.sh draft <archive|list|dir>` (`goal-drafts.sh`): list design-time drafts in `.claude/goals/` and move drafts whose spec shipped into `done/`.
- `goal.sh registry <claim|list|log|status|release|dir>` (`goal-registry.sh`): the cross-session lock. `claim` refuses when a new goal's file globs overlap a running goal.
- `goal.sh merge <gate|merge|mark>` (`mega-merge.sh`): `gate` checks the lane gate, `merge` refuses on a failing gate and dry-runs unless given `--execute`, and `mark` holds a PR with a draft flag and label.
- `goal.sh stack-merge <next|chain>` (`stack-merge.sh`): squash-merge a stacked PR chain bottom-up.
- `goal.sh handoff` (`handoff-gen`, `handoff/handoff_gen.py`): the two-tier handoff document generator.
- `goal.sh wt <start|close> <slug>` (`wt.sh`): start or close one work unit in its own worktree.
- `attempt-state.sh dispatch|mark-disconnected|resume|lose-attempt|commit-result|abandon|status|list|release|dir`: the dispatch attempt state machine. It has no `goal.sh` verb.
- `megagoals.sh list [--repo DIR] [--limit N] [--all]`: list mega-goal folders that still have open sub-goals. It has no `goal.sh` verb.

**Tests**: `lib/goal/tests/test-megagoals.sh` and the root `tests/test-goal-dispatch.sh`, `tests/test-attempt-state.sh`, `tests/test-mega-merge.sh`. Run `bash tests/run-all.sh --only goal`.

**Spec and docs**: `docs/specs/SPEC-204-goal-sh-dispatch-behavior.md`, `docs/specs/SPEC-036-multi-session-concurrent-goals.md`, `docs/specs/SPEC-037-goal-draft-lifecycle.md`, `docs/specs/SPEC-100-mega-merge-guard.md`. The draft and registry stores are compared in `docs/reference/architecture.md`.
