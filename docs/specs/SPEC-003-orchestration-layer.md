# Spec: Orchestration layer (the workflow contract)

Generated: 2026-05-20
Status: VALIDATED
Source: agent-workflow-enforcement research, 2026-05-20 (full landscape + enforcement taxonomy at `ops-toolkit/research/2026-05-20-agent-workflow-enforcement-patterns.md`). Inspiration: hoangnb24/harness-experimental `AGENTS.md`; obra/superpowers; github/spec-kit; bmad-code-org/BMAD-METHOD; Cline Memory Bank; ghuntley/ralph; the AGENTS.md standard.
Prior spec: docs/specs/SPEC-002-upstream-audit.md
Validation: 4 reviewers run 2026-05-20 (scope-critic, assumption-destroyer, failure-mode, philosophy-fidelity). 6 blocking + multiple warnings resolved inline; see Decision Log DEC-006 through DEC-013 and the Validation section.

## Problem

dwarves-kit covers the whole lifecycle (`/think → /spec → /execute → /review → /ship → /retro`), but the *workflow itself* is not written down as one artifact an agent can follow. It is scattered: the data-flow diagram lives in `docs/architecture.md` (maintainer-facing, descriptive), the per-phase instructions live inside each command prompt, the soft "what's next" routing lives in `hooks/context-readiness.sh`, and the principles live in `docs/PHILOSOPHY.md`. A coding agent told "build this feature" has no single instruction file that says: here are the phases, here is how to size the work, here is the gate at each boundary, here is who enforces it.

