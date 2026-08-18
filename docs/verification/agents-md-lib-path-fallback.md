# Proof of done: AGENTS.md lib/ path fallback (fixes #401)

## Claim

`AGENTS.md`'s command snippets (`bash lib/...`) resolve correctly in a
consumer repo that was scaffolded WITHOUT a full `/kit:adopt` (kit run
as a global Claude Code plugin only, no local `lib/` copied in), by
falling back to `${DWARVES_KIT:-$HOME/.claude/dwarves-kit}`.

## Test repo

`/Users/hieutieutu/workspace/prohome/projects` — has `AGENTS.md`
(copied verbatim from this kit) but no local `lib/`, `hooks/`, or
`bin/` (plugin-only scaffold, adopt intentionally skipped).

## Negative control (RED — before fix, bare repo-relative form)

```
$ cd /Users/hieutieutu/workspace/prohome/projects
$ bash lib/gate/gate-ledger.sh rid
bash: lib/gate/gate-ledger.sh: No such file or directory
Exit: 127
```

Confirms the pre-fix snippet form is broken in this environment —
exactly the bug reported in #401.

## Green run (after fix — DWARVES_KIT fallback form)

```
$ cd /Users/hieutieutu/workspace/prohome/projects
$ bash "${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-ledger.sh" rid
construction-project-tracking
Exit: 0
```

Same command, same repo, same missing local `lib/` — resolves via the
global kit install and returns the correct rid.

## Verdict: PASS

Command: `bash "${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-ledger.sh" rid`
Exit: 0
Rollback: revert `AGENTS.md` to the pre-fix commit; bare `bash lib/gate/gate-ledger.sh rid` reproduces the RED case above.

All 11 patched snippets in `AGENTS.md` follow the identical
substitution (`bash lib/X.sh` → `bash "${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/lib/X.sh"`),
verified by `grep -c 'bash lib/' AGENTS.md` returning 0 post-patch.
