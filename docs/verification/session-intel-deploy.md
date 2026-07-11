# Proof of done: session-intel weekly deploy folds into the kit

Change under proof: the telemetry cadence that tracks-and-optimizes the kit (the
weekly cc-intel digest LaunchAgent, formerly ops-toolkit `cc-intel-weekly`) now
ships IN the kit as `lib/session/intel/deploy/macos/`: a generic BTM-friendly
launcher (`session-intel-weekly`, launchd-safe PATH), a `__HOME__`/`__KIT__`
plist template, and an idempotent `install` script. Tenant material is fully
extracted: the launcher runs an OPTIONAL consumer bridge at
`~/.config/session-intel/bridge` (best-effort, never fails the digest); the kit
ships no secret, endpoint, or tenant path.

## Confirmation run-table (live, 2026-07-11)

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Installer renders + bootstraps | `bash lib/session/intel/deploy/macos/install` | `[ok] session-intel-weekly installed` | PASS |
| 2 | End-to-end weekly run | `launchctl kickstart -k gui/$(id -u)/session-intel-weekly` | digest 185 KB, 0 `_unavailable_` | PASS |
| 3 | Consumer bridge fires post-digest | log tail | `heartbeat: 204` | PASS |
| 4 | Launcher + install syntax | `bash -n` both | exit 0 | PASS |
| 5 | Tenant-leak grep on the bundle | personal paths / repo names / vendor keywords over `lib/session/intel/deploy/` | no hits | PASS |

## Negative control (uninstall -> RED -> reinstall)

```
launchctl bootout gui/$(id -u)/session-intel-weekly
launchctl print gui/$(id -u)/session-intel-weekly   -> label gone   RED (expected)
bash lib/session/intel/deploy/macos/install          -> [ok] installed   GREEN
```

Also inherent: with no `~/.config/session-intel/bridge` the launcher skips the
bridge block entirely (plain `-x` test), so a kit-only machine runs the digest
with zero consumer wiring.

## Recorded run

```
Command: bash lib/session/intel/deploy/macos/install
Output:  [ok] session-intel-weekly installed (Mon 09:00; kickstart to run now)
Exit:    0

Command: launchctl kickstart -k gui/$(id -u)/session-intel-weekly
Output:  digest 185296 bytes, grep -c _unavailable_ -> 0; log tail: heartbeat: 204
Exit:    0
Verdict: PASS
```

## Rollback

`launchctl bootout gui/$(id -u)/session-intel-weekly && rm ~/Library/LaunchAgents/session-intel-weekly.plist`
removes the agent cleanly (exercised live as the negative control above);
`git revert` of this commit removes the bundle from the kit. The digest output
dir `~/.claude/intel/` is plain files, never deleted by install or uninstall.

## Reproduce

```
bash lib/session/intel/deploy/macos/install
launchctl kickstart -k gui/$(id -u)/session-intel-weekly
sleep 90; grep -c _unavailable_ ~/.claude/intel/intel-$(date +%F).md   # expect 0
```
