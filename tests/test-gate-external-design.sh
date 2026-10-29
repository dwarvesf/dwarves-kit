#!/usr/bin/env bash
# test-gate-external-design.sh -- `gate-ledger.sh external-design <rid> <citation> <reason>` lets one
# ledger line cite a design record in another GitHub repo and satisfy the design-side gates
# (think, design, design-critique, spec, validate, design-record). The citation is checked through
# `gh api` when written and again whenever check() needs it, so a bare string or a hand-appended
# bogus citation never passes. Per-gate overrides keep working unchanged.
#
# Isolation: a fresh DWARVES_KIT_LOG_DIR per case, KIT_LEDGER_DIR unset, and GH_CMD pointing at a stub
# that answers from a fixture table, so no case touches the network or the real ledger corpus.
#
# Run: bash tests/test-gate-external-design.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
HOOK="$KIT_DIR/hooks/ship-gate.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }
ok() { if eval "$2"; then assert "$1" 0; else assert "$1 (rc: ${RC:-} out: ${OUT:-} err: ${ERR:-})" 1; fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

SHA=7e3e190e854c23ecc4571f203970cd993d08b041
GOOD="consolelabs/playdate-agent@$SHA:docs/specs/SPEC-005-relay-link-and-seal.md"
MISSING="consolelabs/playdate-agent@$SHA:docs/specs/SPEC-999-nope.md"
DIR="consolelabs/playdate-agent@$SHA:docs/specs"
PRIVATE="consolelabs/secret-design@$SHA:docs/x.md"
PR_MERGED="https://github.com/consolelabs/playdate-agent/pull/35"
PR_OPEN="https://github.com/consolelabs/playdate-agent/pull/36"
COVERS="think design design-critique spec validate design-record"
BRANCH_GATES="test-plan build review docs ship reflect"

# The stub gh: `api <endpoint> --jq <filter>` answers from the table below the way the real API does
# (a 404 prints its body on stdout and exits 1). Every call is appended to $GH_LOG.
STUB_DIR="$(_mk)"; GH_LOG="$STUB_DIR/calls"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
[ "${1:-}" = api ] || exit 2
if [ -f "$GH_LOG.hang" ]; then sleep 20; exit 0; fi
if [ -f "$GH_LOG.down" ]; then echo 'gh: Not Found (HTTP 404)'; exit 1; fi
case "$2" in
  "repos/consolelabs/playdate-agent/contents/docs/specs/SPEC-005-relay-link-and-seal.md?ref=7e3e190e854c23ecc4571f203970cd993d08b041") echo file ;;
  "repos/consolelabs/playdate-agent/contents/docs/specs?ref=7e3e190e854c23ecc4571f203970cd993d08b041") echo dir ;;
  "repos/consolelabs/playdate-agent/pulls/35") echo true ;;
  "repos/consolelabs/playdate-agent/pulls/36") echo false ;;
  "repos/consolelabs/secret-design/"*) echo '{"message":"Resource not accessible by integration","status":"403"}gh: Resource not accessible by integration (HTTP 403)'; exit 1 ;;
  *) echo '{"message":"Not Found","status":"404"}gh: Not Found (HTTP 404)'; exit 1 ;;
esac
STUB
chmod +x "$STUB_DIR/gh"
export GH_LOG

LOGD=""
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; : > "$GH_LOG"; rm -f "$GH_LOG.hang" "$GH_LOG.down"; }
# run <verb...>: stdout -> OUT, stderr -> ERR, exit -> RC. GHX overrides the gh command.
run() {
  local e; e="$(_mk)/err"
  OUT="$(env -u KIT_LEDGER_DIR DWARVES_KIT_LOG_DIR="$LOGD" KIT_CONFIG_OPERATOR=/nonexistent GH_CMD="${GHX:-$STUB_DIR/gh}" bash "$GL" "$@" 2>"$e")"; RC=$?
  ERR="$(cat "$e")"
}
ledger_of() { cat "$LOGD/runs/$1.log" 2>/dev/null; }
n_cite() { ledger_of "$1" | grep -c '| GATE | external-design | cite | ' || true; }
gate_line() { printf '%s | GATE | %s | %s | %s\n' "2026-10-30T00:00:00Z" "$2" "$3" "$4" >> "$LOGD/runs/$1.log"; }
branch_gates() { local p; for p in $BRANCH_GATES; do gate_line "$1" "$p" ran "fixture $p"; done; }
n_calls() { grep -c '' "$GH_LOG" 2>/dev/null || true; }

echo "=== gate-ledger external-design: the verb ==="

