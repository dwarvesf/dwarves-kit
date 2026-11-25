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
- The golden carries the operator's repo name as `ops-<NAME>` (a normalization in the suite). `board help` prints it and `lib/gate/boundary-lint.sh` scans fixture text for it, so the raw text failed the lint; A2 added the normalization and regenerated section 7 (three lines, no behavior).
- Section 4 stubs the board command (`--board-cmd`) with its own canned sync lines (not `tests/fixtures/board-sweep/sync-output.txt`, so the digest prints `WARN parse-degraded`), so it pins the sweep's own legs and log text, not `board mirror` itself; section 6 pins the verbs. Section 4 also has a case the spec did not list: the legs plus `--poster` and `--health --health-force`, which pins the digest and health legs' log lines. The sweep fixture has one `bridge=on` repo with a local bare origin, because the mirror leg runs `git fetch`.
- Section 5 drives `board health` and `board brief` with `--now`, so the payloads are deterministic. `--help` of `health`, `brief`, `health run`, `brief run` and `hermes link` are in the golden, which is where the `health-brief-help` hunks will show.
- Section 6 includes `board status --with-mega` and `board board --with-mega` over a mega fixture lifted from `tests/test-mega.sh` (the gh calls are stubbed through `GH_BIN`), so TASK-L diffs against a recorded before.
- The negative controls run on temp copies or with a restored file: `CHARACTERIZE_KIT=<copy>` for the `--hermes-home` mutation of `cmd_sync`; removing one canned issue from the GitHub fake makes `FAIL section 3-engine-dry-run differs from the golden in: github`.
- Section 7 runs the engine with no `--apps` only with `--dry-run`, a scratch `--state-root` and the `osascript` stub, because today's default is a live Reminders sync. After TASK-C the default is gone and that case becomes the `apps-default` delta.
- The entry points run under bash 3.2: the pinned PATH resolves `env bash` to `/bin/bash`, and both new suites also ran under `/bin/bash` directly. Section 4's health case and section 6's cleanup case read the real clock, and two same-day runs do not prove day stability; a red section 4 or 6 with no code change means a clock leak in the harness, not a delta.
- The `describe-line` hunk (TASK-G) is visible in section 3 under `notion-taskboard`: row ID-6 carries a `notion-page:` marker.

## The loader and the bash reader (TASK-B): what the next builder must know

