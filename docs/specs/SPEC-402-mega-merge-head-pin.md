# Spec: pin the mega-goal auto-merge to the head its guards read
Generated: 2026-10-09
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a push between the guards and the merge lands a commit no guard read, such as a .kit.toml edit)
References: `lib/goal/mega-merge.sh:142-146` (`_pr_info`, imitate its overridable `gh pr view --json` read and its fail-closed nonzero return); `lib/goal/mega-merge.sh:202-214` (`_pr_files`, imitate the `MEGA_MERGE_PR_*_CMD` test override); `gh pr merge --match-head-commit` (use as is).

## Problem

`mega-merge.sh merge` reads a PR's state in three steps, then merges it. `_merge_exclusion` reads draft, labels and title. `_merge_config_guard` reads the changed-file list and refuses a PR that touches `.kit.toml`. The gate runs the ledger and diff rules. Then `gh pr merge <pr> --squash --delete-branch` merges whatever the PR head is at that moment (`lib/goal/mega-merge.sh:303`).

A push to the PR branch after the guards read it and before the merge lands a commit no guard saw. The case that matters: an unattended mega-goal run auto-merges a sub-goal PR, and a later push on that branch adds a `.kit.toml` edit that turns off `lane_gates` or adds a broad exemption. SPEC-400 named this residual (its implementation notes item 31, the verification record's "Not proven" list, and `SECURITY.md`).

## Terms

- head pin: the PR head commit SHA, read once before any guard, then passed to `gh pr merge --match-head-commit`. GitHub refuses the merge when the PR head no longer equals it.

## Solution

### Approaches considered

1. **Read the head first, pin the merge to it.** One `gh pr view --json headRefOid` read before `_merge_exclusion`; `--match-head-commit <sha>` on the merge. Tradeoff: one extra `gh` call. A push at any point after the read moves the head, so GitHub refuses the merge. The guards may read a newer head than the pin, which is safe: the merge then fails.
2. **Re-read state after the gate and compare.** Tradeoff: still leaves a window between the last read and the merge call. Rejected.
3. **Merge a local, checked commit by SHA through the API.** Tradeoff: needs the local checkout to hold the PR head, which the orchestrator's wave merge does not (it runs from its own checkout). Rejected.

### Chosen approach + why

Approach 1. GitHub enforces the pin server-side, so no window remains between the check and the merge. The head is read before the guards, so a push during the guards also fails the merge instead of slipping through.

### Extensibility & boundaries

- Units: (1) `_pr_head <pr>` reads the head SHA; (2) `merge()` reads it first, refuses when it is unreadable, and passes it to the merge command. Each is testable with the existing `MEGA_MERGE_*_CMD` and fake-`gh` patterns.
- Growth: none. One read per merge.

### Architecture

See `## Design`.

## Picture

```
 merge <pr> <rid> <lane> [--execute]
    |
    v
 _pr_head <pr>  --unreadable / not a 40-hex SHA-->  BLOCKED (fail closed)
    | sha H
    v
 _merge_exclusion --> _merge_config_guard --> gate
    |   (each may read a NEWER head than H; that only makes the merge fail)
    v
 gh pr merge <pr> --squash --delete-branch --match-head-commit H
    |
    +-- head still H  --> merged
    +-- head moved    --> GitHub refuses, merge() returns nonzero
```

## Design

### Approaches considered + chosen

See `## Solution`. Approach 1.

### Diagram

See `## Picture`.

### ADR link(s)

None. The change adds a guard to an existing command and reverses no recorded decision.

### Boundaries & failure modes

Out of bounds: the gate's own diff rules, which read the local checkout's `HEAD` (`lib/goal/mega-merge.sh:105`), not the PR head. See `## Out of Scope` and `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `_pr_head <pr>` (new, `lib/goal/mega-merge.sh`): prints the PR head SHA. Default read: `gh pr view <pr> --json headRefOid --jq .headRefOid`. Override for tests: `MEGA_MERGE_PR_HEAD_CMD <pr>`, the same shape as `MEGA_MERGE_PR_INFO_CMD`. Returns nonzero, printing nothing, when the read fails or the output is not exactly 40 lowercase hex characters.
- `merge()`: calls `_pr_head` first, before `_merge_exclusion`. On a nonzero return it prints `BLOCKED: cannot read PR #<pr> head commit (gh unavailable/offline); failing closed and refusing auto-merge. Verify + merge manually if intended.` on stderr, logs `BLOCKED merge pr=<pr> (head unreadable, fail-closed)`, and returns 1. Otherwise the merge command, and the `cmd_str` printed on every DRY-RUN and EXECUTING line, becomes `gh pr merge <pr> --squash --delete-branch --match-head-commit <sha>`.
- A failed `gh pr merge` (head moved, or any other error) keeps today's behavior: `merge()` returns gh's nonzero status, and the wave merge in `lib/queue/orchestrate.sh` stops convergence.
- `mark` and `_merge_exclusion` are unchanged.

### Data model changes

None.

### API changes

None. `MEGA_MERGE_PR_HEAD_CMD` is a new test-only env knob, listed in `lib/config/module-registry.md`.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-1: Head pin. Add `_pr_head`, call it first in `merge()`, refuse on unreadable or malformed output, and add `--match-head-commit <sha>` to the merge command and `cmd_str`. Add the AC cases to `tests/test-mega-merge.sh`, and stub `MEGA_MERGE_PR_HEAD_CMD` in every test that stubs `MEGA_MERGE_PR_INFO_CMD` (`tests/test-mega-merge.sh`, `tests/test-mega-reconcile.sh`). Depends on nothing. AC: AC1, AC2, AC3, AC4.

### Phase 2: Polish

- [ ] TASK-2: Docs. Add `MEGA_MERGE_PR_HEAD_CMD` to `lib/config/module-registry.md` beside `MEGA_MERGE_PR_INFO_CMD`. Remove the head-race residual from `SECURITY.md` and add a CHANGELOG `### Security-relevant config` line under `## [Unreleased]`. Depends on TASK-1. AC: AC5.
- [ ] TASK-3: Verification record `docs/verification/mega-merge-head-pin.md` with the green run and one negative control. Depends on TASK-1 and TASK-2. AC: the record exists and the control shows its case going red.

## After state

- [ ] Every mega-goal auto-merge pins the head its guards read. Checkable by `bash tests/test-mega-merge.sh` (case `head-pin-passed`).
- [ ] An unreadable head refuses the merge. Checkable by `bash tests/test-mega-merge.sh` (case `head-unreadable-refused`).

## Quality requirements

none (the repo keeps no `docs/QUALITY.md`; the negative-control AC rows pin the invariant).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality (every existing `tests/test-mega-merge.sh` and `tests/test-mega-reconcile.sh` case stays green)

| AC | Claim | Check | Expect |
|---|---|---|---|
| AC1 | The merge is pinned to the head read first | `head-pin-passed`: `MEGA_MERGE_PR_HEAD_CMD` prints a fixed 40-hex SHA; a clear, gate-passing PR runs `merge --execute` with the fake `gh` on PATH | the fake `gh` records `pr merge <pr> --squash --delete-branch --match-head-commit <sha>`; the DRY-RUN leg prints the same `cmd_str` |
| AC2 | An unreadable head refuses (negative control) | `head-unreadable-refused`: the head command exits 1, then prints nothing, then prints `abc` | each: nonzero return, stderr names `cannot read PR #<pr> head commit`, no `pr merge` recorded |
| AC3 | The head is read before the guards (negative control) | `head-read-first`: the head stub, the state stub and the files stub each append their name to one call log; a clear PR | the call log lists `head` first |
| AC4 | A moved head fails the merge (negative control) | `head-moved-fails`: the fake `gh` exits 1 on `pr merge` when `--match-head-commit` differs from a "current head" file the test then changes | `merge --execute` returns nonzero; the wave-merge contract (nonzero stops convergence) holds |
| AC5 | Docs match | `module-registry` row present; `SECURITY.md` no longer lists the head race; CHANGELOG line present | `bash tests/test-meta.sh` and `bash lib/gate/doc-projection-check.sh .` pass |

## Verification

`bash tests/test-mega-merge.sh && bash tests/test-mega-reconcile.sh && bash tests/test-meta.sh && bash lib/gate/doc-projection-check.sh . && bash tests/run-all.sh --changed origin/master`

AC map: AC1 `head-pin-passed`; AC2 `head-unreadable-refused`; AC3 `head-read-first`; AC4 `head-moved-fails`; AC5 `test-meta.sh` plus `doc-projection-check.sh`.

## Edge Cases

1. A push lands between the head read and the guards: the guards read the newer head, the pin holds the older one, GitHub refuses the merge. Safe; a later run re-reads both.
2. A force-push that rewrites the branch to the same tree under a new SHA: the head moved, so the merge fails. Accepted.
3. `per-pr-review` posture and dry runs: no merge runs, but the printed `cmd_str` carries the pin, so a human who copies it gets the same protection.
4. A `gh` without `--match-head-commit`: the merge call fails and `merge()` returns nonzero. Fail closed. The flag exists in the installed gh 2.100.0 (Grounding).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Head read after the guards | `head-read-first` goes red | `_pr_head` is the first call in `merge()` |
| Pin dropped from the merge command | `head-pin-passed` goes red | AC1 asserts the recorded argv |
| Unreadable head treated as clear | `head-unreadable-refused` goes red | Nonzero on a failed read or a non-40-hex value |
| Existing tests call real `gh` for the head | `test-mega-merge.sh` or `test-mega-reconcile.sh` cases go red offline | Stub `MEGA_MERGE_PR_HEAD_CMD` wherever `MEGA_MERGE_PR_INFO_CMD` is stubbed |

## Out of Scope

- The gate's diff rules read the local checkout's `HEAD` against its merge base (`lib/goal/mega-merge.sh:93-107`). The wave merge calls `merge` from the orchestrator's own checkout (`lib/queue/orchestrate.sh:2183`), so the gate's diff rules may not see the PR's commits at all. That is a separate, older gap with a larger fix (checking out or fetching the PR head); it needs its own spec.
- Other merge paths (`stack-merge.sh`, `wrap-land.sh`, `wrap merge --apply`, a direct `gh pr merge`).

## Decision Log

- DEC-1: read the head once, first, and pin the merge to it with `--match-head-commit`. Rationale: GitHub enforces it server-side, so no window remains. Rejected: re-reading after the gate (leaves a window), merging a local SHA (the wave merge has no PR checkout).
- DEC-2: an unreadable or malformed head refuses the merge. Rationale: the same fail-closed posture as `_merge_exclusion` and `_merge_config_guard`.
- DEC-3: the gate's local-`HEAD` diff check stays out of scope. Rationale: it is a separate gap with a larger fix; folding it in would turn a pin into a checkout redesign.

## Grounding

Live samples from this worktree (`fix/mega-merge-head-pin` at `06966368`).

Sample 1, the flag exists (`gh pr merge --help`, gh 2.100.0):

```
      --match-head-commit SHA   Commit SHA that the pull request head must match to allow merge
```

Sample 2, the head read shape (`gh pr view 963 --json headRefOid --jq .headRefOid`):

```
d2a480915ea1d62eaca5bfba24a7609a1adcd8b8
```

Sample 3, the merge call today (`lib/goal/mega-merge.sh:303`): `gh pr merge "$pr" --squash --delete-branch`, no pin.

Sample 4, the wave merge runs from the orchestrator's checkout (`lib/queue/orchestrate.sh:2183`): `$WAVE_MERGE_CMD "$pr" "$rid" "$lane"`, so `gate()` reads that checkout's `HEAD` (`lib/goal/mega-merge.sh:105`).

Dry traces for the negative controls:

- AC2: mutation, `merge()` ignores `_pr_head`'s return. Fixture: head command exits 1. Path: the guards and gate pass, the merge runs with an empty pin. `head-unreadable-refused` goes red on the recorded `pr merge`.
- AC3: mutation, `_pr_head` called after `_merge_config_guard`. Fixture: call log. Path: `state` and `files` precede `head`. `head-read-first` goes red.
- AC4: mutation, the pin flag dropped. Fixture: the fake `gh` refuses only a mismatched `--match-head-commit`. Path: no flag, the fake merges, `merge` returns 0. `head-moved-fails` goes red; `head-pin-passed` goes red on the argv too.

## Open questions

(none)
