# Verification log: right-arm review parity (SPEC-092, kit-hardening SG-04)

Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | 4 agents exist, conform to ADR-0029, each passes the SG-01 gate | PASS | `tests/test-right-arm-parity.sh` AC1 block; `tests/test-agent-effectiveness.sh agents/<name>.md` per agent, all exit 0 |
| AC2 | Acceptance + System-test rows in `docs/architecture.md` are non-empty | PASS | `docs/architecture.md` Right arm TEST table names `acceptance-verifier` / `system-verifier`; `tests/test-right-arm-parity.sh` AC2 block |
| AC3 | `recheck-verifier` prompt carries re-execution-not-read-back semantics | PASS | `agents/recheck-verifier.md` (bolded rule + Rules section + Source line); `tests/test-right-arm-parity.sh` AC3 block |
| AC4 | Negative control: planted-bad PASS fixture + recheck-verifier catches the class | PASS | `tests/fixtures/right-arm-parity/planted-bad-pass.md`; `tests/test-right-arm-parity.sh` AC4 block |
| AC5 | `commands/execute.md` wires the re-audit lens over a right-arm PASS | PASS | `commands/execute.md:209` (2c-1, after task-verifier) + `commands/execute.md:331` (2b, after integration-verifier); `tests/test-right-arm-parity.sh` AC5 block |
| AC6 | `tests/test-meta.sh` stays green with the 4 new names | PASS | `tests/test-meta.sh` REVIEW_AGENTS list + architecture-table-row-count check (item d), both green |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | 4 new agents (`brief-reviewer`, `acceptance-verifier`, `system-verifier`, `recheck-verifier`) + a fresh-context re-audit lens wired into `commands/execute.md` |
| Where | `agents/{brief-reviewer,acceptance-verifier,system-verifier,recheck-verifier}.md`; `commands/execute.md` (2c-1, Step 4 item 2b); `docs/architecture.md`; `MANUAL.md`; `tests/test-meta.sh` |
| How it runs | Agents are dispatched via the Task tool by `/kit:execute` (recheck-verifier, automatically after a right-arm PASS) or invoked ad hoc; no runtime service, no daemon |
| Reversibility | Pure additive markdown + a `REVIEW_AGENTS` string edit; `git revert` is sufficient, no data/state involved |

## 3. Confirmation (runs)

| Run | When (ISO+tz) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-07-02T00:00:00+07:00 | `bash tests/test-right-arm-parity.sh` | 0 | PASS (34/34) |
| R2 | 2026-07-02T00:00:00+07:00 | `bash tests/test-agent-effectiveness.sh agents/brief-reviewer.md` | 0 | PASS (3/3) |
| R3 | 2026-07-02T00:00:00+07:00 | `bash tests/test-agent-effectiveness.sh agents/acceptance-verifier.md` | 0 | PASS (3/3) |
| R4 | 2026-07-02T00:00:00+07:00 | `bash tests/test-agent-effectiveness.sh agents/system-verifier.md` | 0 | PASS (3/3) |
| R5 | 2026-07-02T00:00:00+07:00 | `bash tests/test-agent-effectiveness.sh agents/recheck-verifier.md` | 0 | PASS (3/3) |
| R6 | 2026-07-02T00:00:00+07:00 | `bash tests/test-meta.sh` | 0 | PASS (576/576) |
| R7 | 2026-07-02T00:00:00+07:00 | `bash tests/test-hooks.sh` | 0 | PASS (438/438, unrelated suite unaffected) |

## 4. Run detail

### R1 GREEN

- Command: `bash tests/test-right-arm-parity.sh`
- Exit: 0
- Output (excerpt): `=== 34/34 passed, 0 failed ===`, including the negative-control line
  `AC4 [NEGATIVE CONTROL]: fixture's Command ('bash -c 'exit 1'') re-run FAILS (exit 1),
  contradicting its own recorded PASS`.
- Verdict: PASS

### R2-R5 GREEN (SG-01 gate, per agent)

- Command: `bash tests/test-agent-effectiveness.sh agents/<name>.md` for
  `brief-reviewer`, `acceptance-verifier`, `system-verifier`, `recheck-verifier`.
- Exit: 0 (all four)
- Output (excerpt): `=== 3/3 passed, 0 failed ===` for each (read-only tools, valid model
  tier, on-axis name).
- Verdict: PASS

### R6 GREEN (roster + naming-axis regression check)

- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output (excerpt): `Passed: 576 / 576` / `All meta tests passed.` -- includes the 4 new
  names in the ADR-0029 positive-axis block and the architecture-table-row == live-file
  count check (item d).
- Verdict: PASS

### R7 NEGATIVE-CONTROL-ADJACENT (unrelated suite unaffected)

- Command: `bash tests/test-hooks.sh`
- Exit: 0
- Output (excerpt): `Passed: 438 / 438` / `All tests passed.`
- Verdict: PASS (confirms this sub-goal's changes did not regress the hooks suite)

## 5. Reproduce

```
cd dwarves-kit
bash tests/test-right-arm-parity.sh
for a in brief-reviewer acceptance-verifier system-verifier recheck-verifier; do
  bash tests/test-agent-effectiveness.sh "agents/$a.md"; done
bash tests/test-meta.sh
bash tests/test-hooks.sh
```
