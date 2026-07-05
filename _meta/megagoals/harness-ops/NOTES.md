# NOTES, harness-ops

## Active blockers

<none yet>

## Proposed additions

- 2026-07-06: after Track A lands, consider promoting the config as the default runtime knobs across ALL env-var call sites (a sweep), not just ledger/mega, discovered while scoping 02/03.
- 2026-07-06 (advisor P6): a permanent CI lint asserting NO hot-path hook sources kit-config.sh (grep hook dirs for `kit_config_get`/`source.*kit-config`) , the hybrid-read contract is load-bearing for every later sub-goal; without a standing lint it regresses the moment someone wires a hook to a new knob. HIGH.
- 2026-07-06 (advisor P6): a two-way schema-reality test , every `[impl]` key in kit.toml has a `kit_config_get` call site AND every live `kit_config_get` has a schema entry. 08 only proves inert keys stay inert; this catches the opposite drift (an `[impl]` key gone dead, a live read with no schema). HIGH.
- 2026-07-06 (advisor P6): sweep ALL adopted consumer repos (dfoundation, console-labs, ...) for `$DWARVES_KIT/lib/` deep-path refs, not just ops-toolkit's board , 05's proof only covers the board, but the board-break is a CLASS; file a follow-up/backlog row per repo found. HIGH.
- 2026-07-06 (advisor P6): a rollback-tested revert path for 12-root-slim (per-file "revert this commit + rerun full suite"), cheap given the per-file commit split already planned, high blast-radius item. MED.
- 2026-07-06 (advisor P6): turn 07's doc-vs-code check into a STANDING CI test , a "cold adopt" run on a scratch project diffing injected files vs consumer-contract.md , so the contract can't silently drift from adopt.sh. MED.
- 2026-07-06 (advisor P6): enforce 13→09/11 with a PR check that FAILS if `docs/proof/` or `docs/runs/` still exists at merge time (belt-and-suspenders on the Depends-on fix). MED.

## Event log

2026-07-06 · scaffolded · harness-ops, 13 sub-goals across 2 tracks (A config-layer 8, B docs-restructure 5). 01-config-resolver already BUILT (c84cda5 on feat/config-layer). Track A design: docs/specs/DECISION-BRIEF-config-layer.md; Track B design: the 2026-07-06 docs+root audits.
2026-07-06 · advisor pre-launch · P5 critique + P6 over-suggest. P5: 1 CRITICAL (install.sh has no docs/ copy step , goal 12 root-slim would 404 every installed consumer's WORKFLOW/MANUAL/CHANGELOG pointer; FIXED , 12 now requires the install-copy step + an installed-stub test) + 3 MAJOR (cross-track lib/adopt.sh collision 05↔12 , noted + sequenced; goal 13 Depends-on said "none" vs prose "after 09/11" , FIXED to `09, 11`; goal 12 undercounted readers , FIXED with a mandatory repo-wide grep + prose dangling-check) + 1 MINOR (brief named a nonexistent lint file , FIXED to test-install-modules.sh). NO flat-lib-path bug (subdir paths correct this time). P6: 6 suggestions → ## Proposed additions. Scaffold now launch-ready.
