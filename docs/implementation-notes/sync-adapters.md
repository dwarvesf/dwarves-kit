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
