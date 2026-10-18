#!/usr/bin/env bash
# test-modules-table.sh -- lib/config/modules.tsv is the ONE module table.
#
# install.sh and lib/adopt.sh both read it through lib/config/modules.sh; neither keeps a private
# copy. This suite pins every other surface to the table so a drift has nowhere to hide:
#   T1  the table is well formed (4 columns, core|opt-in, unique names, no folded `bridge`)
#   T2  kit.toml [modules] defaults and the module-registry rows mirror the default column
#   T3  every hook in settings.json and hooks/hooks.json sits in exactly one module, under the event
#       the table names; every table hook exists on disk
#   T4  install.sh and adopt.sh define no table of their own and source the shared reader
#   T5  NEGATIVE CONTROL: the T3 check, run on a planted table, names each planted fault
#
# Run: bash tests/test-modules-table.sh
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TABLE="$KIT_DIR/lib/config/modules.tsv"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
assert_true() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

# Slice S4 removes session-state-save and wires intake-sweep at SessionStart in settings.json and
# hooks/hooks.json. Until that lands, settings.json still carries the first and lacks the second;
# the table already shows the end state. Delete both lists when S4 merges.
SETTINGS_EXTRA="session-state-save.sh"
TABLE_NOT_YET_WIRED="intake-sweep.sh"

# table_problems <table> <manifest.json>... -- print one line per fault. A manifest is a
# settings.json or a hooks/hooks.json; the table's <Event>:<script> pairs must match it both ways.
table_problems() {
  local table="$1"; shift
  local pairs manifest
  pairs="$(awk -F'\t' '/^#/ || NF < 4 { next } $3 != "-" { n = split($3, p, " "); for (i = 1; i <= n; i++) print $1 "\t" p[i] }' "$table")"
  # a script wired by two modules, or a module row twice
  printf '%s\n' "$pairs" | awk -F'\t' '{ k = $2; sub(/^[A-Za-z]*:/, "", k); if (k in seen && seen[k] != $1) print "script in two modules: " k " (" seen[k] ", " $1 ")"; seen[k] = $1 }'
  awk -F'\t' '/^#/ || NF < 4 { next } seen[$1]++ { print "module listed twice: " $1 }' "$table"
  for manifest in "$@"; do
    local wired
    wired="$(jq -r '.hooks // {} | to_entries[] | .key as $e | .value[] | .hooks[] | .command | gsub("^.*/hooks/"; "") | split(" ")[0] | "\($e):\(.)"' "$manifest" | sort -u)"
    # every wired pair belongs to a module (anchor-root is the wrapper, not a hook)
    while IFS= read -r w; do
      [ -z "$w" ] && continue
      case "$w" in *:anchor-root.sh) continue ;; esac
      script="${w#*:}"
      case " $SETTINGS_EXTRA " in *" $script "*) continue ;; esac
      if ! printf '%s\n' "$pairs" | awk -F'\t' '{ print $2 }' | grep -qxF "$w"; then
        if printf '%s\n' "$pairs" | awk -F'\t' '{ s = $2; sub(/^[A-Za-z]*:/, "", s); print s }' | grep -qxF "$script"; then
          echo "$(basename "$manifest"): $script is wired under $w, the table names a different event"
        else
          echo "$(basename "$manifest"): $w is in no module"
        fi
      fi
    done <<< "$wired"
    # every table pair is wired
    while IFS=$'\t' read -r _m pair; do
      [ -z "$pair" ] && continue
      case "$pair" in statusLine:*) continue ;; esac
      script="${pair#*:}"
      case " $TABLE_NOT_YET_WIRED " in *" $script "*) continue ;; esac
      printf '%s\n' "$wired" | grep -qxF "$pair" || echo "$(basename "$manifest"): table pair $pair is not wired"
    done <<< "$pairs"
  done
  # every table script exists on disk
  while IFS=$'\t' read -r _m pair; do
    [ -z "$pair" ] && continue
    script="${pair#*:}"
    [ -f "$KIT_DIR/hooks/$script" ] || echo "table script $script has no file in hooks/"
  done <<< "$pairs"
}

