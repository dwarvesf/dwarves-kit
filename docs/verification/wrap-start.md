# Proof of done: `bin/wrap start`, the hand-made-worktree opening half

`start` is the start side `land` finishes. `bin/wrap start <repo> <branch>` resolves the repo's detected default branch through `_default_branch` (the same helper `scan`/`apply`/`merge`/`land` read), fetches `origin/<default>` quietly, and creates `<repo>/.claude/worktrees/<slug>` at `origin/<default>` on a new local `<branch>`, where `<slug>` is the branch name with its `type/` prefix stripped. The worktree path is the only stdout line, so a caller captures it directly; every diagnostic is on stderr. A dirty main checkout is never a refusal, which is the point of the verb: the worktree is isolated. What refuses, each with its named reason before any write: a missing argument, a non-repo `<repo>` or an invalid `<branch>` name (usage, 64), a protected name (`<def>`/`main`/`master`), an existing local branch, an existing same-named branch on origin (live `ls-remote`, since `worktree add -b` never sees the remote), an existing worktree path, an unresolved default branch, a failed fetch, a held `index.lock`, and a `worktree add` git itself refuses.

The precedent checked first: `lib/goal/wt.sh start` runs this same sequence but is a different contract (hardcoded `origin/master`, slug-only grammar, gate-ledger start + board-row claim side effects for kit work units), and `lib/worktree-provision` provisions a worktree after creation, it never creates one. `wrap start` is the generalized verb beside `wrap land`, not a sibling of either.

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | the worktree is created at the fetched `origin/<default>` tip on the new branch | `test-wrap.sh` start happy path: worktree HEAD equals the post-clone-pushed remote tip, `branch --show-current` is `feat/start`, the local ref and `worktree list` entry exist |
| AC2 | the worktree path is the only stdout line (scriptable) | `chk "start prints only the worktree path on stdout"` compares the full stdout capture to the resolved path |
| AC3 | a non-`main` default branch resolves | master-default fixture: worktree HEAD equals `origin/master` |
| AC4 | an existing local branch refuses | exit 1, message names the branch |
| AC5 | a same-named branch on origin refuses | exit 1, `branch feat/pushed already exists on origin`; the clone predates the push so the live `ls-remote` check is what fires |
| AC6 | an existing worktree path refuses | exit 1, `.claude/worktrees/collide already exists`, no branch created |
| AC7 | a protected name and an invalid name refuse | exit 1 naming `main`; exit 64 naming the invalid name |
| AC8 | a dirty main checkout is not a refusal | exit 0, worktree created, the sibling's dirty line untouched |
| AC9 | unresolved default / failed fetch refuse with their reasons | exit 1 on a no-remote repo and on a broken origin URL, naming each reason |
| AC10 | usage and docs wiring | `wrap --help` names `start`; `commands/wrap.md` names `bin/wrap start <repo> <branch>`; no-arg and non-repo calls exit 64 |
| AC11 | no regression to the rest of wrap | full `test-wrap.sh` green |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 724 passed
Verdict: PASS
```

```
Command: bash tests/test-bin-forwarders.sh
Exit: 0
test-bin-forwarders: all 48 passed, 0 skipped
Verdict: PASS
```

```
Command: bash tests/test-docs-wiring.sh
Exit: 0
=== 25/25 passed ===
Verdict: PASS
```

## Live run (not a fixture)

`bin/wrap start` ran against the real dwarves-kit checkout while it was dirty (`_meta/backlog-staging.md` modified, foreign untracked dirs present) and nested inside another live worktree:

```
Command: ./bin/wrap start /Users/tieubao/workspace/dwarvesf/dwarves-kit test/wrap-start-live
Exit: 0
STDOUT: /Users/tieubao/workspace/dwarvesf/dwarves-kit/.claude/worktrees/wrap-start-live
(STDERR empty)
worktree branch: test/wrap-start-live
worktree HEAD:   7238c6c fix(board): dedupe reports an absent id instead of silent set -e death (#716)
                 -- origin/master's tip, ahead of the checkout's own b7d5828, so the fetch ran
```

Tidied with `git worktree remove` + `git branch -D test/wrap-start-live`; `git worktree list` no longer names it.

## Negative control

The master checkout's `bin/wrap` has no `start` verb; the same command on the branch does.

```
Command: /Users/tieubao/workspace/dwarvesf/dwarves-kit/bin/wrap start <repo> test/wrap-start-live   (master checkout's bin/wrap)
Exit: 64
wrap: unknown verb 'start' (try: wrap --help)
Verdict: RED as expected -- the verb does not exist on master
```

```
Command: <worktree>/bin/wrap start <repo> test/wrap-start-live   (this branch's bin/wrap)
Exit: 0, prints the worktree path
Verdict: GREEN
```

The fixture-suite control is the same shape `wrap-land.md` used: with `lib/wrap/wrap.sh` reverted the new `=== start:` cases all fail on `unknown verb`, and nothing else in the suite moves.

## Not proven

- `git worktree add`'s own refusal path has code and a message but no dedicated case (the colliding-path and colliding-branch refusals fire first in practice).
- The held-`index.lock` refusal is `_write_guard`, already covered under `apply`; `start` reuses it untested-at-this-verb.
- Single-fixture branch grammar: `<type>/<slug>` is exercised; a bare `<branch>` with no prefix also works (slug = the whole name) but has no case.

## Reproduce

```
bash tests/test-wrap.sh
bin/wrap start <repo> <branch>     # prints <repo>/.claude/worktrees/<slug>
```
