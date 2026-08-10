#!/usr/bin/env bash
# cloud-session-start.sh -- SessionStart hook: assemble the cloud working layout.
#
# Registered with matcher "startup|resume". WITHOUT that matcher this fires on
# every `clear` and every auto-compaction too, re-running the whole assembly
# mid-session (the SessionStart matcher set is startup, resume, clear, compact,
# fork). A setup script does NOT cover this job: the platform skips the setup
# script whenever a cached environment exists, so a resumed session would get
# nothing. A SessionStart hook runs every session, as the session user, with the
# repo as cwd, and it degrades instead of aborting when it fails.
#
# Outside a cloud VM it exits immediately: a local machine already has the user
# CLAUDE.md, skills, plugins and workspace this rebuilds, and a local session
# must not pay for it. The cloud test is the documented CLAUDE_CODE_REMOTE
# variable plus Linux. It is NEVER a "does directory X exist" probe: an earlier
# version of this gate tested for a sibling checkout, so cloning that sibling
# (a normal, documented action) silently disabled the hook for the rest of the
# session.
#
# Output goes back as additionalContext so the SESSION sees what was assembled
# (the memory index to read, the rules file, any !! lines), not just the log.
# reloadSkills rides along because provision can install plugins: without it the
# new skills only appear in the NEXT session.
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0  # local CLI: nothing to rebuild
[ "$(uname -s)" = "Linux" ] || exit 0             # macOS: nothing to do

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROV="$SELF_DIR/../lib/cloud/provision.sh"
[ -f "$PROV" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
out="$(bash "$PROV" --repo-root "$ROOT" 2>&1)" || true

command -v python3 >/dev/null 2>&1 || exit 0

# Emit as additionalContext (model-visible). Keep it one JSON payload; python3
# does the escaping so a stray quote in the output cannot break the contract.
python3 - "$out" <<'PY' 2>/dev/null || exit 0
import json, sys
out = sys.argv[1] if len(sys.argv) > 1 else ""
msg = (
    "Cloud session provisioned (dwarves-kit SessionStart hook). Output:\n\n" + out +
    "\n\nFollow the cloud rules file named above for this session. "
    "Read .claude/memory/MEMORY.md and AGENTS.md before working. "
    "Kit CLIs are reachable by path under the kit install; there are no /kit: "
    "slash commands in a cloud VM."
)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": msg,
    # Documented SessionStart key: Claude Code re-scans the skill and command
    # directories after the SessionStart hooks complete, so skills the hook
    # installed are available in the same session. The doc scopes it to SKILLS
    # and commands; whether a plugin's hooks arm mid-session is NOT documented.
    # This is the honest ceiling, not a full plugin reload.
    "reloadSkills": True,
}}))
PY
exit 0
