# Proof of done: agent-effectiveness validator (SPEC-088, kit-hardening SG-01)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | Planted-bad agent flagged with file:line, one per lens | 4 planted fixtures each literally carry their defect; validator prompt carries each lens + `file:line` evidence rule | PASS |
| AC1 [NEGATIVE CONTROL] | The check that passes a good agent must FAIL a bad one | `tools_violation` passes `agent-effectiveness.md` (AC3) AND fires on `bad-tools-overgrant.md` (Write/Edit/Bash present) | PASS |
| AC2 | Existing roster passes, no false positives | good fixture + real roster (task/doc/integration-verifier) carry no over-grant; prompt has explicit "do not cry wolf" guard | PASS |
| AC3 | Validator uses read-only tools only | frontmatter tools = Read/Grep/Glob/Bash(git diff*)/Bash(git log*); no Edit/Write/NotebookEdit/bare-Bash | PASS |
| AC4 [fail-safe] | Infra failure -> unvalidated, never silent pass | prompt has UNVALIDATED verdict, "not a pass", "live-risk" | PASS |
| AC5 [gated] | Diff-keyed: only new/changed agent defs | `commands/draft-agent.md` Step 4.7 dispatches on the just-written agent only, "diff-keyed", advisory | PASS |

## Implementation

- `agents/agent-effectiveness.md` -- read-only 4-lens validator (tools / description / instructions / tier), refuter framing, fail-safe UNVALIDATED verdict. `model: sonnet` (sibling of integration-verifier/doc-verifier; cheap-first).
- `tests/fixtures/agent-effectiveness/` -- `good.md` + one planted-bad per lens (`bad-tools-overgrant.md`, `bad-desc-misfire.md`, `bad-instr-contradict.md`, `bad-tier-mismatch.md`).
- `tests/test-agent-effectiveness.sh` -- AC1-AC5, prompt-completeness + deterministic greps + the negative control.
- `commands/draft-agent.md` Step 4.7 -- diff-keyed dispatch at the agent-author phase (advisory, ship-visible).
- Roster: `MANUAL.md` agent table + `docs/architecture.md` V-phase inventory.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-agent-effectiveness.sh` | 0 | 24/24 passed, 0 failed |
| `bash tests/test-meta.sh` | 0 | 514/514 passed (new agent + roster rows lint-clean) |

## Run detail

```
=== agent-effectiveness validator (SPEC-088 AC1-AC5) ===
  PASS AC3: agents/agent-effectiveness.md exists
  PASS AC3: validator declares read-only tools only (no Edit/Write/NotebookEdit/bare-Bash)
  PASS AC1/tools [NEGATIVE CONTROL]: planted over-grant fixture flagged by read-only check (Write/Edit/Bash present)
  PASS AC1/tools: validator prompt carries the over-grant lens
  PASS AC1/tools: validator prompt states minimal-and-sufficient
  PASS AC1/desc: planted misfire fixture has a too-vague description
  PASS AC1/desc: validator prompt carries the misfire lens
  PASS AC1/desc: validator prompt checks both broad and narrow
  PASS AC1/instr: planted contradiction fixture says read-only AND apply-the-fix
  PASS AC1/instr: validator prompt carries the contradiction lens
  PASS AC1/instr: validator prompt carries the ambiguity lens
  PASS AC1/tier: planted tier fixture is opus for a mechanical check
  PASS AC1/tier: validator prompt carries the tier lens
  PASS AC1: validator reports defects with file:line evidence
  PASS AC2: good fixture has clean read-only tools (would not be over-grant-flagged)
  PASS AC2: validator prompt guards against false positives on a good agent
  PASS AC2: real read-only roster agents (task/doc/integration) carry no over-grant
  PASS AC4: validator has an UNVALIDATED verdict
  PASS AC4: UNVALIDATED is explicitly not a pass (fail-safe)
  PASS AC4: an unvalidated agent is treated as live-risk
  PASS AC5: commands/draft-agent.md exists (agent-author phase)
  PASS AC5: draft-agent dispatches agent-effectiveness
  PASS AC5: the dispatch is diff-keyed (new/changed agent only)
  PASS AC5: the dispatch is advisory, never a mid-flight block

=== 24/24 passed, 0 failed ===
```

## Negative control (the load-bearing proof)

The Tools lens core (`tools_violation`) is the same function on both sides: it returns
EMPTY for `agents/agent-effectiveness.md` (so the validator PASSES AC3) and returns a
NON-EMPTY hit for `tests/fixtures/agent-effectiveness/bad-tools-overgrant.md` (Write /
Edit / bare-Bash present), so the planted-bad fixture is FLAGGED. A check that could
only ever pass would be worthless; this one demonstrably distinguishes a good agent
from a bad one.

## Reproduce

```
cd dwarves-kit
bash tests/test-agent-effectiveness.sh   # 24/24, exit 0
bash tests/test-meta.sh                   # 514/514, exit 0
```
