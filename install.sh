#!/bin/bash
# dwarves-kit installer
# Merges hooks into ~/.claude/settings.json, symlinks commands and skills.
# Idempotent: safe to re-run.
#
# v1.1: Fixed jq merge (concat arrays, don't deduplicate by matcher).
# Added --uninstall flag. Backs up settings.json before modifying.
#
# v1.2 (ID-277 SG-04): layered install. The spine (safety-gate, ship-gate,
# spec-drift-guard, secrets-guard, commit-format, anti-rationalization) is always
# wired; everything else is an opt-in module via `--with <a,b,c>`, recorded in a
# `kit.toml [modules]` manifest. A re-run is additive (never un-wires a previously
# wired hook); `--prune --with <modules>` is the explicit trim path.

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

  # Remove the bin/ stable-entrypoint dir we deployed (SPEC-184).
  BIN_DEST="$CLAUDE_DIR/dwarves-kit/bin"
  if [ -L "$BIN_DEST" ]; then
    rm "$BIN_DEST" && echo "[ok] Removed bin symlink: $BIN_DEST"
  elif [ -d "$BIN_DEST" ] && [ -f "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" ]; then
    rm -rf "$BIN_DEST" && echo "[ok] Removed copied bin dir: $BIN_DEST"
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
  for CONTRACT in AGENTS.md WORKFLOW.md docs/WORKFLOW.md; do
    LINK="$CLAUDE_DIR/dwarves-kit/$CONTRACT"
    if [ -L "$LINK" ]; then rm "$LINK" && echo "[ok] Removed $CONTRACT symlink: $LINK"
    elif [ -f "$LINK" ] && printf '%s' " $UNMANAGED " | grep -q " $CONTRACT "; then
      rm "$LINK" && echo "[ok] Removed kit-managed $CONTRACT: $LINK"
    fi
  done
  [ -f "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" ] && rm "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" && echo "[ok] Removed install stamp"
  for CONTRACT in AGENTS.md WORKFLOW.md docs/WORKFLOW.md; do
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

  # Remove the module manifest (ID-277 SG-04); it is meaningless without an install.
  if [ -f "$CLAUDE_DIR/dwarves-kit/kit.toml" ]; then
    rm "$CLAUDE_DIR/dwarves-kit/kit.toml"
    echo "[ok] Removed module manifest: kit.toml"
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

# --- Layered install: spine + opt-in modules (Decision B, ID-277 SG-04) --
# The core spine (safety-gate, ship-gate, spec-drift-guard, secrets-guard,
# commit-format, anti-rationalization) is ALWAYS wired. Everything else is an
# optional module, wired only when named via `--with <a,b,c>`. A `kit.toml
# [modules]` manifest RECORDS the enabled set (for `--with`-less re-installs
# and future discovery) -- it is a shell-install RECORD, never a runtime
# feature-registry: no hook reads it (see tests/test-no-runtime-manifest-read.sh).
KIT_KNOWN_MODULES="board session advisor cosmetic queue stats quiz_gate weekend_batch bridge worktree money_gate prose_rag"
KIT_SPINE_HOOKS="safety-gate.sh ship-gate.sh spec-drift-guard.sh secrets-guard.sh commit-format.sh anti-rationalization.sh"

# module -> its hook script basenames (space-separated; empty = hookless, e.g.
# queue/stats/quiz_gate/weekend_batch/bridge/worktree are commands/skills/CLIs with
# no hook to gate -- still valid --with names, recorded in the manifest for discovery).
kit_module_hooks() {
  case "$1" in
    board) echo "backlog-stage.sh" ;;
    session) echo "context-readiness.sh output-offload.sh pre-compact-backup.sh post-compact-reinject.sh session-state-save.sh harvest.sh citation-guard.sh" ;;
    advisor) echo "context-hints.sh" ;;
    cosmetic) echo "auto-format.sh notification.sh slop-cleaner.sh statusline.sh codebase-index.sh permission-auto-approve.sh" ;;
    money_gate) echo "money-gate.sh" ;;
    prose_rag) echo "prose-rag.sh" ;;
    *) echo "" ;;
  esac
}

