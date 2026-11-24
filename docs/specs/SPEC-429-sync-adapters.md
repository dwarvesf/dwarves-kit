# Spec: move the Hermes, Notion, Reminders and Multica connectors out of core board and sync into adapters

Generated: 2026-11-25
Status: DRAFT
Lane: full (the build edits `lib/board/`, `lib/sync/` and `lib/config/`, and adds a loader that `board sync`, `board sweep`, `board health` and `board brief` run on every call; the live hourly sweep on this host runs this checkout)
Depth: blind-spot (failure: a moved path, a renamed verb or a changed flag silently breaks a live job that no suite in this repo exercises: the hourly sweep on this host, the Notion intake tick and Hermes relay on the Mini, the daily brief, the Hermes mirror)
Type: spec-feature
Board: ID-937
File: `docs/specs/SPEC-429-sync-adapters.md`
References: `lib/sync/backlog_sync.py` (the engine: `build_source`, `check_pull_isolation`, argparse), `lib/sync/sync_core.py` (the planner; already source-agnostic apart from the lines named below), `lib/sync/sources/*.py` (the interface that already exists: a duck-typed source object), `lib/board/board.sh` (`cmd_sync`, `cmd_mirror`, `cmd_status`, `cmd_writeback`, `main`), `lib/sync/sweep/board-sweep` (the mirror, expire and link-check legs), `lib/config/modules.tsv` and `lib/config/kit-config.sh` (`kit_config_get_root`, the operator-only read used for `multica_url`), the standalone-doctrine ADR (`docs/decisions/00NN-standalone-doctrine.md`, number filled by the lead).

## Problem

Core `lib/board` and `lib/sync` name four specific apps. `grep -ril hermes lib/board lib/sync` lists 26 files today, and 40 files name at least one of Hermes, Notion, Reminders or Multica. Adding or removing an app means editing the engine, the board dispatcher and the sweep scripts. A kit install that wants none of the four still ships all of them in core paths.

The goal (board row ID-937, full lane):

- Core `lib/board` and `lib/sync` have zero references to the four apps: `grep -ril hermes lib/board lib/sync` prints nothing, and the same for notion, reminders and multica.
- Each connector sits behind one adapter interface, and adapters load by config.
- All four adapters pass the existing sync tests through the interface.
- Doctrine this follows (standalone-doctrine ADR, number filled by the lead): core names no specific app; connectors are adapters loaded by config; the kit's integration of a module is a thin shim.

The hard constraint, from the live callers below: this host runs the kit straight from the main checkout (`~/.claude/dwarves-kit` links `bin`, `lib`, `hooks`, `kit.toml` into it, and `/Users/Shared/dwarves-kit` links the same checkout for the neko-chief account). A merged move is live at once. No installed launchd job and no cron entry point may change its path or its behavior.

## Terms

- adapter: a directory `lib/adapters/<name>/` holding one connector: a manifest `adapter.tsv`, an entry module `adapter.py`, its own code, tests and README.
- manifest: `adapter.tsv`, tab separated rows that tell core which apps, flags, verbs and sweep legs the adapter provides. Core reads manifests and never names an app.
- app: a name usable in `[sync] apps` and `--apps` (`hermes`, `notion`, `notion-taskboard`, `notion-taskboard-pull`, `reminders`, `multica`, `github`). App names are frozen: they key `<app>.state.json`, the filter keys and the config keys.
- verb: a `board <verb>` word that an adapter provides (`mirror`, `status`, `writeback`, `mirror-cleanup`, `hermes`).
- leg: a script `board sweep` runs after the per-repo syncs (the Hermes mirror, the expiry and the link check).
- core: every path under `lib/board/` and `lib/sync/`. After this spec no dated record sits there (see TASK-P), so the purity check has no exemption list.

## Coupling map

Method: `grep -ril hermes lib/board lib/sync` (26 files) and `grep -rilE 'hermes|notion|reminders|multica' lib/board lib/sync` (40 files), each file then read. Counts are matching lines (H hermes, N notion, R reminders, M multica). Classes: UNIT = the whole file is one app's connector, moves as a unit; BRANCH = generic code with an app branch, needs an interface call; CMT = comment or help text only; TEST-UNIT = test of a UNIT, moves with it; TEST-CORE = a core test that uses an app name as sample data; DOC = live doc; REC = dated record; DATA = data file.

| # | File | Refs | Class | What the reference is | Disposition (task) |
|---|---|---|---|---|---|
| 1 | `lib/board/board-mirror.sh` | H65 | UNIT | Hermes kanban mirror engine | move to `lib/adapters/hermes/` (M) |
| 2 | `lib/board/board-writeback.sh` | H51 | UNIT | Hermes writeback leg | move (M) |
| 3 | `lib/board/board-mirror-cleanup.py` | H20 | UNIT | Hermes card reconcile and expiry | move (M) |
| 4 | `lib/board/native-map.tsv` | H2 | DATA | row state to Hermes card state map | move (M) |
| 5 | `lib/board/board.sh` | H37 N30 R3 M11 | BRANCH | five kinds of branch: bridge verb docs in the usage header; startup `[ -f ]` requires of the two bridge scripts; `cmd_mirror`, `cmd_status`, `cmd_writeback`; per-app flag lines and the Multica token read in `cmd_sync`; `main()` cases `mirror`, `status`, `writeback`, `mirror-cleanup`, `hermes` | generic manifest loops and one generic verb lookup (C to F, H, I, L, M) |
| 6 | `lib/board/README.md` | H2 | DOC | verb list | reword (Q) |
| 7 | `lib/sync/backlog_sync.py` | H18 N68 R12 M11 | BRANCH | eight imports from `sources/`; `CREATE_ONLY_APPS` and `PULL_ONLY_APPS`; the Notion database guard inside `check_pull_isolation`; the `build_source` if-chain; per-app argparse flags; the legacy Reminders state copy; the Notion skip-without-binding; `body_expander=expand_body` wiring Hermes to Notion | registry calls (C to I) |
| 8 | `lib/sync/sync_core.py` | H1 N6 R6 | BRANCH | `PULL_MARKER_RE` and `bound_page_id` (the Notion page marker) inside `plan_create_only`; the `describe()` line "bound to an existing Notion page"; `INBOX_HEADING = "### Reminders inbox"`; comments | `bound_re` parameter (G); neutral wording and heading (N) |
| 9 | `lib/sync/cockpit.py` | H5 N2 | CMT | module docs say the helpers serve two named adapters; the functions are generic | reword (N); file stays |
| 10 | `lib/sync/sweep/board-sweep` | H26 | BRANCH | the mirror leg (about 200 lines incl. `build_origin_mirror_registry`), the expiry leg, the link-check call, three flags, help text | generic leg runner (J) |
| 11 | `lib/sync/sweep/board-health` | H6 | BRANCH | "Hermes mirror" and "hermes mirror" in digest lines, doc text | `mirror-label` from manifest (K) |
| 12 | `lib/sync/sweep/board-brief` | H7 | BRANCH | `HM = sweep_modules.load("board-hermes")` at import, `check_links()`, "Hermes card" in drift text | `report` hook and label (K) |
| 13 | `lib/sync/sweep/board-hermes` | H34 | UNIT | `board hermes link` and `check` | move to `lib/adapters/hermes/link.py` (M) |
| 14 | `lib/sync/sweep/board-sweep-verify` | R2 | CMT | an example in a comment | reword (O) |
| 15 | `lib/sync/deploy/macos/board-sync-cron` | R1 M1 | CMT | TCC and token comments; the file is baked into plists on other hosts | reword comments only (O); path and behavior frozen |
| 16 | `lib/sync/deploy/macos/install` | R1 | CMT | usage example | reword (O) |
| 17 | `lib/sync/deploy/macos/README.md` | R2 M1 | DOC | cron notes | reword (O) |
| 18 | `lib/sync/sources/hermes.py` | H16 N1 | UNIT | Hermes kanban spoke | move (I) |
| 19 | `lib/sync/sources/multica.py` | M29 | UNIT | Multica REST spoke | move (F) |
| 20 | `lib/sync/sources/notion.py` | N10 | UNIT | two-way Notion spoke | move (H) |
| 21 | `lib/sync/sources/notion_taskboard.py` | N16 | UNIT | one-way push to a team board | move (H) |
| 22 | `lib/sync/sources/notion_taskboard_pull.py` | H3 N18 | UNIT | read-only intake, `expand_body` | move (H) |
| 23 | `lib/sync/sources/ntn.py` | N5 | UNIT | the shared `ntn` runner | move (H) |
| 24 | `lib/sync/sources/reminders.py` | R18 | UNIT | Apple Reminders spoke | move (D) |
| 25 | `lib/sync/sources/github.py` | H1 R1 | UNIT | GitHub Issues spoke; names two apps only in comments | move as a fifth adapter (E) |
| 26 to 32 | `lib/sync/tests/test_hermes.py`, `test_multica.py`, `test_notion.py`, `test_notion_taskboard.py`, `test_notion_taskboard_pull.py`, `test_ntn.py`, `test_reminders.py` | | TEST-UNIT | one suite per UNIT | move with the unit; `test_notion_taskboard_pull.py` splits (see Test plan) |
| 33 | `lib/sync/tests/test_github.py` | none | TEST-UNIT | names no app, but tests a moving unit | move (E) |
| 34 | `lib/sync/tests/test_core.py` | H12 N2 R8 | TEST-CORE | `"hermes"` and `"reminders"` as sample app names, the heading assertion | reword (N) |
| 35 | `lib/sync/tests/test_cockpit.py` | H1 | TEST-CORE | docstring | reword (N) |
| 36 | `lib/sync/README.md` | H43 N38 R11 M17 | DOC | one doc for engine and all apps | core rewrite, app text to per-adapter READMEs (Q, R) |
| 37 | `lib/sync/docs/proof-of-done.md` | H19 N34 R10 M10 | REC | dated proof records | `git mv` untouched to `lib/adapters/docs/` (P) |
| 38 to 41 | `lib/sync/docs/specs/SPEC-001` to `SPEC-004` | | REC | dated module specs, mostly about connectors | `git mv` untouched to `lib/adapters/docs/specs/` (P) |
| 42 | `lib/sync/sources/__init__.py` | none | | empty package marker | delete (the package goes away) |

