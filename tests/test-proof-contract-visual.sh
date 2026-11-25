#!/usr/bin/env bash
# test-proof-contract-visual.sh
# The opt-in visual contract (SPEC-385, R9 + R10): `proof-gate.sh contract` adds one
# `visual:` line naming the artifact the task owes, but only when [proof] visual
# resolves true; commands/verify.md carries the matching capture step. Guards:
#   case 21  visual on, contract "redesign the settings page UI"
#              -> a `visual:` line naming desktop and 400px screenshots
#   (extra)  visual on, a task no keyword row matches -> `visual: none`
#   case 22  visual off (project key false, and no .kit.toml at all)
#              -> `contract` output byte-identical to origin/master's
#   R10      commands/verify.md gates a capture step on `proof.visual` and points
#            every image at `bin/proof-asset put`
#   capture  visual on: a ui page task gets a `capture:` line naming `bin/proof-capture run page`, a
#            tui task `run tape`, every other row none; the `visual:` text is unchanged; the other verbs
#            (class, requirement, skeleton) print what master's gate printed
# modules under test: lib/gate/proof-gate.sh commands/verify.md
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$KIT/lib/gate/proof-gate.sh"
fails=0; total=0
pass(){ total=$((total+1)); echo "PASS $*"; }
fail(){ total=$((total+1)); echo "FAIL $*"; fails=$((fails+1)); }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-vp-contract.XXXXXX")" || exit 1
trap 'rm -rf "$TMPD"' EXIT

# Pin every config layer: the operator's real ~/.config/dwarves-kit/kit.toml and the
# installed kit-root kit.toml must never leak a proof.visual value into this suite.
export KIT_CONFIG_ROOT="$TMPD/kit-root" KIT_CONFIG_OPERATOR="$TMPD/no-operator"
mkdir -p "$KIT_CONFIG_ROOT"
printf '[proof]\nvisual = false\n' > "$KIT_CONFIG_ROOT/kit.toml"

# proj <name> <true|false|absent> -- a fake project dir; "absent" writes no .kit.toml.
proj() {
  local d="$TMPD/$1"
  mkdir -p "$d"
  [ "$2" = absent ] || printf '[proof]\nvisual = %s\n' "$2" > "$d/.kit.toml"
  printf '%s\n' "$d"
}
contract() { KIT_PROJECT_ROOT="$1" bash "$GATE" contract "$2"; }

echo "=== case 21: visual on, a ui task names its artifact ==="
D="$(proj on true)"
OUT="$(contract "$D" "redesign the settings page UI")"
VLINE="$(printf '%s\n' "$OUT" | grep '^visual:' || true)"
if printf '%s' "$VLINE" | grep -qi 'screenshot' \
   && printf '%s' "$VLINE" | grep -q 'desktop' \
   && printf '%s' "$VLINE" | grep -q '400px'; then
  pass "visual: line names desktop and 400px screenshots ($VLINE)"
else
  fail "want a visual: line naming desktop and 400px screenshots, got [$VLINE]"
fi

echo "=== extra: visual on, a non-visual task -> visual: none ==="
OUT="$(contract "$D" "extract the ledger rollups into a shared helper")"
VLINE="$(printf '%s\n' "$OUT" | grep '^visual:' || true)"
[ "$VLINE" = "visual: none" ] \
  && pass "non-visual task gets visual: none" \
  || fail "want 'visual: none', got [$VLINE]"

echo "=== capture: visual on, the producer is named for a ui page and a tui, and for nothing else ==="
D="$(proj on true)"
OUT="$(contract "$D" "redesign the settings page UI")"
CLINE="$(printf '%s\n' "$OUT" | grep '^capture:' || true)"
VLINE="$(printf '%s\n' "$OUT" | grep '^visual:' || true)"
printf '%s' "$CLINE" | grep -qF '$DWARVES_KIT/bin/proof-capture run page' \
  && pass "ui page: capture: line names run page ($CLINE)" \
  || fail "ui page: want a capture: line with run page, got [$CLINE]"
[ "$VLINE" = "visual: before + after screenshots, desktop and 400px" ] \
  && pass "ui page: the visual: line text is unchanged" \
  || fail "ui page: the visual: line changed: [$VLINE]"
[ "$(printf '%s\n' "$OUT" | grep -n '^visual:' | cut -d: -f1)" = "$(( $(printf '%s\n' "$OUT" | grep -n '^capture:' | cut -d: -f1) - 1 ))" ] \
  && pass "the capture: line follows the visual: line" \
  || fail "the capture: line is not right after the visual: line"
OUT="$(contract "$D" "record a vhs demo of the tui")"
printf '%s\n' "$OUT" | grep '^capture:' | grep -qF 'bin/proof-capture run tape' \
  && pass "tui: capture: line names run tape" \
  || fail "tui: want a capture: line with run tape, got [$(printf '%s\n' "$OUT" | grep '^capture:' || true)]"
