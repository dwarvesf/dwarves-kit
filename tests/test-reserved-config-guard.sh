#!/usr/bin/env bash
# test-reserved-config-guard.sh -- harness-ops sub-goal 08 (reserved-keys-guard).
#
# The forward-looking-but-not-built config surface -- [features] (auto_improvement,
# learning_ledger) and all of [team].* -- must stay HONESTLY INERT: resolver-readable
# via kit_config_get, but with NO live code path (flipping one changes no behavior).
# This is the opposite failure mode from test-install-modules.sh's [modules] lint:
# there the concern is "no OPTIONAL module wired without being asked"; here it is
# "these specific keys must never be wired at all yet, and that must be documented,
# not a silent no-op a user mistakes for a working toggle."
#
# Run: bash tests/test-reserved-config-guard.sh
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
assert_true() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

# auto_improvement graduated [design] -> [impl] in SPEC-195 (`learn propose` is now built),
# but its FLAG must STILL never be read kit-side: the command is always available, and the
# weekly cadence gates on the flag CONSUMER-side (SG-10), never kit-side. So it stays in the
# no-live-path guard below -- that assertion now protects a live invariant (no kit-side read
# of an [impl] flag), not just a not-built one. learning_ledger stays [consumer]; [team].* inert.
RESERVED_FEATURES_KEYS="auto_improvement learning_ledger"
RESERVED_TEAM_KEYS="actor_identity attestation ci_recheck spec_reservation policy onboarding pilot"

# ============================================================
echo "== NC no-live-path: nothing under lib/, commands/, hooks/ branches on [features]/[team] =="
# ============================================================
# Mirrors the hooks-only-kit.toml lint in test-install-modules.sh: a grep-based
# STANDING assertion, not a registry. Any kit_config_get call addressing
# features.<key> or team.<key> would be a live code path -- out of scope for this
# sub-goal (see goal file "Not: wiring any reserved key to a live path").
LIVE_HITS=""
for k in $RESERVED_FEATURES_KEYS; do
  hits="$(grep -rln "kit_config_get[[:space:]]*['\"]\\?features\\.$k" "$KIT_DIR/lib" "$KIT_DIR/commands" "$KIT_DIR/hooks" 2>/dev/null || true)"
  [ -n "$hits" ] && LIVE_HITS="$LIVE_HITS$hits"$'\n'
done
for k in $RESERVED_TEAM_KEYS; do
  hits="$(grep -rln "kit_config_get[[:space:]]*['\"]\\?team\\.$k" "$KIT_DIR/lib" "$KIT_DIR/commands" "$KIT_DIR/hooks" 2>/dev/null || true)"
  [ -n "$hits" ] && LIVE_HITS="$LIVE_HITS$hits"$'\n'
done
assert_true "no lib/commands/hooks file reads a [features]/[team] key (leaked: ${LIVE_HITS:-none})" "$([ -z "$LIVE_HITS" ]; echo $?)"

# ============================================================
echo "== NC lint-load-bearing: the grep genuinely catches a planted live-path read =="
# ============================================================
# A vacuously-green lint proves nothing (SPEC-183's same NC pattern). Plant a fake
# consumer that DOES call kit_config_get team.actor_identity and confirm the same
# grep this test uses would flag it.
FAKE_DIR="$(mktemp -d)"; trap 'rm -rf "$FAKE_DIR"' EXIT
mkdir -p "$FAKE_DIR/lib/fake"
cat > "$FAKE_DIR/lib/fake/fake-team-consumer.sh" <<'EOF'
#!/usr/bin/env bash
v="$(kit_config_get team.actor_identity false)"
EOF
PLANTED_HIT="$(grep -rln "kit_config_get[[:space:]]*['\"]\\?team\\.actor_identity" "$FAKE_DIR/lib" 2>/dev/null || true)"
assert_true "NC: planted live-path read of team.actor_identity is caught by the same grep" "$([ -n "$PLANTED_HIT" ]; echo $?)"

# ============================================================
echo "== resolver-readable: kit_config_get surfaces reserved keys via project override =="
# ============================================================
PROJ="$(mktemp -d)"
cat > "$PROJ/.kit.toml" <<'TOML'
[features]
auto_improvement = true
[team]
actor_identity = true
TOML
export KIT_PROJECT_ROOT="$PROJ" KIT_CONFIG_ROOT="$KIT_DIR"
# shellcheck source=/dev/null
source "$KIT_DIR/lib/config/kit-config.sh"
V1="$(kit_config_get features.auto_improvement false)"
V2="$(kit_config_get team.actor_identity false)"
assert_true "resolver reads project override features.auto_improvement=true" "$([ "$V1" = "true" ]; echo $?)"
assert_true "resolver reads project override team.actor_identity=true" "$([ "$V2" = "true" ]; echo $?)"

# ============================================================
echo "== NC inert-flip-changes-nothing: flipping the reserved keys touches no observed behavior =="
# ============================================================
# Behavioral negative control: run a representative spine surface (the config
# resolver's own selftest, plus the [modules] lane classifier) once with the
# BASELINE kit-root config, once with the project override above flipping
# features.auto_improvement / team.actor_identity to true, and diff the output.
# If either key had a live path, one of these two runs would differ.
BASE_OUT="$(unset KIT_PROJECT_ROOT; KIT_CONFIG_ROOT="$KIT_DIR" bash "$KIT_DIR/lib/config/kit-config.sh" selftest 2>&1)"
FLIP_OUT="$(KIT_PROJECT_ROOT="$PROJ" KIT_CONFIG_ROOT="$KIT_DIR" bash "$KIT_DIR/lib/config/kit-config.sh" selftest 2>&1)"
assert_true "config-resolver selftest identical baseline vs inert-key-flipped (features.auto_improvement, team.actor_identity)" "$([ "$BASE_OUT" = "$FLIP_OUT" ]; echo $?)"

BASE_LANE="$(bash "$KIT_DIR/lib/classify/lane-classify.sh" classify "guard reserved inert config keys" 2>&1)"
FLIP_LANE="$(KIT_PROJECT_ROOT="$PROJ" bash "$KIT_DIR/lib/classify/lane-classify.sh" classify "guard reserved inert config keys" 2>&1)"
assert_true "lane-classify output identical baseline vs inert-key-flipped" "$([ "$BASE_LANE" = "$FLIP_LANE" ]; echo $?)"

# ============================================================
echo "== status tags: kit.toml documents the reserved keys as [design]/[consumer], not live =="
# ============================================================
KIT_TOML="$KIT_DIR/kit.toml"
assert_true "kit.toml: auto_improvement tagged [impl] (graduated in SPEC-195)" "$(grep -qE 'auto_improvement[[:space:]]*=.*#[[:space:]]*\[impl\]' "$KIT_TOML"; echo $?)"
assert_true "kit.toml: learning_ledger tagged [consumer]" "$(grep -qE 'learning_ledger[[:space:]]*=.*#[[:space:]]*\[consumer\]' "$KIT_TOML"; echo $?)"
TEAM_UNTAGGED=""
for k in $RESERVED_TEAM_KEYS; do
  grep -qE "^$k[[:space:]]*=.*#[[:space:]]*\[design\]" "$KIT_TOML" || TEAM_UNTAGGED="$TEAM_UNTAGGED $k"
done
assert_true "kit.toml: all [team] keys tagged [design] (untagged:${TEAM_UNTAGGED:- none})" "$([ -z "$TEAM_UNTAGGED" ]; echo $?)"

echo ""
echo "== $((PASS+FAIL)) run, $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
