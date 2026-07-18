# Proof of done: sync.mode = cron, scheduled `board sync` (kit ID-289)

**Change class:** behavioral (`lib/sync/deploy/macos/install`,
`lib/sync/deploy/macos/board-sync-cron`, `board-sync-cron.plist.tmpl`; config
surface: `kit.toml` + `lib/config/module-registry.md`).

**Claim:** `sync.mode` (previously `[reserved]`, `manual` | `cron`) is now a
real gate. `lib/sync/deploy/macos/install` renders and (with `--apply`) loads
a per-repo macOS LaunchAgent that runs `board sync` on a schedule, but ONLY
for a repo whose own `.kit.toml [sync]` sets `mode = "cron"`; `manual`
(default), unset, or any other value is refused cleanly (exit 2, naming the
bad value), never a silent fallthrough. The installed launcher
(`board-sync-cron`) re-checks the same key live on every scheduled run, so
flipping `mode` back to `manual` after install makes the job go inert
without needing a re-install. `install` defaults to `--dry-run` (prints the
rendered plist + exact `launchctl` commands, never touches the host); no
host was mutated by this build, per the task's repo-side-only constraint.

## Review disposition (kit:code-reviewer architecture lens + kit:advisor/fable critique)

| Finding | Lens | Applied? |
|---|---|---|
| Architecture: per-repo LaunchAgent vs kit-weekly's single scheduler is the right call, but ADR-0034 decision 9's literal "rejects plist-per-job" needs explicit disambiguation | architecture (should-fix) | Applied, README now states the rejection targeted fragmentation WITHIN one shared jobs list, not N self-owned per-repo agents |
| Docs: `mode` is read once at install time; nothing said so | architecture (should-fix) | Superseded by a real fix (see next row), then documented anyway |
| `sync.mode` gate is install-time only; a repo that later flips `mode` back to `manual` keeps syncing forever on the still-loaded job | advisor (finding 1) | Applied: launcher re-reads `sync.mode` live every run and skips cleanly (exit 0) once it's no longer `cron` |
| Cadence lives only in a CLI flag, no config key, contradicts the "different cadence per repo" framing | advisor (finding 2) | Applied: new `sync.interval_secs` kit.toml key (default 3600), `--interval-secs` overrides it for one run |
| Log has no run boundaries; can't tell which run failed from the file alone | advisor (finding 3) | Applied: launcher prints timestamped start/end (with rc) lines per run |
| No consumer-bridge hook symmetry with kit-weekly; a future vps-mon wiring would have to touch the launcher again | advisor (finding 4) | Applied: `~/.config/board-sync-cron/bridge` best-effort hook, same shape as kit-weekly's |
| Slug uses logical (`cd && pwd`) path, diverges from `backlog_sync.py`'s physical-path slug under a symlinked checkout | advisor (finding 5) | Applied: `install` resolves the repo with `pwd -P` |
| Label collision: two differently-laid-out repos can slug to the same LaunchAgent label; `--apply` would silently take over | advisor (finding 6) | Applied: `install` refuses (exit 2, names both paths) when an existing plist's baked-in backlog differs |
| `launchctl print \| grep && echo ok` under `set -e` has no `else`; a confirmation-only failure masks a real successful bootstrap | advisor (finding 7a) | Applied: restructured to an explicit `if/else`, bootstrap success is never gated on the confirmation grep |
| `mktemp -t NAME` is BSD-only, breaks on GNU/Linux | advisor (finding 7b) | Applied: portable `mktemp "$TMPDIR/....XXXXXX"` template form |
| BTM: multiple per-repo installs share one Login Items row name | architecture (nit) | Documented (README caveat + `launchctl print` disambiguation command); accepted as a known cosmetic limitation |
| `cmd_sync` (manual `board sync`) should stay unaffected by `sync.mode` | architecture (passed) | Confirmed correct by design; `board.sh cmd_sync` untouched, module-registry row states this explicitly |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | `sync.mode` unset/`manual` refuses install, exit 2, names the fix | PASS |
| 2 | `sync.mode` = any value other than `manual`/`cron` (negative control) rejected cleanly, exit 2, names the bad value | PASS |
| 3 | `sync.mode = cron` + `apps` unset still refuses (exit 2) | PASS |
| 4 | `sync.mode = cron` + `apps` set: dry-run prints the rendered plist + exact `launchctl` commands, mutates nothing (stubbed `launchctl`, empty log) | PASS |
| 5 | `--apply` actually writes the plist and calls `launchctl bootout` then `bootstrap` | PASS |
| 6 | Both `BACKLOG.md` conventions (`_meta/` and root-level) resolve | PASS |
| 7 | `--interval-secs` flag and `sync.interval_secs` config both set cadence, flag wins | PASS |
| 8 | Non-numeric interval rejected cleanly | PASS |
| 9 | Two differently-named repos get two different labels | PASS |
| 10 | Two repos whose slugs COLLIDE are refused (not silently merged), under both dry-run and `--apply` | PASS |
| 11 | Re-running install for the SAME repo over its own existing plist is not flagged as a collision | PASS |
| 12 | Installed launcher: missing `argv[1]` fails cleanly (no unbound-var crash) | PASS |
| 13 | Installed launcher: `mode = cron` forwards to `bin/board sync --backlog-file <path>`, widens `PATH`, logs timestamped start/end+rc | PASS |
| 14 | Installed launcher: `mode = manual` (or unset) skips cleanly, exit 0, does NOT invoke `bin/board` | PASS |
| 15 | Installed launcher: optional consumer env + optional consumer bridge hook both sourced/invoked when present, silent no-op when absent | PASS |
| 16 | No regression to existing `sync` module tests (engine, dispatch, config registry) or the kit-wide structural suite | PASS |

