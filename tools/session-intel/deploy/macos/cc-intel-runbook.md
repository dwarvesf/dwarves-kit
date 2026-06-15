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
   ln -sf "$PWD/tools/cc-observe/bin/cc-vps-report" ~/.local/bin/cc-vps-report  # SG-05 vps-mon bridge
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

## vps-mon bridge (SG-05)

After writing the digest, the launcher best-effort calls `cc-vps-report` heartbeat-only
(no `--snapshot`) to ping the `cc-intel-weekly` heartbeat, which surfaces digest liveness
on the public `/status` page (`/status/ai-substrate`). A stopped digest (no ping in 7d +
1d grace) flips the item to 🔴 and fires `heartbeat-silent`; it is never silently green.
The `/v1/snapshot` metrics POST is intentionally OFF in the weekly path: it registers a
vps-mon `hosts` row subject to the hardcoded 600s `agent-silent` rule, which false-fires
for a weekly pusher (incident 2026-06-15). Use `cc-vps-report --snapshot` only manually,
and only once vps-mon exempts low-frequency hosts.

- Secret resolves at runtime from 1Password: `op://Toolkit/cc-vps-report/hb_token` (the
  heartbeat-only path needs just the HB token; `credential` is read only by `--snapshot`).
  The bridge no-ops (non-fatal) if `op` is unavailable or the symlink is missing, so a
  vps-mon outage never breaks the weekly digest.
- The Worker side needs the HMAC secret installed once:
  `cd tools/vps-mon/worker && op read op://Toolkit/cc-vps-report/credential | CLOUDFLARE_ACCOUNT_ID=<Han-Ngo> pnpm wrangler secret put HMAC_KEY_CC_AIR` (already done 2026-06-15).
- The D1 rows (status page `ai-substrate`, heartbeat `cc-intel-weekly`, status item) are
  seeded once; see `tools/cc-observe/docs/proof-of-done.md` (SG-05).
- **Launcher body changed (not its path), so no plist redeploy is needed.** To prove the
  bridge end to end after deploying the symlink, run it once:
  `launchctl kickstart -k gui/$(id -u)/cc-intel-weekly` (or `cc-intel-weekly` directly),
  then `curl -s https://mon-ingest.han-ws.workers.dev/status/ai-substrate | grep intel`.
