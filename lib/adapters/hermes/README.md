# Hermes adapter

Two-way sync between the board and a Hermes kanban, over `hermes kanban` verbs only. The adapter name and the app name are both `hermes`. The contract it follows is `lib/adapters/README.md`.

## What it holds

| Field | Hermes |
|---|---|
| title `ID-NNN · item` | frozen at create (the CLI has no edit verb) |
| status | create = `todo`; `complete` maps to shipped, `archive` maps to dropped or parked; moves between active states are reported as skipped, not attempted |
| notes | `--body` at create, frozen |
| #tags | in the body text |

Hermes has no title or body edit verb and no reopen verb, so those cells say "frozen" and "n/a" by capability, not by choice. The reverse direction reads a task `done` as board shipped and `archived` as board dropped.

The store IS the board. A fresh `HERMES_HOME` initializes on first create. Writes go through `hermes kanban` verbs only, so compare-and-set, events and Discord notify stay intact; the sqlite file is never written directly. Seeds carry `--idempotency-key bls-ID-NNN`, so a repeated create is a no-op.

Instance selection is three separate axes: `hermes_target` says which machine and uid (an ssh host, `local`, or `sudo:<user>` for an instance owned by another uid on this host), `hermes_home` says which instance, and `hermes_board` says which board inside it. `hermes_assignee` and `hermes_workspace` shape what a create looks like: an unassigned task on a scratch workspace is inert for a consumer whose workers pick up by profile and whose deliverables must outlive completion. `{id}` in the workspace is the board id, so every relayed task gets its own directory.

## Config

```toml
[sync]
apps              = "hermes"
hermes_target     = "<ssh-host>"      # an ssh host, or "local", or "sudo:<user>"; no default
hermes_home       = "<HERMES_HOME>"   # the kanban store to sync against; no default
# optional, for an instance whose board, workers, and deliverables are shared:
# hermes_board     = "dw-ops"
# hermes_assignee  = "chief-of-staff"
# hermes_workspace = "dir:<HERMES_HOME>/outbox/backlog/{id}"
```

Flags: `--hermes-target`, `--hermes-home`, `--hermes-board`, `--hermes-assignee`, `--hermes-workspace` (also the `[sync]` keys above). Filter keys: `hermes_only_tags`, `hermes_skip_tags`, `hermes_intake`. State: `<sync state dir>/<board-slug>/hermes.state.json`.

Neither `hermes_target` nor `hermes_home` has a default: both name one operator's machine, so a guess would point the sync at someone else's instance. An unset one ends the run with a message that names the key.

## Task Board intake relay

When a task is created from a row that another adapter's intake wrote (the Notion intake), the adapter hands the row body to the `body_expander` hook, which any adapter may provide; the Notion adapter does. The hook fetches the page body once, at create, and the card carries it frozen like the rest of the body. With no adapter declaring the hook the card is created with the body as it is. An adapter that declares the hook and fails to import stops the run before any card is created, because a silent skip would create cards without bodies that are never recreated.

The relay order is intake, publish, relay, each its own invocation:

```
board sync --apps notion-taskboard-pull      # 1. intake
<commit + push the board>                    # 2. publish
board sync --apps hermes                     # 3. relay
```

Intake mints a board id and the create keys its idempotency on it, so the id must be published before the relay. Otherwise a rejected push discards the row while the kanban task survives, and the next tick mints a new id and creates a duplicate task.

## Cockpit bridge: `board mirror`, `status`, `writeback`, `mirror-cleanup`

