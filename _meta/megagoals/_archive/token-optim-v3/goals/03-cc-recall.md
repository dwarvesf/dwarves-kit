# Sub-goal 03: cc-recall

**Merge policy:** auto (ops-toolkit-owned tool, machine-verifiable)
**Time budget:** ~1 session
**Proof:** run-table , a recall query returns a known-present decision from a seed transcript
(structure-preserving, grouped by turn), and a negative control (absent term) returns nothing.
**Depends on:** SG-01 (shares the JSONL parser; same repo, may stack)
**Branch:** `feat/v3-cc-recall`
**PR base:** SG-01's branch if unmerged, else ops-toolkit `main`

## Outcome
A read-only recall CLI searches the raw `~/.claude/projects/*.jsonl` transcripts directly (pi-vcc's
`vcc_recall`), returning structure-preserving results grouped by conversation turn with match
indicators, so a session can retrieve a prior decision without re-reading files or repeating work,
even across compactions.

## Quality bar
Lossless: nothing is ever permanently discarded because the raw JSONL is the source. Results are
grouped by turn so a hit carries its context, not a naked line. Fast enough to run mid-session
without thinking about it.

## How to close the loop
```
# in tools/cc-recall/ (new ops-toolkit tool)
cc-recall "the decision about X" --project <slug>     # turn-grouped matches with indicators
cc-recall "string-that-does-not-exist-zzz"; echo "exit=$?"   # empty, clean exit
```
Capture a run-table: known-decision query hits the right turn; negative control empty; latency
(< a second or two on a real project's transcripts).

**Done =** `cc-recall` returns the known-present decision from the seed transcript grouped by turn,
returns empty on the negative control, and the run-table records both plus the latency.

## Scope edges
**In:** a new `tools/cc-recall/` read-only CLI reusing SG-01's parser; `tool.toml` + README +
proof-of-done per the ops-toolkit tool standard.
**Out:** compaction (SG-01), handoff (SG-02), interactive command (SG-04). Read-only: never mutates
transcripts.
**Not:** an embedding index (this is structure-preserving grep over JSONL; `prose-rag` already does
semantic search, do not duplicate it); a daemon; cross-project fuzzy ranking. Keep it lazy.

## Where to look
pi-vcc `vcc_recall` (structure-preserving search over raw session JSONL). SG-01's parser. Existing
`cc-observe` (transcript parsing) and `prose-rag` (so we do NOT duplicate semantic search).
ops-toolkit tool standard: `tools/tide/` shape, `ops-tool-shape` skill.

## PR body
feat(cc-recall): lossless turn-grouped recall over Claude Code transcripts (ports pi-vcc
vcc_recall). Read-only. Verification: run-table (known-hit + negative control + latency).
token-optim-v3 sub-goal 03.

## Notes
