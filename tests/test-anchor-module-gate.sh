#!/usr/bin/env bash
# test-anchor-module-gate.sh -- hooks/anchor-root.sh skips a hook whose module is off.
# A plugin install registers every hook, so the module choice is enforced in the wrapper:
# lib/config/modules.tsv names each hook's module, [modules] in project .kit.toml, then the
# operator kit.toml, then the kit-root kit.toml says whether it is on, and the table's default
# column is the last word. The spine, an unlisted hook and a missing table always run.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/kit/hooks" "$T/kit/lib/config" "$T/proj" "$T/op" "$T/root"
cp "$KIT/hooks/anchor-root.sh" "$T/kit/hooks/"
cp "$KIT/lib/config/modules.tsv" "$KIT/lib/config/hook-module.sh" "$T/kit/lib/config/"
# stub hooks print a marker and exit 7, so "ran" is distinguishable from "skipped" (exit 0)
for h in slop-cleaner board-row-gate ship-gate safety-gate unlisted-hook money-gate; do
  printf '#!/bin/bash\necho RAN-%s\nexit 7\n' "$h" > "$T/kit/hooks/$h.sh"
done

run() { # $1=hook -> "<rc>:<stdout>"; layers come from the env the caller set
  local out rc
  out="$(cd "$T/proj" && KIT_PROJECT_ROOT="$T/proj" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" \
    bash "$T/kit/hooks/anchor-root.sh" "$T/kit/hooks/$1.sh" </dev/null)"; rc=$?
  echo "$rc:$out"
}
reset() { rm -f "$T/proj/.kit.toml" "$T/op/kit.toml" "$T/root/kit.toml"; }
want() { # $1=label $2=hook $3=ran|skipped
  local got; got="$(run "$2")"
  case "$3:$got" in
    ran:7:RAN-*) ok "$1" ;;
    skipped:0:) ok "$1" ;;
    *) no "$1 (want $3; got [$got])" ;;
  esac
}

reset
want "opt-in module, no config: skipped (cosmetic default is off)" slop-cleaner skipped
want "core module, no config: runs (board default is on)" board-row-gate ran
want "spine hook runs (ship-gate)" ship-gate ran
want "spine hook runs (safety-gate)" safety-gate ran
want "a hook the table does not list runs" unlisted-hook ran

printf '[modules]\ncosmetic = true   # on\n' > "$T/root/kit.toml"
want "kit-root kit.toml turns an opt-in module on" slop-cleaner ran
printf '[modules]\nboard = false\n' > "$T/root/kit.toml"
want "kit-root kit.toml turns a core module off" board-row-gate skipped

reset
printf '[modules]\ncosmetic = true\n' > "$T/root/kit.toml"
printf '[modules]\ncosmetic = false\n' > "$T/op/kit.toml"
want "operator overrides kit-root" slop-cleaner skipped
printf '[modules]\ncosmetic = true\n' > "$T/proj/.kit.toml"
want "project overrides operator" slop-cleaner ran

reset
printf '[ledger]\ncosmetic = true\n[modules]\nboard = "false"\n' > "$T/proj/.kit.toml"
want "a key outside [modules] is ignored" slop-cleaner skipped
want "a quoted false in [modules] counts" board-row-gate skipped

reset
printf '[modules]\nmoney_gate = true\n' > "$T/proj/.kit.toml"
want "an underscore module key matches (money_gate)" money-gate ran
printf '[modules]\nsafety = false\nspine = false\n' > "$T/proj/.kit.toml"
want "spine cannot be turned off" safety-gate ran

reset
rm -f "$T/kit/lib/config/modules.tsv"
want "missing table: the hook runs" slop-cleaner ran

# every spine hook runs even with every module off, and never pays for the lookup
printf '[modules]\nboard = false\nsession = false\n' > "$T/proj/.kit.toml"
for h in $(awk -F'\t' '$1 == "spine" { n = split($3, t, " "); for (i = 1; i <= n; i++) { sub(/^[A-Za-z]*:/, "", t[i]); print t[i] } }' "$KIT/lib/config/modules.tsv"); do
  if KIT_PROJECT_ROOT="$T/proj" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" bash "$KIT/lib/config/hook-module.sh" off "$h"; then
    no "spine hook $h is never off"
  else ok "spine hook $h is never off"; fi
done

# parity: hook-module.sh resolves a module exactly as kit_config_get does, layer by layer
. "$KIT/lib/config/kit-config.sh"
parity() { # $1=label $2=module $3=hook $4=project $5=operator $6=root (toml bodies, empty = no file)
  reset
  [ -z "$4" ] || printf '%s\n' "$4" > "$T/proj/.kit.toml"
  [ -z "$5" ] || printf '%s\n' "$5" > "$T/op/kit.toml"
  [ -z "$6" ] || printf '%s\n' "$6" > "$T/root/kit.toml"
  local want got def
  def="$(awk -F'\t' -v m="$2" '$1 == m { print ($2 == "core" ? "true" : "false") }' "$KIT/lib/config/modules.tsv")"
  want="$(KIT_PROJECT_ROOT="$T/proj" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" kit_config_get "modules.$2" "$def")"
  if KIT_PROJECT_ROOT="$T/proj" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" bash "$KIT/lib/config/hook-module.sh" off "$3"; then got=false; else got=true; fi
  [ "$got" = "$want" ] && ok "parity with kit_config_get: $1" || no "parity with kit_config_get: $1 (reader says $want, hook-module says $got)"
}
parity "no files, opt-in" cosmetic slop-cleaner.sh "" "" ""
parity "no files, core" board board-row-gate.sh "" "" ""
parity "root only" cosmetic slop-cleaner.sh "" "" $'[modules]\ncosmetic = true'
parity "operator beats root" cosmetic slop-cleaner.sh "" $'[modules]\ncosmetic = false' $'[modules]\ncosmetic = true'
parity "project beats operator" board board-row-gate.sh $'[modules]\nboard = false' $'[modules]\nboard = true' ""
parity "inline comment and section comment" session context-readiness.sh "" "" $'[modules]   # x\nsession = true   # on'

