#!/usr/bin/env bash
# test-hook-log-dir.sh -- lib/telemetry/hook-log-dir.sh: hook logs live in hooks/ under the ledger
# root, one setting moves ledgers and hook logs together, and the old default is copied once,
# never overwritten and never deleted.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HLD="$KIT_DIR/lib/telemetry/hook-log-dir.sh"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: want '$3' got '$2'"; fi; }
T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'case "$T" in /*/*) command rm -rf -- "$T" ;; esac 2>/dev/null' EXIT

# resolve <home> [VAR=val ...]: the dir kit_hook_log_dir prints under a scrubbed environment
resolve() {
  local home=$1; shift
  env -i PATH="$PATH" HOME="$home" XDG_STATE_HOME="$home/xdg" KIT_CONFIG_OPERATOR="$home/none" \
    KIT_CONFIG_ROOT="$home/none" KIT_PROJECT_ROOT="$home/none" "$@" \
    bash -c '. "$1"; kit_hook_log_dir' _ "$HLD"
}
new_home() { local h; h=$(mktemp -d "$T/h.XXXXXX"); mkdir -p "$h/.claude/dwarves-kit/logs"; printf '%s' "$h"; }

# 1. precedence: default is the XDG root, the knobs move it, KIT_LEDGER_DIR beats the alias
H=$(new_home)
check "default is the XDG ledger root plus hooks" "$(resolve "$H")" "$H/xdg/dwarves-kit/logs/hooks"
check "DWARVES_KIT_LOG_DIR moves it" "$(resolve "$H" DWARVES_KIT_LOG_DIR="$H/pin")" "$H/pin/hooks"
check "KIT_LEDGER_DIR beats the alias" "$(resolve "$H" KIT_LEDGER_DIR="$H/led" DWARVES_KIT_LOG_DIR="$H/pin")" "$H/led/hooks"
check "an empty KIT_LEDGER_DIR falls back to the XDG root, never a relative path" \
  "$(resolve "$H" KIT_LEDGER_DIR= 2>/dev/null)" "$H/xdg/dwarves-kit/logs/hooks"

# 2. migration: copies the known hook logs, leaves the rest, keeps the old dir intact
H=$(new_home); L="$H/.claude/dwarves-kit/logs"
printf 'old ship\n' > "$L/ship-gate.log"; printf 'old safety\n' > "$L/safety-gate.log"
printf 'keep\n' > "$L/completeness.log"
D=$(resolve "$H")
check "legacy hook log copied" "$(cat "$D/ship-gate.log" 2>/dev/null)" "old ship"
check "second legacy hook log copied" "$(cat "$D/safety-gate.log" 2>/dev/null)" "old safety"
check "a non-hook file is not copied" "$([ -e "$D/completeness.log" ] && echo copied || echo no)" "no"
check "the old dir is left intact" "$(cat "$L/ship-gate.log")/$(ls "$L" | wc -l | tr -d ' ')" "old ship/3"
check "the sentinel is dropped" "$([ -f "$D/.migrated" ] && echo yes || echo no)" "yes"
printf 'later\n' > "$L/secrets-guard.log"; resolve "$H" >/dev/null
check "one time only: a later legacy file is not pulled in" "$([ -e "$D/secrets-guard.log" ] && echo copied || echo no)" "no"

# 3. no clobber: an existing new-dir log survives the copy
H=$(new_home); L="$H/.claude/dwarves-kit/logs"; D="$H/xdg/dwarves-kit/logs/hooks"; mkdir -p "$D"
printf 'new wins\n' > "$D/ship-gate.log"; printf 'old loses\n' > "$L/ship-gate.log"
resolve "$H" >/dev/null
check "cp -n never overwrites" "$(cat "$D/ship-gate.log")" "new wins"

# 4. a pinned root never ingests the machine's old default, but does adopt its own old files
H=$(new_home); L="$H/.claude/dwarves-kit/logs"; printf 'machine\n' > "$L/ship-gate.log"
mkdir -p "$H/pin"; printf 'pin old\n' > "$H/pin/safety-gate.log"
D=$(resolve "$H" DWARVES_KIT_LOG_DIR="$H/pin")
check "pinned root does not ingest the old default" "$([ -e "$D/ship-gate.log" ] && echo ingested || echo no)" "no"
check "pinned root adopts a log that sat directly in it" "$(cat "$D/safety-gate.log" 2>/dev/null)" "pin old"

# 4b. [ledger].location = isolated: a per-project root never ingests the machine-wide old logs
H=$(new_home); L="$H/.claude/dwarves-kit/logs"; printf 'machine\n' > "$L/ship-gate.log"
mkdir -p "$H/proj"; printf '[ledger]\nlocation = "isolated"\n' > "$H/proj/.kit.toml"
D=$(cd "$H/proj" && env -i PATH="$PATH" HOME="$H" XDG_STATE_HOME="$H/xdg" KIT_CONFIG_OPERATOR="$H/none" \
  KIT_CONFIG_ROOT="$H/none" KIT_PROJECT_ROOT="$H/proj" bash -c '. "$1"; kit_hook_log_dir' _ "$HLD")
check "isolated root is the project's .kit/logs/hooks" "$D" "$H/proj/.kit/logs/hooks"
check "isolated root does not ingest the machine-wide logs" "$([ -e "$D/ship-gate.log" ] && echo ingested || echo no)" "no"

# 5. a symlinked old dir is refused
H=$(new_home); rmdir "$H/.claude/dwarves-kit/logs"; mkdir -p "$H/elsewhere"; printf 'planted\n' > "$H/elsewhere/ship-gate.log"
ln -s "$H/elsewhere" "$H/.claude/dwarves-kit/logs"
D=$(resolve "$H")
check "a symlinked legacy dir is not copied through" "$([ -e "$D/ship-gate.log" ] && echo copied || echo no)" "no"

# 6. a real hook logs there: safety-gate under a pinned root, with and without lib/ beside it
H=$(new_home)
cmd="rm -rf ""$H/data"
payload=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
printf '%s' "$payload" | env -i PATH="$PATH" HOME="$H" DWARVES_KIT_LOG_DIR="$H/pin" bash "$KIT_DIR/hooks/safety-gate.sh" >/dev/null 2>&1
check "safety-gate logs into <root>/hooks" "$(grep -c 'BLOCKED' "$H/pin/hooks/safety-gate.log" 2>/dev/null)" "1"
check "nothing lands in the old default" "$(ls "$H/.claude/dwarves-kit/logs" | wc -l | tr -d ' ')" "0"

mkdir -p "$H/bare/hooks"; cp "$KIT_DIR/hooks/safety-gate.sh" "$H/bare/hooks/"
printf '%s' "$payload" | env -i PATH="$PATH" HOME="$H" DWARVES_KIT_LOG_DIR="$H/pin2" bash "$H/bare/hooks/safety-gate.sh" >/dev/null 2>&1
check "without lib/ the inline fallback still lands in <root>/hooks" "$(grep -c 'BLOCKED' "$H/pin2/hooks/safety-gate.log" 2>/dev/null)" "1"

echo "hook-log-dir: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
