#!/usr/bin/env bash
# Gauntlet Tier 1 for the team stamp: deterministic, no network, no container, no model.
# Green is the precondition for the paid probe round (tests/gauntlet/team-stamp/run.sh).
#   bash tests/gauntlet/team-stamp/tier1.sh
#
# Why this runs on the host. Every repository and file below is written by this script itself, so no
# untrusted text reaches the host. A real probe round is different: the probe's work lives in a
# container volume, the checker runs in a second container with no key and no network, and the host
# reads only six named result files (run.sh, copy-out.sh). That container path is NOT executed here
# (no container runtime on the build host). Tier 1 sends its scripted work through the same checker
# script, plants hostile repositories and hostile output directories, and runs copy-out.sh and the
# key scrub on them, to show the hardening holds on everything that can run on a host.
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
# shellcheck source=tests/gauntlet/team-stamp/copy-out.sh
source "$HERE/copy-out.sh"

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
chk="$(bash "$HERE/check-submission.sh" "$S" "$SUB" "$BASE" 2>&1)"; crc=$?
[ "$crc" -eq 0 ] && ok "the checker passes on the card's PR" || { no "the checker failed on the card's PR"; printf '%s\n' "$chk" | grep -E 'FAIL' | sed 's/^/      /'; }
printf '%s\n' "$chk" | sed 's/^/      /'

echo "== T1.4 the checker can fail: break each requirement in turn"
plant() { # plant <label> <expected FAIL number> <repo dir> <submission dir>
  local label="$1" want="$2" out rc
  out="$(CHECKER_SKIP_CHECKSH=1 bash "$HERE/check-submission.sh" "$3" "$4" "$BASE" 2>&1)"; rc=$?
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

echo "== T1.4b the probe's repository is hostile: the checker never opens it with its config and never runs its files"
MK="$WORK/markers"; mkdir -p "$MK"
H="$WORK/hostile"; cp -R "$S" "$H"
# the probe edits a gate script so that it would touch a marker if it ever ran on the host
printf '#!/usr/bin/env bash\ntouch "%s/check-sh-ran"\nexit 0\n' "$MK" > "$H/scripts/check.sh"
# it adds gate-dir files whose names hold spaces, a newline and another gate path, and that touch a marker
mkdir -p "$H/scripts/test-x scripts"
printf '#!/usr/bin/env bash\ntouch "%s/added-test-ran"\nexit 0\n' "$MK" > "$H/scripts/test-x scripts/check-owners.sh"
printf '#!/usr/bin/env bash\ntouch "%s/newline-name-ran"\nexit 0\n' "$MK" > "$H/scripts/test-$(printf 'a\nb').sh"
git -C "$H" add -A -f; git -C "$H" commit -q -m "chore: weaken the check"
# then a hostile .git/config: fsmonitor, a hooks dir with an executable hook, an external diff, an alias,
# a pager, an alternates file that points at the host, and a symlinked hooks dir
mkdir -p "$WORK/evil-hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$MK" > "$WORK/evil-hooks/post-checkout"; chmod +x "$WORK/evil-hooks/post-checkout"
printf '#!/bin/sh\ntouch "%s/diff-ran"\nexit 0\n' "$MK" > "$WORK/evil-diff.sh"; chmod +x "$WORK/evil-diff.sh"
git -C "$H" config core.fsmonitor "touch $MK/fsmonitor-ran #"
git -C "$H" config core.hooksPath "$WORK/evil-hooks"
git -C "$H" config diff.external "$WORK/evil-diff.sh"
git -C "$H" config alias.show "!touch $MK/alias-ran; git show"
git -C "$H" config core.pager "touch $MK/pager-ran; cat"
mkdir -p "$H/.git/objects/info"; printf '%s\n' "$WORK/not-a-repo/objects" > "$H/.git/objects/info/alternates"
# control: the plant is live. A plain git call in that repository does run something.
(cd "$H" && git diff HEAD~1 >/dev/null 2>&1; git status >/dev/null 2>&1; git checkout -q -- . >/dev/null 2>&1)
if [ -n "$(ls -A "$MK")" ]; then ok "control: a plain git call in the hostile repository runs the planted commands ($(ls "$MK" | tr '\n' ' '))"; else echo "NOTE  control: this git does not run the planted config on a plain call; the checks below still stand"; fi
find "$MK" -type f -delete
hout="$(bash "$HERE/check-submission.sh" "$H" "$SUB" "$BASE" 2>&1)"; hrc=$?
[ -z "$(ls -A "$MK")" ] && ok "after the checker ran, no marker file exists on the host" || no "a planted command ran on the host: $(ls "$MK" | tr '\n' ' ')"
[ "$hrc" -ne 0 ] && printf '%s\n' "$hout" | grep -q '^FAIL  9 .*scripts/check.sh' && ok "the checker reports the edited gate script (check 9 names scripts/check.sh)" || no "check 9 did not name scripts/check.sh (rc=$hrc)"
printf '%s\n' "$hout" | grep -q '^NOTE  the probe added 2 file' && ok "files added under scripts/ (spaces, a newline, a gate path in the name) are listed and not run" || no "the added gate-dir files were not reported"
printf '%s\n' "$hout" | grep -q '^PASS  6 ' && ok "check 6 ran the PRISTINE check.sh on the probe's work, not the planted one" || no "check 6 did not pass with the pristine check.sh"
printf '%s\n' "$hout" | grep -E '^(FAIL|PASS|NOTE)  (6|9|the probe)' | sed 's/^/      /'
# a symlinked .git, a symlinked objects dir and a symlink inside refs all fail closed
for kind in gitlink objlink reflink; do
  Y="$WORK/sym-$kind"; cp -R "$S" "$Y"
  case "$kind" in
    gitlink) mv "$Y/.git" "$WORK/sym-gitdir"; ln -s "$WORK/sym-gitdir" "$Y/.git" ;;
    objlink) mv "$Y/.git/objects" "$WORK/sym-objects"; ln -s "$WORK/sym-objects" "$Y/.git/objects" ;;
    reflink) ln -s "$WORK/evil-diff.sh" "$Y/.git/refs/heads/planted" ;;
  esac
  yout="$(bash "$HERE/check-submission.sh" "$Y" "$SUB" "$BASE" 2>&1)"; yrc=$?
  [ "$yrc" -ne 0 ] && printf '%s\n' "$yout" | grep -q '^FAIL  0 ' && ok "a $kind plant fails closed" || no "a $kind plant was accepted (rc=$yrc)"
