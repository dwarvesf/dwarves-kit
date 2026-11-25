{{KIT_MARKER}}
# Agent rules

This file is the repo's instruction file for every coding agent and every teammate. Everything you need is in this file and the files it names. No plugin or extra tool is required: a shell with `git` and `gh`, plus the toolchains your own code needs, is enough.

[docs/TEAM-WORKFLOW.md](docs/TEAM-WORKFLOW.md) gives the reasons behind each rule. The rules themselves live only here.

## Commands

Run `bash scripts/check.sh` before every push. It runs the same checks as CI, with the same inputs: the owners check, the PR shape check and every script test. Run each command from the repo root.

| Task | Run | When |
|---|---|---|
| Before a push | `bash scripts/check.sh` | every PR |
| Merge | `bash scripts/pr-merge.sh --wait <number>` | the PR is ready; never a bare `gh pr merge` |
| Script tests | `bash scripts/test-<name>.sh` for the script you changed | anything under `scripts/` |
| Negative control | `bash scripts/negctl.sh "<test command>" "<mutate command>"` (commit first; it prints the block for the proof file) | a proof for a behavior change |
| Owners | `bash scripts/check-owners.sh` | a new script, workflow or job |
| Work queue | `bash scripts/issues-from-rows.sh` for a dry run, then `--apply` | after the board file changes |
| Team digest | `bash scripts/team-digest.sh` | in place of a stand-up |
| Release notes | `bash scripts/release-notes.sh Unreleased` (`--help` for usage) | when you cut a release |
| Lessons | `bash scripts/agent-lessons.sh` | before work a lesson may cover |
| Language tests | the repo's own build and test commands: add a row here for each | the paths each one covers |

- Branch: `git switch -c <type>/<short-slug>`. Never work on `{{DEFAULT_BRANCH}}`.
- PR title and commit subject: a conventional commit, `type(scope): subject`, 72 characters or less. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`, `build`, `perf`.
- CI runs the owners check (job `changes`) and the PR shape check (job `pr-shape`) on a self-hosted runner. A repo with no runner shows the checks as pending: run `bash scripts/check.sh` instead, and `pr-merge.sh --wait` never merges on a pending check. Language test jobs are the repo's to add.
- `scripts/agent-guard.sh` is a hook, not a command: you never run it by hand.

## Playbooks

Claude Code loads these as project skills. Any other agent reads the file as a plain step list.

- `.claude/skills/ship-pr/SKILL.md`: an issue to a merged PR: claim, branch, build, proof, `scripts/check.sh`, PR, checks, `scripts/pr-merge.sh`, clean up.

## Lessons

`.claude/memory/MEMORY.md` lists what past work already paid for, one line each. Claude Code prints it at session start through the hook in `.claude/settings.json`. Other agents: run `bash scripts/agent-lessons.sh` or read the file. Read the note before you do the work it covers.

Add a lesson when your PR paid for one. One note per lesson, in the same PR: a file `.claude/memory/<slug>.md` with `name` and `description` in the frontmatter, then the fact, the why and how to apply it, under 1,200 characters, with no personal names and no dates. Add one line to `MEMORY.md`. Keep `MEMORY.md` under 8,000 characters: Claude Code caps hook output at 10,000 characters and shows only a short preview of more.

## Team rules

These rules apply to every agent and teammate.

### Work queue
- Your work comes from GitHub Issues. If the repo keeps a board file, it is the plan. List yours: `gh issue list --assignee @me --label ready --state open`.
- An issue is one unit of work for one agent run. Body: `## Goal`, `## Done when` (one check you can run), `## Scope`, optional `## Notes`.
- Labels: `ready` (Goal and Done when are set, an agent may take it), `one-way-door` (a second person says yes before merge), `blocked` (waits on something named in the body).
- Claim an issue by assigning yourself, before you build. An unassigned `ready` issue is free to take. An assigned issue with no linked PR after 7 days goes back to unassigned; anyone may release it.
- Work under a day: open a draft PR at once.

### What a PR carries
- `Closes #<n>` in the body, the issue that holds the work. When the repo keeps a board file and the issue came from a row, the same PR updates that row.
- No issue and no row (a typo, a tooling fix): one body line `no-board-row: <reason, 10+ characters>`.
- Fix any doc the change makes wrong, in the same PR.
- Optional marker lines in the PR body: `no-board-row:`, `no-changelog:`, `no-proof:` and `no-rule-mirror:` (each with a reason of 10+ characters), and `One-way door:` (see below).
- A change to `AGENTS.md` or `docs/TEAM-WORKFLOW.md` changes both, so the two stay in step. A change that truly needs only one puts `no-rule-mirror: <reason>` in the PR body.

