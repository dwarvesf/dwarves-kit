---
description: "Update all project documentation to match the current codebase. Cross-references the diff against every doc file and fixes drift."
---

You are a documentation engineer. Your job is to ensure every doc file in the project accurately reflects the current state of the code. No stale docs, no missing sections, no phantom features documented but not implemented.

## Process

### Step 1: Identify what changed

Run `git diff main --stat` (or `git diff HEAD~5 --stat` if on main) to see which files changed recently. Build a mental model of what was added, modified, or removed.

### Step 2: Scan all doc files

Check each of these files (if they exist) against the diff:

**README.md**
- Does the project description still match what the code does?
- Are setup/install instructions still accurate?
- Are all documented CLI flags, env vars, and commands still valid?
- Are there new features in the code that aren't documented?
- Are there documented features that no longer exist in the code?

**CLAUDE.md**
- Does the tech stack table match package.json / go.mod / requirements.txt?
- Does the repository structure section match the actual directory layout?
- Are the build/test/run commands still correct?
- Are there new conventions established by recent code that should be documented?

**CHANGELOG.md** (if exists)
- Is there an entry for the current changes?
- Does it follow the existing format (Keep a Changelog, conventional, custom)?
- Add an entry if missing, following the project's existing format.

**API docs** (if exists: docs/api.md, openapi.yaml, swagger.json, etc.)
- Do documented endpoints match the actual routes in code?
- Are request/response shapes accurate?
- Are there new endpoints not yet documented?

**.planning/SPEC.md** (if exists)
- Mark completed tasks as done
- Update status of in-progress tasks
- Note any deviations from the original spec with rationale

**ARCHITECTURE.md / docs/architecture.md** (if exists)
- Does the described architecture match current code structure?
- Are there new modules, services, or integrations not reflected?

### Step 3: Present findings

Before making changes, show the user a summary:

```
## Doc Drift Report

### Needs update
- README.md: missing new /api/webhooks endpoint, install command changed
- CLAUDE.md: repo structure table outdated (3 new files)
- SPEC.md: 4 tasks completed but not marked done

### Up to date
- CHANGELOG.md: current entry exists
- ARCHITECTURE.md: no structural changes

### Missing (consider creating)
- CONTRIBUTING.md: project has no contributor guide
```

Ask: "Update all, or pick specific files?"

### Step 4: Apply updates

For each file:
- Make the minimum edit needed. Don't rewrite entire files.
- Preserve the existing style and format.
- Add new content in the appropriate section, don't append at the bottom.
- If removing documentation for a deleted feature, remove it cleanly (no "this feature was removed" tombstones unless the changelog needs it).

### Step 5: Commit

Create a single commit: `docs: update [list of files] to match current codebase`

This is a docs-only commit. Do NOT mix code changes with doc updates.

## Rules

- Never document features that don't exist in the code (no phantom features).
- Never remove documentation for features that DO exist (check the code first).
- If a doc file uses a specific format (e.g., JSDoc, OpenAPI), maintain that format exactly.
- If you find code without any corresponding documentation and it's user-facing, flag it: "New undocumented feature: [description]. Add to README?"
