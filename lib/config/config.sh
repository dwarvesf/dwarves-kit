#!/usr/bin/env bash
# config.sh -- the bin/config engine (SPEC-198, ADR-0034 decision 4).
#
# WHY: every runtime knob has an env var, a kit.toml key, or both, resolved by a DIFFERENT
# ad-hoc precedence in a different file. There was no ONE place to see "what is this knob's
# value right now, and WHY" (env override vs project .kit.toml vs kit-root kit.toml vs
# hardcoded default) without opening files. This is that read/explain surface.
#
# FENCE (ADR-0034 decision 4): `lib/config/kit-config.sh` stays the ONLY reader of TOML. This
# file does NOT parse kit.toml itself -- it calls INTO kit-config.sh's existing accessors
# (kit_config_get / kit_config_root / kit_config_project / _kit_toml_get) for every value, and
# reads the CHECKED-IN lib/config/module-registry.md (a markdown table, not TOML) to enumerate
# which keys exist. `config set` is OUT (help text says .kit.toml hand-edit for now).
#
# Verbs:
#   config list             -- every declared knob: key, status tag, effective value,
#                               provenance, owning module
#   config get <key>        -- the resolved effective value only (for scripting)
#   config explain <key>    -- the full 4-level provenance chain + which level won
# <key> is either the env var name (WAVE_CAP) or the dotted kit.toml key (mega.wave_cap).
set -euo pipefail
CONFIG_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE="${CONFIG_REGISTRY_FILE:-$CONFIG_SELF/module-registry.md}"
# shellcheck source=lib/config/kit-config.sh
source "$CONFIG_SELF/kit-config.sh" || { echo "config: lib/config/kit-config.sh missing or unreadable" >&2; exit 1; }

_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# _registry_rows -- print every data row (raw, still pipe-delimited) from every subsection
# under "## Env <-> key registry", skipping section headers, table headers, and separators.
_registry_rows() {
  [ -f "$REGISTRY_FILE" ] || { echo "config: registry file missing: $REGISTRY_FILE" >&2; return 1; }
  awk '
    /^## Env <-> key registry/ {inreg=1; next}
    /^## Allowlist/ {inreg=0}
    inreg && /^\|/ {
      if ($0 ~ /^\| Env var \|/) next
      if ($0 ~ /^\|---/) next
      print
    }
  ' "$REGISTRY_FILE"
}

# _row_get <row> <1..6> -- trimmed column (1=env var, 2=kit.toml key, 3=default, 4=status,
# 5=module, 6=doc). Pipe-split is safe: the registry deliberately keeps no literal `|` inside
# a cell (verified at authoring time; see the sub-goal's proof-of-done pipe-count check).
_row_get() {
  local row="$1" idx="$2" f
  IFS='|' read -ra f <<< "$row"
  _trim "${f[$idx]:-}"
}

# _find_row <key> -- first registry row whose env-var column OR kit.toml-key column exactly
# matches <key>. Registry order is the tie-break when a kit.toml key has more than one env var
# (ledger.location: KIT_LEDGER_DIR is listed before DWARVES_KIT_LOG_DIR before the toml-only
# default row, so a lookup by the bare key resolves to the canonical env var's row).
_find_row() {
  local key="$1" row env tk
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    env="$(_row_get "$row" 1)"; tk="$(_row_get "$row" 2)"
    if [ "$env" = "$key" ] || [ "$tk" = "$key" ]; then printf '%s' "$row"; return 0; fi
  done < <(_registry_rows)
  return 1
}

# _resolve <row> -- sets EFFECTIVE / PROVENANCE / ENV_VAL / ENV_SET / PROJ_VAL / PROJ_SET /
# ROOT_VAL / ROOT_SET (globals; mirrors the small-bash-script house style of
# lib/classify/lane-classify.sh's LANE/REASON/FIRED globals, not a subshell-return dance).
_resolve() {
  local row="$1" envvar tomlkey defaultval section key
  envvar="$(_row_get "$row" 1)"; tomlkey="$(_row_get "$row" 2)"; defaultval="$(_row_get "$row" 3)"

  ENV_VAL=""; ENV_SET=0
  if [ "$envvar" != "-" ] && declare -p "$envvar" >/dev/null 2>&1; then
    ENV_SET=1; ENV_VAL="${!envvar}"
  fi

  PROJ_VAL=""; PROJ_SET=0; ROOT_VAL=""; ROOT_SET=0
  if [ "$tomlkey" != "env-only" ] && [ "$tomlkey" != "-" ]; then
    section="${tomlkey%%.*}"; key="${tomlkey#*.}"
    PROJ_VAL="$(_kit_toml_get "$(kit_config_project)" "$section" "$key")"
    [ -n "$PROJ_VAL" ] && PROJ_SET=1
    ROOT_VAL="$(_kit_toml_get "$(kit_config_root)" "$section" "$key")"
    [ -n "$ROOT_VAL" ] && ROOT_SET=1
  fi

  if [ "$ENV_SET" = 1 ]; then EFFECTIVE="$ENV_VAL"; PROVENANCE="env"
  elif [ "$PROJ_SET" = 1 ]; then EFFECTIVE="$PROJ_VAL"; PROVENANCE="project .kit.toml"
  elif [ "$ROOT_SET" = 1 ]; then EFFECTIVE="$ROOT_VAL"; PROVENANCE="kit-root kit.toml"
  else EFFECTIVE="$defaultval"; PROVENANCE="default"
  fi
}

