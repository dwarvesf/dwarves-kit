# Implementation notes: sync adapters (SPEC-429)

Warnings from the spec validation that the build's own tests would catch or that need a builder's judgment. The spec holds the contract; this file holds the hints. Delta only.

## Before you start

- Retake the baselines of the spec's Test plan on the branch base (`bash tests/test-sync.sh` and the bash suites named there) and write the numbers here. Counts on master drift; the spec's numbers come from `3eb93852`.
- Each phase starts with `git fetch -q origin master && git merge --no-edit origin/master`. The state-check change (branch `feat/state-check-engine`) adds `state-check)` and `BOARD_STATE_CHECK_PY` beside `mirror-cleanup)` in `lib/board/board.sh`, usage-header lines, and lines 14 to 16 of `lib/board/README.md`; `docs/reference/FEATURES.md` also changes on both sides, so regenerate it after the merge instead of resolving it by hand.
- The state files, the intake heading and every `[sync]` key must not change shape. When a golden diff shows something that is not in `deltas.txt`, the code is wrong, not the golden.

## Facts the validator found that the tasks rely on

- `board-sync-all` (ops-toolkit) always passes `--mirror-hermes-home` and `--mirror-snapshot`; only `--expire-kinds-file` is gated on `board sweep --help`. A kit with no hermes adapter therefore fails that wrapper with exit 64 by design.
- `board-health record --leg` accepts `sync` and `mirror` only; the runner records a missing leg only when its name is `mirror`.
- `cmd_sync` reads `multica_token_ref` and calls `secret-cache-read` or `op read` on every sync whose operator config sets the ref, whether or not Multica is a named app. Keep that; narrowing it is a follow-up.
- The legacy Reminders copy today runs on every sync whatever `--apps` says; the spec moves it into the Reminders `build`, so it runs only when Reminders is named. `~/.cache/backlog-reminders-sync` does not exist on this host.
- `board-hermes` does `sys.path.insert(0, HERE)` and `import sweep_modules`; after the move `HERE` is `lib/adapters/hermes`, so insert `KIT_LIB/sync/sweep` instead. The other self-location lines are listed in TASK-M1.
- `_iso_to_utc_z` and `MEGA_SH` are used by `cmd_status` and are not in the helper list the draft named; find the full closure with `rg` over `cmd_mirror`, `cmd_status` and `cmd_writeback`.
- `bin/board`'s `*)` fall-through is the hot path for `next`, `get`, `set` and `add`. Run `adapters_verb` only for a first word that is not a core verb, and time `board next` before and after (the lookup should add a few milliseconds, not a process per manifest).
- Filter keys for a hyphenated app use underscores in the config key and keep the hyphen in the filter token (`notion_taskboard_only_tags` becomes `--filter notion-taskboard:only_tags=...`).
- `HermesSource` is the only source that takes `body_expander`; `ctx.hooks.get("body_expander")` is `None` when no adapter declares the hook, and a declared hook that fails to import must exit non-zero.
- `sync_core` is imported by `board_add.py`, `backlog.sh`, `bin/add-backlog` and `lib/reflect/staging-format.py`; `insert_inbox_rows` and `plan_create_only` gain optional parameters only.
- Leftover ignored `__pycache__` directories under `lib/sync/sources/`, `lib/sync/tests/` and `lib/sync/sweep/` hold app names. Scan tracked files (`git grep`, `git ls-files`); do not delete them as part of the change.

## Warnings not folded into the spec

- A project `.claude/settings.json` `env` block or a direnv file can set `KIT_ADAPTERS_DIR` in a repo the operator syncs. The variable has the trust of `PATH`; the README says so. Not hardened.
- `hermes_target` and `hermes_home` are read from project files (DEC-M). The Hermes spoke turns them into an ssh or sudo target. Unchanged.
- The Multica URL accepts any scheme and sends the bearer token over `http://` if the operator configures it. Unchanged; a follow-up if wanted.
- A manifest `help` string with a `%` is doubled by the loader; keep help text plain.
- `board-brief` and `board-health` still own a "mirror target" reader (two kanban commands and the `origin: <repo>:<id>` marker). The Hermes shape is named in `lib/adapters/README.md`; a second mirror target must satisfy it.

## Round 2 warnings left to the builder

