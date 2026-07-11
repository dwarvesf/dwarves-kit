# session-intel weekly deploy (macOS LaunchAgent)

Folded from ops-toolkit's `cc-intel-weekly` (2026-07-11): the telemetry cadence that
tracks-and-optimizes the kit belongs to the kit. The agent runs `cc-intel run` every
Monday 09:00 -> `~/.claude/intel/intel-YYYY-MM-DD.md`, read-only.

```
bash lib/session/intel/deploy/macos/install    # render plist + bootstrap (idempotent)
launchctl kickstart -k gui/$(id -u)/session-intel-weekly   # run now
```

Service graph: plist -> `session-intel-weekly` launcher (exports a launchd-safe
PATH; the bare launchd PATH silently hollowed every digest for three weeks once) ->
`~/.local/bin/cc-intel` (the installer's CLI shim) -> shells out to `cc-observe`
(+ `repo-sweep` when the consumer has one; degrades to `_unavailable_` without).

**Consumer bridge (optional).** The kit ships no monitoring endpoint or secret.
If an executable exists at `~/.config/session-intel/bridge`, the launcher runs it
best-effort after the digest (liveness heartbeat, notification, anything
tenant-side); a bridge failure never fails the digest.

Uninstall: `launchctl bootout gui/$(id -u)/session-intel-weekly && rm ~/Library/LaunchAgents/session-intel-weekly.plist`