# module -> the CLIs it exposes on PATH (~/.local/bin). Each name is a stable
# bin/<name> entrypoint (SPEC-184). Replaces the consumer-side snapshot-symlink
# dance (ops-toolkit cc-elevation redeploy.sh) for kit-owned tools.
kit_module_clis() {
  case "$1" in
    board) echo "add-backlog" ;;
    session) echo "cc-intel cc-observe cc-semantic cc-recall cc-vps-report" ;;
    worktree) echo "worktree-provision" ;;
    prose_rag) echo "prose-rag" ;;
    *) echo "" ;;
  esac
}

# kit_write_cli_shim <name> <target> -- write ~/.local/bin/<name> as an exec-shim to
# <target>. A wrapper FILE, not a symlink: bin/ entrypoints resolve ../lib relative
# to BASH_SOURCE without realpath, so a symlink at ~/.local/bin would break them.
# Never clobbers a user-owned file: writes only when the path is absent, a symlink
# (e.g. a stale cc-elevation link, the exact thing this replaces), or a prior shim.
kit_write_cli_shim() {
  local name="$1" target="$2" dst="$HOME/.local/bin/$1"
  if [ -e "$dst" ] && [ ! -L "$dst" ] && ! grep -q "dwarves-kit CLI shim" "$dst" 2>/dev/null; then
    echo "[warn] $dst exists and is not kit-managed; left untouched"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n# dwarves-kit CLI shim (installed by install.sh; re-run install.sh to refresh)\nexec "%s" "$@"\n' "$target" > "$dst.tmp.$$"
  chmod +x "$dst.tmp.$$"
  mv -f "$dst.tmp.$$" "$dst"
}

