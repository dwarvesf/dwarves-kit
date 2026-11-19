# Verification -- ship-gate-cd-var

The ship-gate resolves a line-start `cd $W` (or `${W}`) to the literal path W was set to by one plain assignment earlier in the same command; every other shape keeps the session-cwd fallback.

| # | Run | Command | Exit | Result | Verdict |
|---|---|---|---|---|---|
| 1 | Red on the base commit `c4d029b8` | `bash tests/test-ship-gate-cd-var.sh` | 1 | `PASS=104 FAIL=12`: the 12 resolve rows red, every fallback row green | expected red |
| 2 | Green run | `bash tests/test-ship-gate-cd-var.sh` | 0 | `PASS=116 FAIL=0` | PASS |
| 3 | Green under macOS bash 3.2 | `PATH="/bin:$PATH" bash tests/test-ship-gate-cd-var.sh` | 0 | `PASS=116 FAIL=0` | PASS |
| 4 | Existing ship-gate suites | `bash tests/test-ship-gate-<name>.sh`, each suite | 0 | all pass (see below) | PASS |
| 5 | Diff-scoped regression | `bash tests/run-all.sh --changed --time` | 0 after the regen | 37 suites; `test-meta-docs-registry` was red only because the new test file moved FEATURES.md counts; regenerated, 120/120 | PASS |
| 6 | Negative control | `lib/gate/negctl.sh`, the hook restored from `c4d029b8` | 1 under mutation, 0 after restore | the live-sample and reverse rows go red | PASS |

## Green run
```
Command: bash tests/test-ship-gate-cd-var.sh
Exit: 0
Output:
ok - live sample: the cd target resolves to the worktree
ok - live sample: W=<feature worktree>, cd $W, push from a main cwd -> allowed
ok - reverse: W=<repo on main>, cd $W && git push -q from a feature cwd -> blocked
ok - unquoted W=~/r, push from a main cwd -> allowed
---
PASS=116 FAIL=0
Verdict: PASS
```

The existing ship-gate suites, each run on its own:

```
Command: for t in tests/test-ship-gate-*.sh; do bash "$t" 2>&1 | tail -1; done
Exit: 0
Output:
tests/test-ship-gate-cd-var.sh :: PASS=116 FAIL=0
tests/test-ship-gate-command-words.sh :: PASS=145 FAIL=0
tests/test-ship-gate-coverage-map.sh :: PASS=10 FAIL=0
tests/test-ship-gate-default-push.sh :: PASS=37 FAIL=0
tests/test-ship-gate-fail-closed.sh :: PASS=12 FAIL=0
tests/test-ship-gate-identities.sh :: pass=11 fail=0
tests/test-ship-gate-impl-notes.sh :: PASS=19 FAIL=0
tests/test-ship-gate-profiles.sh :: ALL PASS (3 profiles x allow+block)
tests/test-ship-gate-refs-block.sh :: Results: 11 passed, 0 failed
tests/test-ship-gate-review-verdict.sh :: pass=60 fail=0
Verdict: PASS
```

## Negative control
```
Command: o=$(mktemp); bash tests/test-ship-gate-cd-var.sh >"$o" 2>&1; s=$?; grep -E "live sample|reverse|^PASS=" "$o" | cut -c1-110; exit $s
Mutation: git show c4d029b8:hooks/ship-gate.sh > hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - live sample: the cd target resolves to the worktree (want '/var/folders/dr/n3x74rr93kvfjf1873pyjvp800
  NOT ok - live sample: W=<feature worktree>, cd $W, push from a main cwd -> allowed (want exit 0, got 2: BLOCKE
  NOT ok - reverse: W=<repo on main>, cd $W && git push -q from a feature cwd -> blocked (want exit 2 + 'lands o
  PASS=104 FAIL=12
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

`lib/gate/negctl.sh` swapped in the base hook, the live-sample and reverse rows went red, and the restore brought the suite back to green with a clean tree.

## Not proven
- A mid-line cd (`W=..; cd $W && git push` on one line) still falls back to the session cwd. That is the shape of the 2026-11-03 and 2026-11-14 hook-log blocks and of most `W=` commands in the transcripts; only the 2026-11-19 shape (W on its own line) is fixed. Widening the extraction is SPEC-423's problem.
- The push parse (`2>&1` read as the remote `2>`, SPEC-423 R1) is unchanged. In an adopted repo the live shape can still be refused for that reason.
- Rows run the hook directly, not through a live Claude Code session.
