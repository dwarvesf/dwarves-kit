#!/usr/bin/env bash
# install.sh: idempotent wiring of cc-self-improve into Claude Code settings.json.
#   - skill-review hook on PreCompact + SessionEnd (async)
#   - sessionstart-surface hook on SessionStart (async)
# Backs up settings.json first; writes atomically; running twice adds NO duplicate entries.
# CC_SI_SETTINGS overrides the target (tests). Never wires anything live by itself beyond the merge.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

SETTINGS="$(_expand "${CC_SI_SETTINGS:-$HOME/.claude/settings.json}")"
HOOK_SKILL="$ROOT/hooks/skill-review.sh"
HOOK_SURFACE="$ROOT/hooks/sessionstart-surface.sh"

mkdir -p "$(dirname "$SETTINGS")" 2>/dev/null || true
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then echo "install: $SETTINGS is not valid JSON, aborting" >&2; exit 1; fi

cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

tmp="$(mktemp)"
jq --arg skill "$HOOK_SKILL" --arg surface "$HOOK_SURFACE" '
  def add($event; $cmd):
    .hooks[$event] = ((.hooks[$event] // [])
      | if any(.[]?; ((.hooks // [])[]?.command) == $cmd) then .
        else . + [{matcher:"", hooks:[{type:"command", command:$cmd, async:true}]}] end);
  . | (.hooks //= {})
    | add("PreCompact"; $skill)
    | add("SessionEnd"; $skill)
    | add("SessionStart"; $surface)
' "$SETTINGS" > "$tmp"

if jq -e . "$tmp" >/dev/null 2>&1; then
  mv "$tmp" "$SETTINGS"
  echo "install: wired skill-review (PreCompact+SessionEnd) + surfacing (SessionStart) into $SETTINGS"
else
  echo "install: jq produced invalid JSON; left $SETTINGS unchanged (see $tmp)" >&2; exit 1
fi

# Runtime state + config (idempotent).
mkdir -p "$CC_SI_STATE_DIR/state" 2>/dev/null || true
if [ ! -f "$CC_SI_STATE_DIR/config.toml" ]; then
  cp "$ROOT/config/config.example.toml" "$CC_SI_STATE_DIR/config.toml" 2>/dev/null \
    && echo "install: seeded $CC_SI_STATE_DIR/config.toml"
fi
echo "install: done. Opt-in/tune via $CC_SI_STATE_DIR/config.toml. Uninstall: deploy/uninstall.sh"
