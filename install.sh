#!/bin/bash
# dwarves-kit installer
# Merges hooks into ~/.claude/settings.json, symlinks commands and skills.
# Idempotent: safe to re-run.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "=== dwarves-kit installer ==="
echo "Kit location: $KIT_DIR"
echo ""

# Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills"

# 1. Make hook scripts executable
chmod +x "$KIT_DIR/hooks/"*.sh
echo "[ok] Hook scripts are executable"

# 2. Merge settings.json (key-level merge using jq)
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  # No existing settings, just copy ours
  cp "$KIT_DIR/settings.json" "$SETTINGS_FILE"
  echo "[ok] Created $SETTINGS_FILE"
else
  # Merge: combine hook arrays, preserve everything else
  if command -v jq >/dev/null 2>&1; then
    MERGED=$(jq -s '
      .[0] as $existing |
      .[1] as $kit |
      $existing * {
        hooks: (
          ($existing.hooks // {}) as $eh |
          ($kit.hooks // {}) as $kh |
          ($eh | keys) + ($kh | keys) | unique | map(
            . as $key |
            { ($key): (($eh[$key] // []) + ($kh[$key] // []) | unique_by(.matcher // "default")) }
          ) | add // {}
        )
      }
    ' "$SETTINGS_FILE" "$KIT_DIR/settings.json" 2>/dev/null)

    if [ -n "$MERGED" ]; then
      echo "$MERGED" > "$SETTINGS_FILE"
      echo "[ok] Merged hooks into $SETTINGS_FILE"
    else
      echo "[warn] jq merge failed. Manual merge needed."
      echo "       Copy hooks from $KIT_DIR/settings.json into $SETTINGS_FILE"
    fi
  else
    echo "[warn] jq not installed. Cannot auto-merge settings.json."
    echo "       Install jq: brew install jq (macOS) or apt install jq (Linux)"
    echo "       Then re-run this script, or manually merge $KIT_DIR/settings.json"
  fi
fi

# 3. Symlink commands
for CMD_FILE in "$KIT_DIR/commands/"*.md; do
  CMD_NAME=$(basename "$CMD_FILE")
  LINK="$CLAUDE_DIR/commands/$CMD_NAME"
  if [ -L "$LINK" ] || [ -f "$LINK" ]; then
    rm "$LINK"
  fi
  ln -s "$CMD_FILE" "$LINK"
  echo "[ok] Linked command: /user:${CMD_NAME%.md}"
done

# 4. Copy skills (symlinks don't always work for skills)
if [ -d "$KIT_DIR/skills/get-api-docs" ]; then
  mkdir -p "$CLAUDE_DIR/skills/get-api-docs"
  cp "$KIT_DIR/skills/get-api-docs/SKILL.md" "$CLAUDE_DIR/skills/get-api-docs/SKILL.md"
  echo "[ok] Installed skill: get-api-docs"
fi

# 5. Verify
echo ""
echo "=== Verification ==="
echo "Hooks directory: $KIT_DIR/hooks/"
ls -1 "$KIT_DIR/hooks/"*.sh 2>/dev/null | while read f; do echo "  [hook] $(basename "$f")"; done

echo "Commands:"
ls -1 "$CLAUDE_DIR/commands/"*.md 2>/dev/null | while read f; do
  NAME=$(basename "$f" .md)
  echo "  /user:$NAME"
done

echo "Skills:"
find "$CLAUDE_DIR/skills" -name "SKILL.md" 2>/dev/null | while read f; do
  DIR=$(dirname "$f")
  echo "  $(basename "$DIR")"
done

echo ""
echo "=== Done ==="
echo "Start a new Claude Code session to activate hooks."
echo "Run /user:think to challenge an idea, /user:spec to generate a spec."
echo ""
echo "Tip: Copy CLAUDE.md template to your project root:"
echo "  cp $KIT_DIR/CLAUDE.md ./CLAUDE.md"