- `lib/sync/adapters.py` and `lib/sync/adapters.sh` are not wired into the engine, `board.sh` or the sweep yet; the golden is byte identical after TASK-B. `adapters.sh` keeps the grammar in one awk program (`_adapters_awk_program`) and `adapters.py` mirrors it check for check, in the same order, with the same message text; `lib/adapters/tests/test-adapters.sh` feeds 38 bad manifests to both and compares the lines. Change a rule in both files or the suite goes red.
- Message shapes the spec left open (the suite pins them): `<kind> needs N fields` or `needs at least N fields` (counted after the kind), `empty field`, `bad <thing> '<x>'`, `reserved ENV name` and `reserved ENV prefix '<p>' in '<x>'`, `duplicate <app|flag|key|ENV|verb|const|hook|sweep flag> '<x>' (also in <file>:<line>)`, `bad adapter directory name '<x>'` (reported at line 1), `adapter.py is missing` or `is a symlink` (reported at the first `app` or `hook` row), and the secret-beside-host-key rule (reported at the `opt` row). `key` is one namespace for `opt` and `secret` rows; `ENV` is one namespace for `secret` and `sweep-opt` rows.
- `adapters.sh` has no `adapters_const`: nothing in bash reads a constant (the engine, health and brief are Python), so the module suite compares `adapters_rows const` and the Python `Registry.const` is covered in `test_adapters.py`.
- A bad adapter directory name is reported after every earlier adapter parsed cleanly, in both readers, so the first error in name order wins in both.
- The core lists live once, in `adapters.sh` (`CORE_VERBS`, `ADAPTERS_ENGINE_FLAGS`, `ADAPTERS_SWEEP_FLAGS`); `adapters.py` reads them from that file's text. The engine and sweep lists exclude what moves out later (the `--list`, `--notion-*`, `--hermes-*`, `--multica-*`, `--github-repo` flags and the three sweep leg flags). `test-adapters.sh` compares them with the argparse calls in `backlog_sync.py` and the case labels of `board-sweep`; once the engine builds its parser from manifests (TASK-C onward) keep the comparison pointed at the flags that stay core.
- `CORE_VERBS` equality has an interim exclusion: the five bridge verbs (`mirror`, `status`, `writeback`, `mirror-cleanup`, `hermes`) are still `main()` labels until TASK-M3 moves them behind the manifest, so the test removes them from the expected set. `state-check` is not a `main()` label on this base; when that change lands the equality test goes red until `state-check` is added to `CORE_VERBS` (the intended reminder).
- `Registry` has two helpers the spec did not name: `rows(kind)` and `verb(name)` (the bash-parity surface the module suite compares), and `HookFailure` (a `SystemExit` subclass with `.adapter`, `.hook`, `.exc`) so the brief can turn a failed provider into its attention line without parsing the message. `Registry.build` fills `opts` with every opt key (None when absent) and gives `ctx` a `hooks` view when the caller supplied none; the mode check against the manifest stays the engine's job (TASK-C).
- A failed import of an adapter module in `Registry.build` exits 1 with `adapters: <name>: import failed: <ExceptionClass>: <message>`; the spec named only the hook form.
- `lib/adapters/tests/test-adapters.sh` runs `pytest lib/adapters/tests` and accepts exit 5 (no tests yet); `lib/sync/tests/test_adapters.py` (28 tests) runs under `tests/test-sync.sh`, so that suite now reports 354 passed (326 baseline plus 28). The fixture adapter is `lib/sync/tests/fixtures/adapters/fake/`; its `build` and hooks are stubs that TASK-C extends for the engine tests.
- `lib/adapters/README.md` states the whole contract, including parts that land in later tasks (legs, the conformance test, `lib/adapters/docs/`); reword anything that is still false when the last task lands.
- Decisions on the run itself: the rules file's push and PR steps and the spec's phase-end `run-all --changed` were overridden by the phase 1 brief (no push, no PR, no `run-all`); the phase 1 check ran suite by suite.

## Phase 2 start: the state-check merge (builder 2)

- The state-check change (`origin/feat/state-check-engine`) was merged into the branch after `origin/master`; `state-check)` and `BOARD_STATE_CHECK_PY` are in `board.sh`, so the spec's "the state-check change has landed" branch is true for every later task. The only conflict was the generated `docs/reference/FEATURES.md`; resolved by taking this side and running `bash lib/registry/feature-registry.sh generate` (`check` reports fresh).
- The merge changed two phase 1 artifacts, neither by a task: the `board help` text of golden section `7-help-errors` gained exactly the nine `state-check` usage lines (no tag in the closed list covers an upstream change, so the commit `rebase golden and core verbs onto state-check lines` rebases the golden once, with no `deltas.txt` row), and the module suite's `CORE_VERBS` equality went red as phase 1 predicted, so `state-check` joined `CORE_VERBS` in `lib/sync/adapters.sh`. TASK-S step 5 (`git diff <A2 commit> HEAD -- golden.txt`) therefore sees that one nine-line hunk with no row: diff against the rebase commit instead, or accept that hunk as the base change.
- `CHARACTERIZE_UPDATE=1` rewrites the whole golden; always read `git diff` of it afterwards and confirm it holds only the hunk the task causes.

## TASK-G (bound marker)

