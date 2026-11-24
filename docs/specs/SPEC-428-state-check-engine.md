# Spec: `board state-check`, a generic engine that checks the state values a repo stores against its own registry

Generated: 2026-11-25
Status: DRAFT
Lane: normal (one bounded feature: one new Python file, one verb line in `board.sh`, docs; no enforcement-surface path)
Depth: standard (the checker being ported was read in full, with every caller and its tests)
Type: spec-feature
File: `docs/specs/SPEC-428-state-check-engine.md`
References: `docs/briefs/DECISION-BRIEF-declared-state-machines.md`; `lib/board/states.tsv`; `lib/board/board.sh`; `lib/board/README.md`

## Problem

A consumer repo keeps a registry of every state machine whose value lives in a file (frontmatter, a TOML field, a table column), plus a checker that blocks NEW drift at commit and reports old drift. The checker was repo-local Python. Any repo with stored statuses wants the same guard, and a second copy would drift from the first.

## Rules

| # | Rule |
|---|---|
| R1 | One engine in the kit, `lib/board/state_check.py`, exposed as `bin/board state-check`. The kit holds no registry; the consumer repo keeps its own TOML file and calls the engine. |
| R2 | The registry path comes from `--states-file` (else `STATES_REGISTRY`, else `<repo-root>/_meta/states.toml`). The repo root comes from `--repo-root` (else `STATES_ROOT`, else the git root of the current directory, else the current directory). |
| R3 | Flags and exit codes are the old checker's: `--all [--strict]`, `--staged`, `--fix`; exit 0 clean, 1 blocked (or `--strict` with findings), 2 internal error or no mode flag. `ALLOW_STATE_CHANGE="<reason>"` turns a `--staged` block into exit 0. `STATES_BASE` compares the index against another commit. |
| R4 | Findings are byte-identical to the old checker's on the same repo: same report lines, same BLOCKED banner, same messages. The only strings that name the caller (the `--fix` hint, the internal-error prefix, the usage text) take the command name from `STATES_PROG` (default `board state-check`); the banner names the registry path relative to the repo root. |
| R5 | Python 3.9 works. Without `tomllib` the engine reads the registry with a built-in reader (tables, quoted or bare keys, strings, integers, booleans, arrays, inline tables) and reads a stored TOML file's top-level field line by line, so a store file may use any TOML. `STATES_TOML=mini` forces the built-in reader. A registry the reader cannot parse is exit 2. |
| R6 | The module stays importable: a wrapper can reuse `ROOT`, `REGISTRY`, `norm`, `classify`, `move_problem`, `values`, `parse_table`, `retoken`, `retoken_row`. |
| R7 | No tenant name in kit code or fixtures. The fixture registry is neutral. |
| R8 | The registry keeps its TOML shape. The board's own `states.tsv` (state, class, next) is advisory and permissive by decision; this engine blocks, so the two do not merge. |

## Solution

`state_check.py` is the old checker with three changes: the TOML reader (R5), root and registry resolution (R2), and the caller-naming strings (R4). The kit's own hooks do not run it; a consumer wires `bin/board state-check --staged` into its pre-commit hook and `--all --strict` into a periodic job.

```
 consumer pre-commit ──> bin/board state-check --staged ──> lib/board/state_check.py
 consumer weekly job ──> bin/board state-check --all --strict        │
                                                                     ├─ reads <repo>/_meta/states.toml (or --states-file)
                                                                     ├─ reads stored values from the index, HEAD and disk
                                                                     └─ prints findings, exits 0 / 1 / 2
```

## Technical Design

- `lib/board/state_check.py`: the engine; `# kit-verb: board state-check` header.
- `lib/board/board.sh`: one `state-check)` dispatch line (`exec python3`) and one usage entry.
- `tests/test-state-check.sh` with `tests/fixtures/state-check/states.toml`: the rules, both TOML readers, the arguments, the exit codes, the importable surface, a tenant-name scan, and a negative control per rule.
- Docs: `lib/board/README.md`, `docs/MANUAL.md`, `docs/reference/project-structure.md`, `docs/reference/workflow-paths.md`, `docs/reference/FEATURES.md` (generated), `CHANGELOG.md`.

### Out of scope

Replacing the consumer's own checker (a later step in that repo). Wiring the engine into any kit hook. Merging the registry shape with `states.tsv`.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: port the checker with the three changes | `lib/board/state_check.py` | AC1, AC3 |
| T2: wire the verb and register it | `lib/board/board.sh`, docs, `CHANGELOG.md` | `tests/test-registry-verbs.sh`, `tests/test-meta.sh` |
| T3: fixture suite with negative controls, parity proof | `tests/test-state-check.sh`, `tests/fixtures/state-check/`, `docs/verification/state-check-engine.md` | AC1 to AC4 |

## After state

A repo with a registry file runs `bin/board state-check` and gets the findings its old checker gave. The kit itself behaves as before.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 every ported rule blocks or passes as before, under both TOML readers | `tests/test-state-check.sh` Part 1 and 1b |
| AC2 registry and root arguments, exit codes, the importable surface | `tests/test-state-check.sh` Part 2 |
| AC3 old and new engine print the same stdout, stderr and exit code on a real consumer checkout and on planted drift | `docs/verification/state-check-engine.md` |
| AC4 negative control: break each rule in a copy of the engine and its case goes red | `tests/test-state-check.sh` Part 3 |

## Verification

```bash
bash tests/test-state-check.sh
PYTHON=/usr/bin/python3 bash tests/test-state-check.sh
bash tests/run-all.sh --changed
```
