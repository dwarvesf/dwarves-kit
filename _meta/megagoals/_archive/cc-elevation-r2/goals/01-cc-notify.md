# Sub-goal 01: Phone push when a loop needs me (cc-notify)

**Time budget:** ~2-3h (config-first; tool only if native push is insufficient)
**Depends on:** none
**Branch:** feat/cc-elev-r2-01-notify
**PR base:** main

## Outcome

When a `/goal` loop finishes, or Claude needs input while I am away from the desk, my phone gets pinged. Smallest viable mechanism first: flip Claude Code's native push flags (`agentPushNotifEnabled`, `inputNeededNotifEnabled`, both currently `false` in settings) and verify Remote Control delivers to the phone. Escalate to a `tools/cc-notify/` script wired on the `Notification` / `StopFailure` events (routing to my channel, with a repo allowlist) ONLY if native push does not reach the phone reliably or I need routing/allowlist control. If a tool is built, the logic lives in ops-toolkit; dotfiles gets only a one-line hook entry calling `~/.local/bin/cc-notify`.

## Quality bar

Minimum-infra (config before a new script). No notification on every turn, only loop-finish + input-needed. If the custom path is used, family-office / trading / NDA repos are excluded, and the message says only which repo + what state, never session content.

## How to close the loop

- Native path: set the two flags, trigger a loop-finish + an input-needed event, confirm the phone receives both pushes. Document the flags + Remote Control setup in a runbook.
- If escalated: the `Notification`/`StopFailure` hook, given a sample payload, calls cc-notify which emits a push for an away-event and no-ops for a normal turn (negative control); the allowlist excludes a family/trading repo path.
- Lane via lane-classify; if a tool ships, it owes `tools/cc-notify/docs/proof-of-done.md`.

**Done =** my phone receives a push on `/goal` loop-finish and on input-needed; the mechanism (native flags, or cc-notify hook + channel) is documented in a runbook; if a tool was built it has proof-of-done and excludes family/trading repos; on PR #NN.

## Scope edges

**In:** the settings-flag change (dotfiles one-liner) and/or `tools/cc-notify/`, runbook, proof.
**Out:** rich notification content (session text), notifying on every event, the scheduled-digest push (06 reuses this).
**Not:** a new always-on daemon (the hook fires on CC events; no listener).

## Open knobs (do NOT flip without Han)

- Channel: native Remote Control push vs Discord vs ntfy/Pushover. Default native; pick the channel with Han only if native is insufficient.

## Where to look

settings.json `agentPushNotifEnabled` / `inputNeededNotifEnabled`, the `PushNotification` tool, the `Notification` + `StopFailure` hook payloads, the SPEC-002 iOS pilot path, `tools/tide/` for tool shape.

## PR body

Outcome: phone gets pinged on /goal loop-finish + input-needed; native push flags first, allowlisted cc-notify hook only if native is insufficient.
Verify: trigger loop-finish + input-needed, confirm phone push; custom path no-ops on normal turns + excludes family/trading.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 01).

## Notes
