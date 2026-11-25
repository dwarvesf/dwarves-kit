# board sync (backlog-sync)

Two-way sync between an adopted repo's kanban `BACKLOG.md` (the hub, source
of truth) and its spokes. A spoke is an app behind the adapter interface: a
task app, a note app, a kanban, an issue tracker. This directory is the
engine, the planner and the sweep; it names no app. Each app lives in
`lib/adapters/<name>/` with its own manifest and README, and the contract
every adapter follows is `lib/adapters/README.md`. Registered kit module `sync`
(stage: Shape, formerly Specify) at `lib/sync/`; front door is the `board sync`
verb, so every adopted repo's `_meta/board` shim already reaches it. Design:
`lib/adapters/docs/specs/SPEC-001-multi-source-sync.md` (subsystem-local). Spokes plug
in per repo via the `[sync]` section of `.kit.toml` (see below); no `apps`
entry, no sync, that's the whole plugin mechanism. Boundary with the one-way
`bridge` cockpit mirror is recorded in `lib/config/module-registry.md`.

```
                      _meta/BACKLOG.md  (hub)
                              |
        spoke A         spoke B         spoke C        ...   one adapter each
        (lib/adapters/<name>/: manifest + adapter.py + its transport)
```

Each app syncs independently: three-way merge against a per-spoke snapshot
in `<sync state dir>/<source>.state.json` (`config data path state backlog-sync`). On conflict the board wins.
A spoke-side deletion tombstones the row (mirroring stops; the board is never
touched). New spoke items without an `ID-` prefix become queued rows in an
intake section and get retitled/keyed with their assigned ID. The section
heading comes from the adapter that supplies one (manifest `const
inbox-heading`); with none installed a new section is `### Intake inbox`, and an
existing section with another heading keeps receiving rows.

An archive pass moves a closed row out of `BACKLOG.md`, so the planner stops
seeing it and its card used to stay open forever. A linked card now closes
when its id sits in the board archive with a closed status (`shipped`,
`dropped`, `done`, `resolved`). The archive is `BACKLOG-archive.md` beside
the board, or `sync.archive_file` in `[sync]` for a repo that keeps it
elsewhere. Evidence must be positive: an id missing from both files keeps its
card open and logs the orphan note, because a truncated or half-merged board
read would otherwise close every linked card on every spoke. A relative
`sync.archive_file` resolves against the board's own directory, never the
process cwd. More than 20 archive-driven closes in one tick means a bulk
archive pass, so the whole batch is refused with a note;
`--allow-archived-closes N` is the one-run override.
The snapshot drops a card's map entry once its row leaves the board, so after
the first tick the card's `ID-NNN` title prefix is its only link. A card
linked that way closes too, but only when its title text agrees with the
archive row. A card already done whose row sits in the archive closed is
settled on both sides: no write and no orphan note. The page stays in the
spoke with its closed status; the sync never trashes it.

**Ownership guards.** The sync carries a human decision and never makes one.

- A shipped or dropped row is never reopened from a spoke. An open spoke item
  on a closed row is a stale copy: the plan closes it (a note says so) and
  writes nothing to the board. Active rows stay two-way.
- Tag filters (`only_tags`, `skip_tags`) read the item cell and the notes
  cell. Titles compare without `#tags`, so a tag in the item cell never reads
  as a retitle; how an app carries tags is in its adapter README.
- Intake dedupe ("title already on board") looks at rows still in play. A new
  item titled like a shipped or dropped row is new work.
- `intake_skip_re` is searched against `title + "\n" + body` (MULTILINE), so
  `^thread: ` still anchors on a body line and `^\[to:` matches a title.

## What each app can hold

Each adapter README has its own table of what the app holds (title, status,
notes, tags) and where it is frozen or one-way by the app's own capability.
The planner treats an app by its mode, declared in the manifest:

