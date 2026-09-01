# Spec: Gauntlet stats, eval projection over the run-record corpus

Generated: 2026-09-01
Status: VALIDATED
Lane: normal
References: `commands/gauntlet.md` (QL-VERDICT grammar, rule 10 findings-graduation); `docs/verification/gauntlet/*/ROUNDS.md` (the corpus); `lib/telemetry/lane-telemetry.sh` (the existing ledger-projection idiom this mirrors); `_meta/BACKLOG.md` ID-494 (the source row); ID-496 (the A/B search-select loop this unblocks).

**Scope:** a read-only projection over records that already exist. No new store, no daemon, no schema change to any record. The corpus is the source of truth; the stats view is derived and disposable.

## Problem

Six gauntlet run records exist (one with a same-card sonnet/deepseek probe pair) and the corpus grows with every campaign pass, but the flywheel is unmeasurable: severity trajectory, rounds-to-SOLID, probe cost, and probe-model deltas live scattered across ROUNDS.md tables, QL-VERDICT markers, and omp transcripts. Nobody can answer "is the surface converging?" or "what does a probe round cost?" without hand-reading every record. ID-496 (surface A/B) is blocked on exactly this scoring.

## Solution

### Approaches considered

1. **`lib/gauntlet/stats.sh`, bash + jq, print a table + `--write` snapshot** (chosen).
2. Fold into the session-observe subsystem (ADR-0034): wrong owner; observe reads session transcripts, not verification records.
3. Python projection: heavier than needed; the kit's lib idiom is bash + jq and the parse targets are line-grep-able markers and JSONL.

### Chosen approach + why

A single `lib/gauntlet/stats.sh` that scans `docs/verification/gauntlet/` for record dirs (top-level `ROUNDS.md` / `*-ROUNDS.md` files only, never recursing into room contents such as `kit-extract/` or `fixture-repo/`), parses the QL-VERDICT markers plus the row/verdict tables, sums per-round token+cost from `transcript.jsonl` where present (omp v3 `turn_end.usage`), and prints one table. Operator picked the surface 2026-09-01: CLI verb + optional `--write` dated snapshot; print-only and report-only variants were declined.

### Extensibility & boundaries

- ID-496 consumes the same projection to score A/B variants; this spec ships the projection only.
- A future `gauntlet stats` wiring into `commands/gauntlet.md` is a doc row, not a new engine.
- Boundary: the script never writes into record dirs; `--write` output is a NEW dated file at the `docs/verification/gauntlet/` top level.

## Picture

```
docs/verification/gauntlet/
  <run-record>/ROUNDS.md ── QL-VERDICT markers ─┐
  <run-record>/*/transcript.jsonl ── usage ─────┼─► stats.sh ─► stdout table
  (gate ledger gauntlet entries, if present) ───┘        └─(--write)─► YYYY-MM-DD-stats.md
```

## Technical Design

### Interfaces (I/O contract)

- `bash lib/gauntlet/stats.sh` → a markdown table to stdout, one row per run record: record dir, date, preset/slug, rounds, findings trajectory (e.g. `3→1→0`), clean-at (round number or `-`), rows GREEN/total (campaign records), probe tokens (sum of `turn_end.usage` input+output across transcripts), probe cost (sum of `usage.cost.total`), probe model (from ROUNDS.md prose or `-`).
- `bash lib/gauntlet/stats.sh --write` → same table plus header/notes written to `docs/verification/gauntlet/$(date +%F)-stats.md`; refuses to overwrite an existing same-day file unless `--force`.
- Exit non-zero with a named error when a ROUNDS.md contains a malformed QL-VERDICT marker (report, never silently skip).
- Same-card probe-model deltas: when two records share a card/scenario (e.g. `user-J1` and `user-J1-nw`), print a second short "deltas" table comparing rounds/findings/tokens/cost.

### Data model changes

None. Read-only over existing files; the snapshot is a derived artifact.

### API / UI / Infrastructure changes

None.

## Task Breakdown

### Phase 1

- TASK-001: `lib/gauntlet/stats.sh` scanner + QL-VERDICT/table parser + usage summer + stdout table.
- TASK-002: `--write` snapshot + malformed-marker error path.
- TASK-003: deltas table for same-card record pairs.
- TASK-004: doc row in `commands/gauntlet.md` + `docs/MANUAL.md` (whatever surface lists gauntlet verbs).

## After state

- One command prints the whole corpus's convergence picture; every committed record dir under `docs/verification/gauntlet/` appears as a row.
- A dated snapshot can be committed alongside campaign records with `--write`.
- A malformed QL-VERDICT line is a loud error naming the file, not a missing row.
- ID-496 has its scoring input.

## Acceptance Criteria (global)

1. Live run against the real corpus lists every committed record dir (count derived from `ls`, never hardcoded).
2. Token/cost columns are populated for records whose rooms carry omp transcripts, `-` otherwise.
3. Negative control: corrupt one QL-VERDICT line in a scratch copy → the run fails loud naming that file; restore → green.
4. No writes outside the one `--write` target; record dirs untouched (verified by `git status`).

## Verification

```
bash lib/gauntlet/stats.sh                       # green: table, all record dirs present
bash lib/gauntlet/stats.sh --write               # snapshot lands, git status shows only it
# negative control on a scratch copy per AC-3
```

## Edge Cases

- Record dirs with per-row nested records (campaign passes) vs single-run records: both shapes parse; a campaign record's row-verdict table feeds rows-GREEN/total.
- `J3-ROUNDS.md`-style prefixed files in one dir count as separate runs.
- Transcripts in omp v3 event format only; unknown formats yield `-`, not a crash.
- The legacy `campaign-current` symlink is skipped (its target is already scanned).

## Out of Scope

- ID-496's A/B loop, any revision automation, any new store, gate-ledger writes, rewriting or normalizing existing records.

## Decision Log

- Surface: CLI verb + `--write` snapshot (operator, 2026-09-01).
- Owner lib, not session-observe: observe owns session transcripts, verification records own this.
- bash + jq over Python: matches lib idiom; parse targets are greppable markers + JSONL.

## Open questions

None blocking; findings-graduated-to-Tier1 count (rule 10) ships only if the markers prove greppable from ROUNDS.md prose, else it lands as a `-` column with a note.