### Proof
- A change to a behavior path adds `docs/verification/<slug>.md`, one file per PR: a proof file with `Command:`, `Output:`, `Exit:` and `Verdict:` blocks and pasted output. How to write one: [docs/verification/README.md](docs/verification/README.md).
- A behavior path is any changed file that is not documentation: not `.md` or `.txt`, and not an image, PDF or CSV under `docs/`.
- The proof file holds a negative control: break the change on purpose, show the test go red, restore. That block is headed `NEGATIVE CONTROL` and ends `Verdict: RED, as expected`. Commit first so the restore works; `scripts/negctl.sh` prints the block.
- CI requires a proof file that the PR adds or changes, that is not the README, with an `Exit:` line, an `Output:` line followed by a non-empty line, a line that starts `Verdict: RED`, and the words `NEGATIVE CONTROL`.
- A change with no behavior effect (a comment, a rename, formatting) puts `no-proof: <reason, 10+ characters>` in the PR body instead.
- `docs/verification/README.md` is never a proof.

### Changelog
- A change under {{PRODUCT_PATHS}} adds a `CHANGELOG.md` line under `## [Unreleased]`. Every line starts with one tag from this list: {{TAGS_COLON}}. The tag `dev:` marks team tooling and stays out of the release notes.
- No effect a user sees: `no-changelog: <reason, 10+ characters>` in the PR body.

### One-way doors
A door is hard to undo after it ships: money and pricing, legal and consent text, a data format a shipped client reads, deleting production data, secrets and access. Get a second person's yes, recorded in the PR, before you change one: the line `One-way door: <door>. Second yes: #<github-login>` in the PR body, with a link to their comment. The author cannot be the second yes. Reversible work merges when checks pass, with no approval. Unsure? Treat it as a door.

| Door setting | Value |
|---|---|
| Paths the merge guard checks (a comma list; blank means the guard lists no path) | {{DOOR_PATHS}} |
| Who says the second yes for those paths (blank means any person other than the author) | {{DOOR_APPROVER}} |

The merge guard checks only the paths in that table. For every other door, the `One-way door:` line and the reviewer are the control.

### Merge
- Merge with `bash scripts/pr-merge.sh --wait <number>`, never a bare `gh pr merge`. `--wait` polls the checks until none is pending (`--timeout <seconds>`). It refuses a draft, a red or pending check, a conflict, and a change under a door path without a second person's approval. It merges the exact head it judged.
- `--dry-run` prints the verdict and merges nothing.
- Never push to `{{DEFAULT_BRANCH}}` and never commit on it.

### Checks
- CI job `pr-shape` fails a PR with a title that is not a conventional commit, a behavior change with no valid proof (see Proof) or no board link (a changed board file, a `Closes #<n>` line or `no-board-row:`), product code with no tagged `CHANGELOG.md` line, a changed shell script that fails shellcheck, or a change to only one of `AGENTS.md` and `docs/TEAM-WORKFLOW.md`. Run it first: `bash scripts/check.sh`, which runs `scripts/pr-shape.sh` with the same inputs as CI.
- Every new script, workflow or job gets an owner row in `OWNERS.md` in the same PR. An agent owner names a sponsor, a person who answers for it.
- Every refusal from a script prints two lines: the rule, then `Fix:` and a command you can paste. Run the fix.

### Limits
- GitHub cannot enforce any of this without branch protection. A person who merges from the GitHub site passes everything, on a plan without branch protection.
- Two machines back the rules instead: a Claude Code hook (`.claude/settings.json`, `scripts/agent-guard.sh`) for agents that run in Claude Code, and the CI check `pr-shape` for everyone. The hook blocks a bare `gh pr merge`, a push to `{{DEFAULT_BRANCH}}` and a commit on `{{DEFAULT_BRANCH}}`, and prints the fix. It is advice with teeth, not a wall: see the lesson "Guards match command text".
- Claude Code uses a hook from `.claude/settings.json` even in a folder not yet trusted (only a parent folder trusted, or a `claude -p` run), so a teammate needs no extra step.
- Agents other than Claude Code get no hook: CI is their stop.

## Never
- Never push to `{{DEFAULT_BRANCH}}`, never commit on it, never run a bare `gh pr merge`.
- Never hide a command from the hook (in a variable or a helper script) to get past it. The rule still holds and CI finds the break later.
- Never touch secrets or access. Stop and ask a human.
- Never paste a secret, a token or a private key into a file, a PR, an issue or a proof.
- Never invent output. A proof holds what the command printed, not what it should print.
- Never merge a PR whose check is red or pending.

## Optional kit

Nothing above needs a plugin. If you also use dwarves-kit, its contract is at https://github.com/dwarvesf/dwarves-kit and its gates read `.kit.toml`. Where its generic rules differ from the rules above, this repo's rules win.