# ============================================================
echo "== T1 the table is well formed =="
# ============================================================
BAD_ROWS="$(awk -F'\t' '/^#/ { next } NF != 4 { print NR ": " $0 }' "$TABLE")"
assert_true "every data row has exactly 4 tab separated columns (bad: ${BAD_ROWS:-none})" "$([ -z "$BAD_ROWS" ]; echo $?)"
BAD_DEFAULT="$(awk -F'\t' '/^#/ || NF < 4 { next } $2 != "core" && $2 != "opt-in" { print $1 ":" $2 }' "$TABLE")"
assert_true "every default is core or opt-in (bad: ${BAD_DEFAULT:-none})" "$([ -z "$BAD_DEFAULT" ]; echo $?)"
DUP="$(awk -F'\t' '/^#/ || NF < 4 { next } { print $1 }' "$TABLE" | sort | uniq -d)"
assert_true "module names are unique (dup: ${DUP:-none})" "$([ -z "$DUP" ]; echo $?)"
assert_true "spine is a row and is core" "$(awk -F'\t' '$1 == "spine" && $2 == "core" { f = 1 } END { exit !f }' "$TABLE"; echo $?)"
assert_true "the folded bridge module is gone" "$(awk -F'\t' '$1 == "bridge" { f = 1 } END { exit f }' "$TABLE"; echo $?)"
assert_true "session-state-save is not in the table (slice S4 removes the hook)" "$(! grep -q 'session-state-save' "$TABLE"; echo $?)"
assert_true "intake-sweep sits under board at SessionStart" "$(awk -F'\t' '$1 == "board" && $3 ~ /SessionStart:intake-sweep\.sh/ { f = 1 } END { exit !f }' "$TABLE"; echo $?)"
CORE="$(bash -c "source '$KIT_DIR/lib/config/modules.sh'; kit_modules_core")"
assert_true "core set is exactly board (spine is not a toggle) (got: $CORE)" "$([ "$CORE" = "board" ]; echo $?)"
KNOWN="$(bash -c "source '$KIT_DIR/lib/config/modules.sh'; kit_modules_known")"
case " $KNOWN " in *" spine "*) SPINE_TOGGLE=1 ;; *) SPINE_TOGGLE=0 ;; esac
assert_true "spine is not a toggleable module" "$SPINE_TOGGLE"
for m in session advisor cosmetic money_gate prose_rag queue stats worktree sync quiz_gate weekend_batch; do
  assert_true "$m is opt-in" "$([ "$(bash -c "source '$KIT_DIR/lib/config/modules.sh'; kit_module_default $m")" = "opt-in" ]; echo $?)"
done

# ============================================================
echo "== T2 kit.toml [modules] and module-registry mirror the default column =="
# ============================================================
KT_KEYS="$(awk '/^\[modules\]/ { s = 1; next } /^\[/ { s = 0 } s && /^[a-z_]+[[:space:]]*=/ { k = $0; sub(/[[:space:]]*=.*/, "", k); print k }' "$KIT_DIR/kit.toml" | grep -vx team_mode | sort | tr '\n' ' ')"
TB_KEYS="$(printf '%s\n' $KNOWN | sort | tr '\n' ' ')"
assert_true "kit.toml [modules] keys equal the table's toggleable modules (kit.toml: $KT_KEYS)" "$([ "$KT_KEYS" = "$TB_KEYS" ]; echo $?)"
for m in $KNOWN; do
  d="$(bash -c "source '$KIT_DIR/lib/config/modules.sh'; kit_module_default $m")"
  want=false; [ "$d" = "core" ] && want=true
  got="$(awk -v k="$m" '/^\[modules\]/ { s = 1; next } /^\[/ { s = 0 } s && $1 == k { print $3; exit }' "$KIT_DIR/kit.toml")"
  assert_true "kit.toml modules.$m default is $want for a $d module (got: $got)" "$([ "$got" = "$want" ]; echo $?)"
  reg="$(grep -E "^\| - \| modules\.$m \|" "$KIT_DIR/lib/config/module-registry.md" | awk -F'|' '{ gsub(/[ `]/, "", $4); print $4 }')"
  assert_true "module-registry modules.$m default is $want (got: $reg)" "$([ "$reg" = "$want" ]; echo $?)"
