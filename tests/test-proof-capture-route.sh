#!/usr/bin/env bash
# test-proof-capture-route.sh -- the kit side of the proof-capture module: how the kit finds it, routes to it
# and survives its absence. The module's own behavior is tested in lib/proof-capture/tests/ (stub browser).
#   R1  the module directory, copied out of any repo, passes its own suite under `env -i`
#   R2  no file outside the module sources a path inside it (the grep can fail: a planted file is found)
#   R3  the delete test: no shim, no module directory, and a near-full copy of the kit without the module
#   R4  the shim lint, and the registry rows
#   R5  end to end in a temp repo with [proof] visual on: capture, proof-asset put, the gate accepts, and blocks
#       once the image is gone
#   R6  the `capture:` lines in the contract output run against stubs, also with [modules] proof_capture = false
#   R7  commands/verify.md tells the reader to look at the image before put (added with the docs task)
# No case starts a real browser or vhs or reaches the network: PROOF_CAPTURE_BROWSER, PROOF_CAPTURE_VHS and
# PROOF_ASSET_CONVERT are stubs everywhere.
# modules under test: lib/proof-capture bin/proof-capture lib/gate/proof-gate.sh lib/config/modules.tsv
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0; total=0
pass(){ total=$((total+1)); echo "PASS $*"; }
fail(){ total=$((total+1)); echo "FAIL $*"; fails=$((fails+1)); }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-pc-route.XXXXXX")" || exit 1
trap 'rm -rf "$TMPD"' EXIT
export GIT_TEMPLATE_DIR="$TMPD/no-git-template"; mkdir -p "$GIT_TEMPLATE_DIR"
export KIT_LEDGER_DIR="$TMPD/ledger"
# Pin every config layer: the operator's real kit.toml must never reach this suite (tests/test-operator-pin.sh).
export KIT_CONFIG_ROOT="$KIT" KIT_CONFIG_OPERATOR="$TMPD/no-operator"
unset DWARVES_KIT PROOF_CAPTURE_BROWSER PROOF_CAPTURE_VHS PROOF_CAPTURE_DEADLINE PROOF_CAPTURE_BROWSER_CANDIDATES