- `plan_create_only(..., bound_re=None)`; `sync_create_only` passes `getattr(src, "bound_marker_re", None)`; `NotionTaskBoardSource.bound_marker_re` is the compiled `notion-page:([0-9a-f]{32})`. `PULL_MARKER_RE` and `bound_page_id` are gone from `sync_core`.
- Golden delta: section `3-engine-dry-run`, tag `describe-line`, one line (the `notion-taskboard` adopted row). Recorded in `deltas.txt`.
- Test names unchanged: the three marker planning tests in `test_notion_taskboard.py` now pass `bound_re=PULL_MARKER_RE` (a module constant bound to the source's attribute); three new tests in `test_core.py` use a fake `fake-id:` marker. `tests/test-sync.sh` reports 357 passed (354 plus 3).

## TASK-L (board-lib.sh)

- Moved verbatim into `lib/board/board-lib.sh`: the `OPT_*` defaults and `POSITIONAL`, `_parse_flags`, `_mega_rollups`, `_default_repo_root`, `_resolve_repo_root`, `_repo_root_for`, `_iso_to_utc_z`, plus `MEGA_SH` (now `$KIT_LIB/mega/mega.sh`) and the `box.sh` source. The helper closure of the three bridge functions was exactly that set; `_behind_count`, `_stale_marker` and `_stale_trailer` stay in `board.sh` (only `cmd_all` uses them).
- `board.sh` computes `KIT_LIB="$(cd "$BOARD_DIR/.." && pwd)"` and exports it unconditionally, so an inherited value is ignored. `board-lib.sh` fails with a message when `KIT_LIB` is unset. The file is mode 644 (sourced, like `work.sh`).
- Proof the diff is a move: every removed `board.sh` line other than the `MEGA_SH` and `box.sh` lines exists in `board-lib.sh` (`comm -23` of the sorted lines prints only those two).

## TASK-C (engine and `cmd_sync` on the registry): what the next builder must know

- `backlog_sync.main()` calls `adapters.load()` first (a manifest error stops the run), adds one argparse flag per `opt` row with `dest=<key>`, and has no `--apps` default: absent or empty prints `backlog_sync: no apps (--apps)` to stderr and exits 2. Order after the filter parse: guards of adapters that provide a named app (`reg.hooks("guard", only=names)`), `check_pull_isolation(names, args, filters, reg)`, the unknown-app exit `no adapter provides <app> (searched: <dir>)` (a name in `LEGACY_APPS` stays known), then backlog check, worktree fence, archive, lock, as before.
- `LEGACY_APPS`, `CREATE_ONLY_APPS` and `PULL_ONLY_APPS` stay as module sets until TASK-I deletes them; the engine uses `LEGACY | registry` everywhere (`check_pull_isolation` and `strict_id`). Each moving task (D to I) deletes its app from `LEGACY_APPS`, from the legacy sets where it sits, from the if-chain and from the argparse lines.
- `build_source(name, args, reg=None, state_path=None)`: the registry answers first; the source object's mode is checked against the manifest (`adapters: <app>: the manifest says <mode> but the source object is <mode>`); `None` from an adapter is a skip and `main` continues. The opts handed to `build` are `{o.key: getattr(args, o.key, None)}` for every `opt` row, so a hand-built `Namespace` in a test needs only the attributes it cares about. `check_pull_isolation` keeps its three-argument form (the registry is loaded when not passed).
- The legacy dest names are still `list_name` (Reminders `--list`) and the rest of the old flags; TASK-D renames the Reminders dest to `reminders_list` through its `opt` row, which is why golden section 3 builds its namespace with both names.
- `cmd_sync` sources `lib/sync/adapters.sh` itself (not at the top of `board.sh`), then adds, after the legacy per-app lines: the filter keys per `app` row (`<app with - as _>_<fk>`; two-way gets `only_tags skip_tags intake`, create-only the first two, pull-only none), one `--<flag> <value>` per `opt` row (scope `root` reads `kit_config_get_root` and prints the shadow note), and one exported env var per `secret` row (root-only ref, `secret-cache-read --ttl 21600` first, `op read` as the fallback, skipped when the variable is already non-empty). A manifest error exits 1 (loud). The Multica block and every other legacy line are untouched, so with no adapter present nothing new runs.
- Golden deltas recorded in `deltas.txt`: `apps-hint` (section 1, two hunks, so two identical rows), `unknown-app` (sections 3 and 7), `apps-default` (section 7). The rows are one per hunk; a repeated row is intentional. Section 3 prints `searched: <KIT>/lib/adapters` (the harness normalizes the kit path).
- Tests: 15 engine tests in `test_core.py` over the fixture adapter (`KIT_ADAPTERS_DIR` via a `fake_adapters` fixture that restores `sys.path` and drops `kit_adapter_*` modules), `tests/test-sync.sh` now 372 passed (357 plus 15); `tests/test-sync-dispatch.sh` 18 of 18 (8 new cases over the fixture adapter, including a secret that must reach the stub engine by environment only). The dispatch stub `python3` now also prints `FAKE_TOKEN:<set or empty>`.
- Negative controls run and restored: guards run for every adapter (the `only=names` argument dropped): `FAILED test_a_guard_checks_only_runs_that_name_one_of_its_apps`; mode check removed: `FAILED test_a_manifest_mode_must_match_the_source_object`; unknown-app exit disabled: `FAILED test_unknown_app_exits_before_the_lock_and_syncs_nothing`; secret copied into argv: dispatch case `a secret row reaches the engine by environment only, never argv` FAIL; create-only given `intake`: dispatch case `filter keys follow the app mode` FAIL.

## TASK-D (Reminders adapter): what the next builder must know

- The adapter directory holds `reminders.py` (the spoke, unchanged) beside `adapter.py`; the sibling stem is `reminders`, and `test_reminders.py` imports it as `import reminders` (two import lines changed, the `sys.path` line is gone: `lib/adapters/tests/conftest.py` supplies the paths). A moved adapter test file in a later task follows the same shape: `from sources.x import` becomes `from x import`.
- `tests/test-sync.sh` runs two pytest roots, `lib/sync/tests` and `lib/adapters/tests` (380 passed: 372 plus 8 in `test_conformance.py`). Test file basenames must stay unique across the two roots (pytest prepend mode).
- The legacy state copy is `_migrate_legacy_state` in the adapter; the legacy path is read at call time (`Path.home()`), so a test sets `HOME` and nothing else. `ctx.state_path` of `None` skips it (a hand-built call). It runs inside `build`, so a multi-app run prints the line when `reminders` is built, not before the first app.
- `test_conformance.py`: the registry is the real `lib/adapters` (the test removes `KIT_ADAPTERS_DIR`), apps are parametrized at collection, the autouse guard also patches `Popen`, so the two fresh-interpreter checks go through `fresh_interpreter()` which restores the real `Popen` for that one call. Opts are `fixture-<key>` strings over an optional `fixture-opts.json` in the adapter directory. `sync_fields` is asserted as a bool only when present. The legacy-copy cases (T8) live in this file; the "another app named" case runs `backlog_sync.main` over a temp adapter directory that symlinks the real `reminders` directory beside the fixture adapter, with `kit_data.path` stubbed (it shells out to `data-path.sh`, which the guard refuses).
- The module suite's decoy and "no kit.toml key selects the directory" cases asserted an empty row list, which was true only while the real directory was empty. They now compare with a run from a neutral cwd (`base_py`, `base_sh`), so a loaded decoy still shows as an extra row. Expect the same edit to be unneeded in later tasks.
- Golden: no change, no delta row. Negative control: with the `target.exists()` check dropped from `_migrate_legacy_state`, `FAILED lib/adapters/tests/test_conformance.py::test_legacy_reminders_state_is_copied_once_and_only_when_named` (379 passed, 1 failed); restored.

## TASK-E (GitHub adapter)

- Same shape as Reminders: `github.py` beside `adapter.py`, `test_github.py` imports `from github import GitHubSource`. The two comments naming other apps in `github.py` are reworded (no other change).
- The golden never sees the `cwd` the adapter hands to `gh` (it replaces the runner), so a new case in `test_conformance.py` (`test_github_takes_its_repo_from_the_flag_and_its_cwd_from_the_project_root`) goes through `build_source` with `KIT_PROJECT_ROOT`. Negative control: `cwd=None` in `adapter.py` gives `FAILED ...test_github_takes_its_repo_from_the_flag_and_its_cwd_from_the_project_root` (383 passed, 1 failed); restored. The characterization suite stayed green under the same mutation, which is why the case exists.
- `tests/test-board-states.sh` line 52 now puts `../adapters/github` on `sys.path` (the script runs from `lib/sync`) and imports `github as g`; the `sources.hermes` import there stays until the Hermes task.
- `tests/test-sync.sh` reports 384 passed (380 plus 3 conformance cases for `github` plus the cwd case).

## TASK-F (Multica adapter)

- `cmd_sync` has no Multica line left: the url (root scope), workspace, project, the token block and the filter keys all come from `adapters/multica/adapter.tsv`. The shadow notes now print from the manifest loops, so they come after the legacy per-app lines instead of in the middle of them (stderr order only; the dispatch suite pins the text).
- The `secret` loop reads `multica_token_ref` on every `board sync` that finds the adapter, named or not, as before. With no multica adapter installed it reads nothing.
- Dispatch (T10): the stub `python3` also prints `MULTICA_TOKEN:<set or empty>`; two new cases (project-only ref leaves it unset; operator ref sets it and `stub-token` is absent from the printed argv). 20 of 20. Negative control: `args+=(--leak "$rval")` after the export in the secret loop gives `FAIL with the operator ref MULTICA_TOKEN reaches the engine by environment, never argv` and the fixture-secret case fails the same way; restored.
- `tests/test-sync.sh` reports 387 passed (384 plus 3 conformance cases for `multica`, which set `MULTICA_TOKEN=fixture` inside the test only).

## TASK-N (neutral wording, inbox heading)

- `sync_core.INBOX_HEADING` is now the neutral default `### Intake inbox`; `apply_board(..., heading=INBOX_HEADING)` and `insert_inbox_rows(..., heading=INBOX_HEADING)` take it as an optional parameter. The engine passes `reg.const("inbox-heading", INBOX_HEADING)` into `sync_source` and `sync_pull_only` (both gained an optional `heading`), and the Reminders manifest carries `const inbox-heading ### Reminders inbox`.
- The loader rejects a `const` name declared by two adapters, so two adapters can never both supply the heading (the fixture adapter's `### Fixture inbox` clashed with the Reminders row in the T8 "another app" case; that case now runs over a probe adapter that declares no const).
- T7 is split by the purity rule (no app word may stay under `lib/sync`): the neutral cases live in `lib/sync/tests/test_core.py` over a temp probe adapter (a pull-only app, with or without a `const inbox-heading` row), and the cases with the real Reminders adapter live in `lib/adapters/tests/test_conformance.py`. Negative control: with the `const` row removed from `lib/adapters/reminders/adapter.tsv`, `FAILED ...test_the_reminders_adapter_supplies_the_intake_heading` and `FAILED ...test_an_existing_reminders_section_keeps_receiving_rows` (389 passed, 2 failed); restored. The second case first passed wrongly (the new section landed after the old one); it now asserts the new row sits inside the existing section.
- `test_core.py` and `test_cockpit.py` hold no app word any more (checked with `git grep -i`): sample names are `spoke-a` and `spoke-b`; two engine tests that named a real app now run over the fixture adapter (`fake-two`, through the `fake_adapters` fixture). `test_apply_board_add_inbox_section_and_status` and the intake test in `test_notion_taskboard_pull.py` assert the new default heading (that file moves in TASK-H, and the assertion stays `### Intake inbox` there since it calls `sync_pull_only` with no heading).
- The comments in `sync_core.py` and `cockpit.py` lost their app words (comment text only; two cockpit comments point at "the adapter that creates cards" and "the intake adapter" until the adapters' README text names them).
- `tests/test-sync.sh` reports 391 passed. Golden: unchanged, no delta row.
- What phase 4 must know: `backlog_sync.py` still names `hermes` and the Notion apps in `LEGACY_APPS`, the legacy sets and the if-chain; `lib/sync/tests/test_notion_taskboard_pull.py` and `test_hermes.py` etc. still hold app words until H and I move them.