done

# ============================================================
echo "== T3 settings.json and hooks/hooks.json agree with the table =="
# ============================================================
P_SET="$(table_problems "$TABLE" "$KIT_DIR/settings.json")"
assert_true "settings.json: every hook is in one module under its event, every table hook is wired (${P_SET:-no problems})" "$([ -z "$P_SET" ]; echo $?)"
P_PLG="$(table_problems "$TABLE" "$KIT_DIR/hooks/hooks.json")"
assert_true "hooks/hooks.json (the plugin manifest) agrees too (${P_PLG:-no problems})" "$([ -z "$P_PLG" ]; echo $?)"
SL_CMD="$(jq -r '.statusLine.command // ""' "$KIT_DIR/settings.json")"
assert_true "the statusLine pair in the table matches settings.json statusLine.command" "$({ trap '' PIPE; printf '%s' "$SL_CMD" 2>/dev/null || :; } | grep -q 'statusline\.sh'; echo $?)"

# ============================================================
echo "== T4 install.sh and adopt.sh keep no table of their own =="
# ============================================================
for f in install.sh lib/adopt.sh; do
  assert_true "$f defines no kit_module_hooks / kit_module_clis function" "$(! grep -qE '^kit_module_(hooks|clis)\(\)' "$KIT_DIR/$f"; echo $?)"
  assert_true "$f has no KIT_KNOWN_MODULES string literal" "$(! grep -qE '^KIT_KNOWN_MODULES="[a-z_ ]+"' "$KIT_DIR/$f"; echo $?)"
  assert_true "$f sources lib/config/modules.sh" "$(grep -q 'config/modules\.sh' "$KIT_DIR/$f"; echo $?)"
done

# ============================================================
echo "== T5 NEGATIVE CONTROL: the check names each planted fault =="
# ============================================================
PLANT="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
{
  grep -v '^board' "$TABLE"
  printf 'board\tcore\tSessionStart:board-row-gate.sh PreToolUse:backlog-stage.sh\t-\n'
  printf 'ghost\topt-in\tStop:no-such-hook.sh\t-\n'
  printf 'rival\topt-in\tStop:anti-rationalization.sh\t-\n'
} > "$PLANT/modules.tsv"
P_PLANT="$(table_problems "$PLANT/modules.tsv" "$KIT_DIR/settings.json")"
assert_true "NC: a hook under the wrong event is named" "$({ trap '' PIPE; printf '%s\n' "$P_PLANT" 2>/dev/null || :; } | grep -q 'board-row-gate.sh is wired under'; echo $?)"
assert_true "NC: a table hook with no file is named" "$({ trap '' PIPE; printf '%s\n' "$P_PLANT" 2>/dev/null || :; } | grep -q 'no-such-hook.sh has no file'; echo $?)"
assert_true "NC: a table hook that is not wired is named" "$({ trap '' PIPE; printf '%s\n' "$P_PLANT" 2>/dev/null || :; } | grep -q 'table pair Stop:no-such-hook.sh is not wired'; echo $?)"
assert_true "NC: a script claimed by two modules is named" "$({ trap '' PIPE; printf '%s\n' "$P_PLANT" 2>/dev/null || :; } | grep -q 'script in two modules: anti-rationalization.sh'; echo $?)"
assert_true "NC: the real table is not flagged by the same check (no vacuous pass)" "$([ -z "$P_SET" ]; echo $?)"
rm -rf "$PLANT"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
