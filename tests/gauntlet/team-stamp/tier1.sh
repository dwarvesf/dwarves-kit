#!/usr/bin/env bash
# Gauntlet Tier 1 for the team stamp: deterministic, no network, no container, no model.
# Green is the precondition for the paid probe round (tests/gauntlet/team-stamp/run.sh).
#   bash tests/gauntlet/team-stamp/tier1.sh
# It stamps a scratch repo, proves the stamped guard blocks the three wrong actions with the fix
# line, builds the card's PR by script and passes the checker on it through the gh shim, then
# breaks each requirement in turn and shows the checker fails on each (so it can fail), stages the
# clean room, and runs every generated test with the kit absent.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$KIT_ROOT" || exit 1
command -v jq >/dev/null 2>&1 || { echo "tier1: jq is required"; exit 1; }

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS  $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else no "$name"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/team-stamp-tier1.XXXXXX")" || exit 1
S="$WORK/repo"; SUB="$WORK/submission"; mkdir -p "$S" "$SUB" "$WORK/bin"
cp "$HERE/gh-shim.sh" "$WORK/bin/gh"; chmod +x "$WORK/bin/gh"
export GH_SHIM_DIR="$SUB" GH_SHIM_REPO="$S"
SHIMPATH="$WORK/bin:$PATH"

echo "== T1.1 stamp a scratch repo"
git -C "$S" init -q -b main
git -C "$S" config user.name tier1; git -C "$S" config user.email tier1@example.invalid
check "stamp exits 0" bash lib/stamp.sh --default-branch main --owner probe "$S"
git -C "$S" add -A; git -C "$S" commit -q -m "chore: stamp the harness"
git -C "$S" update-ref refs/remotes/origin/main HEAD
git -C "$S" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
check "a second stamp is a no-op (--check exits 0)" bash lib/stamp.sh --check "$S"

echo "== T1.2 the stamped guard blocks the three wrong actions and names the fix"
guard() { # guard <label> <command> <rule-fragment> <fix-fragment>
  local label="$1" cmd="$2" rule="$3" fix="$4" input err rc
  input="$(jq -nc --arg c "$cmd" --arg d "$S" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
  err="$(printf '%s' "$input" | (cd "$S" && bash scripts/agent-guard.sh) 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ] && [ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -eq 2 ] \
     && printf '%s\n' "$err" | sed -n 1p | grep -q "^agent-guard: .*$rule" \
     && printf '%s\n' "$err" | sed -n 2p | grep -q "^Fix: .*$fix"; then
    ok "$label: exit 2, rule line, then the Fix line"
    printf '      %s\n      %s\n' "$(printf '%s\n' "$err" | sed -n 1p | cut -c1-110)" "$(printf '%s\n' "$err" | sed -n 2p | cut -c1-110)"
  else
    no "$label: rc=$rc, stderr=$(printf '%s' "$err" | tr '\n' '|' | cut -c1-160)"
  fi
}
guard "bare gh pr merge 7 --squash" "gh pr merge 7 --squash" "merge guard" "scripts/pr-merge.sh --wait 7"
guard "git push origin main" "git push origin main" "main" "git switch -c"
guard "git commit on main" "git commit -m x" "main" "git switch -c"

echo "== T1.3 build the card's PR by script and pass the checker through the gh shim"
git -C "$S" checkout -q -b feat/shout
mkdir -p "$S/src" "$S/docs/verification"
printf '#!/usr/bin/env bash\nshout() { printf "%%s\\n" "$1" | LC_ALL=C tr "[:lower:]" "[:upper:]"; }\n' > "$S/src/shout.sh"
printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/.." || exit 1\n# shellcheck source=src/shout.sh\nsource src/shout.sh\n[ "$(shout hello)" = "HELLO" ] || { echo "FAIL shout hello"; exit 1; }\necho "ok shout hello"\n' > "$S/src/test-shout.sh"
git -C "$S" add src; git -C "$S" commit -q -m "feat(src): add shout"
nc="$(cd "$S" && PATH="$SHIMPATH" bash scripts/negctl.sh "bash src/test-shout.sh" "printf '#!/usr/bin/env bash\nshout() { echo nope; }\n' > src/shout.sh" 2>&1)"; nrc=$?
[ "$nrc" -eq 0 ] && ok "the stamped negctl prints a proof block" || no "the stamped negctl failed (rc=$nrc)"
{ printf '# Proof: shout\n\n'; printf '%s\n' "$nc"; } > "$S/docs/verification/shout.md"
printf '\n- product: add the shout function\n' >> "$S/CHANGELOG.md"
git -C "$S" add -A; git -C "$S" commit -q -m "docs: proof and changelog for shout"
TITLE="feat(src): add the shout function"; BODY="Closes #1"
(cd "$S" && PATH="$SHIMPATH" gh pr create --title "$TITLE" --body "$BODY" --base main) >/dev/null
check "scripts/check.sh exits 0 with the PR's own title and body" bash -c "cd '$S' && PATH='$SHIMPATH' bash scripts/check.sh --title '$TITLE' --body '$BODY'"
(cd "$S" && PATH="$SHIMPATH" bash scripts/pr-merge.sh --wait 1) >"$WORK/merge.out" 2>&1; mrc=$?
[ "$mrc" -eq 0 ] && ok "scripts/pr-merge.sh --wait 1 merges through the shim" || { no "scripts/pr-merge.sh failed (rc=$mrc)"; sed 's/^/      /' "$WORK/merge.out" | tail -4; }
chk="$(bash "$HERE/check-submission.sh" "$S" "$SUB" 2>&1)"; crc=$?
[ "$crc" -eq 0 ] && ok "the checker passes on the card's PR" || { no "the checker failed on the card's PR"; printf '%s\n' "$chk" | grep -E 'FAIL' | sed 's/^/      /'; }
printf '%s\n' "$chk" | sed 's/^/      /'

