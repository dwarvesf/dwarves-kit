# 0041. Standalone doctrine: neutral defaults, data outside the code, modules that work alone

Date: 2026-11-25
Status: Accepted. Rules 1 and 2 rest on code that already shipped (PRs #1111, #1115, #1117). Rule 3, with its connector rule, is direction. Each section says which parts are true today.
Relates-to: ADR-0035 (durable ledger root, the run-log resolver this ADR leaves alone), SPEC-248 (operator config layer), SPEC-418 (one data root), `lib/config/data-path.sh`, `lib/config/kit-config.sh`, `lib/gate/boundary-lint.sh`

## Decision (one line)

The kit ships neutral defaults, a user's data lives outside the kit's code, and a module works alone and composes with the kit only through one thin adapter and one manifest row.

## Context

The kit is a public repo (`gh repo view dwarvesf/dwarves-kit` reports `PUBLIC`) that started as one operator's tooling. Three things leaked from that start: operator values hardcoded as defaults (a host, a handle, a monorepo name), runtime data written to paths each feature chose for itself, and modules that only make sense with the kit's core running. A stranger who installs the kit gets the operator's taste, writes state into places nobody can list, and cannot take one capability without the rest. Three PRs fixed the first two. This ADR names the rule behind them, so the next change cannot undo them quietly, and states the third rule that has no code yet.

The packaging research behind rule 3 compared spec-kit, BMAD, agent-os v3, superpowers, OpenSpec, Taskmaster and the Claude Code skill, MCP and plugin layers. It was removed from the tree in #1064; it lives in git history at `d63699ff` as `docs/research/2026-07-25-packaging-prior-art-refresh.md`. Its verdict, used below: plain files are the source of truth, the CLI only reads and writes them, one thin adapter per host, and the kit owns only the composition manifest. Its warning, also used: a pack that only works with the host's core running is a plugin wearing a standalone label.

## Rule 1. The kit ships neutral defaults

A default in code or in the shipped `kit.toml` is correct for a stranger with no setup. A value that names one operator, host, account or secret store is not a default. It goes in the operator's own `kit.toml`.

True today (PR #1111, merged 2026-11-09):
- Six keys moved out of code into the operator `kit.toml`, read with `kit_config_get_root` (operator file, then kit root, never the project `.kit.toml`; `lib/config/kit-config.sh`): `[session_report] url`, `host_id`, `hmac_key_cmd`, `hb_token_cmd`; `[stats] home_repo`; `[sync] notion_title`. Each ships empty or neutral in `kit.toml`. An empty `url` makes `session-report` exit 2 with one line; an empty `home_repo` drops the `Home:` line.
- `lib/gate/boundary-lint.sh` has a deny check (`deny_re`) over executable code and fixtures for the operator's host, handle, monorepo and 1Password vault names. `bash lib/gate/boundary-lint.sh` prints `boundary-lint: PASS` on this tree.

Not true yet:
- The deny check skips comment lines, Python docstrings, markdown and `docs/`. Operator handles still appear in comments (for example `lib/reflect/propose.py`, `lib/goal/megagoals.sh`) and in history records. That is accepted for comments; it is not accepted for a default.
- Only the four tokens in `deny_re` are linted. A new kind of operator value (a path, a channel id) is caught by review, not by a test.

## Rule 2. User data lives outside the code

Three places, no others:

| What | Where | Owner of the rule |
|---|---|---|
| Operator preferences and per-machine values | the operator `kit.toml` (`$KIT_CONFIG_OPERATOR` or `~/.config/dwarves-kit/kit.toml`) | `lib/config/kit-config.sh`, project beats operator beats kit root beats default; `kit_config_get_root` skips the project layer |
| Runtime state, cache and edited config files | one data root | `lib/config/data-path.sh` (`kit_data_path <kind> <name>`) |
| Knowledge the user wants to keep | context-kit's tree, named by `[knowledge] root` (operator or kit-root file only) | empty means repo-local `.claude/memory/` |

True today:
- PR #1117 (merged 2026-11-09) added `data-path.sh`. Order for one entry: its own env var, `KIT_DATA_ROOT`, the old path while it holds data and the new one does not, the operator `[data] root`, then the XDG default. A fresh HOME gets the XDG layout. A host with data at the old `~/.claude`, `~/.cache` or `~/.config` paths keeps using them until the operator runs `bin/config data move --apply` (dry run by default). `bin/config data` lists every path and how it resolved.
- `boundary-lint` has a DATA check: a legacy data path spelled in `lib/`, `hooks/`, `bin/`, `deploy/`, `install.sh` or the agent-facing prose in `commands/`, `skills/`, `agents/`, `integrations/` and `templates/`, anywhere except `lib/config/data-path.sh`, fails the lint. It skips `tests/`, `docs/`, fixtures, other markdown, comments and docstrings.
- PR #1115 (merged 2026-11-09) added the operator-layer fence. `tests/test-operator-pin.sh` fails any suite that reaches the config resolver without pinning `KIT_CONFIG_OPERATOR`, `XDG_CONFIG_HOME` or `HOME`, and fails a runner that stops pinning (`tests/run-all.sh`, `bin/test-affected`). `tests/test-clean-room.sh` installs into a bare HOME under `env -i` with no `op`, `direnv` or `gh` login, runs onboard-detect, adopt and a gate cycle, and asserts writes land only in the sandbox and no output names the maintainer.

Not true yet:
- "One data root" holds for state, cache and config. Run logs resolve through their own function, `kit_resolve_log_dir` (ADR-0035), with its own knobs. Both sit outside `~/.claude` on a fresh install. Merging the two resolvers is not decided here.
- A host with old data still writes under `~/.claude`. That is deliberate (no cursor resets) and ends only when the operator moves the data.
- The clean-room test ran on macOS only and does not cover the plugin install path.

## Rule 3. A module runs alone and composes when installed beside others

A module is a tool a developer can use with no kit present. The kit adds composition (the gate ledger, the lane classifier, the board) when the tool is installed beside it. Deleting the kit leaves the tool working. Deleting the tool leaves the kit missing one capability, never broken.

```
  standalone tool                                  kit core (composition only)
  +------------------------------+                +----------------------------+
  | README with contract block   |                | lib/config/modules.tsv row |
  | artifact file + schema (API) | <--reads--     | gate ledger, lanes, board  |
  | bin entry, own exit codes    |   --shim-->    | calls the shim, reads the  |
  +------------------------------+   (1 command)  | artifact, never the code   |
                                                  +----------------------------+
```

What a module owes to count as standalone (each item names its check):

1. **Contract block.** The module README has an IN block (argv and stdin), an OUT block (artifact file and its schema) and an EXIT block (what each exit code means). Check: the three headings exist in `lib/<module>/README.md`.
2. **The API is the artifact schema.** Another tool reads the artifact file. It never sources the module's shell functions or imports its internals. Artifacts are plain files (markdown, jsonl, tsv) a person can `cat`. Check: no file outside the module sources or imports a path inside it.
3. **Thin adapter.** Kit integration is one command shim (`bin/<name>`) plus one row in `lib/config/modules.tsv` (module, default, hooks, clis). The shim locates the tool and execs it; a missing-dependency message is allowed, other logic is not. Check: the shim is a few lines and holds no parsing, no branching on arguments.
4. **The delete test, both ways.** With the kit deleted, the documented standalone command still works. With the tool deleted and its adapter (shim and manifest row) left in place, the kit still runs, reports the one capability as missing, and its own suites pass except that module's. Check: a script that does both in a scratch copy.
5. **Own docs.** The README names the install path and one standalone invocation that needs no kit file.

True today:
- `lib/config/modules.tsv` is the one module table. `bin/stats` has the shim shape (it checks for `uv`, then execs `lib/stats`), but the `stats` row of the table has `-` in its `clis` column, so the shim and the row are not tied together by the table today.
- The two modules that #1111 made read operator config degrade instead of breaking when the kit is absent. `lib/session/observe/bin/session-report` (`kit_root_get`) and `lib/stats/src/stats/config.py` (`home_repo`) shell out to `lib/config/kit-config.sh`; if the reader is missing or fails they use the default (empty), so only the flags and env vars remain. That passes the delete test for running, but the operator-config path is a kit dependency, and a standalone module needs its own documented way to take the same values (flag or env var).
- `tests/test-clean-room.sh` proves a stranger can install the kit with none of the maintainer's setup. It does not prove any module works without the kit.

Direction, not built: items 1, 2, 4 and 5 have no check in the repo. No module README carries an IN, OUT and EXIT block (an `rg` for those headings over `lib/*/README.md` and `lib/*/*/README.md` finds none), and nothing stops one module sourcing another's files. The first module extracted under these rules is the test of the rules; a rule that fails there gets fixed here.

Left out on purpose: a distribution channel decision, two spec-template acceptance criteria that would mechanize item 4, and a spec-validate lens question. None is needed to state the rule. Add them when the first extraction wants them.

### Connectors are adapters behind one interface

A connector to a specific app (Hermes, Notion, Reminders, Multica) is an adapter behind one interface, loaded by name from config. Core code names no app.

```
  kit core (board, sync_core)  -->  one interface  <--  adapter: reminders
        names no app                 read() / apply()    adapter: notion
              ^                                          adapter: hermes
              |                                          adapter: multica
   [sync] apps = "..." (config)  ---- picks adapters ---->
```

The interface is the one most adapters already share: `read()` returns normalized items (`rid`, `title`, `done`, `body`, `status`, per the `sync_core.py` module docstring) and `apply(plan, assigned, rows_after)` writes the plan back. Six of the seven classes under `lib/sync/sources/` define both (`rg -n "def (read|apply)" lib/sync/sources/*.py`). `notion_taskboard_pull.py` has `read()` only, and `notion_taskboard.py` `apply()` takes an extra parameter, so the interface needs one written definition before it can be called one interface. The check: a search of core files for an app name finds hits only under `lib/sync/sources/` and in the config table.

True today: `[sync] apps` in `kit.toml` selects apps by name, each app has its own file under `lib/sync/sources/`, and `lib/sync/sync_core.py` describes itself as the source-agnostic core.

Not true yet: `lib/sync/backlog_sync.py` imports each source class by name (lines 39 to 47) and builds them in an if/elif factory (lines 329 to 388). `lib/sync/sync_core.py` still names apps in code, not only comments (the `notion-page:` pull marker regex), `lib/sync/sweep/board-hermes` is a Hermes-only core script, and `lib/board/board.sh` names these apps on 78 lines. The interface is a convention in code, with no written definition and no test that a new adapter can load without editing core. Closing that gap is the next piece of work and must cite this ADR.

## Open-source readiness: the obligation

This ADR states the obligation. It does not run the audit.

Done:
- The kit's own board, staging buffer and mega-goals moved to the private `dwarves-kit-internal` repo. `CLAUDE.md` ("Repository structure") and `AGENTS.md` (task loop, step 0) say so; `.gitignore` ignores `/_meta`; `git ls-files _meta` lists nothing on this tree; a maintainer's `_meta` is a local symlink to the private repo. Board commands run on a clone without it and print one line naming the missing file (#1067).

Still required (the repo is already public, so these are overdue, not preparatory):
1. **Secrets and history audit.** A scan of the full git history, not only the tree, for credentials, account ids, private hostnames and client or personal data. The tree holds no record that one ran. #1111 states "History is untouched": older commits still carry the operator values rule 1 removed from code, and #1064 pruned old records from the tree only. The audit decides, per finding, whether to accept it or rewrite history; any rewrite is irreversible, needs the operator, and is not authorized by this ADR.
2. **Internal-state check.** Confirm no tenant, client or Dwarves-internal reference remains in tracked files beyond the comments and history named under rule 1.
The wider readiness work (contributor files, README claims against reality) belongs to the open-source readiness row and is not restated here.

## Consequences

- A new default that names one operator fails `boundary-lint` when it sits in executable code. A new runtime path outside `data-path.sh` fails it too. A suite that reaches the resolver without pinning the operator layer fails `test-operator-pin`.
- Work that extracts a module, or adds a connector, cites this ADR and answers the five items and the connector check above. Until the checks exist, the answer is a review note, and the PR says which items are unchecked.
- This ADR changes no code and no config key. It adds no hook, lint or test.
