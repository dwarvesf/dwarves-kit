# Spec: The opt-in /user:design lane (realizes SPEC-008 Part C)

Generated: 2026-05-21
Status: VALIDATED
Source: SPEC-008 Part C, deferred there ("design now, build behind the PHILOSOPHY §5 bar"). The maintainer's original signal (the session that produced SPEC-008): the think/plan phase ran without their feedback and produced a shallow solution. SPEC-008 fixed the depth half (template + Reviewer 5); this spec builds the feedback half. Backlog: ID-014.
Depends on: SPEC-008 (the enriched Solution template `/user:design` produces) shipped/committed. Conceptual lineage: `superpowers:brainstorming` interaction loop (forked, not depended-on).
Lane: normal (one new command + two one-line handoff pointers + tests/docs; no auth/data/hook/migration risk). `/user:spec-validate` recommended (it adds a command to the public surface).

## Decision brief (folded-in /think)
- **Real pain:** the design phase advances to /spec (and, under bypass, all the way to validate) with no point where the user shapes the solution. SPEC-008's Reviewer 5 reviews depth *after* the spec is written; nothing creates a *conversation* about the solution *before* it.
- **Why now:** SPEC-008 deferred this as Part C; the maintainer asked to build it.
- **Cut list:** no kit-wide hard gate, no Visual Companion, no superpowers runtime dependency, no rewrite of /think or /spec.
- **Exit criteria:** `/user:design` exists as an opt-in command between /think and /spec, produces the Solution block /spec consumes, never auto-runs, never hard-gates; tests green.

## Problem

SPEC-008 delivered solution-**depth** (the `## Solution` template scaffold + Reviewer 5 in `/spec-validate`) but explicitly deferred the **feedback** half (Part C): an interactive beat where the user shapes the solution design *before* the spec is committed. Today the lifecycle goes `/think` (product framing) -> `/spec` (writes the contract). There is no solution-design conversation in between, and Reviewer 5 only reviews depth *after* the fact. Under bypassPermissions the agent auto-proceeds through all of it.

The maintainer's original complaint had two halves; only one is closed:
```
shallow solution  ->  FIXED by SPEC-008 (template depth + Reviewer 5)
ran without me     ->  OPEN: no interactive design beat; this spec
```

## Solution

### Approaches considered
1. **An opt-in `/user:design` command between /think and /spec.** Forks brainstorming's interaction loop (one question at a time, present design in sections, approve per section), writes the Solution block /spec reads. Tradeoff: a 13th command, but it is user-pulled (self-imposed beat), so it respects "Detect, don't dictate".
2. **Make Reviewer 5 interactive / add an approval gate inside `/spec`.** Tradeoff: bolts a feedback loop onto commands that already have a job; muddies them; `/spec-validate` already has a per-reviewer "address this?" ask, so this duplicates partway.
3. **A Stop-hook enforcement (like anti-rationalization).** Tradeoff: a kit-wide hard gate on design completeness, which PHILOSOPHY explicitly rejects.

### Chosen approach + why
Approach 1. It is the user-pulled lane the maintainer originally asked for, forks the proven brainstorming loop into kit idiom, and leaves `/think` and `/spec` almost untouched (one handoff pointer each). Approach 2 was rejected for muddying existing commands; Approach 3 for being the PHILOSOPHY-rejected hard gate.

### Extensibility & boundaries
- Load-bearing dimension: command count and lifecycle surface. Adding one optional command between two existing phases is the minimal change; it does not alter the lane model beyond inserting an optional beat.
- Unit boundaries: `commands/design.md` is self-contained. It produces the Solution block; `/spec` consumes it via the existing `docs/specs/DECISION-BRIEF.md` handoff (SPEC-010 mapping). The command does NOT execute, does NOT hard-gate, does NOT edit `/think`/`/spec` logic.

### Architecture (diagram if it helps)
```
/user:think     product framing (unchanged) -> writes docs/specs/DECISION-BRIEF.md (if BUILD)
   |  (one-line pointer: "consider /user:design next")
/user:design    OPT-IN. solution-design conversation:
                  - propose 2-3 approaches, one question at a time (AskUserQuestion)
                  - present the design in sections; hold for approval per section
                  - write the Solution block (approaches/chosen/extensibility)
                    into docs/specs/DECISION-BRIEF.md for /spec to fold in
   |
/user:spec      reads the brief (incl. the design), writes docs/specs/SPEC-NNN (unchanged
                beyond reading the design if present)
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** the idea from chat and `docs/specs/DECISION-BRIEF.md` if `/think` ran; the user's per-section approvals via `AskUserQuestion`.
- **Outputs / produces:** a Solution block (the SPEC-008 sub-sections: approaches considered / chosen + why / extensibility) written into `docs/specs/DECISION-BRIEF.md` (the `/think`->`/spec` handoff per SPEC-010 DEC-014), so `/spec` folds it into the spec's `## Solution`.
- **Invariants:** opt-in (never auto-runs, never a Stop hook or phase gate); does not execute; does not edit `/think`/`/spec` logic beyond a one-line pointer each; bash/markdown only; no superpowers runtime dependency; **appends** a Solution section to `docs/specs/DECISION-BRIEF.md`, preserving `/think`'s product framing (never clobbers the brief).

