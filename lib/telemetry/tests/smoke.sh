#!/usr/bin/env bash
# telemetry smoke test -- the durable-ledger-root resolver (lib/telemetry/kit-log-dir.sh).
#
# The resolver decides WHERE every ledger in the kit is written (gate-ledger, proof-ledger,
# lane-telemetry, precedent, mega-merge, queue). Getting it wrong is not a cosmetic bug: it is
# the 2026-07-01 class of incident (corpus written inside the plugin state dir, wiped by a
# reinstall) or the silent-wrong-path class (an empty root turning every append into a relative
# `runs/...` write in whatever cwd the caller happened to be in). So the four precedence levels,
# the set-but-empty FATAL, and the symlink refusal each get an assertion here.
#
# FULLY HERMETIC: every case runs in a fresh `bash -c` with $HOME, $KIT_CONFIG_ROOT,
# $KIT_PROJECT_ROOT and $XDG_STATE_HOME pointed at mktemp dirs, so no case can read or write the
# real machine corpus. KIT_LEDGER_DIR / DWARVES_KIT_LOG_DIR are NEVER exported by this script;
# they are passed per-case as command prefixes, which is what makes "genuinely unset" testable.
#
# Run: bash lib/telemetry/tests/smoke.sh   Pass: "smoke: all N passed", exit 0.
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"          # lib/telemetry
RESOLVER="$DIR/kit-log-dir.sh"
LANE_TELEMETRY="$DIR/lane-telemetry.sh"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }
eq() {  # eq <label> <got> <want>
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got [$2] want [$3])"; fi
}

# `cd`+`pwd` normalizes the path: macOS $TMPDIR carries a trailing slash, so a raw mktemp path
# holds a `//` that $PWD later collapses -- which would make the isolated-mode compare (P3b,
# built from $PWD) fail on a string artifact rather than on resolver behavior.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/telemetry-smoke.XXXXXX")" && pwd)"
trap 'rm -rf "$WORK"' EXIT

HOME_FX="$WORK/home";      mkdir -p "$HOME_FX"
XDG_FX="$WORK/xdg-state";  mkdir -p "$XDG_FX"
CFG_FX="$WORK/kit-root";   mkdir -p "$CFG_FX"     # holds kit.toml (the kit-root config layer)
PROJ_FX="$WORK/project";   mkdir -p "$PROJ_FX"    # holds .kit.toml (the project config layer)

# The config layer the resolver consults at level 3. Default: no [ledger].location at all, so
# level 4 (XDG) is what a bare install resolves to. Individual cases rewrite kit.toml.
: > "$CFG_FX/kit.toml"

# Every case inherits this hermetic env; the two ledger-root env vars are deliberately absent.
env_base=(
  "HOME=$HOME_FX"
  "XDG_STATE_HOME=$XDG_FX"
  "KIT_CONFIG_ROOT=$CFG_FX"
  "KIT_PROJECT_ROOT=$PROJ_FX"
)

# resolve [extra env...] -- print kit_resolve_log_dir's stdout from a FRESH shell.
resolve() {
  env "${env_base[@]}" "$@" bash -c 'source "$0" && kit_resolve_log_dir' "$RESOLVER" 2>/dev/null
}

echo "== precedence: KIT_LEDGER_DIR > DWARVES_KIT_LOG_DIR > kit.toml [ledger].location > XDG =="

# P1: the canonical knob wins over BOTH the alias and the toml (all three set at once, so this
# asserts the ORDER, not merely that the var is read).
printf '[ledger]\nlocation = "%s"\n' "$WORK/from-toml" > "$CFG_FX/kit.toml"
eq "P1 KIT_LEDGER_DIR wins over the alias and the toml" \
   "$(resolve "KIT_LEDGER_DIR=$WORK/from-canonical" "DWARVES_KIT_LOG_DIR=$WORK/from-alias")" \
   "$WORK/from-canonical"

# P2: with the canonical knob genuinely unset, the back-compat alias wins over the toml. This is
# the level every pre-SPEC-182 test pin and the live corpus still resolve through.
eq "P2 DWARVES_KIT_LOG_DIR (alias) wins over the toml when KIT_LEDGER_DIR is unset" \
   "$(resolve "DWARVES_KIT_LOG_DIR=$WORK/from-alias")" \
   "$WORK/from-alias"

# P3: with neither env var set, [ledger].location decides. Three values, three meanings.
eq "P3a kit.toml [ledger].location = <explicit path>" \
   "$(resolve)" \
   "$WORK/from-toml"

printf '[ledger]\nlocation = "isolated"\n' > "$CFG_FX/kit.toml"
eq "P3b kit.toml location = isolated -> \$PWD/.kit/logs" \
   "$(cd "$PROJ_FX" && resolve)" \
   "$PROJ_FX/.kit/logs"

# P4: location = shared (and, below, absent entirely) falls to the XDG default -- the whole point
# of SPEC-097: a path OUTSIDE ~/.claude, where no plugin reinstall can reach it.
printf '[ledger]\nlocation = "shared"\n' > "$CFG_FX/kit.toml"
eq "P4a location = shared -> XDG state default" \
   "$(resolve)" \
   "$XDG_FX/dwarves-kit/logs"

: > "$CFG_FX/kit.toml"
eq "P4b no [ledger] key at all -> XDG state default" \
   "$(resolve)" \
   "$XDG_FX/dwarves-kit/logs"

# And the default is never inside the reinstall blast zone, whatever HOME is.
case "$(resolve)" in
  *".claude/dwarves-kit"*) no "P4c default resolves INSIDE the ~/.claude reinstall blast zone" ;;
  *) ok "P4c the default is outside ~/.claude (the SPEC-097 invariant)" ;;
esac