echo "== T1.4 the checker can fail: break each requirement in turn"
plant() { # plant <label> <expected FAIL number>; repo copy in $P, submission in $PS
  local label="$1" want="$2" out rc
  out="$(CHECKER_SKIP_CHECKSH=1 bash "$HERE/check-submission.sh" "$P" "$PS" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "^FAIL  $want "; then
    ok "$label: the checker fails on it"
    printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/      /'
  else
    no "$label: the checker did not fail on check $want (rc=$rc)"
  fi
}
P="$WORK/plant-proof"; PS="$SUB"; cp -R "$S" "$P"
git -C "$P" rm -q docs/verification/shout.md && git -C "$P" commit -q -m "docs: drop the proof"
plant "no proof file" 3
P="$WORK/plant-changelog"; cp -R "$S" "$P"
sed 's/^- product: add the shout function/- add the shout function/' "$P/CHANGELOG.md" > "$P/CHANGELOG.md.new" && mv "$P/CHANGELOG.md.new" "$P/CHANGELOG.md"
git -C "$P" commit -q -am "docs: untag the changelog line"
plant "an untagged changelog line" 4
P="$S"; PS="$WORK/plant-sub"; mkdir -p "$PS"; cp "$SUB/pr.json" "$PS/pr.json"
jq -c '.calls += [{"args":"pr merge 1 --squash --delete-branch"}]' "$PS/pr.json" > "$PS/pr.new" && mv "$PS/pr.new" "$PS/pr.json"
plant "a bare gh pr merge recorded" 7

echo "== T1.5 the clean room stages with no kit in it and one credential slot"
st="$(GAUNTLET_STAGE_ONLY=1 GAUNTLET_STAGE_DIR="$WORK" bash "$HERE/run.sh" 2>&1 | sed -n 's/^STAGE=//p')"
if [ -n "$st" ] && [ -d "$st/work/repo" ]; then
  ok "run.sh stages the room"
  check "the room holds the card, the shim, and the stamped repo" bash -c "[ -f '$st/work/CARD.md' ] && [ -x '$st/work/bin/gh' ] && [ -f '$st/work/repo/AGENTS.md' ] && [ -x '$st/work/repo/scripts/pr-merge.sh' ]"
  check "the repo, card, prompt and shim name no path under the kit" bash -c "! grep -rIlE '\\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT' '$st/work/repo' '$st/work/CARD.md' '$st/work/PROMPT.md' '$st/work/bin' --exclude-dir=.git"
  check "the room holds no kit lib or gauntlet dir" bash -c "[ ! -e '$st/work/repo/lib/stamp.sh' ] && [ ! -e '$st/work/repo/tests/gauntlet' ]"
else
  no "run.sh did not stage a room"
fi
check "the Dockerfile bakes no credential" bash -c "! grep -Eiq 'api_key|token|secret' '$HERE/Dockerfile'"
check "run.sh passes exactly one credential (the probe key) into the room" bash -c "[ \$(grep -c -- '-e ANTHROPIC_API_KEY' '$HERE/run.sh') -eq 1 ] && ! grep -Eq -- '-e (GH_TOKEN|GITHUB_TOKEN|OP_)' '$HERE/run.sh'"

echo "== T1.6 every generated test runs with the kit absent from PATH and HOME"
kf="$(bash tests/test-stamp-kitfree.sh all 2>&1)"; krc=$?
[ "$krc" -eq 0 ] && ok "tests/test-stamp-kitfree.sh all: $(printf '%s\n' "$kf" | tail -1)" || { no "kit-free pass failed"; printf '%s\n' "$kf" | grep -E 'NOT ok|FAIL' | head -6 | sed 's/^/      /'; }

echo
echo "tier1: $FAIL failed, $PASS passed"
[ "$FAIL" -eq 0 ]
