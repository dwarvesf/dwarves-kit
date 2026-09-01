# Proof of done -- mutation-smoke (SPEC-131, kit-run-integrity SG-04)

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | biting suite FAILS on a mutation (bite is observable) | PASS (T1) |
| AC2 | a NON-biting suite is FLAGGED (`verdict=flag`, WARN) | PASS (T2) |
| AC3 | FALSE-POSITIVE NC (load-bearing): a biting suite is NOT flagged (`verdict=clean`, no WARN) | PASS (T3) |
| AC4 | clean tree after a run: mutated file byte-identical (hash) + porcelain clean, on BOTH the flag and clean paths | PASS (T4) |
| AC5 | advisory cannot block: a FLAGGED run exits 0 | PASS (T2, T5) |
| AC6 | runtime bounded: attempts capped at `MUTATION_SMOKE_MAX`, stops, no full sweep | PASS (T6) |
| AC7 | baseline-red SKIP: a red baseline yields `verdict=skip`, exit 0, no false flag | PASS (T7) |
| AC8 | additive-marker safety: a `\| MUTATION \|` line never satisfies/fakes/masks a required gate | PASS (T8) |
| CD  | coverage delta: 0 -> 11 mutation-smoke acceptance cases (32 assertions); covered vs uncovered named below | PASS |
| regression | sibling suites (`test-meta.sh` 667, `test-ledger-durability.sh` 35, `test-e2e.sh` 20) unaffected by the new `mutation` verb / spec / command | PASS |

**COVERAGE-DELTA.** Covered (T1-T11): bite-observable, flag, the false-positive NC (biting NOT
flagged), byte-identical clean-tree on both paths, advisory-exit-0, the mutation-count bound,
baseline-red skip, additive-marker gate-safety, no-runner skip, the sed-split portability edge
(line-1 + last-line, BSD address-0 guarded), and the tests/docs scope exclusion.
Uncovered (accepted, advisory smoke): a live polyglot suite run (`npm test`/`go test`/`pytest`) --
the tests use a controllable bash fixture suite as the strongest portable stand-in; and
semantic-equivalent mutations (a behaviorally-no-op mutation reads as a false survivor) -- comment
lines are excluded, mid-line string/comment mutations remain possible noise, called out not solved.

## Confirmation run

```
$ bash tests/test-mutation-smoke.sh
=== T1: bite is observable -- a mutation makes a biting suite FAIL ===
  PASS T1 a mutable candidate exists in the changed hunk
  PASS T1 biting suite went RED under mutation (bite observable)
=== T2: a NON-biting suite is FLAGGED ===
  PASS T2 advisory: flagged run still exits 0
  PASS T2 WARN emitted for a non-biting suite
  PASS T2 ledger records verdict=flag
=== T3: FALSE-POSITIVE negative control -- a biting suite is NOT flagged (load-bearing) ===
  PASS T3 biting run exits 0
  PASS T3 no WARN for a biting suite
  PASS T3 ledger records verdict=clean (suite bit)
  PASS T3 ledger has NO flag verdict
=== T4: clean tree after a run -- byte-identical, no residue (flag AND clean paths) ===
  PASS T4 [nonbiting] code.sh byte-identical after run
  PASS T4 [nonbiting] git tree clean after run (no residue)
  PASS T4 [biting] code.sh byte-identical after run
  PASS T4 [biting] git tree clean after run (no residue)
=== T5: advisory cannot block -- a flagged run never returns non-zero ===
  PASS T5 flagged smoke exit code is 0 (cannot block a push)
=== T6: runtime bounded -- attempts capped at MUTATION_SMOKE_MAX, no full sweep ===
  PASS T6 bounded run exits 0
  PASS T6 stopped at the cap (2 attempts), did not sweep all 6
  PASS T6 verdict=clean after the cap (all attempted mutations caught)
=== T7: baseline-red SKIP -- no false flag when the suite is already failing ===
  PASS T7 baseline-red run exits 0
  PASS T7 SKIP emitted (baseline not green)
  PASS T7 ledger verdict=skip reason=baseline-red
  PASS T7 no flag on a red baseline
=== T8: additive-marker safety -- a | MUTATION | line never fakes/satisfies a gate ===
  PASS T8 MUTATION-only ledger still fails the required-gate check (exit non-zero)
  PASS T8 spec gate still reported MISSING despite the MUTATION line
  PASS T8 MUTATION line changes nothing vs an empty ledger
=== T9: no test runner -> SKIP (advisory, exit 0) ===
  PASS T9 no-runner run exits 0
  PASS T9 SKIP: no test runner detected
  PASS T9 ledger verdict=skip reason=no-runner
=== T10: portability -- sed-split rewrite is byte-exact at line 1 and the last line ===
  PASS T10 line-1 rewrite
  PASS T10 last-line rewrite (rest intact)
=== T11: scope -- a diff touching only tests/docs yields no candidates (SKIP) ===
  PASS T11 no candidates from a tests/docs-only diff
  PASS T11 tests/docs-only run exits 0
  PASS T11 ledger verdict=skip reason=no-candidates

  ---------------------------------------------
  TOTAL: 32   PASS: 32   FAIL: 0
Exit: 0
```

