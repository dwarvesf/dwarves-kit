#!/usr/bin/env bash
# config-parity-driver.sh -- replay config lookups through one resolver, for the parity check in
# tests/test-config-cache.sh. Usage: config-parity-driver.sh <resolver.sh> <sub|direct> < cases
#
# A case line is `id|project-dir|operator-dir|root-dir|fn|arg1|arg2`:
#   fn=get   kit_config_get arg1 arg2          fn=root  kit_config_get_root arg1 arg2
#   fn=tg    _kit_toml_get <project-dir> arg1 arg2   (raw getter; project-dir is a FILE path here)
# One output line per case: `id|<%q of the value>`. `sub` reads through `$(...)` like the real
# callers do; `direct` calls in this shell so the in-process cache is exercised across cases.
# The resolver is sourced from the current directory, which the caller points at a fixture.
lib="$1"; mode="${2:-sub}"
. "$lib"
out="$(mktemp)"
while IFS='|' read -r id P O R fn a1 a2; do
  export KIT_PROJECT_ROOT="$P" KIT_CONFIG_OPERATOR="$O" KIT_CONFIG_ROOT="$R"
  case "$fn" in
    get)  if [ "$mode" = sub ]; then v="$(kit_config_get "$a1" "$a2"; echo x)"
          else kit_config_get "$a1" "$a2" >"$out"; v="$(cat "$out"; echo x)"; fi ;;
    root) if [ "$mode" = sub ]; then v="$(kit_config_get_root "$a1" "$a2"; echo x)"
          else kit_config_get_root "$a1" "$a2" >"$out"; v="$(cat "$out"; echo x)"; fi ;;
    tg)   if [ "$mode" = sub ]; then v="$(_kit_toml_get "$P" "$a1" "$a2" 2>/dev/null; echo x)"
          else _kit_toml_get "$P" "$a1" "$a2" >"$out" 2>/dev/null; v="$(cat "$out"; echo x)"; fi ;;
  esac
  v="${v%x}"
  printf '%s|%q\n' "$id" "$v"
done