new_log
run external-design r "$GOOD" "relay design lives in playdate-agent"
ok "verb: a file at a pinned commit is cited, exit 0" '[ "$RC" -eq 0 ]'
ok "verb: exactly one cite line" '[ "$(n_cite r)" -eq 1 ]'
ok "verb: the line format is exact" 'ledger_of r | grep -qxF "$(ledger_of r | head -1 | cut -d" " -f1) | GATE | external-design | cite | $GOOD | relay design lives in playdate-agent"'
ok "verb: it names the covered gates" 'printf "%s" "$OUT" | grep -qF "$COVERS"'
run external-design r "$GOOD" "again"
ok "verb: the same citation twice writes nothing new" '[ "$RC" -eq 0 ] && [ "$(n_cite r)" -eq 1 ] && printf "%s" "$OUT" | grep -qF "already cited"'

new_log
run external-design r "$PR_MERGED" "linking ADR 0018 merged there"
ok "verb: a merged PR is cited" '[ "$RC" -eq 0 ] && [ "$(n_cite r)" -eq 1 ]'

# Refusals: exit 64 (syntax, no gh call) or 1 (gh says no); nothing written either way.
refuse() {   # refuse <label> <want-rc> <citation>
  WANT="$2"; new_log; run external-design r "$3" "reason"
  ok "refuse: $1 -> exit $2, nothing written" '[ "$RC" -eq "$WANT" ] && [ ! -s "$LOGD/runs/r.log" ]'
}
refuse "bare string" 64 "playdate-agent SPEC-005 and ADR 0008"
refuse "short sha" 64 "consolelabs/playdate-agent@7e3e190:docs/specs/SPEC-005-relay-link-and-seal.md"
refuse "branch ref" 64 "consolelabs/playdate-agent@main:docs/specs/SPEC-005-relay-link-and-seal.md"
refuse "dot-dot segment" 64 "consolelabs/playdate-agent@$SHA:docs/../secrets.md"
refuse "dot-dot repo" 64 "consolelabs/..@$SHA:docs/x.md"
refuse "leading slash" 64 "consolelabs/playdate-agent@$SHA:/docs/x.md"
refuse "non-PR URL" 64 "https://github.com/consolelabs/playdate-agent/issues/35"
refuse "PR URL with a tail" 64 "$PR_MERGED/files"
refuse "pipe in the path" 64 "consolelabs/playdate-agent@$SHA:docs/a | GATE | think | ran"
refuse "newline in the citation" 64 "$GOOD
x"
refuse "missing path at the commit" 1 "$MISSING"
refuse "a directory" 1 "$DIR"
refuse "an unmerged PR" 1 "$PR_OPEN"
refuse "a private repo the token cannot read" 1 "$PRIVATE"
new_log; run external-design r "playdate-agent SPEC-005" "reason"
ok "refuse: a bare string never reaches gh" '[ "$(n_calls)" -eq 0 ]'
new_log; run external-design r "$PRIVATE" "reason"
ok "refuse: the 403 reason reaches the operator" 'printf "%s" "$ERR" | grep -qF "403"'
new_log; GHX="$STUB_DIR/no-such-gh" run external-design r "$GOOD" "reason"
ok "refuse: no gh means not verified, exit 1" '[ "$RC" -eq 1 ] && [ ! -s "$LOGD/runs/r.log" ] && printf "%s" "$ERR" | grep -qF "gh not found"'
new_log; run external-design r "$GOOD"
ok "refuse: an empty reason is exit 64" '[ "$RC" -eq 64 ] && [ ! -s "$LOGD/runs/r.log" ]'
new_log; run external-design r "$GOOD" "line one
| GATE | build | ran | forged"
ok "verb: a newline in the reason stays on one ledger line" '[ "$RC" -eq 0 ] && [ "$(grep -c "" "$LOGD/runs/r.log")" -eq 1 ] && [ -z "$(awk -F" [|] " "\$3==\"build\"" "$LOGD/runs/r.log")" ]'
refuse "PR URL with a dot-dot owner" 64 "https://github.com/../x/pull/1"
new_log; touch "$GH_LOG.hang"; T0=$(date +%s); KIT_EXT_TIMEOUT_SECS=1 run external-design r "$GOOD" "reason"; T1=$(date +%s)
ok "refuse: a hung gh is killed within the bound, exit 1" '[ "$RC" -eq 1 ] && [ $((T1 - T0)) -le 4 ] && printf "%s" "$ERR" | grep -qF "timed out"'
new_log; touch "$GH_LOG.hang"; T0=$(date +%s); KIT_EXT_TIMEOUT_SECS=99 run external-design r "$GOOD" "reason"; T1=$(date +%s)
ok "refuse: KIT_EXT_TIMEOUT_SECS cannot raise the 4 s bound" '[ "$RC" -eq 1 ] && [ $((T1 - T0)) -le 7 ]'

