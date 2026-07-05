# Sub-goal 02: token capture under delegation (stream-to-FILE, conductor stays lean)

**Merge policy:** auto
**Time budget:** 4-6 hours (the reconciliation is the hard part , the design-bearing sub-goal).
**Proof:** run-table with COVERAGE DELTA: a delegated `claude -p --stream > child.jsonl` run writes the child stream to a FILE · usage (input/output/cache tokens) is EXTRACTED from that file and recorded to the token ledger (kit-face SG-03 `TOKENS` marker) · the conductor reads ONLY the box-flip / terse result (NOT the child stream) · FALSE-BLOAT NEGATIVE CONTROL: a run that pipes the child `--stream` TO the conductor is shown to bloat the conductor context (the anti-pattern this sub-goal forbids), while the stream-to-FILE path leaves the conductor lean · the recorded usage matches the child's own totals (capture correctness). A COVERAGE-DELTA row names covered + uncovered.
**Depends on:** 01.
Model: opus
Effort: high
**Branch:** feat/oh-02-token-capture
**PR base:** feat/oh-01-model-routing

## Outcome

Reconcile the token ledger (kit-face SG-03) with the plain-`-p` delegate rule. Token capture needs `--stream` (usage lives in the stream-json), but ADR-0032's hard rule forbids `--stream` piped TO THE CONDUCTOR (that dumps the child transcript into the parent , the exact accumulation trap). The resolution (ADR-0032 section 3): the delegated child runs `claude -p --stream > child.jsonl`, usage is extracted FROM the file, the token ledger records it, and the CONDUCTOR reads only the box-flip / terse result , never the stream. Both hold: token capture works AND the conductor context stays lean. This sub-goal builds that path and OVER-TESTS the two properties that make it correct: usage-captured-from-file, and conductor-stays-lean (with a negative control proving the stream-to-conductor anti-pattern would bloat it).

## Quality bar

The two properties are BOTH load-bearing and BOTH tested: (1) usage is faithfully extracted from the child FILE (capture correctness vs the child's own totals), and (2) the conductor context stays LEAN , the child stream never reaches the parent. The false-bloat NC (piping `--stream` to the conductor demonstrably bloats it) is what proves the design is not cosmetic. REUSE the kit-face `TOKENS` marker convention (do not invent a second capture shape); if it disagrees with ledger-observatory's canonical schema, defer to that schema (NOTES).

## How to close the loop

`/spec` + `/spec-validate` first (design-bearing , write a `## Design` block: the stream-to-file path, where the file lives + lifecycle, the usage-extraction, how the conductor stays lean). Then `/kit:test-plan` + `bash tests/test-token-capture.sh`: a delegated stream-to-file run records usage matching the child totals, the conductor sees only the terse line, and the false-bloat NC shows stream-to-conductor would bloat the parent. Capture the COVERAGE-DELTA row. Assumptions: ROADMAP 02 + ADR-0032 section 3.

**Done =** a delegated `claude -p --stream > child.jsonl` run records faithful usage to the kit token ledger, the conductor reads only the box-flip (stays lean), the false-bloat NC proves stream-to-conductor is the forbidden bloat path, the COVERAGE-DELTA row is recorded, tests green.

## Scope edges

**In:** the stream-to-FILE delegate path, the usage-extraction from `child.jsonl`, the token-ledger record (reusing the kit-face `TOKENS` marker), the conductor-stays-lean guarantee, tests + coverage-delta.
**Out:** the model routing (01); the TIER-4 close (03); the panes (04); the docs (05).
**Not:** piping `--stream`/`--verbose` to the conductor (the forbidden bloat path , the NC guards it); inventing a second token-marker convention (reuse kit-face SG-03); rebuilding the token ledger itself (this feeds it under delegation).

## Where to look

`lib/orchestrate.sh` (the delegate dispatch , where the stream-to-file wraps the `-p` call), `lib/gate-ledger.sh` (`tokens` subcommand , the `TOKENS` marker producer), kit-face SG-03 (the token ledger it reconciles against), ADR-0032 section 3 (the stream-to-FILE resolution), `lib/lane-telemetry.sh` (how usage is surfaced), the research note section 5 (the TENSION -> stream-to-FILE reconciliation).

## PR body

Token capture under delegation: the delegated child runs `claude -p --stream > child.jsonl`, usage is extracted from the FILE and recorded to the kit token ledger (SG-03 `TOKENS` marker), and the conductor reads only the box-flip , token capture works WITHOUT dumping the child transcript into the conductor. Executes ADR-0032 section 3. Stacked on #<01's PR>; review after it. Verify: `bash tests/test-token-capture.sh` (usage-from-file capture correctness + conductor-stays-lean + false-bloat NC) + coverage-delta. Roadmap: ops-toolkit `_meta/megagoals/orchestrate-hardening/ROADMAP.md`.

## Notes

<empty>
