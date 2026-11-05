# update-check: SPEC

## Problem

A kit install goes stale without any sign. Nothing tells the user a newer release exists.

## Solution

`hooks/kit-update-notice.sh` compares the installed `VERSION` with the latest `VERSION` on the default branch and prints one `systemMessage` when the latest is newer. Pattern copied from the Delta plugin: check once per session at startup, notify, never install.

## Contract

| Item | Rule |
|---|---|
| Event | `SessionStart`, matcher `startup` only (resume and compact do not repeat it) |
| Installed version | `${CLAUDE_PLUGIN_ROOT}/VERSION`, else `${DWARVES_KIT:-~/.claude/dwarves-kit}/VERSION` |
| Latest version | `curl -fsS --max-time 2 $KIT_UPDATE_CHECK_URL` (default: raw.githubusercontent.com, `dwarvesf/dwarves-kit`, `master`, `VERSION`) |
| Version shape | strict `major.minor.patch`, digits only; anything else is "unknown" |
| Throttle | at most one fetch per 24h; `{checked_at, latest}` cached in `${KIT_UPDATE_STATE_DIR:-~/.claude/dwarves-kit/state/update-notice}/cache.json`; between fetches the cached latest is compared |
| A failed fetch | recorded as an attempt (keeps the old cached latest), so an offline machine retries tomorrow, not every start |
| Output | `{"systemMessage": "..."}` on stdout, only when latest > installed (semver compare); otherwise nothing |
| Failure | offline, no curl or jq, bad VERSION, any error: exit 0, no output. Never blocks past the 2s curl cap; hooks.json timeout is 5 |
| Opt-out | `KIT_UPDATE_CHECK=0`; module toggle `update_check` (enforced by `hooks/anchor-root.sh`) |

## Non-goals

- Installing or updating anything. The notice names the command; the user runs it.
- Release notes, changelog fetching, or a prerelease channel (`1.2.3-rc1` counts as unknown).
- Auto-detecting that the plugin and the install.sh copy differ.

## Verification

`bash tests/test-update-check-notice.sh` (hermetic, no network: `file://` fetch URL, temp HOME and state dir) plus `bash tests/test-modules-table.sh`.