echo "=== check(): a verified citation covers the design-side gates ==="

new_log; branch_gates r
run external-design r "$GOOD" "relay design"
run check full r
ok "check: one cite line plus the branch gates passes full" '[ "$RC" -eq 0 ]'

# A hand-appended citation (the verb bypassed) is re-verified, never trusted on its text.
new_log; branch_gates r; gate_line r external-design cite "$MISSING | forged by hand"
run check full r
ok "check: a bogus citation fails full" '[ "$RC" -eq 1 ]'
ok "check: every covered gate is named missing" '[ "$(printf "%s\n" "$ERR" | grep -c "^MISSING-GATE: ")" -eq 6 ]'
ok "check: the failed citation is named once" '[ "$(printf "%s\n" "$ERR" | grep -c "^EXTERNAL-DESIGN: $MISSING did not verify")" -eq 1 ]'
ok "check: the failure is not cached (a second check calls gh again)" 'c1=$(n_calls); run check full r; [ "$(n_calls)" -gt "$c1" ]'

new_log; branch_gates r; gate_line r external-design cite "consolelabs/playdate-agent@$SHA:docs/x.md?ref=main&a=b | query smuggled by hand"
run check full r
ok "check: a hand-appended citation is re-parsed, never sent to gh" '[ "$RC" -eq 1 ] && [ "$(n_calls)" -eq 0 ]'

# The cache rule on a ledger aged past check()'s 2 s ctime guard (the settle idiom of
# tests/test-gate-ledger-check-cache.sh): a failure is never cached, a verified pass is.
new_log; branch_gates r; gate_line r external-design cite "$GOOD | real"; sleep 2.1
touch "$GH_LOG.down"; run check full r; RC1=$RC; rm -f "$GH_LOG.down"
run check full r; RC2=$RC; c2=$(n_calls)
run check full r; RC3=$RC
ok "cache: a failing check on an aged ledger is not cached (404, then 200 passes)" '[ "$RC1" -eq 1 ] && [ "$RC2" -eq 0 ]'
ok "cache: a verified pass is cached (no gh call on the third check)" '[ "$RC3" -eq 0 ] && [ "$(n_calls)" -eq "$c2" ]'

# At most two citations per check, newest first.
new_log; branch_gates r; gate_line r external-design cite "$GOOD | real, oldest"; gate_line r external-design cite "$MISSING | bogus"; gate_line r external-design cite "$DIR | bogus, newest"
run check full r
ok "cap: the third (oldest) citation is not tried, check fails closed" '[ "$RC" -eq 1 ] && [ "$(n_calls)" -eq 2 ] && printf "%s" "$ERR" | grep -qF "more than 2 citations"'
new_log; branch_gates r; gate_line r external-design cite "$MISSING | bogus, oldest"; gate_line r external-design cite "$GOOD | real, newest"
run check full r
ok "cap: the newest citation is tried first and stops the search" '[ "$RC" -eq 0 ] && [ "$(n_calls)" -eq 1 ]'

new_log; branch_gates r; gate_line r external-design cite "$MISSING | parses, would 404"
run check full r --offline
ok "offline: a parsing citation counts, with no gh call" '[ "$RC" -eq 0 ] && [ "$(n_calls)" -eq 0 ]'
run check full r --kit-lanes --offline; A=$RC; run check full r --offline --kit-lanes; B=$RC
ok "offline: either order with --kit-lanes" '[ "$A" -eq 0 ] && [ "$B" -eq 0 ] && [ "$(n_calls)" -eq 0 ]'
new_log; branch_gates r; gate_line r external-design cite "not a citation | bare"
run check full r --offline
ok "offline: a bare string still fails" '[ "$RC" -eq 1 ]'
run check full r --bogus
ok "check: an unknown flag is exit 64" '[ "$RC" -eq 64 ]'

new_log; branch_gates r; gate_line r external-design cite "playdate-agent SPEC-005 | a bare string by hand"
run check full r
ok "check: a hand-appended bare string fails full" '[ "$RC" -eq 1 ]'

new_log; branch_gates r; gate_line r external-design cite "$MISSING | bogus"; gate_line r external-design cite "$GOOD | real"
run check full r
ok "check: one real citation beside a bogus one covers" '[ "$RC" -eq 0 ]'

