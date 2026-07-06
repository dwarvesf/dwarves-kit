# Proof of done: orchfin-03-wave-tokens (ID-094)

## Acceptance criteria

| # | Criterion | Met | Evidence |
|---|---|---|---|
| 1 | Wave (parallel) reap path captures per-sub-goal TOKENS, same as serial | yes | Run-table: both SG-01/SG-02 TOKENS lines land in a 2-sub-goal wave |
| 2 | Serial + wave paths write via the identical extraction (no drift) | yes | Shared `_record_tokens` helper called from both call sites |
| 3 | Negative control: pre-fix-equivalent code produces ZERO wave TOKENS lines (causal, not just presence) | yes | `NC_SKIP_WAVE_TOKENS=1` run: same mock, same child.jsonl, 0 TOKENS lines |
| 4 | Serial path's existing token capture unchanged | yes | `tests/test-token-capture.sh` 9/9 PASS unmodified |
| 5 | Green under macOS bash 3.2 (CI) and bash 5 | yes | Both suites run under `/bin/bash` and `bash`, both green |

## Implementation

`lib/queue/orchestrate.sh`:
- New `_record_tokens <dir> <id> <slog>` helper (beside `_rid_for`): the SPEC-110 extraction
  (`handoff_gen.py sum-usage` -> `gate-ledger.sh tokens`), factored out so serial and wave share one
  copy. Serial call site refactored to use it (behavior-preserving).
- `_wave_run`'s reap loop success branch (box flipped, `shipped` emitted) now calls
  `_record_tokens "$megadir" "$id" "$megadir/.orchestrate/${id}.stream.jsonl"`, gated on
  `CAPTURE_TOKENS=1 || DETERMINISTIC_HANDOFF=1`. The slog path is RECOMPUTED (deterministic, same
  expression `_run_one_session` uses internally) rather than threaded back from the forked subshell
  that backgrounds `_run_one_session` on the wave path, since its `_ROS_SLOG` global cannot cross
  the fork back to the reap loop.
- `NC_SKIP_WAVE_TOKENS=1` test-only escape hatch on the same call site, used only by the new test's
  negative control.
- Optional trivial cleanup: fixed the stale "WAVE_CAP default 1" comment in the `_wave_gate`
  docstring and the CAPTURE_TOKENS header block (the live default was already `WAVE_CAP=2`, matching
  `commands/mega.md`; three deeper narrative comments elsewhere left untouched, see impl-notes).
- New test: `tests/test-wave-token-capture.sh` (positive 2-sub-goal wave + negative control).

## Run detail (2-sub-goal-wave token run-table)

```
$ bash tests/test-wave-token-capture.sh
PASS wave-token-capture POSITIVE: both wave sub-goals' TOKENS lines recorded (SG-01='in=1200 out=80 cache_read=8000 cache_create=0' SG-02='in=1200 out=80 cache_read=8000 cache_create=0')
RUN-TABLE (wave token capture, positive):
  SG-01 rid=wave-tok-sg-01: 2026-07-05T20:33:04Z | TOKENS | in=1200 out=80 cache_read=8000 cache_create=0
  SG-02 rid=wave-tok-sg-02: 2026-07-05T20:33:04Z | TOKENS | in=1200 out=80 cache_read=8000 cache_create=0
PASS wave-token-capture: each sub-goal's ledger usage == sum-usage of ITS OWN child.jsonl (no cross-sub-goal mixup)
PASS wave-token-capture NEGATIVE CONTROL: pre-fix-equivalent code (extraction stubbed) writes the SAME child.jsonl files but ZERO wave TOKENS lines -- causal effect demonstrated
----
ALL PASS
```

Byte-identical result (modulo timestamp) under `/bin/bash` (macOS system bash 3.2.57); stable across
3 repeat runs on each bash version.

## Regression sweep

| Test | bash 5 | bash 3.2 |
|---|---|---|
| `tests/test-token-capture.sh` (serial path) | 9/9 PASS | 9/9 PASS |
| `tests/test-orchestrate-wavefront.sh` | 104 PASS, 0 fail (idle host) | 101 PASS, 0 fail (idle host)* |

\* Pre-existing FIFO-barrier flake (`wave_run g`/`h2`, `BARRIER_T=4`) under host load; reproduced
identically on unmodified `origin/master` with zero diff applied (twice), so it predates and is
independent of this change. See `docs/verification/orchfin-03-wave-tokens.md` for the full
reproduction and `docs/implementation-notes/orchfin-03-wave-tokens.md` for the deviation log.

## Dropped scope (per contract)

The original item's "reconcile the WAVE_CAP default" half was dropped: the live default
(`orchestrate.sh` `WAVE_CAP=2`) already agrees with `commands/mega.md`'s documented default. Only
stale internal comments claiming "default 1" existed; the ones adjacent to code this sub-goal
touched were fixed as the contract's optional trivial cleanup.

## Reproduce

```bash
bash tests/test-wave-token-capture.sh
/bin/bash tests/test-wave-token-capture.sh
bash tests/test-token-capture.sh
```
