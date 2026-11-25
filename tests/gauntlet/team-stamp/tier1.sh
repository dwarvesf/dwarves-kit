#!/usr/bin/env bash
# Gauntlet Tier 1 for the team stamp: deterministic, no network, no container, no model.
# Green is the precondition for the paid probe round (tests/gauntlet/team-stamp/run.sh).
#   bash tests/gauntlet/team-stamp/tier1.sh
#
# Why this runs on the host. Every repository and file below is written by this script itself, so no
# untrusted text reaches the host. A real probe round is different: the probe's repository is never
# opened on the host, and check-submission.sh reads only a bundle made inside the room (see the header
# of check-submission.sh). Tier 1 sends its own scripted work through that same hardened checker, and
# plants hostile repositories to show the hardening holds.
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
# a bundle of a repository this script made, taken with every repo-level hook and config disabled
mkbundle() { git -C "$1" -c core.fsmonitor= -c core.hooksPath=/dev/null -c diff.external= bundle create "$2" --all >/dev/null 2>&1; }

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
BASE="$(git -C "$S" rev-parse origin/main)"
mkbundle "$S" "$WORK/ok.bundle"
chk="$(bash "$HERE/check-submission.sh" "$WORK/ok.bundle" "$SUB" "$BASE" 2>&1)"; crc=$?
[ "$crc" -eq 0 ] && ok "the checker passes on the card's PR" || { no "the checker failed on the card's PR"; printf '%s\n' "$chk" | grep -E 'FAIL' | sed 's/^/      /'; }
printf '%s\n' "$chk" | sed 's/^/      /'

echo "== T1.4 the checker can fail: break each requirement in turn"
plant() { # plant <label> <expected FAIL number> <repo dir> <submission dir>
  local label="$1" want="$2" out rc
  mkbundle "$3" "$WORK/plant.bundle"
  out="$(CHECKER_SKIP_CHECKSH=1 bash "$HERE/check-submission.sh" "$WORK/plant.bundle" "$4" "$BASE" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "^FAIL  $want "; then
    ok "$label: the checker fails on it"
    printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/      /'
  else
    no "$label: the checker did not fail on check $want (rc=$rc)"
  fi
}
Q="$WORK/plant-proof"; cp -R "$S" "$Q"
git -C "$Q" rm -q docs/verification/shout.md && git -C "$Q" commit -q -m "docs: drop the proof"
plant "no proof file" 3 "$Q" "$SUB"
Q="$WORK/plant-changelog"; cp -R "$S" "$Q"
sed 's/^- product: add the shout function/- add the shout function/' "$Q/CHANGELOG.md" > "$Q/CHANGELOG.md.new" && mv "$Q/CHANGELOG.md.new" "$Q/CHANGELOG.md"
git -C "$Q" commit -q -am "docs: untag the changelog line"
plant "an untagged changelog line" 4 "$Q" "$SUB"
PS="$WORK/plant-sub"; mkdir -p "$PS"; cp "$SUB/pr.json" "$PS/pr.json"
jq -c '.calls += [{"args":"pr merge 1 --squash --delete-branch"}]' "$PS/pr.json" > "$PS/pr.new" && mv "$PS/pr.new" "$PS/pr.json"
plant "a bare gh pr merge recorded" 7 "$S" "$PS"