# _display_key <row> -- the env var name if one exists, else the kit.toml key.
_display_key() {
  local row="$1" envvar tomlkey
  envvar="$(_row_get "$row" 1)"; tomlkey="$(_row_get "$row" 2)"
  [ "$envvar" != "-" ] && { printf '%s' "$envvar"; return 0; }
  printf '%s' "$tomlkey"
}

cmd_list() {
  printf '%-30s %-10s %-30s %-20s %s\n' "KEY" "STATUS" "VALUE" "PROVENANCE" "MODULE"
  local row status module display val
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    _resolve "$row"
    status="$(_row_get "$row" 4)"; module="$(_row_get "$row" 5)"
    display="$(_display_key "$row")"
    val="$EFFECTIVE"
    # Non-[impl] keys are inert by contract (design/reserved/consumer): never render them as
    # a live toggle, so a reader cannot mistake a designed-not-built key for a working one.
    if [ "$status" != "[impl]" ]; then
      local tag="${status#\[}"; tag="${tag%\]}"
      val="(inert: $tag, no live effect)"
    fi
    printf '%-30s %-10s %-30s %-20s %s\n' "$display" "$status" "$val" "$PROVENANCE" "$module"
  done < <(_registry_rows)
}

cmd_get() {
  local key="${1:?usage: config get <key>}" row
  row="$(_find_row "$key")" || { echo "config: unknown key '$key' (not in $REGISTRY_FILE)" >&2; return 1; }
  _resolve "$row"
  printf '%s\n' "$EFFECTIVE"
}

cmd_explain() {
  local key="${1:?usage: config explain <key>}" row envvar tomlkey defaultval status module doc
  row="$(_find_row "$key")" || { echo "config: unknown key '$key' (not in $REGISTRY_FILE)" >&2; return 1; }
  envvar="$(_row_get "$row" 1)"; tomlkey="$(_row_get "$row" 2)"; defaultval="$(_row_get "$row" 3)"
  status="$(_row_get "$row" 4)"; module="$(_row_get "$row" 5)"; doc="$(_row_get "$row" 6)"
  _resolve "$row"

  printf '%s (module=%s, status=%s)\n' "$(_display_key "$row")" "$module" "$status"
  printf '  %s\n\n' "$doc"

  if [ "$envvar" != "-" ]; then
    if [ "$ENV_SET" = 1 ]; then printf '  1. env             %-20s = %s\n' "$envvar" "$ENV_VAL"
    else printf '  1. env             %-20s = (unset)\n' "$envvar"; fi
  else
    printf '  1. env             n/a (this key has no env override)\n'
  fi

  if [ "$tomlkey" != "env-only" ] && [ "$tomlkey" != "-" ]; then
    if [ "$PROJ_SET" = 1 ]; then printf '  2. project .kit.toml %-19s = %s   [%s]\n' "[$tomlkey]" "$PROJ_VAL" "$(kit_config_project)"
    else printf '  2. project .kit.toml %-19s = (unset)   [%s]\n' "[$tomlkey]" "$(kit_config_project)"; fi
    if [ "$ROOT_SET" = 1 ]; then printf '  3. kit-root kit.toml %-19s = %s   [%s]\n' "[$tomlkey]" "$ROOT_VAL" "$(kit_config_root)"
    else printf '  3. kit-root kit.toml %-19s = (unset)   [%s]\n' "[$tomlkey]" "$(kit_config_root)"; fi
  else
    printf '  2. project .kit.toml n/a (this key has no kit.toml backing: %s)\n' "$tomlkey"
    printf '  3. kit-root kit.toml n/a (this key has no kit.toml backing: %s)\n' "$tomlkey"
  fi

  printf '  4. default          = %s\n\n' "$defaultval"
  printf 'Effective: %s   (source: %s)\n' "$EFFECTIVE" "$PROVENANCE"
}

usage() {
  cat <<'EOF'
usage: config {list|get|explain} [args...]

  config list             every declared knob: key, status, effective value, provenance, module
  config get <key>        the resolved effective value only (env var name or dotted kit.toml key)
  config explain <key>    the full 4-level provenance chain (env > project > kit-root > default)

`config set` is not built. Hand-edit <project>/.kit.toml to change a project-level value; the
kit-root default lives in kit.toml. See docs/specs/SPEC-198-config-surface.md.
EOF
}

main() {
  local verb="${1:-}"
  case "$verb" in
    list) cmd_list ;;
    get) shift; cmd_get "$@" ;;
    explain) shift; cmd_explain "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "config: unknown verb '$verb'" >&2; usage >&2; return 64 ;;
  esac
}

main "$@"
