# Verification -- session-state-root

Spec: `docs/specs/SPEC-334-session-state-root.md`. Run id: `session-state-root`. Lane: full.

Every hook entry in `hooks/hooks.json` and the root `settings.json` now runs through
`hooks/anchor-root.sh`, which cds to the repo (or worktree) root before it execs the hook.
`secrets-guard.sh` stays unanchored. `ship-gate.sh` resolves a relative embedded `cd`, and its
no-cd root, from the real invocation cwd.

## Green run

The real primary flow, end to end: a live `claude -p` session started in a repo SUBDIRECTORY
(`<repo>/.claude/handoffs`), with the kit loaded as a plugin through `--plugin-dir`, so Claude
Code itself dispatched the Stop hooks from `hooks/hooks.json`. `--setting-sources project` kept
the operator's installed (unanchored) kit hooks out of the run. The fixture repo holds
`docs/specs/SPEC-001-x.md` with `Status: DRAFT` at its root.

```
Command: cd <live-after>/.claude/handoffs && claude -p --model haiku --setting-sources project --plugin-dir <this worktree> "Reply with the single word ok."
Exit: 0
Verdict: PASS
```

| Check | Result |
|---|---|
| `<live-after>/.claude/session-state/last-state.md` (repo root) | exists |
| `<live-after>/.claude/handoffs/.claude/session-state/last-state.md` (nested copy) | absent |
| `Spec:` line in the state file | `Spec: DRAFT` (the root spec glob resolved) |

The suites:

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS (530 of 530, including the nine new wrapper-routed cases)
```

```
Command: bash tests/test-hook-anchor.sh
Exit: 0
Verdict: PASS (6 of 6: two self-check fixtures, then both real dispatch tables)
```

```
Command: bash lib/codex/repin.sh check
Exit: 0
Verdict: PASS (repin: all pins fresh in hooks/codex-hooks.json)
```

`bash tests/run-all.sh` results are in the feature commit's `## How I verified it` section and
in `## Not proven` below (two pre-existing failures, both reproduced on clean `afb52d01`).

## Negative control

The same live flow against clean `origin/master` (`afb52d01`, a scratch clone), identical
fixture and command, plugin dir pointed at the pre-fix kit:

```
Command: cd <live-before>/.claude/handoffs && claude -p --model haiku --setting-sources project --plugin-dir <clean afb52d01 clone> "Reply with the single word ok."
Exit: 0
Verdict: PASS (the bug reproduces: state nested, spec missed)
```

| Check | Result |
|---|---|
| `<live-before>/.claude/session-state/last-state.md` (repo root) | absent |
| `<live-before>/.claude/handoffs/.claude/session-state/last-state.md` (nested copy) | exists |
| `Spec:` line in the state file | `Spec: none` |

The three spec-defined controls, each through `lib/gate/negctl.sh` on committed HEAD
`901961a1`:

```
## Negative control (negctl)  NC1: the anchor's own cd
Command: bash tests/test-hooks.sh 2>&1 | grep -E "FAIL.*(subdir with content|worktree keeps own state|writer/reader pair)" && exit 1 || exit 0
Exit: 0 (green before mutation)
Mutation: printf '#!/bin/bash\nexec "$@"\n' > hooks/anchor-root.sh
Changed: hooks/anchor-root.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/anchor-root.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
## Negative control (negctl)  NC2: the bypass lint
Command: bash tests/test-hook-anchor.sh
Exit: 0 (green before mutation)
Mutation: git show afb52d01:hooks/hooks.json > hooks/hooks.json
Changed: hooks/hooks.json
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/hooks.json
Exit: 0 (green after restore)
Verdict: PASS
```

```
## Negative control (negctl)  NC3: the ship-gate fix
Command: bash tests/test-hooks.sh 2>&1 | grep -E "FAIL.*(relative cd resolves|payload cwd resolves root)" && exit 1 || exit 0
Exit: 0 (green before mutation)
Mutation: git show afb52d01:hooks/ship-gate.sh > hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Each mutation was restored by negctl; `git status --short` was empty after all three.

## Test plan coverage
| Row | Run / skip reason |
|---|---|
| 1 | tests/test-hooks.sh "subdir with content" cases; live Claude Code run above; NC1 |
| 2 | tests/test-hooks.sh "worktree keeps own state" cases; NC1 |
| 3 | tests/test-hooks.sh "outside a repo, wrapper-routed" case |
| 4 | tests/test-hooks.sh "pre-compact-backup subdir with content" cases; NC1 |
| 5 | tests/test-hooks.sh "writer/reader pair" cases; NC1 |
| 6 | tests/test-hooks.sh 6a, 6b ("relative cd resolves") and 6c ("payload cwd resolves root"); NC3 |
| 7 | tests/test-hooks.sh "smoke exec" case; hand mutation (anchor-root.sh chmod -x) turned every hooks.json entry to 126, recorded in the implementation notes |

## Not proven

- `post-compact-reinject.sh` under a real Claude Code compaction: whether its `PostToolUse`
  matcher `compact` ever fires is spec Edge Case 6, unresolved. The writer/reader pair is proven
  by direct wrapper-routed runs only.
- The `settings.json` (bash-install) path was exercised by test case 7 only (launch, no 126/127),
  not by a live session against an installed kit.
- Per-fire latency of the extra wrapper and `git rev-parse` processes is not benchmarked.
- `tests/test-no-scattered-ids.sh` fails on this branch and on clean `afb52d01` alike (2 hits in
  `lib/gate/proof-ledger.sh:293,415`, a file this branch does not touch).
- `tests/test-meta.sh` is load-sensitive: it timed out at `run-all.sh`'s 300s default ceiling
  on this branch under concurrent load, and on clean `afb52d01` too. It passes in full alone,
  with the ceiling raised, and inside the final bare `run-all.sh` run.