# kit_toml_modules_section_true <file> -- print the bare keys set `= true` WITHIN
# the [modules] section only (SPEC-183). Scoped on purpose: the full-schema kit.toml
# (repo-root default + its install-rendered copy) legitimately ships `= true`
# defaults in OTHER sections too ([ledger] telemetry, [mega] tier4_close, [gate]
# understanding_gate, [features] learning_ledger); a file-wide grep would
# misidentify those as "modules". INVARIANT: only ever call this on an
# INSTALL-RENDERED kit.toml (i.e. $KIT_TOML below), never the repo-root default --
# the match requires the line to end right after `true` with no trailing comment,
# which `kit_render_install_toml` guarantees for [modules] lines (it always emits
# a bare `key = true|false`), but the repo-root file's [modules] section has
# inline `#` comments on several keys and would silently under-match.
# `tests/test-install-modules.sh` keeps an identical `modules_section_true()`
# (can't source this file directly -- it's a full script, not a library); keep
# both in sync if this awk changes.
kit_toml_modules_section_true() {
  awk '
    /^\[modules\]/ { insec = 1; next }
    /^\[/          { insec = 0 }
    insec && /^[a-z_]+[[:space:]]*=[[:space:]]*true[[:space:]]*$/ {
      key = $0; sub(/[[:space:]]*=.*/, "", key); print key
    }
  ' "$1" 2>/dev/null
}

# kit_render_install_toml <src-default> <dst-install> -- render the install kit.toml
# (SPEC-183): copy the repo-root default VERBATIM (full schema, every section), then
# recompute ONLY the [modules] section's booleans from this run's actual enabled set
# (uses the caller's $KIT_ENABLED_MODULES). Every other section (`[ledger]`, `[mega]`,
# `[gate]`, `[features]`, `[team]`) rides through unchanged, so the install copy is
# the full schema, not just the old minimal manifest.
kit_render_install_toml() {
  local src="$1" dst="$2"
  {
    echo "# --- Rendered by install.sh from the repo-root kit.toml + --with (SPEC-183). ---"
    echo "# Do not hand-edit the [modules] section; re-run \`install.sh --with <modules>\`"
    echo "# (or \`--prune --with <modules>\` to trim) to change it. Every other section is"
    echo "# copied verbatim from the repo-root default; edit that file upstream to change a"
    echo "# default, or this project's .kit.toml to override just this project."
    echo ""
    awk -v mods=" $KIT_ENABLED_MODULES " '
      /^\[/ { insec = ($0 ~ /^\[modules\]/); print; next }
      insec && /^[a-z_]+[[:space:]]*=/ {
        key = $0; sub(/[[:space:]]*=.*/, "", key)
        if (key == "team_mode") { print "team_mode = false"; next }
        val = (index(mods, " " key " ") > 0) ? "true" : "false"
        print key " = " val
        next
      }
      { print }
    ' "$src"
  } > "$dst"
}

KIT_WITH_ARG=""
KIT_PRUNE=0
KIT_ARGS=("$@")
_i=0
while [ $_i -lt ${#KIT_ARGS[@]} ]; do
  case "${KIT_ARGS[$_i]}" in
    --with)
      _i=$((_i + 1))
      KIT_WITH_ARG="${KIT_ARGS[$_i]:-}"
      ;;
    --with=*)
      KIT_WITH_ARG="${KIT_ARGS[$_i]#--with=}"
      ;;
    --prune)
      KIT_PRUNE=1
      ;;
  esac
  _i=$((_i + 1))
done
unset _i

# Validate + normalize the requested module list (clean error on unknown/reserved).
KIT_REQUESTED_MODULES=""
if [ -n "$KIT_WITH_ARG" ]; then
  IFS=',' read -ra _KIT_REQ <<< "$KIT_WITH_ARG"
  for _m in "${_KIT_REQ[@]}"; do
    _m="$(echo "$_m" | xargs)"
    [ -z "$_m" ] && continue
    if [ "$_m" = "team_mode" ]; then
      echo "[error] 'team_mode' is a reserved, not-yet-installable module (parked; see DECISIONS.md Decision C)." >&2
      exit 1
    fi
    case " $KIT_KNOWN_MODULES " in
      *" $_m "*) KIT_REQUESTED_MODULES="$KIT_REQUESTED_MODULES $_m" ;;
      *)
        echo "[error] unknown module: '$_m'. Known modules: $KIT_KNOWN_MODULES" >&2
        exit 1
        ;;
    esac
  done
  unset _m
fi
KIT_REQUESTED_MODULES="$(echo "$KIT_REQUESTED_MODULES" | xargs)"

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
  mkdir -p "$CLAUDE_DIR/dwarves-kit/docs"
  for f in bin lib WORKFLOW.md AGENTS.md docs/WORKFLOW.md; do
    ln -sfn "$KIT_DIR/$f" "$CLAUDE_DIR/dwarves-kit/$f"
    echo "[ok] compat symlink ~/.claude/dwarves-kit/$f -> $KIT_DIR/$f"
  done
  # CLI shims too: a plugin/compat machine is a dev machine, so expose every
  # module's CLIs (module gating only applies to the full bash install, which is
  # the only path that resolves an enabled set).
  for _mod in $KIT_KNOWN_MODULES; do
    for _cli in $(kit_module_clis "$_mod"); do
      kit_write_cli_shim "$_cli" "$CLAUDE_DIR/dwarves-kit/bin/$_cli"
    done
  done
  unset _mod _cli
  echo "[ok] CLI shims written to ~/.local/bin"
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

# 1c-bis. Deploy bin/ -- the STABLE consumer entrypoint dir (SPEC-184). Consumers (an
# adopted repo's board shims, the adopt-injected CLAUDE.md block) reference
# $DWARVES_KIT/bin/<name>, never a deep lib path, so an internal lib reorg never breaks
# them. Copied next to lib/ so each wrapper's `../lib/...` resolution holds in the install.
if [ -n "$DEST_REAL" ] && [ "$KIT_REAL" = "$DEST_REAL" ]; then
  echo "[ok] Kit is installed in place; bin already at \$HOME/.claude/dwarves-kit/bin/"
