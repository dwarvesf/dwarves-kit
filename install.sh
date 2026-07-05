#!/bin/bash
# dwarves-kit installer
# Merges hooks into ~/.claude/settings.json, symlinks commands and skills.
# Idempotent: safe to re-run.
#
# v1.1: Fixed jq merge (concat arrays, don't deduplicate by matcher).
# Added --uninstall flag. Backs up settings.json before modifying.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"   # overridable for fixture installs (SPEC-066)
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

  # Remove skills (glob over every skills/*/SKILL.md the kit ships, not a hardcoded
  # single name, so a newly-promoted skill uninstalls too without an install.sh edit).
  for SKILL_FILE in "$KIT_DIR/skills/"*/SKILL.md; do
    [ -f "$SKILL_FILE" ] || continue
    SKILL_NAME="$(basename "$(dirname "$SKILL_FILE")")"
    if [ -d "$CLAUDE_DIR/skills/$SKILL_NAME" ]; then
      rm -rf "$CLAUDE_DIR/skills/$SKILL_NAME"
      echo "[ok] Removed skill: $SKILL_NAME"
    fi
  done

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
      # symlinks (pre-SPEC-066) and copied files (SPEC-066) both belong to the kit
      { [ -L "$LINK" ] || [ -f "$LINK" ]; } && rm "$LINK"
    done
    # Companion *.py/*.json files installed alongside a hooks/*.sh shim (see install,
    # step 1b); hooks.json (the plugin manifest) is excluded, matching install.
    for AUX_FILE in "$KIT_DIR/hooks/"*.py "$KIT_DIR/hooks/"*.json; do
      [ -f "$AUX_FILE" ] || continue
      [ "$(basename "$AUX_FILE")" = "hooks.json" ] && continue
      LINK="$HOOKS_DEST/$(basename "$AUX_FILE")"
      { [ -L "$LINK" ] || [ -f "$LINK" ]; } && rm "$LINK"
    done
    rmdir "$HOOKS_DEST" 2>/dev/null && echo "[ok] Removed hooks directory: $HOOKS_DEST"
  fi

  # Remove the lib we deployed (SPEC-045; symlink pre-066, real dir post-066).
  LIB_DEST="$CLAUDE_DIR/dwarves-kit/lib"
  if [ -L "$LIB_DEST" ]; then
    rm "$LIB_DEST" && echo "[ok] Removed lib symlink: $LIB_DEST"
  elif [ -d "$LIB_DEST" ] && [ -f "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" ]; then
    rm -rf "$LIB_DEST" && echo "[ok] Removed copied lib dir: $LIB_DEST"
  fi

  # Remove the operate-contract files (SPEC-049 symlinks, or SPEC-066 copies recorded in
  # the stamp's managed= list; a user's own file is never in the list and never removed).
  UNMANAGED="$(grep '^managed=' "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" 2>/dev/null | cut -d= -f2- || true)"
  for CONTRACT in AGENTS.md WORKFLOW.md; do
    LINK="$CLAUDE_DIR/dwarves-kit/$CONTRACT"
    if [ -L "$LINK" ]; then rm "$LINK" && echo "[ok] Removed $CONTRACT symlink: $LINK"
    elif [ -f "$LINK" ] && printf '%s' " $UNMANAGED " | grep -q " $CONTRACT "; then
      rm "$LINK" && echo "[ok] Removed kit-managed $CONTRACT: $LINK"
    fi
  done
  [ -f "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" ] && rm "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" && echo "[ok] Removed install stamp"
  for CONTRACT in AGENTS.md WORKFLOW.md; do
    LINK="$CLAUDE_DIR/dwarves-kit/$CONTRACT"
    if [ -L "$LINK" ]; then rm "$LINK" && echo "[ok] Removed $CONTRACT symlink: $LINK"; fi
  done

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