done
[ -z "$(ls -A "$MK")" ] && ok "and no marker file exists after the symlink plants" || no "a marker appeared after a symlink plant"
# a base the probe's history does not hold is refused
bad="$(bash "$HERE/check-submission.sh" "$S" "$SUB" "$(printf '1%.0s' $(seq 1 40))" 2>&1)"; brc=$?
[ "$brc" -ne 0 ] && printf '%s\n' "$bad" | grep -q 'base commit is not in the probe' && ok "a base commit missing from the history is refused" || no "a missing base was accepted"

echo "== T1.4c the host reads six named files out of the output dir and nothing else"
SECRET="k-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
RO="$WORK/out"; RR="$WORK/record"; mkdir -p "$RO" "$RR"
printf 'PASS\n' > "$RO/verdict.txt"; printf 'PASS  1 fine\n' > "$RO/checker-output.txt"
printf '{"pr":{"number":1}}\n' > "$RO/pr.json"; printf 'x\n' > "$RO/calls.jsonl"
printf 'diff\n' > "$RO/clean-diff.patch"
printf 'host secret: %s\n' "$SECRET" > "$WORK/host-secret.txt"
ln -s "$WORK/host-secret.txt" "$RO/transcript.jsonl"            # a symlink planted at a result name
printf 'not named\n' > "$RO/other.txt"; mkdir "$RO/dir-entry"
copy_results "$RO" "$RR" > "$WORK/co.out" 2>&1
[ "$COPIED" -eq 5 ] && [ -f "$RR/verdict.txt" ] && ok "five regular result files were copied" || no "copy-out copied $COPIED files"
[ ! -e "$RR/transcript.jsonl" ] && ok "a symlink at a result name was not copied" || no "a symlink was copied"
[ ! -e "$RR/other.txt" ] && [ ! -e "$RR/dir-entry" ] && ok "an unnamed file and an unnamed directory were ignored" || no "an unnamed entry was copied"
grep -q 'ignored 3 other entries' "$WORK/co.out" && ok "the ignored entries are counted in one log line" || no "the ignored count is wrong: $(cat "$WORK/co.out")"
! grep -rqF "$SECRET" "$RR" && ok "nothing behind the symlink reached the record" || no "the symlink target was read"
for nm in verdict.txt checker-output.txt pr.json calls.jsonl clean-diff.patch transcript.jsonl; do
  RO2="$WORK/out-$nm"; RR2="$WORK/rec-$nm"; mkdir -p "$RO2" "$RR2"; ln -s "$WORK/host-secret.txt" "$RO2/$nm"
  copy_results "$RO2" "$RR2" >/dev/null 2>&1
  [ -z "$(ls -A "$RR2")" ] || no "a symlink at $nm was copied"
