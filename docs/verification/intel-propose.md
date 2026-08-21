# Proof of Done: session-intel propose

**Feature:** session-intel's two detectors reach the Learn gate as `## [staged]` blocks instead of prose nobody can promote (SPEC-200 T6 / I1).
**Date:** 2026-07-15 · **Lane:** normal · **Host:** dev laptop (macOS 26.5)

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `propose` stages a merge candidate (synthesis) as a `## [staged]` block with a citation | SPEC-200 I1 |
| A2 | `propose` stages a repeated-sequence candidate (repeat-detect) the same way | SPEC-200 I1 |
| A3 | The output points at the human gate (`learn drain` / `board promote`) | propose-don't-dispose |
| A4 | Re-running stages nothing new (deduped against staging + board) | idempotence |
| A5 | `--dry-run` prints the blocks and writes NO file | NEGATIVE CONTROL |
| A6 | `propose` never touches the board (byte-identical, sha256) | NEGATIVE CONTROL |
| A7 | The digest still prints the prose (the reading surface is unchanged) | no regression |

## Implementation

| Piece | What | Where |
|---|---|---|
| Rendering | the SAME detectors -> candidate dicts -> `staging-format.render_block` (the ONE renderer) | `cmd_propose()` |
| Dedup | `existing_keys(staging, board)` over every staging state + the board | same |
| Write | append-only to the staging buffer; `--dry-run` writes nothing | same |
| Tests | fixtures + 4 new assertions incl. 2 negative controls | `tests/smoke.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Full smoke (A1-A7) | `bash lib/session/intel/tests/smoke.sh` | `smoke: all 15 passed` | PASS |
| Staged with citation (A1/A2) | items 9 | blocks + `- Source: session intel <date> \| synthesis` / `\| repeat-detect` | PASS |
| Human gate named (A3) | item 9 | output contains `board promote` | PASS |
| Idempotent (A4) | item 10 | re-run leaves the block count unchanged | PASS |
| NEGATIVE CONTROL dry-run (A5) | item 11 | prints blocks, creates no file | PASS |
| NEGATIVE CONTROL board untouched (A6) | item 12 | board sha256 identical before/after | PASS |
| Digest unchanged (A7) | item 5 | the dated digest still carries all 5 sections | PASS |

## Run detail

```
$ bash lib/session/intel/tests/smoke.sh
...
[9] propose: synthesis + repeat land as ## [staged] blocks
  ok: merge candidate staged with a citation
  ok: repeat sequence staged with a citation
  ok: propose points at the human gate
[10] propose is idempotent (dedup vs staging + board)
  ok: re-run stages nothing new (1 blocks)
[11] NEGATIVE CONTROL: --dry-run writes nothing
  ok: dry-run prints blocks
  ok: dry-run wrote NO file (NEGATIVE CONTROL)
[12] NEGATIVE CONTROL: propose NEVER writes the board (propose-don't-dispose)
  ok: board byte-identical after propose

smoke: all 15 passed
Exit: 0
Verdict: PASS
```

Live run against the real baseline audit report (2026-07-15), proving the loop closes end to end:

```
$ bash lib/session/session.sh audit triage --dry-run | head -5
## [staged] Split the 7 mega-sessions at natural task boundaries (/clear + handoff skill)...
- Intent: directionally large, est. 40-60% cache-read reduction for these 7 sessions
- Approach: ... · metric cache_read_input_tokens per session now 1,185.4M across 44 sessions; re-run: jq -s ...
- Tags: #u-mid #f-mid
- Source: session audit 2026-07-15 | report=audit-2026-07-15.md owner=user-habit finding="..."
Exit: 0
Verdict: PASS
```

## Reproduce

```bash
cd <dwarves-kit>
bash lib/session/intel/tests/smoke.sh
bash lib/session/session.sh intel propose --dry-run
```