# --- Plugin-aware compat mode --------------------------------------------
# If the kit is already installed as a Claude Code plugin, the plugin provides
# the hooks, commands, agents, and lib/ at runtime via ${CLAUDE_PLUGIN_ROOT}.
# Running the full bash install here would DOUBLE-register hooks (settings.json
# AND the plugin) and could pin a different lib/ version, which is exactly the
# "don't run both paths" hazard the README warns about.
#
# So on a plugin machine we do a COMPAT-ONLY install: symlink the legacy
# ~/.claude/dwarves-kit paths (lib, WORKFLOW.md, AGENTS.md) that docs still call
# as plain bash (`bash ~/.claude/dwarves-kit/lib/<x>.sh`, where CLAUDE_PLUGIN_ROOT
# is not set). No settings.json hooks, no flat commands. The symlinks track this
# checkout (KIT_DIR), which is also the marketplace source, so a `git pull`
# updates them. Force the full bash install with KIT_FORCE_FULL=1.
PLUGIN_LIB="$(ls -d "$CLAUDE_DIR"/plugins/cache/dwarves-marketplace/kit/*/lib 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "${PLUGIN_LIB:-}" ] && [ -z "${KIT_FORCE_FULL:-}" ]; then
  echo "[plugin detected] kit@dwarves-marketplace is installed; runtime comes from the plugin."
  echo "Doing a COMPAT-ONLY install (legacy path shims), not the full bash install,"
  echo "to avoid double-registering hooks."
  mkdir -p "$CLAUDE_DIR/dwarves-kit"
  for f in lib WORKFLOW.md AGENTS.md; do
    ln -sfn "$KIT_DIR/$f" "$CLAUDE_DIR/dwarves-kit/$f"
    echo "[ok] compat symlink ~/.claude/dwarves-kit/$f -> $KIT_DIR/$f"
  done
  echo ""
  echo "Legacy doc paths (bash ~/.claude/dwarves-kit/lib/*.sh) now resolve."
  echo "Full bash install anyway: KIT_FORCE_FULL=1 bash install.sh"
  exit 0
fi
# --- end plugin-aware compat mode ----------------------------------------

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
  # SPEC-066: COPY, never symlink. A symlinked hook follows the CHECKED-OUT BRANCH of
  # the clone, so switching branches silently swaps the live enforcement code (observed
  # 2026-06-08: a fixed safety-gate regressed to the old build mid-session). Copies pin
  # the installed version; upgrades are an explicit re-run of install.sh.
  for HOOK_FILE in "$KIT_DIR/hooks/"*.sh; do
    LINK="$HOOKS_DEST/$(basename "$HOOK_FILE")"
    if [ -L "$LINK" ] || [ -f "$LINK" ]; then
      rm "$LINK"
    fi
    cp "$HOOK_FILE" "$LINK" && chmod +x "$LINK"
  done
  # Companion files a hooks/*.sh shim `exec`s or reads by co-located path (e.g. the
  # kit-foldin *.py ports + their JSON data files) must land alongside it in
  # $HOOKS_DEST too, or the shim's realpath-relative lookup 404s post-install.
  # hooks.json (the plugin manifest) is excluded: it is not consulted at this path.
  for AUX_FILE in "$KIT_DIR/hooks/"*.py "$KIT_DIR/hooks/"*.json; do
    [ -f "$AUX_FILE" ] || continue
    [ "$(basename "$AUX_FILE")" = "hooks.json" ] && continue
    LINK="$HOOKS_DEST/$(basename "$AUX_FILE")"
    [ -L "$LINK" ] || [ -f "$LINK" ] && rm -f "$LINK"
    cp "$AUX_FILE" "$LINK"
  done
  echo "[ok] Copied hook scripts into $HOOKS_DEST/ (pinned; re-run install.sh to upgrade)"
fi

# 1c. Deploy lib/ so the gates (proof-ledger, gate-ledger) resolve from the stable
# install path even when pushing a CONSUMER repo (SPEC-045). A consumer repo has no
# lib/, and bash-install mode has no CLAUDE_PLUGIN_ROOT, so without this the ship-gate
# fails open in every repo but dwarves-kit itself. Copied, not symlinked (SPEC-066).
if [ -n "$DEST_REAL" ] && [ "$KIT_REAL" = "$DEST_REAL" ]; then
  echo "[ok] Kit is installed in place; lib already at \$HOME/.claude/dwarves-kit/lib/"
else
  LIB_DEST="$CLAUDE_DIR/dwarves-kit/lib"
  mkdir -p "$CLAUDE_DIR/dwarves-kit"
  [ -L "$LIB_DEST" ] && rm "$LIB_DEST"
  [ -d "$LIB_DEST" ] && [ ! -L "$LIB_DEST" ] && rm -rf "$LIB_DEST"
  cp -R "$KIT_DIR/lib" "$LIB_DEST"
  echo "[ok] Copied lib into $LIB_DEST (pinned, SPEC-066)"
fi

