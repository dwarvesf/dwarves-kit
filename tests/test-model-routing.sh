#!/usr/bin/env bash
# test-model-routing.sh -- SPEC-116: proves the `Model:` field is LOAD-BEARING on the delegate
# dispatch path, not advisory. Companion to (not a replacement for):
#   - tests/test-orchestrate.sh TEST 8, which proves the `sonnet` tier + the inherit fallback on
#     the SERIAL path only.
#   - tests/test-routing.sh, which proves lib/classify/route-suggest.sh's SUGGESTION logic (decompose-time),
#     not dispatch-time enforcement.
#
# This file proves:
#   1. the DEFAULT-APPLIED positive case for ALL THREE tiers (opus/sonnet/haiku) on the serial
#      delegate path -- a goal file carrying `Model: <tier>` reaches a real
#      `claude -p --model <tier>` invocation, not just that the field is read.
#   2. the SAME on the concurrent wave delegate path, for one tier (opus) -- the wave dispatch site
#      shares `_route()` with the serial site; one case catches drift without a full second matrix.
#   3. route-suggest.sh has NO call site in the dispatch functions, so it cannot silently override
#      an explicit `Model:` field (the "alignment" ADR-0032/open-fork-3 asks for is structural).
#   4. the NEGATIVE CONTROL: a goal file with NO `Model:` field passes no `--model` flag (documented
#      default: inherit the parent session's tier, SPEC-107 "Open questions"), not a crash and not a
#      silently wrong tier.
#
# Run: bash tests/test-model-routing.sh   (exit 0 = pass, 1 = fail)

set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
fails=0; total=0
pass() { total=$((total + 1)); echo "PASS $*"; }
fail() { total=$((total + 1)); echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ============================ SECTION 1: route-suggest alignment (structural) ============================
# route-suggest.sh is a decompose-time SUGGESTER (invoked by a human / agents/meta-agent.md Mode B
# when DRAFTING a goal file's Model: line). It has NO call site in lib/queue/orchestrate.sh's dispatch
# functions, so it cannot contradict an already-written explicit Model: field at dispatch time --
# the two surfaces operate in disjoint phases. This is a structural grep, not a runtime mock: there
# is no runtime interaction between the two scripts to mock.
if grep -n 'route-suggest' "$ORCH" >/dev/null 2>&1; then
  fail "route-suggest alignment: lib/queue/orchestrate.sh calls route-suggest.sh at dispatch time (would need a runtime alignment check, not just this structural one)"
else
  pass "route-suggest alignment: lib/queue/orchestrate.sh has no route-suggest.sh call site (cannot contradict an explicit Model: field)"
fi

# ============================ SECTION 2: serial delegate path, all three tiers + negative control ==========
mk_megagoal_tiered() {  # dir model-line-or-empty
  local d="$1" modelline="$2"
  mkdir -p "$d/goals"
  cat > "$d/ROADMAP.md" <<'EOF'
# Mega-goal: tiered fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  {
    printf '# SG-01\n'
    [ -n "$modelline" ] && printf '%s\n' "$modelline"
    printf '\nGOALFILE-MARKER-01 contract for SG-01\n'
  } > "$d/goals/01-first.md"
}

# Mock claude: logs "<id>|<argv flags>" (prompt arrives on stdin, argv carries only route flags),
# then flips SG-01's box so the loop advances cleanly (grounded completion).
cat > "$TMP/claude-route" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
printf '%s|%s\n' "$id" "$*" >> "$ROUTE_LOG"
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$ROUTE_RM" > "$ROUTE_RM.tmp" && mv "$ROUTE_RM.tmp" "$ROUTE_RM"
EOF
chmod +x "$TMP/claude-route"

run_serial_case() {  # tier(opus|sonnet|haiku|none) expect_flag(--model X or empty)
  local tier="$1" want="$2" d log
  d="$TMP/serial-$tier"; log="$TMP/serial-$tier.log"; : > "$log"
  if [ "$tier" = none ]; then
    mk_megagoal_tiered "$d" ""
  else
    mk_megagoal_tiered "$d" "Model: $tier"
  fi
  # TIER4_CLOSE=0 (SPEC-118): this all-auto single-sub-goal fixture reaches the _next-empty terminal,
  # where the TIER-4 mega-close now fires by default. This suite only tests per-sub-goal model routing,
  # so opt out of the close here -- it is exercised by its own dedicated tests/test-tier4-close.sh.
  ROUTE_LOG="$log" ROUTE_RM="$d/ROADMAP.md" CLAUDE_FLAGS="" TIER4_CLOSE=0 \
    CLAUDE_CMD="$TMP/claude-route" bash "$ORCH" run "$d" >/dev/null 2>&1
  if [ -n "$want" ]; then
    grep -q "^SG-01|.*$want" "$log" \
      && pass "serial: Model: $tier -> dispatch '$want' (default-applied)" \
      || { fail "serial: Model: $tier did NOT reach '$want'"; cat "$log"; }
  else
    { grep '^SG-01|' "$log" | grep -qv -- '--model'; } \
      && pass "serial: no Model: field -> no --model flag (inherit fallback, no crash)" \
      || { fail "serial: no-Model: case got an unexpected --model flag"; cat "$log"; }
  fi
}

run_serial_case opus   "--model opus"
run_serial_case sonnet "--model sonnet"
run_serial_case haiku  "--model haiku"
run_serial_case none   ""

# ============================ SECTION 3: wave (concurrent) delegate path, opus tier ============================
# Source orchestrate.sh to call _wave_run directly (the tests/test-orchestrate-wavefront.sh pattern).
# The guard in orchestrate.sh (`[ "${BASH_SOURCE[0]}" = "$0" ]`-style main gate) keeps `main "$@"`
# from firing on source.
# shellcheck source=../lib/queue/orchestrate.sh
source "$ORCH"

mk_git_mega() {  # repo-root
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
}

WR="$TMP/wave-repo"; mk_git_mega "$WR"
WM="$WR/mega"; mkdir -p "$WM/goals"
cat > "$WM/ROADMAP.md" <<'EOF'
# Mega-goal: wave-tiered fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WM/POINTER_PROMPT.md"
cat > "$WM/goals/01-SG-01.md" <<'EOF'
# SG-01: sub-goal
**Branch:** feat/sg-01
Model: opus

## Touches
- lib/wave-tiered/**
EOF

WAVE_LOG="$TMP/wave.log"; : > "$WAVE_LOG"
cat > "$TMP/claude-wave-route" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
printf '%s|%s\n' "$id" "$*" >> "$WAVE_ROUTE_LOG"
"$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
EOF
chmod +x "$TMP/claude-wave-route"

wrc=0
( export WAVE_ROUTE_LOG="$WAVE_LOG" ORCH="$ORCH" MEGADIR="$WM" CLAUDE_FLAGS="" WAVE_CAP=2 \
    CLAUDE_CMD="$TMP/claude-wave-route"
  _wave_run "$WM" "$WM/ROADMAP.md" ) > "$TMP/wave.out" 2>&1 || wrc=$?

if [ "$wrc" = 0 ] && grep -q '^SG-01|.*--model opus' "$WAVE_LOG"; then
  pass "wave: Model: opus -> dispatch '--model opus' (default-applied, concurrent delegate path)"
else
  fail "wave: Model: opus did not reach --model on the wave path (rc=$wrc)"; cat "$WAVE_LOG" "$TMP/wave.out" 2>/dev/null
fi

echo ""
echo "=== $((total - fails))/$total passed, $fails failed ==="
[ "$fails" -eq 0 ]
