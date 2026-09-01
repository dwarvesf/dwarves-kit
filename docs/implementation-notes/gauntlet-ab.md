# Implementation notes: gauntlet-ab (delta from SPEC-241)

## 2026-09-01 one engine change after all

Context: the spec's Scope said "no engine changes". The design critique found run-remote's remote path re-ships `git archive HEAD` as the artifact tarball, silently discarding the variant.
Decision: run-remote.sh now ships the caller's `GAUNTLET_SRC_TAR` when set (the harness copy still ships HEAD; only the artifact varies).
Impact: remote runners carry the variant. Without this the A/B measured sampling noise on any non-local runner.

## 2026-09-01 round verdict classes

The spec scored GREEN/RED only. Per the critique: checker exit 3 (BLOCKED) is card evidence, not variant evidence; a harness rc is infrastructure. Both are excluded from the tally, shown in the table, and HARNESS makes the driver exit non-zero. The verdict file (`ab-verdict.txt`) is the single source of truth per round and the resume key (run-remote pre-creates the round dir, so dir-existence was a corrupt resume key).

## 2026-09-01 winner needs a sweep

At small N a 2-1 lead is noise. Winner requires margin >= rounds-per-variant; a thinner lead is AB-WEAK (a tally, not a finding). Marker grammar gains `winner=weak`.

## 2026-09-01 plain tar, not tar.gz

GNU tar cannot auto-detect compression on a pipe (remote ship path); bsdtar can. Plain tar works on both.

## 2026-09-01 tiebreak duplicates the stats derivation

The token tiebreak re-states the dual-format usage derivation from `lib/gauntlet/stats.sh` (that script is an executable, not a sourceable library). Accepted duplication, two expressions; extract a shared lib only if a third consumer appears.