# ---- stubs ---------------------------------------------------------------------------------------
STUBS="$TMPD/stubs"; mkdir -p "$STUBS"
# A PNG-shaped file (real magic, IHDR and IEND trailer) and the smallest GIF.
png_hex="89504e470d0a1a0a0000000d49484452000000010000000108020000009077 53de0000000c4944415408d763f8cfc00000030101 00c9fe92ef0000000049454e44ae426082"
gif_hex="47494638396101000100800000ffffff00000021f90401000000002c00000000010001000002024401003b"
hex_to_file() { local h=${1// /} f=$2 i=0; : >"$f"; while [ "$i" -lt "${#h}" ]; do printf "\\x${h:$i:2}" >>"$f"; i=$((i + 2)); done; }
hex_to_file "$png_hex" "$STUBS/stub.png"
hex_to_file "$gif_hex" "$STUBS/stub.gif"
cat >"$STUBS/browser" <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in --screenshot=*) cp "$STUB_DIR/stub.png" "${a#--screenshot=}" ;; esac; done
exit 0
EOF
cat >"$STUBS/vhs" <<'EOF'
#!/bin/bash
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
cp "$STUB_DIR/stub.gif" "$out"
exit 0
EOF
cat >"$STUBS/convert" <<'EOF'
#!/bin/bash
cp "$1" "$2"
EOF
chmod +x "$STUBS/browser" "$STUBS/vhs" "$STUBS/convert"
export STUB_DIR="$STUBS"

# is_png / is_gif <file>
is_png() { [ "$(od -An -tx1 -N8 "$1" 2>/dev/null | tr -d ' \n')" = 89504e470d0a1a0a ]; }
is_gif() { [ "$(od -An -c -N4 "$1" 2>/dev/null | tr -d ' \n')" = GIF8 ]; }

# proj_tree <name>: a tree the gate's `contract` runs in, modeled on case 22 of the contract suite. The gate file is
# copied (its lib dir is the real path of its own directory, so the file-test guards look at THIS tree); the
# classifier, config and verification registry are linked in. Prints the tree path.
proj_tree() {
  local t="$TMPD/tree-$1"
  mkdir -p "$t/lib/gate" "$t/docs" "$t/bin"
  cp "$KIT/lib/gate/proof-gate.sh" "$KIT/lib/gate/proof-classes.sh" "$KIT/lib/gate/proof-classes.tsv" "$t/lib/gate/"
  ln -sfn "$KIT/lib/classify" "$t/lib/classify"
  ln -sfn "$KIT/lib/config" "$t/lib/config"
  ln -sfn "$KIT/docs/verification" "$t/docs/verification"
  printf '%s\n' "$t"
}
# A project dir whose tracked-or-not .kit.toml turns the visual knob on.
VP="$TMPD/visual-project"; mkdir -p "$VP"; printf '[proof]\nvisual = true\n' >"$VP/.kit.toml"
contract_in() { KIT_PROJECT_ROOT="$VP" bash "$1/lib/gate/proof-gate.sh" contract "$2" 2>&1; }

# ---- R1: the module runs alone -------------------------------------------------------------------
echo "=== R1: the module directory, copied out of any repo, passes its own suite under env -i ==="
T="$(mktemp -d "${TMPDIR:-/tmp}/dk-pc-alone.XXXXXX")"
cp -R "$KIT/lib/proof-capture" "$T/pc"
OUT="$(cd "$T" && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin /bin/bash "$T/pc/tests/test-proof-capture.sh" 2>&1)"; rc=$?
RECAP="$(printf '%s\n' "$OUT" | tail -n 1)"
if [ "$rc" = 0 ] && printf '%s' "$RECAP" | grep -q ' 0 failed'; then pass "R1: standalone suite passes ($RECAP)"; else fail "R1: standalone suite failed (rc=$rc): $(printf '%s\n' "$OUT" | grep -E '^FAIL|failed' | head -5)"; fi

# ---- R2: no inbound source ------------------------------------------------------------------------
echo "=== R2: nothing outside the module sources a path inside it ==="
# The same grep as the spec's Verification block. The planted text is built from variables so this file's own text
# never matches it.
INBOUND='(^|[;&|[:space:]])(source|[.])[[:space:]]+[^#]*proof-capture/'
HITS="$(cd "$KIT" && git grep --no-index --exclude-standard -nE "$INBOUND" -- . ':!lib/proof-capture' ':!docs' ':!*.md' ':!tests/test-proof-capture-route.sh' 2>/dev/null || true)"
[ -z "$HITS" ] && pass "R2: no kit file sources a proof-capture path" || fail "R2: inbound source found: $HITS"
PL="$TMPD/planted"; mkdir -p "$PL/lib/other"
w1="sour"; w2="ce"; p1="lib/proof-captu"; p2="re/bin/proof-capture"
printf '%s%s %s%s\n' "$w1" "$w2" "$p1" "$p2" >"$PL/lib/other/planted.sh"
HITS="$(cd "$PL" && git grep --no-index --exclude-standard -nE "$INBOUND" -- . ':!lib/proof-capture' ':!docs' ':!*.md' 2>/dev/null || true)"
[ -n "$HITS" ] && pass "R2: the grep finds a planted untracked source line" || fail "R2: the grep missed a planted line"

# ---- R3: the delete test --------------------------------------------------------------------------
echo "=== R3: the kit survives the tool's absence ==="
WANT_VIS="visual: before + after screenshots, desktop and 400px"
# a control: shim and module both present -> the capture: line is there
T3="$(proj_tree full)"
cp "$KIT/bin/proof-capture" "$T3/bin/proof-capture"; chmod +x "$T3/bin/proof-capture"
mkdir -p "$T3/lib/proof-capture/bin"; ln -sfn "$KIT/lib/proof-capture/bin/proof-capture" "$T3/lib/proof-capture/bin/proof-capture"
OUT="$(contract_in "$T3" "redesign the settings page UI")"
printf '%s\n' "$OUT" | grep -q '^capture: ' && pass "R3: control, shim and module present: a capture: line prints" || fail "R3: control lost its capture: line"
# (b) no shim, module present
T3b="$(proj_tree noshim)"
mkdir -p "$T3b/lib/proof-capture/bin"; ln -sfn "$KIT/lib/proof-capture/bin/proof-capture" "$T3b/lib/proof-capture/bin/proof-capture"
OUT="$(contract_in "$T3b" "redesign the settings page UI")"; rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$OUT" | grep -qxF "$WANT_VIS" ; then pass "R3b: no shim: contract exits 0 with the same visual: line"; else fail "R3b: no shim: rc=$rc, visual line missing"; fi
printf '%s\n' "$OUT" | grep -q '^capture:' && fail "R3b: no shim, yet a capture: line printed" || pass "R3b: no shim: no capture: line"
# (b') shim present, module directory gone
T3c="$(proj_tree nomodule)"
cp "$KIT/bin/proof-capture" "$T3c/bin/proof-capture"; chmod +x "$T3c/bin/proof-capture"
OUT="$(contract_in "$T3c" "redesign the settings page UI")"; rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$OUT" | grep -qxF "$WANT_VIS"; then pass "R3b: shim without a module: contract exits 0 with the same visual: line"; else fail "R3b: shim without a module: rc=$rc"; fi
printf '%s\n' "$OUT" | grep -q '^capture:' && fail "R3b: shim without a module, yet a capture: line printed" || pass "R3b: shim without a module: no capture: line"
# (c) a near-full copy of the kit without lib/proof-capture
CP="$TMPD/kit-copy"; mkdir -p "$CP"
( cd "$KIT" && tar --exclude=./.git --exclude=./lib/proof-capture -cf - . ) | ( cd "$CP" && tar -xf - )
[ ! -e "$CP/lib/proof-capture" ] && [ -x "$CP/bin/proof-capture" ] && pass "R3c: the copy has the shim and no module directory" || fail "R3c: the copy is not the intended shape"
OUT="$(cd "$TMPD" && "$CP/bin/proof-capture" run page x y 2>&1)"; rc=$?
[ "$rc" = 69 ] && printf '%s' "$OUT" | grep -q 'proof-capture: module files missing: ' && pass "R3c: the shim prints the missing-files line and exits 69" || fail "R3c: shim without a module: rc=$rc out=[$OUT]"
OUT="$(KIT_PROJECT_ROOT="$VP" bash "$CP/lib/gate/proof-gate.sh" contract "redesign the settings page UI" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$OUT" | grep -qxF "$WANT_VIS" && ! printf '%s\n' "$OUT" | grep -q '^capture:'; then pass "R3c: the copy's contract exits 0, same visual: line, no capture: line"; else fail "R3c: the copy's contract: rc=$rc"; fi
for s in test-modules-table test-bin-forwarders; do
  O="$TMPD/r3c-$s.out"
  ( cd "$CP" && bash "tests/$s.sh" >"$O" 2>&1 ); rc=$?
  [ "$rc" = 0 ] && pass "R3c: $s passes in the copy" || fail "R3c: $s fails in the copy (rc=$rc): $(grep -iE 'FAIL' "$O" | head -3)"
done

# ---- R4: the shim lint and the registry ---------------------------------------------------------------
echo "=== R4: the shim is thin; the module is registered ==="
# shim_lint <file>: at most 6 non-comment non-blank lines (the shebang counts), exactly one line starts with exec,
# none of the forbidden tokens, and "$@" only on the exec line.
shim_lint() {
  local f=$1 body n ex
  body="$(grep -v '^[[:space:]]*$' "$f" | grep -v '^[[:space:]]*#[^!]')"
  n="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  [ "$n" -le 6 ] || return 1
  ex="$(printf '%s\n' "$body" | grep -c '^exec ')"
  [ "$ex" = 1 ] || return 1
  if printf '%s\n' "$body" | grep -qE 'case |if |while |for |shift|getopts|[$]1|[$]#'; then return 1; fi
  [ "$(printf '%s\n' "$body" | grep -c '"[$]@"')" = 1 ] && printf '%s\n' "$body" | grep '"[$]@"' | grep -q '^exec ' || return 1
  return 0
}
shim_lint "$KIT/bin/proof-capture" && pass "R4: the shim passes the lint" || fail "R4: the shim fails the lint"
BAD="$TMPD/bad-shim"; cp "$KIT/bin/proof-capture" "$BAD"; printf 'if [ -z "${X:-}" ]; then :; fi\n' >>"$BAD"
shim_lint "$BAD" && fail "R4: the lint missed a planted if" || pass "R4: the lint fails a shim with an added if"
BAD2="$TMPD/bad-shim2"; cp "$KIT/bin/proof-capture" "$BAD2"; printf 'echo "$@" >/dev/null\n' >>"$BAD2"
shim_lint "$BAD2" && fail "R4: the lint missed a planted extra use of the arguments" || pass "R4: the lint fails a shim that uses the arguments off the exec line"
[ -x "$KIT/bin/proof-capture" ] && pass "R4: the shim is executable" || fail "R4: the shim is not executable"
awk -F'\t' '$1=="proof_capture" && $2=="opt-in" && $3=="-" && $4=="proof-capture" {f=1} END{exit !f}' "$KIT/lib/config/modules.tsv" \
  && pass "R4: modules.tsv has proof_capture, opt-in, no hooks, the proof-capture CLI" || fail "R4: the modules.tsv row is wrong"
grep -qE '^proof_capture +=  *false' "$KIT/kit.toml" && pass "R4: kit.toml has proof_capture = false" || fail "R4: kit.toml key missing or on"
grep -q '^| proof_capture | Build (Execute) |' "$KIT/lib/config/module-registry.md" && grep -q 'modules.proof_capture' "$KIT/lib/config/module-registry.md" \
  && pass "R4: the registry has the stage row and the key row" || fail "R4: registry rows missing"

# ---- R5: end to end -----------------------------------------------------------------------------------
echo "=== R5: capture, put, and the gate in a hermetic repo with the visual knob on ==="
D="$TMPD/e2e"; mkdir -p "$D/docs/verification" "$D/lib" "$D/app"
git -C "$D" init -q; git -C "$D" config user.email t@t; git -C "$D" config user.name t; git -C "$D" config commit.gpgsign false
git -C "$D" remote add origin git@github.com:acme/widget.git
echo "# Verification log (proof of done)" >"$D/docs/verification/README.md"; echo baseline >"$D/lib/thing.sh"
printf '[proof]\nvisual = true\nassets = "local"\n' >"$D/.kit.toml"
git -C "$D" add -A; git -C "$D" commit -qm base
echo "export default function P() {}" >"$D/app/page.tsx"
SHOT="$D/shot.png"
PROOF_CAPTURE_BROWSER="$STUBS/browser" bash "$KIT/bin/proof-capture" run page "$KIT/lib/proof-capture/examples/hello.html" "$SHOT" --width 800 --height 500 >"$TMPD/r5-cap.out" 2>&1; rc=$?
[ "$rc" = 0 ] && is_png "$SHOT" && pass "R5: the capture wrote a PNG ($(cat "$TMPD/r5-cap.out" | sed "s|$D|<repo>|g"))" || fail "R5: the capture failed (rc=$rc): $(cat "$TMPD/r5-cap.out")"
EMBED="$(cd "$D" && PROOF_ASSET_CONVERT="$STUBS/convert" bash "$KIT/bin/proof-asset" put ui "$SHOT" --name shot 2>"$TMPD/r5-put.err")"; rc=$?
[ "$rc" = 0 ] && [ -n "$EMBED" ] && pass "R5: proof-asset put took the capture ($EMBED)" || fail "R5: proof-asset put failed (rc=$rc): $(cat "$TMPD/r5-put.err")"
{ echo "# Verification"; echo "## NEGATIVE CONTROL"; echo "reverting the change turns this RED."
  echo "Command: \`bash lib/thing.sh\`"; echo "Exit: 0"; echo "Output:"; echo "test-thing: all 3 passed"; echo "Verdict: PASS"
  printf '%s\n' "$EMBED"; } >"$D/docs/verification/vf.md"
GATE_OUT="$(bash "$KIT/lib/gate/proof-ledger.sh" check "$D" "$(git -C "$D" rev-parse HEAD)" vf 2>&1)"; rc=$?
[ "$rc" = 0 ] && pass "R5: the gate accepts the proof with the captured image" || fail "R5: the gate blocked: $GATE_OUT"
# the control: the image is gone, the same proof is blocked with the visual message
mkdir "$D/.kit/image-gone"; mv "$D"/.kit/proof-assets/ui/*.png "$D/.kit/image-gone/"
GATE_OUT="$(bash "$KIT/lib/gate/proof-ledger.sh" check "$D" "$(git -C "$D" rev-parse HEAD)" vf 2>&1)"; rc=$?
if [ "$rc" != 0 ] && printf '%s' "$GATE_OUT" | grep -q 'visual proof of done'; then pass "R5: without the image the gate blocks with the visual message"; else fail "R5: the gate did not block (rc=$rc): $GATE_OUT"; fi

# ---- R6: the contract's capture lines run -------------------------------------------------------------
echo "=== R6: the capture: lines, taken from the contract output, run against the stubs ==="
# run_capture_line <tree> <task> <module-toggle> <expected kind>: take the capture: line, put the tree where
# $DWARVES_KIT stands, fill the placeholders and run the argv against the stubs.
run_capture_line() {
  local tree=$1 task=$2 toggle=$3 kind=$4 proj out line cmd w outfile rc valid
  proj="$TMPD/r6-$toggle"; mkdir -p "$proj"
  printf '[proof]\nvisual = true\n[modules]\nproof_capture = %s\n' "$toggle" >"$proj/.kit.toml"
  out="$(KIT_PROJECT_ROOT="$proj" bash "$tree/lib/gate/proof-gate.sh" contract "$task" 2>&1)"
  line="$(printf '%s\n' "$out" | grep '^capture: ' | head -n 1)"
  [ -n "$line" ] || { fail "R6: [$task] toggle $toggle: no capture: line"; return; }
  cmd="${line#capture: }"; cmd="${cmd%% (then*}"
  outfile="$TMPD/r6-out-$toggle-$kind"
  set --
  for w in $cmd; do
    case "$w" in
      '$DWARVES_KIT/bin/proof-capture') w="$tree/bin/proof-capture" ;;
      '<page.html|url>') w="$KIT/lib/proof-capture/examples/hello.html" ;;
      '<demo.tape>') w="$KIT/lib/proof-capture/examples/hello.tape" ;;
      '<out.png>'|'<out.gif>') w="$outfile.$([ "$kind" = page ] && echo png || echo gif)" ;;
    esac
    set -- "$@" "$w"
  done
  ( export PROOF_CAPTURE_BROWSER="$STUBS/browser" PROOF_CAPTURE_VHS="$STUBS/vhs"; "$@" >"$TMPD/r6.out" 2>&1 ); rc=$?
  valid=0
  if [ "$kind" = page ]; then is_png "$outfile.png" && valid=1; else is_gif "$outfile.gif" && valid=1; fi
  if [ "$rc" = 0 ] && [ "$valid" = 1 ]; then
    pass "R6: [$kind] toggle $toggle: the contract's own line runs and writes a valid file"
  else
    fail "R6: [$kind] toggle $toggle: rc=$rc cmd=[$cmd] out=[$(cat "$TMPD/r6.out")]"
  fi
}
# a tree the shim resolves in: the real kit's bin/ and lib/ sit together, so the real tree is the tree under test
for toggle in true false; do
  run_capture_line "$KIT" "redesign the settings page UI" "$toggle" page
  run_capture_line "$KIT" "record a vhs demo of the tui" "$toggle" tape
done

[ "$fails" -eq 0 ] && { echo "ALL PASS ($total/$total)"; exit 0; } || { echo "$fails/$total FAILED"; exit 1; }