### Data model changes
None.

### API / UI / Infrastructure changes
One new command file; one-line pointers in `/think` and `/spec`; a WORKFLOW.md note placing `/user:design` as an optional beat; the "12 commands" -> "13 commands" count ripple across README/MANUAL/CLAUDE/architecture.

## Task Breakdown

**Phase 1: The command**
- [x] **TASK-1: write `commands/design.md`.** The `/user:design` command: explore 2-3 solution approaches one question at a time (`AskUserQuestion`, multiple-choice preferred), present the design in sections scaled to complexity, hold for the user's approval after each section, then write the Solution block (approaches / chosen + why / extensibility & boundaries) into `docs/specs/DECISION-BRIEF.md`. Frontmatter `description:`. State plainly: opt-in, does not execute, does not hard-gate; under bypassPermissions the per-section asks may auto-resolve (the lane is most useful interactively). Cite the brainstorming fork.
  - Acceptance: `commands/design.md` exists with `description:` frontmatter; drives a one-question-at-a-time loop with per-section approval; **appends** the Solution block to `docs/specs/DECISION-BRIEF.md` (does not overwrite the brief's product framing; creates the brief if absent); states opt-in + no-hard-gate + the bypass caveat; cites lineage.
- [x] **TASK-2: wire the handoff (minimal).** Add a one-line pointer in `commands/think.md` ("consider `/user:design` to shape the solution before `/spec`") and confirm `commands/spec.md` reads the brief's design (it already reads `docs/specs/DECISION-BRIEF.md`). Add a one-line note to `WORKFLOW.md` placing `/user:design` as an optional beat between Think and Spec (advisory, opt-in).
  - Acceptance: `/think` points at `/user:design`; `/spec` consumes the design from the brief; `WORKFLOW.md` notes the optional beat; no logic rewrite of `/think`/`/spec`.

**Phase 2: Verify + hygiene**
- [x] **TASK-3: tests + command count.** `tests/test-meta.sh`: assert `commands/design.md` exists with `description:` frontmatter (the existing per-command frontmatter loop already covers new command files; add an explicit presence assertion if the loop does not fail on absence). Update every "12 commands" reference to "13 commands" (README, MANUAL "The N commands" heading + add the `/user:design` entry, CLAUDE.md "12 commands", `docs/architecture.md`, `.claude-plugin/` if it enumerates).
  - Acceptance: `bash tests/test-meta.sh` passes (new count documented); `bash tests/test-hooks.sh` 42/42; no stale "12 commands" reference remains.
- [x] **TASK-4: docs.** README command table row + MANUAL `/user:design` entry + CHANGELOG `[Unreleased]`.
  - Acceptance: README/MANUAL/CHANGELOG updated.

## Acceptance Criteria (global)
- [x] `commands/design.md` exists: opt-in `/user:design`, one-question-at-a-time + per-section approval, appends the Solution block to `docs/specs/DECISION-BRIEF.md`
- [x] Never auto-runs, never a Stop hook / phase gate; `/think` + `/spec` gain only a one-line pointer each; `WORKFLOW.md` notes the optional beat
- [x] Forked from `superpowers:brainstorming` (lineage cited); no superpowers runtime dependency; bash/markdown only; no Visual Companion
- [x] The "12 commands" count is updated to 13 everywhere (live docs; historical spec refs left); SPEC-008 is NOT edited
- [x] `bash tests/test-hooks.sh` 42/42; `bash tests/test-meta.sh` passes (130 -> 133); README/MANUAL/CHANGELOG updated

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Run under bypassPermissions: the per-section `AskUserQuestion`s auto-resolve, so the feedback beat is hollow | the loop "completes" with no real user input | the command states it is most useful interactively; the bypass caveat is the inherent limit (same as SPEC-008 Known limitation 5); not solvable in-command |
| `/user:design` runs but `/spec` ignores its output | the spec's `## Solution` does not reflect the design conversation | `/spec` already reads `docs/specs/DECISION-BRIEF.md` (SPEC-010 DEC-014); `/user:design` writes the design there; TASK-2 confirms the read |
| The lane becomes a de-facto required gate | users feel forced through `/user:design` | opt-in by construction (no hook, no gate); documented as user-pulled; WORKFLOW notes "optional" |
| `/user:design` clobbers `/think`'s product brief in DECISION-BRIEF.md | the brief's Problem / product framing is lost | the command APPENDS a Solution section, never overwrites; creates the brief if absent (DEC-006) |
| A stale "12 commands" reference survives | doc says 12, kit has 13 | TASK-3 sweeps every count; a grep check in the acceptance |

## Edge Cases
1. **`/user:design` run with no prior `/think`.** It works from the chat idea directly (like brainstorming); writes a fresh `docs/specs/DECISION-BRIEF.md`.
2. **User wants to skip it.** Default: it is never invoked unless the user runs it. `/spec` works exactly as before without it.
3. **Tiny-lane work.** No spec, no design lane; `/user:design` is a normal/full-lane beat.
4. **Bypass mode.** The command runs but the asks may auto-resolve; the value degrades to the agent's own design (documented limit), not a regression.

## Out of Scope
- Any kit-wide hard gate / Stop hook forcing the design lane (PHILOSOPHY-rejected).
- The Visual Companion / browser mockups (bash/markdown only).
- A superpowers runtime dependency (fork the pattern).
- Rewriting `/think` or `/spec` logic (only one-line pointers + the existing brief read).
- Solving the bypass-auto-resolve limitation (inherent; documented).

## Decision Log
- **DEC-001**: Realize SPEC-008 Part C as a new spec (SPEC-011), not by editing SPEC-008 (committed). Per "new work gets a new spec."
- **DEC-002**: `/user:design` is opt-in, user-pulled, never a hard gate. Rationale: "Detect, don't dictate"; the cost of skipping it is reversible.
- **DEC-003**: Output lands in `docs/specs/DECISION-BRIEF.md` (the `/think`->`/spec` handoff, SPEC-010 DEC-014), so `/spec` folds it in with no new plumbing.
- **DEC-004**: Fork the brainstorming loop into kit idiom; no runtime dependency. Per "synthesize, don't originate" + "external tools are dependencies, not features".
- **DEC-005**: Drop the Visual Companion (bash-over-binaries); the bypass-auto-resolve limit is documented, not solved (mirrors SPEC-008 Known limitation 5).
- **DEC-006 (validation)**: `/user:design` APPENDS a Solution section to the brief, never clobbers `/think`'s product framing (failure-mode + design reviewers W1).
- **DEC-007 (validation)**: the "12 commands" -> "13" update is a mechanical sweep across README/MANUAL/CLAUDE/architecture (scope reviewer W3).

## Known limitations
1. **The `/spec` fold is an advisory soft handoff.** `/spec` reads `docs/specs/DECISION-BRIEF.md` and the architect incorporates the design; it is not hard-enforced that the design lands verbatim in `## Solution`. Consistent with the kit's advisory posture; Reviewer 5 catches a shallow Solution downstream.
2. **Bypass mode hollows the feedback beat** (see Failure modes); inherent to bypassPermissions, documented, not solved here (mirrors SPEC-008 Known limitation 5).

## Open questions
(none yet; append here if execution surfaces a decision SPEC-008 Part C did not cover.)

## Source citations
- The design this realizes: SPEC-008 Part C (Solution > Part C; deferred there).
- Forked loop: `superpowers:brainstorming` 5.1.0 (one-question-at-a-time, present-in-sections, per-section approval).
- The handoff this writes into: `docs/specs/DECISION-BRIEF.md` (SPEC-010 DEC-014).
- Philosophy bars: `docs/PHILOSOPHY.md` ("Detect, don't dictate", "Synthesize, don't originate", "Bash over binaries").

## Validation
5 reviewers run 2026-05-21 (security, failure-mode, assumption-destroyer, scope-critic, solution-design & extensibility; this dogfoods the reviewer set SPEC-008/009 built). Pre-fix verdict: NEEDS REVISION (one correctness warning, two acknowledged).
- W1 (failure-mode + design): `/user:design` could clobber `/think`'s product brief in `docs/specs/DECISION-BRIEF.md` -> now APPENDS a Solution section, preserving the brief (DEC-006; invariant + TASK-1 + failure-modes row).
- W2 (assumption, acknowledged): the `/spec` fold is an advisory soft handoff (Known limitation 1).
- W3 (scope, acknowledged): the "12 commands" -> "13" ripple touches >5 files but is mechanical (DEC-007).
- Security N/A (command prompt; no auth/input/secret/data surface).
Status flipped to VALIDATED after inline resolution.