The community pattern for this is the **harness/orchestration layer**: a single instruction file (harness-experimental's `AGENTS.md`, Spec Kit's command templates, superpowers' `using-superpowers`) that embeds the end-to-end workflow the agent must follow, as distinct from a library of *atomic* skills/commands. The research note distilled how these files make a stochastic agent comply, and the one load-bearing finding: **markdown cannot enforce a workflow on its own; it only biases the next token. Real enforcement comes from a mechanism outside the prose: a loop, a re-read-this-file discipline, or a test gate.**

dwarves-kit already owns the strongest such mechanism (the verification pipeline). What it lacks is the readable spine that names the workflow and routes work by size. This spec adds that spine without violating the kit's two governing tensions: **"Guardrails over guidance"** (advice is ~70%; enforce with hooks) and **"Detect, don't dictate"** (no rigid phase gates).

## Decision: chosen version

**Ship a single agent-facing `WORKFLOW.md` contract at the repo root, delivered through `CLAUDE.md` (which Claude Code auto-loads every session), that routes work by risk tier and delegates every hard gate to the guardrails that already exist.**

The orchestration layer is two things, not one new mechanism:

1. **`WORKFLOW.md`** (new doc, repo root): the readable spine. Required-reading order, a risk-tier intake table, a phase→exit→enforcer map, and a completion contract. Voiced in the kit's opinionated register. Short enough to read in under a minute.
2. **Risk-tiered intake** (the one net-new idea, cited to harness-experimental): a `tiny / normal / full` lane router so trivial work skips the ceremony. Routing by work size is "Detect, don't dictate" applied to process weight, and it addresses the "full lifecycle on a one-line fix" failure Anthropic explicitly warns about.

**Delivery is via `CLAUDE.md`, not the `context-readiness` hook.** Claude Code natively loads `CLAUDE.md` into context at the start of every session (100% present, the strongest delivery available for a guidance-grade artifact). `CLAUDE.md` gains a one-line pointer to `WORKFLOW.md`; the doc rides that native load. The earlier draft routed delivery through a one-line addition to `context-readiness.sh`; that is **cut** (DEC-002). By this spec's own thesis a markdown pointer in a hook string is still guidance, it does not make the doc "active," and it carried a real `set -euo pipefail` failure mode plus a compaction-durability gap (`post-compact-reinject` does not know the file). Cutting it is more minimal and removes a false "active delivery" claim. No hook is touched by this spec.

Crucially, the contract **suggests and routes; it does not block.** Every hard stop is an existing guardrail: the safety-gate hook (destructive Bash), the push-to-main blocker, the anti-rationalization Stop hook (premature "done"), and the verification pipeline (worker → task-verifier → fix-agent, max 2). `WORKFLOW.md` names these gates and points at them; it invents no new ones and uses no coercion prose.

**Form chosen: `WORKFLOW.md` referenced from `CLAUDE.md`, not a second auto-loaded `AGENTS.md`, and not a section folded into `architecture.md`.** The kit is Claude-Code-native and `CLAUDE.md` is its single instruction channel; a competing auto-loaded `AGENTS.md` would create two sources of truth (violates "One kit, whole cycle"). A separate file rather than an `architecture.md` section is required because downstream projects ship `WORKFLOW.md` (via `examples/hello-spec/`) but do **not** ship the kit's `architecture.md`; the contract must stand alone. The AGENTS.md *pattern* is the cited source; the filename is the adaptation.

### Tradeoff table (chosen vs rejected alternatives)

| | **CHOSEN: WORKFLOW.md + CLAUDE.md pointer + risk tiers** | Alt A: `/user:flow` autopilot command | Alt B: BMAD/Spec-Kit hard-gate machine (HALT/CAPS) | Alt C: passive standalone AGENTS.md | Alt D: new section inside architecture.md |
|---|---|---|---|---|---|
| Single readable spine | yes | no (logic in a command prompt) | yes | yes | yes |
| "Detect, don't dictate" | honored (suggests + routes, blocks nothing) | violated (runs think→ship in one shot) | violated (phase-locking is a verbatim rejection) | honored | honored |
| "Guardrails over guidance" | honored (gates = existing hooks/verifier; doc openly guidance-grade) | partial | violated (CAPS prose ~70-85%; ADR-0008) | partial | honored |
| Delivery | CLAUDE.md native auto-load (100% present each session) | a command (must be invoked) | passive-ish | passive (ADR-0008: "may not be the active reference") | rides architecture.md (read on demand) |
| One source of truth | yes (CLAUDE.md → WORKFLOW.md) | yes | risky (logic in two places) | no (two auto-loaded files) | yes |
| Downstream portability | yes (template ships standalone) | no (command is kit-internal) | n/a | yes | **no (downstream gets no architecture.md)** |
| Source lineage | harness-experimental intake + AGENTS.md pattern | Spec Kit `/implement` | BMAD/Spec-Kit gates | AGENTS.md standard | n/a |

Alt A rejected: a full-cycle autopilot dictates the whole sequence (anti "Detect, don't dictate") and duplicates `/start` (routing) plus `/execute` (build autopilot). Alt B rejected: hard phase gates are an explicit PHILOSOPHY rejection, and coercion CAPS is the exact ~70-85% guidance ADR-0008 chose hooks over. Alt C rejected: ADR-0008 passivity precedent, plus a second auto-loaded instruction file breaks single-source-of-truth. Alt D rejected: the strongest minimalism option, but `architecture.md` is maintainer-facing and is not shipped to downstream projects, so an agent-facing contract folded into it cannot travel; the verb-split (descriptive map vs imperative spine) also keeps the two genuinely distinct.

### Enforcement-taxonomy mapping

Every design element maps to a named row in `ops-toolkit/research/2026-05-20-agent-workflow-enforcement-patterns.md` Part 5. Three rows are deliberately declined, which is itself a design decision (DEC-005).

| Taxonomy mechanism | How this design uses it |
|---|---|
| Programmatic backpressure (tests/lint gate completion) | **Delegated** to the verification pipeline (worker → task-verifier → fix-agent) + the ship gate. The kit's existing moat; `WORKFLOW.md` points at it, does not reinvent it. |
| Forced state-file re-read | `.planning/SPEC.md` (downstream) / `docs/specs/SPEC-NNN` (kit-on-kit) is the re-read state; `WORKFLOW.md` lists it as required reading. |
| Harness re-injects rules each turn | `CLAUDE.md` is auto-loaded by Claude Code each session and points at `WORKFLOW.md`. (Presence-each-session, not mid-session re-read; see Known limitations.) |
| Self-audit pass | The anti-rationalization Stop hook catches premature completion; the completion contract phrases the self-check. |
| Anti-fabrication clause | Completion contract: "done only when the verifier has actually run the tests, not when you claim they pass" → points at task-verifier. |
| Risk-tiered routing | **New element.** The `tiny / normal / full` intake table, cited to harness-experimental. Self-attested, not detected (see Known limitations). |
| Next-step lock-in (soft) | The existing `context-readiness` hook's `next:` suggestion + `/start`; suggestion only, never a lock. Unchanged by this spec. |
| Identity / stake framing | **Declined.** Persona theater is an anti-pattern (ADR-0008 rejects skill coercion). |
| Outer bash `while` loop | **Declined.** Autonomous-runtime territory; PHILOSOPHY §3 routes that to GSD v2 / OMC. The kit is one-session. |

### PHILOSOPHY check

| Principle | Compliance |
|---|---|
| Guardrails over guidance | ✓ All enforcement delegated to existing hooks + verifier. The doc is openly labeled guidance-grade; it never claims its prose enforces. |
| Synthesize, don't originate | ✓-with-caveat. Workflow-file pattern cited to harness-experimental + AGENTS.md standard. The risk-tier router is **net-new, single-source, experimental-grade lineage** (harness-experimental is an experimental repo, not 3-months-in-production). Accepted under the "indirect lineage / originated in-kit but grounded" carve-out (PHILOSOPHY §1) and labeled as such; it has NOT met the §5 "1 week on a real project" bar. See Known limitations. |
| One kit, whole cycle | ✓ Single source of truth preserved: `CLAUDE.md` → `WORKFLOW.md`; references the spec + `architecture.md` rather than copying them. No new format. |
| Shallow and wide beats deep and narrow | ✓ Indexes all 8 phases at spine depth; adds no per-phase depth. (`WORKFLOW.md` is connective tissue across the lifecycle, like `architecture.md`; it does not "serve" a phase the way `/spec` or task-verifier does. Justified as cross-phase connective tissue, NOT under the "serves 2+ phases" gate.) |
| Verify before proceeding / Verify, then trust | ✓ The completion contract and Build gate defer to the verification pipeline. |
| Bash over binaries | ✓ One doc + one template + pointer edits + one meta test. No binary, no runtime, no hook touched. |
| Detect, don't dictate | ✓ Routes by risk tier and indexes next phases; blocks nothing (verified: no code change adds blocking behavior). Hard stops remain the existing safety/verify hooks. The doc says plainly "this contract does not lock phases." |
| External tools are dependencies, not features | ✓ No new external dependency. |
| NO list (§3) | ✓ No compiled binary, no paid dep, no LLM API in a hook, no hook touched, one-sentence describable, source-cited. File budget: current 79 files → 81 (+2: root doc + downstream template). No hard cap; each new file justified. |

One-sentence description (NO-list gate 4): *"`WORKFLOW.md` is the agent-facing contract that names each lifecycle phase, routes work by risk tier, and points at the existing guardrail that enforces each boundary."*

## Solution

Additive. One new doc, one new template, pointer edits, one meta test. No new command, no new agent, no new dependency, no hook touched, no new hard gate.

| Task | Files | Type |
|---|---|---|
| TASK-1 | `WORKFLOW.md` (new, repo root; `docs/specs/` paths per ADR-0002) | New doc |
| TASK-2 | `CLAUDE.md` (Workflow section → pointer, kit root) + `examples/hello-spec/CLAUDE.md` (Workflow body → pointer, **keep the `## Workflow` header**) + `examples/hello-spec/WORKFLOW.md` (new template; `.planning/` paths) | Pointer edits + template |
| TASK-3 | `tests/test-meta.sh` (assert both WORKFLOW.md files exist, four pinned headers, and path correctness) | Extend test |
| TASK-4 | `README.md` + `MANUAL.md` + `docs/architecture.md` (one-line cross-reference each) + CHANGELOG | Doc hygiene |

### Task Breakdown

**Phase 1: The artifact**
- [ ] **TASK-1: Author `WORKFLOW.md`** at repo root. Content = the embedded draft below. Kit-root version uses `docs/specs/SPEC-NNN-<slug>.md` in required-reading (per ADR-0002), NOT `.planning/`.
  - Acceptance: file exists; ≤ ~80 lines; contains the four headers pinned in TASK-3; every gate named maps to an existing hook/agent/command (no invented gate); kit's opinionated register; no CAPS coercion; no em dash in any header (ASCII-clean headers so the meta grep is stable).

**Phase 2: Single source of truth + downstream template**
- [ ] **TASK-2: Replace, don't duplicate.** Shrink the kit-root `CLAUDE.md` "Workflow" section to a one-line pointer to `WORKFLOW.md`. Add `examples/hello-spec/WORKFLOW.md` (downstream template, same shape, `.planning/SPEC.md` paths). In `examples/hello-spec/CLAUDE.md`, **keep the `## Workflow` H2 header** (the demo CLAUDE.md is section-tested by `test-meta.sh`) and replace only its body with the pointer line.
  - Acceptance: no workflow step list exists in two places after this task; kit-root `CLAUDE.md` Workflow section is a pointer; demo `## Workflow` header survives; downstream template present, self-consistent, uses `.planning/`; `architecture.md` data-flow diagram is referenced by `WORKFLOW.md`, not copied.

**Phase 3: Guardrail**
- [ ] **TASK-3: Structural test in `tests/test-meta.sh`.** New block titled `=== WORKFLOW.md contract ===` (distinct from the existing `=== Workflow file ===` CI-YAML block). Assert, matching on stable ASCII prefixes:
  - `WORKFLOW.md` exists and contains `^## Required reading`, `^## Size the work first`, `^## The cycle`, `^## Completion contract`
  - `examples/hello-spec/WORKFLOW.md` exists and `grep -q '.planning/SPEC.md'` in it
  - kit-root `WORKFLOW.md` `grep -q 'docs/specs/'`
  - Acceptance: meta count rises from 104 to 110 (+6); green on the kit after TASK-1/TASK-2; would fail if a future edit drops a required section or swaps the path convention. The four assertion strings MUST byte-match the embedded-draft headers (verified internally consistent in this spec).

**Phase 4: Hygiene**
- [ ] **TASK-4: Cross-references.** One-line pointer to `WORKFLOW.md` from `README.md`, `MANUAL.md`, and `docs/architecture.md` ("imperative companion to the data-flow diagram below"). CHANGELOG entry. Reconcile the canonical phase count (PHILOSOPHY says "7" in one place and "9" in another; this spec standardizes on **8**: Think, Spec, Validate, Build, Review, Docs, Ship, Reflect) in the same docs pass.

**Phase 5: Verify**
- [ ] `bash tests/test-hooks.sh` exit 0 (42/42; no hook touched, so unchanged)
- [ ] `bash tests/test-meta.sh` exit 0 (110)
- [ ] No workflow step list duplicated across files
- [ ] No new command, agent, dependency, env var, settings.json field, or hook edit
- [ ] CHANGELOG entry under the next version
- [ ] Flip this spec's Status to SHIPPED after the tag

## Embedded draft artifact: `WORKFLOW.md`

> The complete kit-root draft to land as TASK-1. The downstream template (TASK-2) is identical except required-reading line 2 reads `.planning/SPEC.md`. Kept short by design. Headers are ASCII-clean to keep the TASK-3 grep stable.

```markdown
# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The only hard stops are the
> safety-gate hook, the push-to-main blocker, the anti-rationalization Stop
> hook, and the verification pipeline.

## Required reading (in order)
1. CLAUDE.md            - project context: stack, structure, rules
2. docs/specs/SPEC-NNN-<slug>.md - the active spec; the shared contract for the cycle
3. docs/architecture.md - how the pieces fit (reference; not required per task)

## Size the work first (risk-tiered intake)
Pick a lane before you start. Smaller work skips ceremony.

| Lane   | When | Path |
|--------|------|------|
| tiny   | typo, copy, comment, one obvious edit | edit, verify, done. No spec. |
| normal | one bounded feature or fix | /spec, /execute, /review, /ship |
| full   | touches auth, authz, data model, data loss, audit/security, an external provider, an API contract, a migration, or weakens validation | /think, /spec, /spec-validate, /execute, /review-team, /docs, /ship, /retro |

When in doubt between two lanes, take the heavier one. Anything in the full-lane
trigger list uses the full lane unless you explicitly narrow the scope and say why.

## The cycle (phase, exit, enforcer)
| Phase    | Command | Exit when | Enforced by |
|----------|---------|-----------|-------------|
| Think    | /user:think | decision brief written (if BUILD) | advisory |
| Spec     | /user:spec | spec exists, Status: DRAFT | spec-drift-guard hook |
| Validate | /user:spec-validate | Status: VALIDATED | advisory (full lane) |
| Build    | /user:execute or /user:next | tasks checked, verifier PASS | verification pipeline (worker, verifier, fix; max 2) |
| Review   | /user:review or /user:review-team | review verdict recorded | advisory |
| Docs     | /user:docs | README/CHANGELOG match code | advisory |
| Ship     | /user:ship | tagged + PR | ship gate (blocks on FIX-REQUIRED), push-to-main blocker |
| Reflect  | /user:retro | docs/retro/v<version>.md written | advisory |

Throughout: safety-gate blocks destructive Bash; anti-rationalization blocks
premature "done"; auto-format runs on edit; session-state-save and
post-compact-reinject protect long sessions.

## Completion contract
A task is done only when its acceptance criteria are met and the verifier has
actually run the tests, not when you claim they pass. If you cannot run the
check, report that plainly; the anti-rationalization hook is the backstop for
premature completion. Self-reported "done" is not proof; the task-verifier is.

## What this contract does NOT do
It does not lock phases. An experienced operator may skip /spec-validate on a
normal-lane change or go straight to /next. The kit detects state
(context-readiness hook) and suggests the next step; it never blocks
progression. Hard stops are reserved for irreversible cost: destructive
commands, push-to-main, premature completion, failed verification.
```

## Acceptance Criteria (global)
- [ ] `WORKFLOW.md` exists, ≤ ~80 lines, four required sections present, headers ASCII-clean
- [ ] Every gate named maps to a real existing hook/agent/command (no invented gate)
- [ ] No CAPS coercion prose anywhere in the artifact
- [ ] Workflow step list exists in exactly one place (others are pointers)
- [ ] Demo `## Workflow` header survives; demo template uses `.planning/`; kit-root uses `docs/specs/`
- [ ] Meta test asserts both files, four pinned headers, and path correctness; count is 110
- [ ] No new command, agent, dependency, env var, settings.json field, or hook edit
- [ ] CHANGELOG entry; phase count reconciled to 8 across PHILOSOPHY + WORKFLOW.md

## Known limitations
1. **The doc is guidance-grade by design.** Per the kit's own thesis, markdown biases but does not enforce. Its real enforcement is delegated to the verification pipeline + safety hooks. The genuinely new payload is the risk-tier table; the rest restates guardrails the agent already gets at 100% from the hooks. This is acceptable: the contract's job is to *name and route*, not to enforce.
2. **Risk-tier classification is self-attested, not detected.** The agent picks its own lane, and an agent biased toward completion may under-classify to skip ceremony (pick "tiny" on work that deserves "full"). There is no diff-scanner forcing the lane. Mitigation: the safety-gate, push-to-main blocker, and anti-rationalization hook still fire regardless of lane, so a mis-classified change cannot do irreversible damage; it can only skip *ceremony*. A future spec could add a real detector (grep the diff for auth/migration patterns) if mis-classification shows up in retros. Not built now (no signal yet; PHILOSOPHY §5 bar).
3. **`WORKFLOW.md` and `architecture.md` can drift.** Mitigation: `WORKFLOW.md` links to the data-flow diagram rather than restating it, and the TASK-3 test asserts section headers (not command names) to avoid ossification. The phase-order agreement between the two is a ship-time reviewer check, which is guidance-grade; accepted because the cost of drift here is confusion, not breakage.

## Edge Cases
1. **Phase/command name drift.** TASK-1 uses live command names; TASK-3 asserts section headers, not command names, so it will not ossify the command list.
2. **Two path conventions.** Downstream template uses `.planning/`; kit-root uses `docs/specs/` (ADR-0002). TASK-3 asserts each path in the correct file so a copy-paste error is caught.
3. **No `WORKFLOW.md` in a repo.** Nothing breaks: `CLAUDE.md` simply has a pointer to a file that is absent until the project adds it. No hook depends on the file (the hook edit was cut).

## Out of Scope
- A `/user:flow` autopilot command (Alt A, rejected).
- Any new hard phase gate, hook, or hook edit (anti "Detect, don't dictate"; the hook delivery was cut).
- Coercion/persona prose (anti ADR-0008).
- A diff-scanning risk detector (Known limitation 2; deferred until a real mis-classification signal exists).
- An outer execution loop / multi-session orchestration (GSD v2 / OMC territory per PHILOSOPHY §3).
- Claiming the `AGENTS.md` filename / dual auto-loaded instruction files (Alt C, rejected).
- Multi-harness packaging of `WORKFLOW.md` (deferred per ADR-0009).

## Decision Log
- **DEC-001**: Form is `WORKFLOW.md` referenced from `CLAUDE.md`, not a standalone auto-loaded `AGENTS.md` (single source of truth) and not a section in `architecture.md` (which is not shipped downstream). The AGENTS.md *pattern* is the cited source; the filename is the adaptation.
- **DEC-002**: The `context-readiness.sh` pointer (in the prior draft) is **cut**. Rationale (scope-critic B2 + assumption-destroyer W1 + failure-mode BLOCK-3): a markdown pointer in a hook string is still guidance by this spec's own thesis, it does not make the doc "active," it carried a `set -euo pipefail` trailing-`&&` abort risk for every repo without the file, and `post-compact-reinject` does not surface the file. `CLAUDE.md` native auto-load is the honest, stronger, zero-code-change delivery. No hook is touched.
- **DEC-003**: Risk-tiered intake is the only net-new idea, accepted under the indirect-lineage carve-out and labeled as single-source/experimental, not as a battle-tested pattern. Source: harness-experimental `FEATURE_INTAKE.md` lane model, simplified to one trigger list (no flag-counting arithmetic) per scope-critic W3. It has not met the §5 1-week-on-a-real-project bar; that is recorded as Known limitation 1, not hidden.
- **DEC-004**: No hard gates added. All hard stops remain the existing safety/verify hooks; the contract names and points at them.
- **DEC-005**: Identity-framing and outer-loop mechanisms from the taxonomy are deliberately declined (persona theater per ADR-0008; loops are autonomous-runtime territory). Declining is recorded so a future reader does not "add them back."
- **DEC-006**: The persona-theater decline is grounded in "Synthesize, don't originate" + ADR-0008 (which exist today), NOT in PHILOSOPHY's proposed "v1.6 explicit-reject list." Rationale (philosophy-fidelity B1): SPEC-002 is only VALIDATED, so that section is not in live `PHILOSOPHY.md`; citing it would be forward-dated. If/when SPEC-002 ships, a docs pass may re-anchor.
- **DEC-007**: Risk-tier table simplified to one trigger list, no numeric flag-counting (scope-critic W3). "2-3 flags / 4+ flags" arithmetic is process weight, not relief; a plain "touches auth/data/contracts → full" trigger is lighter and more "Detect, don't dictate."
- **DEC-008**: `WORKFLOW.md` is justified as cross-phase connective tissue (like `architecture.md`), NOT under the NO-list "serves 2+ phases" gate (scope-critic B3). Indexing phases is not serving them; the honest justification is lifecycle-connective-tissue, the same basis `architecture.md` stands on.
- **DEC-009**: File-budget stated as honest arithmetic: 79 → 81 (+2 files), no hard cap, each justified (scope-critic B1 + assumption-destroyer W5). The earlier "net-neutral" framing was a byte-count claim mislabeled as a file-count claim.
- **DEC-010**: Kit-root embedded draft uses `docs/specs/` in required-reading, not `.planning/` (failure-mode WARN-3 + ADR-0002). The downstream template uses `.planning/`. TASK-3 asserts each.
- **DEC-011**: TASK-3 assertion strings are pinned verbatim to the embedded-draft headers, matched on ASCII prefixes (failure-mode BLOCK-2). Headers are ASCII-clean (no arrows, no em dash) so the grep cannot drift on Unicode.
- **DEC-012**: TASK-2 keeps the demo `## Workflow` H2 header and replaces only the body (failure-mode BLOCK-1); `test-meta.sh` section-tests the demo CLAUDE.md.
- **DEC-013**: Canonical phase count standardized at 8; PHILOSOPHY's 7-vs-9 internal inconsistency reconciled in the TASK-4 docs pass.

## Source citations
- Workflow-file / harness pattern: hoangnb24/harness-experimental `AGENTS.md` + `HARNESS.md` + `FEATURE_INTAKE.md` (fetched 2026-05-20).
- Risk-tier intake: harness-experimental `FEATURE_INTAKE.md` lane model. Simplified to one trigger list.
- Workflow-in-instruction-file pattern + the "markdown biases, mechanism enforces" finding: `ops-toolkit/research/2026-05-20-agent-workflow-enforcement-patterns.md`.
- Delivery via CLAUDE.md native auto-load + enforcement-over-coercion stance: ADR-0008.

## Validation
4 reviewers run 2026-05-20 (scope-critic, assumption-destroyer, failure-mode, philosophy-fidelity). Aggregate pre-fix verdict: FIX-REQUIRED.

Blocking concerns, all resolved inline:
- Hook-edit false "active" premise + `set -e` bug + compaction gap → TASK-2 hook edit cut (DEC-002).
- Forward-dated "v1.6 reject list" citation → re-grounded in existing principles (DEC-006).
- "Serves 2+ phases" gate gamed → re-justified as connective tissue (DEC-008).
- "Net-neutral file budget" false → honest 79→81 arithmetic (DEC-009).
- Kit-root draft hardcoded `.planning/` → switched to `docs/specs/` (DEC-010).
- TASK-1 headers vs TASK-3 assertions unpinned → pinned ASCII prefixes (DEC-011); demo `## Workflow` header preserved (DEC-012).

Warnings addressed: risk-tier self-classification skew recorded as Known limitation 2; risk-tier arithmetic simplified (DEC-007); "Synthesize" mark downgraded to ✓-with-caveat with the experimental-lineage gap stated; "forces"/"stop" prose softened to advice-grade in the embedded draft; phase count reconciled (DEC-013).

Status flipped to VALIDATED after inline resolution. Re-run `/user:spec-validate` if the design changes materially before execute.
