# lib/adapters: connectors behind one interface

A connector to one app (a task app, a note app, a kanban, an issue tracker) is an adapter. Core `lib/board` and
`lib/sync` name no app; they read the manifests in this directory and call the adapters through the interface
below. Adding an app is one new directory here. Removing one is deleting its directory. The doctrine is
`docs/decisions/0041-standalone-doctrine.md` ("Connectors are adapters behind one interface").

```
  [sync] apps = "a,b"  (config picks the apps by name)
        |
  core: lib/board/board.sh   lib/sync/backlog_sync.py   lib/sync/sweep/*
        |  reads manifests only            |  imports an adapter module only when something names it
        v                                  v
  lib/sync/adapters.sh  <--- same grammar ---> lib/sync/adapters.py
        |                                  |
        +---------> lib/adapters/<name>/adapter.tsv  (the manifest)
                    lib/adapters/<name>/adapter.py   (the entry module)
```

An adapter is a directory `lib/adapters/<name>/` with a manifest `adapter.tsv`, an entry module `adapter.py` when it
provides an app or a hook, its own code, and a README. Directory names match `^[a-z][a-z0-9-]*$`. A directory with no
`adapter.tsv`, or whose name starts with `.` or `_`, is skipped (so `tests/` and `docs/` are not adapters).

## IN

What an adapter receives.

**The manifest** `adapter.tsv`: tab separated, UTF-8, one row per line. The first field is the row kind. `#` in column 1
starts a comment, blank lines are skipped, CRLF is read as LF. No row has an empty field (use `-` as a placeholder
where a field is optional by meaning). The rows:

| Row | Fields after the kind | Meaning |
|---|---|---|
| `app` | `<app> <mode>` | an app name and its mode: `two-way`, `create-only` or `pull-only`. The name keys `<app>.state.json`, the filter keys and the config keys; it never changes. |
| `opt` | `<flag> <key> <scope> <help...>` | engine flag `--<flag>`, filled from `[sync] <key>`, handed to `build` as `opts[<key>]`. `scope` is `-` or `root` (`root`: the operator and kit-root files only, never a project `.kit.toml`). `help` is the argparse help text; the loader doubles any `%`; a help of `-` means the flag has no help text. |
| `secret` | `<ENV> <key>` | before the engine starts, `board sync` resolves the 1Password ref in `[sync] <key>` into env var `<ENV>` (operator and kit-root files only). The secret reaches the engine through the environment, never argv. |
| `verb` | `<verb> <script> [<arg>...]` | `board <verb> ARGS` runs the script with the manifest args first, then `ARGS`. A `.py` script runs under `python3`, anything else under `bash`. |
| `sweep-opt` | `<flag> <ENV> <help...>` | `board sweep --<flag> VALUE` is accepted, exported to the legs as `<ENV>`, and listed in `board sweep --help`. |
| `leg` | `<phase> <script>` | a sweep leg. `phase` is `after-sync` or `last`. The leg name is the script basename without its extension. |
| `const` | `<name> <value...>` | a constant core reads from the first adapter that declares it. Defined: `mirror-label` (the display word for the mirror leg in health and brief lines; fallback `mirror target`) and `inbox-heading` (the heading line of a new intake section; fallback `### Intake inbox`). |
| `hook` | `<name>` | the entry module exports a function `<name>`. Defined: `guard`, `body_expander`, `brief_decisions`. |

**The entry module** `adapter.py`, required when the manifest has an `app` or a `hook` row:

```python
def build(app, opts, ctx):
    """Return the source object for `app`, or None to skip it this run (print the reason).
    opts: dict, key -> str or None, for every opt row of every adapter.
    ctx:  SimpleNamespace(state_path=Path of <app>.state.json, project_root=str or None,
          hooks=object with .get(name) -> callable or None)."""

def guard(names, opts):           # hook: raise SystemExit to refuse the run
def body_expander(body):          # hook: a body-to-body function another adapter's source calls
def brief_decisions(health, cluster, first_cluster):   # hook: [(sortkey, text), ...] for the daily brief
```

