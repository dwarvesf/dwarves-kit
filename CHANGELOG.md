# Changelog

All notable changes to dwarves-kit are documented here.

## [Unreleased]

### Changed

- **Dropped hand-maintained component counts and stripped spec IDs from the WORKFLOW contract.** The exact `N hooks / N commands / N agents / N skill` strings are removed from every live surface (`.claude-plugin/{plugin,marketplace}.json`, `README.md`, `MANUAL.md`, `CLAUDE.md`, the `docs/architecture.md` component table, `tool.toml`) and replaced with qualitative phrasing; the `92`/`238` test-suite-total comments in `CLAUDE.md` are dropped too. Counts rot silently: this swept up live drift the guards never caught (`architecture.md` said 19 commands, `tool.toml` said 12 hooks / 18 commands / 9 agents). With nothing left to keep in sync, both count tests in `tests/test-meta.sh` are removed (the ID-013 component-count guard added earlier this cycle and the older command-count parity test); meta suite 238 -> 213. `WORKFLOW.md` no longer cites `SPEC-NNN`/`ADR-NNN` inline (the `docs/specs/SPEC-NNN-<slug>.md` filename pattern stays): rules are stated by concept with one provenance pointer to `docs/specs/` + `docs/decisions/`, and the count-sweep chore paragraph is replaced by a version-only note. SPEC-004 + SPEC-005 `Status:` reconciled VALIDATED -> SHIPPED (shipped alongside SPEC-006).

### Added