Totals. 40 files name one of the four apps: 13 UNIT (12 code files and `native-map.tsv`, with `github.py` as the 13th, because it is in the 40 and moves as the fifth adapter), 7 TEST-UNIT, 6 BRANCH, 4 CMT, 2 TEST-CORE, 3 DOC, 5 REC. Moving: 13 code and data files, 8 test files, 5 dated records = 26 `git mv`, plus 1 deletion. Edited in place inside core: 15 (6 BRANCH, 4 CMT, 2 TEST-CORE, 3 DOC; `lib/sync/README.md` is a rewrite). New files: about 40 (5 manifests, 5 `adapter.py`, 5 hermes extras, 6 READMEs, 3 core helpers, tests and fixtures). Edits outside core: `kit.toml`, `lib/config/module-registry.md`, `docs/reference/project-structure.md`, `CHANGELOG.md` and the 10 suites that pin a moved path (listed in TASK-M).

`github.py` decision: it is a fifth adapter under the same interface and moves with the rest. Reasons: it already implements the same duck type, so moving it costs one file and its test; leaving it would keep a `sources/` package in core for one app and force the loader to scan two roots; and it carries the word Hermes in a comment, so it fails the literal grep as it stands. One github reference stays in core on purpose: the tail of `board capture` (reads `github.state.json`, runs `gh issue view`). It is not one of the four apps and it is listed under Not in this spec.

## Caller inventory

Method: read-only `rg -l` and `rg -n` over the fixed name list `lib/sync`, `sources/<app>`, `backlog_sync`, `sync_core`, `cockpit.py`, `board-mirror`, `board-writeback`, `board-mirror-cleanup`, `board-hermes`, `native-map`, `sweep/board-`, plus the verbs `board mirror|writeback|mirror-cleanup|hermes|sweep|health|brief|status|sync|capture|publish` and the flags `--hermes-*`, `--notion-*`, `--multica-*`, `--mirror-hermes-home`, `--mirror-snapshot`, `--expire-kinds-file`, `--health-kanban`. Roots: the kit, `lib/sync/deploy/macos/*`, `~/Library/LaunchAgents/*.plist`, `ops-toolkit`, `dotfiles`, `hermes-personal/home/scripts`, `foundation-ops`, `dwarves-kit-internal`. Backups, sessions, logs, archives and dated records were excluded.

Verdict first: no installed plist and no external script deep-links to any file this spec moves. Every live caller goes through `bin/board <verb>` with flags, or imports `sync_core` from `lib/sync`. The spec freezes those four surfaces (verbs, flags, `sync_core`, `lib/sync/deploy/macos/*`) and moves nothing a caller names by path.

Installed jobs on this host (read only):

