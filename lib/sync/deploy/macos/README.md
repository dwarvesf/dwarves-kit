# board-sync-cron: scheduled `board sync` (macOS LaunchAgent)

Kit board ID-289: `sync.mode` was declared `[reserved]` (`manual` | `cron`,
scheduled runs not built yet). This wires the `cron` value to a real,
per-repo unattended run so hub-and-spoke sync doesn't depend on someone
remembering to run `board sync` by hand.

```
bash lib/sync/deploy/macos/install --repo <path>              # dry-run: prints the plan
bash lib/sync/deploy/macos/install --repo <path> --apply       # renders + loads the LaunchAgent
launchctl kickstart -k gui/$(id -u)/board-sync-<slug>          # run now
tail -f ~/Library/Logs/dwarves-kit/board-sync-<slug>.log       # watch a run
```

`<slug>` is the target repo's `BACKLOG.md` PHYSICAL absolute path (`pwd -P`,
symlinks resolved) with every non-alphanumeric run collapsed to a single `-`
(the same slugging `backlog_sync.py`'s `board_state_dir()` uses for its
state-cache dir, so the label and the state dir are recognizably the same
identity). `install` refuses to overwrite an existing plist whose baked-in
backlog path differs from the one it's about to render -- a same-label
collision from two differently-laid-out repos is refused, not silently taken
over. Login Items caveat: every per-repo install shares the same
`board-sync-cron` script name, so with 2+ repos on `mode = "cron"`, System
Settings -> Login Items shows multiple identically-named rows; use
`launchctl print gui/$(id -u)/board-sync-<slug>` to tell them apart.

## Why per-repo, not a kit-weekly job

