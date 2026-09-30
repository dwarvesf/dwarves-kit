# Decision Brief: wrap apply --pull-only

Date: 2026-09-30 · Source: SPEC-359 (operator ask, no board row). Status: RETROACTIVE. This `/kit:think` pass ran after the change was specced, validated, and built on `feat/wrap-pull-only`. The six forcing questions were answered from the spec and the build evidence, with no operator in the loop. One finding below changed the build (see "What this pass changed").

## Verdict: BUILD

## Core thesis: a shared main checkout needs a pull that touches nothing but the pull, so an operator stops hand-rolling a bare stash/pull/pop that grabs other sessions' files.

## Strongest argument for: the workaround already happened four times in one session, and it is the exact sequence `commands/wrap.md` forbids (a bare stash takes every dirty file, a bare pop takes whatever stash is on top).

## Strongest argument against: skipping the stray-commits carry silences the one signal that tells a session its default branch holds unpushed commits, so `--pull-only` can hide the rot the carry was built to surface.

## If BUILD: recommended scope for v1

- One flag on the existing `apply` verb. No new verb, no knob, no change to `_pull_default`.
- Gate the six write-capable sweeps off; keep fetch, default-branch resolution, and the pull section.
- Refuse the four flags that only widen or seed a sweep the flag turns off (`--worktrees`, `--archive-unmerged`, `--own`, `--tips-file`), exit 64.
- Keep the ahead-of-origin state visible: a read-only NOTE naming the ahead count and the recovery (plain `apply --apply`). Added by this pass.

## Forcing questions (retroactive answers)

| Q | Answer |
|---|---|
| Q1 real pain | Right after merging one PR in a shared checkout, the operator wants main current. Plain `apply --apply` would also sweep branches and worktrees other sessions still own. The workaround is a bare `git stash && pull && stash pop`. |
| Q2 10x version | `apply` itself knows which branches and worktrees belong to this session and sweeps only those. `--own` already does part of that for worktrees. Out of reach for this change. |
| Q3 simplest proof | One `if` around the six sweep calls, plus a conflict check. The existing `_pull_default` does the rest. |
| Q4 cut list | A new `wrap pull` verb. A `kit.toml` default. Gating the tip snapshot and `gh auth status` probe (read-only leftovers). |
| Q5 breaks at scale | `--under <root>` pulls every repo under the root, the same as plain `apply`. With many sessions on one checkout, a skipped stray-commits carry means ahead-of-origin commits go unreported run after run. |
| Q6 exit criteria | Zero hand-rolled stash/pull/pop in `wrap` sessions after merge. Measurable proxy: `tests/test-wrap.sh` green with every Test plan row covered, and a negative control that turns the scope rows red. |

## North-star alignment: N7 (serve the team: a shared checkout with several sessions stays safe to pull). No conflict found.

## Survival scenarios

| # | Scenario | Category |
|---|---|---|
| 1 | A session committed on the shared default branch and never pushed; later sessions run `--pull-only` after every merge, and origin never moves past the fork, so each pull reports "Already up to date" and nobody learns the commits exist. | guarantee inversion (the pull is all that matters) |
| 2 | The operator's muscle memory types `--pull-only --apply --worktrees`; the refusal exits 64 in the middle of a scripted wrap. | guarantee inversion (flags compose) |
| 3 | Origin is unreachable; `--pull-only` prints a fetch failure and the pull fails with exit 2, leaving the checkout behind with no delete to blame. | dependency failure |
| 4 | Two sessions run `--pull-only --apply` on the same checkout at once, each with a sibling's dirty file under `wrap.pull_past_dirty`. | concurrency |
| 5 | The checkout sits on a feature branch; `--pull-only` skips the pull and only fast-forwards the default ref by fetch. | wrong-state input |

## What this pass changed

Scenario 1 changed the build. The spec accepted "the local commits stay unreported". This pass rejects that: it keeps a read-only NOTE in the pull section when the default branch is ahead of origin under `--pull-only`. The NOTE prints the count and points at plain `apply --apply`. It writes nothing. The spec's Report shape and Test plan carry the change.

## Solution

Retroactive `/kit:design` pass, run after the build with no operator in the loop. Every `AskUserQuestion` step of the lane was answered from the spec and the brief above, so this section records the design the build already embodies plus the one change the think pass forced. The lane's interactive value did not apply here.

### Approaches considered

| # | Approach | Trade |
|---|---|---|
| A | `--pull-only` flag on `apply` (built) | Reuses the repo list, `--under`, the dry-run/`--apply` split and `_apply_repo`. Costs one global and one `if` block. |
| B | New `wrap pull <repo>` verb | Clean name, but duplicates arg parsing, `--under` expansion and the dry-run split for no new behavior. |
| C | Teach `--own` to also skip the branch and stray sweeps | No new flag, but overloads `--own` (which scopes worktree cleanup) with a second meaning and still runs the origin-branch sweep. |

### Chosen approach + why

A. The pull stage already lives inside `_apply_repo`; a flag gates its neighbours without touching `_pull_default`. The think finding adds one read-only line: under `--pull-only`, on the default branch with a good fetch, when `origin/<def>..HEAD` counts N > 0, the pull section prints `NOTE: <def> is N commits ahead of origin/<def>; --pull-only never carries them, plain apply --apply does` before `_pull_default` runs. It writes nothing and changes no exit code.

### Extensibility & boundaries

- The gate is one `if [ "$PULL_ONLY" != 1 ]` block; a future sweep added inside `_apply_repo` joins the block or stays outside it on purpose.
- The NOTE reuses the `rev-list --count origin/<def>..HEAD` read `_carry_stray_commits` and `scan` already use. It is skipped when the fetch failed, since `origin/<def>` may be stale then.
- Not design-bearing (no new component, no data model, one flag on an existing verb), so no `## Design` diagram or ADR.

### Survival scenarios (carried from think)

| # | Scenario | Disposition |
|---|---|---|
| 1 | Ahead-only commits go silent | Kept; now covered by the NOTE and a Test plan row |
| 2 | Muscle-memory flag combo exits 64 | Kept; the refusal names the flag |
| 3 | Origin unreachable | Kept; fetch-failure wording row |
| 4 | Two sessions pull at once under `pull_past_dirty` | Kept; unchanged `_pull_default` (SPEC-286 owns the run-named stash) |
| 5 | Checkout on a feature branch | Kept; off-default-branch row |
