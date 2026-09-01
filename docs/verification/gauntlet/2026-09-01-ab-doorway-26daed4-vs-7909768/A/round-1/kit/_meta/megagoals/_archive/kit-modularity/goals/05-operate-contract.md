# Sub-goal 05: operate-contract (AGENTS.md + WORKFLOW.md refresh)

**Merge policy:** auto
**Time budget:** 2-3 hours of loop work
**Proof:** run-table / doc-diff, a `kit:doc-verifier`-style pass (or a grep audit) confirming `AGENTS.md` + `WORKFLOW.md` reference NO stale surface (`ledger-observatory`, `bash tools/...`, the old install model, lib-vs-tools framing) and DO reference the new one (standalone `<subsystem> <verb>`, `stats`, layered install/`[modules]`, the module structure). Named NC: grep for each retired name across both files returns zero live references. Rung 2 (docs, but load-bearing, first thing an adopting agent reads).
**Design:** obvious (a targeted docs refresh to a known surface; no new component)
**Depends on:** 01, 02, 03, 04 (the surface must be settled)
Model: sonnet
**Branch:** docs/kitmod-05-operate-contract
**PR base:** master (rebased after 04)

## Outcome

`AGENTS.md` + `WORKFLOW.md` (the operate-contract / orchestration layer, what an adopting agent reads first: what to read, the lanes, the gate at each phase boundary, how the pieces compose) are refreshed to the new surface: standalone subsystem commands, `stats` (not `ledger-observatory`), the layered install + `[modules]` model, the retired lib-vs-tools framing. A stale operate-contract silently mis-drives every downstream run, this closes that gap.

## Quality bar

The first thing an adopting agent reads is accurate. No retired name survives; no removed flow is described; the new command surface + install model are correctly represented. Surgical, refresh what the modularity changes touched, don't rewrite the whole contract.

## How to close the loop

- Diff the modularity changes (SG-01..04) against what `AGENTS.md` + `WORKFLOW.md` currently say; list every stale reference.
- Update each: `ledger-observatory`→`stats`; `tools/`-path invocations → the module/standalone-command form; the old all-hooks install → the layered `--with` model; the lib-vs-tools framing → subsystem modules.
- Grep-audit: each retired token (`ledger-observatory`, `bash tools/`, old install phrasing) → zero live references in both files.
- If the repo has a `kit:doc-verifier`, run it against the two files.

Kit-adopted: record docs + verify via `bash lib/gate-ledger.sh`.

**Done =** `AGENTS.md` + `WORKFLOW.md` contain zero stale-surface references (grep-audited) and correctly describe the new command/install surface, captured in `docs/proof/kitmod-operate-contract.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-07 reconciles the scaffolders against this now-updated contract.
3. DECISIONS.md: note any contract flow that changed materially (not just a rename).
4. Report in records, EXIT.

## Scope edges

**In:** `dwarves-kit/AGENTS.md` + `dwarves-kit/WORKFLOW.md`.
**Out:** the README/philosophy (SG-06); the scaffolders (SG-07); code (SG-01..04).
**Not:** rewriting the whole operate-contract; changing lane/gate semantics; documenting Decision H (separate mega).

## Where to look

`dwarves-kit/AGENTS.md`, `dwarves-kit/WORKFLOW.md`, the merged SG-01..04 diffs, design note Decision D.

## PR body

Refresh the operate-contract (`AGENTS.md` + `WORKFLOW.md`) to the new surface: standalone subsystem commands, `stats`, layered install/`[modules]`, subsystem modules. Zero stale references.

Verify: grep-audit (retired tokens → zero live refs) + doc-verifier. Proof: `docs/proof/kitmod-operate-contract.md`. Stacked on #<SG-04>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes
