# Sub-goal 12: root-slim

**Merge policy:** auto
**Time budget:** 3-5 hours
**Proof:** run-table showing each of the 3 files repointed and its readers still resolving the bulk at the new path + the full suite green (the gate machinery still parses WORKFLOW; test-meta still parses MANUAL; ship still reads CHANGELOG). Rung 2 + a negative control per file (a reader pointed at the OLD root path would now fail, proving the repoint is real). Design-bearing.
**Design:** bearing
**Depends on:** none (Track B, standalone; highest-risk B item)
Model: sonnet
**Branch:** fix/harness-ops-12-root-slim
**PR base:** main

## Outcome

The 3 giant machine-parsed root files stop overwhelming a newcomer WITHOUT breaking the machinery that parses them. For each of `WORKFLOW.md` (1260 ln), `MANUAL.md` (589 ln), `CHANGELOG.md` (549 ln): a THIN human-facing stub stays at root (intro + a pointer), the BULK moves into `docs/`, and every code reader is repointed to the new bulk path. The root reads welcoming; the gate/test machinery is unaffected.

## Design

Design-bearing: WHERE the bulk lands + HOW the stub/pointer is shaped is a real choice, and the blast radius is large (runtime gate parsing). The spec's `## Design` names, per file: the new bulk path, which readers repoint, and the stub contract. Do the 3 files as SEPARATE commits within the PR so a break is bisectable. Readers to repoint (from the 2026-07-06 root audit): WORKFLOW → `lib/gate/gate-ledger.sh`, `lib/gate/dispatch-gate.sh`, `lib/gate/proof-table-gen.py`, `install.sh`, `lib/adopt.sh`; MANUAL → `tests/test-meta.sh`, `commands/draft-agent.md`; CHANGELOG → `commands/ship.md`, `commands/kit-health.md`, `commands/dispatch.md`.

## How to close the loop

- Per file: move the bulk to `docs/<name>.md` (or a `docs/` home), leave a thin root stub pointing at it, repoint EVERY reader listed above (grep to confirm none missed).
- Run the FULL suite (`tests/`) , especially test-meta (MANUAL parse), the gate tests (WORKFLOW parse), ship/kit-health (CHANGELOG). All must stay green.
- Negative control per file: point a reader at the old root bulk path, assert it now fails (proving the bulk really moved + the repoint is load-bearing).
- Capture the run-table (suite green + the 3 repoints).

**Done =** each of WORKFLOW/MANUAL/CHANGELOG is a thin root stub + bulk-in-docs with every reader repointed, the FULL test suite is green, and the per-file negative control proves the repoint is real (captured run-table).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `bash lib/classify/lane-classify.sh classify "..."` → full; record via `bash lib/gate/gate-ledger.sh`).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → 13; append DECISIONS.md (note this was the highest-risk B item + how the repoints were verified); report; EXIT.

## Scope edges

**In:** the 3 root files' bulk + stub, and their code readers.
**Out:** the OTHER root essentials (README/LICENSE/CLAUDE.md/AGENTS.md/install.sh/tool.toml/VERSION), the parsed CONTENT (only its location moves).
**Not:** moving AGENTS.md/CLAUDE.md (plugin/adopt-pinned), changing WORKFLOW's matrix, a docs framework.

## PR body

Slims the 3 giant machine-parsed root files (WORKFLOW/MANUAL/CHANGELOG) to thin root stubs + bulk-in-docs, repointing every code reader (gate-ledger, dispatch-gate, test-meta, ship, adopt, ...). The newcomer-welcoming-root win, done without breaking the machinery. Verify: full suite green + per-file repoint NC (run-table). Part of `harness-ops` (Track B), see ROADMAP.md.

## Notes
