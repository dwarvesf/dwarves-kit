# Spec: v1.6 (upstream-audit absorption + lineage hygiene)

Generated: 2026-05-20
Status: SHIPPED (v1.6.0)
Source: upstream-audit-2026-05-20 (this session's audit of the 10 source repos against current upstream HEADs)
Prior spec: docs/specs/SPEC-001-polish.md
Validation: 4 reviewers run 2026-05-20 (security, failure-mode, assumption-destroyer, scope-critic). 1 critical + 8 warnings resolved inline. See Decision Log entries DEC-006 through DEC-014.

## Problem

The 2026-05-20 upstream audit checked the 10 repos dwarves-kit pattern-matched from (GSD, gstack, Trail of Bits, ClaudeKit, Context Hub, oh-my-claudecode, CCGS, OMC, Smart Ralph, obra/superpowers) against their current HEADs. Five concrete gaps surfaced:

1. **No behavioral test for `/review-team`.** superpowers v5.1.0 ships a test that plants known-bad fixtures (SQL injection, plaintext password) and asserts the security lens flags every one. We have 42 hook tests + 104 meta tests but zero behavioral assertions on what the review pipeline actually catches. The v1.5.1 retro lesson "verify before proceeding" has no hard-test equivalent for the review side of the pipeline.
2. **No structural check on agent/command frontmatter.** CCGS v1.0 fixed missing `model:` and `description:` frontmatter across 17 skills in a recent audit. Our `tests/test-meta.sh` checks `name:` and `description:` on agents but does NOT assert `model:` is present or `description:` is on commands. Same class of bug we caught in v1.5.1 (plugin.json version drift): grep-only checks pass while structural parity silently rots.
3. **`/start` output is one-size-fits-all.** GSD v1.43-rc2 added tiered help (`--brief`, default, `--full`). Our `/start` always emits the same level of detail. Returning users want a one-line cue; new users want the full state-detection report. No way to dial.
4. **OMC source lineage in README Credits does not trace.** The audit could not anchor v1.2's task-verifier pattern to `1mancompany/OneManCompany` (the repo currently associated with the "OMC" name); that project is a pixel-art agent-company OS, not an architect-verifier pattern. Either re-anchor to a real source or own the pattern as synthesized from the family of architect-verifier loops.
5. **PHILOSOPHY.md has no explicit "won't accept" section for upstream anti-patterns.** The audit observed four anti-patterns in upstream repos (vendor-skill sprawl, UI-shell creep, agent-persona theater, slop-PR submissions) that we want to actively reject. Today PHILOSOPHY enumerates rejected ideas implicitly through "Decision this would reject" snippets. A dedicated section makes the rejection wall scannable.

## Solution

Five additive content edits. No new hooks. No new commands. No new agents. No new dependencies.

| Task | Files | Type |
|---|---|---|
| TASK-1 | `tests/test-review-team-plants.sh` (new) + `tests/test-meta.sh` (link) | New test |
| TASK-2 | `tests/test-meta.sh` (extend) | Extend test |
| TASK-3 | `commands/start.md` (refactor) | Modify command |
| TASK-4 | `README.md` (Credits) + `docs/decisions/0005-separate-verifier-subagent.md` (Source) | Lineage edit |
| TASK-5 | `docs/PHILOSOPHY.md` (new section) | Append philosophy |

Tasks are independent. No inter-task dependencies; can run in any order.

## Task Breakdown

### Phase 1: Tests (run first so subsequent task work is verified)

- [ ] **TASK-1: Behavioral test for `/review-team` security lens**
  - Files: `tests/test-review-team-plants.sh` (new)
  - Approach: the test creates a fixture dir via `mktemp -d "$TMPDIR/dwarves-kit-test.XXXXXX"` with planted-bad files (Python file with a string-interpolated SQL query; config file with a hardcoded credential; shell script using `os.system($user_input)` shape). Trap-based cleanup removes the fixture on exit. The test then runs a static check: greps the kit's security review prompts for the required detection vocabulary. The grep terms below are pre-verified as already present in current prompts (see DEC-006). No prompt edits required.
  - Required grep terms (must appear in EITHER `agents/security-auditor.md` OR `agents/reviewer.md`):
    - "SQL injection"
    - "Command injection"
    - "Path traversal"
    - "XSS"
    - "hardcoded" (matches: hardcoded API keys / passwords / tokens / secrets)
    - "PII"
    - "CORS"
  - Acceptance criteria:
    - [ ] `tests/test-review-team-plants.sh` exists, executable (`chmod +x`), runs in under 5 seconds
    - [ ] Uses `mktemp -d "$TMPDIR/dwarves-kit-test.XXXXXX"` for the fixture dir; trap-based cleanup runs on EXIT
    - [ ] Fixture dir contains at least 3 planted vulnerability files covering 3 distinct classes from the required-terms list above
    - [ ] Test greps each required term in BOTH `agents/security-auditor.md` and `agents/reviewer.md`; FAIL if any term is missing from BOTH files (a term in either file is OK; the reviewer's security lens inherits security-auditor's checklist per the prompt's own statement)
    - [ ] Test exits 0 on current kit (verified at spec time via pre-check)
    - [ ] Test would exit non-zero if a future edit drops any required term from BOTH prompts
    - [ ] Added to `.github/workflows/test.yml` alongside the existing two test scripts (same matrix, same job)
    - [ ] No fixture data committed to repo (fixture dir is under `$TMPDIR`, not under the repo root)
  - Source: superpowers v5.1.0 `tests/security-fixtures/` pattern. Adapted: superpowers can dispatch a real reviewer in their test environment; we cannot, so we test the prompt completeness instead. Same intent (regression-guard the reviewer), different mechanism.

- [ ] **TASK-2: Frontmatter parity audit in `tests/test-meta.sh`**
  - Files: `tests/test-meta.sh` (extend, ~25 lines). **No source-file edits required** (pre-check at spec time confirmed all 9 agents have `model:` and all 12 commands have frontmatter + `description:`).
  - Approach: add assertions for every `commands/*.md` and `agents/*.md`: file starts with `---`, contains `description:`, and (for agents) contains `model:` with a value in the accepted set `{sonnet, haiku, opus}`. The existing meta test checks `name:` + `description:` on agents already; this extends to `model:` on agents and frontmatter + `description:` on commands.
  - Acceptance criteria:
    - [ ] Every `commands/*.md` is asserted to have YAML frontmatter starting with `---` and a `description:` field
    - [ ] Every `agents/*.md` is asserted to have a `model:` field whose value matches `^(sonnet|haiku|opus)$` (after stripping whitespace)
    - [ ] Total meta test count rises by approximately 33 (12 commands x 2 checks + 9 agents x 1 check)
    - [ ] All tests land green on current kit (no source-file fixes needed per pre-check)
    - [ ] If any future agent uses a model value outside the accepted set, the assertion fails and the maintainer updates EITHER the file OR the regex (whichever is correct given the actual Claude Code model surface at that time)
  - Source: CCGS v1.0 skill audit pattern. Adapted: same structural-integrity intent, scoped to the kit's commands + agents.

### Phase 2: User-facing surface

- [ ] **TASK-3: Tiered `/start` output (`--brief` / default / `--full`)**
  - Files: `commands/start.md` (modify), `MANUAL.md` (arg-shape doc)
  - Approach: command prompt grows three modes via Claude Code's `$ARGUMENTS` substitution. `--brief` outputs one line. Default keeps existing output BYTE-FOR-BYTE (regression-safe). `--full` adds: full SPEC.md task checklist, hook log summary (counts only, NOT raw lines), last 5 commits, full command table grouped by phase.
  - Sub-step: confirm the kit's slash-command runtime supports `$ARGUMENTS` (Claude Code's documented placeholder); if a different mechanism applies on the deployed Claude Code version, adapt and document the actual mechanism in the command file's body.
  - Acceptance criteria:
    - [ ] `commands/start.md` references `$ARGUMENTS` (or the actual runtime-supported placeholder, if different, with a body comment naming what it is)
    - [ ] `--brief` output is a single line, max 120 characters including any leading prefix, contains current state + suggested next command
    - [ ] **Default-mode regression check**: the prompt's default-mode behavior is byte-for-byte identical to the current prompt; only `--brief` and `--full` code paths are added. Verify by diffing the post-edit default-mode pseudocode against the current file's prompt body; the diff must show only additions in `--brief` / `--full` branches
    - [ ] `--full` output adds: SPEC task checklist (parsed from `.planning/SPEC.md` checkboxes), hook log activity as **line counts per log file from the last 7 days only** (NOT raw log content, to avoid leaking paths or command fragments), last 5 commits via `git log -5 --oneline`, command table grouped by Think/Spec/Build/Review/Ship/Reflect phases
    - [ ] CHANGELOG entry mentions `--brief` and `--full`
    - [ ] MANUAL.md `/user:start` section updated with the new arg shape and example outputs
  - Source: GSD v1.43-rc2 `gsd-help --brief|--full|<topic>` pattern. Adapted: `--brief / --full` only (no `<topic>` mode per DEC-002; the kit's state space is small enough that section-level help is overkill).

### Phase 3: Documentation hygiene

- [ ] **TASK-4: OMC lineage correction**
  - Files: `README.md` (Credits section), `docs/decisions/0005-separate-verifier-subagent.md` (Source line), `CHANGELOG.md` (v1.6 entry)
  - Approach: 10-minute search for Option A (re-anchor to a real architect-verifier-in-Ralph-loop source, e.g. Geoff Huntley's "Ralph Wiggum" post at `https://ghuntley.com/ralph/`). If Option A passes verification, take it. Otherwise default to Option B (own as synthesized). See DEC-003 + DEC-011.
  - **"Verified" criterion for Option A**: the candidate URL returns HTTP 200 AND the fetched page contains at least one of these phrases (case-insensitive): "architect verifier", "verifier loop", "verify after execution", "Ralph loop". Capture the `archive.org` snapshot URL at citation time alongside the live URL, so the citation survives future link rot.
  - Acceptance criteria:
    - [ ] README Credits no longer lists OMC pointing at `1mancompany/OneManCompany`
    - [ ] If Option A taken: cited URL returns 200, content contains one of the required phrases, AND the citation in README Credits includes both the live URL and an archive.org snapshot URL captured during this task
    - [ ] If Option B taken: ADR-0005's Source line is updated to "Synthesized from the family of architect-verifier-in-Ralph-loop patterns documented across AI-coding-agent projects in 2024-2025" and README Credits has the OMC bullet removed
    - [ ] CHANGELOG v1.6 entry includes a "Lineage correction: OMC credit removed" bullet under `Fixed`
    - [ ] No silent drift between README Credits and ADR-0005 Source line (both updated in the same commit)
  - Source: 2026-05-20 upstream audit, lineage-correction recommendation. Decision codified in DEC-003.

- [ ] **TASK-5: PHILOSOPHY.md "What we explicitly reject (from upstream observation)" section**
  - Files: `docs/PHILOSOPHY.md` (append new section, ~40 lines)
  - Approach: add a new section after the principles enumeration that lists 4 anti-patterns observed in upstream projects with explicit rejection rationale. Each anti-pattern names the observed example, the principle it violates, and the kit-level criterion that would catch it in review.
  - Acceptance criteria:
    - [ ] New PHILOSOPHY.md section heading: `## What we explicitly reject (from upstream observation)`
    - [ ] Lists exactly 4 anti-patterns: vendor-skill sprawl, UI-shell creep, agent-persona theater, slop-PR submissions
    - [ ] Each anti-pattern has: one-line description, observed example with repo + version, principle violated, and the review-criterion that catches it
    - [ ] CONTRIBUTING.md gets a one-line cross-reference to the new section under "What we will not accept"
    - [ ] `commands/kit-health.md` rejection list (Step 4) updated if any of the 4 anti-patterns are not already there
  - Source: 2026-05-20 upstream audit, anti-patterns column.

### Phase 4: Verify, docs, ship

- [ ] All 5 task acceptance criteria met
- [ ] `bash tests/test-hooks.sh` exit 0 (42/42)
- [ ] `bash tests/test-meta.sh` exit 0 (104+ tests; new count documented)
- [ ] `bash tests/test-review-team-plants.sh` exit 0 (new)
- [ ] CHANGELOG entry under `[1.6.0]` listing all 5 tasks
- [ ] No new ADR for v1.6 itself (changes additive within existing principles). ADR-0005 Source line edit per TASK-4 is a correction, not a new decision.
- [ ] `VERSION` -> `1.6.0`
- [ ] `.claude-plugin/plugin.json` version bumped to match (regression from v1.5.0 caught by `test-meta.sh` parity check)
- [ ] Atomic conventional commits, one per TASK + 1 docs + 1 version bump
- [ ] Tag `v1.6.0`
- [ ] Flip this file's Status header to `SHIPPED` after the v1.6.0 tag lands (no move needed; the spec was drafted directly at `docs/specs/SPEC-002-upstream-audit.md` per the post-cleanup convention)
- [ ] Write `docs/retro/v1.6.md` after ship per the v1.5.1 retro action item ("add /retro to every release ritual")
- [ ] Write `docs/handoff/v1.6.md` after ship (per v1.5.1 retro convention; build-narrative complementary to CHANGELOG's what-shipped record). See DEC-012.

## Acceptance Criteria (global)

- [ ] All 5 task ACs met
- [ ] Hook tests: 42/42
- [ ] Meta tests: 104+ (rises with TASK-2 frontmatter checks)
- [ ] Behavioral test: passes
- [ ] No file deleted; no breaking changes; no new dependencies
- [ ] No new env var, no new settings.json field
- [ ] README Credits is self-consistent with ADR Source citations after TASK-4

## Edge Cases

1. **TASK-1's static prompt grep is too weak.** If the security-auditor prompt doesn't literally say "SQL injection" (the prompt may use "injection attack" or similar), the test fails on TASK-1 day one. Mitigation: read both prompts during TASK-1 implementation, choose grep terms that genuinely appear AND that we want to lock in as required vocabulary. If a term is missing from the current prompt, fix the prompt as part of TASK-1, not the test.
2. **TASK-2 reveals current files miss `model:` frontmatter.** Likely true for at least some commands. Mitigation: fix in-file FIRST, then add the assertion. AC explicitly forbids landing a red test.
3. **TASK-3 default-mode regression risk.** `/start` is invoked both by user typing and (per ADR-0009 pattern) potentially by SessionStart hook readouts. Mitigation: AC includes "Default output unchanged from current behavior". Confirm by diffing current and post-edit default outputs before merge.
4. **TASK-4 Option A's source verification fails mid-task.** Geoff Huntley's "Ralph Wiggum" post may not exist, may be deleted, may not actually describe the architect-verifier pattern as we used it. Mitigation: 10-minute search budget; if Option A fails, fall back to Option B without further search.
5. **TASK-5 anti-patterns overlap existing rejection criteria.** The audit's anti-patterns may already be captured implicitly in PHILOSOPHY's "Synthesize, don't originate" or "Bash over binaries". Mitigation: AC requires each anti-pattern have a distinct example + principle. If an anti-pattern is genuinely already covered, drop it from the list rather than duplicate.

## Out of Scope

- The 4 DEFER items from the audit (oh-my-claudecode HUD cache GC, gstack `/freeze`+`/unfreeze`, Smart Ralph thin-orchestrator refactor, Smart Ralph `references/` extraction). These remain in `_meta/BACKLOG.md` v2 candidates. No spec work this cycle.
- The 3 SKIP items (Trail of Bits stable; ClaudeKit vendor-skill drift; Context Hub npm-only). No action.
- Multi-harness packaging (still deferred per ADR-0009).
- Submitting to Anthropic's `claude-plugins-official` marketplace (manual maintainer step; not blocking).
- `/qa` command, Agent Teams parallel dispatch, `SessionEnd` knowledge-capture hook (all v2 candidates with no signal yet).
- Rewriting OMC lineage in CHANGELOG.md (historical record stays frozen per the v1.5.1 retro convention).

## Decision Log

- **DEC-001**: TASK-1 implements as a static-grep assertion on reviewer prompts, NOT as a live `/review-team` dispatch.
  - **Rationale**: bash CI cannot dispatch Claude Code sessions; the kit has no test-harness equivalent. A static grep on the prompt content catches regressions in WHAT we ask reviewers to look for, which is the actual failure mode we observed when adopting superpowers v5.1.0 (reviewers drift, prompts get edited, vulnerability classes silently dropped). Live dispatch belongs in a maintainer's manual `/user:kit-health` run, not CI.
  - **Rejected alternative**: shell out to Claude Code via headless. Too brittle, requires API keys in CI, adds external dep.

- **DEC-002**: TASK-3 supports `--brief` and `--full` only, no `<topic>` mode.
  - **Rationale**: GSD has dozens of commands and a richer state model that justifies topic-level help. dwarves-kit has 12 commands and a flat state model. `--brief` + default + `--full` covers the 3 user shapes (returning, default, new). A `<topic>` mode would be carrying superpowers we don't need.
  - **Rejected alternative**: also add `--commands` to dump just the command list. Same content available via `--full`. YAGNI.

- **DEC-003**: TASK-4 takes Option B (own as synthesized) UNLESS a verifiable source can be cited in 10 minutes.
  - **Rationale**: honesty beats elegance. Citing a wrong source is worse than admitting we synthesized the pattern. Time-box the source hunt to avoid yak-shaving.
  - **Rejected alternative**: keep the OMC bullet "for historical reasons". No, the v1.5.1 retro's lesson is that broken citations rot and confuse future readers. Fix it now.

- **DEC-004**: TASK-5 explicitly avoids lifting the "94% PR rejection rate" stat from superpowers.
  - **Rationale**: same logic as ADR-0008's stat-lifting rejection. We have no rejection-rate data of our own. Adopting voice and structure is fine; adopting numbers we did not measure is phantom-feature territory.

- **DEC-005**: No new ADR for v1.6 itself.
  - **Rationale**: all 5 tasks fit within existing principles. ADR-0005 gets a Source-line correction (TASK-4), not a new decision. PHILOSOPHY gets a new section (TASK-5), which is content addition, not a principle change.

- **DEC-006**: TASK-1 grep-term list locked at spec time, not implementation time.
  - **Rationale**: spec-validate Critical 1. The most-subjective decision in TASK-1 was being pushed into the worker's context. Pre-checking which terms exist in current prompts at spec time means TASK-1 lands with zero prompt edits (current prompts already cover the locked 7-term set). If the implementer finds a term genuinely missing, that becomes a separate scoped sub-task, not silent prompt mutation.

- **DEC-007**: TASK-1 fixture lives under `$TMPDIR`, never in the repo.
  - **Rationale**: spec-validate Security finding 2. Planted SQL-i and credential strings inside the repo are scanning-hazardous (security scanners + future grep audits may snag on them). Using `mktemp -d` + trap-cleanup gets the fixture out of the repo lifecycle entirely.

- **DEC-008**: TASK-2 scope locked to test-extension only; no source-file fixes needed.
  - **Rationale**: spec-validate Scope finding 3. Pre-check showed all 9 agents have `model:`, all 12 commands have `description:` + frontmatter. The spec's original "fix files first" hedge was based on an assumption that pre-check invalidated.

- **DEC-009**: TASK-3 default-mode regression check is a body-diff assertion in the AC.
  - **Rationale**: spec-validate Failure finding 4. "Default unchanged" needs a verification mechanism. Added explicit AC: prompt body diff shows only additions in `--brief` / `--full` branches.

- **DEC-010**: TASK-3 `--full` log activity is line counts only, no raw lines.
  - **Rationale**: spec-validate Security finding 7. Hook logs may contain command fragments with secret-bearing paths or args. Counts give signal without leak.

- **DEC-011**: TASK-4 "verified" criterion for Option A is HTTP 200 + required-phrase presence + archive.org snapshot.
  - **Rationale**: spec-validate Failure finding 8. Vague "10-minute search" needs a concrete pass/fail bar. The phrase list is the same conceptual content we claim the source covers; archive snapshot insulates against future link rot.

- **DEC-012**: `docs/handoff/v1.6.md` is in scope for Phase 4.
  - **Rationale**: spec-validate Assumption finding 9. v1.5.1 retro recommended every release produces both retro AND handoff. Spec originally listed retro but not handoff; closing that gap. Handoff captures build narrative (what was decided, where surprises happened); retro captures cycle-level lessons; CHANGELOG captures what shipped. Three different layers, three different files.

- **DEC-013**: TASK-3 slash-command arg passing uses `$ARGUMENTS` placeholder.
  - **Rationale**: spec-validate Assumption finding 5. Today's kit commands take no args; `$ARGUMENTS` is Claude Code's documented pattern. Sub-step requires confirming the placeholder actually substitutes on the deployed Claude Code version; if not, the body of `commands/start.md` documents the actual mechanism.

- **DEC-014**: TASK-3 `--brief` length cap is 120 characters single line, not "~20-40 words".
  - **Rationale**: spec-validate Scope finding 6. Word ranges aren't testable; character cap is.

## Source citations

- TASK-1 pattern: obra/superpowers v5.1.0 (https://github.com/obra/superpowers, fetched 2026-05-20). Specifically the security-fixture behavioral test pattern.
- TASK-2 pattern: CCGS v1.0 (https://github.com/Donchitos/Claude-Code-Game-Studios) skill frontmatter audit.
- TASK-3 pattern: GSD v1.43-rc2 (https://github.com/gsd-build/get-shit-done) tiered `gsd-help` command.
- TASK-4: 2026-05-20 upstream audit findings.
- TASK-5: 2026-05-20 upstream audit anti-patterns column.

## Validation

To be filled by `/spec-validate`. Status flips to `VALIDATED` only after all 4 reviewers (security, failure-mode, assumption-destroyer, scope-critic) report no blocking concerns.
