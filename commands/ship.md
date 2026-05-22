---
description: "Ship: review gate, tests, version bump, changelog, conventional commit, docs update, PR. Complete pipeline from done to merged."
---

You are a release engineer. The user says the feature is done. Your job is to verify, package, and ship it cleanly.

## Process

### Step 1: Review gate

Check if a review has been done:
- Does `REVIEW.md` exist? Read its verdict.
- If verdict is `SHIP` or `FIX THEN SHIP` (with fixes applied): proceed.
- If verdict is `DO NOT SHIP`: STOP. Tell the user to fix the issues first.
- If no `REVIEW.md` exists: WARN. Ask: "(A) Run /kit:review first / (B) Run /kit:review-team for thorough review / (C) Skip review and ship anyway"

Do not silently skip the review check. The user must explicitly choose to ship without review.

### Step 1b: Completeness log (warn, not block)

Read `~/.claude/dwarves-kit/logs/completeness.log` (the warn+log sink from the WORKFLOW completeness clauses). Surface any entries since the last ship/tag: lost build-decisions (decision-translation) and un-updated companion docs (doc-update, per the WORKFLOW doc-impact map). REPORT them so the maintainer decides; do NOT auto-block on completeness. Hard blocks stay reserved for the REVIEW.md DO-NOT-SHIP verdict and the safety gates. If the log is absent or empty, say "completeness: clean". Source: SPEC-006.

### Step 2: Run tests

Detect the test runner and execute:
- Node.js: `npm test` or `pnpm test` or `yarn test`
- Go: `go test ./...`
- Python: `pytest` or `python -m pytest`
- Rust: `cargo test`

If tests fail: STOP. Show the failures. Ask if the user wants to fix them first.
If no test runner found: WARN but continue.

### Step 3: Check for uncommitted changes

Run `git status`. If there are unstaged files, show them and ask:
- Which files should be committed?
- Are any of these accidental (build artifacts, .env, node_modules)?

### Step 4: Version bump (if applicable)

Check if the project has a version file:
- `package.json` (Node.js): read current version
- `version.go` or `VERSION` file (Go): read current version
- `Cargo.toml` (Rust): read current version
- `pyproject.toml` (Python): read current version

If a version file exists:
- Determine bump type from the changes:
  - Breaking changes or major refactors: major bump (ask user to confirm)
  - New features: minor bump
  - Bug fixes, docs, refactors: patch bump
- Present the proposed bump: "Current: 1.2.3, Proposed: 1.3.0 (minor: new feature). Approve?"
- Apply the bump to the version file.

If no version file exists: skip this step silently.

### Step 4a: Release-hygiene warn (warn, not block)

At the version/tag decision, check for a **phantom cut**: `VERSION` names a version that has no matching git tag. Run the check, then REPORT to the maintainer; do NOT block the ship. Mirror the Step 1b "warn, not block" voice: hard blocks stay reserved for the REVIEW.md DO-NOT-SHIP verdict and the safety gates.

Use this exact check shape (kit-health's check uses the same shape; they must not drift):

```bash
# Graceful degrade: no VERSION or not in a git repo => silent no-op, never error or block.
if [ -f VERSION ] && git rev-parse --git-dir >/dev/null 2>&1; then
  VER=$(tr -d '[:space:]' < VERSION)   # strip whitespace so a trailing newline cannot break the pattern
  if [ -n "$VER" ] && [ -z "$(git tag -l "v$VER")" ]; then
    echo "WARN release-hygiene: phantom cut. VERSION names v$VER but no matching git tag exists."
    # Accumulation context: [Unreleased] non-empty => work piling above an untagged cut.
    if [ -f CHANGELOG.md ] && awk '/## \[Unreleased\]/{f=1;next} /^## /{f=0} f && NF{print}' CHANGELOG.md | grep -q .; then
      echo "         work is accumulating above an untagged cut v$VER."
    fi
  fi
fi
```

If the phantom cut fires, surface it as a heads-up at the version step (remember to tag `v$VER`), then continue. During a real release this fires between the version-bump commit and the tag, where the warn is the correct "remember to tag" nudge. Source: SPEC-028 (DEC-001 warn-only, DEC-005 shared shape).

### Step 5: Generate changelog entry

If `CHANGELOG.md` exists (or the project follows a changelog convention):
- Generate an entry from the commits since last release/tag:
  ```
  ## [version] - YYYY-MM-DD

  ### Added
  - [feature descriptions from feat() commits]

  ### Fixed
  - [fix descriptions from fix() commits]

  ### Changed
  - [refactor/chore descriptions]
  ```
- Prepend to CHANGELOG.md (newest first).
- If no CHANGELOG.md exists: offer to create one. If user declines, skip.

Source: Keep a Changelog format (keepachangelog.com).

### Step 6: Create conventional commit(s)

Follow conventional commits format: `type(scope): description`

Types: feat, fix, refactor, test, docs, chore, style, perf
Rules:
- Subject line under 72 characters
- Imperative mood ("add feature" not "added feature")
- NO spec IDs, task IDs, or phase markers in the subject (e.g. no trailing `(SPEC-002 TASK-5)`); put that context in the body or PR description
- If changes span multiple logical units, create separate commits for each
- Include a body if the change touches more than 2 files

Stage files intentionally. Do NOT `git add .` blindly.
Show the proposed commit(s) and ask for confirmation before committing.

### Step 7: Update docs

Run the pinned diff (the merge-base of the integration branch) against the WORKFLOW doc-impact map and update every companion the map names for each change-type touched; log any companion that did not move. The map is the canonical list. The bullets below are the common cases:
- `README.md` -- features, setup steps, env vars
- `CLAUDE.md` -- tech stack, structure, commands
- `CHANGELOG.md` -- already updated in Step 5
- `docs/specs/SPEC-NNN-<slug>.md` -- mark completed tasks
- `ARCHITECTURE.md` -- structural changes
- API docs (openapi.yaml, docs/api.md, etc.)

For each file: make the minimum edit needed, preserve existing style, no phantom features.
Create a single commit: `docs: update [list of files] to match current codebase`

### Step 8: Open PR (if on a feature branch)

If the current branch is not main/master:
- Run `git push origin [branch]`
- Generate a PR description from the commits:
  ```
  ## What
  [summary of changes]

  ## Why
  [link to spec or decision brief if exists]

  ## Review
  [review verdict from REVIEW.md, or "not reviewed"]

  ## Testing
  [what was tested, test results]

  ## Checklist
  - [x] Tests pass
  - [x] Docs updated
  - [x] Review: [SHIP / skipped]
  - [ ] No regressions
  ```
- If the spec references issue numbers, link them in the PR.
- Tell the user the PR is ready.

If on main: warn that they should have used a feature branch.

### Step 9: Summary

```
## Ship summary
Branch: [branch]
Version: [old] -> [new] (or "no version file")
Commits: [N]
Tests: [pass/fail/skipped]
Review: [SHIP / FIX THEN SHIP / skipped]
Changelog: [updated / created / skipped]
Docs updated: [list]
PR: [URL or "ready to push"]
```

Source: ClaudeKit /ck:ship pipeline (merge > test > adversarial review > version > changelog > push > PR). Adapted: review gate checks existing REVIEW.md instead of running inline review. Version bump is optional and project-aware.
