# Proof of done: spec depth line

| | |
|---|---|
| **Profile** | feature (kit command and helper change) |
| **Proof class** | behavioral (a helper with exit codes, plus command wiring) |
| **Spec** | [`docs/specs/SPEC-372-spec-depth-line.md`](../specs/SPEC-372-spec-depth-line.md) |
| **Canonical** | this file (table-first) |
| **Run id** | `spec-depth-line` |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | `level` parses every form, header only | PASS | R1 `level`: 8 asserts |
| AC2 | `check` rejects bad lines | PASS | R1 `check`: 14 asserts |
| AC3 | inverse check | PASS | R1 `inverse`: 3 asserts |
| AC4 | rid-tag phrases survive | PASS | R1 `spec-md-wiring`, R2 (test-meta asserts the phrase) |
| AC5 | missing line: critical on new, warning on old | PASS | R1 `missing-line`: 6 asserts |
| AC6 | review routing | PASS | R1 `review-routing`; live floor passes in `spec-depth-line/floor-passes.md` |
| AC7 | default depth sends zero research agents (live `/kit:spec`) | PARTIAL | no live run; static wiring + ledger verb round-trip + dry trace (notes row 10) |
| AC8 | `wants` never fires without a header line | PASS | R1 `wants` |
| AC9 | no regressions | PASS | R2, R3 |

## 2. Confirmation (recorded runs)

| Run | Command | Exit | Result |
|---|---|---|---|
| R1 | `bash tests/test-spec-depth.sh` (BSD tools, macOS bash 3.2 path) | 0 | `spec-depth: 65 passed, 0 failed` |
| R1g | same with `/opt/homebrew/opt/coreutils/libexec/gnubin` first on PATH | 0 | `spec-depth: 65 passed, 0 failed` (63 before the body-only fixture) |
| R2 | `bash tests/test-meta.sh` | 0 | `Passed: 887 / 887` |
| R3 | `bash tests/test-hooks.sh` | 0 | `Passed: 817 / 817` |
| R4 | `bash lib/gate/doc-projection-check.sh .` and `feature-registry.sh check docs/FEATURES.md` | 0 | clean, `docs/FEATURES.md is fresh` |
| R5 | ledger verb in a temp `DWARVES_KIT_LOG_DIR`: `gate-ledger.sh action spec-depth-line "depth=standard research_agents=0"` then `show` | 0 | one `ACTION` line matching the AC7 grep |

R2 and R3 ran on the BSD tool set only. The GNU tool set ran the new suite only.

## 3. Negative controls (commit, break, red, restore with `git checkout -- <file>`, green)

| Must-have | Break | Red | Restored |
|---|---|---|---|
| Importance-only reasons rejected (AC2) | `check_reason` never flags importance | `check`: 12 passed, 2 failed | 14 passed, 0 failed |
| Header-only parse (DEC-7, AC1) | `header()` returns the whole file | 3 failed (body-only level, fenced-example check, body-only wants) | 65 passed, 0 failed |
| `wants` never fires without a line (AC8) | no header line yields `research-repo` | `wants`: 9 passed, 1 failed | 10 passed, 0 failed |
| Grace period pinned (AC5) | `DEPTH_REQUIRED_FROM` moved to 2030 | `missing-line`: 4 passed, 2 failed | 6 passed, 0 failed |
| Inverse check (AC3) | standard-with-open-questions no longer flagged | `inverse`: 2 passed, 1 failed | 3 passed, 0 failed |
| Step 2 routes by depth (AC7 dry trace) | `wants <spec> research-repo` line altered | `spec-md-wiring`: 9 passed, 1 failed | 10 passed, 0 failed |
| Rid phrase kept (AC4) | `include \`rid=<rid>\`` reworded | `spec-md-wiring`: 9 passed, 1 failed | 10 passed, 0 failed |
| Validator runs the check (TASK-3) | `spec-depth.sh check` removed from Reviewer 4 | `validate-wiring`: 2 passed, 2 failed | 4 passed, 0 failed |
| Floor routing (AC6) | `--floor` removed from test-plan step 4 | `review-routing`: 5 passed, 1 failed | 6 passed, 0 failed |
| Docs wording (TASK-5) | floor/full phrase removed from WORKFLOW | `docs`: 2 passed, 1 failed | 3 passed, 0 failed |
| The floor pass bites (AC6) | seeded-gap plan | 4 CRITICAL, RECONSIDER | good plan: 0 CRITICAL |

## 4. Not covered

| Item | Why |
|---|---|
| AC7 live run | needs an interactive `/kit:spec` session; the validator Reviewer 4 CRITICAL on the `research (this is important)` fixture was not dispatched live either (only its mechanical `check` exit 1 is proven) |
| GNU run of test-meta and test-hooks | only the new suite ran on the GNU tool set |
