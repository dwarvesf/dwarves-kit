# Spec: Invocation namespace sweep (/user: and bare -> /kit:)

Generated: 2026-05-22
Status: VALIDATED

## Problem

The kit's docs reference its slash commands as `/user:<cmd>` (and occasionally bare `/<cmd>`). On Claude Code 2.x neither resolves to the kit: `/user:` is the reserved personal-command prefix and returns "unknown command"; bare `/<cmd>` only worked under the old flat bash-installer copy. The kit now ships as a plugin named `kit`, so the live invocation is `/kit:<cmd>`. Every doc that still says `/user:spec` teaches a command that does not work.

This is the doc-drift class the kit keeps re-hitting (ID-026 phantom cut, ID-016 missing doc-impact guard): guidance the kit's own guards never checked. ID-031 pairs the one-time sweep with a permanent meta-test so the form cannot rot again.

Scale (grep 2026-05-22): ~70 files contain `/user:`. They split into live docs that must be swept and historical records that must not.

## Solution

### Approaches considered

1. **Blanket `sed s|/user:|/kit:|` across all `*.md`.** One command, but rewrites point-in-time records (specs, retros, ADRs, handoff) that documented `/user:` as the truth at their ship date. Falsifies history; rejected.
2. **Plugin-canonical sweep of live docs only, historical records exempt, one invocation note for bash-install users (chosen).** Sweep `/user:<cmd>` -> `/kit:<cmd>` in the live, user-facing surface; leave dated/historical dirs untouched; add a single "Invocation" note explaining the plugin (`/kit:`) vs bash-install (bare `/`) difference. A meta-test pins the live set.
3. **Neutral phrasing everywhere (refer to "the spec command", no prefix).** Avoids the dual-ship ambiguity entirely but is a much larger rewrite, reads worse, and loses the copy-pasteable form. Rejected as over-correction.

### Chosen approach + why

Approach 2. It fixes what is broken (live docs), respects the kit's own "don't rewrite historical records" rule (the ADR-0009 precedent already applied this session), and the meta-test makes the win durable. The dual-ship ambiguity (below) is handled by one canonical note, not by mangling every reference.

### The dual-ship invocation decision (load-bearing)

