# Spec: the mega-goal merge gate checks the PR head it merges
Generated: 2026-10-10
Status: DRAFT
Lane: full
Depth: blind-spot (failure: the auto-merge gate passes on a commit other than the one GitHub merges, so a hard-path diff in the PR skips the full lane's gates)
References: `lib/goal/mega-merge.sh` `_pr_head` (imitate its overridable read and fail-closed return); `lib/gate/ship-rules.sh` `ship_rules_merge_base`, `ship_rule_floor`, `ship_rule_large_spec` (reuse as is); `git fetch origin refs/pull/<n>/head` (use as is).

## Problem

`mega-merge.sh merge` pins the PR head SHA `H` before its guards and merges with `--match-head-commit H` (SPEC-402). Its `gate()` step does not look at `H`. It reads the local checkout's `HEAD` (`lib/goal/mega-merge.sh` `gate`, `head="$(git -C "$root" rev-parse HEAD)"`) and runs the hard-path floor and the large-spec rule on that commit against its merge base.

The wave merge calls `merge` from the orchestrator's own checkout (`lib/queue/orchestrate.sh` converge loop, `$WAVE_MERGE_CMD "$pr" "$rid" "$lane"`). That checkout is on the default branch or the mega branch, not the sub-goal PR. So the floor diffs a commit with none of the PR's changes, finds no hard path, and the gate passes. A sub-goal PR that touches `src/auth/` or a migration can then auto-merge on the lane its goal file claims, with no full-lane gates. SECURITY.md names this residual.

## Terms

- PR head `H`: the SHA `_pr_head` reads, already passed to `--match-head-commit`.
- head mode: `gate <rid> <lane> --head <sha>`, where the diff rules run on `<sha>`, not on the local `HEAD`.

## Solution

### Approaches considered

1. **Fetch the PR head into the gate's repo and run the diff rules on `H`.** `merge()` fetches `refs/pull/<pr>/head`, checks the fetched commit equals `H`, and calls `gate --head H`. Tradeoff: one `git fetch` per merge; needs network access to origin, which `gh pr merge` needs anyway.
2. **Read the PR diff through the GitHub API and match paths there.** Tradeoff: duplicates the floor's path and data-loss logic outside `ship-rules.sh`, so the two gates drift. Rejected.
3. **Require the caller to check out the PR branch before `merge`.** Tradeoff: moves the burden to every caller, and the wave merge would have to switch branches inside the orchestrator checkout. Rejected.

### Chosen approach + why

Approach 1. The floor and large-spec rules stay the single implementation in `ship-rules.sh`, and they now see the exact commit GitHub merges. The fetch check ties the gate to the pin: if the fetched head is not `H`, the merge would fail anyway, so the gate refuses early.

### Extensibility & boundaries

- Units: (1) `gate --head <sha>`: the diff rules and the spec lookup read `<sha>`; (2) `_pr_fetch <pr> <sha>` in `merge()`: fetch and verify; (3) `merge()` passes the pin to the gate. Each is testable with a local bare `origin` that carries `refs/pull/<n>/head`.
- Growth: none. One fetch per merge.

### Architecture

See `## Design`.

## Picture

```
 merge <pr> <rid> <lane>
    |
 _pr_head --> H (pin, SPEC-402)
    |
 _merge_exclusion --> _merge_config_guard
    |
 _pr_fetch <pr> H:  git -C root fetch origin refs/pull/<pr>/head
    |                 FETCH_HEAD == H ?  --no / fetch fails-->  BLOCKED (fail closed)
    v yes
 gate <rid> <lane> --head H
    |   ledger check (unchanged)
    |   base = merge-base(H, remote default)
    |   large-spec rule: spec read from H's tree
    |   ship_rule_floor root base H
    v
 gh pr merge <pr> --match-head-commit H

 gate <rid> <lane>   (no --head: unchanged, local HEAD; the hook-parity path)
```

## Design

### Approaches considered + chosen

See `## Solution`. Approach 1.

### Diagram

See `## Picture`.

### ADR link(s)

None. The change narrows which commit an existing gate reads and reverses no recorded decision.

### Boundaries & failure modes

Out of bounds: the ship-gate hook, which already reads the pushed head. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `gate <rid> <lane> [--head <sha>]` (`lib/goal/mega-merge.sh`): with no `--head`, behavior is unchanged (local `HEAD`), so `tests/test-mega-gate-parity.sh` keeps its hook parity. With `--head <sha>`:
  - `<sha>` must be 40 lowercase hex characters and a commit in the gate's repo (`git cat-file -e <sha>^{commit}`). Otherwise the gate prints `BLOCKED: mega gate: head <sha> is not a commit in <root>` on stderr and returns 1.
  - With no repo root, `--head` returns 1 with `BLOCKED: mega gate: --head needs a repo`, never the bare ledger check.
  - `base` is `ship_rules_merge_base <root> <sha>`. The ledger check and lane config read that base, as today.
  - The large-spec rule finds the spec in `<sha>`'s tree: the first path from `git ls-tree -r --name-only <sha>` that matches `docs/specs/SPEC-<n>-<rid>.md` at the root, else `*/docs/specs/SPEC-<n>-<rid>.md` (`<n>` digits), the same precedence `spec_for_slug` uses. It writes that blob to a temp file for `ship_rule_large_spec` and removes it after. No match means no large-spec rule, as today.
  - `ship_rule_floor <root> <base> <sha> ...` runs on `<sha>`.
- `_pr_fetch <pr> <sha>` (new): runs `git -C <root> fetch -q origin refs/pull/<pr>/head`, then checks `git -C <root> rev-parse FETCH_HEAD` equals `<sha>`. Returns nonzero on a failed fetch or a mismatch. Override for tests: `MEGA_MERGE_PR_FETCH_CMD <pr> <sha>` (test-only; never set in an unattended run), the same shape as the other `MEGA_MERGE_PR_*_CMD` knobs. `<root>` is `MEGA_MERGE_ROOT` or the cwd's repo, the same as `gate()`.
- `merge()`: after `_merge_config_guard` and before the gate, it calls `_pr_fetch <pr> <H>`. On nonzero it prints `BLOCKED: cannot fetch PR #<pr> head <H> (offline, or the head moved); failing closed and refusing auto-merge.` on stderr, logs `BLOCKED merge pr=<pr> (PR head fetch failed, fail-closed)`, and returns 1. Otherwise it calls `gate <rid> <lane> --head <H>`.

### Data model changes

None.

### API changes

`gate` gains an optional `--head <sha>`. `MEGA_MERGE_PR_FETCH_CMD` is a new test-only env knob, listed in `lib/config/module-registry.md`.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-1: `gate --head`. Parse the flag, validate the SHA and the repo, run the base, large-spec (spec from the SHA's tree) and floor rules on it. Add cases to `tests/test-mega-merge.sh` (or a new `tests/test-mega-gate-head.sh` registered with the runner) using a temp repo. Depends on nothing. AC: AC1, AC2, AC3, AC4.
- [ ] TASK-2: `_pr_fetch` and the `merge()` wiring. Add the fetch-and-verify step and pass `--head` to the gate. Stub `MEGA_MERGE_PR_FETCH_CMD` in every existing test that runs `merge` (`tests/test-mega-merge.sh`, `tests/test-mega-reconcile.sh`). Depends on TASK-1. AC: AC5, AC6, AC7.

### Phase 2: Polish

- [ ] TASK-3: Docs. Add `MEGA_MERGE_PR_FETCH_CMD` to `lib/config/module-registry.md`. In `SECURITY.md` line 14, replace the sentence that says the gate's diff rules read the local `HEAD` with one that says the mega-goal gate now checks the pinned PR head. Update the `gate` header comment in `mega-merge.sh` and `commands/mega.md` where it describes what the gate reads. Add a CHANGELOG `### Security-relevant config` line under `## [Unreleased]`. Depends on TASK-2. AC: AC8.
- [ ] TASK-4: Verification record `docs/verification/mega-gate-pr-head.md` with the green run, an end-to-end leg through a local bare origin, and one negative control. Depends on TASK-1 to TASK-3. AC: the record exists and the control shows `head-mode-floor-hits` going red.

## After state

- [ ] A mega-goal merge of a PR that touches a hard path asks for the full lane's gates even when the orchestrator checkout is on the default branch. Checkable by the case `merge-floor-sees-pr-head`.
- [ ] `gate` with no `--head` still matches the ship-gate hook. Checkable by `bash tests/test-mega-gate-parity.sh`.

## Quality requirements

none (the repo keeps no `docs/QUALITY.md`; the negative-control AC rows pin the invariant).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality (every existing `test-mega-merge.sh`, `test-mega-reconcile.sh` and `test-mega-gate-parity.sh` case stays green)

In the table, the fixture is a temp repo with a bare `origin` (default branch `main`), a ledger stub that passes only the normal lane's gates, and a branch commit `P` that adds `src/auth/login.ts`. The working checkout stays on `main`.

| AC | Claim | Check | Expect |
|---|---|---|---|
| AC1 | Head mode runs the floor on the given commit (negative control) | `head-mode-floor-hits`: `gate rid normal --head P` from the `main` checkout | exit 1, stderr names `hard path (auth: src/auth/login.ts`; the same gate with no `--head` exits 0 |
| AC2 | Head mode refuses a SHA that is not a commit, and refuses with no repo (negative control) | `head-mode-bad-sha`: `--head` with 40 hex chars that name no object, then `--head abc`, then `--head P` with `MEGA_MERGE_ROOT` pointing at a non-repo | each exits 1 with `BLOCKED: mega gate:`; no bare ledger pass |
| AC3 | Head mode finds the spec in the commit's tree | `head-mode-large-spec`: `P` also adds `docs/specs/SPEC-001-rid.md`, a large spec, with no validate record; the `main` checkout has no such file | exit 1, stderr names `is large` |
| AC4 | No `--head` keeps hook parity | `tests/test-mega-gate-parity.sh` unchanged | all cases pass |
| AC5 | `merge` fetches the PR head and gates on it (negative control) | `merge-floor-sees-pr-head`: origin carries `refs/pull/7/head` = `P`; head stub prints `P`; state and files stubs clear; `merge 7 rid normal --execute` from the `main` checkout | refused at the gate with the auth hard-path message; no `pr merge` recorded |
| AC6 | A fetch that fails, or fetches another commit, refuses (negative control) | `merge-fetch-mismatch`: `refs/pull/7/head` = `P2` while the head stub prints `P`; then origin unreachable | each refused with `cannot fetch PR #7 head`; no `pr merge` recorded |
| AC7 | A clean PR still merges | `merge-clean-pr-head`: `P` changes only `README.md`; same setup as AC5 | the fake `gh` records `pr merge 7 --squash --delete-branch --match-head-commit P` |
| AC8 | Docs match | registry row present; `SECURITY.md` no longer says the gate reads the local `HEAD`; CHANGELOG line present | `bash tests/test-meta.sh` and `bash lib/gate/doc-projection-check.sh .` pass |

## Verification

`bash tests/test-mega-merge.sh && bash tests/test-mega-reconcile.sh && bash tests/test-mega-gate-parity.sh && bash tests/test-meta.sh && bash lib/gate/doc-projection-check.sh . && bash tests/run-all.sh --changed origin/master`

AC map: AC1 `head-mode-floor-hits`; AC2 `head-mode-bad-sha`; AC3 `head-mode-large-spec`; AC4 `test-mega-gate-parity.sh`; AC5 `merge-floor-sees-pr-head`; AC6 `merge-fetch-mismatch`; AC7 `merge-clean-pr-head`; AC8 `test-meta.sh` plus `doc-projection-check.sh`. If TASK-1 puts the head-mode cases in a new test file, the Verification command adds it.

## Edge Cases

1. The PR is from a fork: `refs/pull/<n>/head` still exists on the base repo, so the fetch works.
2. The orchestrator checkout has local changes: the gate reads only objects and the merge base, never the working tree, in head mode. The spec lookup reads the commit's tree, not the working tree.
3. A push lands after `_pr_head` but before `_pr_fetch`: the fetched head is not `H`, so `merge` refuses. A rerun pins the new head.
4. The fetch writes `FETCH_HEAD` and objects into the orchestrator repo. It moves no branch and touches no working tree.
5. The gate's ledger arm still keys on `<rid>`, as today. Head mode changes only which commit the diff rules read.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Gate reads local `HEAD` in the merge path | `merge-floor-sees-pr-head` goes red | `merge()` always passes `--head H` |
| Fetched commit differs from the pin | `merge-fetch-mismatch` goes red | `_pr_fetch` compares `FETCH_HEAD` to `H` |
| Head mode falls back to the bare ledger check | `head-mode-bad-sha` goes red | `--head` with no repo or a bad SHA returns 1 |
| Spec looked up in the working tree in head mode | `head-mode-large-spec` goes red | Spec read from the commit's tree |
| Parity with the hook breaks | `test-mega-gate-parity.sh` goes red | No `--head` keeps today's code path |
| Existing merge tests fetch from the real origin | merge cases go red offline | Stub `MEGA_MERGE_PR_FETCH_CMD` wherever `merge` runs |

## Out of Scope

- Other merge paths (`stack-merge.sh`, `wrap-land.sh`, `wrap merge --apply`, a direct `gh pr merge`).
- The ship-gate hook, which reads the pushed head already.

## Decision Log

- DEC-1: fetch `refs/pull/<pr>/head`, verify it equals the pin, and run the existing rules on it. Rationale: one implementation of the floor, and the gate reads the exact merged commit. Rejected: an API path diff (a second floor), requiring a PR checkout (pushes the burden onto every caller).
- DEC-2: `gate` with no `--head` is unchanged. Rationale: it is the hook-parity surface, pinned by `test-mega-gate-parity.sh`.
- DEC-3: head mode never falls back to the bare ledger check. Rationale: a caller that asks for a head expects the diff rules; skipping them silently would recreate this gap.

## Grounding

Live samples from this worktree (`fix/mega-gate-pr-head` at `5f298ae2`).

Sample 1, a PR head ref fetches and matches the pinned head (PR #965):

```
$ git ls-remote origin refs/pull/965/head | cut -c1-12
c7f77d2f0949
$ git fetch -q origin refs/pull/965/head && git rev-parse FETCH_HEAD | cut -c1-12
c7f77d2f0949
```

Sample 2, `gate()` reads the local `HEAD` today (`lib/goal/mega-merge.sh` gate): `head="$(git -C "$root" rev-parse HEAD 2>/dev/null || true)"`.

Sample 3, the wave merge runs from the orchestrator checkout (`lib/queue/orchestrate.sh` converge loop): `$WAVE_MERGE_CMD "$pr" "$rid" "$lane"`, with no checkout of the PR branch.

Sample 4, the large-spec rule reads a file path (`ship_rule_large_spec` calls `spec.sh depth size "$spec"`), so head mode writes the blob to a temp file.

Dry traces for the negative controls:

- AC1: mutation, head mode ignores `--head` and reads local `HEAD`. Fixture: checkout on `main`, `P` adds `src/auth/login.ts`. Path: the floor diffs `main` against itself, no hit, exit 0. `head-mode-floor-hits` goes red.
- AC2: mutation, head mode with a missing SHA falls back to the bare ledger check. Fixture: unknown SHA. Path: ledger stub passes, exit 0. `head-mode-bad-sha` goes red.
- AC3: mutation, the spec is looked up in the working tree. Fixture: spec only in `P`. Path: no spec found, the rule is skipped, exit 0. `head-mode-large-spec` goes red.
- AC5: mutation, `merge()` calls `gate` without `--head`. Fixture: as AC5. Path: gate passes on `main`, the fake `gh` records the merge. `merge-floor-sees-pr-head` goes red.
- AC6: mutation, `_pr_fetch` skips the `FETCH_HEAD` comparison. Fixture: `refs/pull/7/head` = `P2`. Path: fetch succeeds, the gate runs on `H` (= `P`, already in the repo), passes, the merge is recorded. `merge-fetch-mismatch` goes red.

## Open questions

(none)
