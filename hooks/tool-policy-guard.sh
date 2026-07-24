#!/bin/bash
# tool-policy-guard.sh -- PreToolUse hook enforcing the tool-choice policy.
#
# The policy file (~/.claude/dwarves-kit/tool-policy.json by default, override
# with KIT_TOOL_POLICY) maps tool-name substrings to allow | ask | deny per
# domain (browser, computer_use, ...). It is the enforcement half of the
# dashboard's Config & tool policy page: edit there, export, save here.
#
#   deny  -> exit 2 with the preferred rung in the message (the call is blocked)
#   ask   -> exit 0 with a warning on stderr naming the preferred rung
#   allow / no match / no policy file -> exit 0 silently (fail open by design:
#            a missing or malformed policy must never brick every tool call)
#
# Input: hook JSON on stdin (tool_name field). Stdlib python3 only. The payload
# rides an env var because the python program itself arrives on stdin.
set -euo pipefail

POLICY="${KIT_TOOL_POLICY:-$HOME/.claude/dwarves-kit/tool-policy.json}"
[ -f "$POLICY" ] || exit 0

HOOK_PAYLOAD="$(cat || true)"
export HOOK_PAYLOAD

python3 - "$POLICY" <<'PY'
import json
import os
import sys

try:
    policy = json.load(open(sys.argv[1]))
    payload = json.loads(os.environ.get("HOOK_PAYLOAD", "") or "{}")
except Exception:
    sys.exit(0)  # fail open: a broken policy must not block every tool
tool = payload.get("tool_name", "")
if not tool:
    sys.exit(0)
# v2 schema nests domains under "capabilities" and carries per-provider actions;
# v1 keeps domains at the top level. Normalize both into (domain, prefer, rules).
domains = policy.get("capabilities", policy)
norm = {}
for domain, spec in domains.items():
    if domain.startswith("_") or not isinstance(spec, dict):
        continue
    rules = list(spec.get("rules", []))
    for pv in spec.get("providers", []):
        if pv.get("match"):
            rules.append({"match": pv["match"], "action": pv.get("action", "allow"),
                          "note": pv.get("note", "")})
    norm[domain] = {"prefer": spec.get("prefer") or spec.get("preferred", ""), "rules": rules}
for domain, spec in norm.items():
    for rule in spec["rules"]:
        if rule.get("match") and rule["match"] in tool:
            action = rule.get("action", "allow")
            prefer = spec["prefer"]
            note = rule.get("note", "")
            if action == "deny":
                print(f"tool-policy-guard: {tool} is DENIED by policy ({domain}). "
                      f"Preferred: {prefer}. {note}", file=sys.stderr)
                sys.exit(2)
            if action == "ask":
                print(f"tool-policy-guard: {tool} is policy-controlled ({domain}). "
                      f"Preferred rung: {prefer}. {note} "
                      f"Proceed only if the lighter rung is genuinely exhausted.",
                      file=sys.stderr)
            sys.exit(0)
sys.exit(0)
PY