else
  BIN_DEST="$CLAUDE_DIR/dwarves-kit/bin"
  mkdir -p "$CLAUDE_DIR/dwarves-kit"
  [ -L "$BIN_DEST" ] && rm "$BIN_DEST"
  [ -d "$BIN_DEST" ] && [ ! -L "$BIN_DEST" ] && rm -rf "$BIN_DEST"
  cp -R "$KIT_DIR/bin" "$BIN_DEST"
  echo "[ok] Copied bin into $BIN_DEST (stable entrypoint, SPEC-184)"
fi

# 1d. Deploy the operate-contract files so they resolve from the stable install path. adopt.sh
# needs a source AGENTS.md at $KIT_ROOT; gate-ledger reads the lane x phase matrix from
# $KIT_ROOT/docs/WORKFLOW.md (the bulk moved out of the root stub, SPEC-185). Without these,
# adopt + the lane gate are broken from the install (SPEC-049). Copied and version-pinned,
# mirroring hooks + lib (SPEC-066). docs/WORKFLOW.md is the CRITICAL one here: root WORKFLOW.md
# is now just a thin pointer stub, so skipping the docs/ copy would leave every installed
# consumer's gate machinery reading an empty/pointer-only file (404 in effect).
if [ -n "$DEST_REAL" ] && [ "$KIT_REAL" = "$DEST_REAL" ]; then
  echo "[ok] Kit is installed in place; AGENTS.md + WORKFLOW.md + docs/WORKFLOW.md already at \$HOME/.claude/dwarves-kit/"
else
  mkdir -p "$CLAUDE_DIR/dwarves-kit/docs"
  # A real file is kit-managed ONLY if a prior run recorded it in the stamp's managed=
  # list; presence of the stamp alone is not enough (review HIGH: the stamp is written by
  # the same run that first sees the user's file, so stamp-presence destroys it on run 2).
  PRIOR_MANAGED=""
  [ -f "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" ] \
    && PRIOR_MANAGED="$(grep '^managed=' "$CLAUDE_DIR/dwarves-kit/INSTALL-STAMP" 2>/dev/null | cut -d= -f2- || true)"
  MANAGED_CONTRACTS=""
  COPIED_CONTRACTS=""
  for CONTRACT in AGENTS.md WORKFLOW.md docs/WORKFLOW.md; do
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

# 1f. Resolve the enabled module set (spine always; optionals additive across
# re-installs unless --prune). Three inputs feed the union so a re-run NEVER
# retroactively un-wires a hook a prior run (or a hand-edited settings.json) wired:
#   (a) kit.toml's prior [modules] (this consumer's own record)
#   (b) hooks ALREADY present in settings.json that map to a known module (covers
#       a consumer who ran the OLD all-hooks installer, e.g. ops-toolkit/
#       console-labs/family-office, before this manifest existed)
#   (c) this run's --with request
# --prune drops (a)+(b) and trims to exactly --with (spine-only if --with is empty).
KIT_TOML="$CLAUDE_DIR/dwarves-kit/kit.toml"

KIT_PRIOR_MODULES=""
if [ -f "$KIT_TOML" ]; then
  KIT_PRIOR_MODULES="$( (kit_toml_modules_section_true "$KIT_TOML" | grep -v '^team_mode$' | tr '\n' ' ') || true)"
fi

KIT_EXISTING_WIRED_MODULES=""
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
  KIT_EXISTING_CMDS="$(jq -r '(.hooks // {}) | to_entries[]? | .value[]? | .hooks[]? | .command // empty' "$SETTINGS_FILE" 2>/dev/null || true)"
  for _mod in $KIT_KNOWN_MODULES; do
    for _h in $(kit_module_hooks "$_mod"); do
      if printf '%s\n' "$KIT_EXISTING_CMDS" | grep -q "dwarves-kit/hooks/${_h}"; then
        KIT_EXISTING_WIRED_MODULES="$KIT_EXISTING_WIRED_MODULES $_mod"
        break
      fi
    done
  done
  unset _mod _h
