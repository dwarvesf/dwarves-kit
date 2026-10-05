#!/usr/bin/env bash
# kit-config-reference.sh -- FROZEN copy of the pre-cache resolver (kit_config_get and friends,
# one awk per layer per key). It is the parity oracle for tests/test-config-cache.sh: the cached
# lib/config/kit-config.sh must return exactly what this returns. Do not edit it to follow the
# cache; change it only if the intended value semantics of kit.toml reads change.
kit_config_root()     { printf '%s' "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml"; }
kit_config_operator() { printf '%s' "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml"; }
kit_config_project()  { printf '%s' "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml"; }

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

# kit_config_get <section.key> [default] -- project override, else operator, else kit-root,
# else default. The dotted key splits at the LAST dot: `lane.normal.phases` reads section
# `lane.normal`, key `phases`. A missing file at any layer is skipped silently.
kit_config_get() {
  local dotkey="$1" def="${2:-}" section key v
  section="${dotkey%.*}"; key="${dotkey##*.}"
  v="$(_kit_toml_get "$(kit_config_project)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  v="$(_kit_toml_get "$(kit_config_operator)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  v="$(_kit_toml_get "$(kit_config_root)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  printf '%s' "$def"
}

# kit_config_get_root <section.key> [default] -- operator, else kit-root, else default. The
# project overlay is SKIPPED. For security-bearing keys a committed project .kit.toml must
# NOT be able to set: a project toml rides inside an untrusted PR, so a key that selects a
# runner host, a secret ref, or a dispatch target must resolve from an operator-owned file
# alone. Same read-model the kit already applies to enabled_agent_clis. The operator file
# carries the same trust as the kit root: it sits on the operator's own machine and never
# rides inside a pull request.
kit_config_get_root() {
  local dotkey="$1" def="${2:-}" section key v
  section="${dotkey%.*}"; key="${dotkey##*.}"
  v="$(_kit_toml_get "$(kit_config_operator)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  v="$(_kit_toml_get "$(kit_config_root)" "$section" "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  printf '%s' "$def"
}
