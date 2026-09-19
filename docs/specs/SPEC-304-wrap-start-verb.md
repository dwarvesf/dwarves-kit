# SPEC-304: wrap start, the hand-made-worktree opening half

**Status:** VALIDATED (the change lands in the same PR)
Lane: normal
**Proof:** `tests/test-wrap.sh`, the `=== start:` block; `docs/verification/wrap-start.md`.

## Problem

Sessions repeatedly hand-run "create a worktree off `origin/<default>` with a fresh branch, edit, commit, push, `gh pr create`" when the main checkout is dirty or foreign; one wrap report counted four hand-runs in a single session across ops-toolkit, forge, dwarves-kit and dfoundation. `wrap land <worktree>` already owns the finish side (push -> PR -> merge -> tidy). The start side had no verb, so every session re-derived the fetch, the `.claude/worktrees` path convention, and the branch-at-remote-tip incantation by hand.

## Contract

`bin/wrap start <repo> <branch>`:

- Resolves `<repo>`'s default branch through `_default_branch` (origin/HEAD, else main, else master; the helper every wrap verb already uses), then `git fetch -q origin <default>`.
- Creates `<repo>/.claude/worktrees/<slug>` at `origin/<default>` on a NEW local branch `<branch>` via `git worktree add -b`, where `<slug>` is `<branch>` with its `type/` prefix stripped (gate-ledger's rid rule).
- The resolved worktree path is the only stdout line, so a caller captures it directly; every diagnostic goes to stderr.
- A dirty main checkout is never a refusal: the worktree is isolated, which is the point of the verb.
- Refusals, each with its named reason before any write: missing argument, a `<repo>` that is not a git repo, an invalid `<branch>` name (`git check-ref-format --branch`) -> usage, exit 64. Then exit 1: `<branch>` naming the default or `main`/`master`; `<branch>` already a local ref; the worktree path already on disk; no default branch resolved; a failed fetch; `<branch>` already on origin (live `ls-remote`, plus the tracking ref); a held `index.lock` (`_write_guard`); a `worktree add` git itself refuses. `git worktree prune` runs before the add so a path deleted out-of-band cannot wedge it.
- Never switches a branch, never pushes, never deletes anything. The write set gains exactly one entry: the worktree add under `.claude/worktrees` on a new local branch.

## Design record

`lib/goal/wt.sh start` runs this same sequence and was checked first, per the precedent rule. It is a different contract: hardcoded `origin/master`, a slug-only grammar (`[a-z0-9-]+`), requires running inside the repo, and carries kit-work-unit side effects (gate-ledger START, board-row claim). `lib/worktree-provision` provisions env/deps into a worktree after creation and never creates one. `wrap start` is the generalized verb beside `wrap land`, not a sibling of either. The same-name-on-origin check runs live (`ls-remote`) rather than trusting tracking refs, because `fetch origin <default>` refreshes no other ref and `worktree add -b` never sees the remote: a local branch created over an already-pushed name collides only at push time.

## Test plan

| Case | Setup | Expected |
|---|---|---|
| happy path | clone, then remote tip advanced | exit 0; stdout is exactly the resolved worktree path; worktree HEAD == fetched tip; `branch --show-current` is the new branch; local ref + worktree entry exist |
| master default | clone of a `master`-remote | exit 0, worktree at `origin/master` |
| local branch exists | after the happy path | exit 1, names the branch |
| name on origin | branch pushed post-clone | exit 1, `already exists on origin`, no local branch created |
| path exists | `mkdir -p .claude/worktrees/<slug>` | exit 1, names the path, no branch created |
| protected name | `main` | exit 1, names the protected reason |
| invalid name | `feat/../x` | exit 64, names the invalid name |
| usage | no args / non-repo | exit 64 |
| no remote | repo with no origin | exit 1, `no default branch resolved` |
| failed fetch | broken origin URL | exit 1, `fetch origin main failed`, nothing left behind |
| dirty main checkout | uncommitted tracked edit | exit 0, worktree created, dirty line untouched |
| docs wiring | `--help`, `commands/wrap.md` | both name `start` |

## Verification

`bash tests/test-wrap.sh` runs the `=== start:` block with the rest of the suite. `docs/verification/wrap-start.md` holds the run-table, the live run on the real dwarves-kit checkout, and the negative control (master's `bin/wrap` -> `unknown verb`, exit 64).

## Out of scope

No commit, push, or `gh pr create` inside the verb; those stay session steps. No `--base` override (the detected default is the contract). No change to `lib/goal/wt.sh`, which keeps its gate-ledger and board side effects. No automatic `worktree-provision` run after the add; an operator who wants env/deps provisioned calls it separately.