Regression (siblings unaffected by the new `mutation` verb + spec + command):

```
$ bash tests/test-meta.sh | tail -2
Passed: 667 / 667
All meta tests passed.

$ bash tests/test-ledger-durability.sh | tail -1
=== 35/35 passed, 0 failed ===

$ bash tests/test-e2e.sh | tail -1
Golden run green.

$ shellcheck -S warning lib/gate/mutation-smoke.sh   # clean, no output, exit 0
```

## Run detail

- Repo `dwarves-kit`, branch `feat/kri-04-mutation-smoke`, isolated clone. macOS, bash 3.2-compatible,
  no network, no LLM calls (pure bash: `git diff`, `sed`, `awk`, subprocess to `gate-ledger.sh`).
- **The advisory contract is structural, not a prose promise.** `run()` has `return 0` on EVERY
  terminal path (skip / flag / clean); T5 pins that a flagged run exits 0. The ledger marker is a
  brand-new `| MUTATION |` verb whose readers (`check`/`override`/`descent`/`_rows`) all key on
  `$2=="GATE"|START|ACTION`; T8 pins that a `MUTATION`-only ledger yields the byte-identical
  required-gate verdict as an EMPTY one, so the smoke's decision can never fake or block a push.
- **The false-positive NC (T3) is the load-bearing check.** The biting fixture asserts `calc 2 3 == 5`;
  a `+`->`-` mutation makes it `-1`, the suite goes red, the mutation is CAUGHT, and the smoke stays
  quiet (`verdict=clean`, no WARN). Only the non-biting fixture (which runs the line but asserts
  nothing) is flagged. A smoke that flagged the good suite would be noise; it does not.
- **No residue (T4).** The target file is mutated in place (the suite must run against the real tree),
  but its exact bytes are backed up first and restored after each run; an `EXIT`/`INT`/`TERM` trap
  restores an in-flight mutation. T4 hashes `code.sh` before and after a full run on BOTH the flag and
  clean paths -- identical -- and asserts `git status --porcelain` is empty.
- **Bounded (T6).** The many-biting fixture has 6 mutable added lines; with `MUTATION_SMOKE_MAX=2` the
  smoke records `attempts=2` and stops -- no full sweep. First-survivor-stops bounds the flag case
  earlier.
- **Portable (T10).** The single-line rewrite is a `sed -n` head/tail split + `printf`, NOT `sed -i`
  (which needs `sed -i ''` on BSD and `sed -i` on GNU). The `n==1` head slice is skipped because BSD
  sed rejects line address 0. Operators are literal substrings (no `\b`/`[[:<:]]` word-boundary regex,
  which diverges BSD vs GNU). Verified green on macOS; CI re-runs it on ubuntu + macOS.
- Live invocation path (TIER-4 no-orphan): wired as an advisory Step 6b in `commands/verify.md`
  (`/kit:verify`), warn-only, never a verdict downgrade. Full docs-wiring is SG-06.

## Reproduce

```bash
cd dwarves-kit   # or the kri-04 clone
bash tests/test-mutation-smoke.sh
bash tests/test-meta.sh
bash lib/gate/mutation-smoke.sh detect-cmd     # inspect runner detection
bash lib/gate/mutation-smoke.sh candidates     # inspect changed-hunk mutation candidates
```
