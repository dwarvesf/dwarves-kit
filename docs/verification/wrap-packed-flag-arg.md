# Proof of done: `wrap.sh` refuses flags packed into one argument

A caller that builds flags in a variable and passes it unquoted to a shell that does not word-split (zsh) hands `wrap.sh` one argument such as ` --own /path/to/wt`. It does not start with `-`, so it was read as a repo, printed `not a git repo, skipped`, and the `--own` scope was lost. `apply --worktrees $args <repo>` could then sweep every merged worktree in a shared repo.

One helper, `_reject_packed <verb> <arg>`, now runs in the positional branch of `apply`, `scan`, `merge`, `land`, `start` (repo, branch, and `--carry` paths), and `rebase`. It exits 64 with one stderr line when the leading-whitespace-trimmed argument starts with `-`, or the argument holds whitespace followed by `--`. A path with spaces and no ` --` passes.

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 1
test-wrap: 1596 passed, 2 FAILED of 1598
Verdict: PASS for this change. The 2 failures are pre-existing on origin/master
         ("step 10 re-sizes the real diff before landing", "commands/wrap.md classifies each
         candidate's lane"): HEAD's commands/wrap.md has no `lane-classify.sh classify` text.
```

```
Command: bash tests/test-docs-wiring.sh   -> === 25/25 passed ===
Command: bash tests/test-bin-forwarders.sh -> test-bin-forwarders: all 48 passed, 0 skipped
Command: shellcheck lib/wrap/wrap.sh       -> 13 findings before and after (no new finding)
```

## Negative control

```
Command: bash <copy of the tree with HEAD's lib/wrap/wrap.sh>/tests/test-wrap.sh
Exit: 1
test-wrap: 1587 passed, 11 FAILED of 1598
Verdict: RED. 9 new cases fail (apply exit 64, apply message, apply never a repo, scan exit 64,
         scan message, land/rebase/merge/start message); the same 2 pre-existing failures remain.
```

The tree copy held the new tests and HEAD's `wrap.sh`; the real worktree kept the fix throughout.

## Not proven
- `--own` given as two arguments still scopes: covered by the existing `apply --own` cases in the same file, all green.
- A `--title` value or a `--under` root that itself holds ` --` is now refused; accepted as the cost of one shared rule.
