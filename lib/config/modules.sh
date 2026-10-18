#!/usr/bin/env bash
# modules.sh -- source this; it defines the readers over lib/config/modules.tsv and runs nothing.
#
#   kit_modules_known            every toggleable module, space separated (spine excluded)
#   kit_modules_core             the toggleable modules whose default is core
#   kit_module_default <m>       core | opt-in (empty for an unknown module)
#   kit_module_hooks <m>         the module's hook script basenames, in table order, deduplicated
#   kit_module_hook_events <m>   the module's <Event>:<script> pairs, as the table lists them
#   kit_module_clis <m>          the bin/ entrypoints the module exposes on PATH
#
# `spine` answers the hook readers too (its hooks are always wired) but is never in
# kit_modules_known, so it cannot be named in --with or written to [modules].
# KIT_MODULES_FILE overrides the table path (a test seam); the default sits next to this file.
# bash 3.2 safe: awk and case only.

KIT_MODULES_FILE="${KIT_MODULES_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/modules.tsv}"

_kit_modules_field() {  # _kit_modules_field <module> <column-number>
  awk -F'\t' -v m="$1" -v c="$2" '/^#/ || NF < 4 { next } $1 == m { print $c; exit }' "$KIT_MODULES_FILE"
}

kit_modules_known() {
  awk -F'\t' '/^#/ || NF < 4 || $1 == "spine" { next } { print $1 }' "$KIT_MODULES_FILE" | tr '\n' ' ' | sed 's/ $//'
}

kit_modules_core() {
  awk -F'\t' '/^#/ || NF < 4 || $1 == "spine" { next } $2 == "core" { print $1 }' "$KIT_MODULES_FILE" | tr '\n' ' ' | sed 's/ $//'
}

kit_module_default() { _kit_modules_field "$1" 2; }

kit_module_hook_events() {
  local v
  v="$(_kit_modules_field "$1" 3)"
  [ "$v" = "-" ] && v=""
  printf '%s\n' "$v"
}

kit_module_hooks() {
  kit_module_hook_events "$1" | tr ' ' '\n' | sed -n 's/^[A-Za-z]*://p' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ $//'
  echo
}

kit_module_clis() {
  local v
  v="$(_kit_modules_field "$1" 4)"
  [ "$v" = "-" ] && v=""
  printf '%s\n' "$v"
}
