# Proof of done: ceremony lens

Run 2026-09-30 in the `feat/ceremony-lens` worktree. All tests use temp fixture dirs; the live ledgers and `~/.claude/projects` were read only by the baseline run.

## Green suite

| Command | Exit | Result |
|---|---|---|
| `bash lib/stats/tests/test-ceremony-lens.sh` | 0 | `RESULT: 68 passed, 0 failed` |
| `bash lib/stats/tests/test-anomalies-advisor.sh` | 0 | `== 36 passed, 0 failed ==` |
| `bash lib/stats/tests/test-schema-parity.sh` | 0 | `== 4 passed, 0 failed ==` |
| `bash lib/stats/tests/test-schema-conform.sh` | 0 | `== 10 passed, 0 failed ==` |
| `bash tests/test-hooks.sh` | 0 | `All tests passed.` |
| `bash tests/test-meta.sh` | 1 | one failure, `docs/FEATURES.md is fresh`: drift is only spec-mention counts (`SPEC-... +N`) for `/kit:debug`, `/kit:design`, `/kit:dispatch`, `/kit:docs`; regenerating needs `docs/FEATURES.md`, outside this spec's Touches |
| `bash lib/stats/tests/test-docs-wiring.sh` | 1 | `PASS=15 FAIL=3`, three skill frontmatter trigger phrases missing (`understanding debt`, `kit runs`, `render the ledger`); the description was capped at 400 chars by an earlier commit, this change edits only a table row |

## Negative control (spec case A-one-catch)

| Step | Command | Result |
|---|---|---|
| Baseline commit | `git commit` (988c2fec) | detector clean in tree |
| Break | delete the `if caught_true != 0: return None` clause in `_detect_ceremony_share` | `FAIL  A-one-catch no ceremony_share (unexpected: "key": "ceremony_share")`, `RESULT: 67 passed, 1 failed` (red) |
| Restore | `git checkout -- lib/stats/src/stats/anomalies.py` | `RESULT: 68 passed, 0 failed` (green) |

## Baseline reproduces from the lens (criterion 9)

Command: `cd lib/stats && uv run stats ceremony --json`. Three cells checked against `baseline.md`.

| Cell | JSON path | Value | baseline.md |
|---|---|---|---|
| ceremony records | `.records.ceremony` | 637 | 637 |
| dispatches | `.dispatch.count` | 1152 | 1152 |
| known-caught rows | `.catches.known` | 178 | 178 |

Criterion 8: `grep -c '^| ' docs/verification/ceremony-lens/baseline.md` returns 45 (needs >= 10).

## Not done

| Row | Status |
|---|---|
| 8b A/B baseline | PARTIAL, post-ship of the dispatch-tag and whole-spec-dispatch changes; see the last section of `baseline.md` |
