#!/bin/bash
# dwarves-kit installer
# Merges hooks into ~/.claude/settings.json, symlinks commands and skills.
# Idempotent: safe to re-run.
#
# v1.1: Fixed jq merge (concat arrays, don't deduplicate by matcher).
# Added --uninstall flag. Backs up settings.json before modifying.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
BACKUP_DIR="$CLAUDE_DIR/backups"
KIT_MARKER="dwarves-kit"

# ============================================================
# UNINSTALL
# ============================================================
if [ "${1:-}" = "--uninstall" ]; then
  echo "=== dwarves-kit uninstaller ==="

  # Remove command symlinks
  for CMD_FILE in "$KIT_DIR/commands/"*.md; do
    CMD_NAME=$(basename "$CMD_FILE")
    LINK="$CLAUDE_DIR/commands/$CMD_NAME"
    if [ -L "$LINK" ]; then
      rm "$LINK"
      echo "[ok] Removed command: /${CMD_NAME%.md}"
    fi
  done

  # Remove skills
  if [ -d "$CLAUDE_DIR/skills/get-api-docs" ]; then
    rm -rf "$CLAUDE_DIR/skills/get-api-docs"
    echo "[ok] Removed skill: get-api-docs"
  fi

  # Remove agents
  for AGENT_FILE in "$KIT_DIR/agents/"*.md; do
    AGENT_NAME=$(basename "$AGENT_FILE")
    if [ -f "$CLAUDE_DIR/agents/$AGENT_NAME" ]; then
      rm "$CLAUDE_DIR/agents/$AGENT_NAME"
      echo "[ok] Removed agent: ${AGENT_NAME%.md}"
    fi
  done

  # Remove the hook links we created (and the dir if it is now empty). Only
  # symlinks are removed, so an in-place clone (KIT_DIR == ~/.claude/dwarves-kit,
  # where the scripts are real files) keeps its hooks; that layout is torn down by
  # deleting the clone, per the message at the end of this block.
  HOOKS_DEST="$CLAUDE_DIR/dwarves-kit/hooks"
  if [ -L "$HOOKS_DEST" ]; then
    rm "$HOOKS_DEST"
    echo "[ok] Removed hooks symlink: $HOOKS_DEST"
  elif [ -d "$HOOKS_DEST" ]; then
    for HOOK_FILE in "$KIT_DIR/hooks/"*.sh; do
      LINK="$HOOKS_DEST/$(basename "$HOOK_FILE")"
      [ -L "$LINK" ] && rm "$LINK"
    done
    rmdir "$HOOKS_DEST" 2>/dev/null && echo "[ok] Removed hooks directory: $HOOKS_DEST"
  fi

  # Remove dwarves-kit hooks from settings.json
  if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    # Backup first
    mkdir -p "$BACKUP_DIR"
    cp "$SETTINGS_FILE" "$BACKUP_DIR/settings-pre-uninstall-$(date +%Y%m%d-%H%M%S).json"

    # Remove any hook whose command path contains "dwarves-kit"
    CLEANED=$(jq '
      .hooks |= (
        to_entries | map(
          .value |= (
            map(
              .hooks |= map(select(.command | tostring | contains("dwarves-kit") | not))
            ) | map(select(.hooks | length > 0))
          )
        ) | from_entries
      )
    ' "$SETTINGS_FILE" 2>/dev/null)

    if [ -n "$CLEANED" ]; then
      echo "$CLEANED" | jq '.' > "$SETTINGS_FILE"
      echo "[ok] Removed dwarves-kit hooks from settings.json"
    else
      echo "[warn] Could not clean settings.json automatically. Remove dwarves-kit entries manually."
    fi
  fi

  echo ""
  echo "=== Uninstall complete ==="
  echo "Kit directory ($KIT_DIR) was NOT removed. Delete it manually if desired:"
  echo "  rm -rf $KIT_DIR"
  exit 0
fi

# ============================================================
# INSTALL
# ============================================================
echo "=== dwarves-kit installer ==="
echo "Kit location: $KIT_DIR"
echo ""

# Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills"

# 1. Make hook scripts executable
chmod +x "$KIT_DIR/hooks/"*.sh
echo "[ok] Hook scripts are executable"

# 1b. Ensure the hook scripts exist at the path settings.json references.
# settings.json hard-codes $HOME/.claude/dwarves-kit/hooks/<script>.sh, so the
# scripts must live there. Two layouts:
#   in-place : the kit was cloned to ~/.claude/dwarves-kit (README Option 2), so
#              KIT_DIR already IS ~/.claude/dwarves-kit and the scripts are in
#              place. Linking would point each script at itself, so skip it.
#   elsewhere: a dev checkout, CI, or template dir. Link each hooks/*.sh into
#              ~/.claude/dwarves-kit/hooks/ (per-file, like commands, so repo
#              edits stay live). Without this every hook fails at runtime with
#              "No such file or directory".
# NOTE: detection relies on ~/.claude/dwarves-kit NOT existing yet on a first
# out-of-place install. Do not mkdir "$CLAUDE_DIR/dwarves-kit" before this block,
# or the in-place branch could false-match and skip linking.
KIT_REAL="$(cd "$KIT_DIR" && pwd -P)"
DEST_REAL="$(cd "$CLAUDE_DIR/dwarves-kit" 2>/dev/null && pwd -P || true)"
if [ -n "$DEST_REAL" ] && [ "$KIT_REAL" = "$DEST_REAL" ]; then
  echo "[ok] Kit is installed in place; hooks already at \$HOME/.claude/dwarves-kit/hooks/"
else
  HOOKS_DEST="$CLAUDE_DIR/dwarves-kit/hooks"
  # A previous run may have left a directory symlink here; drop it so we own a real dir.
  [ -L "$HOOKS_DEST" ] && rm "$HOOKS_DEST"
  mkdir -p "$HOOKS_DEST"
  for HOOK_FILE in "$KIT_DIR/hooks/"*.sh; do
    LINK="$HOOKS_DEST/$(basename "$HOOK_FILE")"
    if [ -L "$LINK" ] || [ -f "$LINK" ]; then
      rm "$LINK"
    fi
    ln -s "$HOOK_FILE" "$LINK"
  done
  echo "[ok] Linked hook scripts into $HOOKS_DEST/"
fi

# 2. Merge settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  # No existing settings, just copy ours
  cp "$KIT_DIR/settings.json" "$SETTINGS_FILE"
  echo "[ok] Created $SETTINGS_FILE"
else
  if command -v jq >/dev/null 2>&1; then
    # Backup existing settings
    mkdir -p "$BACKUP_DIR"
    cp "$SETTINGS_FILE" "$BACKUP_DIR/settings-pre-install-$(date +%Y%m%d-%H%M%S).json"
    echo "[ok] Backed up existing settings.json"

    # First, remove any existing dwarves-kit hooks (idempotent reinstall)
    EXISTING_CLEAN=$(jq '
      .hooks |= (
        to_entries | map(
          .value |= (
            map(
              .hooks |= map(select(.command | tostring | contains("dwarves-kit") | not))
            ) | map(select(.hooks | length > 0))
          )
        ) | from_entries
      )
    ' "$SETTINGS_FILE" 2>/dev/null || cat "$SETTINGS_FILE")

    # Then merge: CONCAT arrays (don't deduplicate by matcher)
    # This preserves the user's existing hooks alongside ours
    MERGED=$(echo "$EXISTING_CLEAN" | jq --slurpfile kit "$KIT_DIR/settings.json" '
      . as $existing |
      $kit[0] as $new |
      ($new.hooks // {}) as $kh |
      .hooks = (
        ((.hooks // {}) | to_entries) + ($kh | to_entries)
        | group_by(.key)
        | map({
            key: .[0].key,
            value: [.[].value[]] | unique_by(.hooks[0].command // "")
          })
        | from_entries
      )
      | .permissions = ((.permissions // {}) + {deny: (((.permissions.deny // []) + ($new.permissions.deny // [])) | unique)})
    ' 2>/dev/null)

    if [ -n "$MERGED" ] && echo "$MERGED" | jq '.' >/dev/null 2>&1; then
      echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
      echo "[ok] Merged hooks into $SETTINGS_FILE (existing hooks preserved)"
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
  echo "[ok] Linked command: /${CMD_NAME%.md}"
done

# 4. Copy skills (symlinks don't always work for skills)
if [ -d "$KIT_DIR/skills/get-api-docs" ]; then
  mkdir -p "$CLAUDE_DIR/skills/get-api-docs"
  cp "$KIT_DIR/skills/get-api-docs/SKILL.md" "$CLAUDE_DIR/skills/get-api-docs/SKILL.md"
  echo "[ok] Installed skill: get-api-docs"
fi

# 4b. Install subagent definitions
if [ -d "$KIT_DIR/agents" ]; then
  mkdir -p "$CLAUDE_DIR/agents"
  for AGENT_FILE in "$KIT_DIR/agents/"*.md; do
    AGENT_NAME=$(basename "$AGENT_FILE")
    cp "$AGENT_FILE" "$CLAUDE_DIR/agents/$AGENT_NAME"
    echo "[ok] Installed agent: ${AGENT_NAME%.md}"
  done
fi

# 5. Create log directory
mkdir -p "$HOME/.claude/dwarves-kit/logs"
echo "[ok] Log directory ready"

# 6. Install path-scoped rules templates
if [ -d "$KIT_DIR/rules" ]; then
  mkdir -p ".claude/rules"
  RULES_INSTALLED=0
  for RULE_FILE in "$KIT_DIR/rules/"*.md; do
    RULE_NAME=$(basename "$RULE_FILE")
    # Only copy if the project doesn't already have this rule
    if [ ! -f ".claude/rules/$RULE_NAME" ]; then
      cp "$RULE_FILE" ".claude/rules/$RULE_NAME"
      RULES_INSTALLED=$((RULES_INSTALLED + 1))
      echo "[ok] Installed rule template: $RULE_NAME"
    else
      echo "[skip] Rule exists: .claude/rules/$RULE_NAME (not overwriting)"
    fi
  done
  if [ "$RULES_INSTALLED" -eq 0 ]; then
    echo "[ok] All rule templates already present in .claude/rules/"
  fi
  echo "  Customize paths in YAML frontmatter to match your project structure."
  echo "  NOTE: path-scoped rules only activate when Claude READS matching files."
  echo "  They must live in project .claude/rules/, not ~/.claude/rules/."
fi

# 7. Merge statusLine config
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
  HAS_STATUSLINE=$(jq '.statusLine // null' "$SETTINGS_FILE" 2>/dev/null)
  if [ "$HAS_STATUSLINE" = "null" ]; then
    STATUSLINE_CMD=$(jq -r '.statusLine.command' "$KIT_DIR/settings.json" 2>/dev/null)
    if [ -n "$STATUSLINE_CMD" ] && [ "$STATUSLINE_CMD" != "null" ]; then
      jq --arg cmd "$STATUSLINE_CMD" '.statusLine = {"command": $cmd}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      echo "[ok] Registered statusLine"
    fi
  else
    echo "[ok] statusLine already configured (not overwriting)"
  fi
fi

# 6. Verify
echo ""
echo "=== Verification ==="
echo "Hooks directory: $KIT_DIR/hooks/"
ls -1 "$KIT_DIR/hooks/"*.sh 2>/dev/null | while read f; do echo "  [hook] $(basename "$f")"; done

echo "Commands:"
ls -1 "$CLAUDE_DIR/commands/"*.md 2>/dev/null | while read f; do
  NAME=$(basename "$f" .md)
  echo "  /$NAME"
done

echo "Skills:"
find "$CLAUDE_DIR/skills" -name "SKILL.md" 2>/dev/null | while read f; do
  DIR=$(dirname "$f")
  echo "  $(basename "$DIR")"
done

echo "Agents:"
ls -1 "$CLAUDE_DIR/agents/"*.md 2>/dev/null | while read f; do
  NAME=$(basename "$f" .md)
  echo "  $NAME"
done

echo ""
echo "=== Done ==="
echo "Start a new Claude Code session to activate hooks."
echo "Run /start to detect project state and get a suggestion."
echo ""
echo "Tip: Copy CLAUDE.md template to your project root:"
echo "  cp $KIT_DIR/CLAUDE.md ./CLAUDE.md"
echo ""
echo "Tip: If your project does not already have an AGENTS.md, copy one to its root:"
echo "  cp $KIT_DIR/AGENTS.md ./AGENTS.md"
echo ""
echo "To uninstall: bash $KIT_DIR/install.sh --uninstall"
