# Proof of done: debt-ledger response-writer schema mismatch (TIER-4 close finding)

VERDICT: PASS

## Acceptance criteria

1. The live repro from the assigning prompt (`gate-ledger.sh debt-response ... defer` then
   `weekend-batch.sh mark-paid`) exits 0 (was exit 64).
2. `debt_response()` forward-carries significance/worthiness/verdict from the last FAT debt line
   for the rid, when one exists; never fabricates data when none exists.
3. `weekend-batch.sh cmd_mark_paid` closes via `debt-response ... engage`, never the raw fat `debt`
   verb.
4. Readers (`cmd_list`/`cmd_collect`) walk back to the last FAT line for sig/wor display when the
   last line lacks them.
5. A `reason=` free-text value can never smuggle a control token, at both the writer (neutered `=`)
   and reader (`_kv` struct-prefix cut) layers.
6. A true end-to-end `respond -> collect -> mark-paid` regression test exists (not a hand-seeded
   fat line), plus a forward-carry case and two security negative controls.
7. The full CI suite + the three directly-touched suites (`test-weekend-batch.sh`,
   `test-quiz-gate.sh`, `test-significance-classify.sh`) + `test-meta.sh` all stay green.

## Implementation

- `lib/gate-ledger.sh` `debt_response()`: looks back at the ledger for the rid's last `| DEBT |`
  line containing `verdict=` (a "fat" line); if found, re-emits its
  `significance=`/`worthiness=`/`verdict=` alongside the new `response=`. Also neuters any `=`
  inside a `reason` value (writer-side smuggle guard), matching the same guard added to `debt()`.
- `lib/weekend-batch.sh` `cmd_mark_paid()`: no longer calls the fat `debt` verb; closes via
  `bash "$GATE_LEDGER" debt-response "$rid" engage "$reason"`.
- `lib/weekend-batch.sh` `_last_fat_debt_line()` (new helper) + walk-back in `cmd_list`/`cmd_collect`:
  falls back to the last fat line for sig/wor display when the last (possibly thin) line lacks them.
- `lib/weekend-batch.sh` `_kv()`: cuts the line at the first ` reason=` (`struct="${line%% reason=*}"`)
  and parses control keys from that prefix only (reader-side smuggle guard, `_disposition()`
  inherits it automatically since it calls `_kv`).
- `.github/workflows/test.yml`: cosmetic, `test-significance-classify.sh` step comment corrected
  `SPEC-122` -> `SPEC-123`.
- `tests/test-weekend-batch.sh`: added a true end-to-end regression (thin response -> collect ->
  mark-paid, exits 0), a forward-carry case (fat line before a response line), and two security
  negative controls (writer-side neutering, reader-side struct-prefix cut against the actual
  exploitable shape: a silent-wave line with no real `response=` field).

## Confirmation run-table (2026-07-03/04, ug-fix worktree, fixed code)

| # | Command | Exit | Output |
|---|---------|------|--------|
| 1 | `bash tests/test-weekend-batch.sh` | 0 | `TOTAL: 34   PASS: 34   FAIL: 0   SKIP: 0` |
| 2 | `bash tests/test-quiz-gate.sh` | 0 | `TOTAL: 29   PASS: 29   FAIL: 0` |
| 3 | `bash tests/test-significance-classify.sh` | 0 | `25/25 passed, 0 failed` |
| 4 | `bash tests/test-meta.sh` | 0 | `Passed: 667 / 667` |
| 5 | Full CI suite (every `bash tests/test-*.sh` wired in `.github/workflows/test.yml`, 20 files) | 0 (all) | `PASS` for every suite: test-e2e, test-hooks, test-lane-classify, test-lane-telemetry, test-ledger-durability, test-mega-merge, test-meta-agent, test-meta, test-model-routing, test-multiplexer, test-orchestrate-wavefront, test-orchestrate, test-pane-viewer, test-proof-visual-evidence, test-review-team-plants, test-role-classify, test-significance-classify, test-spec-index, test-tier4-close, test-token-capture |
| 6 | Live repro (assigning prompt, verbatim): `gate-ledger.sh debt-response <rid> defer ...` then `weekend-batch.sh mark-paid <rid>` | 0 | `EXIT=0` (was `debt: significance must be low|high (got '')` / exit 64 before this fix) |

Note: `tests/test-weekend-batch.sh` and `tests/test-quiz-gate.sh` are not currently wired into
`.github/workflows/test.yml` (a pre-existing gap, out of scope for this fix); both were run
directly (rows 1-2) and are green.

## NEGATIVE CONTROL (revert -> RED -> restore)

