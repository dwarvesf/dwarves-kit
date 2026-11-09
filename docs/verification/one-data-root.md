# Verification -- one-data-root

`lib/config/data-path.sh` is the one resolver for the kit's runtime data paths. A host with data at the old paths keeps using them; a fresh HOME gets XDG paths; `config data move` is the only thing that moves anything (spec: `docs/specs/SPEC-418-one-data-root.md`).

## Green run

The new suite, run under `env -i` with a temp HOME, a pinned operator config dir and a pinned kit root:

```
Command: bash tests/test-data-root.sh
Exit: 0
Output:
  == 1 fresh HOME: XDG layout only ==
    PASS  every entry resolves to the XDG layout on a fresh HOME
  == 5 legacy wins while it holds data ==
    PASS  harvest -> legacy
    PASS  backlog-sync (a ~/.cache path) -> legacy
    PASS  an empty dir at the new path does not hide old data
  == 7 config data move ==
    PASS  dry run changes nothing
    PASS  harvest cursor moved intact
    PASS  a rerun moves nothing
  test-data-root: 83 passed, 0 failed
Verdict: PASS
```

The lint and the clean-room install, with the narrowed write fence:

```
Command: bash tests/test-boundary-lint.sh && bash tests/test-clean-room.sh && bash tests/test-operator-pin.sh
Exit: 0
Output:
  === 36/36 passed ===
  clean-room: 75 passed, 0 failed
  operator-pin: 4 passed, 0 failed
Verdict: PASS
```

The diff-scoped run on the rebased branch, 155 suites at 4 at a time, under a host load average over 200:

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (one suite red, fixed after the run)
Output:
  run-all: --changed against 0f48463e: 74 changed files -> 155 suites (153 named, the rest always-on)
  run-all: FAILED -> test-operator-pin
  run-all: 155 suites run, 0 skipped for missing tooling
Verdict: 154 of 155 ok. test-operator-pin named tests/test-boundary-lint.sh, whose fixtures mention lib/config/; the pin was added and the suite reran green (operator-pin: 4 passed, 0 failed above).
```

An earlier run on the same tree hit the runner's 300s timeout on `test-wrap-merge` and a 5000ms timing limit on `test-lanes-data` (host load); both reran alone and passed (205s and 285s).

The real flow, on the Mini that holds the live state. Read-only: `config data` and the dry run of `config data move`, then a before and after listing of every data dir (11624 entries, 0 differences):

```
Command: bin/config data
Exit: 0
Output:
  KIND    NAME                 HOW     DATA    PATH
  state   harvest              legacy  yes     ~/.claude/dwarves-kit/state/harvest
  state   intake-sweep         legacy  yes     ~/.claude/dwarves-kit/state/intake-sweep
  state   backlog-sync         legacy  yes     ~/.cache/backlog-sync
  state   intel                legacy  yes     ~/.claude/intel
  state   hermes-links.json    legacy  yes     ~/.config/dwarves-kit/hermes-links.json
  state   skill-proposals      legacy  yes     ~/.claude/skill-proposals
  state   skill-curator        legacy  yes     ~/.claude/skill-curator
  state   money-gate.log       legacy  yes     ~/.claude/logs/money-gate.log
  cache   backlog-stage        legacy  yes     ~/.claude/dwarves-kit/state/backlog-stage
  cache   context-hints        legacy  yes     ~/.claude/dwarves-kit/state/context-hints
  cache   update-notice        legacy  yes     ~/.claude/dwarves-kit/state/update-notice
  cache   context-budget       legacy  yes     ~/.cache/claude-context-budget
  config  tool-policy.json     new     no      ~/.config/dwarves-kit/tool-policy.json
  config  board.json           new     yes     ~/.config/dwarves-kit/board.json
  config  harvest-sweep        legacy  yes     ~/.config/harvest-sweep
  state   logs                 new     yes     ~/.local/state/dwarves-kit/logs
Verdict: PASS (every entry that holds data resolves to its old path; nothing moved)
```

## Negative control

Each control was run with `lib/gate/negctl.sh` on the committed tree: the suite green, one mutation, RED, `git checkout` restore, green again.

| Mutation | Suite | Under mutation |
|---|---|---|
| old path no longer wins over the default | `test-data-root.sh` | 62 passed, 11 failed |
| an entry's own env var ignored | `test-data-root.sh` | 70 passed, 3 failed |
| the `[data] root` key ignored | `test-data-root.sh` | 69 passed, 4 failed |
| dry run of `move` really moves | `test-data-root.sh` | 70 passed, 3 failed |
| `move` copies instead of renaming | `test-data-root.sh` | 59 passed, 14 failed |
| an empty target dir hides old data | `test-data-root.sh` | 79 passed, 2 failed |
| the key beats old data again | `test-data-root.sh` | 77 passed, 4 failed |
| a relative root accepted | `test-data-root.sh` | 79 passed, 2 failed |
| boundary-lint data check disabled | `test-boundary-lint.sh` | 19 of 36 passed |
| a hook spells its old path again | `test-boundary-lint.sh` | 35 of 36 passed (live tree fails) |
| a hook writes under the old `~/.claude` state | `test-clean-room.sh` | 73 passed, 2 failed |
| `kit.toml` names the maintainer's tooling repo again | `test-clean-room.sh` | 74 passed, 1 failed |

```
Command: bash lib/gate/negctl.sh <root> "bash tests/test-data-root.sh" "<mutation: legacy rule off>"
Exit: 1 (under mutation, RED expected)
Output:
    FAIL  context-hints: legacy dir keeps being used (expected 'yes', got 'no')
    FAIL  context-hints: no new dir created beside it (expected 'no', got 'yes')
  test-data-root: 62 passed, 11 failed
Restore: git checkout HEAD -- lib/config/data-path.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- The Air. Only the Mini was read; the Air's paths follow the same table, but its live state was not inspected.
- `config data move --apply` was never run on a live host, by design. The moves are proven on temp HOMEs, on one disk. The cross-disk copy path (`.part`) is read, not run.
- A launchd job under a different environment than the shell that ran `move`: the XDG stop covers a differing value in the shell that runs it, not in a plist.
- Hook-level legacy-keeps-working is run for `context-hints`; the other hooks share the same resolver call and are covered at the resolver and by the fresh-HOME parity suites.
- Suites that set only HOME and are run by hand, outside `run-all`, still see the host's XDG dirs. The runner now unsets them for every suite; the one suite found leaking (`test-hooks`) is fixed.
