# Spec: engine seam and lint (learning-boundary SG-01)
Generated: 2026-09-10
Status: VALIDATED
References: `docs/decisions/0036-loops-split-by-who-changes.md` (the decision this spec implements); `lib/config/module-registry.md` `## Seams` and `wrap.before`'s row (the pattern `understand.teach` copies exactly); `docs/specs/SPEC-249-estate-seams.md` (the seam machinery `bin/config seams` already runs, unchanged by this spec).

## Problem

`bin/learn` and `lib/learn/` name a loop ("Learn") that ADR-0036 splits into three words (Reflect / Understand / Study) by who changes. Two engine commands, `commands/explain.md` and `commands/quiz-gate.md` (plus its engine `lib/gate/quiz-gate.sh`), hardcode the pedagogy skill they compose (`narrate-log`, `svg-knowledge-diagram`, `deep-understand`) instead of reaching it through a config seam, so an engine-only adopter with no overlay gets broken references instead of an honest `skipped: no teacher`. The five-stage table (`lib/config/module-registry.md`, README.md) still calls the fifth stage "Learn".

## Solution

### Approaches considered

1. **One seam key (`understand.teach`) resolved exactly like `wrap.before`.** Reuses `kit_config_get_root`, the existing `## Seams` table, and `bin/config seams`'s generic `skill`-kind resolver -- zero new resolver code. Rejected alternative: a bespoke resolver per command (three copies of the same fence logic).
2. **Rename `learn` to `reflect` via `git mv` + a one-release forwarder**, matching the kit's repoint-everything-in-one-release precedent (`add-backlog` -> `board promote`, ADR-0034 decision 7) but WITH a forwarder this time because `bin/learn` is a documented SPEC-184 stable consumer entrypoint external scripts may already call, unlike `add-backlog`'s bare verb-first name. Rejected: no forwarder (breaks an existing external caller with no warning, against ADR-0034's own stable-entrypoint promise).
3. **Boundary lint scope.** The goal names `lib/`, `commands/`, `tests/`, `kit.toml` verbatim. A literal full-`lib/` recursive grep for `ops-toolkit/` or `dotfiles` was tested (see Decision Log DEC-003) and hits 30+ pre-existing, legitimate porting citations in unrelated subsystems (`lib/stats/`, `lib/prose-rag/`, `lib/sync/`, `lib/webcheck/`, `lib/plugin-check/`) that document where that code graduated FROM, none of them a live reach-across. Rejected: fixing all of them in this sub-goal (unbounded, unrelated scope); a full-`lib/` scan with no narrowing (breaks green on unrelated content this sub-goal has no mandate to touch).

### Chosen approach + why

1 and 2 as stated. For 3: the lint scans `lib/gate/`, `lib/reflect/` (the two subsystems ADR-0036 actually touches: the Understand gate and the renamed Reflect subsystem), all of `commands/`, all of `tests/`, and `kit.toml`, for a `dotfiles/home` or `ops-toolkit/(tools|_meta)/` path shape (the two path patterns behind the PR #554 regression `tests/test-weekend-batch.sh` already pins as its own precedent). The consumer-skill-name check runs over a narrower, explicit file list (`commands/wrap.md`, `commands/explain.md`, `commands/quiz-gate.md`, `kit.toml`, `lib/gate/quiz-gate.sh`, `lib/gate/README.md`, every file under `lib/reflect/`) rather than all of `commands/`/`tests/`, because a bare-word denylist (`narrate-log`, `deep-understand`, `learning-ledger`, ...) has real, unrelated, legitimate hits elsewhere in the shipped repo: `commands/pitch.md` composes `narrate-log` for an unrelated pitch-deck feature, and `tests/test-wrap.sh` uses the literal string `learning-ledger` as placeholder fixture text for `report-lint.sh`'s generic "names a skill" acceptance check. Neither is this sub-goal's to fix. The allowlist stays exactly the `## Seams` table's `Filled by` column (module-registry.md is not in the lint's scan set at all, so its `learning-kit`/`context-kit`/`the operator` prose never needs a special-case exemption).

### Extensibility & boundaries

A fourth retired word or a fifth seam-adjacent file is one more entry in the lint's two lists; the resolver itself (`kit_config_get_root` + `bin/config seams`) needs no change for a future seam. Units: the seam key + registry rows (data), the lint (a read-only grep), the rename (`git mv` + string substitution, no new logic), each independently testable.

### Architecture

See `## Design`.

## Picture

```
 operator kit.toml                    lib/config/module-registry.md
 ┌───────────────────────┐            ┌──────────────────────────────┐
 │ [understand] teach=""  │──resolve──▶│ ## Seams                     │
 └───────────────────────┘            │  understand.teach | skill |  │
        ▲ kit_config_get_root          │  learning-kit understand    │
        │ (operator or kit-root only)  │  lane, or the operator       │
        │                              └───────────────┬──────────────┘
 learning-kit's `understand` skill                      ▼
 fills the key at install time                 bin/config seams
                                                (unchanged resolver)

 commands/wrap.md Step 7a/7c ──┐
 commands/explain.md ──────────┼──▶ gather material ──▶ Skill tool(understand.teach)
 commands/quiz-gate.md ────────┘         │
                                          empty key ──▶ "skipped: no teacher" + material path

 lib/learn/  ──git mv──▶  lib/reflect/        bin/learn ──forwarder──▶ bin/reflect
 (propose.py, drain.py, drain.sh,             (one deprecation line,
  staging-format.py, weekend-batch.sh,         same args, same exit code)
  learn.sh -> reflect.sh)

 lib/gate/boundary-lint.sh ──▶ greps lib/gate/, lib/reflect/, commands/, tests/, kit.toml
                                for a dotfiles/ops-toolkit path, and a curated file list
                                for a hardcoded consumer-skill name
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Diagram (sequence)

```
operator          commands/quiz-gate.md      lib/gate/quiz-gate.sh    kit-config.sh     Skill tool
   │                       │                          │                     │               │
   │  merge a tap PR       │                          │                     │               │
   │──────────────────────▶│                          │                     │               │
   │                       │── respond engage --ref ─▶│                     │               │
   │                       │◀── 5 questions + material─│                     │               │
   │                       │── kit_config_get_root understand.teach "" ─────▶│               │
   │                       │◀──────────── "" (empty) or "understand" ────────│               │
   │                       │ empty: print "skipped: no teacher" + hand the   │               │
   │                       │        material to the operator directly       │               │
   │                       │ filled: invoke the named skill ─────────────────────────────────▶│
```

### ADR link(s)

`docs/decisions/0036-loops-split-by-who-changes.md` (Accepted). No new irreversible decision here: the seam key defaults empty (no behavior change for an existing install until an overlay fills it), and the rename keeps a forwarder for one release.

### Boundaries & failure modes

Out of bounds: any skill body (learning-kit, dotfiles), the DEBT marker's own recording logic (unchanged), `lib/explain.sh`'s mechanical grounding engine (stays composed by whichever prose invokes it; its own header comment naming `narrate-log`/`svg-knowledge-diagram` as historical architecture commentary is left as is, since it lives at `lib/` root, not `lib/gate/` or `lib/reflect/`, and is not in the lint's scan set).

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `understand.teach` names a skill with no `SKILL.md` under any kept skill dir | `bin/config seams` reports `unresolved` | Existing SPEC-249 behavior, unchanged; the command's own empty/skipped branch only fires on a genuinely empty key, not an unresolved one (Edge Cases below) |
| A future PR reintroduces `narrate-log`/`deep-understand` as a literal in a seam-adjacent file | `boundary-lint.sh` fails naming the line | Route the reference through the seam instead |
| A future PR hardcodes a dotfiles/ops-toolkit path in `lib/gate/` or `lib/reflect/` | `boundary-lint.sh` fails naming the line | Read the path from an env var or `--repo-root`, per the existing adapter pattern |

## Technical Design

### Interfaces (I/O contract)

**`[understand] teach = ""`** (kit-root `kit.toml`, operator override). String, default `""`. Resolved only with `kit_config_get_root understand.teach ""`. Empty means no teacher; the commands print `skipped: no teacher` and hand over the gathered material.

**Registry row**: `understand.teach` under a new `### understand (teacher seam, no install module)` section in `lib/config/module-registry.md`, `[consumer]`, Module `gate` (the Understanding gate owns this seam's call sites: `commands/wrap.md`, `commands/explain.md`, `commands/quiz-gate.md`, `lib/gate/quiz-gate.sh`).

**`## Seams` row**: `| understand.teach | skill | learning-kit understand lane, or the operator |`.

**`bin/config seams`**: no code change. The existing generic `skill`-kind branch in `_seam_target_resolves` already checks `<dir>/<name>/SKILL.md` for any skill-kind row.

**`bin/reflect <verb>`**: new stable entrypoint, same shape as the old `bin/learn` (`propose`, `drain`, `debt <list|collect|mark-paid>`), forwarding to `lib/reflect/reflect.sh`.

**`bin/learn <verb>`**: forwarder. Prints one deprecation line to stderr (`bin/learn: deprecated, use 'bin/reflect <verb>' instead`), then `exec`s `bin/reflect "$@"` (same args, same exit code, same stdout/stderr beyond the one added line).

**`lib/gate/boundary-lint.sh [root]`**: exit 0 and prints `boundary-lint: PASS` when clean; exit 1 and prints one `boundary-lint: <finding>` line per hit to stderr otherwise. Root defaults to the repo root computed from its own path; never executes a target; never writes.

### Data model changes

- `kit.toml`: new `[understand]` section, `teach = ""`.
- `lib/config/module-registry.md`: one new registry row, one new `## Seams` row, the `## Module stages` table's `learn` row renamed to `reflect`/`Reflect`, and every other row whose Primary stage reads `Learn` renamed to `Reflect` (`weekend_batch`, `skill-curator`, `prose_rag`).

### API changes

`commands/wrap.md` Step 7a and 7c each gain one seam-invocation paragraph after their existing write. `commands/explain.md`'s "Compose, do not reinvent" section is replaced by a seam-invocation step; its frontmatter description drops the `narrate-log`/`svg-knowledge-diagram` mention. `commands/quiz-gate.md`'s engage routing names the seam instead of `deep-understand`; its frontmatter and Rules section follow. `lib/gate/quiz-gate.sh`'s `cmd_route`/`cmd_tap`/`cmd_respond` stop hardcoding `deep-understand`, sourcing `kit-config.sh` and resolving `understand.teach` for the payload's route label (empty -> `ROUTE: skipped: no teacher`).

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: the lint (built first, so it proves the seam left no name behind)

- [x] TASK-001: `lib/gate/boundary-lint.sh` (under 60 lines) per the Interfaces contract above. `tests/test-boundary-lint.sh` (green: calls it with no args, asserts exit 0). Wire one line into `tests/run-all.sh`. Acceptance: `bash lib/gate/boundary-lint.sh` currently exits 1 (naming `narrate-log`/`svg-knowledge-diagram` in `commands/explain.md` and `deep-understand` in `commands/quiz-gate.md`/`lib/gate/quiz-gate.sh`), proving the lint catches the real, current violation before Phase 2 removes it.

### Phase 2: the seam

- [x] TASK-002: `kit.toml` `[understand] teach = ""` + the module-registry.md registry row + `## Seams` row. Acceptance: `bash bin/config seams | grep understand.teach` shows the row.
- [x] TASK-003: `commands/wrap.md` Step 7a and 7c invoke the seam, naming no skill. Acceptance: `grep -n understand.teach commands/wrap.md` hits at least twice.
- [x] TASK-004: `commands/explain.md` and `commands/quiz-gate.md` invoke the seam instead of `narrate-log`/`svg-knowledge-diagram`/`deep-understand`; `lib/gate/quiz-gate.sh` resolves `understand.teach` instead of hardcoding `deep-understand`; `lib/gate/README.md`'s table cell follows. `tests/test-quiz-gate.sh` AC3 rewritten to assert the seam-resolution behavior (filled and empty cases) instead of the literal string `deep-understand`. Acceptance: `bash lib/gate/boundary-lint.sh` now exits 0.

### Phase 3: the rename

- [x] TASK-005: `git mv lib/learn lib/reflect`, `git mv lib/reflect/learn.sh lib/reflect/reflect.sh`; new `bin/reflect`; `bin/learn` becomes the deprecation forwarder. Every internal `learn propose`/`learn drain`/`learn debt` string literal inside the moved files becomes `reflect propose`/`reflect drain`/`reflect debt`. Acceptance: `git log --follow lib/reflect/weekend-batch.sh` shows the pre-move history; `bash bin/learn propose --help 2>&1 | head -2` shows the deprecation line then `usage: reflect propose`.
- [x] TASK-006: every call site listed in the implementation notes (tests, `commands/retro.md`, `commands/grill.md`, `lib/board/board.sh`, `lib/gate/gate-ledger.sh`, `lib/gate/docs/proof-of-done.md`, `lib/mega/mega-review.py`, `hooks/intake-sweep.py`, `lib/session/intel/SPEC.md`, `lib/session/audit/{SPEC.md,README.md,docs/feedback-loop.md,bin/session-audit}`, `tests/kit-contract-known-gaps.txt`, `README.md`, `docs/WORKFLOW.md`, `kit.toml`) repointed. Acceptance: `grep -rln 'lib/learn/\|bin/learn debt\|bin/learn propose\|bin/learn drain' lib commands tests hooks docs/WORKFLOW.md README.md kit.toml | grep -v 'bin/learn$'` is empty (a bare `bin/learn` mention describing the forwarder itself is fine).
- [x] TASK-007: the Learn stage renamed Reflect in `README.md`'s five-stage section (prose, mermaid diagram, module table) and `lib/config/module-registry.md`'s `## Module stages` table. `AGENTS.md`, root `WORKFLOW.md`, and `docs/FEATURES.md` checked and confirmed to print no such table (no edit needed there). Acceptance: `grep -c 'Reflect' README.md lib/config/module-registry.md` both nonzero; `grep -n '| Learn |' README.md lib/config/module-registry.md` empty.

## After state

- [x] `bash bin/config seams` lists `understand.teach` (kind `skill`, filled by "learning-kit understand lane, or the operator"). (Today: no such row.)
- [x] `bash lib/gate/boundary-lint.sh` exits 0. (Today: the script does not exist.)
- [x] `bash bin/learn propose --help 2>&1 | head -1` prints a deprecation line naming `bin/reflect`. (Today: `bin/learn` is the primary entrypoint, no deprecation.)
- [x] `bash tests/run-all.sh` exits 0 with the new boundary-lint test included. (Today: the suite has no boundary lint.)
- [x] `grep -c '| Learn |' README.md lib/config/module-registry.md` is 0; `grep -c 'Reflect' README.md lib/config/module-registry.md` is nonzero. (Today: both print `Learn`.)

## Acceptance Criteria (global)

- [x] All tasks pass their individual acceptance criteria
- [x] Tests cover happy path + edge cases listed below
- [x] No regressions in existing functionality

## Verification

```
bash tests/run-all.sh
bash bin/config seams
bash bin/learn propose --help
bash lib/gate/negctl.sh "$PWD" "bash tests/test-boundary-lint.sh" "printf '\n# invoke the '\''learning-ledger'\'' skill here\n' >> lib/reflect/weekend-batch.sh"
```

## Edge Cases

1. `understand.teach` empty (default, no overlay installed): `commands/wrap.md` Step 7a/7c, `commands/explain.md`, `commands/quiz-gate.md` each print `skipped: no teacher` plus the path to the gathered material, and hand it to the operator directly. No skill tool call is attempted.
2. `understand.teach` names a skill whose `SKILL.md` does not exist under any kept skill dir: `bin/config seams` reports `unresolved`; the commands still attempt the Skill tool invocation (its own failure surfaces at that layer, unchanged from today's `wrap.after` contract) rather than pre-empting it with a second resolution check the kit does not otherwise do for `wrap.before`/`wrap.after`.
3. `bin/learn` called with no args or `--help`: prints the deprecation line then the forwarded usage.
4. A caller pipes `bin/learn`'s stdout (e.g. `bin/learn drain`): the deprecation line goes to stderr only, so stdout stays parseable by an existing script that has not yet repointed to `bin/reflect`.
5. The boundary lint run from a worktree or a fresh clone with no `kit.toml [understand]` section yet: `grep` over `commands/`/`tests/`/`lib/gate/`/`lib/reflect/` still runs; a missing `kit.toml` line does not affect the path/skill-name checks (they do not read `kit.toml`'s values, only its text for the same two checks).
6. `lib/gate/quiz-gate.sh route` with `understand.teach` filled to a fixture name: the payload's `ROUTE:` line names that fixture value, never `deep-understand`.
7. Negative control: `learning-ledger` planted as a skill-shaped line in `lib/reflect/weekend-batch.sh` (a file in the lint's `lib/reflect/` scan set): `boundary-lint.sh` goes red, naming the line; `git checkout` restores; green again.
8. A skill name that IS one of this repo's own `skills/*/SKILL.md` entries (e.g. `stats`, `get-api-docs`, `skill-review`) appearing anywhere in the fenced surface: not checked by this lint's skill-name pass at all, since that pass is a fixed retired/pedagogy-name denylist, not a "not under skills/" existence check; documented as a known simplification in the Decision Log (DEC-004).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A future consumer-skill hardcode outside the lint's explicit file list | invisible to `boundary-lint.sh` | Known, disclosed gap (DEC-003); widen the file list when a new seam-adjacent surface is added |
| `bin/learn` forwarder silently drops an exit code | a caller's own error handling breaks | `exec` replaces the process image, so the exit code is `bin/reflect`'s own; no wrapping logic to drop it |

## Out of Scope

- Any skill body (learning-kit's `understand` skill, dotfiles' `weekend-debt-paydown`).
- Moving `learn debt`'s ledger semantics or the DEBT marker's recording logic (ADR-0031 untouched).
- `lib/explain.sh`'s own header commentary naming `narrate-log`/`svg-knowledge-diagram` (lives at `lib/` root, not a lint-scanned subsystem; a stale but harmless architecture note).
- Widening the boundary lint to the rest of `lib/` (stats, prose-rag, sync, webcheck, plugin-check, session, board, skill-curator): those subsystems' historical porting citations are real, legitimate, and unrelated to this axis.

## Touches

- lib/gate/**
- lib/reflect/**
- commands/wrap.md
- commands/explain.md
- commands/quiz-gate.md
- kit.toml
- tests/**
- lib/config/module-registry.md
- README.md
- docs/WORKFLOW.md

## Decision Log

- DEC-001: `understand.teach` resolves with `kit_config_get_root`, identical to `wrap.before`/`wrap.after`/`knowledge.root` -- a project `.kit.toml` is never consulted, because the key names code a command runs. Rejected: `kit_config_get` (would let a PR-carried project toml choose which skill the engine invokes).
- DEC-002: `bin/learn` keeps a forwarder for one release rather than a bare retirement, matching ADR-0034's own promise that `bin/<subsystem>` is a stable consumer entrypoint (SPEC-184). Rejected: no forwarder (an existing external caller breaks with no warning).
- DEC-003: the boundary lint's scan scope is narrower than a literal reading of "greps lib/, commands/, tests/, kit.toml" -- see `## Solution` approach 3 for the full rationale and the measured false-positive count. This is the single largest judgment call in this spec; flagged here for the operator to confirm or revise.
- DEC-004: the skill-name check is a fixed denylist (the ROADMAP's own "Retired words" list plus the two pedagogy skills named in ADR-0036), not a general "any backtick-quoted kebab-case token near the word skill" heuristic. The general heuristic was prototyped and rejected: it produces both false positives (`frontend-design` in `commands/ui-design.md`, an accepted, unrelated, pre-existing pattern) and false negatives (`commands/explain.md`'s bullet-list skill names sit on a different line than the word "skill").

## Review

Self-validated (single-agent execution session, no fresh-context reviewer dispatched; a `normal`-lane sub-goal, not `full`). Six lenses applied directly against the spec text.

### Verdict: APPROVED

### Findings

| # | Finding | Lens | Severity | Status |
|---|---|---|---|---|
| 1 | TASK-006 touches more than 5 files (every call-site repoint) | Scope Critic | advisory | accepted -- the task is one mechanical, uniform substitution (`lib/learn/` -> `lib/reflect/`, `learn propose/drain/debt` -> `reflect propose/drain/debt`) across a fixed, enumerated list; splitting it into N one-file tasks would not reduce risk, only ceremony |
| 2 | DEC-003's scope narrowing is a real, disclosed judgment call, not obviously the operator's own prior intent | Solution-Design | advisory | already flagged in Open Questions; stands as written |

Reviewer 6 (Design Record Auditor): this spec is mildly design-bearing (a new seam key, a rename touching many call sites) but follows an EXISTING pattern (`wrap.before`) exactly, so the `## Design` section's sequence diagram + stated approach is proportionate. PASS, not blocking.

No CRITICAL findings. Security, Failure-Mode, and Assumption-Destroyer lenses found nothing specific to this spec's surface (config resolution + text substitution, no auth/data/concurrency surface).

## Open questions

- DEC-003's scope narrowing is the operator's call to confirm; if the operator wants the literal full-`lib/` scan, the unrelated pre-existing citations in `lib/stats/`, `lib/prose-rag/`, `lib/sync/`, `lib/webcheck/`, `lib/plugin-check/` would need their own cleanup pass first, out of this sub-goal's time budget.
