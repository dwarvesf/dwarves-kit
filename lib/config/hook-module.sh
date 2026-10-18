#!/bin/bash
# hook-module.sh -- is the module that owns this hook switched off?
#
#   hook-module.sh off <hook-script-basename>   exit 0 when the hook's module resolves to false,
#                                               exit 1 otherwise (on, spine, or unknown hook)
#
# hooks/anchor-root.sh calls it before every non-spine hook, so a plugin install (whose
# hooks/hooks.json registers every hook) still honors the module choice. The hook's module comes
# from lib/config/modules.tsv. The setting is [modules].<module> with the same precedence as
# kit_config_get: project .kit.toml, then the operator kit.toml, then the kit-root kit.toml, then
# the table's default column (core on, opt-in off). The paths honor the same overrides
# (KIT_PROJECT_ROOT, KIT_CONFIG_OPERATOR, KIT_CONFIG_ROOT, DWARVES_KIT).
#
# One awk pass over the table and the config files, no python, no sourcing: it runs on every tool
# call. Every uncertainty answers "not off" so the hook runs: a missing table, a hook the table
# does not list, the spine, a value that is not literally true or false.
# tests/test-anchor-module-gate.sh pins the precedence against kit_config_get.
[ "${1:-}" = off ] && [ -n "${2:-}" ] || exit 1
_tsv="${KIT_MODULES_FILE:-$(dirname "$0")/modules.tsv}"
[ -f "$_tsv" ] || exit 1
_files=("$_tsv"); _layers="t"
for _l in "p:${KIT_PROJECT_ROOT:-$PWD}/.kit.toml" \
          "o:${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml" \
          "r:${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml"; do
  [ -f "${_l#*:}" ] && { _files+=("${_l#*:}"); _layers="$_layers ${_l%%:*}"; }
done
[ "$(awk -F'\t' -v hook="$2" -v layers="$_layers" '
  BEGIN { split(layers, L, " ") }
  FNR == 1 { n++ }
  L[n] == "t" {
    if ($0 ~ /^#/ || NF < 4 || mod != "") next
    c = split($3, t, " ")
    for (i = 1; i <= c; i++) { k = t[i]; sub(/^[A-Za-z]*:/, "", k); if (k == hook) { mod = $1; def = $2 } }
    next
  }
  mod == "" { next }
  { line = $0; sub(/#.*/, "", line); gsub(/[ \t\r]/, "", line) }
  line ~ /^\[/ { insec = (line == "[modules]"); next }
  insec && index(line, mod "=") == 1 && !(L[n] in val) {
    v = substr(line, length(mod) + 2); gsub(/"/, "", v)
    if (v == "true" || v == "false") val[L[n]] = v
  }
  END {
    if (mod == "" || mod == "spine") exit
    r = ("p" in val) ? val["p"] : ("o" in val) ? val["o"] : ("r" in val) ? val["r"] : (def == "core" ? "true" : "false")
    if (r == "false") print "off"
  }' "${_files[@]}" 2>/dev/null)" = off ]