done
ok "a symlink planted at each of the six result names copied nothing"
ln -s "$RO" "$WORK/out-link"; mkdir -p "$WORK/rec-link"
copy_results "$WORK/out-link" "$WORK/rec-link" >/dev/null 2>&1 && no "a symlinked output dir was read" || ok "a symlinked output dir is refused"
ln -s "$RR" "$WORK/rec-link2"
copy_results "$RO" "$WORK/rec-link2" >/dev/null 2>&1 && no "a symlinked record dir was written" || ok "a symlinked record dir is refused"
RO3="$WORK/out-big"; RR3="$WORK/rec-big"; mkdir -p "$RO3" "$RR3"; printf 'PASS\n' > "$RO3/verdict.txt"; head -c 2048 /dev/zero > "$RO3/transcript.jsonl"
RESULT_MAX_BYTES=1024 copy_results "$RO3" "$RR3" >/dev/null 2>&1
[ -f "$RR3/verdict.txt" ] && [ ! -e "$RR3/transcript.jsonl" ] && ok "a file over the size cap is not copied" || no "the size cap did not hold"
# the key scrub: text redacted, a binary that holds the key deleted, then scanned again
SR="$WORK/scrub"; mkdir -p "$SR"
printf 'before %s after\n' "$SECRET" > "$SR/t.txt"
{ head -c 64 /dev/urandom; printf '%s' "$SECRET"; head -c 64 /dev/urandom; printf '\000\001'; } > "$SR/b.bin"
printf 'clean\n' > "$SR/c.txt"
scrub_dir "$SR" "$SECRET" 2>/dev/null && ok "the scrub scans text and binary files and ends clean" || no "the scrub left the key behind"
grep -q 'REDACTED-KEY' "$SR/t.txt" && [ ! -e "$SR/b.bin" ] && [ -f "$SR/c.txt" ] && ok "text is redacted, the binary is deleted, a clean file is kept" || no "the scrub changed the wrong files"
! grep -rqF "$SECRET" "$SR" && ok "a second scan finds no key" || no "the key is still there"

echo "== T1.5 the room stages with no kit in it, the checker apart from the probe, one credential slot"
stout="$(GAUNTLET_STAGE_ONLY=1 GAUNTLET_STAGE_DIR="$WORK" bash "$HERE/run.sh" 2>&1)"
st="$(printf '%s\n' "$stout" | sed -n 's/^STAGE=//p')"
if [ -n "$st" ] && [ -d "$st/seed/repo" ]; then
  ok "run.sh stages the room"
  check "the seed holds the card, the shim and the stamped repo" bash -c "[ -f '$st/seed/CARD.md' ] && [ -x '$st/seed/bin/gh' ] && [ -f '$st/seed/repo/AGENTS.md' ] && [ -x '$st/seed/repo/scripts/pr-merge.sh' ]"
  check "the repo, card, prompt and shim name no path under the kit" bash -c "! grep -rIlE '\\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT' '$st/seed/repo' '$st/seed/CARD.md' '$st/seed/PROMPT.md' '$st/seed/bin' --exclude-dir=.git"
  check "the seed holds no kit lib or gauntlet dir" bash -c "[ ! -e '$st/seed/repo/lib/stamp.sh' ] && [ ! -e '$st/seed/repo/tests/gauntlet' ]"
  check "the checker dir holds only the checker, the pristine stamp is a git repo" bash -c "[ -f '$st/checker/check-submission.sh' ] && [ -d '$st/pristine/.git' ] && [ -d '$st/out' ] && [ -z \"\$(ls -A '$st/out')\" ]"
  check "the staged base is the seed repo's first commit" bash -c "[ \"\$(git -C '$st/seed/repo' rev-parse HEAD)\" = \"$(printf '%s\n' "$stout" | sed -n 's/^BASE=//p')\" ]"
else
  no "run.sh did not stage a room"
fi
check "the Dockerfile bakes no credential" bash -c "! grep -Eiq 'api_key|token|secret' '$HERE/Dockerfile'"
check "run.sh passes exactly one credential (the probe key) and only to the probe container" bash -c "[ \$(grep -c -- '-e ANTHROPIC_API_KEY' '$HERE/run.sh') -eq 1 ] && ! grep -Eq -- '-e (GH_TOKEN|GITHUB_TOKEN|OP_)' '$HERE/run.sh'"
check "the checker container has no network and mounts the probe volume read-only" bash -c "grep -q -- '--network none' '$HERE/run.sh' && grep -q -- '\$VOL:/probe:ro' '$HERE/run.sh'"
check "the probe container mounts only the named volume (no host path)" bash -c "blk=\$(grep -B1 -A6 -- '-e ANTHROPIC_API_KEY' '$HERE/run.sh'); printf '%s' \"\$blk\" | grep -q -- '\$VOL:/work' && ! printf '%s' \"\$blk\" | grep -Eq ':/(seed|out|checker|pristine)' && grep -q 'docker volume create' '$HERE/run.sh'"
check "the header says plainly the container path was not executed on the build host" bash -c "grep -q 'NOT EXECUTED ON THE BUILD HOST' '$HERE/run.sh'"
check "the scrub scans without -I" bash -c "! grep -q 'grep -rlIF' '$HERE/run.sh' '$HERE/copy-out.sh'"

echo "== T1.6 every generated test runs with the kit absent from PATH and HOME"
kf="$(bash tests/test-stamp-kitfree.sh all 2>&1)"; krc=$?
[ "$krc" -eq 0 ] && ok "tests/test-stamp-kitfree.sh all: $(printf '%s\n' "$kf" | tail -1)" || { no "kit-free pass failed"; printf '%s\n' "$kf" | grep -E 'NOT ok|FAIL' | head -6 | sed 's/^/      /'; }

echo
echo "tier1: $FAIL failed, $PASS passed"
[ "$FAIL" -eq 0 ]
