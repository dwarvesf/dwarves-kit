# Verification -- codex repin verb

`lib/codex/repin.sh` re-pins the trust hashes in `hooks/codex-hooks.json` after a hook file changes, so a Codex session sees the current hook bodies as trusted instead of refusing them. The verb was authored on a local `master` and landed here by cherry-pick with the `docs(wrap)` commit that sat beside it.

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | The verb recomputes every pin and rewrites only the pin fields | `tests/test-codex-hooks.sh`, the repin block | PASS |
| AC2 | A hook file whose pin already matches is left untouched | same suite | PASS |
| AC3 | The rest of the codex hook suite still passes beside the new verb | `bash tests/test-codex-hooks.sh`: 94 passed, 0 failed | PASS |
| NEGATIVE CONTROL | Removing `lib/codex/repin.sh` turns the suite red; restoring it turns it green | `lib/gate/negctl.sh` run below | PASS |

## Runs

Green run, worktree at the cherry-picked head:

```
bash tests/test-codex-hooks.sh
94 passed, 0 failed
```

Negative control (`bash lib/gate/negctl.sh <root> "bash tests/test-codex-hooks.sh" "mv -f lib/codex/repin.sh lib/codex/repin.sh.negctl"`):

```
Mutation: mv -f lib/codex/repin.sh lib/codex/repin.sh.negctl
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/codex/repin.sh
Exit: 0 (green after restore)
```

The tool's own verdict line reported a tree delta after restore: the mutation's `.negctl` leftover, moved out by hand. The red-then-green pair is the control.

Reproduce: `bash tests/test-codex-hooks.sh` from the repo root.

## Not covered

`tests/run-all.sh --changed origin/master` reports `test-config-registry` and `test-loop-engineering-contract` red. Both are red on a clean `origin/master` with none of these commits applied, so they are outside this change; a separate fix branch owns them.