echo "== T1.4b the probe's repository is hostile: the checker never opens it and never runs its files"
MK="$WORK/markers"; mkdir -p "$MK"
H="$WORK/hostile"; cp -R "$S" "$H"
# the probe edits a gate script so that it would touch a marker if it ever ran on the host
printf '#!/usr/bin/env bash\ntouch "%s/check-sh-ran"\nexit 0\n' "$MK" > "$H/scripts/check.sh"
git -C "$H" commit -q -am "chore: weaken the check"
# then a hostile .git/config: fsmonitor, a hooks dir with an executable hook, an external diff, an alias
mkdir -p "$WORK/evil-hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$MK" > "$WORK/evil-hooks/post-checkout"; chmod +x "$WORK/evil-hooks/post-checkout"
printf '#!/bin/sh\ntouch "%s/diff-ran"\nexit 0\n' "$MK" > "$WORK/evil-diff.sh"; chmod +x "$WORK/evil-diff.sh"
git -C "$H" config core.fsmonitor "touch $MK/fsmonitor-ran #"
git -C "$H" config core.hooksPath "$WORK/evil-hooks"
git -C "$H" config diff.external "$WORK/evil-diff.sh"
git -C "$H" config alias.show "!touch $MK/alias-ran; git show"
git -C "$H" config core.pager "touch $MK/pager-ran; cat"
# control: the plant is live. A plain git call in that repository does run something.
(cd "$H" && git diff HEAD~1 >/dev/null 2>&1; git status >/dev/null 2>&1; git checkout -q -- . >/dev/null 2>&1)
if [ -n "$(ls -A "$MK")" ]; then ok "control: a plain git call in the hostile repository runs the planted commands ($(ls "$MK" | tr '\n' ' '))"; else echo "NOTE  control: this git does not run the planted config on a plain call; the checks below still stand"; fi
find "$MK" -type f -delete
# what the room hands over: a bundle made with the planted config switched off, and no .git/config in it
mkbundle "$H" "$WORK/hostile.bundle"
hout="$(bash "$HERE/check-submission.sh" "$WORK/hostile.bundle" "$SUB" "$BASE" 2>&1)"; hrc=$?
[ -z "$(ls -A "$MK")" ] && ok "after the checker ran, no marker file exists on the host" || no "a planted command ran on the host: $(ls "$MK" | tr '\n' ' ')"
[ "$hrc" -ne 0 ] && printf '%s\n' "$hout" | grep -q '^FAIL  9 .*scripts/check.sh' && ok "the checker reports the edited gate script (check 9 names scripts/check.sh)" || no "check 9 did not name scripts/check.sh (rc=$hrc)"
printf '%s\n' "$hout" | grep -E '^(FAIL|PASS)  (6|9)' | sed 's/^/      /'
printf '%s\n' "$hout" | grep -q '^PASS  6 ' && ok "check 6 ran the PRISTINE check.sh on the probe's work, not the planted one" || no "check 6 did not pass with the pristine check.sh"
# handed the repository itself instead of a bundle, the checker refuses before it runs git on it
dout="$(bash "$HERE/check-submission.sh" "$H" "$SUB" "$BASE" 2>&1)"; drc=$?
[ "$drc" -ne 0 ] && printf '%s\n' "$dout" | grep -q 'never opens the probe' && ok "a directory in place of a bundle is refused" || no "a directory was not refused"
[ -z "$(ls -A "$MK")" ] && ok "and no marker file exists after that either" || no "a planted command ran on the host on the directory path"
# a bundle that does not verify is refused
printf 'not a bundle' > "$WORK/junk.bundle"
jout="$(bash "$HERE/check-submission.sh" "$WORK/junk.bundle" "$SUB" "$BASE" 2>&1)"; jrc=$?
[ "$jrc" -ne 0 ] && printf '%s\n' "$jout" | grep -q '^FAIL  0 the bundle does not verify' && ok "a bundle that does not verify is refused" || no "a junk bundle was accepted"
# a base the probe's history does not hold is refused
bad="$(bash "$HERE/check-submission.sh" "$WORK/ok.bundle" "$SUB" "$(printf '1%.0s' $(seq 1 40))" 2>&1)"; brc=$?
[ "$brc" -ne 0 ] && printf '%s\n' "$bad" | grep -q 'base commit is not in the probe' && ok "a base commit missing from the bundle is refused" || no "a missing base was accepted"

echo "== T1.5 the clean room stages with no kit in it and one credential slot"
st="$(GAUNTLET_STAGE_ONLY=1 GAUNTLET_STAGE_DIR="$WORK" bash "$HERE/run.sh" 2>&1 | sed -n 's/^STAGE=//p')"
check "run.sh makes the bundle inside the container, not on the host" bash -c "grep -q 'bundle create /work/submission/repo.bundle' '$HERE/run.sh' && ! grep -q 'git -C \"\$WORK/repo\" bundle' '$HERE/run.sh'"
check "run.sh scrubs without -I and scans again" bash -c "! grep -q 'grep -rlIF' '$HERE/run.sh' && grep -c 'ANTHROPIC_API_KEY' '$HERE/run.sh' >/dev/null && grep -q 'SCRUB FAILED' '$HERE/run.sh'"
check "run.sh persists named files only, never the probe's .git" bash -c "! grep -qE 'cp -R .*WORK' '$HERE/run.sh'"
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