fi

if [ "$KIT_PRUNE" -eq 1 ]; then
  KIT_ENABLED_MODULES="$KIT_REQUESTED_MODULES"
  echo "[ok] --prune: trimming enabled modules to exactly: ${KIT_ENABLED_MODULES:-<spine-only>}"
else
  KIT_ENABLED_MODULES="$(printf '%s %s %s\n' "$KIT_PRIOR_MODULES" "$KIT_EXISTING_WIRED_MODULES" "$KIT_REQUESTED_MODULES" \
    | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | xargs)"
fi

KIT_ENABLED_HOOK_NAMES="$KIT_SPINE_HOOKS"
for _mod in $KIT_ENABLED_MODULES; do
  KIT_ENABLED_HOOK_NAMES="$KIT_ENABLED_HOOK_NAMES $(kit_module_hooks "$_mod")"
done
unset _mod

KIT_HOOK_RE=""
for _h in $KIT_ENABLED_HOOK_NAMES; do
  _esc="$(printf '%s' "$_h" | sed 's/\./\\./g')"
  if [ -z "$KIT_HOOK_RE" ]; then KIT_HOOK_RE="$_esc"; else KIT_HOOK_RE="$KIT_HOOK_RE|$_esc"; fi
done
unset _h _esc

# The filtered kit settings.json: spine hooks + only the opted-in modules' hooks.
# An un-installed module's hook is never present here, so it can never reach the
# consumer's settings.json below.
# statusLine ships with the `cosmetic` module (its command is statusline.sh); strip
# it here too, not just in step 7's gate, so a fresh (no-prior-settings.json) install
# doesn't smuggle it in via the blind first-time copy below.
KIT_STATUSLINE_ON=0
case " $KIT_ENABLED_HOOK_NAMES " in *" statusline.sh "*) KIT_STATUSLINE_ON=1 ;; esac

KIT_SETTINGS_FILTERED="$(mktemp)"
jq --arg re "$KIT_HOOK_RE" --argjson sl "$KIT_STATUSLINE_ON" '
  .hooks |= (
    to_entries | map(
      .value |= (
        map(
          .hooks |= map(select(.command | test($re)))
        ) | map(select(.hooks | length > 0))
      )
    ) | from_entries
  )
  | if ($sl == 1) then . else del(.statusLine) end
' "$KIT_DIR/settings.json" > "$KIT_SETTINGS_FILTERED"

# 2. Merge settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  # No existing settings, just copy the filtered (spine + opted-in) set
  cp "$KIT_SETTINGS_FILTERED" "$SETTINGS_FILE"
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
    MERGED=$(echo "$EXISTING_CLEAN" | jq --slurpfile kit "$KIT_SETTINGS_FILTERED" '
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
rm -f "$KIT_SETTINGS_FILTERED"

# 2b. Render the install kit.toml (SPEC-183): the repo-root default (full,
# status-tagged schema) rendered into the live install, recomputing ONLY the
# [modules] section from this run's enabled set -- still a shell-install RECORD
# driving the wiring above, never a runtime registry (no hook reads this file;
# see the standing lint in tests/test-install-modules.sh). Every other section
# ([ledger]/[mega]/[gate]/[features]/[team]) rides through verbatim, so the kit-root
# default -> install render -> resolver read chain stays coherent (the resolver,
# lib/config/kit-config.sh, reads this same file in a prod install).
mkdir -p "$(dirname "$KIT_TOML")"
if [ -f "$KIT_DIR/kit.toml" ]; then
  kit_render_install_toml "$KIT_DIR/kit.toml" "$KIT_TOML"
else
  # Defensive fallback (should not happen in a real checkout: kit.toml ships at
  # repo root). Falls back to the pre-SPEC-183 minimal [modules]-only manifest so
  # install still succeeds.
  echo "[warn] repo-root kit.toml not found at $KIT_DIR/kit.toml; writing a minimal [modules]-only manifest"
  {
    echo "# dwarves-kit module manifest. Generated by install.sh -- do not hand-edit;"
    echo "# use \`install.sh --with <modules>\` (or \`--prune --with <modules>\` to trim) to change it."
    echo "# This is a shell-install RECORD, not a runtime feature-registry: no hook reads it."
    echo ""
    echo "[modules]"
    echo "team_mode = false"
    for _mod in $KIT_KNOWN_MODULES; do
      case " $KIT_ENABLED_MODULES " in
        *" $_mod "*) echo "$_mod = true" ;;
        *) echo "$_mod = false" ;;
      esac
    done
    unset _mod
  } > "$KIT_TOML"