The bridge is a separate engine from the per-repo spoke sync above. It is a many-source to one-cockpit channel: it reads a `boards.txt` registry (every `bridge=on` repo's `BACKLOG.md` plus its active `_meta/megagoals/*/ROADMAP.md`) and keys every card by origin (`<repo>:<id>`, `megagoals:<repo>/<slug>`). The board always wins. The manifest maps the verbs to `bridge.sh` (`mirror`, `status`, `writeback`) and to `board-mirror-cleanup.py`; `bridge.sh` resolves config and runs `board-mirror.sh` (extract, diff, plan, apply) and `board-writeback.sh` (diff, validate, apply, PR). The row-to-card map is `native-map.tsv`, read by both the mirror and the cleanup.

```
board mirror [--dry-run] [--repo-root <path>] [--registry <path>] [--snapshot <path>]
             [--mega-board <name>] [--board-prefix <prefix>]
             [--remote <user@host>] [--remote-kit-path <path>]
board status [--repo-root <path>] [--registry <path>] [--snapshot <path>]
board status --with-mega [--mega-code-root <path>] [--repo-root <path>] [--registry <path>]
board writeback [--dry-run] [--repo-root <path>] [--registry <path>] [--snapshot <path>]
                [--board-prefix <prefix>] [--branch <name>] [--pr-base <branch>]
board mirror-cleanup [--registry <path>] [--snapshot <path>] [--hermes-home <dir>]
                     [--kinds-file <path>] [--expire-only] [--apply]
```

`mirror` projects the opt-in boards and one card per active mega-goal onto a Hermes kanban, idempotently. `--dry-run` prints the plan and applies nothing (no Hermes calls, no snapshot write). `--remote` ships the plan over one `ssh` call to a remote host's own `lib/adapters/hermes/board-mirror.sh apply-plan` (argv vectors, never a templated shell string); the remote host needs a kit checkout of the same version at `--remote-kit-path` (default `$HOME/.claude/dwarves-kit`). A registry row opts in with a third column, exactly the token `on`; absent, `off` or any other value stays out.

The board keyword maps to the reachable card states `{triage, ready, blocked}`, and a card leaves the board by archive:

| Row status | Card state | When the card is elsewhere |
|---|---|---|
| `queued` | `triage` | replace (archive, then create) |
| `claimed`, `speccing`, `validated`, `executing` | `ready` | from `blocked`: `promote`; from `triage`: replace |
| `parked` | `blocked` | from `ready`: `block`; from `triage`: replace |
| `shipped`, `dropped`, row gone | archived | `archive` from any live state, so a card with unfinished parents or in `triage` still closes |

`complete` is never used: Hermes refuses it on a `triage` card, and the old mirror read that refusal as "already terminal" and orphaned the card. A move whose verb fails is recorded as not moved and planned again next tick. The snapshot is `_meta/.board-mirror-snapshot.jsonl`.

`status` reports mirror staleness: per opted-in repo, the snapshot's newest `seen_at` against the board file's last git-log touch time. `--with-mega` appends a `MEGA ROLLUP` section, one line per active mega (an open sub-goal box), from `lib/mega/mega.sh status <slug> --rollup-only`; it makes real `gh` calls per sub-goal, so it is off by default. `--mega-code-root` names the repo where the megas' own branches and PRs live.

`writeback` is the reverse leg. It reads each opted-in repo's live board (`hermes kanban --board <b> list --json`) and the mirror snapshot, builds a changeset of rows whose card status moved, validates it (opted-in repo, legal board state, `row_hash` still matches the snapshot: git wins on any mismatch), and applies the matched rows' Status column on a fresh `chore/board-sync` branch built in an isolated `git worktree`, with one attributed commit (`actor=hermes`) and one held `gh pr create`. It never auto-merges. `--dry-run` prints the changeset and applies nothing (it still reads Hermes, which is exactly what a preview needs). A missing or corrupt `--snapshot` refuses all edits.

`mirror-cleanup` reconciles the open cards against the boards (dry run by default, never deletes). `--kinds-file` takes a JSON rule list that sorts the bot-made cards the mirror never owns; without it only the decomposer rule is built in. A rule with an `expire` block (`{"days": 14, "board": "social", "status": "triage"}`) archives the cards of its kind that sat in that status for that long on that board; `--expire-only` runs just that step (no registry, no board reads) and prints one line, `expired N cards on <board> (limit Nd)`, or `would expire ...` on a dry run. The backup of a snapshot the cleanup rewrites is `<snapshot>.pre-cleanup-<timestamp>`.

## Sweep legs and flags

`board sweep` runs three legs from this adapter (manifest rows `leg` and `sweep-opt`; the legs are `legs/mirror.sh`, `legs/expire.sh`, `legs/link-check.sh`):

| Flag | Leg | What it does |
|---|---|---|
| `--mirror-hermes-home <dir>` | mirror | feeds `board mirror` from `git show origin/<default>:<board>` per registry repo, not the working tree, so a stale or mid-branch checkout cannot leak rows into the kanban. If any repo's origin cannot be resolved, the whole mirror call is skipped for that tick: the planner archives any card whose row is missing from the extract, so a partial registry would close that repo's live cards |
| `--mirror-snapshot <path>` | mirror | the snapshot (default `<repo-root>/_meta/.board-mirror-snapshot.jsonl`) |
| `--expire-kinds-file <path>` | expire | turns the expiry on (needs `--mirror-hermes-home`): archives the cards the rule list's `expire` blocks name, once per tick; `--dry-run` only reports |

The mirror and expire legs are observational: each prints its own `mirror rc=<n>` or `expire rc=<n>` line, records its result in the health state, and never changes the sweep's exit code. The link-check leg always runs, last. The origin copies the mirror leg writes are `.board-mirror-origin.<name>.<pid>.md`, removed on exit and on INT or TERM.

## Health and brief

The adapter supplies the label `Hermes` (manifest `const mirror-label`), so core health and brief lines read `Hermes mirror <n> open = hub` and `the Hermes card`. Its `brief_decisions` hook turns a stale linked profile into one decision line, `kit skills on <label> are stale: re-run board hermes link`, for the link's cluster (the first cluster when none is named). The kanban reader that `board health` and `board brief` call (`--health-kanban CLUSTER=CMD`) must answer `boards list --json` and `--board SLUG list --json` and mark each card body with `origin: <repo>:<id>`; `tests/fixtures/board-sweep/stub-hermes-kanban` is the shape. The health state keeps the stale-link record under the key `hermes_links`, read and written only here.

## Linking a profile: `board hermes link`

```
board hermes link [--home <dir>] [--profile <name>] [--cluster <c>] [--label <l>] [--sudo-user <u>] [--dry-run] [--yes] [--no-verify]
board hermes check [--record] [--health-state-file <path>]
```

`link` links one Hermes agent profile to the kit. It detects Hermes homes (`--home`, `$HERMES_HOME`, `hermes config path`, `~/hermes-*/home`, `~/.hermes`), picks the profile that speaks for the operator, installs `integrations/hermes/skills/*` into that profile's skills directory with a stamp file (`.dwarves-kit-skills.json`: a digest of the skill files, the kit version and sha), records the link in `hermes-links.json` (the path `config data path state hermes-links.json` prints, or `$DWARVES_HERMES_LINKS`, with the cluster's rail, hub and boards read from the kit flag file), and verifies with one real agent turn: the agent must run `board health run --dry-run --force` and answer a nonce, then the command prints `linked`. It previews the plan and asks on a terminal; without one it writes only with `--yes`. A profile in another account's home uses `--sudo-user`. No Hermes found is a skip line and exit 0.