echo "== NEGATIVE CONTROL: a set-but-empty root must FAIL LOUD, not resolve =="

# The footgun this guards: an empty root makes every writer append to a RELATIVE `runs/...` path
# in the caller's cwd. Silent, and the corpus scatters. The contract is a clean nonzero exit.
out="$(env "${env_base[@]}" "KIT_LEDGER_DIR=" bash -c 'source "$0" && kit_resolve_log_dir' "$RESOLVER" 2>"$WORK/err.txt")"
rc=$?
[ "$rc" -ne 0 ] && ok "NC1 empty KIT_LEDGER_DIR exits nonzero (rc=$rc)" || no "NC1 empty KIT_LEDGER_DIR exited 0 -- silent fall-through"
[ -z "$out" ] && ok "NC2 empty KIT_LEDGER_DIR prints NO path on stdout" || no "NC2 empty KIT_LEDGER_DIR still printed a path [$out]"
grep -q 'set but empty' "$WORK/err.txt" && ok "NC3 the failure names the cause on stderr" || no "NC3 no diagnostic on stderr"

# Falsifier for NC1-NC3: the same call with a NON-empty value must succeed. Without this row the
# three assertions above would also pass if the resolver were simply broken for every input.
eq "NC4 (falsifier) a non-empty KIT_LEDGER_DIR still resolves" \
   "$(resolve "KIT_LEDGER_DIR=$WORK/nonempty")" \
   "$WORK/nonempty"

echo "== NEGATIVE CONTROL: migration must refuse a symlinked legacy dir =="

# Threat: the legacy dir (~/.claude/dwarves-kit/logs) is attacker-replaceable with a symlink, and
# `cp -R legacy/.` DEREFERENCES it -- fanning the link target's contents into the corpus that
# /kit:retro and the effectiveness eval read. The resolver refuses to migrate THROUGH a symlink.
# Migration only runs when neither env knob is set (an explicit root means the caller owns the
# path), so both cases below steer the durable root via the toml instead.

# 6a POSITIVE CONTROL: a real legacy DIRECTORY does migrate. Without this, "nothing was copied"
# in 6b would prove nothing -- migration might simply be dead.
LEGACY_REAL="$HOME_FX/.claude/dwarves-kit/logs"
mkdir -p "$LEGACY_REAL/runs"
printf 'ts | START | lane=normal classified=normal type=feature repo=fixture\n' > "$LEGACY_REAL/runs/real-run.log"
printf '[ledger]\nlocation = "%s"\n' "$WORK/durable-a" > "$CFG_FX/kit.toml"
env "${env_base[@]}" bash -c 'source "$0" && kit_migrate_log_dir' "$RESOLVER" >/dev/null 2>&1
[ -f "$WORK/durable-a/runs/real-run.log" ] \
  && ok "6a POSITIVE CONTROL: a real legacy dir IS migrated (so 6b's refusal is falsifiable)" \
  || no "6a a real legacy dir was NOT migrated -- migration is dead, 6b proves nothing"

# 6b the refusal itself: same shape, but the legacy dir is a symlink to an attacker-owned tree.
rm -rf "$HOME_FX/.claude"
mkdir -p "$WORK/evil" "$HOME_FX/.claude/dwarves-kit"
printf 'exfiltrate-me\n' > "$WORK/evil/secret.txt"
ln -s "$WORK/evil" "$LEGACY_REAL"
printf '[ledger]\nlocation = "%s"\n' "$WORK/durable-b" > "$CFG_FX/kit.toml"
env "${env_base[@]}" bash -c 'source "$0" && kit_migrate_log_dir' "$RESOLVER" >/dev/null 2>"$WORK/mig-err.txt"

[ ! -e "$WORK/durable-b/secret.txt" ] \
  && ok "6b the symlink target's contents are NOT copied into the corpus" \
  || no "6b migration followed the symlink and exfiltrated the target into the corpus"
grep -q 'symlink' "$WORK/mig-err.txt" \
  && ok "6c the refusal is announced on stderr" \
  || no "6c the symlink refusal was silent"
[ -f "$WORK/durable-b/.migrated" ] \
  && ok "6d the sentinel is dropped, so a hostile link is not re-scanned every command" \
  || no "6d no sentinel -- the hostile link would be re-scanned on every kit command"

echo "== wiring: the module's own consumer resolves through the resolver =="

# The precedence chain above is only worth anything if the libs that WRITE and READ the corpus
# actually go through it. lane-telemetry.sh is telemetry's own reader: point the canonical knob at
# a seeded fixture root and its `report` must see the run.
FIXROOT="$WORK/fixture-root"
mkdir -p "$FIXROOT/runs"
cat > "$FIXROOT/runs/smoke-rid-001.log" <<'LEDGER'
2026-07-15T00:00:00Z | START | lane=normal classified=full type=feature ctype=feature repo=fixture
2026-07-15T00:01:00Z | GATE | review | ran | verdict=clean findings=0
LEDGER
rep="$(env "${env_base[@]}" "KIT_LEDGER_DIR=$FIXROOT" bash "$LANE_TELEMETRY" report 2>/dev/null)"
printf '%s' "$rep" | grep -q 'smoke-rid-001' \
  && ok "7a lane-telemetry report reads the root the resolver returns" \
  || no "7a lane-telemetry did not read the resolved root"
# The seeded run has lane=normal but classified=full: the aggregator must count it as a misroute.
printf '%s' "$rep" | grep -q 'lane-misrouted: 1' \
  && ok "7b the seeded lane misroute is aggregated (chosen != classified)" \
  || no "7b the lane misroute was not aggregated"

echo ""
if [ "$fail" -eq 0 ]; then
  echo "smoke: all $pass passed"
  exit 0
fi
echo "smoke: $pass passed, $fail FAILED" >&2
exit 1
