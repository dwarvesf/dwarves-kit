#!/usr/bin/env bash
# kit-config.sh -- the single resolver for kit.toml config (config-layer).
#
# WHY: every runtime knob in the kit is an ad-hoc env var resolved in a different
# place. This is the ONE resolver (mirrors lib/telemetry/kit-log-dir.sh, "one place
# the default lives") that reads the layered config: the kit-root default kit.toml
# overridden by a per-project .kit.toml (project WINS). Commands and feature libs
# call kit_config_get AT INVOCATION. Hot spine hooks NEVER source this -- that keeps
# the no-runtime-manifest-read lint green (it forbids HOOK reads, not command reads).
#
# Contract (safe under set -euo pipefail, no output on load):
#   kit_config_get <section.key> [default]   -> resolved value (project > kit-root > default)
#   kit_config_root                           -> the kit-root kit.toml path in use
#   kit_config_project                        -> the project .kit.toml path in use
#
# Precedence sources (each overridable for tests):
#   project : $KIT_PROJECT_ROOT/.kit.toml   (default: $PWD/.kit.toml)
#   kit-root: $KIT_CONFIG_ROOT/kit.toml     (default: ${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/kit.toml)
#
# Idempotent-source guard.
[ -n "${_KIT_CONFIG_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_CONFIG_SOURCED=1

kit_config_root()    { printf '%s' "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml"; }
kit_config_project() { printf '%s' "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml"; }

# _kit_toml_get <file> <section> <key> -- print the raw value of [section].key, empty if absent.
# Line-oriented, no TOML lib (matches install.sh's grep/sed style). Handles: [section]
# headers, `#` full-line and inline comments, surrounding whitespace, and one layer of
# double-quotes. Values themselves must not contain a literal `#` (our schema never does).
_kit_toml_get() {
  local file="$1" section="$2" key="$3"
  [ -f "$file" ] || return 0
  awk -v sec="$section" -v k="$key" '
    { line = $0 }
    line ~ /^[[:space:]]*#/ { next }                      # full-line comment
    line ~ /^[[:space:]]*\[/ {                            # section header
      h = line; sub(/#.*/, "", h); gsub(/[][[:space:]]/, "", h)
      insec = (h == sec); next
    }
    insec {
      sub(/#.*/, "", line)                                # strip inline comment
      if (line ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
        sub(/^[^=]*=[[:space:]]*/, "", line)              # drop `key =`
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)     # trim
        gsub(/^"|"$/, "", line)                           # unquote
        print line; exit
      }
    }
  ' "$file"
}

# kit_config_get <section.key> [default] -- project override, else kit-root, else default.
kit_config_get() {
  local dotkey="$1" def="${2:-}" section key v
  section="${dotkey%%.*}"; key="${dotkey#*.}"
  v="$(_kit_toml_get "$(kit_config_project)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  v="$(_kit_toml_get "$(kit_config_root)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  printf '%s' "$def"
}

# --- self-test: `bash lib/config/kit-config.sh selftest` (ponytail: one runnable check) ---
if [ "${1:-}" = "selftest" ]; then
  set -euo pipefail
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/root" "$d/proj"
  cat > "$d/root/kit.toml" <<'TOML'
[ledger]
location = "shared"   # inline comment must be stripped
[mega]
wave_cap = 2
# over_test = false   # full-comment line must be ignored
TOML
  cat > "$d/proj/.kit.toml" <<'TOML'
[ledger]
location = "isolated"
TOML
  export KIT_CONFIG_ROOT="$d/root" KIT_PROJECT_ROOT="$d/proj"
  fail=0
  chk() { [ "$2" = "$3" ] && echo "ok   $1" || { echo "FAIL $1: got [$2] want [$3]"; fail=1; }; }
  chk "project overrides kit-root"      "$(kit_config_get ledger.location)"    "isolated"
  chk "kit-root default when no proj"   "$(kit_config_get mega.wave_cap)"      "2"
  chk "inline comment stripped"         "$(KIT_PROJECT_ROOT=/nonexistent kit_config_get ledger.location)" "shared"
  chk "commented key -> caller default" "$(kit_config_get mega.over_test off)" "off"
  chk "missing key -> caller default"   "$(kit_config_get nope.nope fallback)" "fallback"
  chk "missing section -> empty"        "$(kit_config_get ghost.key)"          ""
  [ "$fail" = 0 ] && echo "PASS kit-config selftest" || { echo "SELFTEST FAILED"; exit 1; }
fi
