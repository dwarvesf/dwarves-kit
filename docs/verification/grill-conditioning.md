# Proof of done: grill-conditioning (SPEC-138)
Profile: feature   Proof class: behavioral (advisory prompt-file + one write-time bash guard)

## Hypothesis / assumptions
- `/kit:grill`'s firing can be conditioned on a 3-signal precheck (S1 territory novelty, S2
  domain novelty, S3 declared novelty) without changing which lanes REQUIRE grill or adding any
  new command/agent.
- A grill auto-skip can be made auditable by a closed `reason=<home-turf|density-low|
  operator-wave>` enum enforced at WRITE time in `lib/gate/gate-ledger.sh record()`.
- What would prove this false: a `grill`+`skipped` ledger line landing with no reason token, or
  the WORKFLOW.md lane×phase matrix changing as a side effect.

## Test design
- `tests/test-grill-conditioning.sh` (23 assertions): Section A asserts the `record()` guard
  directly (3 valid tokens accepted, 3 negative controls for missing/garbage/look-alike tokens,
  `ran` and non-grill-phase skips unaffected). Sections B/C reproduce the PROSE precheck's two
  purely mechanical legs (S1's git-history check, the fire-rule arithmetic) as harness-only
  functions (not shipped code, same honest limitation `tests/test-design-record.sh` documents
  for other prompt-text logic) and assert the over-test's boundary claims: exactly-2-signals
  fires, S3-alone fires, the 89d-fresh vs 91d-stale S1 boundary (via an exact-epoch, TZ-safe
  fixture, see DEC-006), 1-signal auto-skips.
- Negative control (load-bearing): revert `lib/gate/gate-ledger.sh` to its pre-change state and
  re-run the same suite , exactly the 4 assertions exercising the new guard (checks 4/4b/5/5b)
  must flip RED, proving the suite is not vacuously green.
- Full regression: `tests/test-meta.sh` (SPEC-058 bank-count + SPEC-063 literal-string
  assertions untouched), `tests/test-hooks.sh`, `tests/test-e2e.sh`,
  `tests/test-gate-outcome.sh`, `tests/test-ledger-durability.sh`, `tests/test-lane-telemetry.sh`,
  `tests/test-lane-escalation.sh`, `tests/test-every-step-review.sh`, `tests/test-mega-merge.sh`,
  `tests/test-security-hardening.sh`.

## How to re-run
```
bash tests/test-grill-conditioning.sh
bash tests/test-meta.sh
```

## Runs

### 2026-07-04 07:30 GREEN -- grill-conditioning [green]
- Command: `bash tests/test-grill-conditioning.sh`
- Exit: 0
- Output (excerpt):
  ```
  --- Section A: gate-ledger.sh record() reason= enum guard ---
    PASS check1: reason=home-turf accepted
    PASS check1b: ledger line carries reason=home-turf
    PASS check2: reason=density-low accepted
    PASS check3: reason=operator-wave accepted
    PASS check4: bare-text grill skip refused (exit 64)
    PASS check4b: refused skip writes NOTHING to the ledger
    PASS check5: garbage reason= token refused (exit 64)
    PASS check6: grill+ran unaffected by the enum guard
    PASS check7: non-grill phase skip still accepts free text
  --- Section B: precheck boundary walkthroughs ---
    PASS fixture1 (home-turf): S1=no
    PASS fixture1 (home-turf): decision
    PASS fixture1: ledger accepts the resulting reason=home-turf skip
    PASS fixture2 (declared-novelty): S3 alone fires
    PASS fixture3 (S2 domain-novelty): S1 also fires (no history)
    PASS fixture3: exactly-2-signals fires
    PASS fixture3: blindspot pass required (S2 fired)
  --- Section C: threshold edges ---
    PASS edge: S3-only fires with 0 other signals
    PASS edge: exactly 2 signals (S1+S2) fires
    PASS edge: exactly 1 signal (S1 only) -> density-low
    PASS edge: exactly 1 signal (S2 only) -> density-low
    PASS edge: commit 89 days ago -> S1 does NOT fire (fresh)
    PASS edge: commit 91 days ago -> S1 DOES fire (stale)

  === 22/22 passed ===
  ```
- Verdict: PASS
- Note: this is checks 1-7 + 10-17 from SPEC-138's `## Test plan` coverage matrix in one run.

### 2026-07-04 07:45 RED-as-expected -- grill-conditioning [negative-control]
- Command: `bash tests/test-grill-conditioning.sh`, run against `lib/gate/gate-ledger.sh` temporarily
  reverted to its pre-change content (`git show HEAD~1:lib/gate/gate-ledger.sh`, copied over the
  working file in the same tree; restored immediately after, confirmed clean by `git status
  --short lib/gate/gate-ledger.sh` showing no diff)
- Exit: 1
- Output (excerpt):
  ```
    PASS check1: reason=home-turf accepted
    PASS check1b: ledger line carries reason=home-turf
    PASS check2: reason=density-low accepted
    PASS check3: reason=operator-wave accepted
    FAIL check4: bare-text grill skip refused (exit 64)
    FAIL check4b: refused skip writes NOTHING to the ledger (expected '0', got '1')
    FAIL check5: garbage reason= token refused (exit 64)
    PASS check6: grill+ran unaffected by the enum guard
    PASS check7: non-grill phase skip still accepts free text
    ... (Sections B/C unaffected, all still PASS)
  === 19/22 passed ===
  ```
- Verdict: RED-as-expected
- Note: exactly the 3 assertions exercising the new write-time guard (checks 4, 4b, 5) flip RED
  when the guard is absent; everything else (including the prose-precheck walkthroughs in
  Sections B/C, which do not depend on `gate-ledger.sh` at all) stays green, proving checks
  4/4b/5 are exercising the actual guard and not a tautology. Working tree restored to the
  committed state immediately after (confirmed via `git status --short`).

### 2026-07-04 07:50 PASS -- grill-conditioning [restore-confirm]
- Command: `git status --short lib/gate/gate-ledger.sh` (after restoring)
- Exit: 0
- Output: (empty -- byte-identical to the committed state)
- Verdict: PASS

### 2026-07-04 07:55 PASS -- grill-conditioning [regression]
- Command: `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash tests/test-e2e.sh && bash tests/test-gate-outcome.sh && bash tests/test-ledger-durability.sh && bash tests/test-lane-telemetry.sh && bash tests/test-lane-escalation.sh && bash tests/test-every-step-review.sh && bash tests/test-mega-merge.sh && bash tests/test-security-hardening.sh`
- Exit: 0
- Output (excerpt):
  ```
  test-meta.sh:              Passed: 667 / 667  -- All meta tests passed.
  test-hooks.sh:              Passed: 452 / 452  -- All tests passed.
  test-e2e.sh:                Passed: 20 / 20    -- Golden run green.
  test-gate-outcome.sh:       22/22 passed, 0 failed
  test-ledger-durability.sh:  35/35 passed, 0 failed
  test-lane-telemetry.sh:     25/25 passed, 0 failed
  test-lane-escalation.sh:    22/22 passed, 0 failed
  test-every-step-review.sh:  17/17 passed, 0 failed
  test-mega-merge.sh:         30/30 passed, 0 failed
  test-security-hardening.sh: 22/22 passed, 0 failed
  ```
- Verdict: PASS
- Note: `test-meta.sh`'s SPEC-058 grill-bank-count assertion (`GRILL_BANKS -eq 11`) and SPEC-063's
  literal-string assertion (`record <rid> grill ran` present in `commands/grill.md`) both hold
  unchanged, confirming the "no gate-requirement change" and "11 banks unchanged" After-state
  items.

### 2026-07-04 07:26 PASS -- grill-conditioning [live capture, real ledger]
- Command: `bash lib/gate/gate-ledger.sh record spec138-live-demo grill skipped "reason=home-turf:
  live capture for SPEC-138 proof, familiar territory + known domain nouns, 0 signals fired"`
- Exit: 0
- Output: appended to `~/.local/state/dwarves-kit/logs/runs/spec138-live-demo.log`:
  ```
  2026-07-04T07:26:03Z | GATE | grill | skipped | reason=home-turf: live capture for SPEC-138 proof, familiar territory + known domain nouns, 0 signals fired
  ```
- Cross-check against the sibling `kit_gates` reader's exact grammar (harness-observatory
  `adapters.read_kit_gates`, `ops-toolkit` PR #683): `line.split(" | ")` -> 5 parts;
  `marker=parts[1].strip()=="GATE"`; `gate=parts[2].strip()=="grill"`;
  `outcome=parts[3].strip()=="skipped"`; `reason=parts[4].strip()` is non-None and starts with
  `"reason=home-turf"`. Reproduced verbatim in Python against the live file; no exception, no
  special-casing needed (the reader treats the reason field as opaque text by design, per its
  own DECISIONS.md entry).
- Verdict: PASS
- Note: this is the ONE required live `reason=` skip line from a real ledger log (SPEC-138
  After-state item), separate from the isolated `DWARVES_KIT_LOG_DIR` sandbox the automated
  suite runs under, so this suite never pollutes the real corpus and this one line is the sole
  deliberate real-corpus write.

### 2026-07-04 10:40 GREEN (post-fix) -- grill-conditioning [green, after review fixes]
- Command: `bash tests/test-grill-conditioning.sh` (local TZ, then `TZ=UTC` and
  `TZ=America/Los_Angeles` re-runs)
- Exit: 0 (all three TZ runs)
- Output (excerpt, identical across all 3 TZ runs): `=== 23/23 passed ===`, including the new
  `PASS check5b: look-alike token (prefix, not exact) refused (exit 64)` and both threshold-edge
  lines (`PASS edge: commit 89 days ago -> S1 does NOT fire (fresh)` /
  `PASS edge: commit 91 days ago -> S1 DOES fire (stale)`).
- Verdict: PASS
- Note: supersedes the 22/22 run above after the two test-coverage-review fixes (closed-enum
  `case` pattern in `lib/gate/gate-ledger.sh`; exact-epoch date construction in
  `tests/test-grill-conditioning.sh`). The TZ cross-check directly answers the reviewer's HIGH
  finding (reproduced flaky under `TZ=UTC` before the fix; green under `TZ=UTC` and a third,
  non-UTC-non-local zone after it).

### 2026-07-04 10:42 RED-as-expected (post-fix) -- grill-conditioning [negative-control, re-run]
- Command: same revert-`lib/gate/gate-ledger.sh`-to-`HEAD~1` procedure as the first negative-control
  run above, re-run against the current (23-assertion) test file
- Exit: 1
- Output (excerpt): `PASS check1..3`, `FAIL check4`, `FAIL check4b`, `FAIL check5`,
  `FAIL check5b`, `PASS check6..7`, all of Sections B/C unaffected -- `=== 19/23 passed ===`
- Verdict: RED-as-expected
- Note: the new check5b (the look-alike-token negative control added after the test-coverage
  review) flips RED here too, alongside checks 4/4b/5, confirming it is exercising the guard and
  not vacuously green either. Working tree restored and confirmed clean via `git status --short
  lib/gate/gate-ledger.sh` (shows only the pre-existing, intentional uncommitted diff at the time,
  not a corruption from the revert/restore cycle).

## Reviews (SPEC-069 multi-lens, `lib/` touched)
- **Security** (`kit:security-reviewer`): SECURE, no HIGH/MEDIUM findings. Confirms `oneline()`
  already collapses newlines before the guard runs, the `case` match is a pure pattern match on
  a quoted variable (no glob/eval injection), the guard is correctly scoped to
  `phase==grill && state==skipped`, and the new CI step has no untrusted input.
- **Architecture** (`kit:code-reviewer`, architecture lens): 9/10, no MEDIUM+ findings. Confirms
  no new command/agent/lib file, the enum guard is narrowly scoped inline (not lifted into a
  shared table another phase could inherit), grill.md's documented `reason=` forms match
  `gate-ledger.sh`'s `case` patterns exactly, and `WORKFLOW.md`'s lane×phase matrix is absent
  from the diff (confirmed via `git diff master...HEAD --stat`).
- **Test-coverage** (`kit:code-reviewer`, test-coverage lens): 6/10 as first dispatched, with one
  HIGH (the TZ/time-of-day-dependent boundary fixture) and one MEDIUM (the closed-enum prefix
  bypass) finding, both real and both reproduced live by the reviewer. Both fixed pre-ship: see
  `docs/implementation-notes/grill-conditioning.md`'s 2026-07-04 10:45/10:50 entries and SPEC-138
  Decision Log DEC-005/DEC-006. Post-fix re-verification is the two dated runs directly above.

## Coverage-delta (what's newly covered that nothing covered before)
| Before SPEC-138 | After SPEC-138 |
|---|---|
| `record()` accepted any free-text reason for any phase; a grill skip's honesty was unverifiable | `record()` refuses a `grill`+`skipped` line without `reason=home-turf\|density-low\|operator-wave` (2 negative controls prove this is enforced, not documented-only) |
| No test exercised `gate-ledger.sh`'s grill-specific behavior at all (grepped: zero hits in `tests/*.sh` before this branch) | `tests/test-grill-conditioning.sh` (23 assertions) is the first suite to touch grill-skip semantics in `gate-ledger.sh` |
| The S1 90-day boundary was stated in prose only, never checked at the edge | 89d-fresh vs 91d-stale is asserted directly against a real `git log` on a constructed repo |
| The fire rule (">= 2 signals, or S3 alone") was stated only, never checked at its own edges | exactly-2-signals and S3-alone are asserted as distinct cases, plus both single-signal cases |

## Reversibility
`commands/grill.md`'s Step 0/0b/reordered-Step-2/Step-4 changes are pure prose (no runtime
code); `git revert` of the build commit removes them along with the `record()` guard in one
step. No schema, no migration, no persisted state beyond the append-only ledger (which is
never rewritten, only appended to, so a revert does not need to touch any existing ledger file).