The source object is the duck type the engine already runs: `name`, `sync_fields`, `read() -> list[dict]`,
`apply(plan, assigned, rows_after)`, and optionally `create_only`, `pull_only`, `skip_kw`, `binding`,
`preflight(plan)`, `preview(plan)` and `bound_marker_re` (a compiled regex whose group 1 is the remote id a board
row's notes already carry, so the planner binds that row instead of creating a duplicate).

**Verb argv.** A verb script gets the manifest args, then the caller's args. `KIT_LIB` (the absolute `lib/`) is set for
out-of-tree scripts; scripts that ship in the kit derive it from their own location and ignore the environment.

**Leg environment.** A leg runs as `"$BASH" <script>` with `SWEEP_NAME`, `SWEEP_BOARDS`, `SWEEP_REPO_ROOT`,
`SWEEP_DRY_RUN` (0 or 1), `SWEEP_BOARD_CMD`, `SWEEP_HEALTH_BIN`, `SWEEP_HEALTH_STATE`, `KIT_LIB` and every `sweep-opt`
variable (empty when not given). The runner sets no sweep token, no `GH_TOKEN` and no `GIT_ASKPASS` for it; whatever
the sweep itself inherited from its caller passes through, as it did to the legs before they moved.

**The directory.** The loader scans `$KIT_ADAPTERS_DIR` when it is set (an absolute path; empty or relative exits 1) and
otherwise `lib/adapters/` of the running kit, found from the loader file's real location, never from cwd,
`KIT_PROJECT_ROOT`, `DWARVES_KIT` or a config value. `KIT_ADAPTERS_DIR` replaces the in-tree directory; an extension
directory symlinks the built-ins it wants. A missing directory means zero adapters, silently. An unreadable one is a
load error.

**Trust.** `KIT_ADAPTERS_DIR` has the trust of `PATH`: it selects code that runs with the caller's whole environment.
Never point it at a path a project or another account can write. A project can set an environment variable through
`.claude/settings.json` `env`, `.envrc` and mise, so a repo you sync may set this one; do not run a sweep or a sync in
an environment you do not control. The grammar checks below guard against accidents. The trust boundary is who can
write the adapter directory.

**Load-time grammar.** Both readers (`lib/sync/adapters.py`, `lib/sync/adapters.sh`) check every row and fail with
`adapters: <file>:<line>: <what is wrong>`:

- `app`, `verb`, `flag` and the adapter directory name match `^[a-z][a-z0-9-]*$`; `key` matches `^[a-z][a-z0-9_]*$`; `ENV`
  matches `^[A-Z][A-Z0-9_]*$`, is none of `PATH HOME IFS ENV BASH_ENV SHELLOPTS BASHOPTS PS4 PROMPT_COMMAND CDPATH` and
  starts with none of `LD_ DYLD_ PYTHON KIT_ SWEEP_ BOARD_ GIT_ SSH_ OP_ NODE_`.
- Every script is a relative path with no `..` that stays inside its adapter directory, and is not a symlink. Existence
  is checked when the verb or leg runs, not at load. `adapter.py` must exist and must not be a symlink.
- An app, flag, key, ENV name, verb or `const` name declared twice, and the singular hook `body_expander` declared twice,
  are load errors naming the first declaration.
- An `opt` flag or key equal to a core engine flag or dest, a `sweep-opt` flag equal to a core sweep flag, and a verb equal
  to a core verb are load errors (the lists live in `lib/sync/adapters.sh`).
- An adapter with a `secret` row declares no `opt` of scope `-` whose key ends `_url`, `_host`, `_endpoint` or `_target`,
  so a project file cannot point a root-resolved secret at a host of its choice.
- An unknown row kind is ignored with one warning from the Python loader. A known kind with a bad field is an error.

A manifest error is global: one bad manifest stops every run that loads the registry. A broken `adapter.py` fails only
the runs that name it.

## OUT

What an adapter produces.

- The normalized item a source's `read()` returns: `{"rid": str, "title": str, "done": bool, "body": str, "status": str or None}`
  (a pull-only source adds `"marker"`). `apply(plan, assigned, rows_after)` writes the planner's decisions to the app and
  returns `{board id: remote id}` for the items it created. The planner (`lib/sync/sync_core.py`) owns the plan and the
  board text; a source never writes the board.
- State: `<app>.state.json` under the per-board state directory, `health-state.json` (keys `sync`, `mirror`,
  `hermes_links` stay as they are), the mirror snapshot and the markers each app already writes. None of these change
  name, shape or place when an app moves into an adapter.
- Hook results: `guard` returns nothing or raises `SystemExit`; `body_expander` returns the new body; `brief_decisions`
  returns `[(sortkey, text), ...]` where `sortkey` is a tuple of ints that sorts with the brief's own keys.
- The mirror-target reader contract. `board-health` and `board-brief` read a "mirror target" through two commands,
  `<cmd> boards list --json` and `<cmd> --board SLUG list --json`, and the `origin: <repo>:<id>` marker in a card body.
  A second mirror target must satisfy that reader contract.

## EXIT

- Engine (`backlog_sync.py`): 0 clean; 1 a refusal or a failed source (the bulk-flip breaker, a duplicate board id, no
  adapter provides a named app, a guard refusal, a mode mismatch, a hook provider that cannot be imported); 2 usage (no
  `--apps`, bad flags).
- Loader and reader: 1 with one line `adapters: ...` for a manifest error, an unreadable directory or a bad
  `KIT_ADAPTERS_DIR`; `no adapter provides <app> (searched: <dir>)` and `hook <name> from <adapter> failed: <error>` also
  exit 1. A missing directory is not an error.
- A verb script: its own exit code is the verb's. With no adapter providing the verb, `board <verb>` ends in `backlog.sh`'s
  usage line with exit 64, as any unknown word does.
- A sweep leg: 0 once it has printed its own result line, whatever the wrapped command returned. A non-zero exit means the
  leg itself broke; the sweep prints `leg <name> exited <rc> (non-fatal)` and goes on. A missing leg script fails the
  sweep (exit 1) after the per-repo syncs ran.

## How to add an adapter

1. Make `lib/adapters/<name>/` (or a directory of your own that `KIT_ADAPTERS_DIR` points at; symlink the built-ins you
   still want into it).
2. Write `adapter.tsv` with an `app` row, an `opt` row for each flag your `build` needs, a `secret` row if it needs a
   token, and a `const` or `hook` row if core should use one.
3. Write `adapter.py` with `build(app, opts, ctx)` returning the source object. Keep sibling module names unique across
   adapters (the loader refuses a sibling that shadows a module already loaded). Start each Python file with
   `from __future__ import annotations`.
4. Add a README with install notes and one invocation. Add `[sync] apps = "<app>"` to a repo's `.kit.toml`.
5. Nothing in core changes. `lib/adapters/tests/test-adapters.sh` and the conformance test read the manifests, so they
   cover the new adapter without an edit.

Tests live in `lib/adapters/tests/`. The dated specs and proof records of the connectors sit in `lib/adapters/docs/`.