fi
echo "[ok] Wrote kit.toml: $KIT_TOML"
echo "[ok] Enabled modules: ${KIT_ENABLED_MODULES:-<spine-only>}"

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

# 5b. Expose the enabled modules' CLIs on PATH (~/.local/bin), each an exec-shim to
# the stable bin/ entrypoint (SPEC-184). This is the kit-owned replacement for the
# consumer-side snapshot symlinking (ops-toolkit cc-elevation redeploy.sh) that used
# to wire cc-intel and friends.
KIT_CLI_NAMES=""
for _mod in $KIT_ENABLED_MODULES; do
  KIT_CLI_NAMES="$KIT_CLI_NAMES $(kit_module_clis "$_mod")"
done
KIT_CLI_NAMES="$(echo "$KIT_CLI_NAMES" | xargs)"
if [ -n "$KIT_CLI_NAMES" ]; then
  for _cli in $KIT_CLI_NAMES; do
    kit_write_cli_shim "$_cli" "$CLAUDE_DIR/dwarves-kit/bin/$_cli"
  done
  unset _cli
  echo "[ok] CLI shims on ~/.local/bin: $KIT_CLI_NAMES"
fi

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

# 7. Merge statusLine config (part of the `cosmetic` module; gated the same as its hook)
case " $KIT_ENABLED_HOOK_NAMES " in
  *" statusline.sh "*)
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
    ;;
  *)
    echo "[skip] statusLine not registered (cosmetic module not enabled; --with cosmetic to opt in)"
    ;;
esac

# 6. Verify
echo ""
echo "=== Verification ==="
echo "Modules: spine (always on) + ${KIT_ENABLED_MODULES:-<none opted in>}"
KIT_NOT_ENABLED=""
for _mod in $KIT_KNOWN_MODULES; do
  case " $KIT_ENABLED_MODULES " in
    *" $_mod "*) : ;;
    *) KIT_NOT_ENABLED="$KIT_NOT_ENABLED $_mod" ;;
  esac
done
unset _mod
echo "  Not enabled:${KIT_NOT_ENABLED} team_mode(reserved)"
echo "  --with <modules> to opt in, --prune --with <modules> to trim, kit.toml: $KIT_TOML"
echo "Hooks wired into settings.json:"
printf '%s\n' $KIT_ENABLED_HOOK_NAMES | sort -u | while read -r h; do [ -n "$h" ] && echo "  [hook] $h"; done
echo "Hooks directory (all shipped, not all wired): $KIT_DIR/hooks/"
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
echo "Tip: opt into a module (board, session, advisor, cosmetic, queue, stats, quiz_gate,"
echo "weekend_batch, bridge): bash $KIT_DIR/install.sh --with board,stats"
echo "Tip: trim to exactly a set (drops anything previously wired, incl. an old all-hooks"
echo "install): bash $KIT_DIR/install.sh --prune --with board"
echo ""
echo "To uninstall: bash $KIT_DIR/install.sh --uninstall"
