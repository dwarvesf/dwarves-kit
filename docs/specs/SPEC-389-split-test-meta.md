# Spec: split tests/test-meta.sh into per-area suites

Generated: 2026-10-04
Status: VALIDATED (design: obvious, mechanical split; no validation fan-out run)
Lane: normal
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 02 (D2: split by command area, the way SPEC-374 split test-wrap).

## Problem

`tests/test-meta.sh` is 3,375 lines and 902 asserts, 6-10 minutes wall clock. `bin/test-affected` runs it as one block whenever a diff touches a path it reads, so a one-line doc change pays the full suite. Splitting by command area lets `--changed` runs (and, in SG-03, finer meta_input mapping) pay only for the area the diff touches.

## Design

Same shape as the SPEC-374 wrap split:

- Shared harness (counters, colors, `assert_eq`, `assert_true`, the `KIT_CONFIG_OPERATOR` export) moves verbatim to `tests/lib/meta-stub.sh`. Each suite keeps its own `KIT_DIR` line and sources the stub.
- Each `echo "=== <name> ==="` block (between `# ====` rule lines) moves verbatim into one area suite. Assert labels stay byte-identical; no assert is deleted, merged, reordered inside a section, or weakened.
- `tests/test-meta.sh` becomes a `# runner:` file that relays the area suites (parallel, `META_JOBS`, output collated in suite order) and prints the monolith's `Passed: N / N` summary line so `lib/gate/verify-counts.sh` works unchanged. The suite list is declared on a `# runner-suites:` line and read by both the runner and `tests/run-all.sh`; a bare glob is wrong because `tests/test-meta-agent.sh` is an unrelated suite that matches `test-meta-*.sh`.
- `tests/run-all.sh`: a `# runner:` pick under `--changed` expands into the suites its `# runner-suites:` line names (falling back to the sibling glob), so a selector naming the runner does not silently drop the group. The `test-meta` timeout arm becomes `test-meta*` so the area suites keep the generous ceiling.
- `tests/test-break-it.sh` extracts `is_on_review_axis()` from the file that holds the ADR-0029 section; its `META` path follows the move.
- `bin/test-affected` stays untouched (SG-03 owns the meta_input mapping); its pick of `tests/test-meta.sh` now expands to the area suites via the runner-suites line.

## Areas

| Suite | Sections (echo order preserved) |
|---|---|
| `test-meta-plugin-hooks.sh` | Plugin manifest schema; Invocation namespace guard; Hook registration parity; Hook executability; Installer materializes the hooks; codebase-memory auto-index hook; SPEC-083 session-start board wire; SPEC-084 hook fallback layer; kit-health symlink check |
| `test-meta-contract.sh` | AGENTS.md operating layer; Freeform front door; SPEC-074 composition + 3-surface parity; Self-intro convention |
| `test-meta-agents-commands.sh` | Agent files; Command files; Plugin-qualified agent dispatch |
| `test-meta-spec-depth.sh` | Debug loop; Spec-authoring depth contract; SPEC-357 T18 wrap.distill |
| `test-meta-review-verifiers.sh` | Concurrency-safe review placement; Integration-verifier; Doc-verifier; SPEC-078 review-team routing; SPEC-081 anchored-confidence merge; SPEC-082 per-finding validators; ADR-0029 review-function naming |
| `test-meta-vmodel-dispatch.sh` | V-model lens/convergence/inventory parity; Parallel-execution boundary; Dispatch moat |
| `test-meta-goal-ledger.sh` | Multi-session goal-registry; Goal-draft lifecycle; /kit:verify command; Gate ledger + ship enforcement; SPEC-070 rid pins; SPEC-080 verify-this delta |
| `test-meta-docs-registry.sh` | Spec/ADR number-collision; Demo project; Workflow file; CONTRIBUTING.md; WORKFLOW.md contract; Mid-flight amend; Release-hygiene; SPEC-073 doc-loop; SPEC-085 operator doc sync; Feature-registry freshness; Implementation-notes log; Verification log; ID-651 wrap Step 7a; Task-type contracts |

Cross-section state: `PLUGIN_NAME` (manifest, used by namespace guard), `AGENTS_MD`/`ASSIGN_MD` (AGENTS.md layer, used by Freeform and Self-intro), `fhas`/`VALIDATE_CMD`/`SPEC_CMD_F`/`EXEC_CMD_F`/`WRAP_CMD_F` (depth contract, used by T18) all stay inside their area. Nothing crosses an area boundary; the stub carries only the harness.

## Verification

```
B=<worktree with origin/master checked out>
P='^  .\[0;3[12]m(PASS|FAIL)'
bash "$B"/tests/test-meta.sh > before.out 2>&1                      # ~6-10 min
bash tests/test-meta.sh > after.out 2>&1                          # runner, parallel
diff <(grep -aE "$P" before.out | sort) <(grep -aE "$P" after.out | sort)   # empty
for t in tests/test-meta-*.sh; do [ "$t" = tests/test-meta-agent.sh ] && continue; bash "$t" >/dev/null 2>&1; echo "$? $t"; done   # all 0
bash lib/gate/verify-counts.sh                                    # meta row still resolves a count
bash tests/test-break-it.sh                                     # axis extraction still passes
# Negative control: break one assert in one area suite; runner + that suite red,
# two other suites green; restore; runner green.
```
