# ADR-0014: Read-side secrets guard (hook + permissions.deny)

## Status: accepted (2026-05-21).

## Context
The kit's safety story was entirely write/exec destruction: `safety-gate.sh` blocks `rm -rf`, push-to-main, and force-push. Nothing stopped the agent from *reading* `~/.ssh/id_rsa`, `~/.aws/credentials`, `.env`, keychains, or `.pem` files and surfacing the contents into a log, a PR, or a downstream tool call. For a kit that runs autonomously and ships to contractors, read-exfiltration of secrets was unguarded. The 2026-05-21 cross-repo survey found two proven sources: Trail of Bits `claude-code-config` (a vetted `permissions.deny` list) and claudekit `file-guard` (a sensitive-file read block with exfil-pipeline detection).

## Decision
Add a read-side guard with two layers:
1. **`hooks/secrets-guard.sh`** (PreToolUse, matcher `Read|Edit|Bash`): the primary, cross-install-path layer. Denies Read/Edit of a secret path and best-effort-denies Bash reads of secret files. Registered in both `settings.json` and `hooks/hooks.json`, so it protects both the bash-install and plugin paths.
2. **A `permissions.deny` block in `settings.json`**: declarative defense-in-depth for the bash-install path (the plugin schema cannot set permissions). `install.sh` unions these deny entries into an existing user's settings on merge; a fresh install copies them whole.

Three design rules make the hook honest rather than theater:
- **Canonicalize before matching.** The path is normalized (expand `~`/`$HOME`, make absolute, resolve `..`) before glob-matching, so `~/.ssh/id_rsa`, `$HOME/.ssh/id_rsa`, and a `../` spelling of the same file all match. A portable bash normalizer is used because `realpath -m` is not macOS-portable.
- **Fail-closed on a match, fail-open on error.** A confirmed secret match blocks (exit 2); unparseable input allows + logs (exit 0) so a parse error never bricks the session.
- **The Bash-surface check is best-effort defense-in-depth, not exfil-proof.** A reader denylist (`cat`/`less`/...) is bypassable (`c''at`, `< redirect`, `python -c`). The honest value prop is "prevent accidental and naive secret reads"; the Read/Edit deny + `permissions.deny` is the reliable layer. The secret-glob list is an editable array at the top of the hook.

## Alternatives considered
- **`permissions.deny` only (no hook).** Rejected: the plugin path ships no `settings.json`, so plugin users would have zero protection; and deny matchers do not catch `cat ~/.ssh/id_rsa` via Bash.
- **Extend `safety-gate.sh`.** Rejected: `safety-gate` is registered for Bash only and is single-purpose (block destruction); adding Read/Edit matchers and a read-deny concern muddies it. (Per SPEC-014, the destructive-pattern *additions*, DROP TABLE / `git reset --hard` / kubectl delete, DO belong in safety-gate, as the same concern.)
- **Claim exfil-proofing.** Rejected: a bash reader denylist cannot be exfil-proof; claiming so would violate the kit's own "no phantom features." Scoped honestly instead (Known limitation in SPEC-014).

## Consequences
- The kit goes from 12 to 14 hooks (secrets-guard + commit-format, both from SPEC-014). `test-hooks.sh` count and `test-meta.sh` parity updated.
- `install.sh` now unions `permissions.deny` on merge (previously merged only `.hooks`); uninstall leaves deny entries in place (conservative: removing only the kit's entries from a merged list is not reliably possible, and extra deny is safe).
- A new runtime log `~/.claude/dwarves-kit/logs/secrets-guard.log` (path + tool, never contents).
- Source: SPEC-014; Trail of Bits `claude-code-config` deny-list (https://github.com/trailofbits/claude-code-config) + claudekit `file-guard` (https://github.com/carlrannaberg/claudekit). Sibling guardrail decisions in the same spec: commit-format gate (GSD), phantom-impl check (claudekit), safety-gate merge-ins (gstack).