## Coverage

Test lines added: 174 (`tests/test-sync-cron-install.sh`) + 125
(`tests/test-sync-cron-launcher.sh`) = 299. Behavioral code lines added:
72 (`board-sync-cron`) + 179 (`install`) = 251. Ratio 299/251 ≈ 119%, above
the 80% target. Every branch in both scripts is exercised: the `sync.mode`
case (`cron`/`manual`/other), the `apps` guard, both `BACKLOG.md`
conventions, `--interval-secs` flag vs config vs default vs invalid, the
label-collision guard (both the collision path and the non-collision
same-repo re-run), dry-run vs `--apply`, and in the launcher: missing argv,
live mode skip, PATH widening, consumer env, and the bridge hook (present
and absent).

## Confirmation run

Command: `bash tests/test-sync-cron-install.sh`
Exit: 0

Command: `bash tests/test-sync-cron-launcher.sh`
Exit: 0

Command: `bash tests/test-meta.sh`
Exit: 0

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Install-script suite (29 assertions) | `bash tests/test-sync-cron-install.sh` | 0 | PASS (29/29) |
| Launcher suite (14 assertions) | `bash tests/test-sync-cron-launcher.sh` | 0 | PASS (14/14) |
| sync engine suite (unchanged) | `bash tests/test-sync.sh` | 0 | PASS (60/60) |
| sync dispatch suite (unchanged) | `bash tests/test-sync-dispatch.sh` | 0 | PASS (5/5) |
| config registry drift lint (new `sync.interval_secs` + `sync.mode` status flip both clean) | `bash tests/test-config-registry.sh` | 0 | PASS (19/19) |
| kit-wide structural suite (no regression) | `bash tests/test-meta.sh` | 0 | PASS (698/698) |
| shellcheck (warning level) on both new scripts + both new test files | `shellcheck -S warning lib/sync/deploy/macos/install lib/sync/deploy/macos/board-sync-cron tests/test-sync-cron-install.sh tests/test-sync-cron-launcher.sh` | 0 | clean |

## Run detail