| Mode | Reads | Writes | Notes |
|---|---|---|---|
| `two-way` | yes | yes | three-way merge against its snapshot; filter keys `<app>_only_tags`, `<app>_skip_tags`, `<app>_intake` |
| `create-only` | no | on create only | a push that never edits what a team member changed; filter keys `<app>_only_tags`, `<app>_skip_tags` |
| `pull-only` | yes | no | read-only intake into queued rows; runs alone in its own invocation, takes no filter |

Each adapter that ships with the kit has its own directory under
`lib/adapters/`. A new one is one new directory and no edit here.

## Run

```
_meta/board sync                     # from any adopted repo: all configured spokes
_meta/board sync --dry-run --apps <app>
```

Configure spokes in the repo's `.kit.toml` `[sync]` section (the ADR-0034
config layer; keys declared kit-wide in `kit.toml`, registered in
`lib/config/module-registry.md`). An app plugs in by appearing in `apps` (legacy aliases: `surfaces`, `sources`)
and filling its `<app>_*` keys; CLI flags override. The keys of each app are in
its adapter README:

```toml
[sync]
apps = "<app>,<app>"      # adapter names; no default
```

Resolution happens in `board.sh cmd_sync` via `kit-config.sh` (the one TOML
reader); the python engine takes flags only and reads no config file. The
adapter manifests (`lib/adapters/*/adapter.tsv`) declare every other flag: one
engine flag per `opt` row, one environment secret per `secret` row, one set of
filter keys per `app` row. Core flags: `--apps a,b` · `--backlog PATH` ·
`--archive-file PATH` · `--state-root PATH` · `--dry-run` · `--filter app:key=value` ·
`--scope-exit-cap N` · `--allow-scope-exit` · `--allow-flips` ·
`--allow-archived-closes N`. State snapshots live per board at
`<sync state dir>/<board-slug>/<source>.state.json`.

An app name no adapter provides ends the run with `no adapter provides <app>
(searched: <dir>)` before the lock, and an engine run with no `--apps` ends
`backlog_sync: no apps (--apps)`. The adapter directory is `lib/adapters/` of
the running kit, or `KIT_ADAPTERS_DIR` (an absolute path) for tests and
extensions; `board help` prints the one in effect.

### Scheduled runs (cron)

`board sync` is manual by default. Set `mode = "cron"` in a repo's own
`.kit.toml [sync]` section and install a per-repo LaunchAgent via
`lib/sync/deploy/macos/install` (macOS; kit board ID-289) so it runs
unattended:

```toml
[sync]
apps = "<app>"
mode = "cron"
interval_secs = 3600   # optional; default 3600 (hourly)
```

```
bash lib/sync/deploy/macos/install --repo <this repo>            # dry-run
bash lib/sync/deploy/macos/install --repo <this repo> --apply     # loads it
```

The installed job re-checks `mode` on every scheduled run, so flipping it
back to `"manual"` makes the next run skip cleanly rather than keep syncing.
See `lib/sync/deploy/macos/README.md` for the gate (`mode` must be exactly
`cron`, refused otherwise), the service graph, log shape, and BTM/TCC
details.

### Sweep: many boards, one scheduled run

The cron installer renders one LaunchAgent per repo. An operator with many
boards on one host wants one job instead. `board sweep` is that job: one pass
over a registry (the `boards.txt` that `board all` renders from), all in
`lib/sync/sweep/`.

```
board sweep --registry boards.txt --poster ./post
board sweep --registry boards.txt --dry-run          # plan the whole sweep, write nothing
board sweep verify --registry boards.txt --run "board sweep ..."    # prove no board changed
board sweep verify --last-tick [repo]                # read the newest tick from the log
```

```
registry row ──▶ board sync (own [sync] config) ──▶ digest parse ──▶ board publish
                       (per repo, in order)          (state file)     (only if the sync wrote)
                                │
                                ▼  after the loop
   adapter legs (after-sync) ──▶ one digest post per cluster ──▶ health leg ──▶ adapter legs (last) ──▶ on-clean hook
                                          │
                              your --poster command
```

Each repo's own `.kit.toml [sync]` still decides whether it syncs; a repo with
none logs a skip. The kit does not know your chat service, your host auth, or
which checkouts you keep fresh, so those arrive as hooks, never as defaults:

| Flag | Contract |
|---|---|
| `--preflight CMD` | Runs once as `CMD <registry>` before the loop. A nonzero exit marks the sweep failed. |
| `--poster CMD` | Delivers one digest payload: JSON on stdin, exit 0 means delivered, stderr is the failure reason. |
| `--on-clean CMD` | Runs only when the sweep ended clean and was not a dry run (a liveness ping, say). |
| `--repo-arg NAME=ARG` | One extra argv item for NAME's `board sync`, repeatable. |
| `--sync-token-repo NAME` | NAME's `board sync` receives `GH_TOKEN` from `BOARD_SWEEP_TOKEN`. |

`BOARD_SWEEP_TOKEN` is the one credential handoff. The sweep reads it once,
removes it from its environment, and passes it per call to exactly two legs:
the `--sync-token-repo` syncs, and every `board publish` through a
`GIT_ASKPASS` helper, so it never rides argv and no spoke plugin sees it.

**Digest.** Each repo's `board sync` output is parsed into a change set (the
grammar is `sync_core.describe()`'s). Repos that share a `rail=<name>` column
merge into one cluster and post once. `--cluster-map cluster=rail,...` names
the clusters and limits the valid rails; without it every rail in the registry
is a cluster named after itself. A post fires only when something changed, its
key is a hash of the plain change tuples, and a failed post carries the change
forward: the next payload merges it, shows the redacted reason as
`carried_error`, and raises severity to `warn`. The payload is neutral:

```
{cluster, rail, key, severity: info|warn, title, fields: [{name, value}], carried_error?}
```

`--crit-prefix P` makes a payload `crit` when an adopted row's title starts
with P. The poster maps severity to its own marks and colors.

**Adapter legs and flags.** An adapter may add sweep flags (manifest `sweep-opt`
rows) and legs (manifest `leg` rows). `board sweep --help` lists the flags of
the adapters installed, each leg runs as `"$BASH" <script>` with the `SWEEP_*`
environment (`SWEEP_NAME`, `SWEEP_BOARDS`, `SWEEP_REPO_ROOT`, `SWEEP_DRY_RUN`,
`SWEEP_BOARD_CMD`, `SWEEP_HEALTH_BIN`, `SWEEP_HEALTH_STATE`) and the
`sweep-opt` variables, and a leg is in one of two phases: `after-sync` (after
the per-repo loop, before the digest posts) or `last` (right after the health
leg). A flag no adapter and no core case accepts ends `board sweep: unknown
arg: <arg> (adapter dir: <dir>)` with exit 64, before any sync. A leg that
runs and fails is observational and never changes the sweep's exit code; a
leg whose script is missing fails that leg only, after the per-repo syncs
ran, and ends the sweep with exit 1. INT or TERM during a leg signals the
leg, waits for it, and ends the sweep with 130 or 143 and nothing after it.
Which legs ship, and what each does, is in the adapter README.

