# Spec: Adopt 3 patterns from obra/superpowers
Generated: 2026-04-21
Status: VALIDATED
Source: superpowers v5.0.7 (commit `main`, fetched 2026-04-21)
Validation: 4-lens self-review on 2026-04-21 (security: pass, failure-mode: 1 warning fixed, assumption: 1 warning verified, scope-critic: 2 warnings fixed)

## Problem

dwarves-kit's verification pipeline (`task-verifier`, `reviewer`) was built before obra/superpowers shipped a comparable subagent-driven-development flow. After studying superpowers in 2026-04-21, three patterns surfaced as genuine gaps in our kit:

1. **Our `task-verifier` doesn't explicitly check for "extra/unneeded work"** (over-engineering, scope creep added by the worker). Superpowers' `spec-reviewer-prompt.md` makes this a first-class category alongside missing requirements.
2. **We have no agent for "receiving code review"**. After `/review-team` produces findings, there's no anti-sycophancy guidance for how Claude (or a contractor) should respond. Superpowers' `receiving-code-review` skill closes this gap with a 6-step pattern + forbidden-phrase list.
3. **`commands/kit-health.md` reads as a generic checklist runner.** Superpowers' `AGENTS.md` shows what an opinionated, rejection-first voice looks like ("94% PR rejection rate", "tool of embarrassment"). Our kit-health output should set the same expectations.

These are content/prompt changes only. No new hooks, no runtime dependencies, no architectural shift. The mechanism stays bash + markdown + agent dispatch.

## Solution

Three independent prompt-file edits, each citing superpowers as source:

| Task | File(s) | Type |
|------|---------|------|
| TASK-001 | `agents/task-verifier.md`, `agents/reviewer.md` | Edit existing prompts |
| TASK-002 | `agents/responding-to-review.md` (new), `CLAUDE.md` (mention agent) | New agent + index update |
| TASK-003 | `commands/kit-health.md` | Edit output template only (not the bash checks) |

