# Proof of done: gauntlet A/B search-select (SPEC-241)

`tests/gauntlet/deploy/gauntlet-ab`: same card, two committed artifact variants, N rounds each through the unchanged room runner, scored per round by the row's own checker into `ab-verdict.txt`, verdict by sweep-or-honest-halt. One engine passthrough: `run-remote.sh` ships the caller's `GAUNTLET_SRC_TAR` as the artifact tarball (harness copy still ships HEAD).

## Green run (live smoke, AC-1/2/5)

`gauntlet-ab HEAD ab-smoke-defect user doorway 1` (omp/deepseek probe, local colima, bg-run detached; defect variant = a plumbing commit with `lib/adopt.sh` removed, worktree untouched):

```
ab: A round 1 checker=GREEN
ab: B round 1 checker=GREEN
[[AB-VERDICT winner=A a=1/1 b=1/1]]     # winner via token tiebreak
```

Result: PASS on what it can prove. Variant propagation verified by room contents: A's persisted room carries `kit/lib/adopt.sh`, B's room verifiably lacks it (`find` on both rooms in the committed record dir). Both rounds ran the full room + probe + checker path end to end. Rule-7 held: variants built by `git archive <ref>` (committed state only).

The expected B-RED did not materialize: the probe noticed the missing script and REBUILT it from the kit's own docs, then passed the doorway checker legitimately. Recorded as a finding, not a failure: a single-file deletion is a recoverable defect, so discriminating A/B cards must vary what the docs teach, not what a probe can reconstruct. (Also a data point for artifact robustness: the surface survives a missing adopt script.)

## Tally discrimination (deterministic, replaces the live B-RED leg)

Seeded a scratch pass dir with `A=GREEN, B=RED` verdict files, re-invoked the driver (all rounds resume-skipped):

```
[[AB-VERDICT winner=A a=1/1 b=0/1]]
```

## Resume (AC-3)

The real record was scored under the pre-review driver; after the review fixes, verdict files were seeded and the fixed driver re-invoked against the same pass dir: both rounds skipped (`already scored (GREEN)`), no probe re-run, the new-grammar `AB-ROUNDS.md` emitted. Resume keys on `ab-verdict.txt`, not dir existence (run-remote pre-creates dirs).

## Negative control (AC-4)

`gauntlet-ab 26daed4 ab-smoke-defect user nope 1` → `no checker at tests/gauntlet/check-submission-user-nope.sh; a scoreless A/B is meaningless`, exit 2, nothing staged.

## Design critique round

Opus critique verdicted REVISE with 1 BLOCKER + 3 HIGH + 3 MED + 1 LOW; all fixed before the live scoring completed: remote-path variant passthrough (the blocker: run-remote re-archived HEAD, discarding the variant on any non-local runner), verdict-file resume key, HARNESS/BLOCKED round classes excluded from the tally, sweep-or-AB-WEAK winner honesty, dual-format token tiebreak, untruncated diffstat disclosure. Delta log: `docs/implementation-notes/gauntlet-ab.md`.

## Reproduce

```
KIT_ROOT=<kit checkout> bash tests/gauntlet/deploy/gauntlet-ab <ref-A> <ref-B> user doorway 2
```