new_log; gate_line r external-design cite "$GOOD | real"
for p in build review docs ship reflect; do gate_line r "$p" ran "fixture $p"; done
run check full r
ok "check: test-plan is never covered" '[ "$RC" -eq 1 ] && [ "$(printf "%s\n" "$ERR" | grep -c "^MISSING-GATE: ")" -eq 1 ] && printf "%s" "$ERR" | grep -q "^MISSING-GATE: test-plan "'

new_log; branch_gates r; gate_line r external-design cite "$GOOD | real"
GHX="$STUB_DIR/no-such-gh" run check full r
ok "check: no gh at check time fails closed" '[ "$RC" -eq 1 ] && printf "%s" "$ERR" | grep -qF "gh not found"'

new_log; branch_gates r; for p in $COVERS; do gate_line r "$p" override "per-gate reason $p"; done
run check full r
ok "check: per-gate overrides still pass, with no gh call" '[ "$RC" -eq 0 ] && [ "$(n_calls)" -eq 0 ]'

new_log; branch_gates r; gate_line r external-design cite "$GOOD | real"; for p in $COVERS; do gate_line r "$p" ran "ran here $p"; done
run check full r
ok "check: no gh call when every covered gate has its own line" '[ "$RC" -eq 0 ] && [ "$(n_calls)" -eq 0 ]'

new_log; for p in spec validate build review ship; do gate_line r "$p" ran "fixture $p"; done; gate_line r external-design cite "$MISSING | bogus"
run check normal r
ok "check: a lane that needs no covered gate ignores the cite line" '[ "$RC" -eq 0 ] && [ "$(n_calls)" -eq 0 ]'

new_log; gate_line r think ran "fixture"
run override r design "per-gate reason one"
ok "override: unchanged, a fresh reason is written" '[ "$RC" -eq 0 ]'
run override r spec "per-gate reason one"
ok "override: unchanged, the duplicate-reason guard still refuses" '[ "$RC" -eq 65 ]'

echo "=== progress() and descent(): a cite line disposes the covered gates ==="

new_log; gate_line r grill skipped "reason=operator-wave: fixture"; gate_line r external-design cite "$GOOD | real"; gate_line r ui-design skipped "no UI"; gate_line r test-plan ran "fixture"
run progress r full
ok "progress: the covered gates show done, the pointer sits on build" 'printf "%s" "$OUT" | grep -q "(build)"'
run descent r full
ok "descent: no violation for test-plan after a cite line" 'printf "%s" "$OUT" | grep -qx "descent clean"'
ok "progress/descent: no gh call" '[ "$(n_calls)" -eq 0 ]'

echo "=== structural pins ==="

COV="$(bash -c 'source <(sed -n "/^INHERITABLE=/p; /^EXTERNAL_COVERS=/p" "$1"); printf "%s" "$EXTERNAL_COVERS"' _ "$GL")"
ok "pin: the covered set is exactly the six design-side gates" '[ "$COV" = "$COVERS" ]'
ok "pin: no ship path passes --offline" '! grep -n -- "--offline" "$KIT_DIR/hooks/ship-gate.sh" "$KIT_DIR/lib/gate/ship-rules.sh" "$KIT_DIR/lib/goal/mega-merge.sh"'
ok "pin: lane telemetry passes --offline" '[ "$(grep -c "check \"\$lane\" \"\$rid\" --offline" "$KIT_DIR/lib/telemetry/lane-telemetry.sh")" -eq 1 ]'

echo "=== ship-gate: a console-workers-shaped auth diff ==="