for t in "post the bot message in a test channel" "build the onboarding flow" "render the weekly report" "extract the ledger rollups into a shared helper"; do
  OUT="$(contract "$D" "$t")"
  if printf '%s\n' "$OUT" | grep -q '^capture:'; then fail "no verb for [$t], but a capture: line printed"; else pass "no capture: line for [$t]"; fi
done

echo "=== the other verbs print what master printed, knob on and off ==="
MST2="$TMPD/master2"; mkdir -p "$MST2/lib/gate" "$MST2/docs"
git -C "$KIT" show origin/master:lib/gate/proof-gate.sh > "$MST2/lib/gate/proof-gate.sh"
for f in proof-classes.sh proof-classes.tsv; do git -C "$KIT" show "origin/master:lib/gate/$f" > "$MST2/lib/gate/$f" || exit 1; done
ln -sfn "$KIT/lib/classify" "$MST2/lib/classify"; ln -sfn "$KIT/lib/config" "$MST2/lib/config"; ln -sfn "$KIT/docs/verification" "$MST2/docs/verification"
same=1
for state in true false; do
  D="$(proj verbs-$state $state)"
  for t in "redesign the settings page UI" "record a vhs demo of the tui" "post the bot message in a test channel" "add a --verbose flag to the stats command"; do
    for verb in class requirement; do
      a="$(KIT_PROJECT_ROOT="$D" bash "$GATE" "$verb" "$t" 2>&1; echo "rc=$?")"
      b="$(KIT_PROJECT_ROOT="$D" bash "$MST2/lib/gate/proof-gate.sh" "$verb" "$t" 2>&1; echo "rc=$?")"
      [ "$a" = "$b" ] || { same=0; echo "  drift: $verb [$t] knob $state"; }
    done
    a="$(KIT_PROJECT_ROOT="$D" bash "$GATE" skeleton some-slug "$t" 2>&1; echo "rc=$?")"
    b="$(KIT_PROJECT_ROOT="$D" bash "$MST2/lib/gate/proof-gate.sh" skeleton some-slug "$t" 2>&1; echo "rc=$?")"
    [ "$a" = "$b" ] || { same=0; echo "  drift: skeleton [$t] knob $state"; }
  done
done
[ "$same" = 1 ] && pass "class, requirement and skeleton print the same bytes as master (4 tasks, knob on and off)" || fail "a verb drifted from master"

echo "=== case 22: visual off, byte-identical to origin/master ==="
# Master's gate file, run against THIS tree's classify libs and task-type registry
# (none of which this change touches), so any output delta is the gate file alone.
MST="$TMPD/master"; mkdir -p "$MST/lib/gate" "$MST/docs"
git -C "$KIT" show origin/master:lib/gate/proof-gate.sh > "$MST/lib/gate/proof-gate.sh"
# The gate sources its class table from its own directory, so master's copy needs master's table too.
for f in proof-classes.sh proof-classes.tsv; do
  git -C "$KIT" show "origin/master:lib/gate/$f" > "$MST/lib/gate/$f" || exit 1
done
ln -sfn "$KIT/lib/classify" "$MST/lib/classify"
ln -sfn "$KIT/lib/config"   "$MST/lib/config"
ln -sfn "$KIT/docs/verification" "$MST/docs/verification"
mcontract() { KIT_PROJECT_ROOT="$1" bash "$MST/lib/gate/proof-gate.sh" contract "$2"; }

D="$(proj off false)"
CUR="$(contract "$D" "redesign the settings page UI")"
OLD="$(mcontract "$D" "redesign the settings page UI")"
[ "$CUR" = "$OLD" ] \
  && pass "project visual=false: contract output identical to master" \
  || fail "project visual=false: output drifted from master"

D="$(proj absent absent)"
CUR="$(contract "$D" "add a --verbose flag to the stats command")"
OLD="$(mcontract "$D" "add a --verbose flag to the stats command")"
[ "$CUR" = "$OLD" ] \
  && pass "no .kit.toml at all: contract output identical to master" \
  || fail "no .kit.toml at all: output drifted from master"

echo "=== R10: commands/verify.md carries the opt-in capture step ==="
VF="$KIT/commands/verify.md"
if grep -q 'proof\.visual' "$VF" && grep -q 'bin/proof-asset put' "$VF"; then
  pass "verify.md gates the capture step on proof.visual and points at bin/proof-asset put"
else
  fail "verify.md lost the proof.visual-gated capture step"
fi

[ "$fails" -eq 0 ] && { echo "ALL PASS ($total/$total)"; exit 0; } || { echo "$fails/$total FAILED"; exit 1; }