**Health digest.** The change digest says what moved. `board health` (also the
sweep's `--health` leg) says whether the boards and the sync legs are healthy,
on a slow clock, through the same `--poster`. Every sweep tick records each
sync and mirror outcome (spokes seen, rc, error lines) into
`health-state.json` in the sync state dir; `--health` then builds one payload
per cluster once `--health-every-days` (default 3) has passed since its last
delivered post. A failed post is not stamped, so it retries next tick and
rides `carried_error`. The word for the mirror target in these lines is the
`mirror-label` constant an adapter supplies (fallback `mirror target`).

| Line | Source |
|---|---|
| extra | each stdout line of `--health-line CLUSTER=CMD`, for facts only the operator knows; a line that opens with the warning mark counts as a fault |
| hub | the one hub named by `--health-hub CLUSTER=NAME`: `NAME: <active> active, <parked> parked · <label> mirror <n> open = hub`. Rows come from `git blame` on the origin copy of the board; the mirror count is the open cards of kanban board NAME whose body says `origin: NAME:`. A mismatch is a fault line instead. |
| board | each kanban board named by `--health-board CLUSTER=SLUG` (reader: `--health-kanban CLUSTER=CMD`, a wrapper over the mirror target's kanban CLI): open cards with their status, stale cards, tickets created since the last delivered run |
| archived | cards archived since the last delivered run, one total; omitted on a baseline run |
| fault | one line per kanban board over the triage threshold (`--health-triage-open`, default 20 cards, or `--health-triage-days`, default 14 days for the oldest), three at most, then `+N more boards over threshold` |
| sync | per spoke and the mirror leg, ok or failed, from the tick records |
| attention | failed legs, FLAPPING ids, a carried change-digest failure, a sweep record older than six hours |

One short line per item. Only real faults carry the warning mark; other repos'
hubs and boards get no line unless they trip the triage threshold, and their
counts stay in the payload's `data`. `--health-faults-only C` keeps only the
fault and attention lines for cluster C.

The payload is the digest payload plus `kind: "health"`, `period_days`,
`next_due`, `attention`, and one display line per field:

```
{kind: "health", cluster, rail, key, severity: info|warn, title, period_days,
 next_due, attention, fields: [{name, value}], data, carried_error?}
```

`attention` is true when something needs a human: a failed sync or mirror leg,
a FLAPPING id, a carried post failure, an unreadable kanban reader, a hub
that differs from its mirror, a board over the triage threshold, a stale
sweep record. A cluster named by `--health-quiet C` posts nothing while
`attention` is false; the run is still stamped. Two limits: a kanban card has
no updated-at field, so "stale" there means the latest of created, started and
completed is older than the threshold, and the first run has no archived
baseline, so it reports no archived count. Tests: `tests/test-board-health.sh`.

**Daily brief.** `board brief run` is the one message an operator reads each
day, built on the health engine above (its source flags, its `--config` file,
its health state). It reads like a report: a `▌` lede, one `**🙋 Your call**`
block of items, one `▌ Handled by bots:` sentence line. Every Your call item
says what to do (bold) and what happens if it is ignored.

| Part | Source |
|---|---|
| lede | `▌ Two things wait on you today: a memo draft that parks tonight, a new alert kind to triage. The bots handled the rest.` Count words One, Two, Three, else digits; up to two item ledes, then `and N more`; an item without a lede counts but adds no phrase. No items and no error: `▌ Nothing waits on you today. The bots handled everything.` |
| Your call | items, most urgent first: those with a `due` epoch (or a ` by <Day D Mon>` date in a plain line) nearest first; incident rows ("Triage or map" before "Close"); the hook's explicit `decisions`; other 👉 items by `wait_days`; hub/mirror drift; board triage, longest wait first; the items an adapter's `brief_decisions` hook adds last. Three items show, the rest is `+N more`. |
| Handled | `▌ Handled by bots: ...` joins the `--line` hook sentences that open with 🤖, `N incidents are with chonky.`, and `sync and bots ran clean.` or the error form. An agent fault is never a decision. |
| Details | a follow-up field, `ℹ️ Details`, on Mondays in Vietnam time (or under `--show-boards`): the board lines, the other `--line` lines, the hook's `details`, the bot counts. Any other day it is dropped unless an error exists, then it holds the error lines only. |

An item is `• `[tag]` [title](<url>)` and its lines. Item sources:

- A `--line` hook line `👉 {json}` with `{"tag", "title", "url", "lines": [...], "lede", "due": epoch, "wait_days": N}`. Any other text after 👉 stays one plain line.
- An incident row with an `action`: tag `quiet Nd` or `firing`, the linked id and label, `fired Nx on <host>. **close the ticket.**` (Close) or `**triage it or add a rule.**` (Triage or map), and what happens if ignored. Without an `action`: one line with the closing question in bold.
- A board past its triage threshold: tag `waiting Nd`, `N cards wait in <board> triage`, up to two quoted titles of 40 chars (the `untrusted ` marker dropped), `**move each card to ready, blocked or done.**`
- Drift and the lines an adapter's `brief_decisions` hook returns: one plain line, no tag. A hook that raises, fails to import or lacks the function adds one attention line, `report hook <adapter> failed: <ExceptionClass>`, and the brief still exits 0; the full text goes to stderr.

`severity` is `warn` only when Your call is not empty or an error exists. The
payload carries `footer_tail` (true on a Details day) and `date_label` and
`next_due_label` (`Sat 7 Nov`) for the poster.

The incident hook prints one JSON object, every key optional, so any operator's
incident source fits:

```
{"open": [{"id", "label", "host", "url", "age", "firing": bool, "needs_you": bool, "question", "action"}],
 "decisions": [{"id", "url", "question"}], "bots": {"auto-resolved": 3},
 "faults": ["line"], "details": ["line"]}
```

An `action` (an imperative, 40 chars at most) turns a needs-you row into the item
above; its facts are the question's `fired Nx, quiet Nd` text without the trailing
hint or question. Ids and urls are masked links with the preview suppressed
(`[ID-538](<url>)`): a board row links to its line in the GitHub copy of the board
(from the repo's origin remote); an id with no URL is inline code; a host after
`@` is inline code. `--main-chars N` (default 1250) keeps the main message under
the poster's cap: over it the Your call items past the first collapse into the
`+N more` line.

The payload is `kind: "brief"`: the health payload shape with `date`, one
display line per field for the main message, and `details` (a list of lines)
for the follow-up message. The poster decides how the follow-up lands (a thread
reply where the rail has threads, else a second short message); a failed details
post never fails the main one. Under `--dry-run` and `--no-state` the hook runs with
`BOARD_BRIEF_READ_ONLY=1` and must write nothing. `--decisions-only C` makes cluster C post only
when a decision exists, and then only the decision lines. A failed post is not
stamped, so it stays due and rides `carried_error`. Brief state lives in the
health state file under `brief`.

`board health run` and `board brief run` read their flags from `--config FILE`,
else `$DWARVES_BOARD_CONFIG`, else the file `config data path config board.json` prints: JSON with
`common`, `health`, and `brief` sections, each key a long flag with `-` as `_`
(a list repeats the flag, `true` is a bare flag). Command-line flags come
after the file. This is what lets an agent run `board health run --dry-run`
with no flags of its own. Tests: `tests/test-board-brief.sh`.

**Exit code.** 0 when every sync, publish, and preflight leg was clean (and no
leg script was missing). The digest, health, and adapter legs that run and fail
are observational and never flip it.

### Bootstrap per app

Each adapter README says what a first run creates or needs. A secret an adapter
declares (manifest `secret` row) resolves from a 1Password ref in `[sync]` at
invocation (Keychain-cached `secret-cache-read`, raw `op read` fallback) and
reaches the engine through an environment variable, never argv.

## Cockpit bridge verbs are a separate engine

The bridge verbs of the board (`mirror`, `status`, `writeback`, `mirror-cleanup`
and the link verb) are provided by an adapter, not by this engine: the manifest
maps each verb to a script, and `lib/board/board.sh` runs it. The bridge is a
many-source to one-cockpit channel, distinct from the per-repo two-way spoke
sync above, and its text is in the adapter README that ships it.
`cockpit.py` keeps only what live spokes import (the untrusted-content
markers, `redact_secrets`, `repo_root_of`); a Python port of the extract and
diff (the old `--engine sync` dry run) was removed because it never ran live
and duplicated the bash engine.

## Tests

```
tests/test-sync.sh                       # kit wrapper: pytest over lib/sync/tests (test_core.py, test_cockpit.py and more) and lib/adapters/tests
lib/adapters/tests/test-adapters.sh      # the manifest grammar, both readers, the frozen lists, the verb lookup
tests/test-sync-characterize.sh          # the golden capture of every entry point, diffed against deltas.txt
tests/test-core-purity.sh                # core names no app
```

No network in pytest; the live proofs (bootstrap, reverse flips, inbox,
idempotence, per spoke) are recorded in `lib/adapters/docs/proof-of-done.md`.