The kit ships two ways (ADR-0009): as the `kit` plugin (commands resolve `/kit:<cmd>`) and via `bash install.sh` (flat copies resolve bare `/<cmd>`). No single literal is correct for both. Decision: **docs are plugin-canonical (`/kit:<cmd>`)**, because plugin is the recommended and now-default path (this session's rename + `--plugin-dir` wrapper). Each entry-point doc (README, MANUAL) carries one note: "Installed via the plugin, commands are `/kit:<cmd>`; via `bash install.sh`, drop the prefix (`<cmd>`)." This is recorded as DEC-001 and is the spec's primary point for `/spec-validate` to attack.

### File scope: sweep vs exempt

SWEEP (live, current behavior):
- Root: `README.md`, `MANUAL.md`, `WORKFLOW.md`, `CLAUDE.md`, `AGENTS.md` (if any).
- `docs/`: `architecture.md`, `ORCHESTRATION.md`, `PLAYBOOK.md`, `operating-layer-vision.md`, `PHILOSOPHY.md`, `ABSORPTION.md`, `absorption/README.md`.
- `commands/*.md` (cross-references in command bodies are shipped behavior).
- `examples/hello-spec/**` (the downstream exemplar; `/user:` there teaches new projects the wrong form).

EXEMPT (dated / point-in-time records, leave verbatim):
- `docs/specs/SPEC-*.md`, `docs/specs/DECISION-BRIEF.md`
- `docs/retro/RETRO-*.md`
- `docs/decisions/0*.md` (ADRs)
- `docs/handoff/v*.md`
- `docs/research/*.md`
- `CHANGELOG.md` (append-only release history; a point-in-time record). Added at execution, DEC-008.
- `_meta/BACKLOG.md` (tracker; its `/user:` mentions describe the bug, e.g. ID-031's "`/user:kit-health` unknown", and must not be rewritten). Added at execution, DEC-008.
- This file (SPEC-029) names `/user:` to describe the problem; it is itself a record.

## Technical Design

### Interfaces (I/O contract)

- Consumes: the literal command-reference strings in the SWEEP set.
- Produces: the same files with `/user:<cmd>` -> `/kit:<cmd>`; the invocation note in README + MANUAL; a new guard in `tests/test-meta.sh`.
- Invariants: command CONTENT unchanged (only the invocation prefix changes); EXEMPT files byte-identical; `plugin.json`/`marketplace.json` stay valid and name `kit`.

### Infrastructure changes

A `tests/test-meta.sh` block that fails if any SWEEP-set file contains `/user:` (or a bare-command invocation pattern it can reliably detect), enforced by directory allow/deny so EXEMPT dirs are not scanned.

## Task Breakdown

Note: TASK-002..005 each touch many files but are one uniform mechanical transform (`/user:<cmd>` -> `/kit:<cmd>`), not independent logic changes, so the >5-file atomicity heuristic is relaxed; the TASK-001 guard is the safety net proving each complete. (Scope Critic, addressed via DEC-006.)

### Phase 1: Foundation
- [x] TASK-001: Add the meta-test guard FIRST (TDD), **denylist-based**: scan all tracked `*.md` for `/user:`, EXCLUDING the exempt dirs (`docs/specs`, `docs/retro`, `docs/decisions`, `docs/handoff`, `docs/research`). Denylist (scan-all-minus-exempt), NOT an allowlist of known live files, so a future live doc is covered automatically (DEC-004). The guard enforces `/user:` ABSENCE only; it does not assert `/kit:` presence or catch bare `/<cmd>` (DEC-005). Assert it currently FAILS (red). Acceptance: guard added, runs, fails listing offending live files only, zero exempt files in the list.

### Phase 2: Core
- [x] TASK-002: Sweep `/user:<cmd>` -> `/kit:<cmd>` across root docs (README, MANUAL, WORKFLOW, CLAUDE.md, AGENTS.md). Acceptance: 0 `/user:` remain in these files; content otherwise unchanged.
- [x] TASK-003: Sweep `docs/` live set (architecture, ORCHESTRATION, PLAYBOOK, operating-layer-vision, PHILOSOPHY, ABSORPTION, absorption/README). Acceptance: 0 `/user:` remain in these files.
- [x] TASK-004: Sweep `commands/*.md` bodies. Acceptance: 0 `/user:` remain in commands/.
- [x] TASK-005: Sweep `examples/hello-spec/**`. Acceptance: 0 `/user:` remain under examples/.

### Phase 3: Polish
- [x] TASK-006: Add the plugin-vs-bash invocation note (DEC-001) to README + MANUAL. Acceptance: each entry-point doc states `/kit:<cmd>` (plugin) and drop-prefix (bash install) in one place.
- [x] TASK-007: Update BACKLOG ID-031 -> target SPEC-029, status validated (after `/spec-validate`); run full test suite green. Acceptance: `bash tests/test-meta.sh && bash tests/test-hooks.sh` pass.

## After state
- [x] Zero `/user:` invocation forms in the SWEEP set. (Today: ~70 files contain `/user:`.) Checkable: `grep -rl '/user:' README.md MANUAL.md WORKFLOW.md CLAUDE.md docs/architecture.md docs/ORCHESTRATION.md docs/PLAYBOOK.md commands/ examples/` returns nothing.
- [x] `bash tests/test-meta.sh` includes a guard that fails on any future `/user:` in the live set, and passes now.
- [x] EXEMPT dirs (`docs/specs`, `docs/retro`, `docs/decisions`, `docs/handoff`, `docs/research`) are byte-identical to pre-sweep. Checkable by `git diff` touching none of them.
- [x] README and MANUAL each carry the plugin-vs-bash invocation note.

## Acceptance Criteria (global)
- [x] All tasks pass their individual acceptance criteria
- [x] The meta-test guard goes red-before / green-after
- [x] No EXEMPT (historical) file is modified
- [x] No regressions: `bash tests/test-meta.sh && bash tests/test-hooks.sh` both pass

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh`

## Edge Cases
1. A live doc references `/user:` inside a quoted example explaining the OLD broken behavior (e.g. "`/user:kit-health` used to fail"). Expected: keep the historical mention but mark it clearly as the dead form; the meta-test must allow an explicit opt-out marker, or such mentions move to an EXEMPT note. Resolve during TASK-001 (the guard design decides this).
2. Bare `/<cmd>` references (not `/user:`) in live docs. Expected: convert to `/kit:<cmd>` where they are invocation instructions; do NOT touch `/specs/`-style paths or URLs. The guard targets `/user:` precisely; bare-form conversion is manual per-hit in TASK-002..005.
3. `AGENTS.md` may already be prefix-neutral (grep showed 0). Expected: no change; that is the correct tool-agnostic style and a model for any ambiguous case.

## Out of Scope
- Rewriting historical records (specs, retros, ADRs, handoff, research). Explicitly exempt.
- Deprecating or changing the bash installer (ADR-0009 dual-ship stands; this spec only documents the invocation difference).
- The plugin rename itself (already shipped: `kit`).

## Decision Log
- DEC-001: Docs are plugin-canonical (`/kit:<cmd>`) with a one-line bash-install prefix-drop note in README + MANUAL. Rationale: plugin is the recommended/default path; one note beats neutral-phrasing churn. Rejected: neutral phrasing (larger, reads worse), per-install conditional text everywhere (unmaintainable).
- DEC-002: Historical/dated dirs are exempt and left byte-identical. Rationale: they are point-in-time records; rewriting falsifies history (same call as ADR-0009 this session). The live docs are where current behavior is canonical.
- DEC-003: Meta-test guard added before the sweep (TDD red-green) so the fix is proven, not asserted.
- DEC-004: The guard is denylist-based (scan all `*.md` minus exempt dirs), not an allowlist of known live files. Rationale: an allowlist would let a future live doc reintroduce `/user:` undetected, i.e. the anti-rot guard would itself rot. (Failure Mode Analyst, SPEC-029 validation.)
- DEC-005: The guard enforces `/user:` ABSENCE only, not `/kit:` presence or bare-`/cmd` absence. Rationale: bare-form detection is too noisy to automate without false positives on paths/URLs; bare-form hits are converted manually in TASK-002..005. Accepted limit: the guard prevents `/user:` regression, not every wrong form. (Assumption Destroyer, SPEC-029 validation.)
- DEC-006: Multi-file sweep tasks (TASK-003 7 files, TASK-004 ~18 files) exceed the 5-file atomicity heuristic but are kept whole. Rationale: a single uniform mechanical transform is not the multi-concern risk the heuristic targets; the guard verifies completeness. (Scope Critic, SPEC-029 validation.)
- DEC-007: Hardcoding `/kit:` into ~70 references is brittle to a future plugin rename (one just happened). Accepted: markdown cannot template slash commands, so literals are unavoidable; the denylist guard localizes detection of the most common stale form. A future rename re-runs a scoped version of this sweep. (Design & Extensibility critic, SPEC-029 validation, advisory.)
- DEC-008: At execution the guard surfaced two more record/tracker files (`CHANGELOG.md`, `_meta/BACKLOG.md`) that the validation-time EXEMPT list missed; both added to the exemption (records, not invocation guides). Scope refinement, not scope creep. Result: 326 `/user:` occurrences swept across 31 live files; suite green (257 meta + 92 hooks).

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
