# Docs rewrite: requirements ledger

Requirements for the README, QUICKSTART and guides rewrite. Read this file before any task in the rewrite. One entry per line: `RL-NN · type · rule · scope · status`.

RL-01 · decision · The first reader is an outside engineer who uses Claude Code and has no Dwarves context; the Dwarves team reads second · scope: README, QUICKSTART, docs/guides · active
RL-02 · decision · Keep today's file paths; folder moves (concepts/, reference/) wait for the structure phase · scope: docs/ · active
RL-03 · decision · Figures come from one model, `docs/figures/MODEL.md`, rendered by `lib/system-design` into `docs/figures/<id>.png`; no hand-drawn SVG, no mermaid, no ASCII box diagrams in README or guides · scope: README, QUICKSTART, docs/guides · active
RL-04 · quality-gate · `docs/figures/MANIFEST.tsv` holds each sheet's model hash; a test fails when a sheet changes without a re-render · scope: docs/figures · active
RL-05 · decision · Figures render in the light theme only; a dark variant waits until GitHub picture sources are worth the second render · scope: docs/figures · active
RL-06 · decision · Every guide uses one page shape: Use this when, figure, What happens, What you do, What you will see, When it breaks, Related · scope: docs/guides · active
RL-07 · decision · Merge guide pairs: spine absorbs lanes, mega-goal absorbs dispatch-vs-mega, gauntlet absorbs gauntlet-tutorial; the absorbed files are removed and every link to them is repointed · scope: docs/guides · active
RL-08 · decision · New guides: adopt, review, wrap · scope: docs/guides · active
RL-09 · quality-gate · No spec, ADR or board IDs in prose, no hardcoded counts, no operator-private detail (hosts, personal domains, vault paths), no em or en dashes · scope: all rewritten files · active
RL-10 · quality-gate · Every command, flag and path a doc names exists today; a doc-drift Tier 1 pass on the rewritten files finds zero FIX · scope: all rewritten files · active
RL-11 · audience-test · A gauntlet onboarding run passes using only README and QUICKSTART · scope: README, QUICKSTART · active
RL-12 · decision · Voice is STE-lite with plain everyday words, second person; README at most 150 lines, QUICKSTART at most 120, each guide 80 to 160 lines · scope: README, QUICKSTART, docs/guides · active
