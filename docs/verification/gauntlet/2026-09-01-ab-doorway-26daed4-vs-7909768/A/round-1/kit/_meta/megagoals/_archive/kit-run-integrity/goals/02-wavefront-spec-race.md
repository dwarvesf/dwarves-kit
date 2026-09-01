# Sub-goal 02: close the wavefront SPEC-number race

**Merge policy:** auto
**Time budget:** 3-5 hours (design-bearing; the fix is small but the race analysis + test are the work).
**Proof:** run-table proving the race is closed: a CONCURRENCY test that fires N reservations "simultaneously" (background subshells / `xargs -P`) against the reservation path and asserts N DISTINCT numbers, zero collisions · the reservation SURVIVES the scan surfaces spec-next already covers (a reserved-but-not-yet-branched number is not handed out twice) · a negative control: the OLD path (racing `spec-next next` with no reservation) DOES collide (proves the test can see a collision) · `spec-next.sh check <NNN>` still reports a reserved number as TAKEN. A COVERAGE-DELTA row names what was covered + what was left uncovered.
**Depends on:** none. FIRST.
Model: opus
Effort: high
**Branch:** feat/kri-02-spec-race
**PR base:** master

## Outcome

The concurrent `spec-next.sh next` race is closed. Today `spec-next.sh` scans docs/specs/ + local/remote branches + recent commit subjects and prints max+1 (SPEC-064 already hardened the SCAN). But a parallel wave calls `next` at spec-time, BEFORE any of the racing workers has created its branch or written its spec , so all of them scan the same surfaces, see the same max, and get the SAME number. The scan is correct; the RESERVATION happens too late. Fix: move WHO reserves the number and WHEN , an ATOMIC reservation at wavefront dispatch (in `lib/orchestrate.sh`'s wavefront path), so a number is claimed the instant it is handed out, before the branch exists, and the next caller sees it as taken. REUSE `spec-next.sh` (its scan is the source of truth for "already used"; the reservation is an additional surface it consults, not a rewrite of the scan).

## Quality bar

REUSE, do not rewrite: `spec-next.sh next` stays the number source; add a reservation surface (an append-only reservations ledger under the kit log dir, claimed under `flock` so two concurrent claims serialize) that `_numbers()` (or an equivalent consult) folds in, so a reserved number reads as taken by the very next `next`. The atomic claim is the load-bearing property , prove it with a real concurrency test (N parallel claimers -> N distinct numbers), and prove the test can FAIL with a negative control (the pre-fix path collides). Minimum-infra: a file + `flock`, no daemon, no new service. The fix must not break the existing `spec-next.sh next|check` contract (SPEC-064 / ID-052).

## How to close the loop

`bash lib/lane-classify.sh classify "close the wavefront SPEC-number reservation race in orchestrate.sh, reusing spec-next.sh"` then run that lane. This is DESIGN-BEARING: `/spec` + `/spec-validate` FIRST with a `## Design` block that pins (a) the reservation surface + its path under the kit log dir, (b) the `flock` atomic-claim protocol, (c) exactly WHERE in orchestrate.sh's wavefront path the claim moves to, (d) how a reservation is reconciled once the branch/spec exists (the branch scan then covers it; the reservation can expire or be pruned). Resolve open-fork 1 (reservation mechanism). Then `/kit:test-plan` + the concurrency test + the negative control. Capture the COVERAGE-DELTA row. Record each gate via `bash lib/gate-ledger.sh record <rid> <phase> ran "<note>"`. Assumptions: ROADMAP `## Assumptions` + open-fork 1.

**Done =** N concurrent reservations yield N distinct SPEC numbers (real concurrency test green), a reserved number reads as TAKEN before its branch exists, the negative control shows the old path colliding, `spec-next.sh next|check` contract intact, COVERAGE-DELTA row recorded, gates ledgered, committed at phase boundaries.

## Scope edges

**In:** the reservation surface (a `flock`-guarded append-only reservations file under the kit log dir), the consult in/beside `spec-next.sh`, the moved claim point in `lib/orchestrate.sh`'s wavefront dispatch, the concurrency test + negative control + coverage-delta.
**Out:** the conductor's manual pre-assign for THIS run (the conductor does that itself outside the kit); 01's outcome emit; 03/04 gates; 05 proof-table; 06 docs.
**Not:** a rewrite of `spec-next.sh`'s scan (reuse it); a new numbering scheme; a daemon or lock service (a file + flock); changing the SPEC-064 `next|check` contract.

## Where to look

`lib/spec-next.sh` (the scanner to REUSE; note the SPEC-064 header explaining the prior collisions , SPEC-047/041 , which were the STALE-branch case; this is the CONCURRENT case), `lib/orchestrate.sh` (the wavefront dispatch path; grep `wavefront` , see the `_wave_gate` / WAVE_CAP logic around the pre-wavefront invariant), `lib/kit-log-dir.sh` (where the reservation file should live), `lib/gate-ledger.sh` (the `flock`/append-only pattern already used for the ledger , mirror its atomic-append discipline).

## PR body

Close the wavefront SPEC-number race: a parallel wave that each calls `spec-next next` before any branch exists all get the same number (the scan is correct; the reservation is too late). Reuse spec-next's scan; add a `flock`-guarded reservation claimed atomically at wavefront dispatch, so a number reads as taken the instant it is handed out. Verify: concurrency test (N parallel claims -> N distinct numbers) + negative control (old path collides) + spec-next contract intact + coverage-delta. First of the kit-run-integrity wave (enables the parallel 01/03/04/05). Roadmap: ops-toolkit `_meta/megagoals/kit-run-integrity/ROADMAP.md`.

## Notes

<empty>
