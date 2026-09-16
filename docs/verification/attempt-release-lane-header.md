# Verification -- attempt-release-lane-header

Spec: `docs/specs/SPEC-293-attempt-release-lane-header.md`. Run id: `attempt-release-lane-header`.
Lane: full.

Two behavioral claims. `commands/dispatch.md` Step 6 releases a settled task's attempt record.
`hooks/ship-gate.sh` parses the markdown-bold `Lane:` header shapes beside the plain one.

## Green run

```
Command: bash tests/test-ship-gate-fail-closed.sh
Exit: 0
Verdict: PASS
```

| Case | What it pins |
|---|---|
| 1 | spec with no lane header, adopted repo: still BLOCKED (exit 2) |
| 2 | `Lane: full` parses, gates recorded, push passes |
| 3 | `**Lane**: full` parses the same |
| 4 | `**Lane:** full` parses the same |
| 5 | spec with no lane, not adopted: fail open |
| 6 | no spec for the slug: fail open |
| 7 | non-push command: gate not engaged |

```
Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS
```

853 of 853 pass, including the new assertion that `commands/dispatch.md` names
`attempt-state.sh release`. `tests/test-attempt-state.sh` case 21 already covered the `release`
verb itself, so no case was added there.

The whole suite, on this branch at `ed4918b`:

```
Command: bash tests/run-all.sh
Output:  run-all: 151 suites, 1 at a time, 3 serial
         run-all: all 151 suites passed, 0 skipped for missing tooling
Exit: 0
Verdict: PASS
```

The first run of the suite failed two suites, both re-pinned in the same commit:
`test-codex-hooks` pins the ship-gate content hash in `hooks/codex-hooks.json`, and `test-meta`
pins a fresh `docs/FEATURES.md`.

## Negative control

```
Command: bash lib/gate/negctl.sh <worktree> "bash <worktree>/tests/test-ship-gate-fail-closed.sh" "bash <mutate-script>"
Exit: 0
Verdict: PASS
```

negctl output:

```
Exit: 0 (green before mutation)
Mutation: put the ship-gate lane parser back to the plain-only '^Lane:' expression
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation reverts the grep to `^Lane:` only. Both bold-header cases go red, which is the
BLOCKED push this change fixes, and the suite returns green after restore.

## Not proven

- No live `/kit:dispatch` run drove Step 6. The release call is prose a lead follows; the test
  pins that the line is there, not that a lead ran it.
- `commands/ship.md` and `commands/mega.md` carry the same expression as documented shell for a
  human or agent to paste. Nothing executes them, so only `hooks/ship-gate.sh` is proven.
- The `- ` list-marker header shape is refused by design, and no test pins the refusal.
