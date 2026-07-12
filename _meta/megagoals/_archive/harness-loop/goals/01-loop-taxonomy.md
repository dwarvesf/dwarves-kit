# Sub-goal 01: loop-taxonomy

**Merge policy:** gate
**Time budget:** 2-4 hours of loop work
**Proof:** the ADR file itself + a recorded advisor P5 critique pass (findings applied or dispositioned) + a grep-audit table proving every name the ADR locks has zero pre-existing collisions. Ladder rung 2 (doc, but load-bearing: named negative check = the collision grep). No screenshots.
**Design:** bearing
**Depends on:** none
Model: opus
**Branch:** `docs/loop-01-taxonomy`
**PR base:** master

## Touches

docs/decisions/, docs/research/2026-07-05-harness-ops-loop-and-naming.md (reference only, not edited)

## Outcome

ADR-0034 "harness-loop taxonomy" exists and is APPROVED by Han. It opens with a full SURFACE CENSUS (every `bin/` entry, every `SKILL.md` location, every shipped plist/deploy template, every subsystem lacking a bin entry) and a TARGET-STATE table per surface, so the taxonomy is a consolidation plan, not additive naming. It locks, with one decision record each: (1) the `learn` subsystem (`lib/learn/` + `bin/learn` verbs `propose|drain|debt`), what physically moves into it (weekend-batch) and what stays put (harvest/backlog-stage hooks stay capture-side in their modules); (2) the retro-vs-propose vocabulary rule (one word, one meaning; `/kit:retro` per-run, `learn propose` cross-run; the recurring goal keeps its drafted `kit-retro-YYYY-WW` name); (3) legs-as-metadata: a module→primary-leg table (Specify/Execute/Observe/Govern/Learn), modules keep their install names, the two honest spanners (board, session) documented as such; (4) front-door verb fences: start=detector, adopt=mechanical injector, onboard=interactive orchestrator, config=read/explain surface; (5) the `-propose` role suffix added to the 2026-07-05 naming vocabulary (a propose-only writer whose ONLY legal sink is a staging file); (6) scope fences restated per the kit-fold contract (engine kit-side, LaunchAgent/boards/cockpit consumer-side, no tenant mentions); (7) bin/ consolidation per brief §4.7: one `bin/<subsystem> <verb>` grammar, the five `session-*` CLIs collapse to `session <verb>`, `add-backlog` folds as `board promote` (deciding the 2026-07-05 doc's deferred question), missing subsystem entries (spec, goal, stats, mega, queue) created, module CLIs stay module-named (the two-class rule stated); (8) the kit-skill rule per brief §4.8 (what earns `skills/`, where the stats skill lives); (9) the one-scheduler decision per brief §4.9 (single weekly LaunchAgent + declarative jobs list; per-job plists retire); (10) ledger retention position: append-only stands (SPEC-097/182 discipline), revisit only at a MEASURED size threshold named in the ADR, never silent rotation.

## Quality bar

Reads like ADR-0024: short, decided, each section says what was rejected and why. A name that survives this ADR never needs renaming in sub-goals 04-10; if a later sub-goal wants to deviate, the ADR was wrong and gets amended, not ignored.

## How to close the loop

1. Draft `docs/decisions/0034-harness-loop-taxonomy.md` from brief §4 (working positions, to be attacked, not transcribed).
2. Collision grep-audit, recorded as a table in the ADR appendix: `rg -l 'bin/learn|lib/learn|learn propose|-propose' lib bin docs commands hooks` must show zero live-code collisions; `rg 'learn' kit.toml install.sh` shows only `learning_ledger`/`weekend_batch`.
3. Dispatch `kit:advisor` P5 on the draft (contradictions vs the brief, vs ADR-0031/SPEC-126/SPEC-183, names a worker could misread). Apply CRITICAL/MAJOR; record the pass.
4. Open the PR, record gates (`classify` will call this docs/full), emit the approval banner, STOP for Han.

**Done =** ADR-0034 committed with all six decision areas + the collision-audit appendix + advisor P5 recorded, PR open and HELD for Han's approval (the gate click IS the done signal).

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip this box in ROADMAP.md + record PR #. 2. Overwrite HANDOFF.md: this gate unblocks 04 AND 08 (both depend only on 01); 02/03 were dispatchable all along; first action for 04 = read the APPROVED ADR §1 move plan. 3. Append locked names to DECISIONS.md. 4. Report in the records, then EXIT.

## Scope edges

**In:** the ADR file (census + target-state tables + the nine decision areas), the collision audit, one paragraph amending the naming-vocabulary section pointer.
**Out:** any code, any file move, any kit.toml edit (those are 04+); the census records reality, it changes nothing.
**Not:** renaming existing modules, re-opening SPEC-126's kit/skill split, designing the wizard UX (09's job).

## Where to look

The brief §4; `docs/research/2026-07-05-harness-ops-loop-and-naming.md` (the convention being extended); ADR-0031, SPEC-126, SPEC-182/183/184; `lib/queue/weekend-batch.sh` header; the kit-fold contract note in ops-toolkit repo memory.

## PR body

ADR-0034: harness-loop taxonomy (learn subsystem, retro/propose vocabulary, legs-as-metadata, front-door fences, -propose suffix). Decision record only, zero code. Verification: collision-audit appendix inside the ADR. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-01. GATED: needs Han's approval before SG-04/05/06/08/09 start.

## Notes

- 2026-07-12: `bin/classify lane classify` returned `normal` (the PR-body note guessed docs/full); gates recorded per the normal lane plan (spec/build/ship required).
- 2026-07-12: advisor P5 ran on the draft: 1 CRITICAL + 2 MAJOR + 3 MINOR, all applied or dispositioned (see NOTES.md ## Advisor dispositions). The goal file's "all six decision areas" undercount vs the Outcome's ten areas is treated as the superset: all ten are in the ADR.