`deploy/macos/` (kit root) is ADR-0034 decision 9's ONE weekly scheduler,
which explicitly REJECTED a plist-per-job scheme ("N daemons, N runbooks, the
fragmentation Han flagged") in favor of one LaunchAgent walking a declarative
`jobs.txt`. That rejection targeted fragmentation WITHIN one shared,
kit-owned jobs list, N housekeeping tasks (session-intel, kit-retro,
prose-rag-index) all resolved relative to the kit repo itself, competing for
one dispatcher. This is a different shape: one self-contained, self-owned
LaunchAgent PER OPTED-IN CONSUMER REPO, not N jobs fragmenting one shared
list. `board sync` is inherently per-CONSUMER-REPO (a different `BACKLOG.md`,
a different set of `[sync]` apps, potentially a different cadence per repo),
and the kit repo's own `jobs.txt` is shared across every adopter of this
kit, so it cannot carry one operator's repo paths without breaking
genericity for everyone else who installs the kit. Each adopted repo
therefore gets its own LaunchAgent, installed from within that repo, exactly
the "consumer instantiates the template" split SPEC-126 already established
for kit-weekly.

## Gate: `sync.mode` must be `cron`

`install` reads `.kit.toml [sync] mode` for the target repo via the one TOML
resolver (`kit_config_get`, same as `board.sh cmd_sync`) and refuses to
render or load anything unless it is exactly `cron`:

| `sync.mode` value | Result |
|---|---|
| unset / `manual` (default) | refuses, tells you to set `mode = "cron"` |
| `cron` | proceeds (also requires `[sync] apps` to be non-empty) |
| anything else (typo, stray value) | refuses, names the bad value |

This is deliberate: a launchd job silently never getting installed because
`mode` was misspelled would be a much worse failure than a loud, immediate
refusal at install time.

**`mode` is read live in TWO different places, for two different questions:**
`install` reads it ONCE, at install time, to decide whether to LOAD the
LaunchAgent at all -- editing `.kit.toml` afterward does not retroactively
unload an already-installed job (`launchctl bootout`, below, is the only
off-switch for that). The installed **launcher** (`board-sync-cron`) also
re-reads the same key on EVERY scheduled run, so a repo that later flips
`mode` back to `"manual"` gets its next scheduled run skip cleanly (exit 0,
logged) instead of silently syncing forever against a config that says it
shouldn't. Net effect: to stop scheduled syncing, either flip `mode` back to
`manual` (job stays loaded but goes inert) or fully `launchctl bootout` it
(job stops existing); both are documented, self-service, no re-install
needed for the former.

## Service graph

```
board-sync-<slug>.plist -> lib/sync/deploy/macos/board-sync-cron <backlog-path>
                            -> bin/board sync --backlog-file <backlog-path>
                               -> lib/board/board.sh cmd_sync
                                  -> lib/sync/backlog_sync.py (per-app three-way merge)
```

`board-sync-cron` is generic and kit-owned (git-tracked, never templated);
only the plist itself carries per-repo values (`__KIT__`, `__BACKLOG__`,
`__LABEL__`, `__INTERVAL__`, `__HOME__`), rendered once at install time and
never hand-edited afterward (anti-drift: edit the `.tmpl`, re-run
`install --apply`; a custom `--interval-secs` given at a previous install is
NOT remembered by the template -- put it in `[sync] interval_secs` in the
repo's own `.kit.toml` if it should survive a re-render, see Cadence below).

**Log shape.** Every run writes two timestamped lines to
`~/Library/Logs/dwarves-kit/board-sync-<slug>.log` (start with the backlog
path, end with the exit code), so a failed scheduled run is identifiable by
run even though the file accumulates across every run (no rotation is
shipped; `newsyslog`/`logrotate` it yourself if it grows too large for your
taste).

**Cadence.** `install` computes `StartInterval` (seconds) from, in order:
the `--interval-secs N` flag, else `[sync] interval_secs` in the repo's
`.kit.toml`, else `3600` (hourly). `StartInterval` (not
`StartCalendarInterval`, which kit-weekly uses for its fixed Monday-09:00
slot) is the right launchd key for a fixed-cadence, drift-tolerant job like
this one.

**Consumer env (optional).** launchd gives jobs a bare env. If
`~/.config/board-sync-cron/env` exists, the launcher sources it before
running (e.g. a per-machine `MULTICA_TOKEN` override), never committed to
the kit repo.

**Consumer bridge (optional).** If an executable exists at
`~/.config/board-sync-cron/bridge`, the launcher runs it best-effort AFTER
every sync attempt (success or failure), passing `<exit-code> <backlog-path>`
as argv -- a liveness heartbeat, notification, or anything tenant-side. A
bridge failure never fails the run. The kit ships NO bridge (no monitoring
endpoint, no secret): symmetric with kit-weekly's own
`~/.config/kit-weekly/bridge`.

BTM rules honored: `ProgramArguments[0]` is `board-sync-cron`'s own absolute
path (never `/bin/sh`), the launcher has no `.sh` extension, and its shebang
is `#!/bin/bash` (Apple-signed) rather than `env bash` -- the reminders spoke
drives Automation/Reminders via `osascript`, and TCC keys that grant to the
resolved interpreter binary, so a brew-upgraded `env bash` would silently
lose the grant on the next `brew upgrade bash`.

## Monitoring (follow-up, out of this repo)

This ships the schedule PLUS the seam a monitor needs: the per-run log
lines (start/end/rc) for a log-mtime-freshness check, and the consumer
bridge hook above for a real success-keyed heartbeat -- the same seam
kit-weekly exposes via its own bridge. Per the job-monitoring-onboarding
convention (a scheduled job isn't "done" until it's monitored), actually
WIRING that up (an ops-toolkit `vps-mon` probe or bridge script for
`board-sync-<slug>`) is a separate follow-up in
`ops-toolkit/tools/vps-mon/`, not part of this kit repo.

## Uninstall

```
launchctl bootout gui/$(id -u)/board-sync-<slug>
rm ~/Library/LaunchAgents/board-sync-<slug>.plist
```
