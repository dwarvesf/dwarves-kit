# Proof of done: meta-agent provenance + efficacy metric (SPEC-108, kit-face wave)

Generated agents are now distinguishable forever (`generated-by:` frontmatter, backfilled on the
5 + emitted by draft-agent going forward), and SPEC-073 gains metric 11 (generated-agent catch
count) to measure their runtime value.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | 5 generated agents carry a well-formed `generated-by: draft-agent YYYY-MM-DD <ctx>` (ctx from Source footers, colon-free) | PASS |
| 2 | draft-agent Step 4.2 stamps `generated-by:` on install (forward emit, colon-free rule) | PASS |
| 3 | EMIT FIXTURE (wiring gate): install-sim stamps + asserts a well-formed key on a NEW post-install agent | PASS |
| 4 | SET-EQUALITY guard: the key set-equals the 5 generated agents (no silent spread to hand-written) | PASS |
| 5 | NEGATIVE CONTROL: the frontmatter lint tolerates the key (test-meta still green) | PASS |
| 6 | SPEC-073 metric 11 = catch COUNT with a literal AC2-compliant command + metric-6 distinction | PASS |
| 7 | Probe (CC-load proxy): backfilled frontmatter parses + lints with the extra key | PASS |
| 8 | All 12 CI suites green | PASS |

## Implementation

- `agents/{advisor,brief-reviewer,acceptance-verifier,system-verifier,recheck-verifier}.md`:
  `generated-by: draft-agent 2026-07-02 <ctx>` after `model:` (order-independent for the lint).
- `commands/draft-agent.md` Step 4.2: stamp instruction + colon-free `<context>` rule + "only
  generated agents carry it".
- `tests/test-meta-agent.sh` install-sim (:88+): stamp + well-formed-`generated-by` assertion +
  re-lint of the stamped agent (the NEW-generation emit fixture).
- `tests/test-meta.sh`: 5 per-agent format pins + a set-equality guard.
- `docs/specs/SPEC-073-*.md`: metric-table row 11 + `## Amendments` (catch COUNT, literal command,
  metric-6 distinction).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| backfill format | `for a in <5>; do grep -qE '^generated-by: draft-agent [0-9]{4}-...' agents/$a.md; done` | all match | all match |
| emit fixture | `bash tests/test-meta-agent.sh` , install-sim stamp assert | PASS | PASS "install: Step-4 stamps a well-formed generated-by (SPEC-108 emit fixture)" |
| set-equality | `bash tests/test-meta.sh` , key set == 5 roster | PASS | PASS "generated-by key set-equals the known generated roster" |
| lint tolerance (NC) | `bash tests/test-meta.sh` frontmatter lint with key | green | 589/589 |
| metric 11 present | `grep -q 'generated-agent catch count' docs/specs/SPEC-073-*.md` | match | match |
| suite: meta | `bash tests/test-meta.sh` | green | 589/589 |
| suite: meta-agent | `bash tests/test-meta-agent.sh` | green | 72/72 |
| all CI suites | test-hooks/e2e/review-team-plants/orchestrate/role-classify/lane-classify/lane-telemetry/mega-merge/ledger-durability/proof-visual-evidence | green | all pass |

## Run detail (captured 2026-07-03)

```
$ bash tests/test-meta.sh
  PASS generated agent acceptance-verifier carries a well-formed generated-by (SPEC-108)
  PASS generated agent advisor carries a well-formed generated-by (SPEC-108)
  PASS generated agent brief-reviewer carries a well-formed generated-by (SPEC-108)
  PASS generated agent recheck-verifier carries a well-formed generated-by (SPEC-108)
  PASS generated agent system-verifier carries a well-formed generated-by (SPEC-108)
  PASS generated-by key set-equals the known generated roster (no spread to hand-written agents)
Passed: 589 / 589 ; All meta tests passed.

$ bash tests/test-meta-agent.sh
  PASS install: Step-4 stamps a well-formed generated-by (SPEC-108 emit fixture)
  PASS stamped-agent: model is sonnet|haiku|opus (sonnet)
=== 72/72 passed, 0 failed ===

# all remaining CI suites: test-hooks All passed; test-e2e 20/20; test-orchestrate ALL PASS;
# test-role-classify 15/15; test-lane-classify 23/23; test-lane-telemetry 18/18;
# test-mega-merge 30/30; test-ledger-durability 32/32; test-proof-visual-evidence 4/4;
# test-review-team-plants All passed.
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh && bash tests/test-meta-agent.sh
for a in advisor brief-reviewer acceptance-verifier system-verifier recheck-verifier; do
  grep -qE '^generated-by: draft-agent [0-9]{4}-[0-9]{2}-[0-9]{2} .+' agents/$a.md || echo "MISSING $a"
done
grep -q 'generated-agent catch count' docs/specs/SPEC-073-telemetry-eval-design.md
```
