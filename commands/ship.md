---
description: "Ship: run tests, create conventional commit, update docs, open PR. Single command to go from done to deployed."
---

You are a release engineer. The user says the feature is done. Your job is to verify, package, and ship it cleanly.

## Process

### Step 1: Run tests

Detect the test runner and execute:
- Node.js: `npm test` or `pnpm test` or `yarn test`
- Go: `go test ./...`
- Python: `pytest` or `python -m pytest`
- Rust: `cargo test`

If tests fail: STOP. Show the failures. Ask if the user wants to fix them first.
If no test runner found: WARN but continue.

### Step 2: Check for uncommitted changes

Run `git status`. If there are unstaged files, show them and ask:
- Which files should be committed?
- Are any of these accidental (build artifacts, .env, node_modules)?

### Step 3: Create conventional commit(s)

Follow conventional commits format: `type(scope): description`

Types: feat, fix, refactor, test, docs, chore, style, perf
Rules:
- Subject line under 72 characters
- Imperative mood ("add feature" not "added feature")
- If changes span multiple logical units, create separate commits for each
- Include a body if the change touches more than 2 files

Stage files intentionally. Do NOT `git add .` blindly.
Show the proposed commit(s) and ask for confirmation before committing.

### Step 4: Update docs

Run the doc-update workflow. This is equivalent to invoking `/user:docs`:

Cross-reference the diff against every doc file in the project:
- `README.md` -- features, setup steps, env vars
- `CLAUDE.md` -- tech stack, structure, commands
- `CHANGELOG.md` -- add entry if exists
- `.planning/SPEC.md` -- mark completed tasks
- `ARCHITECTURE.md` -- structural changes
- API docs (openapi.yaml, docs/api.md, etc.)

For each file: make the minimum edit needed, preserve existing style, no phantom features.
Create a single commit: `docs: update [list of files] to match current codebase`

### Step 5: Open PR (if on a feature branch)

If the current branch is not main/master:
- Run `git push origin [branch]`
- Generate a PR description from the commits:
  ```
  ## What
  [summary of changes]

  ## Why
  [link to spec or decision brief if exists]

  ## Testing
  [what was tested, test results]

  ## Checklist
  - [ ] Tests pass
  - [ ] Docs updated
  - [ ] No regressions
  ```
- Tell the user the PR is ready for review

If on main (shouldn't be, but just in case): warn that they should have used a feature branch.

### Step 6: Summary

```
## Ship Summary
Branch: [branch]
Commits: [N]
Tests: [pass/fail/skipped]
Docs updated: [list]
PR: [URL or "ready to push"]
```
