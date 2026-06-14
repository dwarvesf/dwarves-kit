# cc-intel weekly digest, deploy runbook

## Status + topology

- What: a weekly LaunchAgent that runs `cc-intel run` -> `~/.claude/intel/intel-YYYY-MM-DD.md`.
- Host: the Air (tieubao GUI session). Work is local + read-only: parses transcripts, shells out to cc-observe/repo-sweep, reads the ledger + GLOSSARYs.
- Service graph: `cc-intel-weekly.plist` -> launcher `cc-intel-weekly` -> `~/.local/bin/cc-intel run`. cc-intel itself shells out to `cc-observe` + `repo-sweep` (also on `~/.local/bin`).
- Schedule: Monday 09:00 local (`StartCalendarInterval`), `RunAtLoad` false.
- Output + log: `~/.claude/intel/`.

## Recreate from zero

1. Clone ops-toolkit; ensure the `~/.local/bin` symlinks exist:
   ```bash
   ln -sf "$PWD/tools/cc-intel/bin/cc-intel" ~/.local/bin/cc-intel
   ln -sf "$PWD/tools/cc-observe/bin/cc-observe" ~/.local/bin/cc-observe
   ln -sf "$PWD/tools/repo-sweep/bin/repo-sweep" ~/.local/bin/repo-sweep
   ```
2. `mkdir -p ~/.claude/intel`
3. Install the agent:
   ```bash
   cp tools/cc-intel/deploy/macos/cc-intel-weekly.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/cc-intel-weekly.plist
   ```
4. Verify:
   ```bash
   launchctl print gui/$(id -u)/cc-intel-weekly | grep -i program   # ProgramArguments = the bare launcher
   launchctl kickstart -k gui/$(id -u)/cc-intel-weekly              # run now
   ls ~/.claude/intel/                                              # the digest appears
   ```
   Then System Settings > General > Login Items & Extensions: the row shows `cc-intel-weekly` with the exec icon.
5. Unload: `launchctl bootout gui/$(id -u)/cc-intel-weekly`

## Hazards

- The launcher is a bare-name executable (no `.sh`) per the repo plist rule, so BTM shows the real name + exec icon.
- If `~/.local/bin/cc-intel` is missing, the launcher exits non-zero and the digest is skipped that week (no harm; read-only).
- Anti-drift: edit the repo template, then redeploy; never hand-edit the installed plist.
- Push channel (cc-notify, sub-goal 01) can later be appended to the launcher to ping the digest; deferred (01 is blocked on a channel decision).