`check` compares each recorded link's stamp with this kit (stale: no stamp, a different digest, a missing skill); `board sweep` records it every tick. Where the kit's Hermes skills sit on top: `docs/reference/hermes-layering.md`.

## Install notes

- `hermes` must be on the target's `PATH` (over ssh, `local`, or `sudo -n -u <user> -H`). The `sudo:` form needs a NOPASSWD rule; `-n` keeps an unattended run from waiting on a password prompt.
- A `hermes_target` and `hermes_home` that your repo sets in a project `.kit.toml` are read as they are: treat a pull request that edits them like a change to a command line.

## One invocation

```bash
board sync --dry-run --apps hermes
```

## Tests

`tests/test-board-mirror.sh`, `tests/test-board-writeback.sh`, `tests/test-board-mirror-cleanup.sh`, `tests/test-board-mirror-expire.sh`, `tests/test-board-hermes.sh`, `tests/test-board-sweep-mirror.sh` and `tests/test-board-sweep-expire.sh` cover the bridge, the cleanup, the link script and the legs against stub kanban and stub `gh` binaries. `lib/adapters/tests/test_hermes.py` runs against a fake ssh transport; `test_body_expander.py` checks the relay through the registry (the block transport is a fake, and the broken-provider cases run in a child interpreter that refuses every transport); `test_conformance.py` checks the adapter against the contract. None of them reaches a Hermes host.