The fix (and its own regression tests) is falsifiable, not a rubber stamp. The pre-fix code
(commit `77815c2`, the parent of this fix) was extracted via `git archive 77815c2 | tar -x` into a
scratch directory (no working-tree mutation, no `git worktree add`), then:

**1. The exact live repro from the assigning prompt, run against the pre-fix code:**
```
$ cd <scratch-pre-fix-checkout>
$ export DWARVES_KIT_LOG_DIR=$(mktemp -d); rid="repro-negctrl-$$"
$ bash lib/gate-ledger.sh debt-response "$rid" defer "deferred to weekend"
$ bash lib/weekend-batch.sh mark-paid "$rid"
debt: significance must be low|high (got '')
Exit: 64
```
RED, confirming the bug is real and reproducible on the pre-fix code.

**2. The same repro against the fixed code (this branch):**
```
$ cd <ug-fix worktree>
$ export DWARVES_KIT_LOG_DIR=$(mktemp -d); rid="repro-$$"
$ bash lib/gate-ledger.sh debt-response "$rid" defer "deferred to weekend"
$ bash lib/weekend-batch.sh mark-paid "$rid"
Exit: 0
```
GREEN, confirming the fix closes the exact reported bug.

**3. The NEW test file (this branch's `tests/test-weekend-batch.sh`, with all new regression +
forward-carry + security cases) copied onto the pre-fix `lib/` and run there:**
```
$ cp <ug-fix worktree>/tests/test-weekend-batch.sh <scratch-pre-fix-checkout>/tests/
$ cd <scratch-pre-fix-checkout>
$ bash tests/test-weekend-batch.sh
...
FAIL regression: mark-paid on a THIN response-only item exits 0 (was exit 64 before this fix)
FAIL regression: ug-20-thin-response-* is no longer collectible after mark-paid (disposed paid, never re-collected)
FAIL forward-carry: the response line carries significance=high from the earlier classifier line
FAIL forward-carry: the response line carries worthiness=high from the earlier classifier line
FAIL forward-carry: the response line carries verdict=tap from the earlier classifier line
FAIL forward-carry: the digest shows real sig/wor for ug-21-fat-then-response-* (high / high), not blanks
FAIL security [writer]: only ONE 'response=<word>' token survives on the line (the real control field; the embedded one was neutered)
FAIL security [reader]: a silent-wave line (no real response= field) with 'response=engage' smuggled in reason= still reads disposition=waved, NOT paid (struct-prefix cut)
TOTAL: 34   PASS: 26   FAIL: 8   SKIP: 0
```
8 of the new checks correctly FAIL against the pre-fix code (proving the new tests actually
exercise the seam, not a tautology), and the SAME test file run against the fixed code (row 1 of the
run-table above) is 34/34 green.

**4. Why the OLD test suite never caught this:** `tests/test-weekend-batch.sh`'s pre-existing `AC3a`
case seeded a hand-written FAT debt line directly into the fixture file (`seed()`, bypassing
`respond`/`debt-response` entirely) before calling `mark-paid` -- so `mark-paid`'s re-emit through
the fat `debt` verb always had real sig/wor/verdict to re-emit and never crashed in that fixture.
The new regression case instead calls the REAL `gate-ledger.sh debt-response` codepath with no
prior classifier line, which is the actual default live shape (the fat writer,
`significance-classify record`, is unwired today) -- that is the seam the old suite masked.

No restore step was needed: the pre-fix code was read from a disposable `git archive` extraction in
a scratch temp directory, never the working tree.

## Reproduce

```
cd <dwarves-kit>/.claude/worktrees/ug-fix   # or the merged master
bash tests/test-weekend-batch.sh
bash tests/test-quiz-gate.sh
bash tests/test-significance-classify.sh
bash tests/test-meta.sh
for t in $(grep -oE 'bash tests/test-[a-z0-9-]+\.sh' .github/workflows/test.yml | sort -u | sed 's/bash //'); do
  bash "$t" >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"
done

# live repro
export DWARVES_KIT_LOG_DIR=$(mktemp -d); rid="repro-$$"
bash lib/gate-ledger.sh debt-response "$rid" defer "deferred to weekend"
bash lib/weekend-batch.sh mark-paid "$rid"; echo "EXIT=$?"   # expect EXIT=0

# negative control (pre-fix code, disposable)
TMPD="$(mktemp -d)"; git archive 77815c2 | tar -x -C "$TMPD"
cd "$TMPD"
export DWARVES_KIT_LOG_DIR=$(mktemp -d); rid="repro-negctrl-$$"
bash lib/gate-ledger.sh debt-response "$rid" defer "deferred to weekend"
bash lib/weekend-batch.sh mark-paid "$rid"; echo "EXIT=$?"   # expect EXIT=64 (RED)
```
