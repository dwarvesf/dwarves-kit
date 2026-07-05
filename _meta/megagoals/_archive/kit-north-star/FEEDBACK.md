# FEEDBACK, kit-north-star

Append-only skill-meta observations recorded DURING the run: friction in plan-for-mega-goal itself, missing tooling, or codebase issues that complicated the work. Audience: the skill maintainer (Han), post-run. Not the lab record (that is ops-toolkit `_meta/LAB_LOG.md`).

Format: `- <YYYY-MM-DD>: <observation> — <suggested improvement>`

- 2026-06-10: dwarves-kit ship-gate (PreToolUse hook) evaluates the SESSION cwd, not the command's cwd: pushing from an ops-toolkit session with a cd-prefixed compound command ran the gate against ops-toolkit state, misresolved slug `ambient-agent-spec` from unrelated working-tree state, and blocked a dwarves-kit push whose own branch carried a gate-green proof. Also: the gate engages by pattern-matching the command STRING, so prose inside a heredoc containing push-like phrases re-triggers it (same family as the safety-gate text false-positives seen 2026-06-10). Suggested: derive the repo from the command's cd prefix or the remote; anchor the engage-regex to the command head. Worked around via the audited proof-ledger override.
