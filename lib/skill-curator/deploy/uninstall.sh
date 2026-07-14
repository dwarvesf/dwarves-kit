#!/usr/bin/env bash
# uninstall.sh: remove ONLY skill-curator's hook entries from settings.json (any hook group whose
# command path contains "skill-curator"). Backs up first; writes atomically. Leaves runtime state
# (ledger, proposals) in place , drafts are the user's, not ours to delete. SKILL_CURATOR_SETTINGS overrides.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

SETTINGS="$(_expand "${SKILL_CURATOR_SETTINGS:-$HOME/.claude/settings.json}")"
[ -f "$SETTINGS" ] || { echo "uninstall: no $SETTINGS, nothing to do"; exit 0; }
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then echo "uninstall: $SETTINGS not valid JSON, aborting" >&2; exit 1; fi

cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

tmp="$(mktemp)"
jq '
  if (.hooks // {}) == {} then .
  else .hooks = (.hooks | to_entries
    | map(.value = (.value | map(select(
        ((.hooks // []) | map(.command // "") | any(test("skill-curator"))) | not
      ))))
    | from_entries)
  end
' "$SETTINGS" > "$tmp"

if jq -e . "$tmp" >/dev/null 2>&1; then
  mv "$tmp" "$SETTINGS"
  echo "uninstall: removed skill-curator hook entries from $SETTINGS (state/ledger/proposals kept)"
else
  echo "uninstall: jq produced invalid JSON; left $SETTINGS unchanged (see $tmp)" >&2; exit 1
fi
