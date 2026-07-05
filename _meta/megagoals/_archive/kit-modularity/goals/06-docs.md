# Sub-goal 06: docs (philosophy + README + per-module usage-doc audit)

**Merge policy:** auto
**Time budget:** 3-4 hours of loop work
**Proof:** doc-diff + an AUDIT table, a first-adopter README that leads with "install the spine, opt into modules"; a PHILOSOPHY carrying the toolbox-not-appliance framing; AND a completeness audit proving EVERY installable/fireable module has a co-located usage doc (the F-bar doc half), a table of module → doc path → firing point, with zero gaps (or each gap explicitly justified). Named NC: pick a module, delete its usage doc, confirm the audit FLAGS it. Rung 2.
**Design:** obvious (docs to a settled surface; the audit is a checklist)
**Depends on:** 01, 02, 03, 04 (describes the settled surface); parallel to 05
Model: sonnet
**Branch:** docs/kitmod-06-docs
**PR base:** master (rebased after 04)

## Outcome

The kit's docs match its new adoption model. **PHILOSOPHY:** the composable-middle-level framing (bash-first + shallow-and-wide as a stated choice; a TOOLBOX you install a-la-carte, NOT an appliance you switch on; essential spine vs opt-in modules; git-as-only-shared-medium; team-mode named as parked-not-absent), with the explicit anti-goal that the kit must never feel like one big product. **README:** rewritten for a first-time adopter who wants ONLY the SDD spine and can stop there, leading with the standalone `<subsystem>` commands + the install model. **Per-module usage docs (F-bar audit):** every installable/fireable module has a co-located usage doc; SG-06 AUDITS all modules and closes any doc gap (the firing-point half was checked per-module in 01/02/03).

## Quality bar

A first-time reader can install the spine and stop, or opt into exactly what they want, the docs make the a-la-carte model obvious. The philosophy reads as a philosophy, not a feature list, and states the anti-goal plainly. No important module is undocumented, the audit table is the proof, one row per module.

## How to close the loop

- Rewrite PHILOSOPHY with the toolbox-not-appliance framing + the anti-goal + team-mode-parked line.
- Rewrite README lead: standalone commands + "install spine, opt into modules" + a one-command core install respecting the manifest.
- Build the F-bar doc audit: enumerate every installable/fireable module (from SG-01..04), map each to its co-located usage doc + its firing point; close gaps (write the missing usage docs, calibrated to `ops-tool-docs` shape, real usage, not template fill).
- NC: delete one module's usage doc → the audit flags the gap.

Kit-adopted: record docs + verify via `bash lib/gate-ledger.sh`.

**Done =** PHILOSOPHY + README reflect the toolbox model, and the F-bar audit table shows every installable/fireable module has a co-located usage doc + firing point (zero unjustified gaps), captured in `docs/proof/kitmod-docs.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-07 (the last one) reconciles the scaffolders; docs are done.
3. DECISIONS.md: only if a doc surfaced a real surface inconsistency to fix.
4. Report in records, EXIT.

## Scope edges

**In:** PHILOSOPHY, README, the per-module usage-doc audit + any missing usage docs.
**Out:** `AGENTS.md`/`WORKFLOW.md` (SG-05); the scaffolders (SG-07); code.
**Not:** a marketing rewrite; documenting Decision H; per-internal-helper manuals (only installable/fireable modules).

## Where to look

kit `README.md` + `PHILOSOPHY` + per-module docs, the merged SG-01..04 surface, `ops-tool-docs` skill shape, design note Decision D + F.

## PR body

Docs refresh to the toolbox-not-appliance model: PHILOSOPHY (a-la-carte, anti-goal stated) + a first-adopter README + the F-bar per-module usage-doc audit (every installable/fireable module documented).

Verify: doc-diff + the audit table (zero unjustified gaps) + delete-a-doc NC. Proof: `docs/proof/kitmod-docs.md`. Stacked on #<SG-04>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes
