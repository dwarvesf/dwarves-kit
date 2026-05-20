# MANUAL

Operator reference for dwarves-kit. For the WHY behind any choice, see `docs/PHILOSOPHY.md`. For component fit, see `docs/architecture.md`. For diagnosing a misbehaving hook, see `RUNBOOK.md`. For the end-to-end workflow contract (phases, risk-tier lanes, gates), see `WORKFLOW.md`.

## Conventions

- Bash install path: commands invoked as `/user:<name>` (e.g. `/user:spec`).
- Plugin install path: commands invoked as `/<name>` (the `/user:` namespace is bash-installer-specific).
- Hooks have no invocation, they fire on Claude Code events.
- Agents have no invocation, they are dispatched by commands.

## The 14 commands

### `/user:start`

**Phase:** entry router
**Reads:** project state (existence of `docs/specs/SPEC-NNN-<slug>.md`, git branch, dirty count, hook log activity)
**Writes:** nothing; advises in chat which command to run next
**When to invoke:** opening a fresh session and you do not remember where you left off
**Common gotcha:** the router suggests a next step but does not run it. You decide.
**Spec resolution (dual-mode, SPEC-005):** the active spec is the lone non-SHIPPED/PARKED `docs/specs/SPEC-*.md`; with several live, the one whose slug matches the git branch; if zero or several match, it reports `spec:ambiguous(...)` and asks rather than guessing. Legacy `.planning/SPEC.md` is a deprecation fallback. The same rule drives the `context-readiness` hook, `spec-drift-guard` (which greps the union of active specs), and `/user:next`.

**Modes (`$ARGUMENTS`):**
- `/user:start --brief` -- one line, max 120 chars: state + suggested command + `[branch | N dirty | spec]`. For returning users who want a cue, not a report. Example: `Spec VALIDATED, 3/8 tasks -> /user:execute. [master | 2 dirty | VALIDATED]`
- `/user:start` -- the default 3-4 line orientation (unchanged from prior versions).
- `/user:start --full` -- the default block, then: SPEC task checklist, hook-log line counts (last 7 days, counts only, never raw lines), `git log -5 --oneline`, and the command map grouped by phase. For a new user or a deep status check.

### `/user:think`

**Phase:** challenge an idea before writing a spec
**Reads:** the idea from chat
**Writes:** `docs/specs/DECISION-BRIEF.md` only if the verdict is BUILD
**When to invoke:** before any non-trivial feature. Costs ~5 minutes.
**Common gotcha:** the 6 forcing questions are confrontational by design. If you accept them too easily, the brief is weak.

### `/user:design`

