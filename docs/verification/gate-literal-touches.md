# Verification -- gate-literal-touches

`gate_normalize_glob` marked a `## Touches` line that is a literal path (`docs/implementation-notes/share-bar.md`) as `?` (unprovable). Any `?` forces every pair to overlap, so a mega-goal whose sub-goals each write their own notes file never formed a wave and ran serially all night. A literal path is now its own exact prefix; `prefix_overlap` already compares on segment boundaries, so a file overlaps only itself or an ancestor directory.

## What changed

| Touches line | Before | After |
|---|---|---|
| `dir/**`, `dir/sub/**` | prefix `dir` | unchanged |
| `docs/notes/x.md` (literal) | `?docs/notes/x.md` (unprovable) | `docs/notes/x.md` (exact prefix) |
| `docs/notes/*.md`, `**/x`, `a/{b,c}`, `a/?.md` | `?...` | unchanged, still unprovable |
| `docs/../lib/x.md`, `./x.md`, `/abs/x.md` | `?...` | unchanged, still unprovable (a `.`/`..` segment or absolute path cannot be compared as a string prefix) |

The same function backs `lib/goal/goal-registry.sh` (cross-session globs), so a literal path there is also now an exact prefix.

## Recorded run

```
Command: bash tests/test-orchestrate-hardening.sh
Exit: 0
Output:
  PASS ID-098 [Done=]: a cleanly-landed (shipped) sub-goal's window is killed on the happy path (no orphaned pane)
  PASS literal ## Touches: disjoint literal paths run together, a repeated literal path defers
  === 13/13 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0 for every selected suite except the registry freshness pin, which went red on one count in docs/reference/FEATURES.md and was regenerated (`feature-registry.sh check --fix`)
Output:
  test-hooks                                     ok (142s)
  test-orchestrate-hardening                     ok (8s)
  test-meta-vmodel-dispatch                      ok (1s)
  test-meta-goal-ledger                          ok (0s)
  run-all: 43 suites, 4 at a time, 0 serial
Verdict: PASS (after the FEATURES.md regeneration; test-meta-docs-registry rerun: Passed 120 / 120)
```

New cases: `tests/test-hooks.sh` dispatch-gate section (8 cases: two disjoint literal paths are disjoint, exit 0; the same literal path in both overlaps, exit 1; a literal file under the other's `dir/**` overlaps, exit 1; a literal vs an unrelated `dir/**` is disjoint; a literal vs a real glob `share-*.md` stays an overlap; a `..` literal stays an overlap; `touches` prints the literal with no `?`; `plan` marks two disjoint literal specs both PARALLEL) and `tests/test-orchestrate-hardening.sh` section 4 (`_wave_gate` admits SG-01 and SG-02 with disjoint literal paths and defers SG-03, which repeats SG-01's path).

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate-hardening.sh" "git show origin/master:lib/gate/dispatch-gate.sh > lib/gate/dispatch-gate.sh"
Exit: 1 under the mutation (RED expected), 0 after restore
Output:
  FAIL literal ## Touches: expected 'run SG-01 run SG-02 defer SG-03', got 'run SG-01 defer SG-02 defer SG-03 '
  === 12/13 passed, 1 failed ===
Verdict: PASS
```

The mutation is the pre-change `dispatch-gate.sh`. The same revert run against the dispatch-gate section of `tests/test-hooks.sh` (that section cut into a scratch harness, so the 142 s suite did not rerun) went RED on four cases: two disjoint literal paths, a literal vs an unrelated `dir/**`, `touches` printing the literal, and `plan` marking both PARALLEL; 13 passed, 4 failed. The overlap cases stay green under the revert by design: the old code over-serialized, so they only guard against the fix going too far.

## Not proven
- No live mega-goal run. Wave formation is shown through `_wave_gate` on a fixture, not through a real `orchestrate.sh run`.
- A literal that names a directory (`docs/notes`, no `/**`) is treated as that directory's prefix, the same as `docs/notes/**`. That is the conservative reading and was not changed.
- `commands/mega.md` Step 4 still words the `## Touches` form as `dir/**`; it is narrower than the gate, not wrong.

## Rollback
Revert the commit: `lib/gate/dispatch-gate.sh` returns to marking every literal path unprovable. The function writes no state.