- **`/user:ui-design` command + the downstream UI-design loop (SPEC-020)**: writes a structured `## UI design` brief (aesthetic-direction preamble + layout + states matrix + named viewports + a11y bars + 3-tier token ladder + voice) into the active spec (else the pre-spec brief), delegates generation to the external `frontend-design` skill (the kit ships no renderer), critiques via `/user:visual-team`, and runs a bounded auto-revise loop (E6 `<user-feedback>` injection-wrap, E7 unconditional accumulated-feedback re-send, terminate on SOLID / RECONSIDER / max-2 cap). Opt-in, report-only, downstream-facing (the PHILOSOPHY carve-out + kit-health allow-note now name both `/user:visual-team` and `/user:ui-design`). The kit is now 20 commands. Brief enriched per the 2026-05-21 deep scan (`docs/research/2026-05-21-ui-design-loop-deep-scan.md`): aesthetic-direction from `frontend-design`'s real input, token ladder + states matrix + a11y bars + voice adapted from `nextlevelbuilder/ui-ux-pro-max-skill` (its renderer / fonts / `.cjs`+`.py` tooling rejected per bash-over-binaries), loop shapes from gstack. Dogfooded through `/user:spec-validate` twice; the re-dogfood caught an unimplementable numeric stop (visual-team emits no combined score) and folded it to a SOLID-verdict stop. Credits: gstack (loop shapes), `frontend-design` (generator), `ui-ux-pro-max-skill` (brief sub-shapes). Source: SPEC-020.
- **`/user:absorb` command + the absorption ritual (SPEC-004)**: a maintainer-only, proposal-only external-absorption audit that generalizes SPEC-002/SPEC-014's one-shot surveys into a recurring ritual. `docs/ABSORPTION.md` carries it: two lanes (Credits drift re-audit + a seed-rescan of the SPEC-014 survey set, scanning the interest areas workflow/agents/QA/UI), the adoption rubric (>=10), the gate, and the **human merge gate** (discovery + scoring + drafting are automatic; adopting a source or adding it to Credits is maintainer-approved, preserving "synthesize, don't originate"). `/user:absorb` writes a dated, ranked + capped, proposal-only report under `docs/absorption/` (HEAD-SHA baseline for since-last-run, an overflow appendix so a real ADOPT is never dropped, a `git status` self-check); QA/UI candidates needing binaries route to "recommend external". The kit is now 19 commands. Think+Design narrowed lane B to a seed-rescan (web-search discovery deferred as tool-weak). Also corrected the plugin manifests' stale hook/agent counts (now 14 hooks / 11 agents). Source: SPEC-004 + `docs/ABSORPTION.md`; DATA-not-instructions guard from ADR-0008.
- **Reviewer 5 (Solution-Design & Extensibility Critic)** in `/user:spec-validate`: flags shallow or non-extensible designs, with a calibration clause (no false-positive storm) and a legacy-grace clause for specs predating the richer template. Source: SPEC-008; forked from `superpowers:brainstorming` ("design for isolation and clarity") + its spec-document-reviewer calibration. Not a runtime dependency.
- **I/O contract + Failure modes sections** in the `/user:spec` template, plus pointer bullets in `/user:spec-validate` Reviewer 2 (failure modes) and Reviewer 5 (I/O contract). Both sections optional + lane-scoped. Source: SPEC-009; forked from ops-toolkit SDD (`agency-lead-radar` / `tide`). Not a runtime dependency.
- **`/user:design` command (opt-in)**: an interactive solution-design beat between `/think` and `/spec` (propose 2-3 approaches one question at a time, present the design in sections, approve per section), appending the Solution to `docs/specs/DECISION-BRIEF.md` for `/spec` to fold in. Realizes SPEC-008 Part C; forked from `superpowers:brainstorming`. The kit is now 13 commands. Closes the "ran without my feedback" half of the original signal.
- **`/user:debug` command + `bug` lane (SPEC-013)**: a systematic debug loop (four phases: root cause -> pattern -> hypothesis -> fix) under the iron law "no fix without a recorded root cause," with an append-only evidence ledger (`.claude/debug/<slug>.md`), `[DEBUG Hn]`-tagged instrumentation to `.claude/debug/<slug>.log` plus region-marker cleanup, `git bisect` for regressions, failing-test-first routed into the existing verification pipeline, and human-confirm before declaring fixed. `WORKFLOW.md` gains a `bug` intake lane and an off-cycle Debug row. The kit is now 14 commands. Forked from `superpowers:systematic-debugging` + GSD `gsd-debugger` (evidence ledger) + doraemonkeys debug-mode (tagged logs, region cleanup) + SuperClaude `/sc:troubleshoot`; classic lineage Agans ("9 Indispensable Rules") + Zeller (delta debugging). **ADR-0012** records the command+hook hybrid as a refinement of ADR-0008.
- **`.claude/goals/` draft-store contract + state model (SPEC-005)**: documents the kit's three-store state model (`_meta/BACKLOG.md` queue, `docs/specs/` contract, `.claude/goals/` ephemeral drafts) in `docs/architecture.md`, a formal Active-queue Schema in `_meta/BACKLOG.md`, and the goal-draft store beside the built-in `/goal` (the kit never writes `last-goal.md`; activator-agnostic with graceful degradation). **ADR-0011** records the draft-store-not-a-shadow decision. No `/user:goals` command yet (deferred to SPEC-006).
- **`/user:assign` command + the orchestration spine (SPEC-006)**: wires the backlog Active queue -> `/user:assign ID-NNN` (goal-crafts a `.claude/goals/` draft, picks the lane from the item, detects the activator, hands off to the lane's first command; never executes, never writes `last-goal.md`, idempotent per id) -> the WORKFLOW lane -> ship. `/user:start` + `/user:next` now render the queue + goal drafts read-only. `WORKFLOW.md` gains a `## The spine` section and two warn+log completeness clauses (decision-translation + doc-update) with a doc-impact map reviewed by `/user:ship` + `/user:retro`; PHILOSOPHY section 3 gains a bounded/unbounded loop note covering both the goal and debug loops. The kit is now 15 commands (also corrects `.claude-plugin/{plugin,marketplace}.json`, stale at 13). Source: SPEC-006.
- **Three opt-in design-assurance lanes (SPEC-016)**: `/user:devs-team` and `/user:visual-team` add parallel multi-lens critique of a design (in the decision brief or the active spec) before it hardens (the design analogue of `/user:review-team`), and `/user:test-plan` derives a test-case coverage matrix from a spec's acceptance criteria before `/user:execute`. Generic house-style lenses, inline parallel Task dispatch, report-only verdicts, no hard gate. `/user:visual-team` is downstream-facing (recorded PHILOSOPHY carve-out so kit-health does not flag it). The kit is now 18 commands. Lenses adapted from `zvadaadam/az-skills` devs-roundtable + design-roundtable, recast as generic lenses; test-plan is the kit's own coverage shape. Source: SPEC-016.
- **Two guardrail hooks (SPEC-014): `secrets-guard` + `commit-format`.** `secrets-guard` (PreToolUse Read\|Edit\|Bash) blocks reads of secret files (`.env`, `~/.ssh`, `~/.aws`, `.pem`, keychains), canonicalizing the path first so `~`/`$HOME`/`..` spellings cannot bypass; fail-closed on a match, fail-open on parse error; allows `.env.example`. The Read/Edit deny plus a new `settings.json` `permissions.deny` block is the primary layer; the Bash-surface check is best-effort defense-in-depth (a reader denylist is bypassable, stated honestly, not exfil-proof). `commit-format` (PreToolUse Bash) blocks a `git commit -m` subject that is non-conventional, >72 chars, or carries a SPEC-/TASK-/phase marker (subject only; bodies + editor commits pass). The kit is now 14 hooks. **ADR-0014.** Sources: Trail of Bits deny-list + claudekit `file-guard` (secrets); GSD `gsd-validate-commit` (commit-format).
- **`integration-checker` agent (SPEC-021)**: a read-only adversarial cross-task verifier dispatched once at `/user:execute` Step 4 for multi-task specs, filling the seam between per-task `task-verifier` and the once-at-end full suite (which silently passes when integration tests are absent). It verifies each new component reaches its activation point (a hook registered, a handler mounted, an export imported AND called) and the spec's stated end-to-end chains, without inventing links between independent tasks; scoped read-only tools (no write/bare-Bash, meta-asserted, DEC-006); diffs the whole build via a pre-build base ref; reuses fix-agent for fixable wiring gaps. The kit is now 10 agents. **ADR-0015.** Source: GSD `gsd-integration-checker`.
- **`doc-verifier` agent (SPEC-022)**: a read-only fact-checker dispatched by `/user:docs` at a new Step 4.5 (after it applies updates, before the commit) that independently verifies the just-updated docs against the live code (counts, command/flag names, file paths, existence, cross-references), closing the fox-guards-henhouse gap where `/docs` was the only reader of what `/docs` wrote. It reads the uncommitted doc diff, flags only checkable contradictions (not phrasing or prose), and reports; `/docs` re-edits a `FAIL:fixable` (max 2 rounds, not fix-agent, since `/docs` is not the `/execute` pipeline). Scoped read-only tools (meta-asserted). The kit is now 11 agents and has three read-only verifiers (task-verifier / integration-checker / doc-verifier), all on the ADR-0005 pattern; the retro should confirm the trio pays off. **ADR-0016.** Source: GSD `gsd-doc-verifier`.

### Changed

- **`/user:devs-team` + `/user:visual-team` aligned to spec-first placement (SPEC-023)**: both critique lanes now write their `## Design critique` / `## Visual critique` into the active spec when one exists (else the pre-spec brief; visual-team else inline), matching `/user:test-plan` (SPEC-018) and `/user:ui-design` (SPEC-020). Previously `devs-team` wrote brief-first and `visual-team` had no spec path, so the WORKFLOW.md placement rule was true for two lanes and waived for two; now all four share the spec-first head (visual-team keeps an inline tail since it alone can run with neither artifact). Both resolve the active spec via the shared SPEC-005 detection and ask on a multi-match; a meta-test pins the spec-first wording (both of devs-team's read and write sides). **Supersedes SPEC-016's `## Design critique` / `## Visual critique` placement.** WORKFLOW.md's two tables drop the "predates the rule" caveats. Source: SPEC-023; dogfooded through `/user:spec-validate` (the assumption-destroyer lens caught a draft that misread SPEC-020's writer model, corrected before implementation).
- **`/user:test-plan` writes into the spec + `/user:execute` consumes it (SPEC-018)**: the coverage matrix moves from a root `TEST-PLAN.md` to a `## Test plan` section appended into the active spec (mirroring `/user:devs-team`'s `## Design critique`), and `/user:execute` now reads that section, injecting each task's cases into the worker prompt and using each case's `proof` command as the per-step verify. Fixes the SPEC-016 Part B orphan (the plan was produced but never consumed) and makes the plan multi-spec safe (each spec carries its own). Adds a `proof` column to the matrix (behavior-to-proof, adapted from harness-experimental's `TEST_MATRIX.md` Evidence column); `proof` is `TBD` when unknown, never fabricated. The `## Test plan` heading is pinned in both `test-plan.md` and `execute.md` by a meta-test (drift guard). **Supersedes SPEC-016 Part B's root-file placement.** Source: SPEC-018; dogfooded through `/user:spec-validate` (1 critical caught: the wiring was lexical, not behavioral, now fixed).
- **`/user:spec` Solution template**: replaced the one-line `## Solution` block with scaffolded sub-sections (Approaches considered, Chosen approach + why, Extensibility & boundaries, Architecture) so specs carry design depth by default. Source: SPEC-008; forked from `superpowers:brainstorming` ("propose 2-3 approaches"). The opt-in `/user:design` interactive beat is deferred behind the PHILOSOPHY §5 bar.
- **`/user:spec` template stop-criteria (SPEC-012 Part 1)**: pinned `## Verification` (the command(s) that prove a spec done) and `## Open questions` (the blocker landing zone a `/goal` loop appends to), so any validated spec is natively pointer-`/goal`-ready. Part 2 (the QA gate around the loop) is held until the pointer-`/goal` pattern has real runs.
- **`tests/test-meta.sh`**: spec-authoring depth + contract assertions (3 Solution sub-headings + Reviewer 5 + the 5-reviewers header + a stale-"4 reviewer" drift guard, SPEC-008; the I/O contract + Failure modes headings, SPEC-009; a no-stray-`.planning/` guard + the demo-migration assertions, SPEC-010; commands/design.md presence, SPEC-011; the Verification + Open-questions headings, SPEC-012 P1). Suite total: 121 → 135.
- **Unified the spec-location convention onto `docs/specs/SPEC-NNN-<slug>.md`** for both the kit and downstream projects (was: downstream `.planning/SPEC.md`). The 5 spec-aware hooks resolve the active spec from `docs/specs/` (interim selector: highest non-SHIPPED/PARKED `SPEC-NNN`; SPEC-005 dual-detect refines later) with a bounded `.planning/` deprecation fallback (removed next minor). Satellite artifacts: research -> `docs/research/`, retro -> `docs/retro/`, CONTEXT -> `docs/specs/CONTEXT.md`, decision-brief folded into the spec. The demo (`examples/hello-spec`) migrated. **ADR-0010 supersedes ADR-0002.** Source: SPEC-010 Part 1 (Part 2 worktree-safety pending).
- **Spec detection is now branch-aware (SPEC-005)**: `context-readiness.sh`, `spec-drift-guard.sh`, `commands/next.md`, `commands/start.md` resolve the active spec among non-SHIPPED/PARKED `docs/specs/` specs by git-branch slug match, emitting `spec:ambiguous(...)` instead of silently picking when several are live (replaces SPEC-010's interim highest-NNN selector); `spec-drift-guard` greps the union of all active specs. The leakage sweep extends to `agents/` (research agents write `docs/research/`, not `.planning/research/`). SPEC-005 was reconciled to ADR-0010 (docs/specs-first; `.planning` is the deprecation fallback) since it predated SPEC-010. Tests: test-hooks 42 → 52 (10 detection fixtures), test-meta +4 (state-model + agents guard).
- **`/user:execute` worker step expansion (SPEC-017)**: each worker now expands its task into bite-sized "smallest verifiable increment -> verify -> commit" steps before coding (TDD when a unit test fits; grep/bash/test-suite verify for the kit's doc and config tasks), instead of a 3-bullet sketch. Worker-side (orchestrator stays lean), no new command, no new artifact; the task-verifier runtime gate is unchanged. Folds writing-plans-grade granularity into the kit's idiom. Source: SPEC-017.
- **`hooks/anti-rationalization.sh` gains a gated guess-fix guard (SPEC-013)**: blocks a premature fix/done claim ONLY when an open `.claude/debug/` ledger still has an empty `## Root cause`; silent in all non-debug sessions (~26ms, under the 500ms budget). The command<->hook contract (the `## Root cause` heading literal) is pinned in both files by a `tests/test-meta.sh` assertion so it cannot silently drift (DEC-010).
- **`tests/test-hooks.sh` + `tests/test-meta.sh` (SPEC-013)**: 3 hook behavior cases for the guess-fix guard (block when undiagnosed; allow once root cause recorded; dormant outside a debug session) and 13 meta assertions for the debug command structure, the DEC-010 cross-file `## Root cause` pin, and the WORKFLOW bug lane. Suite totals: hooks 52 → 55, meta 135 → 148.
- **`safety-gate.sh` + `anti-rationalization.sh` + `install.sh` (SPEC-014)**: `safety-gate` gains a build-artifact allowlist (a single `rm -rf node_modules/dist/.next/target/...` passes; compound commands still block) plus `DROP TABLE` / `git reset --hard` / `kubectl delete` blocks; `anti-rationalization` gains a phantom-implementation guard (a completion claim + an unimplemented-stub line such as `raise NotImplementedError` in the diff's added lines blocks, anchored so code that merely names the marker does not self-trigger); `install.sh` now unions `permissions.deny` on merge (was hooks-only). `tests/test-hooks.sh` adds 33 behavior cases and the hook-count assertion moves 12 → 14 (suite to 92 green); `test-meta.sh` parity auto-covers the two new hooks (178 green). A fresh-context code review caught and fixed three issues before merge: an `rm -rf node_modules/../..` traversal escape in the allowlist (now rejects any `..` token), a symlink bypass in secrets-guard (now resolves symlinks via `realpath` and matches both forms), and JSON-injection on a path containing a quote (now emits via `jq`). Sources: gstack `careful` (safety-gate), claudekit `self-review` (phantom-impl).

### Fixed

- **`context-readiness.sh` + `session-state-save.sh` count fragility**: `find ... | grep -v` and `grep -c ... || echo 0` both mishandled the zero-match case under `set -e`/pipefail. In a source-file-free repo the hook aborted with no output; a spec with 0 done tasks rendered `tasks:0\n0/N` plus an `integer expected` error. Now uses `{ grep -v ... || true; }` and `grep -c ... || true`. Found during SPEC-010 execution (ID-013).
- **`install.sh` never materialized the hooks `settings.json` references (SPEC-025)**: settings hard-code every hook (and the statusline) at `$HOME/.claude/dwarves-kit/hooks/<script>.sh`, but the bash installer only `chmod`'d the scripts at its own `$KIT_DIR/hooks/`, merged settings, and created `logs/`. That coincidence held only for the documented in-place clone (README Option 2: clone to `~/.claude/dwarves-kit`); from a dev checkout or CI clone elsewhere, `~/.claude/dwarves-kit/` got only `logs/` and all 14 hooks plus the statusline pointed at missing files, so a fresh session opened with `SessionStart ... No such file or directory` and every hook was silently dead. `install.sh` now links each `hooks/*.sh` into `~/.claude/dwarves-kit/hooks/` when the kit lives elsewhere (per-file symlinks, mirroring the existing `commands/` step, so dev edits stay live), detects the in-place layout and skips linking (a naive loop there deletes the real scripts and leaves broken self-referential symlinks, a regression the first cut shipped and the SDD pass then caught), and the uninstall removes only the symlinks it created. `tests/test-meta.sh` gains a 3-assertion guard (referenced scripts exist in `hooks/`; an isolated out-of-place install resolves every path; an in-place install keeps the scripts resolvable) so neither failure mode can regress past CI. Meta suite 213 -> 216.

## [1.6.0] - 2026-05-20

Orchestration layer (SPEC-003) plus upstream-audit absorption and lineage hygiene (SPEC-002).

### Added

- **`WORKFLOW.md`** (repo root): the agent-facing workflow contract. Names each lifecycle phase, routes work by risk tier (tiny / normal / full), and points at the existing guardrail that enforces each boundary. Delivered via the `CLAUDE.md` pointer (auto-loaded each session); it suggests and routes, it does not block. Downstream template ships at `examples/hello-spec/WORKFLOW.md` (`.planning/` path convention). Source: SPEC-003; harness-experimental intake model + the AGENTS.md pattern.
- **`tests/test-review-team-plants.sh`**: behavioral regression guard for the `/review-team` security lens. Plants 3 known-bad fixtures under `$TMPDIR` (trap-cleaned, never in the repo) and asserts the security-review prompts still carry the detection vocabulary for each class; a term missing from both `security-auditor.md` and `reviewer.md` fails the build. Wired into CI. Source: superpowers v5.1.0 (SPEC-002 TASK-1).
- **Tiered `/user:start`**: `--brief` (one line, state + next command) and `--full` (SPEC task checklist, hook-log line counts, recent commits, phase-grouped command map) via `$ARGUMENTS`; default output is byte-for-byte unchanged. Source: GSD v1.43-rc2 (SPEC-002 TASK-3).
- **`tests/test-meta.sh`**: 6 assertions for the WORKFLOW.md contract (SPEC-003) plus a `model:` parity check on every agent, value in `{sonnet,haiku,opus}` (SPEC-002 TASK-2). Suite total: 104 → 120 (the extra check is the new CONTRIBUTING.md cross-link from TASK-5).

### Changed

- **`CLAUDE.md` Workflow section** (kit root + `examples/hello-spec/`): replaced the duplicated step list with a pointer to `WORKFLOW.md`, so the cycle lives in exactly one place.
- **`docs/PHILOSOPHY.md`**: reconciled the canonical lifecycle phase count to 8 (Think, Spec, Validate, Build, Review, Docs, Ship, Reflect; was 7 in one place and 9 in another), and added a "What we explicitly reject (from upstream observation)" section enumerating four audited anti-patterns (vendor-skill sprawl, UI-shell creep, agent-persona theater, slop-PR submissions). `CONTRIBUTING.md` and `commands/kit-health.md` cross-reference it, and the same 9→8 count fix was applied in both. Source: SPEC-002 TASK-5.
- **`README.md`, `MANUAL.md`, `docs/architecture.md`**: one-line cross-reference to `WORKFLOW.md` (the architecture pointer frames it as the imperative companion to the data-flow diagram).

### Fixed

- **OMC lineage correction**: the `task-verifier` pattern no longer claims the unverifiable "OMC" anchor. The README Credits bullet is removed and ADR-0005's Source line now owns the pattern as synthesized from the family of architect-verifier-in-Ralph-loop patterns. Source: SPEC-002 TASK-4 / DEC-003.

## [1.5.1] - 2026-04-21

Audit-fix release. Same-day patch following a retroactive `/review-team` and `/retro` that surfaced gaps in the v1.4/v1.5 SDLC application.

### Fixed

- **`plugin.json` version drift**: `.claude-plugin/plugin.json` was still declaring `1.4.0` after VERSION bumped to `1.5.0`. Now bumped to `1.5.1` and asserted by `tests/test-meta.sh` (parity check between VERSION and plugin manifest). The bug shipped briefly in v1.5.0; v1.5.0 tag is preserved in history.

### Added

- **`tests/test-meta.sh`**: 62 new assertions covering structural integrity that grep-only checks miss. Validates: plugin manifest schema (including version-matches-VERSION parity), hooks.json/settings.json hook count parity, all hooks.json paths use `${CLAUDE_PLUGIN_ROOT}`, every agent/command markdown file has YAML frontmatter with required fields, CLAUDE.md Subagents list bidirectionally matches `agents/*.md`, demo project files have all required template sections, workflow has explicit permissions block, CONTRIBUTING.md cross-links resolve. Test suite total: 42 → 104.
- **CI hardening**: workflow now runs `tests/test-meta.sh` alongside `tests/test-hooks.sh`. `actions/checkout` pinned to release SHA (supply-chain best practice). Explicit `permissions: contents: read` (least privilege).
- **`docs/retro/v1.3-v1.5.md`**: cycle retrospective covering what worked, what hurt, action items. First retro since the kit started; addresses the action item to make `/retro` part of the release ritual.

### Changed

- **README "Project structure" section**: replaced the embedded file tree (drifted across 5 releases, last accurate at v1.0) with a concise top-level overview pointing at `git ls-files` for the canonical listing. Removes a recurring drift surface.
- **README "Changelog" section**: removed the duplicated highlight bullets (last updated at v1.2.0). CHANGELOG.md is now sole source of truth for version history.
- **README "v2 roadmap"**: removed "Plugin marketplace packaging" (shipped in v1.4); added "Multi-harness packaging" deferred line.
- **`examples/hello-spec/README.md`**: added a one-line synthetic-demo disclaimer at the bottom (the `spm` package is fictional; the file shapes are real).

## [1.5.0] - 2026-04-21

### Added

- **GitHub Actions CI** (`.github/workflows/test.yml`): runs `bash tests/test-hooks.sh` on push to `master` and on every PR. Matrix: macOS + Ubuntu. Also validates all JSON files (`plugin.json`, `marketplace.json`, `hooks.json`, `settings.json`) parse cleanly.
- **CI status badge in README** (top of file alongside version, license, Claude Code plugin badges).
- **README hero section**: tagline, badge row, value prop, "Who this is for" / "Who this is NOT for" sections, prominent plugin install command. First-screen visible to anyone landing on the repo.
- **Demo project at `examples/hello-spec/`**: small self-contained walkthrough showing real `CLAUDE.md`, `.planning/SPEC.md`, and a README that explains how the kit picks each file up. Demo subject: a Python CLI's `--version` flag.
- **`CONTRIBUTING.md`** at repo root: rejection-first voice (adapted from superpowers v5.0.7 AGENTS.md, same source as v1.3 kit-health). Numbered MUST list before opening a PR. "What we will not accept" enumerates PHILOSOPHY.md's actual rejection criteria with cross-links.

### Notes

- All changes are additive. No breaking changes. No removals.
- No new ADR: every change fits within existing principles. PHILOSOPHY.md unchanged.
- README's component count line updated to "9 agents" (was "8"); tracks the `responding-to-review` agent added in v1.3.
- CI is **descriptive**, not enforcing: PRs that fail CI are flagged but not auto-blocked. Enforcement still lives in the `safety-gate` hook locally.

## [1.4.0] - 2026-04-21

### Added

- **Claude Code plugin packaging**: Kit now installs via `/plugin marketplace add dwarvesf/dwarves-kit` + `/plugin install dwarves-kit@dwarves-marketplace`. No `git clone`, no bash, no `jq` required. Updates via `/plugin update dwarves-kit`.
- **`.claude-plugin/plugin.json`**: Plugin manifest with name, version, description, author, homepage, repository, keywords. Auto-discovers `agents/`, `commands/`, `skills/` directories.
- **`.claude-plugin/marketplace.json`**: Self-hosted marketplace manifest. Single-plugin marketplace named `dwarves-marketplace` pointing at the repo root.
- **`hooks/hooks.json`**: Plugin-format hook registration. Same 12 hooks across 8 event types as the bash install path. Uses `${CLAUDE_PLUGIN_ROOT}` for path-portable script references.
- **README dual install section**: Plugin install presented first as recommended path. Bash install retained as alternative for CI / older Claude Code versions / non-plugin contexts. One-line note about Anthropic official marketplace submission via https://claude.ai/settings/plugins/submit.

### Changed

- **`docs/decisions.md`**: Added ADR-009 documenting the dual-ship deviation from PHILOSOPHY's "Replace, don't deprecate" with explicit rationale and sunset trigger.

### Notes

- This is an additive release. The bash installer (`install.sh`) and root `settings.json` are unchanged. Existing installs continue to work without action.
- **Do not run both install paths on the same machine.** Hooks would register twice. Pick one.
- Plugin install does not configure `statusLine` (not in v1 plugin schema). Use the bash install if you want the statusline HUD.

## [1.3.0] - 2026-04-21

### Added

- **`responding-to-review` agent**: New subagent that responds to code review findings with verify-before-implement, no performative agreement, YAGNI check, and push-back-when-wrong. Wired into `/review-team` Step 5 so the FIX-THEN-SHIP path can dispatch it. Source: superpowers v5.0.7 `skills/receiving-code-review/SKILL.md`, adapted from a Skill (auto-discovered) to a custom subagent (dispatched on demand).
- **`task-verifier` "Extra / unneeded work" check (Section 3b)**: Verifier now explicitly checks whether the worker built features that weren't requested, over-engineered, or added nice-to-haves outside the spec. Distinct from the existing file-scope check. Source: superpowers v5.0.7 `skills/subagent-driven-development/spec-reviewer-prompt.md`.
- **`reviewer` (architecture lens) decomposition + contribution checks**: New bullets for "decomposed for independent testability" and "what this change contributed (don't flag pre-existing file size)". Source: superpowers v5.0.7 `skills/subagent-driven-development/code-quality-reviewer-prompt.md`.
- **`commands/kit-health` rejection-first verdict**: Output template now produces `SHIP / FIX-REQUIRED / REJECT` verdicts with explicit gate rules. New Step 4 "What this kit will reject" section enumerates 10 auto-REJECT conditions grounded in PHILOSOPHY.md. Source framing: superpowers v5.0.7 `AGENTS.md` "What We Will Not Accept".

### Changed

- **`task-verifier` Rules**: Added "Verify by reading code, not by trusting the worker's report" as the first rule. Source: superpowers v5.0.7 spec-reviewer-prompt.
- **`commands/review-team` Step 5**: FIX-THEN-SHIP path now suggests dispatching `responding-to-review` to handle the findings without performative agreement.
- **`CLAUDE.md`**: Added `responding-to-review` to the Subagents inventory.
- **`docs/decisions.md`**: Added ADR-008 covering the superpowers v5.0.7 adoption.

### Fixed

- **`tests/test-hooks.sh`**: Stale assertion `expected 10 event hooks` updated to `12` to match actual settings.json count (drift since v1.2 added SubagentStop and StatusLine entries). Test suite now reports 42/42 instead of 41/42.

## [1.2.0] - 2026-03-30

### Added

- **Verification pipeline**: /execute now runs worker > task-verifier > fix-agent retry loop (max 2) for every task. No task is accepted without verification.
- **8 custom agents**: task-verifier (read-only verification), fix-agent (targeted fixes), reviewer (configurable lens), security-auditor (OWASP audit), research-stack, research-features, research-architecture, research-pitfalls (4 parallel brownfield researchers).
- **/start command**: entry point router that detects project state and suggests next command. Source: CCGS /start.
- **/review-team command**: parallel 3-lens review dispatching security + architecture + test-coverage reviewers simultaneously.
- **session-state-save.sh** (Stop + SubagentStop): persists session state to `.claude/session-state/`, rotates last 10 archives. Fail-open.
- **docs/COLLABORATIVE-DESIGN.md**: shared protocol for structured decision-making (Question > Options > Recommendation > Decision > Record).
- **SubagentStop event** in settings.json for session-state-save.

### Changed

- **/execute**: complete rewrite with verification pipeline, Collaborative Design Protocol integration, codebase-memory-mcp awareness.
- **/ship**: added review gate (checks REVIEW.md verdict), version bump detection, automatic changelog entry generation.
- **/spec**: added 4 parallel research subagents for brownfield projects (Mode A: formal agents, Mode B: inline fallback).
- **/spec-validate**: enhanced Scope Critic with aggressive atomicity check, dependency declaration checking, testability criteria.
- **context-readiness.sh**: v2 upgrade. Reads spec status, counts completed tasks, suggests next command ("detect, don't dictate").
- **install.sh**: added agents install/uninstall, path-scoped rules auto-copy to `.claude/rules/`.
- **PHILOSOPHY.md**: added "Verify before proceeding" and "Verify, then trust" principles. Updated version strategy.
- **rules/*.md**: YAML `paths` changed to multi-line list format.

## [1.1.0] - 2026-03-30

### Security

- **permission-auto-approve**: reject commands with pipes, chains, subshells (`|`, `&&`, `;`, `$()`, backticks) before checking whitelist. Prevents injection via chained commands.

### Fixed

- **anti-rationalization**: trimmed from 13 to 5 patterns. Removed 8 false-positive-prone phrases ("out of scope", "pre-existing", "we can revisit", "a future improvement", "for now, this should", "beyond the scope", "outside the current task", "I'll leave that for").
- **auto-format**: no more `npx --yes` network downloads per edit. Detection order: project-local binary > global binary > npx cache only (`npx --no`).
- **install.sh**: fixed jq merge logic that silently replaced user's existing hooks. Now removes dwarves-kit hooks first (idempotent), then concatenates arrays. Backs up settings.json before every modify.
- **context-readiness**: reduced context noise. Only outputs warnings and compact state (branch, dirty count). Healthy project = empty JSON = zero context cost.
- **spec-drift-guard**: shortened warning message, added `.claude/` to skip list.

### Added

- **statusline.sh** (StatusLine): shows `[model] branch | ctx:XX%! | $cost | think:on/off`. Context warning at 60% (`!`) and 80% (`!!`). Bash-only.
- **slop-cleaner.sh** (Stop hook): checks recently modified files for functions >50 lines, deep nesting >4 levels, files >300 lines, duplicate code blocks. Nudge only, never blocks.
- **kit-health command**: self-assessment against PHILOSOPHY.md principles. Checks file count, hook performance, settings validity, source citations, structural health.
- **rules/backend-go.md**: Go backend conventions template (path-scoped rules).
- **rules/frontend-ts.md**: TypeScript frontend conventions template (path-scoped rules).
- **tests/test-hooks.sh**: automated test suite (40+ cases) covering safety-gate, anti-rationalization, permission-auto-approve, auto-format, context-readiness, slop-cleaner, statusline.
- **Hook logging**: safety-gate, spec-drift-guard, slop-cleaner now log decisions to `~/.claude/dwarves-kit/logs/`.
- **Debug mode**: `DWARVES_KIT_DEBUG=1` makes all hooks log to stderr.
- **install.sh --uninstall**: clean removal of hooks, commands, skills from settings.json.

### Changed

- File budget: replaced hard 35-file cap with "every file must justify its existence" rule in PHILOSOPHY.md.
- README: added v1.1 changelog section, testing instructions, debug mode docs, hook log docs, known limitations.
- PHILOSOPHY.md: added indirect lineage documentation, expanded "NOT cover" section for parallel execution.
- v1.1-handoff.md: rewritten from build spec to post-build handoff document.

## [1.0.0] - 2026-03-29

Initial release. 9 hooks + 9 commands + 1 skill.

### Hooks
- safety-gate (PreToolUse): blocks rm -rf, push to main, force push
- context-readiness (SessionStart): project status injection
- anti-rationalization (Stop): catches incomplete work rationalization
- auto-format (PostToolUse): runs formatter on file changes
- spec-drift-guard (PreToolUse): warns on unplanned files
- pre-compact-backup (PreCompact): saves session snapshot
- post-compact-reinject (PostToolUse): re-injects rules after compaction
- notification (Notification): desktop alert when Claude needs input
- permission-auto-approve (PermissionRequest): auto-approves read-only operations

### Commands
- /user:think, /user:spec, /user:spec-validate, /user:execute, /user:next
- /user:review, /user:docs, /user:ship, /user:retro

### Other
- settings.json with all hooks registered
- CLAUDE.md project template with Trail of Bits quality rules
- install.sh idempotent installer
- skills/get-api-docs Context Hub integration
- docs/PHILOSOPHY.md design principles
