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

Design-bearing: WHERE the bulk lands + HOW the stub/pointer is shaped is a real choice, and the blast radius is large (runtime gate parsing). The spec's `## Design` names, per file: the new bulk path, which readers repoint, and the stub contract. Do the 3 files as SEPARATE commits within the PR so a break is bisectable.

Readers to repoint , this list is a STARTING POINT, NOT exhaustive (advisor P5): the audit named WORKFLOW → `lib/gate/gate-ledger.sh`, `lib/gate/dispatch-gate.sh`, `lib/gate/proof-table-gen.py`, `install.sh`, `lib/adopt.sh`; MANUAL → `tests/test-meta.sh`, `commands/draft-agent.md`; CHANGELOG → `commands/ship.md`, `commands/kit-health.md`. But a repo-wide grep finds MORE: WORKFLOW has ~30 refs incl. a FUNCTIONAL `lib/queue/orchestrate.sh:1357` no-orphan lint (scans WORKFLOW.md as a corpus), ~13 test files, and ~10 `commands/*.md` PROSE pointers; CHANGELOG's real readers include `commands/docs.md` (missed above), and `commands/dispatch.md` only mentions it in prose (not a parse target). The `commands/*.md` prose class is the dangerous one , a stale prose pointer produces NO test failure.

**CRITICAL (advisor P5): `install.sh` copies only `lib WORKFLOW.md AGENTS.md` to the install location (`install.sh:241`), NEVER `docs/`.** If you only repoint the stub without adding a `docs/`-bulk copy step to `install.sh`, every INSTALLED consumer (the real `$KIT_ROOT` path, not the dev checkout this loop runs from) gets a root stub pointing at a `docs/WORKFLOW.md` that was never copied → a 404 for every installed user, and NO current test catches it. The install-copy step + a test on the INSTALLED copy's pointer are mandatory, not optional.

## How to close the loop

- **MANDATORY reader discovery (P5 #4):** before touching anything, run `grep -rn 'WORKFLOW\.md\|MANUAL\.md\|CHANGELOG\.md' --include='*.sh' --include='*.md' --include='*.py' . | grep -v '^./WORKFLOW.md\|^./MANUAL.md\|^./CHANGELOG.md'` and repoint EVERY hit (the audit list is a starting point only). Do NOT trust the enumerated list.
- Per file: move the bulk to `docs/<name>.md`, leave a thin root stub pointing at the new path, repoint every discovered reader.
- **`install.sh` docs-copy (P5 #1, CRITICAL):** add a step so `install.sh` copies the new `docs/<bulk>` files to the install location alongside the stub (today it copies only `lib WORKFLOW.md AGENTS.md` at `:241`). Without this, installed consumers get a stub pointing at an uncopied `docs/` file (404).
- Run the FULL suite (`tests/`) , test-meta (MANUAL parse), gate tests (WORKFLOW parse incl. the orchestrate.sh:1357 no-orphan lint), ship/kit-health (CHANGELOG). All green.
- Negative control per file: point a reader at the old root bulk path, assert it now fails (repoint is load-bearing).
- **Installed-copy test (P5 #1):** a NEW test that runs `install.sh` into a temp `$KIT_ROOT` and asserts the installed stub's pointer RESOLVES (the bulk was copied), not just the dev-repo copy.
- **Prose dangling-ref check (P5 #4):** grep `commands/*.md` for stale root-path prose pointers (invisible to the test suite); assert none remain.
- Capture the run-table (suite green + install-copy test + the repoints).

**Done =** each of WORKFLOW/MANUAL/CHANGELOG is a thin root stub + bulk-in-docs with EVERY reader (grep-discovered, not just the audit list) repointed, `install.sh` copies the bulk so the INSTALLED stub resolves (new test green), the full suite is green, `commands/*.md` prose has no dangling root pointer, and the per-file negative control proves the repoint is real (captured run-table).

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
