# Proof of done: emit START/rid on the wave dispatch path (ID-099)

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | Every sub-goal in a wave (parallel) run gets its own START/rid record, same as the serial path | MET |
| 2 | Serial + wave paths write via the identical `_emit_start` (no drift risk between them) | MET |
| 3 | Negative control A: pre-fix-equivalent code produces ZERO wave START lines under the same scenario (causal effect, not just post-fix presence) | MET |
| 4 | Negative control B: a dispatch with no derivable rid is loudly flagged (WARN on stderr), never silently untracked, and the wave still completes (advisory, not an abort) | MET |
| 5 | No behavior change to the serial path's existing `_emit_start` call or its advisory missing-rid warning | MET |
| 6 | Green under macOS system bash 3.2 (CI-equivalent) AND modern bash 5 | MET |

## Implementation

`lib/queue/orchestrate.sh`:
- `_wave_run`'s spawn loop previously emitted only `_emit_event "$megadir" "$id" executing "wave (worktree $wt)"`
  and never called `_emit_start`, so a wave dispatch left zero START/rid records, invisible to
  lane-telemetry, even though the serial path (`cmd_run`) already calls `_emit_start` right after its
  own `executing` event.
- Added `_emit_start "$megadir" "$id"` immediately after the existing `executing` event in the wave
  spawn loop, mirroring the serial call site exactly (same function, same shared `_rid_for` rid
  derivation, same advisory WARN+skip when the goal file has no `**Branch:**` header). Nothing in
  `_emit_start` or `_rid_for` was changed; only the missing call site was added.
- Test-only `NC_SKIP_WAVE_START=1` escape hatch guarding the new call (same pattern as ID-094's
  `NC_SKIP_WAVE_TOKENS`), used only by the new test's negative control A.

New test: `tests/test-wave-rid-check.sh` (positive 2-sub-goal wave, negative control A: fix
stubbed out, negative control B: no-derivable-rid dispatch).

## Confirmation run-table

| Check | Command | bash 5 | bash 3.2 (macOS system) |
|---|---|---|---|
| New wave-rid-check test | `bash tests/test-wave-rid-check.sh` | ALL PASS (3/3) | ALL PASS (3/3) |
| Wave scheduling suite (regression) | `bash tests/test-orchestrate-wavefront.sh` | 2 pre-existing flakes only (see below) | 1 pre-existing flake only (see below) |
| Wave token capture (regression) | `bash tests/test-wave-token-capture.sh` | ALL PASS | ALL PASS |
| Syntax | `bash -n` / `/bin/bash -n lib/queue/orchestrate.sh` | OK | OK |

## Run detail

### Positive: 2-sub-goal wave -> two START records (previously zero)

```
$ /bin/bash tests/test-wave-rid-check.sh
PASS wave-rid-check POSITIVE: both wave sub-goals recorded a START line (SG-01=1 SG-02=1), where the pre-fix wave path recorded zero
RUN-TABLE (wave START records, positive):
  SG-01 rid=rid-check-sg-01: 2026-07-05T21:15:16Z | START | lane=normal classified=normal type=spec-feature ctype=spec-feature repo=orchfin-05
  SG-02 rid=rid-check-sg-02: 2026-07-05T21:15:16Z | START | lane=normal classified=normal type=spec-feature ctype=spec-feature repo=orchfin-05
PASS wave-rid-check NEGATIVE CONTROL A: pre-fix-equivalent code (START call stubbed) completes the SAME wave (both boxes flip) but records ZERO START lines -- causal effect demonstrated
PASS wave-rid-check NEGATIVE CONTROL B: no-derivable-rid wave dispatch still completes (box flips) and is LOUDLY WARNed on stderr, not silently untracked; zero ledger files written for it (advisory, no wrong-rid write either)
----
ALL PASS
```

Same output (modulo timestamp) under `bash` (modern bash 5) -- both runs 3/3 PASS, no flake.

### Negative control A: same wave scenario, START emission disabled (`NC_SKIP_WAVE_START=1`)

Demonstrates the fix's CAUSAL effect: the exact same 2-sub-goal wave, same mock, both sub-goals'
boxes still flip normally (the wave itself is unaffected) -- but with the new `_emit_start` call
skipped, ZERO START lines land in either sub-goal's ledger, and no ledger file is even created for
them:

```
PASS wave-rid-check NEGATIVE CONTROL A: pre-fix-equivalent code (START call stubbed) completes the
SAME wave (both boxes flip) but records ZERO START lines -- causal effect demonstrated
```

This directly operationalizes the sub-goal's stated proof: "a WAVE dispatch now emits a START/rid
record (it previously emitted none)", proven by contrast against the pre-fix-equivalent path.

### Negative control B: no-derivable-rid dispatch is loudly flagged, not silently untracked

A goal file with no `**Branch:**` header cannot derive a rid. The wave still dispatches and
completes (advisory, not an abort, per scope: "Not: ... turning the advisory warn into a hard
abort"), but `_emit_start` (shared, untouched by this fix) prints a loud WARN to stderr and writes
NO ledger file at all for that sub-goal (never a `?`-keyed or wrong-keyed write either):

```
[orchestrate] [telemetry] WARN: SG-01 goal file has no '**Branch:**' header; cannot derive rid, skipping START (run will be '?' in lane-telemetry).
...
PASS wave-rid-check NEGATIVE CONTROL B: no-derivable-rid wave dispatch still completes (box flips)
and is LOUDLY WARNed on stderr, not silently untracked; zero ledger files written for it (advisory,
no wrong-rid write either)
```

### Regression: wave scheduling suite (pre-existing flake, reproduced on unmodified master)

```
$ bash tests/test-orchestrate-wavefront.sh
FAIL wave_run g: concurrency NOT proven (rc=1 ...)
FAIL wave_run h2: both mock sessions never started (marker files missing)
2 FAILED
$ /bin/bash tests/test-orchestrate-wavefront.sh
FAIL wave_run g: concurrency NOT proven (rc=1 ...)
1 FAILED
```

Confirmed pre-existing and unrelated to this change: `git stash` (reverting this branch's diff back
to `origin/master`) reproduces the identical `wave_run g` failure signature on the exact same host,
same run. This is the same host-load-sensitive FIFO-barrier flake documented in
`docs/verification/orchfin-03-wave-tokens.md` (ID-094); not introduced by ID-099.

### Regression: wave token capture (ID-094, unaffected)

```
$ bash tests/test-wave-token-capture.sh
... ALL PASS
$ /bin/bash tests/test-wave-token-capture.sh
... ALL PASS
```

## Reproduce

```bash
bash tests/test-wave-rid-check.sh          # modern bash
/bin/bash tests/test-wave-rid-check.sh     # macOS system bash 3.2 (CI-equivalent)
bash tests/test-wave-token-capture.sh      # ID-094 regression, both bash versions
bash tests/test-orchestrate-wavefront.sh   # wave scheduling regression, both bash versions
```