# 1d. Deploy the operate-contract files so they resolve from the stable install path. adopt.sh
# needs a source AGENTS.md at $KIT_ROOT; gate-ledger reads the lane x phase matrix from
# $KIT_ROOT/WORKFLOW.md. Without these, adopt + the lane gate are broken from the install
# (SPEC-049). Copied and version-pinned, mirroring hooks + lib (SPEC-066).
if [ -n "$DEST_REAL" ] && [ "$KIT_REAL" = "$DEST_REAL" ]; then
  echo "[ok] Kit is installed in place; AGENTS.md + WORKFLOW.md already at \$HOME/.claude/dwarves-kit/"
else
  mkdir -p "$CLAUDE_DIR/dwarves-kit"
  # A real file is kit-managed ONLY if a prior run recorded it in the stamp's managed=
  # list; presence of the stamp alone is not enough (review HIGH: the stamp is written by
  # the same run that first sees the user's file, so stamp-presence destroys it on run 2).
  PRIOR_MANAGED=""
  [ -f "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" ] \
    && PRIOR_MANAGED="$(grep '^managed=' "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" 2>/dev/null | cut -d= -f2- || true)"
  MANAGED_CONTRACTS=""
  COPIED_CONTRACTS=""
  for CONTRACT in AGENTS.md WORKFLOW.md; do
    LINK="$CLAUDE_DIR/dwarves-kit/$CONTRACT"
    if [ -L "$LINK" ]; then
      rm "$LINK"                              # refresh a stale symlink
    elif [ -e "$LINK" ] && ! printf '%s' " $PRIOR_MANAGED " | grep -q " $CONTRACT "; then
      # A real file never recorded as kit-managed = the user's own file; leave it intact
      # (clobbering would be silent data loss, the SPEC-049 review rule, made durable).
      echo "[skip] $CONTRACT at $LINK is a user file (not in the stamp's managed list); leaving it untouched"
      continue
    fi
    cp "$KIT_DIR/$CONTRACT" "$LINK"
    MANAGED_CONTRACTS="$MANAGED_CONTRACTS $CONTRACT"
    COPIED_CONTRACTS="$COPIED_CONTRACTS $CONTRACT"
  done
  if [ -n "$COPIED_CONTRACTS" ]; then
    echo "[ok] Copied$COPIED_CONTRACTS into $CLAUDE_DIR/dwarves-kit/ (pinned, SPEC-066)"
  else
    echo "[ok] Contract files left as user files (none kit-managed)"
  fi
fi

# 1e. Version stamp (SPEC-066): records WHAT is installed so kit-health can flag a stale
# install (the upgrade path is: pull the repo, re-run install.sh). Skipped for in-place
# installs (the clone IS the install).
if [ -z "$DEST_REAL" ] || [ "$KIT_REAL" != "$DEST_REAL" ]; then
  {
    echo "version=$(cat "$KIT_DIR/VERSION" 2>/dev/null || echo unknown)"
    echo "sha=$(git -C "$KIT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "managed=${MANAGED_CONTRACTS# }"
  } > "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP"
  echo "[ok] Stamped install: $(tr '\n' ' ' < "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP")"
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

# 4. Copy skills (symlinks don't always work for skills). Loop over every
# skills/*/SKILL.md the kit ships (glob, not a hardcoded single skill), so a newly
# promoted top-level skill installs regardless of merge order with whatever branch
# added it.
for SKILL_FILE in "$KIT_DIR/skills/"*/SKILL.md; do
  [ -f "$SKILL_FILE" ] || continue
  SKILL_NAME="$(basename "$(dirname "$SKILL_FILE")")"
  mkdir -p "$CLAUDE_DIR/skills/$SKILL_NAME"
  cp "$SKILL_FILE" "$CLAUDE_DIR/skills/$SKILL_NAME/SKILL.md"
  echo "[ok] Installed skill: $SKILL_NAME"
done

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
mkdir -p "$CLAUDE_DIR/dwarves-kit/logs"
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
echo "Tip: Adopt a repo into the kit (injects AGENTS.md + a CLAUDE.md pointer + the proof"
echo "marker, idempotently, and wires the classifiers so the ship-gate engages):"
echo "  bash $KIT_DIR/lib/adopt.sh <repo-dir>      # or run /kit:adopt from inside the repo"
echo ""
echo "To uninstall: bash $KIT_DIR/install.sh --uninstall"