```
$ bash tests/test-sync-cron-install.sh
  PASS unset mode (default manual) refuses, exit 2
  PASS unset mode: message points at mode = "cron"
  PASS unset mode: no launchctl.log written (nothing attempted)
  PASS explicit mode=manual refuses, exit 2
  PASS bad mode value ('biweekly') rejected, exit 2 (not a crash)
  PASS bad mode value: message names the offending value
  PASS bad mode value: no launchctl invocation
  PASS mode=cron with no apps refuses, exit 2
  PASS mode=cron/no-apps: message names the missing apps key
  PASS mode=cron + apps, dry-run exits 0
  PASS dry-run: prints the rendered ProgramArguments (backlog path)
  PASS dry-run: prints the label
  PASS dry-run: prints the exact launchctl bootstrap command to run
  PASS dry-run NEVER calls the real launchctl (no mutation)
  PASS dry-run: no plist written to $HOME/Library/LaunchAgents
  PASS root-level BACKLOG.md convention resolves
  PASS custom --interval-secs is rendered into the plist
  PASS non-numeric --interval-secs rejected cleanly, exit 2
  PASS mode=cron + apps, --apply exits 0
  PASS --apply writes a plist under $HOME/Library/LaunchAgents
  PASS written plist references the repo's own board-sync-cron launcher + backlog path
  PASS --apply invoked launchctl bootout then bootstrap
  PASS two different repos render two different LaunchAgent labels
  PASS sync.interval_secs from .kit.toml is used when --interval-secs is omitted
  PASS --interval-secs flag overrides sync.interval_secs
  PASS colliding slug from a DIFFERENT repo's backlog is refused, exit 2
  PASS collision message names both the existing and the new backlog path
  PASS colliding slug also refused under --apply (never silently takes over)
  PASS re-installing the SAME repo over its own existing plist is fine (not a collision)
=== 29/29 passed ===

$ bash tests/test-sync-cron-launcher.sh
  PASS missing backlog argv[1] fails cleanly (not an unbound-var crash trace)
  PASS mode=cron: resolves KIT via BASH_SOURCE (4 dirs up) and execs the fake bin/board
  PASS mode=cron: forwards argv as: sync --backlog-file <path>
  PASS mode=cron: widens PATH with ~/.local/bin and /opt/homebrew/bin
  PASS mode=cron: prints a timestamped start line
  PASS mode=cron: prints a timestamped end line with rc
  PASS mode=manual: skips cleanly, exit 0
  PASS mode=manual: does NOT invoke bin/board
  PASS mode=manual: says why it skipped
  PASS no .kit.toml (default manual): skips cleanly, exit 0, no board call
  PASS sources ~/.config/board-sync-cron/env when present
  PASS absent consumer env file is a silent no-op (exit 0, no error text)
  PASS executable bridge hook is invoked with rc + backlog path
  PASS absent bridge hook is a silent no-op (exit 0)
=== 14/14 passed ===
```

## NEGATIVE CONTROL (revert -> RED -> restore)

Performed live on this branch, not merely asserted:

1. **Revert**: `lib/sync/deploy/macos/install`'s `sync.mode` case statement
   was mutated from `cron) : ;;` to `cron|biweekly) : ;;`, i.e. the exact
   defect the gate exists to catch: a typo'd/unrecognized mode value
   silently accepted instead of refused.
2. **RED**: `bash tests/test-sync-cron-install.sh` immediately dropped to
   **27/29**, with the two negative-control assertions failing exactly as
   expected:
   ```
   FAIL bad mode value ('biweekly') rejected, exit 2 (not a crash) -- got: rc=0
   FAIL bad mode value: message names the offending value -- got: dry-run: sync.mode=cron confirmed for .../repoC (apps=reminders)
   === 27/29 passed ===
   ```
   This proves the test is load-bearing: it is not a tautology that passes
   regardless of the implementation.
3. **Restore**: `git checkout -- lib/sync/deploy/macos/install` reverted the
   mutation; `bash tests/test-sync-cron-install.sh` returned to **29/29**
   (confirmed above in Run detail). Working tree confirmed clean
   (`git status --short` empty) before this proof was written.

**Verdict: PASS.**

## Reproduce

```
bash tests/test-sync-cron-install.sh    # 29/29
bash tests/test-sync-cron-launcher.sh   # 14/14
bash tests/test-sync.sh                 # 60/60 (unchanged sync engine)
bash tests/test-sync-dispatch.sh        # 5/5 (unchanged cmd_sync dispatch)
bash tests/test-config-registry.sh      # 19/19 (config drift lint)
bash tests/test-meta.sh                 # 698/698 (kit-wide structural suite)
```

**Rollback:** `git revert` this commit removes `lib/sync/deploy/macos/`
entirely and reverts the two doc-only config edits (`kit.toml`,
`lib/config/module-registry.md`, both single-line status/key changes). No
host state is involved: this build never ran `--apply` against a real
`launchctl`, so there is nothing installed on any host to roll back. A repo
that already ran `install --apply` on a real Mac before a future revert
would still need a manual `launchctl bootout gui/$(id -u)/board-sync-<slug>`
(documented in `lib/sync/deploy/macos/README.md`'s Uninstall section) since
git revert cannot reach into launchd state.