All three are independent (no inter-task dependencies). Single phase, sequential dispatch (small enough that parallel doesn't pay off).

## Technical Design

### Data model changes
None.

### API / interface changes
- New agent `responding-to-review` becomes dispatchable via the Task tool.
- `agents/task-verifier.md` keeps the same PASS / FAIL:fixable / FAIL:escalate verdict format. New checklist items added; output format unchanged.
- `agents/reviewer.md` keeps the same per-lens output format. New checks added inside the architecture lens.
- `commands/kit-health.md` keeps the same bash checks. Output template wording changes to opinionated framing.

### Infrastructure changes
None. `install.sh` already iterates `agents/*.md` so the new file installs automatically.

## Task Breakdown

### Phase 1: Prompt enrichment (3 tasks, all independent)

- [ ] **TASK-001: Enrich task-verifier and reviewer prompts**
  - Files touched: `agents/task-verifier.md`, `agents/reviewer.md`
  - Changes:
    - `task-verifier.md`: Add new check section "Extra / unneeded work" (over-engineering, scope additions). Add the "verify by reading code, not by trusting report" framing to the Rules section. Add source citation comment at top.
    - `reviewer.md` (architecture lens): Add "Are units decomposed so they can be understood and tested independently?" Add "what this change contributed (don't flag pre-existing file size)" framing.
    - Source: superpowers v5.0.7 `skills/subagent-driven-development/spec-reviewer-prompt.md` and `code-quality-reviewer-prompt.md`.
  - Acceptance criteria:
    - [ ] `task-verifier.md` contains a new section header matching `^#+ .*[Ee]xtra` (case-insensitive grep)
    - [ ] `task-verifier.md` contains the literal phrase `verify by reading code, not by trusting`
    - [ ] `reviewer.md` architecture lens contains the literal phrases `decomposed` AND `tested independently`
    - [ ] Both files contain the literal string `Source: superpowers v5.0.7`
    - [ ] PASS / FAIL:fixable / FAIL:escalate verdict format in `task-verifier.md` is unchanged: all three of `VERDICT: PASS`, `VERDICT: FAIL:fixable`, `VERDICT: FAIL:escalate` still grep-present
    - [ ] `bash tests/test-hooks.sh` exit code is 0
    - [ ] Smoke test: `wc -l` after > before for both files (proves additive edit, not replacement) AND files start with `---` YAML frontmatter

- [ ] **TASK-002: Add `responding-to-review` agent + wire into /review-team**
  - Files touched: `agents/responding-to-review.md` (new), `CLAUDE.md` (one line in agent inventory), `commands/review-team.md` (one-line mention in Step 5 decision gate)
  - Changes:
    - Create new agent file with YAML frontmatter (name, description, tools: Read+Grep+Glob+Bash(git*), model: sonnet)
    - Body adapts superpowers' 6-step pattern (READ → UNDERSTAND → VERIFY → EVALUATE → RESPOND → IMPLEMENT)
    - Include forbidden-phrase list (no "You're absolutely right", "Great point", etc.)
    - Include YAGNI check + push-back-when-wrong section
    - Cite source at top
    - Update `CLAUDE.md` Subagents section to list the new agent (one line)
    - Update `commands/review-team.md` Step 5 to suggest dispatching `responding-to-review` after presenting findings (prevents orphan-agent status flagged by failure-mode reviewer)
  - Acceptance criteria:
    - [ ] `agents/responding-to-review.md` exists with valid YAML frontmatter (file starts with `---`, has name/description/tools/model fields, ends frontmatter with `---` before line 20)
    - [ ] File contains all 6 step verbs literally: `READ`, `UNDERSTAND`, `VERIFY`, `EVALUATE`, `RESPOND`, `IMPLEMENT` (each greppable as standalone uppercase tokens)
    - [ ] File contains a "Forbidden phrases" or "Do NOT" section listing at minimum: `You're absolutely right`, `Great point`, `Excellent feedback` (each as a string to avoid)
    - [ ] File cites source: literal string `superpowers v5.0.7` present
    - [ ] `CLAUDE.md` contains the string `responding-to-review` in the Subagents list
    - [ ] `commands/review-team.md` Step 5 references `responding-to-review` agent
    - [ ] `install.sh` unchanged (confirmed: install.sh:169 uses `agents/*.md` glob; new file picked up automatically)
    - [ ] `bash tests/test-hooks.sh` exit code 0

- [ ] **TASK-003: Rewrite kit-health output voice**
  - Files touched: `commands/kit-health.md` (Step 2 output template + new Step 3.5 "Rejection summary" framing)
  - Changes:
    - Rewrite the Step 2 report template from neutral PASS/FAIL list to a rejection-first verdict (`SHIP / FIX-REQUIRED / REJECT`)
    - Add a "What this kit will reject" section in Step 3 (philosophy alignment), borrowed verbatim-style from superpowers' "What We Will Not Accept"
    - Keep all existing bash checks unchanged
    - Cite source
  - Acceptance criteria:
    - [ ] Step 2 template uses verdict values `SHIP`, `FIX-REQUIRED`, or `REJECT` (greppable)
    - [ ] New section header containing "reject" or "Rejection" exists in Step 3
    - [ ] All 10 numbered bash checks (1. File count, 2. Hook executability, ..., 10. TODOs/FIXMEs) are still present and unchanged (greppable by their existing comment headers)
    - [ ] File cites source: superpowers v5.0.7
    - [ ] No regression: file is still valid markdown with YAML frontmatter

### Phase 2: Verification + docs (orchestrator-level, not a worker task)

- [ ] Run `bash tests/test-hooks.sh` after all 3 tasks (must exit 0)
- [ ] Mental task-verifier pass on each TASK
- [ ] Mental review-team pass: security (any leaked credentials? no - prompt-only changes), architecture (do new prompts fit existing agent dispatch model? yes - same Task tool interface), test-coverage (test-hooks.sh covers underlying bash; prompt content is verified by grep checks above)
- [ ] CHANGELOG entry under `[Unreleased]` or `[1.3.0]`
- [ ] `docs/decisions.md` ADR-008 with adoption rationale
- [ ] `docs/dependencies.md` unchanged (no new deps)

## Acceptance Criteria (global)

- [ ] All 3 task acceptance criteria met
- [ ] `bash tests/test-hooks.sh` passes (40+ existing assertions still green)
- [ ] No file deleted
- [ ] No bash hook modified (only markdown prompt content)
- [ ] Source citation present in every modified/created file
- [ ] CHANGELOG and decisions.md updated
- [ ] Atomic commits: 1 per TASK + 1 for docs (4 commits total) on master

## Edge Cases

1. **Verifier's "extra work" check causes false positives.** A worker that adds a sensible helper function alongside the requested change might get flagged. Mitigation: the prompt addition explicitly says "small incidental changes (formatting, imports, helpers used by the change) are acceptable; new features are not". Borrowed from existing scope check in `task-verifier.md` line 51-52.
2. **`responding-to-review` agent never gets dispatched.** It's a new agent with no command currently invoking it. That's fine; it's available when needed, similar to how `security-auditor` exists but is dispatched only by `/review-team` on demand. A future enhancement could have `/review-team` suggest dispatching it after producing findings.
3. **kit-health "REJECT" verdict scares contractors.** Possible. Mitigation: "REJECT" only fires on critical philosophy violations (e.g., compiled binary present, hook over 500ms). For minor issues, verdict is `FIX-REQUIRED`. Tone is opinionated, not punitive.
4. **AGENTS.md "94%" stat is fabricated for our kit.** We don't have rejection data. Mitigation: don't lift the stat. Lift the *framing* (numbered MUST list, concrete consequences, "what we will not accept"). Voice without falsified numbers.

## Out of Scope

- New slash command for `responding-to-review` (defer until usage demand). The agent is dispatchable via Task tool when needed.
- Rewriting `CLAUDE.md` template to add a "responding to review" section (CLAUDE.md is passive context; the agent is the active mechanism).
- Modifying `/review` or `/review-team` to auto-dispatch the new agent (separate v1.4 task; this v1.3 just adds the capability).
- Hook for receiving-review (e.g., a Stop-hook that runs after `/review` completes). Not yet a proven pattern.
- Changing the underlying bash checks in `kit-health.md` (only the output framing changes).
- Multi-harness plugin packaging (already on v2 roadmap).
- Adopting the superpowers `<HARD-GATE>` pattern for `/think` (deferred; `/think` works adequately).

## Decision Log

- **DEC-001**: TASK-002 implemented as a new agent file (`agents/responding-to-review.md`), not a CLAUDE.md section.
  - **Rationale**: Agents are dispatchable on demand; CLAUDE.md is passive context that may not be the active reference when feedback arrives. Matches our agent-based pattern (8 existing agents).
  - **Rejected alternative**: CLAUDE.md section. Cheaper but less likely to fire at the right moment.
  - **Rejected alternative**: New skill in `skills/`. We only have one skill (`get-api-docs`) and skills are Claude-triggered, not command/event-triggered. Agent fits better.

- **DEC-002**: All 3 tasks share one phase, sequential dispatch.
  - **Rationale**: Independent (no shared files, no ordering constraint), but small enough that parallel dispatch overhead exceeds the wall-clock savings. Sequential keeps the orchestrator's state simple.

- **DEC-003**: Don't lift the "94% PR rejection rate" number from superpowers' AGENTS.md.
  - **Rationale**: We don't have that data for our kit. Lifting a fabricated stat violates "no phantom features" from CLAUDE.md template. Lift voice and structure, not numbers.

- **DEC-004**: Single ADR (`ADR-008`) covers all three adoptions, not three ADRs.
  - **Rationale**: One coherent decision (adopt patterns from superpowers v5.0.7), three artifact-level applications. Splitting would fragment the rationale across files.

- **DEC-005**: TASK-001 covers two files (task-verifier + reviewer) in one task because they share the same source material (subagent-driven-development reviewer prompts) and the same source citation line.
  - **Rationale**: Atomicity check (Scope Critic): touches 2 files, description fits in one paragraph, 7 acceptance criteria. Within the 5-files / 3-sentences / 5-bullets heuristic from `/spec-validate`. Acceptable.

## Source citations

- `superpowers v5.0.7` (https://github.com/obra/superpowers, commit `main` at 2026-04-21)
- `skills/subagent-driven-development/spec-reviewer-prompt.md` -- "extra / unneeded work" category, "verify by reading code, not by trusting report" framing
- `skills/subagent-driven-development/code-quality-reviewer-prompt.md` -- "decomposed for independent testability", "what this change contributed" framing
- `skills/receiving-code-review/SKILL.md` -- 6-step pattern, forbidden-phrase list, YAGNI check, push-back-when-wrong
- `AGENTS.md` -- rejection-first voice, numbered MUST list, "what we will not accept" structure
