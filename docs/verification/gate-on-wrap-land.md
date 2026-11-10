# Verification -- gate-on-wrap-land

`wrap land` (draft or not), `wrap merge --apply`, and the re-merge push they share now run `hooks/ship-gate.sh` before they push or merge. The PreToolUse hook only sees a literal `git push` in a Bash command, so the push a wrap script makes from inside itself reached master unchecked. A stale codex pin in `hooks/codex-hooks.json` landed that way and turned the nightly regression red (`test-codex-hooks`, `test-mktemp-template-guard`).

## Class diagnosis, confirmed from the code

| Path | Gate before this change | Gate now |
|---|---|---|
| `land --draft` | `hooks/ship-gate.sh` called inline | same, through `_ship_gate_check` |
| `land` (non-draft) | none: `git push origin <branch>` ran with no gate | `_ship_gate_check` before the push |
| `merge --apply`, `gh pr merge` | none | `_merge_ship_gate` on the PR head in a scratch worktree |
| re-merge push (`_push_ff`, used by `land` and `merge`) | none | `_ship_gate_check` on the merge commit, commit undone on refusal |
| `merge --repo <owner>/<name>` | none | none: no checkout to read; prints a skip note |

## Green run

```
Command: bash tests/test-wrap-land-gate.sh && bash tests/test-wrap-merge-gate.sh
Exit: 0
Output:
  test-wrap-land-gate: 14 passed, 0 FAILED
  test-wrap-merge-gate: 28 passed, 0 FAILED
Verdict: PASS
```

The two suites that were red in the nightly run, on the branch:

```
Command: bash tests/test-codex-hooks.sh && bash tests/test-mktemp-template-guard.sh
Exit: 0
Output:
  94 passed, 0 failed
  === 11 passed, 0 failed ===
Verdict: PASS
```

The suites that exercise the touched modules (one case in `test-wrap-merge.sh` changed: an unreachable PR head now refuses at the gate with exit 2 instead of reaching tree-verify, and `_tree_verify` keeps its own direct case):

```
Command: bash tests/test-wrap-land.sh && bash tests/test-wrap-merge.sh
Exit: 0
Output:
  test-wrap-land: all 842 passed
  test-wrap-merge: all 412 passed
Verdict: PASS
```

The diff-scoped run over the whole change (35 suites) was green except that one `test-wrap-merge.sh` case, fixed as above and re-run green:

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (before the test-wrap-merge fix)
Output:
  test-wrap-land-gate   ok (6s)
  test-wrap-land        ok (84s)
  test-wrap-merge-gate  ok (5s)
  test-wrap-merge       FAIL (rc=1) (83s)  tree-verify: an unreachable head object exits 3
  run-all: FAILED -> test-wrap-merge
Verdict: the single failure was the intended behavior change; suite is green after the case update
```

The new cases use real git and a stubbed `gh`. They cover a blocking stub gate, a passing stub gate (payload `.cwd` is a detached worktree at the PR head, command is `git push origin <branch>`), a missing gate file, the REAL ship-gate refusing a stale codex pin (and the documented `DWARVES_KIT_SKIP_CODEX_PIN=1` escape), and the re-merge push undoing its merge commit when the gate refuses.

## Negative control

Run after the code was committed (`c1796058`), each mutation restored with `git checkout -- <file>`:

```
Command: <remove the gate call in lib/wrap/wrap-land.sh>; bash tests/test-wrap-land-gate.sh
Exit: 1 (RED expected)
Output:
  test-wrap-land-gate: 3 passed, 11 FAILED
Verdict: PASS (control RED)
```

```
Command: <remove the _merge_ship_gate call in lib/wrap/wrap-merge.sh>; bash tests/test-wrap-merge-gate.sh
Exit: 1 (RED expected)
Output:
  test-wrap-merge-gate: 14 passed, 14 FAILED
Verdict: PASS (control RED)
```

```
Command: <disable the _ship_gate_check call in _push_ff, lib/wrap/wrap-common.sh>; bash tests/test-wrap-merge-gate.sh
Exit: 1 (RED expected)
Output:
  test-wrap-merge-gate: 24 passed, 4 FAILED
Verdict: PASS (control RED: the merge commit is no longer undone, origin takes the push)
```

Restored and green again:

```
Command: bash tests/test-wrap-land-gate.sh; bash tests/test-wrap-merge-gate.sh
Exit: 0
Output:
  test-wrap-land-gate: 14 passed, 0 FAILED
  test-wrap-merge-gate: 28 passed, 0 FAILED
Verdict: PASS
```

## Not covered

`wrap merge --repo <owner>/<name>` has no local checkout, so it cannot run the gate and prints `ship-gate skipped`. That path is unchanged, not loosened. `wrap-carry.sh`, the squash-fallback branch push and the stacked-rebase push in `wrap-merge.sh` still push without a direct gate call; the squash and rebase heads are gated by the final `merge --apply` check, the carry branch by the PR's own land or merge.
