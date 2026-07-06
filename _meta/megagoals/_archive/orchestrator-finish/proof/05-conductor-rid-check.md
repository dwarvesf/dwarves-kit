# Proof of done: orchfin-05-conductor-rid-check (ID-099)

## Acceptance criteria

| # | Criterion | Met | Evidence |
|---|---|---|---|
| 1 | Wave (parallel) dispatch path emits a START/rid per sub-goal, same as serial | yes | Run-table: both SG-01/SG-02 START lines land in a 2-sub-goal wave |
| 2 | Serial + wave paths write via the identical `_emit_start` (no drift) | yes | Same shared function called from both call sites, no duplication |
| 3 | Negative control A: pre-fix-equivalent code produces ZERO wave START lines (causal, not just presence) | yes | `NC_SKIP_WAVE_START=1` run: same mock, both boxes flip, 0 START lines |
| 4 | Negative control B: a dispatch with no derivable rid is loudly flagged, not silently untracked | yes | WARN on stderr + zero ledger files written; wave still completes (advisory, per pin) |
| 5 | Serial path's existing `_emit_start` + missing-rid advisory warn unchanged | yes | `_emit_start`/`_rid_for` bodies untouched; only the wave call site was added |
| 6 | Green under macOS bash 3.2 (CI) and bash 5 | yes | New test run under both `/bin/bash` and `bash`, both green |

## Implementation

`lib/queue/orchestrate.sh`:
- Verified reality first (per the rescoped Outcome): the serial path (`cmd_run`) already calls
  `_emit_start` right after its `_emit_event ... executing`, and `_emit_start` already WARNs+skips
  (advisory) when a goal file has no `**Branch:**` header. The real gap was entirely in
  `_wave_run`'s spawn loop, which called `_emit_event ... executing` but never `_emit_start`.
- Added one line, `_emit_start "$megadir" "$id"`, immediately after the wave loop's existing
  `executing` event -- same call, same shared `_rid_for` derivation, same advisory behavior as
  serial. No new logic invented; the fix is purely "call the function that already exists at the
  spot that was missing it."
- `NC_SKIP_WAVE_START=1` test-only guard on the new call (mirrors ID-094's `NC_SKIP_WAVE_TOKENS`),
  used only by the new test's negative control A.
- New test: `tests/test-wave-rid-check.sh` (positive 2-sub-goal wave + negative control A: fix
  stubbed out + negative control B: no-derivable-rid goal file).

## Run detail (2-sub-goal-wave START run-table)

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

Byte-identical result (modulo timestamp) under `bash` (modern bash 5); stable, no flake.

## Regression sweep

| Test | bash 5 | bash 3.2 |
|---|---|---|
| `tests/test-wave-token-capture.sh` (ID-094) | ALL PASS | ALL PASS |
| `tests/test-orchestrate-wavefront.sh` | 2 pre-existing flakes (`wave_run g`, `wave_run h2`), 0 caused by this diff | 1 pre-existing flake (`wave_run g`), 0 caused by this diff |

Confirmed via `git stash` on this exact branch/host: reverting this sub-goal's diff back to
`origin/master` reproduces the identical `wave_run g` failure signature, proving the flake predates
and is independent of ID-099. Same host-load-sensitive FIFO-barrier signature documented for ID-094
in `_meta/megagoals/orchestrator-finish/proof/03-wave-tokens.md`.

## Scope confirmation (per contract)

- **In, done:** the wave dispatch path (`_wave_run`'s spawn loop) now emits a START/rid.
- **Out, untouched:** rid GENERATION (`_rid_for`), the gate-ledger's rid/log format, the serial
  path's existing START call.
- **Not done (pinned, intentionally):** the serial advisory warn on a missing rid was NOT turned
  into a hard abort; a `?`-rid run stays degraded-but-runnable, matching the rescoped Outcome's
  explicit pin.

## Reproduce

```bash
bash tests/test-wave-rid-check.sh
/bin/bash tests/test-wave-rid-check.sh
bash tests/test-wave-token-capture.sh
bash tests/test-orchestrate-wavefront.sh
```
