# harvest-sweep: scheduled transcript harvest (macOS LaunchAgent)

The sweep replaces the session-end `harvest.sh` hook and `/kit:wrap`'s inline
distill on the hosts where it is installed: one LaunchAgent harvests every
`harvest.schedule_hours` (default 6h), stages learnings into the sweep
ledgers, aggregates candidates, and writes a wrap-shaped report per run.

```
bash deploy/macos/harvest-sweep/install                        # dry-run: prints the plan
bash deploy/macos/harvest-sweep/install --apply                # renders, marks, loads
bash deploy/macos/harvest-sweep/install --label mini.harvest-sweep --apply   # the Mini
launchctl kickstart -k gui/$(id -u)/harvest-sweep              # run now
tail -f ~/Library/Logs/dwarves-kit/harvest-sweep.log           # watch a run
```

`install` is a dry run by default and refuses unless `harvest.enable` is true
in the operator or kit-root `kit.toml` (root-only read; a project `.kit.toml`
can never switch the sweep on, because it rides inside an untrusted PR).

## What `--apply` writes

| File | Purpose |
|---|---|
| `~/Library/LaunchAgents/<label>.plist` | the LaunchAgent, rendered from the kit's template |
| `<state>/sweep/installed` | host marker `{"label","host","kit","ts"}` that ACTIVATES the sweep on this host |

`<state>` is `$HARVEST_STATE_DIR` or `~/.claude/dwarves-kit/state/harvest`.
The marker is the per-host switch: an operator `kit.toml` may sync across
hosts, but only a host where `install --apply` wrote the marker sweeps; every
other host keeps the session-end hook and wrap's inline distill. The marker is
never synced and never written by a dry run.

The Mini installs `--label mini.harvest-sweep`, a prefix already registered in
vps-mon's `OWNED_PREFIXES`.

## Why a second LaunchAgent beside kit-weekly

ADR-0034 decision 9 chose ONE kit scheduler and rejected a plist per job. The
sweep runs every 6h against kit-weekly's fixed weekly slot, and a per-job
interval inside kit-weekly is exactly the fragmentation decision 9 rejected.
T19 amends decisions 6 and 9 to record the split: the kit owns the template,
launcher, and installer; the instantiated LaunchAgent and the heartbeat
bridge stay consumer-side, the same precedent `lib/sync/deploy/macos/`
(board-sync-cron) already set for per-repo jobs.

## Service graph

```
<Label>.plist -> deploy/macos/harvest-sweep/harvest-sweep (the launcher)
                  -> python3 hooks/harvest_sweep.py --sweep   (direct: harvest.sh
                     would swallow the rc)
                  -> ~/.config/harvest-sweep/bridge <rc> <report or ->   (if present)
```

The launcher re-checks activation on every scheduled run (marker AND
`harvest.enable`, both read live), so flipping `enable` off makes an already
loaded job go inert without a re-install. It logs `start <label>` and
`end rc=<n>` to `~/Library/Logs/dwarves-kit/<label>.log` and exits with the
sweep's own rc.

`StartInterval` renders from `harvest.schedule_hours` * 3600 at install time;
`RunAtLoad` is false. `ProgramArguments[0]` is the launcher's own absolute
path (no `.sh`, `#!/bin/bash` per the BTM rule). The label reaches the
launcher through the plist's `HARVEST_SWEEP_LABEL` environment variable, so
the log file tracks `--label` with no second render knob.

**Consumer env (optional).** If `~/.config/harvest-sweep/env` exists, the
launcher sources it before running (PATH extras, Claude auth settings,
per-machine overrides). Never committed to the kit repo.

**Consumer bridge (optional).** If `~/.config/harvest-sweep/bridge` is
executable, the launcher runs it best-effort after every non-skipped run as
`bridge <rc> <report path or ->`: `-` when the run wrote no report (idle runs
still ping), the lock-held skip is the only case with no call. The kit ships
no bridge and no endpoint; the bridge source and its heartbeat provisioning
live consumer-side (ops-toolkit, T24).

## Uninstall

```
bash deploy/macos/harvest-sweep/install --uninstall
```

Boots out the label, then removes only the two files `--apply` wrote: the
plist and the `installed` marker. The host returns to hook + wrap-distill
behavior immediately. All sweep state stays: `cursor.json`, `sweep/ledger/`,
`patterns.jsonl`, `proposed.jsonl`, `sweep/extract/`, `sweep/runs/`. The
command prints the state path, the queued-learning count, the `extract/`
size, and a purge command for `extract/` that it does NOT run:

```
rm -rf '<state>/sweep/extract'
```

A later `install --apply` resumes from the same cursor; queued learnings
drain through the normal flush path (`python3 hooks/harvest.py --flush-list`).