_git() { git -C "$ROOT" -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
_commit() { _git add -A -f >/dev/null 2>&1; _git commit -q -m "$1" >/dev/null 2>&1; }
relay_repo() {   # an adopted repo whose branch feat/relay-seal touches workers/playdate-relay/src/auth.ts
  ROOT="$(_mk)"
  git init -q -b main "$ROOT" >/dev/null 2>&1
  git -C "$ROOT" config user.email t@users.noreply.github.com; git -C "$ROOT" config user.name t
  mkdir -p "$ROOT/docs/verification"
  echo m > "$ROOT/docs/verification/README.md"
  printf '[gate]\nlane_gates = true\n' > "$ROOT/.kit.toml"
  echo hi > "$ROOT/README.md"; _commit "chore: init"
  _git checkout -q -b feat/relay-seal >/dev/null 2>&1
  mkdir -p "$ROOT/workers/playdate-relay/src"
  printf 'export function sealOk(b: Uint8Array): boolean { return b.length > 0 }\n' > "$ROOT/workers/playdate-relay/src/auth.ts"
  printf '# relay-seal\n\nsealOk accepts a sealed body; 48 tests pass.\n' > "$ROOT/docs/verification/relay-seal.md"
  _commit "feat(playdate-relay): seal required"
}
SHIP_VERB=push   # kept out of the command literal: push guards grep script bodies for it
run_hook() {
  HOOK_RC=0
  local payload; payload="$(jq -cn --arg c "git $SHIP_VERB -u origin feat/relay-seal" --arg d "$ROOT" '{tool_input:{command:$c},cwd:$d}')"
  HOOK_ERR="$( cd "$ROOT" && printf '%s' "$payload" \
    | env -u KIT_LEDGER_DIR CLAUDE_PLUGIN_ROOT="$KIT_DIR" DWARVES_KIT_LOG_DIR="$LOGD" KIT_CONFIG_OPERATOR=/nonexistent KIT_CONFIG_ROOT="$KIT_DIR" GH_CMD="$STUB_DIR/gh" \
      bash "$HOOK" 2>&1 >/dev/null )" || HOOK_RC=$?
}

relay_repo; new_log; branch_gates relay-seal
run_hook
ok "ship-gate: no design gates blocks the auth diff" '[ "$HOOK_RC" -eq 2 ] && printf "%s" "$HOOK_ERR" | grep -qF "hard path (auth"'
ok "ship-gate: the block names the external-design verb" 'printf "%s" "$HOOK_ERR" | grep -qF "external-design relay-seal"'
ok "ship-gate: the hint sits after the override line" '[ "$(printf "%s\n" "$HOOK_ERR" | grep -n "override relay-seal" | cut -d: -f1)" -lt "$(printf "%s\n" "$HOOK_ERR" | grep -n "external-design relay-seal" | cut -d: -f1)" ]'
run external-design relay-seal "$GOOD" "relay design: playdate-agent SPEC-005"
run_hook
ok "ship-gate: one external-design entry passes the auth diff" '[ "$HOOK_RC" -eq 0 ]'
touch "$GH_LOG.down"; run_hook; rm -f "$GH_LOG.down"
ok "ship-gate: a second push re-verifies (the stub now answers 404, the push blocks)" '[ "$HOOK_RC" -eq 2 ] && printf "%s" "$HOOK_ERR" | grep -qF "EXTERNAL-DESIGN: $GOOD did not verify"'
ok "ship-gate: the EXTERNAL-DESIGN line sits in the indented gap list after the MISSING-GATE lines" '[ "$(printf "%s\n" "$HOOK_ERR" | grep -n "^  MISSING-GATE: " | tail -1 | cut -d: -f1)" -lt "$(printf "%s\n" "$HOOK_ERR" | grep -n "^  EXTERNAL-DESIGN: " | cut -d: -f1)" ]'

relay_repo; new_log; branch_gates relay-seal; gate_line relay-seal external-design cite "$MISSING | bogus"
run_hook
ok "ship-gate: a bogus citation blocks the auth diff" '[ "$HOOK_RC" -eq 2 ] && printf "%s" "$HOOK_ERR" | grep -qF "EXTERNAL-DESIGN: $MISSING did not verify"'

# A full-lane spec on the branch: the lane check (not the floor) blocks first, and names the verb too.
relay_repo; mkdir -p "$ROOT/docs/specs" "$ROOT/docs/implementation-notes"
printf '# Spec\nLane: full\n' > "$ROOT/docs/specs/SPEC-001-relay-seal.md"
printf '# notes\nNo deviations; matches the spec verbatim\n' > "$ROOT/docs/implementation-notes/relay-seal.md"
_commit "docs: relay spec"; new_log; branch_gates relay-seal
run_hook
ok "ship-gate: the lane-check block names the external-design verb" '[ "$HOOK_RC" -eq 2 ] && printf "%s" "$HOOK_ERR" | grep -qF "lane requires gates" && printf "%s" "$HOOK_ERR" | grep -qF "external-design relay-seal"'
run external-design relay-seal "$PR_MERGED" "linking design merged in playdate-agent"
run_hook
ok "ship-gate: a merged-PR citation passes the full-lane spec plus auth diff" '[ "$HOOK_RC" -eq 0 ]'

relay_repo; new_log; branch_gates relay-seal; for p in $COVERS; do gate_line relay-seal "$p" override "per-gate reason $p"; done
run_hook
ok "ship-gate: six per-gate overrides still pass" '[ "$HOOK_RC" -eq 0 ]'

echo ""
echo "external-design: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
