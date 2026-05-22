# Spec: Release-hygiene guard (phantom-cut warn)
Generated: 2026-05-22
Status: VALIDATED

Source: SPEC-027 retro ("What hurt": the release-hygiene tangle) + SPEC-018 retro (the first occurrence); ID-026. Goal draft: `.claude/goals/release-hygiene-guard.md`. A two-cycle recurrence, which clears the PHILOSOPHY section-5 bar for promoting a check.

## Problem
The kit can drift into a messy-release state that no surface flags. Concretely (the live state at this spec's writing): `VERSION` and `.claude-plugin/plugin.json` say `1.6.0`, but the latest git tag is `v1.5.1`, so `1.6.0` is a **phantom cut**: the files name a version that was never released. Meanwhile `CHANGELOG.md` `[Unreleased]` keeps accumulating new specs on top of that untagged cut, so it is unclear what `1.6.0` even contains or whether it shipped. This exact state was flagged by the SPEC-018 retro (placement-ui-design: "1.6.0 cut in CHANGELOG + VERSION + plugin.json but never tagged") and recurred in the SPEC-027 retro. Nothing in the kit notices it.

The kit deliberately does "no version bump" ships that let `[Unreleased]` accumulate (e.g. PR #7), so accumulation alone is **not** the bug. The bug is the **phantom cut**: a version named in the files with no matching git tag, with work piling above it.

## Solution

### Approaches considered
- **A (chosen): warn-only surfaces (ship + kit-health), no hook, no hard test.** Add a release-hygiene warn at `/user:ship`'s version step (where the bump/tag decision is made) plus a `kit-health` check line (run before tagging). Both detect the phantom cut (the files' version not present in `git tag`) and warn; neither blocks. A `tests/test-meta.sh` assertion pins that both surfaces carry the check (not that the repo is currently clean). Tradeoff: a warn can be ignored, but PHILOSOPHY reserves hard blocks for the safety subset and the completeness clauses are already warn+log; this matches that grain.
- **B: a `tests/test-meta.sh` hard assertion that `VERSION` is tagged.** Rejected: "VERSION named but not yet tagged" is a **legitimate transient** during a release (bump files, commit, then tag), and CI frequently does not fetch tags (shallow clone), so a hard assertion would go red in the normal flow. The wrong tool for a transient-legitimate state.
- **C: a hook.** Rejected: PHILOSOPHY disfavors hard-gating process; the trigger is fuzzy (on a version-file edit? on a tag?); and the untagged-cut state is a legitimate transient. A hook is overkill for a maintainer-facing heads-up.

### Chosen approach + why
Approach A. The maintainer at `/user:ship` is exactly who needs the warning at exactly the moment it matters (the version/tag decision); `kit-health` is the documented "run before tagging" self-assessment, so it catches the state even between ships. Both are warn-only, matching the existing completeness-clause grain (warn + report, never block). The meta-test pins the surfaces structurally without asserting a transient-sensitive runtime condition.

### Detection logic (the shared signal)
- **Phantom cut (primary, mechanical):** read the version from `VERSION` (and `.claude-plugin/plugin.json`; a meta-test already asserts they match), stripping whitespace (`tr -d '[:space:]' < VERSION`, matching the existing meta-test's read so a trailing newline cannot break the tag pattern). If `git tag -l "v<version>"` is empty, the files name an untagged version: warn. (During a real release this fires between the version-bump commit and the tag; the warn is then a correct "remember to tag" nudge.)
- **Identical shape across both surfaces (anti-drift):** ship and kit-health implement this exact check shape (the whitespace-strip, the `git tag -l "v<version>"` test, and the graceful degrade below). The meta-test pins each surface's *presence*; this spec pins their *shape*, so the two inlined copies (DEC-003) cannot diverge in edge behavior.
- **Accumulation context (soft):** when the phantom cut fires AND `CHANGELOG.md` `[Unreleased]` is non-empty, the warn adds "work is accumulating above an untagged cut" so the maintainer sees the compounding, not just the missing tag.
- **Graceful degrade:** if there is no `.git` (e.g. the installed copy under `~/.claude/dwarves-kit`), no `VERSION`, or `git` is unavailable, the check is a no-op (it is repo-scoped; it must not error in a non-repo context).

### Extensibility & boundaries
- Load-bearing dimension: the number of warn surfaces. Today two (ship, kit-health). The detection is small enough (a `git tag -l` comparison + a CHANGELOG grep) that it is inlined at each surface rather than abstracted (the kit's rule: no shared helper until the same code appears three times). A third surface is the trigger to extract a shared `checks/`-style helper, recorded here so the decision is not re-litigated.
- Boundaries: each surface is independently testable (ship.md carries the warn instruction; kit-health.md carries the check bash); the meta-test pins each.

### Architecture
```text
  VERSION / plugin.json = X
        │
        ▼
  git tag -l "vX"  ──── empty? ────▶ PHANTOM CUT
        │ present                         │ + CHANGELOG [Unreleased] non-empty?
        ▼                                 ▼
   (clean, silent)                  WARN (maintainer-facing, never block):
                                    "vX is not tagged; [Unreleased] is piling on top"
        ▲                                 ▲
        │                                 │
   surface 1: /user:ship Step 4     surface 2: kit-health line (repo-scoped, before tagging)
```

## Technical Design

### Interfaces (I/O contract)
- **Consumes:** `VERSION`, `.claude-plugin/plugin.json` (`.version`), `git tag -l`, `CHANGELOG.md` (`[Unreleased]` section). Read-only.
- **Produces:** a maintainer-facing warning string at `/user:ship` and a `kit-health` report line. No file writes, no block, no exit-code failure from the check itself.
- **Invariants:** the check never blocks a ship and never errors outside a git repo / without a VERSION file (graceful no-op). The meta-test asserts the surfaces carry the check, never that the working tree is currently tag-clean (that would be transient-sensitive).

### Data model / API / UI changes
None. Two command-prompt edits (`commands/ship.md`, `commands/kit-health.md`) + meta-test assertions. No new file, no new command, no hook, no `settings.json` wiring.

## Task Breakdown

### Phase 1: The ship-time warn (primary surface)
- [x] TASK-001 (DONE: 0a27c62 + fix abea75d, verified): Add a release-hygiene warn to `commands/ship.md` at the version step (Step 4, or a Step 4a adjacent to it). It instructs: read the version from `VERSION`, check `git tag -l "v<version>"`; if absent, WARN (phantom cut) and, if `CHANGELOG.md` `[Unreleased]` is non-empty, add the accumulation note. Warn-only, report to the maintainer, never block; degrade silently outside a git repo / without VERSION. Mirror the Step 1b "warn, not block" voice. AC: `commands/ship.md` contains the release-hygiene warn naming the `git tag` phantom-cut check and the "warn, not block" stance; `bash tests/test-meta.sh` green.

### Phase 2: The kit-health line (secondary surface)
- [x] TASK-002 (DONE: 0958107, verified): Add a release-hygiene check to `commands/kit-health.md` Step 1 (a new numbered bash check). Repo-scoped: compare `VERSION` to `git tag -l "v$(cat VERSION)"`; print a clean/PHANTOM-CUT line; degrade gracefully (no `.git`, no `VERSION`, no `git` => skip with a note, never error). AC: `commands/kit-health.md` Step 1 has the check; it is repo-scoped and degrades gracefully (no hard error in a non-repo context); `bash tests/test-meta.sh` green.

### Phase 3: Pin the surfaces
- [x] TASK-003 (DONE: 2b9f2a1, verified): Add a `tests/test-meta.sh` section "Release-hygiene guard" with assertions that (a) `commands/ship.md` carries the release-hygiene warn (greps for the phantom-cut / `git tag` check + the warn-not-block stance) and (b) `commands/kit-health.md` carries the phantom-cut check. The assertions pin the LOGIC's presence, NOT that the repo is currently tag-clean. AC: the new assertions PASS; `bash tests/test-meta.sh` exits 0 with an increased total.

## After state
- [ ] `/user:ship` warns when `VERSION` names an untagged version. (Today: ship bumps/changelogs with no tag-state check; the 1.6.0 phantom cut went unnoticed across two cycles.) Checkable: `rg -i "tag|phantom|release.hygiene" commands/ship.md` returns the warn.
- [ ] `kit-health` reports the phantom-cut state, repo-scoped + graceful. (Today: kit-health checks file count / hooks / descriptions, never the version/tag relationship.) Checkable: `rg -i "tag|phantom|VERSION" commands/kit-health.md` returns the check.
- [ ] The two surfaces are regression-pinned. (Today: nothing tests for them.) Checkable: `bash tests/test-meta.sh` includes and PASSes the "Release-hygiene guard" assertions.
- [ ] The check never blocks and never errors outside a repo. Checkable: the spec's Edge cases 2 + 3 hold by inspection of the added logic.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] `bash tests/test-meta.sh && bash tests/test-hooks.sh` green (no regressions).
- [ ] The guard is warn-only on both surfaces (no block, no test that fails on a legitimate untagged-transient).

## Verification
```bash
bash tests/test-meta.sh && bash tests/test-hooks.sh
```
Plus the After-state greps above (each a real command).

## Edge Cases
1. **Legitimate untagged transient (mid-release).** VERSION bumped + committed, tag not yet created: the warn fires, which is correct (it nudges "tag it"). It must NOT be a hard failure (that is why B was rejected).
2. **Not a git repo / installed copy.** kit-health's bash also runs against `~/.claude/dwarves-kit` (no `.git`): the check degrades to a skip-with-note, never errors.
3. **No `VERSION` file / `git` absent.** Skip silently; the check is best-effort.
4. **Clean state (VERSION tagged, `[Unreleased]` empty or normal):** no warn; the surface stays quiet.
5. **VERSION and plugin.json disagree.** Out of scope here: a separate meta-test already asserts `plugin.json` == `VERSION`; this guard reads `VERSION` as the source.

## Out of Scope
- Fixing the current `1.6.0` phantom cut or tagging anything (that is a release-cleanup action, not this guard).
- Bumping/auto-tagging versions or changing the ship version logic (this only adds a warn).
- A hard `tests/test-meta.sh` "must be tagged" assertion (Approach B, rejected: transient-legitimate).
- A hook (Approach C, rejected).
- A shared detection helper (deferred until a third surface needs it; see Extensibility).

## Decision Log
- DEC-001: Warn-only surfaces (ship + kit-health), Approach A; not a hard meta-test (B) or a hook (C). Rationale: matches the completeness-clause warn grain; B breaks on the legitimate untagged-transient + shallow-CI; C hard-gates process (PHILOSOPHY). Alternatives B/C rejected. (Confirmed with the maintainer at the surface checkpoint.)
- DEC-002: The detectable signal is the phantom cut (VERSION version not in `git tag`), not `[Unreleased]` accumulation. Rationale: the kit deliberately accumulates `[Unreleased]` across "no version bump" ships, so accumulation alone is not a bug; the untagged cut is. Accumulation is a soft context line layered on the phantom-cut warn.
- DEC-003: Detection is inlined at each surface, not a shared helper. Rationale: PHILOSOPHY "no premature abstraction" (two uses < three); a third surface triggers extraction. The meta-test pins both inlined copies against drift.
- DEC-004: The meta-test pins the surfaces' presence, never a tag-clean working tree. Rationale: a runtime tag assertion is transient-sensitive (Edge case 1) and CI-fragile (shallow clone).
- DEC-005 (validation): The check shape is pinned once in "Detection logic" (whitespace-strip the version, `git tag -l "v<version>"`, graceful no-git/no-VERSION degrade) and both surfaces implement it identically. Rationale: spec-validate Reviewer 5 noted the two inlined copies (DEC-003) could drift in edge handling while the meta-test only pins presence; pinning the shape in the spec closes that gap without a premature shared helper. Also folds R1/R2 robustness (quote + whitespace-strip the VERSION read).

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
