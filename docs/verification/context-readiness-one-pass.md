# Verification -- context-readiness-one-pass

The context-readiness SessionStart hook reads every spec in one awk pass instead of two greps per file, with byte-identical output (SPEC-354).

## Green run

The real primary flow: the hook run through `hooks/anchor-root.sh` with a SessionStart payload, as Claude Code runs it, in the dwarves-kit checkout (267 specs).

```
Command: echo '{"session_id":"t","hook_event_name":"SessionStart","source":"startup","cwd":"<dwarves-kit>"}' | CLAUDE_PLUGIN_ROOT=<wt> CLAUDE_PROJECT_DIR=<dwarves-kit> bash <wt>/hooks/anchor-root.sh <hook>
Exit: 0 (old hook, 2.84s) / 0 (new hook, 0.63s)
Verdict: stdout identical (cmp clean)
```

Output equivalence across 11 cases: ops-toolkit, dotfiles, dwarves-kit, an empty non-git dir, and a fixture repo on branches main, feat/gateway, fix/db-migrate, feat/api-auth, feat/gate-check, chore/a, plus a single-live-spec case. The fixture holds a lowercase `status:` line, a late `Status: parked` line, a spec with no Status, and an empty spec.

```
Command: diff -r <baseline outputs from the pre-change hook> <outputs from the new hook>
Exit: 0
Verdict: ALL 11 IDENTICAL
```

Timing, best of three, hook run directly in each checkout:

| Repo | Old | New |
|---|---|---|
| dwarves-kit (267 specs) | 2.147s | 0.357s |
| ops-toolkit (33 specs) | 0.380s | 0.306s |
| dotfiles (0 specs) | 0.092s | 0.084s |

Suite:

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: All tests passed.
```

## Negative control

```
Command: bash lib/gate/negctl.sh . 'bash tests/test-hooks.sh >/dev/null 2>&1; r=$?; git checkout -- _meta/BACKLOG.md 2>/dev/null; exit $r' "sed -i '' 's/l = tolower(\$0)/l = \$0/' hooks/context-readiness.sh"
Exit: 0 green before, 1 under mutation, 0 after restore
Verdict: PASS
```

The mutation stopped the awk pass from case-folding, so the lowercase `status:` spec dropped out and the new edge assertion failed. negctl restored the file with `git checkout HEAD -- hooks/context-readiness.sh`.

A second control, run on commit 112bb82a, removed the readable-file filter (`[ -f "$F" ] && [ -r "$F" ] && `):

```
Command: bash lib/gate/negctl.sh . '<same test command>' "perl -pi -e 's/\[ -f \"\$F\" \] && \[ -r \"\$F\" \] && //' hooks/context-readiness.sh"
Exit: 0 green before, 1 under mutation, 0 after restore
Verdict: PASS
```

Without the filter, the dangling link in the edge fixture made awk abort, and the assertion failed. The review lens found this regression in the first commit (33d543c5). Commit 112bb82a fixes it. The case-folding control was re-run on 112bb82a and also passed.

## Not proven

- Timing under heavy load. Fewer spawns should help most there, but these runs were on a lightly loaded Mini.
- `git status` and the `find` source count, unchanged and about 160ms together in ops-toolkit.
- The test command restores `_meta/BACKLOG.md` because `tests/test-hooks.sh` writes rows into the real board. That behavior predates this change.
