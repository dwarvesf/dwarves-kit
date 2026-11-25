---
description: "Write a kit-free agent harness into a repo whose team does not run the kit: self-contained AGENTS.md and a people's copy, a project hook that blocks a bare merge and a push or commit on the default branch, session-start lessons, a ship playbook, a PR shape CI job with its local twin, an owners check, a merge guard, a negative control, an Issues work queue, a tagged changelog, a digest and a proof guide. Idempotent, never overwrites an edited file, reports drift."
---

You are stamping a repo with the team harness. One operator runs the kit; the teammates and their
coding agents do not. Every file this writes is a plain copy the repo owns and runs with no kit
installed: no file names a path under the kit, and the stamp adds no daemon and no service.

## Run

`$ARGUMENTS` may name a target dir (default: the repo root) and any of the value flags below.

1. Resolve the target: default `.` (`git rev-parse --show-toplevel`). It must be a git repo.
2. Dry run first, then write (idempotent, non-destructive):

   ```
   bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/stamp.sh" --dry-run --owner <github-login> <target>
   bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/stamp.sh" --owner <github-login> <target>
   ```

3. Report the status lines it printed (`created`, `merged`, `unchanged`, `edited (left alone)`,
   `older stamp (run --refresh)`, `missing`) and any two-line refusal with its `Fix:` line. The
   operator reviews and commits the files; the stamp commits nothing.

## Flags

| Flag | Default | Used for |
|---|---|---|
| `--owner <login>` | required | the owner row of every generated script in `OWNERS.md` |
| `--default-branch <name>` | `origin/HEAD`, else refuse | the guard, the merge guard, the checks |
| `--tags a,b` | `product,dev` (`dev` is always added) | changelog tags; release notes drop `dev:` |
| `--product-paths a/,b/` | `src/` | paths that owe a tagged changelog line |
| `--door-paths p,q` and `--door-approver <login>` | empty | paths that need a second person's approval before merge |
| `--board-file <path>` | empty | the board the queue and the digest read |
| `--decision-tag <word>` | `decision` | the tag of a board row that waits on a human |

A value is remembered in `.claude/team-stamp.lock`, so a re-run with no flags renders the same bytes.

## Modes

- `--check`: write nothing; exit 0 only when every file is present and unchanged.
- `--dry-run`: print what would be written.
- `--refresh`: after a kit upgrade, print one unified diff per file whose template changed, and
  the `--take <path>` command for it. It writes nothing.
- `--take <path>`: replace exactly one file the repo did not edit (its hash equals its lock hash),
  keeping the old copy as `<path>.orig`. An edited file is refused and its diff printed; the
  operator applies it by hand. `--take` also swaps adopt's own `AGENTS.md` pointer and proof
  marker for the stamp's versions.
- `--only <group,group>`: limit the run to named template groups (group tests use it).

## What it writes

The file list lives in `docs/specs/SPEC-425-team-stamp.md` ("Generated files"). In short:

- `AGENTS.md` (the kit marker on line 1, a closing optional-kit section naming only the public
  URL) and `docs/TEAM-WORKFLOW.md`, with a CI parity check between them.
- `.claude/settings.json` (merged by entry, never rewritten), `scripts/agent-guard.sh`,
  `scripts/agent-lessons.sh`, `.claude/memory/` seeded with five CI lessons, the `ship-pr` skill.
- `.github/workflows/ci.yml` (always `runs-on: [self-hosted]`), `scripts/pr-shape.sh`,
  `scripts/check.sh` (the local twin), `scripts/check-owners.sh`, `OWNERS.md`,
  `scripts/pr-merge.sh`, `scripts/negctl.sh`, each with its own test under `scripts/test-*.sh`.
- The issue form, `scripts/issues-from-rows.sh`, the PR template, `CHANGELOG.md`,
  `scripts/release-notes.sh`, `scripts/team-digest.sh`, `docs/verification/README.md`, and a
  `.kit.toml` with the proof gate on and the lane gate off.

`OWNERS.md`, `CHANGELOG.md` and the lesson notes are written once and then belong to the repo.

## Order with adopt

Either order works. Stamp first: adopt leaves the stamp's files alone. Adopt first: the stamp
reports adopt's `AGENTS.md`, proof marker and `.kit.toml` as left alone; `--take AGENTS.md` and
`--take docs/verification/README.md` swap the first two; a `.kit.toml` with `lane_gates = true`
gets a two-line drift report and is never edited. Kit hook entries in `.claude/settings.json`
are counted in a note and left in place.

## Limits

- It binds Claude Code through the project hook and every other agent through CI. A person who
  merges from the GitHub site passes everything on a plan without branch protection; the
  generated rules say so.
- The workflow needs a self-hosted runner. Without one it queues; `bash scripts/check.sh` is the
  check until one exists.
- Language test jobs, product playbooks and the list of irreversible paths are the repo's own.

Detail: `lib/stamp/README.md` (how a template group plugs in), `docs/specs/SPEC-425-team-stamp.md`.