**Phase:** opt-in interactive solution-design beat (between Think and Spec)
**Reads:** `docs/specs/DECISION-BRIEF.md` (if present), the codebase
**Writes:** appends a `## Solution` section to `docs/specs/DECISION-BRIEF.md` (never clobbers the brief's product framing)
**When to invoke:** when you want to shape the solution with the agent (2-3 approaches, one question at a time, approve per section) before `/user:spec`. Opt-in; skip it and `/user:spec` works as before.
**Common gotcha:** under bypassPermissions the per-section `AskUserQuestion` prompts may auto-resolve, hollowing the feedback. Use it interactively. It does not execute and is not a gate. Realizes SPEC-008 Part C; forked from `superpowers:brainstorming`.

### `/user:spec`

**Phase:** generate the development spec
**Reads:** `docs/specs/DECISION-BRIEF.md` (if present), the codebase via 4 parallel research subagents (brownfield) or chat (greenfield)
**Writes:** `docs/specs/SPEC-NNN-<slug>.md` (Status: DRAFT), `docs/research/{stack,features,architecture,pitfalls}.md`
**When to invoke:** after `/think`, or directly if the work is well-scoped already
**Common gotcha:** the research agents are parallel-dispatched via Task tool. If your Claude Code is older than v2.0.60, they fall back to inline research and the run is slower.
**Template sections:** the generated spec scaffolds Solution depth (approaches / chosen + why / extensibility, SPEC-008), plus an optional `### Interfaces (I/O contract)` under Technical Design and an optional `## Failure modes` table (SPEC-009). Both optional sections are lane-scoped; Reviewers 2 and 5 check them when present. It also pins `## Verification` (the command(s) that prove the spec done) and `## Open questions` (the blocker landing zone a `/goal` loop appends to), so a validated spec is natively pointer-`/goal`-ready (SPEC-012 P1).

### `/user:spec-validate`

**Phase:** adversarial review of the spec
**Reads:** `docs/specs/SPEC-NNN-<slug>.md`
**Writes:** comments in chat; the maintainer flips SPEC Status to VALIDATED manually after addressing findings
**When to invoke:** before `/execute` on any spec longer than ~5 tasks
**Common gotcha:** 5 reviewers (security, failure-mode, assumption-destroyer, scope-critic, solution-design & extensibility) run sequentially. Budget ~10-12 minutes. The 5th reviewer (SPEC-008) flags shallow or non-extensible designs and is calibrated against false positives + legacy specs.

### `/user:execute`

**Phase:** autonomous build
**Reads:** `docs/specs/SPEC-NNN-<slug>.md` (must be Status: VALIDATED or APPROVED)
**Writes:** code, tests, marks SPEC task checkmarks, appends to SPEC Decision Log
**Dispatches:** worker subagent per task, then task-verifier, then fix-agent on FAIL:fixable (retry max 2)
**When to invoke:** when handing off to a contractor OR running the kit on yourself end-to-end
**Common gotcha:** verification adds ~2x token cost per task. Worth it for the FAIL:fixable catch rate; budget accordingly.

### `/user:next`

**Phase:** manual single-task build
**Reads:** `docs/specs/SPEC-NNN-<slug>.md`
**Writes:** code, tests; you drive the verification yourself
**When to invoke:** when you want hands-on control or the next task needs subtle judgment that the verification pipeline might over-correct on
**Common gotcha:** picks the next unchecked task only. To skip a task or pick a specific one, edit SPEC.md task ordering first.

### `/user:debug`

**Phase:** off-cycle (the `bug` lane: defect, regression, failing test, not a new feature)
**Reads:** the bug report / error / failing test, `git diff`, `git log`, `git bisect`
**Writes:** `.claude/debug/<slug>.md` (the evidence ledger), `.claude/debug/<slug>.log` (tagged instrumentation), then a failing test + a single root-cause fix
**When to invoke:** when something is broken and you would otherwise guess-fix. Runs four phases (root cause -> pattern -> hypothesis -> fix) under the iron law "no fix without a recorded root cause," with a 3-failed-fixes-question-architecture wall.
**Common gotcha:** while the ledger's `## Root cause` is blank, the anti-rationalization hook blocks any guess-fix "done" claim and sends you back to Phase 1. That guard is gated on an open debug session, so it never fires in normal coding. After a confirmed fix, run `/user:review` on the diff. Forked from `superpowers:systematic-debugging` + GSD/doraemonkeys mechanisms; see ADR-0012.

### `/user:review`

**Phase:** paranoid single-pass review
**Reads:** `git diff`, `docs/specs/SPEC-NNN-<slug>.md`
**Writes:** `REVIEW.md`
**When to invoke:** small change (under ~300 lines diff) where one careful pass beats parallel lens-reviewers
**Common gotcha:** outputs a verdict (`SHIP / FIX-REQUIRED / REJECT`). `/ship` reads this and gates on it.

### `/user:review-team`

**Phase:** parallel 3-lens review
**Reads:** `git diff`
**Dispatches:** 3 `reviewer` subagents (security, architecture, test-coverage lenses) in parallel + the deeper `security-auditor` agent
**Writes:** `REVIEW-{security,architecture,test-coverage}.md`
**When to invoke:** medium-to-large diff (>300 lines) or any change touching auth, payments, multi-tenant boundaries
**Common gotcha:** the FIX-THEN-SHIP path dispatches `responding-to-review` to triage findings without performative agreement. Read both the findings AND the response triage before committing fixes.

### `/user:docs`

**Phase:** doc sync
**Reads:** `git diff`
**Writes:** updates README.md, CHANGELOG.md, and any other doc files whose content drifted from code
**When to invoke:** after `/execute` succeeds, before `/ship`
**Common gotcha:** the command does not invent doc content. If a feature is undocumented in the spec, the command will not document it from the diff alone.

### `/user:ship`

**Phase:** review gate, version bump, changelog, commit, PR
**Reads:** `docs/specs/SPEC-NNN-<slug>.md`, `REVIEW*.md`, `VERSION`, `CHANGELOG.md`
**Writes:** bumped `VERSION`, new `CHANGELOG.md` entry, git tag, PR via `gh`
**When to invoke:** review is green and docs are synced
**Common gotcha:** blocks if any REVIEW*.md verdict is FIX-REQUIRED. Use `/review-team` and `responding-to-review` to triage before re-running ship.

### `/user:retro`

**Phase:** post-release reflection
**Reads:** `docs/specs/SPEC-NNN-<slug>.md` (completion rate), `git log`, prior `docs/retro/*.md`
**Writes:** `docs/retro/v<version>.md`
**When to invoke:** after `/ship` lands; one per minor or major release, patch releases append to parent retro
**Common gotcha:** action items become real only if you carry them to the next cycle's spec. Track them, do not just write them.

### `/user:kit-health`

**Phase:** self-assessment against PHILOSOPHY.md
**Reads:** the kit itself (file counts, hook performance, settings validity, source citations)
**Writes:** verdict in chat (`SHIP / FIX-REQUIRED / REJECT`)
**When to invoke:** maintainer-only, before tagging a release of the kit
**Common gotcha:** the rejection-first verdict will REJECT on real violations. Do not soften the criteria; address them.

## Hooks (no invocation)

| Hook | Event | What to remember |
|---|---|---|
| `safety-gate` | PreToolUse(Bash) | Blocks `rm -rf`, push to main, force push. Override needs explicit user OK. |
| `context-readiness` | SessionStart | Reads `docs/specs/SPEC-NNN-<slug>.md` status, suggests next command. Silent when project is healthy. |
| `anti-rationalization` | Stop | Catches premature-completion phrases. 5 patterns, narrow on purpose. |
| `slop-cleaner` | Stop | Flags bloated code in recently modified files. Nudge only. |
| `session-state-save` | Stop, SubagentStop | Persists state to `.claude/session-state/`. Rotates 10 archives. Fail-open. |
| `auto-format` | PostToolUse(Write\|Edit) | Detects local formatter, never network downloads. |
| `spec-drift-guard` | PreToolUse(Write) | Warns when creating files not in the spec. Skips `.claude/`. |
| `pre-compact-backup` | PreCompact | Snapshots session state before context compaction. |
| `post-compact-reinject` | PostToolUse(compact) | Re-injects critical rules after compaction. |
| `notification` | Notification | Desktop alert when Claude needs input. |
| `permission-auto-approve` | PermissionRequest | Auto-approves read-only ops; rejects pipes/chains/subshells. |
| `statusline` | StatusLine | `[model] branch | ctx:XX%! | $cost | think:on/off`. Bash-only. Bash install only. |

## Agents (dispatched, not invoked)

| Agent | Dispatched by | What it does |
|---|---|---|
| `task-verifier` | `/execute` | Read-only verification per task |
| `fix-agent` | `/execute` | Targeted fixes on FAIL:fixable (max 2 retries) |
| `reviewer` | `/review-team` | Focused review with configurable lens |
| `security-auditor` | `/review-team` | Deep OWASP-style audit |
| `responding-to-review` | `/review-team` (FIX-THEN-SHIP) | Triages findings without sycophancy |
| `research-stack` | `/spec` | Brownfield stack mapping |
| `research-features` | `/spec` | Brownfield feature inventory |
| `research-architecture` | `/spec` | Brownfield architecture patterns |
| `research-pitfalls` | `/spec` | Landmine surfacing pre-build |

## Path-scoped rules

`rules/backend-go.md` and `rules/frontend-ts.md` are TEMPLATES. Copy to `.claude/rules/` in the project that needs them. They activate when Claude reads matching files; they do NOT fire on write or create.

## Debug mode

```
export DWARVES_KIT_DEBUG=1
```

All hooks log decisions to stderr. Useful when a hook misbehaves or you want to understand why something was blocked or approved.

## Logs

`~/.claude/dwarves-kit/logs/`:
- `anti-rationalization.log`
- `safety-gate.log`
- `spec-drift-guard.log`
- `slop-cleaner.log`

Format: `timestamp | EVENT | detail | project_dir`. These build the eval corpus for future AutoResearch optimization.