- Leg signals: a background child of a non-interactive bash ignores SIGINT; prove the chosen way (job control or an equivalent) with a test that sends both INT and TERM.
- A `sweep-opt` flag with no `leg` row to consume it passes the unknown-arg check and runs nothing; the golden catches it on the fixture only.
- A kit merge into the live checkout is not atomic: a tick that started on old code can call a verb after the files moved. One mixed tick is possible; the post-merge gate waits for a tick that started after the merge.
- Between TASK-C and TASK-I the engine knows apps through the registry and the legacy chain. Test names that patch `backlog_sync.NotionTaskBoardSource` and similar must patch the adapter module attribute after TASK-H.

## Rejected during validation (do not re-add)

A config key for the adapter directory; a colon list of directories; a package per adapter; a wrapper over `python3` for the bash reader; a stderr line for every unknown first word in `board`; reading the Multica secret only for named apps; requiring `https` for the Multica URL.

## Baselines retaken on the branch base (phase 1, before any change)

Taken on this host after merging `origin/master` (a19ca13d), each suite alone, in the foreground. They equal the spec's Test plan numbers, so none moved on master.

| Suite | Result line |
|---|---|
| `tests/test-sync.sh` | `326 passed` |
| `tests/test-sync-dispatch.sh` | `=== 10/10 passed ===` |
| `tests/test-board-states.sh` | 32 `PASS` lines, `All board-states tests passed.` |
| `tests/test-board-hermes.sh` | `79 passed, 0 failed` |
| `tests/test-board-mirror.sh` | `TOTAL: 116   PASS: 116   FAIL: 0   SKIP: 0` |
| `tests/test-board-writeback.sh` | `TOTAL: 75   PASS: 74   FAIL: 0   SKIP: 1` |
| `tests/test-board-mirror-cleanup.sh` | `TOTAL: 31   PASS: 31   FAIL: 0` |
| `tests/test-board-mirror-expire.sh` | `TOTAL: 31   PASS: 31   FAIL: 0` |
| `tests/test-board-sweep.sh` | `PASS=55 FAIL=0` |
| `tests/test-board-sweep-mirror.sh` | `PASS=43 FAIL=0` |
| `tests/test-board-sweep-expire.sh` | `TOTAL: 14   PASS: 14   FAIL: 0` |
| `tests/test-board-health.sh` | `97 passed, 0 failed` |
| `tests/test-board-brief.sh` | `243 passed, 0 failed` |

## Characterization harness (TASK-A1, TASK-A2): what the next builder must know

- Run it with `bash tests/test-sync-characterize.sh`. A red section prints its name and a unified diff. `CHARACTERIZE_UPDATE=1` rewrites `golden.txt`; use it only in the task that causes a stated delta, and add the `<section><TAB><tag>` row to `deltas.txt` in the same commit. `CHARACTERIZE_KIT=<dir>` runs the entry points of a copy of the tree (needs `bin` and `lib`), which is how the negative controls mutate a temp copy. `CHARACTERIZE_PYTHON=<python3>` picks the interpreter; the golden holds on 3.12 and 3.15 (the engine does not import on `/usr/bin/python3` 3.9, today's floor).
- Every entry point runs under `env -i` with a scratch `HOME`, scratch data and config roots, and PATH stubs. The stubs live in the scratch `$HOME/.local/bin` because `board-sweep` puts that directory first on its own PATH. The transport guard is a `sitecustomize.py` on `PYTHONPATH` (subprocess of a transport program outside the stub dir, or a non-loopback socket, raises and logs) plus a PATH resolution check and an absolute-path grep over `lib/board lib/sync lib/config bin`.
- Sections are named `## <n>-<name>`, with `### <case>` sub-sections, so a red diff names the section and the app or case. The numbering follows the spec: 1 sync argv, 2 engine flags, 3 engine dry run per app, 4 sweep, 5 health and brief (including both `--help` outputs, for the `health-brief-help` tag), 6 bridge verbs, 7 help and errors.
- The golden argv of section 1 is normalized as the spec says: `--apps` first, config-derived flag pairs sorted, `--filter` pairs sorted, caller flags last in their own order. Values are JSON-quoted so an empty `--notion-taskboard-db ""` stays visible.
- Section 3 builds its `Namespace` with both the legacy engine dest names and the config key names (`list_name` and `reminders_list`), because phase 2 renames dests to the config keys. Keep both when the engine changes.
