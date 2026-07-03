# Proof of done: cheap-tier defaults (SPEC-107, kit-face wave)

The kit's cheap-first stance (`sonnet` default, `opus` = explicit hard-reasoning escape hatch)
is now consistent across the three authoring surfaces, and the positive default is APPLIED at
dispatch by the existing `_route` reader (a goal file carrying the template-default `Model:
sonnet` dispatches `--model sonnet`), not merely asserted.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | execute.md 2b: workers dispatch `sonnet` by default + the spec `Model:` header escape hatch + fable-session clause | PASS |
| 2 | meta-agent Mode B writes `Model: sonnet` on abstain (was OMIT/inherit) | PASS |
| 3 | dotfiles subgoal-template defaults `Model: sonnet` (surface 2, applied + committed atomically) | PASS |
| 4 | Positive default APPLIED at dispatch via `_route` (goal file `Model: sonnet` -> `--model sonnet`) | PASS |
| 5 | NEGATIVE CONTROL: an explicit `Model: opus`/none override still routes correctly (opus / inherit unchanged) | PASS |
| 6 | NEGATIVE CONTROL: the old meta-agent contradiction text ("human's call…"; "OMIT the Model: line") is GONE, not merely supplemented | PASS |
| 7 | `test-meta.sh`, `test-meta-agent.sh`, `test-orchestrate.sh` all green; agent-frontmatter lint still green | PASS |

## Implementation

- `commands/execute.md` 2b: "Model tiering (SPEC-107, cheap-first default)" paragraph , sonnet
  default, spec `Model:` escape hatch, verifiers keep frontmatter tiers, fable-session + degrade
  clauses (:152-159).
- `agents/meta-agent.md` Mode B: abstain writes `Model: sonnet` (:80) and the stance paragraph
  rewritten (the two old contradiction lines removed).
- `tests/test-meta.sh`: SPEC-107 block , surface-1 + surface-3 greps + 2 negative controls.
- dotfiles `plan-for-mega-goal/references/subgoal-template.md`: `Model: sonnet` default (value
  line clean; guidance moved to the explanation bullet). Committed atomically (S-64 watcher):
  dotfiles `9dd5c48`.
- No `lib/`/`hooks/` edit , `_route` is UNCHANGED; the default is baked in by the authoring
  surfaces and honored by `_route`'s existing `^Model:` read. `normal` lane held.

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| s1 default | `grep -iE 'workers dispatch at .?sonnet.? by default' commands/execute.md` | match | match (:152) |
| s1 escape hatch | `grep -iE 'Model:.*(escape hatch\|hard[- ]reasoning\|override)' commands/execute.md` | match | match (:154) |
| s3 sonnet-on-abstain | `grep -iE 'write .?Model: sonnet' agents/meta-agent.md` | match | match (:80) |
| s3 NC1 | `grep -F "human's call, not a silent auto-write" agents/meta-agent.md` | no match | exit 1 (absent) |
| s3 NC2 | `grep -E 'OMIT the .?Model:.? line' agents/meta-agent.md` | no match | exit 1 (absent) |
| s2 dotfiles | `grep -E '^Model: sonnet' <subgoal-template.md>` (source + target) | match | match (:14 both) |
| dispatch (positive default) | `bash tests/test-orchestrate.sh` , SG-01 fixture carries `Model: sonnet` | routes `--model sonnet` | PASS "run passes --model/--effort for hinted SG-01" |
| dispatch (NC inherit) | same , SG-02 fixture carries no Model | no `--model` (inherit) | PASS "run passes no --model for inherit SG-02" |
| suite: meta | `bash tests/test-meta.sh` | all green | 583/583 |
| suite: meta-agent | `bash tests/test-meta-agent.sh` | all green | 65/65 |
| suite: orchestrate | `bash tests/test-orchestrate.sh` | all green | ALL PASS |

## Run detail (captured 2026-07-03)

```
$ grep -niE 'workers dispatch at .?sonnet.? by default' commands/execute.md
152:**Model tiering (SPEC-107, cheap-first default).** Workers dispatch at `sonnet` by default ,

$ grep -niE 'write .?Model: sonnet' agents/meta-agent.md
80:# ABSTAIN  reason=thin-data ... -> write `Model: sonnet` (the cheap-first default, SPEC-107); OMIT only to deliberately inherit

$ grep -nF "human's call, not a silent auto-write" agents/meta-agent.md ; echo exit=$?
exit=1                          # negative control: contradiction removed

$ grep -nE 'OMIT the .?Model:.? line' agents/meta-agent.md ; echo exit=$?
exit=1                          # negative control: old abstain phrasing removed

# dotfiles half (surface 2), applied + committed atomically:
$ grep -n '^Model: sonnet' ~/.claude/skills/plan-for-mega-goal/references/subgoal-template.md
14:Model: sonnet
$ git -C ~/workspace/tieubao/dotfiles log -1 --oneline
9dd5c48 feat(plan-for-mega-goal): default subgoal-template Model to sonnet

# dispatch proof (the default applied at dispatch by _route):
$ bash tests/test-orchestrate.sh   # SG-01 fixture Model: sonnet
PASS dry-run shows SG-01 routed model/effort
PASS run passes --model/--effort for hinted SG-01
PASS dry-run shows SG-02 inherit (no hints)      # NC: absent -> inherit (unchanged)
PASS run passes no --model for inherit SG-02

$ bash tests/test-meta.sh
Passed: 583 / 583 ; All meta tests passed.
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh && bash tests/test-meta-agent.sh && bash tests/test-orchestrate.sh
grep -niE 'workers dispatch at .?sonnet.? by default' commands/execute.md
grep -niE 'write .?Model: sonnet' agents/meta-agent.md
! grep -qF "human's call, not a silent auto-write" agents/meta-agent.md
grep -n '^Model: sonnet' ~/workspace/tieubao/dotfiles/home/dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md
```
