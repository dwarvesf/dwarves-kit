# Proof of done: token capture under delegation (SPEC-117, orchestrate-hardening 02)

A delegated `claude -p --stream > child.jsonl` run records faithful usage to the kit token ledger
(SPEC-110 `| TOKENS |` marker) via the new lean `--capture-tokens`/`CAPTURE_TOKENS` trigger, and the
CONDUCTOR reads only the box-flip , never the child transcript. Executes ADR-0032 §3. Both
load-bearing properties are tested, plus the false-bloat negative control.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| C1 | `--capture-tokens` serial run records a `\| TOKENS \|` line equal to the child's ASSISTANT-only totals (`in=1200 out=80 cache_read=8000 cache_create=0`); the cumulative `type:result` line is NOT double-counted (would be `in=2400`) | PASS |
| C1b | Recorded usage == `sum-usage(child.jsonl)` (the record IS the captured file's totals) | PASS |
| C2 | Conductor-stays-lean: the child transcript sentinel is ABSENT from the conductor's stdout, PRESENT in `.orchestrate/<id>.stream.jsonl` | PASS |
| C3 | FALSE-BLOAT NC: the SAME child under `--stream` (tee) PUTS the transcript in the conductor stdout (bloat), while `--capture-tokens` (redirect) leaves it out (lean); BOTH record the identical TOKENS line | PASS |
| C4 | fd1-rigorous: with stdout/stderr captured SEPARATELY, the transcript sentinel is absent from fd1 (the forwarded stream) | PASS |
| C5 | env parity: `CAPTURE_TOKENS=1` (no flag) behaves identically (records TOKENS, conductor lean) | PASS |
| C6 | `--capture-tokens` is an accepted flag (not `unknown flag`) + shows its `--dry-run` advisory | PASS |
| C7 | default NC: no flag/env -> NO stream-json child file, NO TOKENS line (honest `usage=?`, SPEC-087 default invocation intact) | PASS |
| R | Regression: `test-orchestrate.sh`, `test-orchestrate-wavefront.sh`, `test-meta.sh` (662), `test-lane-telemetry.sh` (25), `test-spec-index.sh` (9); `shellcheck` clean | PASS |

The two load-bearing properties were confirmed NON-vacuous by a fresh-context verifier's mutation
testing: (1) swapping the silent `> "$slog"` redirect back to `| tee "$slog"` flipped C2/C4/C3-contrast/C5
to FAIL (leak detected); (2) removing the `CAPTURE_TOKENS` trigger flipped C1/C2/C4/C3/C5 to FAIL.
Both mutations restored; suite green.

## Run table

```
$ bash tests/test-token-capture.sh
PASS C1 capture-correctness: TOKENS line == child assistant totals (in=1200 out=80 cache_read=8000 cache_create=0); result line not double-counted
PASS C1 capture-from-file: recorded usage == sum-usage(child.jsonl) (in=1200 out=80 cache_read=8000 cache_create=0)
PASS C2 conductor-stays-lean: child transcript in child.jsonl, ABSENT from conductor stdout
PASS C4 fd1-rigorous: transcript sentinel absent from the conductor's fd1 (leanness proven, not merged-capture)
PASS C7 default NC: no stream-json child file, NO TOKENS line (honest usage=?, default invocation intact)
PASS C3 false-bloat NC: --stream (tee) PUTS the child transcript in the conductor stdout (bloat proven)
PASS C3 contrast: stream-to-FILE leaves the conductor lean while --stream bloats; BOTH record the same TOKENS (in=1200 out=80 cache_read=8000 cache_create=0)
PASS C5 env parity: CAPTURE_TOKENS=1 env records TOKENS + keeps the conductor lean (flag is sugar over the global)
PASS C6 flag accepted: --capture-tokens parses (not rejected) + shows its dry-run advisory
ALL PASS
```

## COVERAGE-DELTA

**Covered:** C1 capture-correctness (+ result-line-not-double-counted) · C2 conductor-lean ·
C3 false-bloat NC (tee-vs-redirect contrast) · C4 fd1-rigorous · C5 env-parity · C6 flag-accepted ·
C7 default-NC (`usage=?`).

**Explicitly UNcovered (with reason):**
- **Wave-path per-sub-goal ledger extraction** , `_wave_run` has no token hook and never did (SPEC-110
  captured only on the serial path). Under `CAPTURE_TOKENS=1` the wave subshell STILL writes each
  child's `.orchestrate/<id>.stream.jsonl` lean-to-file (the global inherits on fork), so only the
  per-sub-goal extraction is deferred , single wiring point at `orchestrate.sh` reap loop (~L862),
  filed as the next increment. Dep-chained / `## Touches`-less mega-goals run the serial path anyway.
- **Watchdog-path capture** (`WATCHDOG_STALL_SECS>0`) , a pre-existing SPEC-110 gap; unchanged.
- **Live LLM run** , mock `CLAUDE_CMD` seam only (deterministic + free); no live `claude -p`.
- **stderr-redirect hardening** , the child's `--verbose` fd2 is not redirected away from the
  conductor (deferred; it would silence real errors on this opt-in path). C4 proves the fd1 transcript
  , the actual accumulation trap , is clean, which is the load-bearing property.

## Operator note (security)

`.orchestrate/<id>.stream.jsonl` holds the child's FULL plaintext transcript (already true for
`--stream`/`DETERMINISTIC_HANDOFF`; `.orchestrate/` is gitignored). `--capture-tokens` is meant to be
the routine delegate-run flag, so it widens how often this artifact is written to disk , do not run
sub-goals that touch live secrets under a capture flag without an appropriate scratch/cleanup posture.

## Gate ledger

Run `oh-02-token-capture`, lane `full`: grill(skipped) · think · design · design-critique ·
ui-design(skipped) · spec · validate · test-plan · build · review · docs · ship. Reviewed via
review-team (architecture + security, both PASS) + a fresh-context acceptance-verifier (8/8 PASS),
per SPEC-069 (a `lib/` touch uses multi-lens review).
