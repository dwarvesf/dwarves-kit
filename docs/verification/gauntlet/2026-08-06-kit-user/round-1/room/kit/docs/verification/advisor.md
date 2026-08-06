# Proof of done: generic advisor (SPEC-091, ADR-0028 P5/P6, kit-hardening SG-03)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | advisor exists, conforms (named-noun), read-only | `agents/advisor.md`, `name: advisor`, tools Read/Grep/Glob/Bash(git diff*/log*) | PASS |
| AC2 | both modes documented (P5 critique + P6 over-suggest) | in the agent AND WORKFLOW.md advisor section | PASS |
| AC3 [additive] | does NOT replace the specialized reviewers | review-team still dispatches security/architecture/test-coverage AND adds advisor Step 2b; prompt + wiring say "additive, not a replacement" | PASS |
| AC4 [kit-default] | wired as a default, not opt-in | review-team Step 2b + WORKFLOW marked KIT DEFAULT | PASS |
| AC5 [tier knob] | model tier is a config knob, cheap-first | `model: sonnet` default + documented as the knob | PASS |
| AC6 [gated] | passes the SG-01 effectiveness gate | `test-agent-effectiveness.sh agents/advisor.md` exit 0 | PASS |

## Implementation

- `agents/advisor.md` -- one agent, two modes (critique P5 / over-suggest P6), read-only, `model: sonnet` (cheap-first knob).
- `commands/review-team.md` Step 2b -- dispatches the advisor as an EXTRA cross-cutting lens on top of the 3 specialists (KIT DEFAULT, additive).
- `WORKFLOW.md` -- "## The advisor: the kit-default extra lens" documents both modes at the final boundary.
- `tests/test-agent-effectiveness.sh` -- added GATE MODE (`<agent-path>`) reused as the SG-01 gate.
- Roster: MANUAL.md + docs/architecture.md.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-advisor.sh` | 0 | 15/15 passed |
| `bash tests/test-agent-effectiveness.sh agents/advisor.md` | 0 | 3/3 gate passed |
| `bash tests/test-meta.sh` | 0 | 543/543 (advisor lint + roster + on-axis) |

## Run detail

```
=== advisor (SPEC-091 AC1-AC6) ===
  PASS AC1: agents/advisor.md exists
  PASS AC1: name is the named-noun 'advisor' (ADR-0029)
  PASS AC1: advisor declares read-only tools only
  PASS AC2: agent documents critique mode (P5)
  PASS AC2: agent documents over-suggest mode (P6)
  PASS AC2: WORKFLOW.md documents both modes at the final boundary
  PASS AC3: review-team still dispatches the 3 specialist lenses
  PASS AC3: review-team adds the advisor lens (Step 2b)
  PASS AC3: advisor prompt states it is additive, not a replacement
  PASS AC3: review-team wiring states additive, not a replacement
  PASS AC4: review-team marks the advisor a KIT DEFAULT
  PASS AC4: WORKFLOW marks the advisor a kit default (not opt-in)
  PASS AC5: advisor model defaults to sonnet (cheap-first)
  PASS AC5: agent documents the model tier as a config knob
  PASS AC6: advisor passes the SG-01 agent-effectiveness gate
=== 15/15 passed, 0 failed ===
```

## NEGATIVE CONTROL (additive, not a replacement -- the load-bearing property)

The load-bearing risk (ADR-0028 refinement) is the advisor REPLACING the specialized
reviewers. AC3 is the control: `test-advisor.sh` asserts `/kit:review-team` STILL
dispatches all three specialist lenses (security, architecture, test-coverage) AND
adds the advisor -- if a future edit removed a specialist lens, the "review-team still
dispatches the 3 specialist lenses" assertion FAILS. The advisor is proven additive,
not substitutive. The SG-01 gate (AC6) is the second control: the advisor is not
trusted as a kit default until it passes the effectiveness gate.

## Reproduce

```
cd dwarves-kit
bash tests/test-advisor.sh                          # 15/15, exit 0
bash tests/test-agent-effectiveness.sh agents/advisor.md   # 3/3, exit 0
bash tests/test-meta.sh                             # 543/543, exit 0
```
