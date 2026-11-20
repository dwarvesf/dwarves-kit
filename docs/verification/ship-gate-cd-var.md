# Verification -- ship-gate-cd-var

The ship-gate resolves a line-start `cd $W` (or `${W}`) to the literal path W was set to by one plain assignment earlier in the same command; every other shape keeps the session-cwd fallback.

| # | Run | Command | Exit | Result | Verdict |
|---|---|---|---|---|---|
| 1 | Red on the base commit `c4d029b8` | `bash tests/test-ship-gate-cd-var.sh` | 1 | `PASS=104 FAIL=12`: the 12 resolve rows red, every fallback row green (the adopted row came later; the negative control shows it red too) | expected red |
| 2 | Green run | `bash tests/test-ship-gate-cd-var.sh` | 0 | `PASS=117 FAIL=0` | PASS |
| 3 | Green under macOS bash 3.2 | `PATH="/bin:$PATH" bash tests/test-ship-gate-cd-var.sh` | 0 | `PASS=116 FAIL=0` (run before the adopted row was added) | PASS |
| 4 | Diff-scoped regression at HEAD | `bash tests/run-all.sh --changed --time` | 0 | `all 43 suites passed`, every `tests/test-ship-gate-*.sh` suite among them | PASS |
| 5 | The exact live command, replayed | the transcript command into the hook, cwd the ops-toolkit checkout on main, the gone worktree path swapped for an existing feature worktree | see below | new hook: target resolves, no default-push block; base hook: `lands on 'main', the default branch of '2>'` | PASS |
| 6 | Negative control | `lib/gate/negctl.sh`, the hook restored from `c4d029b8` | 1 under mutation, 0 after restore | the live-sample, adopted live-sample and reverse rows go red | PASS |

## Green run
```
Command: bash tests/test-ship-gate-cd-var.sh
Exit: 0
Output:
ok - live sample: the cd target resolves to the worktree
ok - live sample: W=<feature worktree>, cd $W, push from a main cwd -> allowed
ok - adopted live sample: not a default push, not unaccounted
ok - reverse: W=<repo on main>, cd $W && git push -q from a feature cwd -> blocked
---
PASS=117 FAIL=0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
test-meta-docs-registry                        ok (10s)
test-ship-gate-cd-var                          ok (17s)
test-ship-gate-command-words                   ok (61s)
test-ship-gate-coverage-map                    ok (10s)
test-ship-gate-default-push                    ok (7s)
test-ship-gate-fail-closed                     ok (20s)
test-ship-gate-identities                      ok (5s)
test-ship-gate-impl-notes                      ok (34s)
test-ship-gate-profiles                        ok (5s)
run-all: all 43 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

An earlier run of the same command, before `docs/reference/FEATURES.md` was regenerated, had one red suite: `test-meta-docs-registry`, because the new test file moved the registry's counts. Both regenerations are committed.

## Live command replay

The command from the lead transcript (seven lines: `S=...`, `W=<worktree>`, `cd $W && git status --short | head; git branch --show-current`, then the copy, `rg` and `git add ... && git commit ... && git push -q 2>&1 | tail -2` lines), fed to the hook with cwd the ops-toolkit checkout (on main). The original worktree no longer exists, so its path was swapped for an existing feature worktree, `.claude/worktrees/ship-gate-redirect-parse` on `fix/ship-gate-redirect-parse`.

```
Command: DWARVES_KIT_PRINT_CDDIR=1, new hook and base hook, same input
Output:
new: [~/workspace/dwarvesf/dwarves-kit/.claude/worktrees/ship-gate-redirect-parse]
base: []
new verdict exit=2
BLOCKED: proof of done. This is a 'behavioral' change; it cannot ship/merge without a matching proof-of-done entry in docs/verification/.
base verdict exit=2
BLOCKED: ship-gate. This push lands on 'main', the default branch of '2>'. Never push straight to a default branch.
Verdict: PASS
```

The new hook judges the worktree's own branch, so the verdict comes from that repo's rules (its unfinished proof), not the default-push block. With the original path, which no longer exists, the new hook falls back to the session cwd as designed.

## Negative control
```
Command: o=$(mktemp); bash tests/test-ship-gate-cd-var.sh >"$o" 2>&1; s=$?; grep -E "live sample|reverse|^PASS=" "$o" | cut -c1-110; exit $s
Mutation: git show c4d029b8:hooks/ship-gate.sh > hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - live sample: the cd target resolves to the worktree (want '/var/folders/dr/n3x74rr93kvfjf1873pyjvp800
  NOT ok - live sample: W=<feature worktree>, cd $W, push from a main cwd -> allowed (want exit 0, got 2: BLOCKE
  NOT ok - adopted live sample: not a default push, not unaccounted (BLOCKED: ship-gate. This push lands on 'mai
  NOT ok - reverse: W=<repo on main>, cd $W && git push -q from a feature cwd -> blocked (want exit 2 + 'lands o
  PASS=104 FAIL=13
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

`lib/gate/negctl.sh` swapped in the base hook, the live rows went red, and the restore brought the suite back to green with a clean tree.

## Not proven
- A mid-line cd (`W=..; cd $W && git push` on one line) still falls back to the session cwd. That is the shape of the 2026-11-03 and 2026-11-14 hook-log blocks and of most `W=` commands found in the transcripts; only the 2026-11-19 shape (W on its own line) is fixed. Widening the extraction is SPEC-423's problem.
- The one-cd-word rule counts `cd` as a word inside a path too (`.../fix-cd-var`), so such a target falls back. Safe, but a false block stays.
- The push parse (`2>&1` read as the remote `2>`, SPEC-423 R1) is unchanged. The adopted-repo row and the replay show the refspec-less `git push -q 2>&1 | tail -2` is not refused as unaccounted once the cd resolves; a push with an explicit refspec plus `2>&1` in an adopted repo was not run here.
- Residual shapes not banned, none of them a shape an agent writes: zsh `repeat 0` above the cd line, a multi-line `[[` holding the assignment line, shell-managed names outside the denylist (`SHELLOPTS`, `DIRSTACK`).
- Rows run the hook directly, not through a live Claude Code session.