# layer-edge cases: prefix keys, CRLF, an empty file, a path with a space, a quoted value
parity "prefix key: money does not match money_gate" money_gate money-gate.sh $'[modules]\nmoney = true' "" ""
parity "prefix key: money_gate exact" money_gate money-gate.sh $'[modules]\nmoney_gate = true' "" ""
parity "wrong section is ignored" cosmetic slop-cleaner.sh $'[other]\ncosmetic = true' "" ""
parity "quoted false" board board-row-gate.sh $'[modules]\nboard = "false"' "" ""
reset; printf '[modules]\r\ncosmetic = true\r\n' > "$T/proj/.kit.toml"
want "CRLF config file" slop-cleaner ran
reset; : > "$T/proj/.kit.toml"; printf '[modules]\ncosmetic = true\n' > "$T/op/kit.toml"
want "an empty project file does not shift the layers" slop-cleaner ran
mkdir -p "$T/with space"; reset; printf '[modules]\ncosmetic = true\n' > "$T/with space/.kit.toml"
got="$(cd "$T/proj" && KIT_PROJECT_ROOT="$T/with space" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" bash "$T/kit/hooks/anchor-root.sh" "$T/kit/hooks/slop-cleaner.sh" </dev/null)"
[ "$got" = RAN-slop-cleaner ] && ok "a project path with a space resolves" || no "a project path with a space resolves (got [$got])"
reset
# the hook still gets its stdin when it runs
cat > "$T/kit/hooks/echo-stdin.sh" <<'STUB'
#!/bin/bash
cat
STUB
got="$(printf 'payload-123' | (cd "$T/proj" && KIT_PROJECT_ROOT="$T/proj" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" bash "$T/kit/hooks/anchor-root.sh" "$T/kit/hooks/echo-stdin.sh"))"
[ "$got" = payload-123 ] && ok "an unlisted hook receives its stdin" || no "an unlisted hook receives its stdin (got [$got])"
# no hook basename is claimed by two modules (first match would win silently)
DUP="$(awk -F'\t' '!/^#/ && NF >= 4 { n = split($3, t, " "); delete seen; for (i = 1; i <= n; i++) { sub(/^[A-Za-z]*:/, "", t[i]); if (t[i] != "-" && !(t[i] in seen)) { seen[t[i]] = 1; c[t[i]]++ } } } END { for (k in c) if (c[k] > 1) print k }' "$KIT/lib/config/modules.tsv")"
[ -z "$DUP" ] && ok "no hook belongs to two modules" || no "hooks claimed by two modules: $DUP"
# the wrapper's spine fast path names exactly the table's spine hooks
FAST="$(sed -n 's/^  \(safety-gate.sh|[^)]*\)) ;;$/\1/p' "$KIT/hooks/anchor-root.sh" | tr '|' '\n' | sort)"
SPINE="$(awk -F'\t' '$1 == "spine" { n = split($3, t, " "); for (i = 1; i <= n; i++) { sub(/^[A-Za-z]*:/, "", t[i]); print t[i] } }' "$KIT/lib/config/modules.tsv" | sort -u)"
[ -n "$FAST" ] && [ "$FAST" = "$SPINE" ] && ok "the spine fast path matches the table's spine row" || no "spine fast path drifted from the table (fast: $(echo $FAST) / table: $(echo $SPINE))"
# spine = false in config changes nothing
printf '[modules]\nspine = false\n' > "$T/proj/.kit.toml"
if KIT_PROJECT_ROOT="$T/proj" KIT_CONFIG_OPERATOR="$T/op" KIT_CONFIG_ROOT="$T/root" bash "$KIT/lib/config/hook-module.sh" off safety-gate.sh; then no "spine = false is ignored"; else ok "spine = false is ignored"; fi
reset

# negative control: with the gate block removed the opt-in hook runs when it should be skipped
cp "$KIT/lib/config/modules.tsv" "$KIT/lib/config/hook-module.sh" "$T/kit/lib/config/"
awk '/^# Module gate/ { skip = 1 } /^# A \.sh hook runs under/ { skip = 0 } !skip' "$KIT/hooks/anchor-root.sh" > "$T/kit/hooks/anchor-root.sh"
got="$(run slop-cleaner)"
case "$got" in 7:RAN-*) ok "negative control: without the gate an off module's hook runs" ;; *) no "negative control (got [$got])" ;; esac

# every hooks.json target is either in the table or a known unlisted hook
LISTED="$(awk -F'\t' '!/^#/ && NF >= 4 { n = split($3, t, " "); for (i = 1; i <= n; i++) { sub(/^[A-Za-z]*:/, "", t[i]); print t[i] } }' "$KIT/lib/config/modules.tsv" | sort -u)"
MISSING=""
for h in $(grep -o 'hooks/[a-z-]*\.sh' "$KIT/hooks/hooks.json" | sed 's|hooks/||' | sort -u); do
  [ "$h" = anchor-root.sh ] && continue
  printf '%s\n' "$LISTED" | grep -qx "$h" || MISSING="$MISSING $h"
done
[ -z "$MISSING" ] && ok "every hooks.json hook is in the module table" || no "hooks.json hooks missing from the module table:$MISSING"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
