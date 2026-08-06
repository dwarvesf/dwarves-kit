# Proof of done: mega-lane reconcile (SPEC-096, kit-hardening SG-08)
Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | [mirror parity] `commands/mega.md` exists, carries decompose + front-load-checkpoint + per-run-merge-config, names the skill as the mirror source | PASS | R1, lines 1-9 |
| AC2 | auto-merge fires once every required gate for a lane is recorded (green gate) | PASS | R1, lines 12-18 |
| AC3 | [LOAD-BEARING NEGATIVE CONTROL] one required gate missing -> `gate` nonzero AND `merge` REFUSES (no merge, exit nonzero, `BLOCKED` message), even with `--execute` | PASS | R1, lines 24-30 |
| AC4 | dry-run is the default action -- `merge` on a passing gate never calls `gh` unless `--execute` is given | PASS | R1, lines 14-17 |
| AC5 | deploy/UAT terminus reuses SG-07's `lib/gate/proof-ledger.sh deployable` verbatim (yes for deployable, no for inert), documented in `mega.md` | PASS | R1, lines 32-36 |
| AC6 | per-run merge config (`MEGA_MERGE_POSTURE` / `--posture=`) honored -- `per-pr-review` forces dry-run even with `--execute` on a passing gate | PASS | R1, lines 38-43 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `commands/mega.md` (new command, mirrors the ops-toolkit `plan-for-mega-goal` skill's decompose + front-load-checkpoint + per-run-merge-config beats). `lib/goal/mega-merge.sh` (new lib, `gate`/`merge` verbs -- ship-layer auto-merge enforcement that rides `lib/gate/gate-ledger.sh check`, dry-run by default, refuses unconditionally on a failing/missing gate). |
| Where | `commands/mega.md`, `lib/goal/mega-merge.sh`, `tests/test-mega-reconcile.sh`, roster rows in `README.md` / `MANUAL.md` / `docs/architecture.md`. |
| How it runs | `gate` and `merge` are plain bash, called by the mega-lane hand-off step (Step 5 of `mega.md`) once a sub-goal's PR is CI-green. `gate` is a pure decision (calls `lib/gate/gate-ledger.sh check <lane> <rid>` verbatim); `merge` calls `gate` first and only proceeds to `gh pr merge` with `--execute`. No new hook, no new enforcement path -- the ship-gate itself (`hooks/ship-gate.sh`) is untouched. |
| Reversibility | Both new files are additive (no existing file's logic changed); `git revert` on this branch's commits fully removes them. `lib/gate/gate-ledger.sh` and `lib/gate/proof-ledger.sh` are read-only consumed, never modified (confirmed: `git diff` on this branch touches neither file). |

## 3. Confirmation (runs)

| Run | When (ISO+tz) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-07-02T00:00+07:00 | `bash tests/test-mega-reconcile.sh` | 0 | PASS (35/35) |
| R1-NEG | 2026-07-02T00:00+07:00 | `git show mega/kit-hardening:commands/mega.md`; `git show mega/kit-hardening:lib/goal/mega-merge.sh`; `git show mega/kit-hardening:tests/test-mega-reconcile.sh` | 128 (x3) | RED-as-expected: all three `fatal: invalid object name` -- none of the three new files (or their test) exist on the integration branch `mega/kit-hardening` this branch is stacked on, confirming the auto-merge enforcement is genuinely new, not a no-op re-add |
| R2 | 2026-07-02T00:00+07:00 | `bash tests/test-meta.sh` | 0 | PASS (578/578) |
| R3 | 2026-07-02T00:00+07:00 | `bash tests/test-hooks.sh` | 0 | PASS (438/438) |
| R4 | 2026-07-02T00:00+07:00 | `bash tests/test-ship-gate-profiles.sh` | 1 | [UNAVAILABLE: kit not installed at `~/.claude/dwarves-kit` in this dev sandbox; identical failure on `main` -- pre-existing environmental gap, not a regression] |

## 4. Run detail

### R1 GREEN
- Command: `bash tests/test-mega-reconcile.sh`
- Exit: 0
- Verdict: PASS (35/35, including the load-bearing NEGATIVE CONTROL block AC3)
- Output (excerpt):
  ```
  === mega-reconcile (SPEC-096 AC1-AC6) ===

  === AC1: mirror parity -- commands/mega.md exists + carries the 3 beats ===
    PASS AC1: commands/mega.md exists
    PASS AC1: mega.md starts with --- frontmatter
    PASS AC1: mega.md frontmatter has a description field
    PASS AC1: mega.md carries the decompose beat
    PASS AC1: mega.md carries the front-load-checkpoint beat
    PASS AC1: mega.md carries the per-run-merge-config beat
    PASS AC1: mega.md names the ops-toolkit plan-for-mega-goal skill as the mirror source
    PASS AC1: mega.md states it mirrors, not forks, the skill
    PASS AC1: mega.md wires lib/goal/mega-merge.sh into the hand-off step

  === lib/goal/mega-merge.sh exists, is executable, dispatches gate + merge ===
    PASS mega-merge.sh exists and is executable
    PASS mega-merge.sh dispatches 'gate'
    PASS mega-merge.sh dispatches 'merge'

  === AC2: auto-merge past a GREEN gate ===
    PASS AC2: mega-merge.sh gate exits 0 once every required gate is recorded
    PASS AC4: merge on a passing gate WITHOUT --execute prints DRY-RUN
    PASS AC4: merge on a passing gate WITHOUT --execute exits 0
    PASS AC4 [load-bearing]: merge WITHOUT --execute never actually calls gh
    PASS AC2: merge on a passing gate WITH --execute exits 0
    PASS AC2: merge on a passing gate WITH --execute actually calls gh
    PASS AC2: the executed call is a gh pr merge for the right PR

  === AC3 [LOAD-BEARING NEGATIVE CONTROL]: one required gate missing -> never merges ===
    PASS AC3 [NEGATIVE CONTROL]: gate exits nonzero when 'think' is missing
    PASS AC3 [NEGATIVE CONTROL]: merge REFUSES (nonzero exit) on a failing gate
    PASS AC3 [NEGATIVE CONTROL]: merge prints a BLOCKED message
    PASS AC3: the BLOCKED message names the missing gate
    PASS AC3 [NEGATIVE CONTROL]: a failing gate never calls gh, even with --execute
    PASS AC3 [NEGATIVE CONTROL]: --execute cannot force a merge past a failing gate

  === AC5: deploy/UAT terminus via lib/gate/proof-ledger.sh deployable (SG-07 reuse) ===
    PASS AC5: a deployable diff -> lib/gate/proof-ledger.sh deployable prints 'yes' (terminus engages)
    PASS AC5: an inert diff -> lib/gate/proof-ledger.sh deployable prints 'no' (terminus skipped)
    PASS AC5: mega.md documents the deploy/UAT terminus
    PASS AC5: mega.md wires the SG-07 deployable verb verbatim

  === AC6: per-run merge config (MEGA_MERGE_POSTURE) honored ===
    PASS AC6: MEGA_MERGE_POSTURE=per-pr-review dry-runs even WITH --execute on a passing gate
    PASS AC6: per-pr-review posture exits 0 (advisory dry-run, not a block)
    PASS AC6: per-pr-review posture never calls gh even with --execute
    PASS AC6: --posture= flag also honored (overrides default auto-to-final)
    PASS AC6: the posture knob is documented in mega-merge.sh
    PASS AC6: the posture knob is documented in mega.md

  === 35/35 passed, 0 failed ===
  ```

### R2 GREEN (shared-path safety: roster cross-refs)
- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output (excerpt):
  ```
  === SPEC-085: operator doc sync (ID-070) ===
    PASS README commands summary == command files (27)
    PASS README commands rows == command files (27)
  === Results ===
  Passed: 578 / 578
  All meta tests passed.
  ```

### R3 GREEN (shared-path safety: hooks unaffected)
- Command: `bash tests/test-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  === Results ===
  Passed: 438 / 438
  All tests passed.
  ```

### R4 [UNAVAILABLE] (pre-existing environmental gap)
- Command: `bash tests/test-ship-gate-profiles.sh`
- Exit: 1
- Output: `[NO EXECUTABLE CHECK: ship-gate hook not installed at /Users/tieubao/.claude/dwarves-kit/hooks/ship-gate.sh]`
- This is the dev sandbox not having the kit installed at `~/.claude/dwarves-kit`; it fails identically on `main` before this branch's changes and is called out as a pre-existing gap in the SG-08 goal file itself.

## 5. Reproduce

```bash
cd dwarves-kit
git checkout feat/kit-harden-08-megamirror
bash tests/test-mega-reconcile.sh   # 35/35
bash tests/test-meta.sh             # 578/578
bash tests/test-hooks.sh            # 438/438
```

Rollback: `git checkout main -- commands/mega.md lib/goal/mega-merge.sh` deletes both new
files cleanly (nothing else references them until `mega.md`'s own Step 5, which is
prose, not wired into any hook), and `git checkout main -- tests/test-mega-reconcile.sh
README.md MANUAL.md docs/architecture.md` restores the roster to its pre-branch state.