| Job | Entry | What it calls in the kit | After this spec |
|---|---|---|---|
| `mini.sync` (hourly board stage) | `ops-toolkit/tools/mac-mini-substrate/mini-sync`, stage `board-sync-all`, then `tools/board-sync/bin/board-sync-all` | `$HOME/.claude/dwarves-kit/bin/board sweep` with `--registry --board-cmd --repo-arg --sync-token-repo --preflight --poster --on-clean --cluster-map --crit-prefix --mirror-hermes-home --mirror-snapshot --repo-root --expire-kinds-file --extra-board`; it first runs `board sweep --help \| grep -q 'Usage: board sweep'` and `grep -q -- '--expire-kinds-file'` | verb and flags stay; `board sweep --help` still prints `Usage: board sweep` and lists `--expire-kinds-file` (the flag comes from the adapter manifest, so the help text is assembled from it); no change |
| `foundation.d.notion-taskboard-pull` (every 900 s) | `foundation-ops/jobs/notion-taskboard-pull/foundation-notion-taskboard-pull` | runs a pinned kit clone (`KIT_REF` in the job's `deploy`, a commit pin, `177112be...f6da97cc` masked), never this checkout: `bin/board sync --apps notion-taskboard-pull --notion-taskboard-pull-db ... --notion-taskboard-db ""`, then `--apps hermes --filter hermes:only_tags=... --filter hermes:intake=all --filter 'hermes:intake_skip_re=...' --hermes-target --hermes-home --hermes-board --hermes-assignee --hermes-workspace`; `status-return` imports `sync_core` from `<kit>/lib/sync` and calls `bin/board set` | unaffected until the pin is bumped (Not in this spec); after a bump every flag, `--apps` name, the `sync_core.parse_board(text, prefix=)` import and `bin/board set` still work unchanged |
| `kit-weekly`, `mini.harvest-sweep` | `deploy/macos/kit-weekly`, `deploy/macos/harvest-sweep/harvest-sweep` | no board or sync call | none |
| `han.dotfiles-watcher`, `mini.field-watch` | watch paths and a `PATH` entry naming `dwarves-kit/bin` | no call into `lib/board` or `lib/sync` | none |
| per-repo `board-sync-<slug>` plist (may exist on other hosts) | `lib/sync/deploy/macos/board-sync-cron` | `bin/board sync --backlog-file` | the script path is frozen; only comments in it change (O) |
| cron | `crontab -l` prints `no crontab for tieubao` | none | none |

Other callers:

| Caller | Names | After this spec |
|---|---|---|
| kit `bin/board` | `lib/board/board.sh` | stays |
| kit `lib/board/backlog.sh`, `board_add.py`, `bin/add-backlog`, `lib/reflect/staging-format.py` | `sync_core` (`board_lock`, `parse_board`, `detect_prefix`, `history_max_id`) by import from `lib/sync` | `sync_core.py` stays at its path with those names |
| kit `lib/mega/runs-dashboard.py` | loads `lib/sync/cockpit.py` by path for `repo_root_of` | `cockpit.py` stays at its path |
| kit `lib/mega/mega.sh`, `lib/session/handoffs.sh`, `lib/gate/redteam-gate.sh` | comments naming `board-mirror.sh` or `board-writeback.sh` | comment text only; reword with TASK-M |
| kit tests | 10 suites pin a moved path (TASK-M), 2 pin sweep text (TASK-J), `test-sync.sh` runs `lib/sync/tests` (TASK-C) | edited in the task that moves the path |
| kit docs | `docs/reference/project-structure.md` (3), `lib/config/module-registry.md` (5), `docs/reference/FEATURES.md` (3, generated, keyed to suite names that do not change), `docs/reference/architecture.md` (1) | edited (Q, R); dated records left alone |
| `ops-toolkit` `tools/board-sync/bin/board-sync-all` | see `mini.sync` row | no change |
| `ops-toolkit` `tools/board-sync/bin/board-sync-brief` | `board health run`, `board brief run`, `board hermes link` | verbs and flags stay; no change |
| `ops-toolkit` `tools/board-sync/bin/board-mirror-cleanup` | `board mirror-cleanup --registry --snapshot --hermes-home --kinds-file` | verb and flags stay; no change |
| `ops-toolkit` `_meta/scripts/board-decisions.py`, `_meta/states.toml` | `lib/board/parse-board.sh`, `lib/board/backlog.sh` | both stay |
| `ops-toolkit` `.kit.toml`, `_meta/boards.txt`; `foundation-ops` `.kit.toml`; `dwarves-kit-internal` `.kit.toml` | `[sync] apps`, `hermes_*`, `notion_*`, `multica_*`, `reminders_*` keys; the `bridge` column | key names and column unchanged |
| `dotfiles` `home/dot_config/dwarves-kit/kit.toml`, `home/dot_config/board-sync-cron/env` | `[sync]` header; env sourced by `board-sync-cron` | no change |
| `foundation-ops` `fleet/kit-board/{chief-board,kanban,boards.txt}`, `fleet/hooks/hermes-chief-kit-only` | `/Users/Shared/dwarves-kit/bin/board health` and `brief` (dry runs, as the `server` account); the kanban reader contract `<cmd> boards list --json` and `<cmd> --board SLUG list --json` | stay; new directories under `lib/` keep mode 755, so `server` can read them |
| `foundation-ops` `jobs/incident-consumer/foundation-incident-consumer`; `hermes-personal` `home/scripts/incident-consumer` | comments naming `lib/sync/sources/hermes.py` and `HermesSource` | comment text goes stale; optional edit in those two repos (Not in this spec); no code imports |
| `hermes-personal` `home/scripts/board-brief.sh`, `incident-digest.py` | run ops-toolkit `board-sync-brief`; the `--incidents` hook of `board brief` | no change |

Nothing in this spec edits a plist, runs `launchctl`, or touches `~/Library`.

## Solution

### Approaches considered

1. Subclass registry in Python only. A base class `Source` and a Python `register()` call per adapter. It covers the engine but not the bash side (`cmd_sync` flag lines, verbs, sweep legs, the Multica token), which is where most of the Hermes references live, so it would leave about half the grep hits.
2. Plugin entry points by naming convention (`board-<verb>` executables on PATH). Verbs only; no answer for engine flags, filters, guards or sweep legs.
3. One manifest per adapter, read by a small Python loader and a small bash reader. Adds one file format and two readers of it. The engine already has the right Python interface; the manifest adds only what core cannot know any other way (which names exist and which flags and verbs belong to them).

### Chosen approach + why

Approach 3. The interface that already exists is the duck-typed source object in `sources/*.py` (`name`, `sync_fields`, `read()`, `apply()`, and optional `create_only`, `pull_only`, `skip_kw`, `binding`, `preflight()`, `preview()`). It is kept byte for byte. Added, and nothing else: an entry module with `build()` per adapter, three optional hooks (`guard`, `prepare`, and a provided `body_expander`), one optional attribute (`bound_marker_re`), and a manifest so bash can enumerate flags, verbs and legs without importing Python. Rejected: a base class (nothing to share), a config-declared import path (executes arbitrary project code), and a new daemon or registry service (a personal host needs none).

Config: loading is by use, as it is today. `[sync] apps` still selects spokes, `--mirror-hermes-home` still turns the mirror leg on, a verb runs when called. The new key `[adapters] dirs` (operator and kit-root only, never a project `.kit.toml`) says where adapters are looked up; the default `builtin` is the kit's own `lib/adapters/`. A host whose adapter directory is empty gets core only (defined below). No "enabled" list exists, because one that defaults off breaks the hourly sweep at merge (`--mirror-hermes-home` would exit 64) and one that defaults on adds nothing.

### Extensibility & boundaries

- Load-bearing dimension: the number of adapters. Cost of the sixth: one directory with a manifest and an `adapter.py`; no edit to core. The conformance test and the flag-surface check iterate manifests, so they cover it without edits.
- Boundaries: core never imports an adapter by name and never reads an adapter's files except `adapter.tsv`. An adapter may import core (`sync_core`, `cockpit`, `kit_data`, and the sweep helpers) and its own siblings, never another adapter; the one cross-adapter need (Hermes expanding a Notion page body) goes through a named hook the loader passes in.
- Failure containment: an adapter is imported only when something names it (an app in `--apps`, a verb, a leg, a hook provider). A broken adapter fails the runs that name it and warns for the rest.

### Architecture

See `## Design` below.

## Picture

```
BEFORE: core names the apps

  bin/board --> lib/board/board.sh
                 |- cmd_sync ........ one flag line per app key, the Multica token read
                 |- cmd_mirror, cmd_status, cmd_writeback --> board-mirror.sh, board-writeback.sh, native-map.tsv
                 |- mirror-cleanup .. board-mirror-cleanup.py
                 |- hermes .......... lib/sync/sweep/board-hermes
                 `- sweep, health, brief --> lib/sync/sweep/*  (mirror leg, expiry leg, link check, "Hermes mirror" text)

  lib/sync/backlog_sync.py --imports--> lib/sync/sources/{github,hermes,multica,notion,notion_taskboard,
                                          notion_taskboard_pull,ntn,reminders}.py
        build_source if-chain, per-app argparse flags, CREATE_ONLY/PULL_ONLY sets, Notion db guard, legacy state copy
  lib/sync/sync_core.py: notion-page marker, "Reminders inbox" heading, app names in wording

AFTER: core iterates manifests, adapters own their names

  bin/board --> board.sh --opt/secret/app rows--> lib/sync/adapters.sh --reads--> lib/adapters/*/adapter.tsv
                  |  `- unknown verb? --adapters_verb--> script in an adapter dir (mirror, status, writeback, mirror-cleanup, hermes)
                  `- sync --> backlog_sync.py --> lib/sync/adapters.py (loader) --imports--> lib/adapters/<name>/adapter.py
                                   guard, prepare, build, body_expander hook
  board-sweep --after-sync / last legs--> lib/adapters/hermes/legs/{mirror,expire,link-check}.sh
  board-health, board-brief --mirror-label, brief_decisions--> lib/adapters/hermes/{adapter.tsv,report.py}

  lib/adapters/
    reminders/  github/  multica/  notion/  hermes/      each: adapter.tsv adapter.py <its code> tests/ README.md
    docs/       dated specs and proof records moved out of lib/sync
    tests/      cross-adapter tests (conformance, body-expander relay)
  lib/board and lib/sync: zero references to the four apps
```

## Design

Design-bearing: yes (new module, an external-integration boundary, a verb and flag surface that live jobs depend on, 2+ viable approaches).

### Approaches considered + chosen

See `## Solution`: manifest plus the existing source interface.

### Diagram: one `board sync` run through the interface (sequence, ASCII)

```
cmd_sync (bash)                     backlog_sync.py                       adapters.py                 lib/adapters/<name>/adapter.py
 read [sync] keys
 export KIT_ADAPTERS_DIRS
 adapters_rows opt|secret|app
 resolve secret refs to env
 exec engine with plain flags ----> argparse: base flags + manifest opts
                                    reg = load()  -------------------->  scan dirs, parse adapter.tsv
                                    check_pull_isolation(names, reg)      generic: pull-only runs alone, takes no filter
                                    reg.guards(names, opts) ----------->  every adapter with a guard   ---> guard(names, opts)
                                    for app in names:
                                      reg.prepare(app, state_path) ---->  if defined                  ---> prepare(app, state_path)
                                      src = reg.build(app, opts, ctx) ->  import module lazily        ---> build(app, opts, ctx)
                                      (None means skipped this run)       mode must equal manifest mode
                                      sync_source(src, ...)   unchanged planner: src.read(), plan_sync, src.apply()
```

### ADR link(s)

Doctrine: the standalone-doctrine ADR (`docs/decisions/00NN-standalone-doctrine.md`, the lead fills the number). This spec records no separate irreversible decision: the manifest grammar is versioned by being read forgivingly (an unknown row kind is ignored with a warning), and every persisted name is frozen (below).

### Boundaries & failure modes

Out of bounds: the planner (`plan_sync`, `plan_pull_only`, `apply_board`, `build_state`) keeps its behavior and its tests. The state files, snapshot files and board text formats keep their names and shapes. Failure classes are in `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

#### Manifest: `lib/adapters/<name>/adapter.tsv`

Tab separated, UTF-8, one row per line, first field is the row kind, `#` in column 1 starts a comment, blank lines are skipped. An unknown kind is ignored with one stderr warning from the loader. Paths are relative to the adapter directory.

| Row | Fields | Meaning |
|---|---|---|
| `name` | `<name>` | the adapter id; equals its directory name; exactly one |
| `module` | `<file.py>` | entry module; defaults to `adapter.py`; required when an `app` row exists |
| `app` | `<app> <mode>` | app name and mode `two-way`, `create-only` or `pull-only`. The mode must equal what the built object declares (`create_only`, `pull_only` attributes), checked at load time |
| `opt` | `<flag> <key> <scope> <help>` | engine flag `--<flag>`, filled from `[sync] <key>`, handed to `build` as `opts[<key>]`. `scope` is `-` or `root` (operator and kit-root only). `help` is the argparse help text |
| `secret` | `<ENV> <key> <scope>` | before the engine starts, `cmd_sync` resolves the 1Password ref in `[sync] <key>` into env var `<ENV>` (Keychain cache read first, raw `op read` as the fallback, skipped when `<ENV>` is already set, never an argv flag) |
| `verb` | `<verb> <script>` | `board <verb> ARGS` runs the script with `ARGS`; `.py` runs under `python3`, anything else under `bash`. Env: `BOARD_ADAPTER_VERB`, `KIT_LIB` (absolute `lib/`), `KIT_ADAPTER_DIR` |
| `sweep-opt` | `<flag> <ENV> <help>` | `board sweep --<flag> VALUE` is accepted, exported to legs as `<ENV>`, and listed in `board sweep --help` |
| `leg` | `<phase> <script>` | a sweep leg; `phase` is `after-sync` (before the digest posts) or `last` (after the health leg) |
| `mirror-label` | `<Label>` | the display word in health and brief lines about the mirror leg (`Hermes`) |
| `report` | `<file.py>` | module with the optional hook `brief_decisions(health, cluster, first_cluster)` returning `[(sortkey, text), ...]` |
| `hook` | `<name>` | the entry module exports a function `<name>` that the loader hands to other adapters. Defined: `body_expander` |

Rules. Adapters are ordered by name; when two directories in `dirs` hold the same adapter name or app name, the first directory wins and the loader prints one warning. A verb that equals a core verb is ignored (core wins; `tests/test-adapters.sh` lints it). `KIT_ADAPTERS_DIRS` (colon separated) beats the config key, which beats the default `builtin`; `builtin` stands for `<lib>/adapters`.

#### Entry module (`adapter.py`)

```python
def build(app, opts, ctx):
    """Return the source object for `app`, or None to skip it this run (print the reason).
    opts: dict, key -> str or None, for every opt row of every adapter (the foundation-ops
          relay passes --notion-taskboard-db "" with only the pull app listed, so all flags parse).
    ctx:  SimpleNamespace(state=dict loaded from <app>.state.json or {}, project_root=str or None
          (KIT_PROJECT_ROOT), hooks={"body_expander": callable or None})."""

def guard(names, opts):          # optional; runs for EVERY discovered adapter before any source is built;
                                 # raises SystemExit to refuse the run
def prepare(app, state_path):    # optional; one-time migration for an app that is in `names`
def body_expander(body):         # optional; only when the manifest has `hook body_expander`
```

Source object: unchanged from today (`name`, `sync_fields`, `read() -> list[dict]`, `apply(plan, assigned, rows_after)`; optional `create_only`, `pull_only`, `skip_kw`, `binding`, `preflight(plan)`, `preview(plan)`). One added optional attribute: `bound_marker_re`, a compiled regex whose group 1 is the remote id a board row's notes already carry; `plan_create_only(rows, state, skip_kw, filt, bound_re=None)` binds such a row instead of creating a duplicate (the Notion page marker moves out of core this way).

#### Python loader: `lib/sync/adapters.py` (core)

`load(dirs=None) -> Registry`. `Registry` exposes `apps` (app to entry with adapter, mode), `options` (opt rows), `mode(app)`, `build(app, opts, ctx)`, `guards(names, opts)`, `prepare(app, state_path)`, `hook(name)`, `mirror_label()`, `report_hooks()`, `module(adapter, stem)` (imports a sibling module of an adapter the same way the loader does; tests use it). The loader puts `lib/sync`, `lib/sync/sweep`, `lib/config` and the adapter directory on `sys.path` while importing, imports with `importlib` under the name `kit_adapter_<name>`, and imports lazily. Sibling module names are unique across adapters (`reminders`, `github`, `multica`, `hermes`, `notion`, `notion_taskboard`, `notion_taskboard_pull`, `ntn`, `link`, `report`). The engine reads no config file; `KIT_ADAPTERS_DIRS` is its only input.

#### Bash reader: `lib/sync/adapters.sh` (core)

Sourced by `board.sh`, `board-sweep`. `adapters_dirs` prints one directory per line (env, else `kit_config_get_root adapters.dirs`, else `builtin`); `adapters_rows <kind>` prints `<adapter-dir><TAB><fields...>` for every row of that kind, adapters in name order; `adapters_verb <verb>` prints the script path or returns 1; `adapters_export` exports `KIT_ADAPTERS_DIRS` so the Python children see the same set. `tests/test-adapters.sh` runs the same fixture through both readers and compares.

#### Config

`kit.toml` gains `[adapters]` with `dirs = ""` (empty means `builtin`), tagged `[impl]`, with a row in `lib/config/module-registry.md`. It resolves through `kit_config_get_root`: a project `.kit.toml` value is ignored with the existing `_sync_note_shadow` note, because it loads and runs code and a project file rides inside an untrusted pull request. A relative or `~` path is expanded against `$HOME`.

#### Verbs, legs, report hooks

- `board.sh main()`: after the core cases, before the fall-through to `cmd_board_single`, one lookup: `adapters_verb "$first"`; on a hit it exports `BOARD_ADAPTER_VERB`, `KIT_LIB`, `KIT_ADAPTER_DIR` and `exec`s the script. A miss falls through unchanged, so with no adapter `board mirror` ends in `backlog.sh`'s usage line and exit 64, exactly as any unknown word does today.
- Verb scripts may source `$KIT_LIB/board/board-lib.sh` (new, extracted from `board.sh` in TASK-L): `_parse_flags`, `_default_repo_root`, `_resolve_repo_root`, `_repo_root_for`, `_mega_rollups`.
- `board-sweep`: after the per-repo loop it runs every `leg` row of phase `after-sync` in manifest order, and after the health leg every `last` leg. A leg is `bash <script>` with env `SWEEP_NAME`, `SWEEP_BOARDS`, `SWEEP_REPO_ROOT`, `SWEEP_DRY_RUN` (0 or 1), `SWEEP_BOARD_CMD`, `SWEEP_HEALTH_BIN`, `SWEEP_HEALTH_STATE`, `KIT_LIB`, `KIT_ADAPTER_DIR` and every `sweep-opt` variable that was given. The leg prints its own log lines (so log text stays byte for byte); its exit status never changes the sweep's exit code (a nonzero status prints `  leg <name> exited <rc> (non-fatal)`).
- `board-health` and `board-brief`: the words "Hermes mirror", "hermes mirror" and "the Hermes card" become `f"{label} mirror"`, `label.lower()` and `f"the {label} card"` with `label = reg.mirror_label()`; when no adapter supplies one the fallback is `mirror target`. `board-brief` replaces `HM.check_links()` with `report_hooks()`; a hook that raises is skipped with one stderr line, so a broken adapter never breaks the brief.

#### Invariants (frozen names, byte for byte)

- Verbs: `sync`, `sweep`, `sweep verify`, `health`, `brief`, `publish`, `capture`, `mirror`, `status`, `writeback`, `mirror-cleanup`, `hermes link`, `hermes check`.
- Engine flags: `--apps --backlog --archive-file --state-root --dry-run --filter --scope-exit-cap --allow-scope-exit --allow-flips --allow-archived-closes`, `--list --notion-db --notion-parent --notion-title --github-repo --hermes-target --hermes-home --hermes-board --hermes-assignee --hermes-workspace --notion-taskboard-db --notion-taskboard-status-map --notion-taskboard-status-default --notion-taskboard-priority-map --notion-taskboard-weight-map --notion-taskboard-owner --notion-taskboard-props --notion-taskboard-types --notion-taskboard-pull-db --notion-taskboard-pull-props --notion-taskboard-pull-done-option --multica-url --multica-workspace --multica-project`. Sweep flags: `--mirror-hermes-home --mirror-snapshot --expire-kinds-file`. `board sweep --help` prints `Usage: board sweep` and each of those.
- Config keys: every `[sync]` key in `kit.toml` keeps its name; `multica_url` and `multica_token_ref` stay root-only; the token reaches the engine through the `MULTICA_TOKEN` env var only.
- Persisted names: `<app>.state.json`, `digest-state.json`, `health-state.json` and its keys `sync`, `mirror`, `hermes_links`; `hermes-links.json`; `_meta/.board-mirror-snapshot*.jsonl`; the `bridge` column of `boards.txt`; the `chore/board-sync` branch; the markers `bls-<id>` (Hermes idempotency key), `bls: <id>` (GitHub body), `<!-- board:<state> -->` (Multica), `notion-page:<id>` (Notion), `origin: <repo>:<id>` (mirror card body) and `board-mirror:`.
- Board text: a heading of the shape `### <Word> inbox` that already exists keeps receiving intake rows, so `### Reminders inbox` in every live board still works; a board with none gets `### Intake inbox` (TASK-N).
- Output: `dry-run <app>: ...` and `synced <app>: ...` header lines and the `+ board`, `~ board`, `✓ board` action lines (the digest and the publish gate parse them). The one text change: `describe()` says "bound to an existing remote item (pull marker), not created" instead of "... Notion page ...".
- `sync_core.py`, `cockpit.py`, `lib/sync/deploy/macos/*`, `lib/sync/sweep/{board-sweep,board-sweep-verify,board-health,board-brief,board-digest.sh,board-sweep-post.sh,board-git-askpass}`: paths unchanged.

### Data model changes

None. No persisted file changes name, shape or location.

### API changes

The three moved verb groups keep their argv. `lib/board/board.sh` stops requiring `board-mirror.sh` and `board-writeback.sh` at startup. `plan_create_only` gains the optional `bound_re` parameter; `PULL_MARKER_RE` and `bound_page_id` leave `sync_core`.

### UI changes

None. Log and digest text is byte for byte except the one `describe()` line above.

### Infrastructure changes

None. No plist, no cron entry, no launchd reload, no new daemon, user or listener.

### Recipe R: moving one adapter (used by TASK-D to TASK-I)

1. `git mv` the source files and tests into `lib/adapters/<name>/` and `lib/adapters/<name>/tests/`; edit only import lines and the `sys.path` line.
2. Write `adapter.tsv` (`name`, `module`, `app`, `opt`, `secret`, hooks) from the flags and `cmd_sync` lines being deleted, and `adapter.py` from the `build_source` branch being deleted: same messages (`sys.exit("hermes: set hermes_home ...")` text stays), same arguments.
3. Delete from `backlog_sync.py`: the import, the `build_source` branch, the argparse lines. Delete from `board.sh` `cmd_sync`: the key lines.
4. Add `lib/adapters/<name>/tests/fixture-opts.json` for the conformance test, turn the old test imports into `adapter_module("<name>", "<stem>")` calls (the helper in `lib/adapters/conftest.py` goes through the loader; test bodies stay unchanged), and add the adapter's `tests` directory to the explicit pytest root list in `tests/test-sync.sh` (`tests/test-suites-collect.sh` case 8 greps the root suites for each directory name).
5. Check: the adapter's own pytest root, `bash tests/test-sync.sh`, `bash tests/test-sync-dispatch.sh`, and `grep -rilE '<app words>' lib/board lib/sync` shows only the files this task has not reached yet.

## Task Breakdown

Atomicity note. Each task edits at most 5 files that are not tests, fixtures or `git mv` renames. A rename whose only edit is an import or path line is listed under `moves`; the 10 suites in TASK-M change one path string each and are listed as `pins`. Test and fixture files a task adds are named in its Files list and are not counted. Each task has at most 5 acceptance bullets and ends with the repo green: `bash tests/run-all.sh --changed origin/master` after it, and the named suite. All tasks run on one branch (`refactor/sync-adapters`) as one commit each, merged as one PR (see Risk and rollback).

Order and parallelism: A then B. C needs A and B. D to I are serial (each edits `backlog_sync.py` and the `cmd_sync` function in `board.sh`). J, K, L may run in parallel with each other after I (J and K edit `hermes/adapter.tsv`, so J then K; L touches `board.sh` and `board-lib.sh` only). M needs J, K, L. N, O, P are disjoint from the rest and may run any time after G (N edits `sync_core.py`, as G does). Q and R need M. S is last.

`board.sh` overlap with the parallel worker that adds a state-check engine and a `board` verb: that worker edits the usage header comment, the `BOARD_*` variable block near the top, and the `main()` case list. TASK-C to TASK-I edit only `cmd_sync` and are safe. TASK-L edits only helper functions (disjoint). TASK-M edits the usage header, the variable block, the `cmd_mirror`, `cmd_status`, `cmd_writeback` functions and `main()`: it must start after that worker's PR is merged and rebase onto it. If the worker lands second, it must rebase over TASK-M.

### Phase 1: Foundation (loader, contract, config)

- [ ] TASK-A: Python loader and contract doc. Files: new `lib/sync/adapters.py`, new `lib/sync/tests/test_adapters.py`, new `lib/sync/tests/fixtures/adapters/fake/adapter.tsv` and `adapter.py` (a neutral fixture adapter with a two-way app, a create-only app, an `opt`, a `verb`, a `leg`), new `lib/adapters/README.md` (the contract in this spec's Interfaces section, plus "how to add an adapter"). Acceptance: the loader parses every row kind; honors `KIT_ADAPTERS_DIRS`; first directory wins on a name clash with one warning; an unknown row kind warns and is ignored; a built object whose mode disagrees with the manifest raises `SystemExit`; an empty directory list gives `apps == {}` and `build("x", ...)` exits with a message that names the searched directories; an adapter module is imported only when something names it. Check: `bash tests/test-sync.sh`.
- [ ] TASK-B: Bash reader, config key, parity. Depends on A. Files: new `lib/sync/adapters.sh`, new `tests/test-adapters.sh`, `kit.toml` (add `[adapters] dirs`), `lib/config/module-registry.md` (one row). Acceptance: `adapters_rows`, `adapters_verb`, `adapters_dirs`, `adapters_export` return the same data as the Python loader on the fixture (compared in the test); a project `.kit.toml` that sets `adapters.dirs` is ignored with a note and the operator file wins; `KIT_ADAPTERS_DIRS` beats config; `builtin` expands to `lib/adapters`. Check: `bash tests/test-adapters.sh && bash tests/test-config-registry.sh`.

### Phase 2: the engine on the registry, then the five spoke adapters (serial)

- [ ] TASK-C: Engine and `cmd_sync` read the registry; nothing moves yet. Files: `lib/sync/backlog_sync.py`, `lib/board/board.sh` (`cmd_sync` only), `tests/test-sync.sh` (pytest roots, explicit list), `tests/test-sync-dispatch.sh`, `lib/sync/tests/test_core.py` (engine tests that use the fixture adapter through `KIT_ADAPTERS_DIRS`). Acceptance: `build_source(name, args)` asks the registry first and falls back to the existing if-chain; argparse adds the manifest `opt` flags; `cmd_sync` adds manifest `opt` and `secret` rows and the filter keys per `app` row (`only_tags`, `skip_tags`, `intake` for two-way, no `intake` for create-only, none for pull-only), while the existing per-app lines stay until their task; `CREATE_ONLY_APPS` and `PULL_ONLY_APPS` are derived from manifest modes plus the legacy sets; `check_pull_isolation` keeps its generic part (pull-only apps run alone and take no filter) and calls `reg.guards`. The fixture adapter syncs a fixture board end to end through `sync_source`. Check: `bash tests/test-sync.sh && bash tests/test-sync-dispatch.sh`; the pass count stays at least 326 (see Test plan).
- [ ] TASK-D: Reminders adapter (the pilot). Files: new `lib/adapters/reminders/adapter.tsv` and `adapter.py` (`build`, `prepare` carrying the legacy state copy from `~/.cache/backlog-reminders-sync/state.json`), new `lib/adapters/conftest.py` (the `adapter_module` helper) and `lib/adapters/tests/test_conformance.py` (parametrized over every app in the registry; the transport guard in Test plan), `lib/sync/backlog_sync.py`, `lib/board/board.sh`; moves `sources/reminders.py` and `tests/test_reminders.py`; new `fixture-opts.json`. Acceptance: Recipe R; the legacy state copy runs only when `reminders` is in `names`; `--list` and `[sync] reminders_list` still work; the 12 Reminders tests pass unchanged; the conformance test passes for `reminders`. Check: `bash tests/test-sync.sh`.
- [ ] TASK-E: GitHub adapter. Files: new `lib/adapters/github/{adapter.tsv,adapter.py,fixture-opts.json}`, `lib/sync/backlog_sync.py`, `lib/board/board.sh`; moves `sources/github.py` (reword its two comments that name other apps) and `tests/test_github.py`. Acceptance: Recipe R; `--github-repo` and `KIT_PROJECT_ROOT` behavior unchanged; the 6 GitHub tests pass. Check: `bash tests/test-sync.sh`.
- [ ] TASK-F: Multica adapter. Files: new `lib/adapters/multica/{adapter.tsv,adapter.py,fixture-opts.json}`, `lib/sync/backlog_sync.py`, `lib/board/board.sh` (delete the multica key lines and the token block); moves `sources/multica.py`, `tests/test_multica.py`. Acceptance: Recipe R; `adapter.tsv` carries `opt multica-url multica_url root`, `opt multica-workspace`, `opt multica-project`, `secret MULTICA_TOKEN multica_token_ref root`, so `cmd_sync` reads the URL and ref from operator and kit-root only and keeps the "ignoring ... root-only key" note; the token reaches the engine by env only, never argv; the 13 Multica tests pass. Check: `bash tests/test-sync.sh && bash tests/test-sync-dispatch.sh`.
- [ ] TASK-G: Notion bound-marker hook, in place. Files: `lib/sync/sync_core.py` (`plan_create_only` takes `bound_re`; delete `PULL_MARKER_RE` and `bound_page_id`; `describe()` wording), `lib/sync/backlog_sync.py` (`sync_create_only` passes `getattr(src, "bound_marker_re", None)`), `lib/sync/sources/notion_taskboard.py` (class attribute `bound_marker_re`), `lib/sync/tests/test_notion_taskboard.py` (the marker test imports the regex from the adapter module), `lib/sync/tests/test_core.py` (a neutral `bound_re` test with a fake marker). Acceptance: behavior unchanged for a Notion push (the existing 35 tests pass); with `bound_re=None` no row is adopted; the core test uses a fake marker `fake-id:<hex>`. Check: `bash tests/test-sync.sh`.
- [ ] TASK-H: Notion adapter (three apps). Files: new `lib/adapters/notion/{adapter.tsv,adapter.py,fixture-opts.json}` (`adapter.py` holds the three `build` branches, the skip-without-binding rule that prints `notion: skipped (no binding; ...)` and returns None, `guard` with the "same database as notion_taskboard_pull_db" refusal compared with dashes stripped, and `body_expander = expand_body`), `lib/sync/backlog_sync.py` (delete `check_pull_isolation`'s database check, the three branches, the notion skip, the flags), `lib/board/board.sh`; moves `ntn.py`, `notion.py`, `notion_taskboard.py`, `notion_taskboard_pull.py` and their four tests. Acceptance: Recipe R for the three apps; `adapter.tsv` has `app notion two-way`, `app notion-taskboard create-only`, `app notion-taskboard-pull pull-only`, every `--notion-*` flag with its original help text, and `hook body_expander`; the engine's generic isolation tests move to core (`test_core.py`) over the fixture adapter and the three Notion database guard tests stay with the adapter; every Notion test still passes (notion 11, taskboard 35, ntn 55, pull 64 by the baseline); the four generic isolation tests of the pull suite (`test_pull_app_refuses_to_share_an_invocation`, `test_pull_app_alone_is_fine`, `test_pull_app_takes_no_filter`, `test_filters_for_other_apps_are_untouched`) move to `test_core.py` over the fixture adapter, the three database-guard tests stay with the adapter, and the three relay tests move in TASK-I. Check: `bash tests/test-sync.sh`.
- [ ] TASK-I: Hermes spoke adapter and the body-expander relay. Files: new `lib/adapters/hermes/{adapter.tsv,adapter.py,fixture-opts.json}` (`build` reads `ctx.hooks["body_expander"]`; same two `sys.exit` messages for a missing `hermes_home` and `hermes_target`), new `lib/adapters/tests/test_body_expander.py` (the two relay tests and the "build wires the expander" test, moved out of `test_notion_taskboard_pull.py`, now through the registry), `lib/sync/backlog_sync.py`, `lib/board/board.sh`; moves `sources/hermes.py`, `tests/test_hermes.py`; deletes `lib/sync/sources/` (the package is empty). Acceptance: Recipe R; `--hermes-*` flags and `--filter hermes:...` unchanged; the hook is passed in by the loader from whichever adapter declares it (the notion adapter), `None` when that adapter is absent; the 18 Hermes tests and 3 relay tests pass. Check: `bash tests/test-sync.sh && bash tests/test-sync-dispatch.sh`.

### Phase 3: Hermes bridge, sweep legs, report hooks

- [ ] TASK-J: Sweep legs. Depends on I. Files: `lib/sync/sweep/board-sweep` (delete the mirror leg, `build_origin_mirror_registry`, the expiry leg, the link-check call and the three flags; add the generic leg runner and manifest `sweep-opt` parsing; `usage()` appends the adapter flags), new `lib/adapters/hermes/legs/mirror.sh`, `legs/expire.sh`, `legs/link-check.sh` (the deleted code, run from env; `link-check.sh` still calls `python3 "$KIT_LIB/sync/sweep/board-hermes"`, repointed in TASK-M), `lib/adapters/hermes/adapter.tsv` (`sweep-opt`, `leg` rows); pins `tests/test-board-sweep-mirror.sh`, `tests/test-board-sweep-expire.sh` (the mirror-cleanup trap block is extracted from the leg file instead of `board-sweep`). Acceptance: `board sweep --help` still prints `Usage: board sweep`, `--mirror-hermes-home`, `--mirror-snapshot`, `--expire-kinds-file`; with the three flags given, the log lines of the mirror and expire legs are byte for byte what they are today (fixture compare); with no adapter, `board sweep` runs the syncs and ends `rc=0`; a leg exiting nonzero prints the non-fatal line and never changes the sweep rc; `board-sweep` names no app, in code, comments or help text. Check: `bash tests/test-board-sweep.sh && bash tests/test-board-sweep-mirror.sh && bash tests/test-board-sweep-expire.sh`.
- [ ] TASK-K: Health and brief without the app word. Depends on J (shares `hermes/adapter.tsv`). Files: `lib/sync/sweep/board-health`, `lib/sync/sweep/board-brief`, new `lib/adapters/hermes/report.py` (`brief_decisions` carrying the stale-link decision text; imports `board-hermes` through `sweep_modules.load` until TASK-M), `lib/adapters/hermes/adapter.tsv` (`mirror-label Hermes`, `report report.py`), `lib/sync/adapters.py` (`mirror_label`, `report_hooks`; tested in `test_adapters.py`). Acceptance: the health and brief output is byte for byte what it is today with the adapter present (the 97 and 243 existing assertions pass); the two files, their docstrings and their help text name no app; with no adapter the fallback label is `mirror target` and the brief runs; a raising hook is skipped with one stderr line. Check: `bash tests/test-board-health.sh && bash tests/test-board-brief.sh`.
- [ ] TASK-L: Extract the shared board helpers. Depends on I. Files: new `lib/board/board-lib.sh` (`OPT_*` defaults, `_parse_flags`, `_default_repo_root`, `_resolve_repo_root`, `_repo_root_for`, `_mega_rollups`, the `box.sh` source), `lib/board/board.sh` (delete those definitions, source the lib). A pure refactor. Acceptance: `bash tests/test-board.sh` and `bash tests/test-board-mirror.sh` pass with no edit; `board.sh` behavior is unchanged; no other function body changes. Check: `bash tests/test-board.sh`.
- [ ] TASK-M: Move the bridge and add the generic verb lookup. Depends on J, K, L, and on the state-check worker's merge. Files: new `lib/adapters/hermes/bridge.sh` (the bodies of `cmd_mirror`, `cmd_status`, `cmd_writeback` and `_legacy_bridge_note`, dispatching on `$BOARD_ADAPTER_VERB`, sourcing `board-lib.sh`; the `--remote` ssh path becomes `lib/adapters/hermes/board-mirror.sh`), `lib/adapters/hermes/adapter.tsv` (`verb mirror`, `verb status`, `verb writeback` to `bridge.sh`, `verb mirror-cleanup` to `board-mirror-cleanup.py`, `verb hermes` to `link.py`), `lib/board/board.sh` (delete the three functions, the two startup requires, `BOARD_MIRROR_SH`, `BOARD_WRITEBACK_SH`, `BOARD_MIRROR_CLEANUP_PY`, `BOARD_HERMES_PY`, the five `main()` cases and the bridge paragraphs of the usage header; add the one `adapters_verb` lookup), `lib/adapters/hermes/report.py` and `lib/adapters/hermes/legs/link-check.sh` (repoint to `link.py`); moves `board-mirror.sh`, `board-writeback.sh`, `board-mirror-cleanup.py`, `native-map.tsv`, `sweep/board-hermes` to `link.py`, each with its self-location lines changed to `KIT_LIB` (`$BM_DIR/parse-board.sh`, `$BM_DIR/../mega/box.sh`, `$BW_DIR/backlog.sh`, `$BW_DIR/states.tsv`, `Path(__file__).parent.parent / "mega" / "box.py"`, `KIT = HERE.parent.parent.parent`); pins `tests/test-board-mirror.sh`, `test-board-writeback.sh`, `test-board-states.sh`, `test-board-mirror-cleanup.sh`, `test-board-mirror-expire.sh`, `test-board-registry-env.sh`, `test-board-hermes.sh`, `test-mega-box.sh`, `test-kit-contract.sh`, `test-meta-vmodel-dispatch.sh`, fixture `tests/fixtures/board-sweep/stub-hermes-kanban`; comment pointers in `lib/mega/mega.sh`, `lib/session/handoffs.sh`. Acceptance: `board mirror|status|writeback|mirror-cleanup|hermes` reach the moved scripts through `bin/board` with the same argv and output; `board.sh` starts with no adapter directory present; with the adapter absent `board mirror` ends in usage and exit 64; the full bridge suites keep their counts (Test plan). Check: `bash tests/test-board-mirror.sh && bash tests/test-board-writeback.sh && bash tests/test-board-hermes.sh && bash tests/test-board-states.sh`.

### Phase 4: core wording, records, docs, guards

- [ ] TASK-N: Neutral wording in core code. Depends on G. Files: `lib/sync/sync_core.py` (`INBOX_HEADING = "### Intake inbox"` for a new section, `INBOX_HEADING_RE = ^### [A-Za-z]+ inbox$` to find an existing one, comments), `lib/sync/cockpit.py` (comments), `lib/sync/tests/test_core.py` (sample names `"hermes"` and `"reminders"` become `"spoke-a"`, `"spoke-b"`; the heading assertions), `lib/sync/tests/test_cockpit.py` (docstring), new `lib/adapters/reminders/tests/test_legacy_inbox.py` (a fixture board with a `### Reminders inbox` section still receives intake rows under that heading). Acceptance: a board with an existing `### <Word> inbox` section gets rows there (the first match wins); a board with none gets `### Intake inbox` before `## Recently closed`; no behavior change otherwise. Check: `bash tests/test-sync.sh`.
- [ ] TASK-O: Comment-only edits. Files: `lib/sync/deploy/macos/board-sync-cron`, `lib/sync/deploy/macos/install`, `lib/sync/deploy/macos/README.md`, `lib/sync/sweep/board-sweep-verify`. Acceptance: the diff touches comment and doc lines only (`git diff -U0` shows no executable line changed); `bash tests/test-sync-cron-install.sh && bash tests/test-sync-cron-launcher.sh && bash tests/test-board-sweep-verify.sh` pass; `board-sync-cron` keeps its path, mode and shebang `#!/bin/bash`.
- [ ] TASK-P: Move the dated records. Files: `git mv lib/sync/docs/specs/SPEC-001-multi-source-sync.md`, `SPEC-002-sync-mesh.md`, `SPEC-003-oneway-create-push.md`, `SPEC-004-pull-mode-intake.md` to `lib/adapters/docs/specs/` and `lib/sync/docs/proof-of-done.md` to `lib/adapters/docs/proof-of-done.md`, contents untouched. Acceptance: `git diff -M --stat` shows 5 renames at 100 percent similarity; `lib/sync/docs/` no longer exists; `bash -c '. lib/spec/spec-find.sh; spec_files "$PWD"' | rg 'lib/adapters/docs/specs/SPEC-00[1-4]'` prints four lines and `bash tests/test-spec-find.sh` passes.
- [ ] TASK-Q: Docs, part one. Depends on M. Files: `lib/sync/README.md` (core only: the engine, the planner, the sweep, scheduling, the adapter interface by link; no app name), `lib/board/README.md`, new `lib/adapters/reminders/README.md`, `lib/adapters/github/README.md`, `lib/adapters/multica/README.md` (each: what the app holds, config keys, run notes, moved from the old README). Acceptance: every config key and flag the old README documented appears in exactly one README; no moved text is dropped; the core READMEs name no app.
- [ ] TASK-R: Docs, part two. Depends on M. Files: new `lib/adapters/notion/README.md` (sections for `notion`, `notion-taskboard`, `notion-taskboard-pull`), new `lib/adapters/hermes/README.md` (spoke, bridge verbs, legs, link), `docs/reference/project-structure.md` (the `lib/board` rows and a `lib/adapters/` row), `lib/config/module-registry.md` (the `sync` row's paths), `CHANGELOG.md` (an Unreleased entry listing the move and the unchanged surfaces). Acceptance: no live doc names a path that no longer exists (`rg` for the old paths over `docs/reference`, `lib/*/README.md`, `lib/config` shows only dated records); the module-registry completeness suite passes. Check: `bash tests/test-config-registry.sh`.
- [ ] TASK-S: Guards. Depends on all. Files: new `tests/test-core-purity.sh`, new `tests/fixtures/core-purity/planted/lib/sync/planted.py` (contains the word `Hermes`) and `.../planted/lib/board/notion_named.sh` (a file whose name contains `notion`), `tests/test-adapters.sh` (add the frozen-surface check and the no-adapter end-to-end cases), `tests/test-sync.sh` (final pytest roots). Acceptance: see Test plan rows T1 to T4. Check: `bash tests/test-core-purity.sh && bash tests/test-adapters.sh`.

## Test plan

Baselines, taken on `origin/master` at `3eb93852` on this host, before any change:

| Suite | Command | Baseline |
|---|---|---|
| sync python | `bash tests/test-sync.sh` | 326 passed (core 112: `test_core` 94, `test_prefix` 8, `test_cockpit` 5, `test_atomic_write_mode` 5; adapters 214: reminders 12, github 6, multica 13, hermes 18, notion 11, notion taskboard 35, notion pull 64, ntn 55) |
| sync dispatch | `bash tests/test-sync-dispatch.sh` | 10 of 10 |
| board states | `bash tests/test-board-states.sh` | all pass (32 PASS lines) |
| hermes link | `bash tests/test-board-hermes.sh` | 79 passed |
| mirror | `bash tests/test-board-mirror.sh` | TOTAL 116, PASS 116 |
| writeback | `bash tests/test-board-writeback.sh` | TOTAL 75, PASS 74, SKIP 1 |
| mirror cleanup | `bash tests/test-board-mirror-cleanup.sh` | TOTAL 31, PASS 31 |
| mirror expire | `bash tests/test-board-mirror-expire.sh` | TOTAL 31, PASS 31 |
| sweep | `bash tests/test-board-sweep.sh` | PASS 55 |
| sweep mirror | `bash tests/test-board-sweep-mirror.sh` | PASS 43 |
| sweep expire | `bash tests/test-board-sweep-expire.sh` | TOTAL 14, PASS 14 |
| health | `bash tests/test-board-health.sh` | 97 passed |
| brief | `bash tests/test-board-brief.sh` | 243 passed |

How each suite proves the adapter still works through the interface:

- Python: the moved adapter test files keep their test bodies. They obtain the source class through `adapter_module(adapter, stem)` in `lib/adapters/conftest.py`, which calls the loader, so the loader's `sys.path` handling and lazy import are on the path of every test. "Equal count" is mechanical: the `git grep` and `pytest --co` pair in `## Verification` writes the old and new name lists, and `comm -23 before after` must print nothing. Total passes must be at least 326.
- Conformance (new, `lib/adapters/tests/test_conformance.py`): for every app the registry lists, build through `reg.build` with the adapter's `fixture-opts.json`; assert `name == app`, `create_only` and `pull_only` equal the manifest mode, `read` and `apply` are callable (a pull-only source has no `apply`), `sync_fields` is a bool; replace `.runner` with a fake that records the call; call `read()` once and assert the fake was reached. An autouse fixture makes `subprocess.run`, `subprocess.Popen`, `urllib.request.urlopen` and `socket.socket.connect` raise `AssertionError("real transport")`, so no test can reach a real store. `MULTICA_TOKEN=fixture` is set only inside the test.
- Bash: the bridge, sweep, health and brief suites run unchanged except for the one path string each pin changes; their counts must equal the baseline.

New tests (all fixture based; none reaches a real store):

| ID | Test | Where | What it proves | Negative control |
|---|---|---|---|---|
| T1 | core purity | `tests/test-core-purity.sh` | `grep -rilE 'hermes\|notion\|reminders\|multica' lib/board lib/sync` and a `find` over file names return nothing in the real tree | the test copies `lib/board` and `lib/sync` to a temp directory and plants a file naming `Hermes` and a file named `notion_named.sh`; the scanner must report both; the test fails if it reports nothing |
| T2 | no adapter configured | `tests/test-adapters.sh` | with `KIT_ADAPTERS_DIRS` pointing at an empty directory: `board next --backlog-file F` and `board set` work; `board sync` with `apps = "x"` exits nonzero and the message names "no adapter provides it" and the searched directories; `board mirror --backlog-file F` ends in `backlog.sh`'s usage with exit 64; `board sweep --help` prints `Usage: board sweep` and none of the adapter flags; `board sweep` over a registry whose repo has no `[sync]` block logs a skip and ends `rc=0`; `board.sh` starts | the same cases with the fixture adapter directory present show the adapter flags and verbs, so the test fails if "absent" and "present" read alike |
| T3 | frozen surface | `tests/test-adapters.sh` | `backlog_sync.py --help` lists every flag in the frozen list; `board sweep --help` lists the three sweep flags; `adapters_verb` resolves `mirror`, `status`, `writeback`, `mirror-cleanup`, `hermes` in the built-in set; every `[sync]` key in `kit.toml` that starts with an app prefix is read by some manifest `opt` row | delete one `opt` row from a temp copy of a manifest: the test must fail naming the flag |
| T4 | loader and bash parity | `lib/sync/tests/test_adapters.py`, `tests/test-adapters.sh` | both readers agree on the fixture; a project `.kit.toml` cannot set `adapters.dirs` | change one row in the fixture after the Python run: the comparison must fail |
| T5 | engine over a fixture adapter | `lib/sync/tests/test_core.py` | two-way, create-only and pull-only fixture apps run through `sync_source`; pull-only runs alone and takes no filter; a guard refusal stops the run before any source is built | a fixture whose manifest says `two-way` but whose object sets `pull_only = True` must exit with the mode-mismatch message |
| T6 | body-expander relay | `lib/adapters/tests/test_body_expander.py` | the Hermes create carries the Notion page body through the hook the loader passes in; with the Notion adapter absent the hook is `None` and the create still succeeds | remove the `hook body_expander` row in a temp copy: the relay test must fail |
| T7 | legacy inbox heading | `lib/adapters/reminders/tests/test_legacy_inbox.py` | a board with `### Reminders inbox` keeps receiving rows there | a board with no inbox heading must get `### Intake inbox`, not the legacy text |

Coverage by category: happy path (T2 present case, T3, conformance), edge (name clash, unknown row kind, `bound_re=None`, missing hook provider), failure (broken adapter import, leg exits nonzero, mode mismatch), regression (all baselines above), security (project `.kit.toml` cannot set `adapters.dirs`; the Multica token never in argv).

## After state

- [ ] `grep -rilE 'hermes|notion|reminders|multica' lib/board lib/sync` prints nothing, and `grep -ril hermes lib/board lib/sync` prints nothing. (Today: 40 files, 26 of them for hermes.)
- [ ] `lib/adapters/` holds `reminders`, `github`, `multica`, `notion`, `hermes`, each with `adapter.tsv`, `adapter.py`, tests and a README; `lib/sync/sources/` and `lib/sync/docs/` no longer exist. (Today: 8 source files in core.)
- [ ] `bash tests/test-sync.sh` passes with at least 326 tests, and every pre-existing test name still exists (the `comm -23` check prints nothing).
- [ ] `bash tests/test-core-purity.sh` and `bash tests/test-adapters.sh` pass, each with its negative control shown failing first.
- [ ] `KIT_ADAPTERS_DIRS=<empty dir> bash bin/board next --backlog-file <fixture>` works and `board sync` names the missing adapter; with the real set, `board sweep --help` still prints `Usage: board sweep` and `--expire-kinds-file`.
- [ ] No plist, no cron entry and no external caller changed: `rg -l 'lib/(sync|board)|bin/board|board sweep|board sync|backlog_sync' ~/Library/LaunchAgents/*.plist` still prints nothing, and `git diff origin/master --stat -- bin deploy lib/sync/deploy/macos` shows comment lines only.
- [ ] A seventh adapter is one new directory and no core edit.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Tests cover the happy path and the edge cases listed below.
- [ ] No regressions: every baseline in the Test plan holds.
- [ ] The frozen surfaces under Invariants are unchanged (T3).

## Verification

Run from the repo root of the branch, in this order. The first four are the row's own contract.

```bash
grep -rilE 'hermes|notion|reminders|multica' lib/board lib/sync | wc -l
grep -ril hermes lib/board lib/sync
bash tests/test-core-purity.sh
bash tests/test-adapters.sh
bash tests/test-sync.sh
bash tests/test-sync-dispatch.sh
bash tests/test-board-states.sh && bash tests/test-board-hermes.sh && bash tests/test-board-mirror.sh && bash tests/test-board-writeback.sh
bash tests/test-board-mirror-cleanup.sh && bash tests/test-board-mirror-expire.sh && bash tests/test-board-sweep.sh && bash tests/test-board-sweep-mirror.sh && bash tests/test-board-sweep-expire.sh
bash tests/test-board-health.sh && bash tests/test-board-brief.sh
git grep -h '^def test_' origin/master -- lib/sync/tests | sed 's/def \(test_[A-Za-z0-9_]*\).*/\1/' | sort -u > "${TMPDIR:-/tmp}/before.txt"
uv run --no-project --with pytest -- pytest --co -q lib/sync/tests lib/adapters | rg '::' | sed 's/.*:://; s/\[.*//' | sort -u > "${TMPDIR:-/tmp}/after.txt"; comm -23 "${TMPDIR:-/tmp}/before.txt" "${TMPDIR:-/tmp}/after.txt"
bash bin/board sweep --help | rg -e 'Usage: board sweep' -e '--expire-kinds-file' -e '--mirror-hermes-home' -e '--mirror-snapshot'
rg -l 'lib/(sync|board)|bin/board|board sweep|board sync|backlog_sync' ~/Library/LaunchAgents/*.plist
bash tests/run-all.sh --changed origin/master --time
```

Expected: the first prints `0`; the second prints nothing; the `comm` line prints nothing; the `rg` on plists prints nothing and exits 1; every suite reports its Test plan baseline or more; `run-all` ends all green. Never run the live board sync, `board mirror` against a real Hermes, or any call that reaches Notion, Reminders, Multica or Discord: every command above uses fixtures and stubs.

## Edge Cases

1. A manifest row of an unknown kind: ignored with one warning; the rest of the adapter loads.
2. Two directories in `dirs` hold the same adapter name or app name: the first wins, one warning, the second's rows are ignored.
3. `[sync] apps` names an app no adapter provides: exit 1 with `no adapter provides it`, the searched directories and the apps that were found.
4. A hermes flag is passed while the hermes adapter is absent: argparse exits 2 with its usual "unrecognized arguments".
5. A project `.kit.toml` sets `adapters.dirs`: ignored, one stderr note naming the operator file.
6. `KIT_ADAPTERS_DIRS` names a missing directory: skipped with one warning; the remaining directories load.
7. The Notion adapter is absent while the Hermes relay runs: the hook is `None`; the card is created with the unexpanded body, the same outcome as today's "page body unavailable" path.
8. A leg script is missing or exits nonzero: the sweep logs `leg <name> exited <rc> (non-fatal)` or a skip line and continues; its exit code is unchanged.
9. A board with two `### <Word> inbox` headings: the first one receives rows.
10. A verb in a manifest equals a core verb: core wins; `tests/test-adapters.sh` fails the lint so it is caught at build time.
11. `board sweep` and `board health` run as the `server` account through `/Users/Shared/dwarves-kit`: adapter directories are 755 and files keep their mode bits, so it can read and run them.
12. Old state written by the previous kit (`<app>.state.json`, snapshot, `health-state.json`) is read by the new code unchanged, and the reverse holds after a revert.
13. `board sweep --dry-run`: legs receive `SWEEP_DRY_RUN=1` and keep the `--dry-run` behavior they have today.
14. An adapter that imports another adapter directly: not allowed; the conformance test imports each adapter alone in a fresh interpreter to catch it.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A moved path is missed and a live job breaks silently | the hourly `board-sync-all.log` stops ending `rc=0`; T3 and the suite pins fail first | every live caller goes through `bin/board` or `sync_core`; T3 pins verbs, flags and `board sweep --help`; revert the PR (below) |
| The Hermes mirror leg changes its log text or order | `test-board-sweep-mirror.sh` fixture compare, `test-board-health.sh` digest text | legs print their own lines; phase order `after-sync` then `last` reproduces today's order (mirror, expire, digests, health, link check) |
| A broken adapter breaks unrelated runs | a sync that names another app fails at import | lazy per-adapter import; failure only for runs that name the adapter, a hook provider's failure degrades to `None` |
| Manifest and code disagree on a mode or a flag | load-time mode check, T3 frozen list | hard `SystemExit` at load, never a silent skip |
| A project file makes the loader run attacker code | none unless the key is read from the project | `adapters.dirs` resolves root-only; a project value is ignored with a note |
| The Multica token leaks into argv | `ps` shows it | `secret` rows export an env var only; the existing Multica test and a new argv assertion in `test-sync-dispatch.sh` |
| The pinned kit in foundation-ops is bumped before this lands everywhere | the intake tick fails at `bin/board sync` | the bump is a separate operator step (below); until then the pinned clone never sees this change |
| `--remote` mirror runs against a remote host on an older kit | the remote script path is missing | `--remote` has no live user today; it requires the same kit version on both ends (README, TASK-R) |

## Risk and rollback

What breaks if a move is wrong: this host runs the checkout, so the first hourly sweep after merge (`mini.sync`, stage `board-sync-all`) and the next neko-chief `health` or `brief` dry run are the first live readers. A wrong verb path ends the sweep with a nonzero exit; a wrong flag exits 64 or 2; a missed `KIT_LIB` self-location error fails one leg (logged, never fatal). The Notion intake tick on the Mini is isolated by its pinned `KIT_REF` and cannot be hit by the merge.

Rollback: ship the whole change as one PR with one commit per task, squash merged, so one command undoes it: `git revert -m 1 <merge commit>` (or `git revert <sha>` for a squash) on `master`. No persisted file changes name or shape, so there is nothing to migrate back. The one data difference: a board created between merge and revert has `### Intake inbox`, which the old code does not recognize; it would add a second section. No live board is created by the jobs above.

Pre-merge gate: `kit:battery`, then the Verification list. Post-merge, read only: `bash ~/.claude/dwarves-kit/bin/board sweep --help | rg -e 'Usage: board sweep' -e '--expire-kinds-file'`, then the next hourly tick: `tail -n 40 ~/Library/Logs/dwarves-kit/board-sync-all.log` must end with an `end rc=0` line.

## Not in this spec

Anything that needs a plist edit, a launchd reload or another repo. None is required for this change to work.

1. Bump the pinned kit in the Notion intake job (foundation-ops, a separate PR). Edit `KIT_REF` at line 33 of `jobs/notion-taskboard-pull/deploy` to a commit that contains this change; run `jobs/notion-taskboard-pull/test-takeover`, `jobs/notion-taskboard-pull/test-status-return` and `jobs/notion-taskboard-pull/test-heartbeat-ok-only` against that kit; merge; then from the Air `jobs/notion-taskboard-pull/deploy` (it refreshes the clone and re-bootstraps the LaunchAgent), then `ssh $MINI_OPS_SSH 'launchctl kickstart -k gui/$(id -u)/foundation.d.notion-taskboard-pull'`.
2. Stale comment pointers to `lib/sync/sources/hermes.py` in `foundation-ops` `jobs/incident-consumer/foundation-incident-consumer` and in `hermes-personal` `home/scripts/incident-consumer` (comments only, no import): optional edits in those two repos.
3. `board capture` still reads `github.state.json` and runs `gh issue view`. It names GitHub, not one of the four apps; moving it needs an adapter hook (`capture_note`) and is a follow-up.
4. `kit.toml` `[sync]` and `lib/config/module-registry.md` still declare the per-app keys by name (config documentation, outside `lib/board` and `lib/sync`). Making key declarations adapter-owned is a follow-up.
5. `integrations/hermes/skills/` stays where it is (an agent skill pack that `board hermes link` installs, outside the two core roots).
6. Operator, after merge, read only: the two commands under Risk and rollback. No state file, plist or credential changes.

## Out of Scope

- A change to the planner (`plan_sync` and friends) or to any state, snapshot or board text format, beyond the one inbox-heading rule and the one `describe()` line.
- Renaming a verb, flag, config key, app name or marker.
- A new adapter (the sixth is a later change that this makes cheap).
- Moving `lib/sync/sync_core.py`, `cockpit.py`, the sweep scripts or `deploy/macos/*`: live callers import or run them by path.
- Rewriting dated records: they move untouched.

## Grounding

Every external data shape below was read in this tree or on this host, read only, on 2026-11-25. No live Hermes, Notion, Reminders or Multica call was made.

- The literal grep: `grep -ril hermes lib/board lib/sync` lists 26 files, among them `lib/board/board.sh`, `lib/board/board-mirror.sh`, `lib/sync/backlog_sync.py`, `lib/sync/sources/hermes.py`, `lib/sync/sweep/board-sweep`, `lib/sync/tests/test_hermes.py`. `grep -rilE 'hermes|notion|reminders|multica' lib/board lib/sync` lists 40.
- Installed jobs: `rg -l 'lib/(sync|board)|bin/board|board sweep|board sync|backlog_sync' ~/Library/LaunchAgents/*.plist` prints nothing (exit 1). `crontab -l` prints `crontab: no crontab for tieubao`. The four plists that name `dwarves-kit` are `han.dotfiles-watcher`, `mini.field-watch`, `kit-weekly` (ProgramArguments `.../dwarves-kit/deploy/macos/kit-weekly`) and `mini.harvest-sweep`.
- The live sweep entry: `mini.sync` ProgramArguments is `.../ops-toolkit/tools/mac-mini-substrate/mini-sync`; its stage `board-sync-all` runs `tools/board-sync/bin/board-sync-all`, which contains `if ! "$BOARD_CMD" sweep --help 2>&1 | grep -q 'Usage: board sweep'` and `if "$BOARD_CMD" sweep --help 2>&1 | grep -q -- '--expire-kinds-file'`. `bash bin/board sweep --help` prints both strings today (the `Usage: board sweep` line and the `--expire-kinds-file` flag line).
- The pinned intake job: `jobs/notion-taskboard-pull/deploy` line 33 reads `KIT_REF="${KIT_REF:-177112be...f6da97cc}"` (masked); the job script runs `DWARVES_KIT="${KIT}" "${CLONE}/_meta/board" sync --apps notion-taskboard-pull --notion-taskboard-pull-db "${PULL_DB}" --notion-taskboard-db ""` and `--apps hermes --filter hermes:only_tags=notion-intake --filter hermes:intake=all ... --hermes-workspace "dir:${HERMES_WORKSPACE}"`; `status-return` does `sys.path.insert(0, os.path.join(a.kit, "lib", "sync"))` then `import sync_core` and calls `sync_core.parse_board(text, prefix=a.prefix)`.
- Shared kit for neko-chief: `/Users/Shared/dwarves-kit` is a symlink to the live checkout; `fleet/kit-board/chief-board` runs `$KIT/bin/board` for `health` and `brief` only.
- Unknown verb today: with a fixture backlog, `bash bin/board bogusverb --backlog-file <f>` prints `usage: backlog.sh {board|next|get <ID-NNN>|...}` and exits 64. With no adapter, `board mirror` takes this path.
- Baselines: `bash tests/test-sync.sh` printed `326 passed in 5.75s`; the bash baselines are the lines in the Test plan table, taken from each suite's own last line.

Dry traces for the negative controls (nothing was run against a mutated tree; each is the planned mutation, the fixture read, the code path and the test that goes red):

- T1: mutation, add the word `Hermes` to `lib/sync/sync_core.py` in a temp copy; the scanner `grep -rilE 'hermes|notion|reminders|multica' <copy>/lib/board <copy>/lib/sync` returns that path; `tests/test-core-purity.sh` case "planted word is found" asserts the output contains `planted.py` and goes red when the scanner prints nothing. A second case plants `notion_named.sh` and asserts the `find`-based name scan reports it.
- T2: mutation, run the same CLI cases with the fixture adapter directory instead of the empty one; `board sweep --help` then contains the fixture's `sweep-opt` flag and `board mirror` is a verb; the case "absent differs from present" asserts the two outputs differ and goes red when they are equal.
- T3: mutation, delete the `opt hermes-target` row in a temp manifest copy; `backlog_sync.py --help` no longer lists `--hermes-target`; the frozen-flag loop names the missing flag and goes red.
- T4: mutation, change one `app` mode in the fixture manifest between the Python and bash reads; the parity diff is non-empty; the comparison goes red.
- Conformance: mutation, call `read()` on a source whose `.runner` was not replaced; the autouse guard raises `AssertionError("real transport")`; the case goes red instead of reaching a store.
- T6: mutation, remove the `hook body_expander` row from the notion manifest in a temp copy; the Hermes build gets `hooks["body_expander"] is None`; the assertion that the create body contains the page text goes red.

## Touches

- lib/adapters/**
- lib/sync/**
- lib/board/**
- lib/config/module-registry.md
- kit.toml
- docs/reference/project-structure.md
- CHANGELOG.md
- tests/test-adapters.sh
- tests/test-core-purity.sh
- tests/test-sync.sh
- tests/test-sync-dispatch.sh
- tests/test-board-mirror.sh
- tests/test-board-writeback.sh
- tests/test-board-states.sh
- tests/test-board-mirror-cleanup.sh
- tests/test-board-mirror-expire.sh
- tests/test-board-registry-env.sh
- tests/test-board-hermes.sh
- tests/test-board-sweep-mirror.sh
- tests/test-board-sweep-expire.sh
- tests/test-mega-box.sh
- tests/test-kit-contract.sh
- tests/test-meta-vmodel-dispatch.sh
- tests/fixtures/core-purity/**
- tests/fixtures/board-sweep/**
- lib/mega/mega.sh
- lib/session/handoffs.sh

## Decision Log

- DEC-A: adapters live in `lib/adapters/<name>/`. Why: `~/.claude/dwarves-kit` links `bin`, `lib`, `hooks` and `kit.toml` only and `install.sh` copies `lib` and `bin`, so a new top-level directory such as `integrations/` is not reachable on this host or in a pinned install; `lib/adapters` is outside both core roots, so the row's grep comes back empty. Rejected: `integrations/<app>/` (unreachable), `lib/sync/adapters/` (inside the grep scope).
- DEC-B: enablement is by use, not by a new enabled list; `[adapters] dirs` only says where to look. Why: an off-by-default list breaks the hourly sweep at merge, an on-by-default list adds nothing. With an empty adapter directory, core works and the connectors are absent, which T2 pins.
- DEC-C: `adapters.dirs` resolves root-only. Why: it selects code that runs, and a project `.kit.toml` rides inside an untrusted pull request; same rule as `multica_url` and `multica_token_ref`.
- DEC-D: GitHub becomes a fifth adapter. Why: same interface, one file plus its test, and it removes the only reason to keep a `sources/` package in core.
- DEC-E: the dated records (`lib/sync/docs/proof-of-done.md` and `lib/sync/docs/specs/SPEC-001` to `SPEC-004`) move untouched to `lib/adapters/docs/`. Why: the literal grep must return nothing, and a dated record is never reworded; `spec-find` resolves any `*/docs/specs/`, so they stay findable. The alternative, a purity exemption list for five paths, would leave the row's literal command non-empty.
- DEC-F: the inbox heading becomes `### Intake inbox` for new sections and any existing `### <Word> inbox` still receives rows. Why: the string `### Reminders inbox` is in live boards, so it must keep working, and core may not carry the word. Cost: a board with a hand-written `### Triage inbox` before the intake section would collect intake rows; the first match wins and a test pins it.
- DEC-G: `board status` (mirror staleness and its `--with-mega` rollup) goes with the Hermes adapter. Why: the verb reports the bridge snapshot; `board --with-mega` stays in core for the plain rollup. With no Hermes adapter `board status` is an unknown verb.
- DEC-H: the Hermes relay gets the Notion page-body expander through a loader-passed hook, not a core import. Why: core must not know that one adapter feeds another, and the hook degrades to `None`.
- DEC-I: sweep legs have two phases (`after-sync`, `last`). Why: it reproduces today's order exactly (mirror, expire, digests, health, link check), so log text and order are byte for byte.
- DEC-J: one PR, one commit per task. Why: the host runs the checkout, so each merge is live; one PR gives one revert.
- DEC-K: `describe()` and the inbox heading are the only visible text changes; the digest parser keys on the `+ board`, `~ board` and `✓ board` lines, which do not change.
- DEC-L: the loader is core code in `lib/sync/` (`adapters.py`, `adapters.sh`), not a new module under `lib/`. Why: `lib/sync` already owns the engine, and a new top-level module would need a `tool.toml` and a row in the kit contract.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)

<!-- provenance: ID-937, SPEC-386 (co-located specs), SPEC-243, SPEC-004 (the Notion pull record moved under lib/adapters/docs) -->
