#!/usr/bin/env bash
# test-board-hermes.sh -- lib/sync/sweep/board-hermes: `board hermes link` and `check`,
# the sweep leg that records link drift, and the brief's decision line for a stale link.
#
# Hermes homes are scratch dirs under a scratch HOME; `hermes`, `sudo`, and the board
# command are stubs. No real Hermes, account, agent turn, or network.
#
#   AC1  no Hermes found: one skip line, exit 0, nothing written
#   AC2  detection: homes with a config.yaml, root and named profiles; several homes and no
#        terminal is a usage error that lists the choices
#   AC3  --dry-run prints the plan and writes nothing; no terminal and no --yes writes nothing
#   AC4  install: every kit skill into the profile's skills dir, a stamp with the skills
#        digest, the link recorded with the cluster's rail, hub, and boards
#   AC5  a named profile installs under profiles/<name>/skills; an unknown profile is refused
#   AC6  re-running refreshes and keeps one record per (home, profile)
#   AC7  verify: success needs the agent to RUN board health run and answer the nonce;
#        an answer without the run, or without the nonce, is "installed, not verified"
#   AC8  --sudo-user reads and writes the home through sudo
#   AC9  check: fresh is not stale; a changed digest, a missing stamp, a missing skill are
#        stale; --record writes hermes_links into the health state
#   AC10 board sweep records the check each tick
#   AC11 board brief: a stale link is one decision line for its cluster (the first cluster
#        when none is named); a fresh link adds nothing
#   AC12 the verb reaches the script
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HERMES_PY="$HERE/../lib/sync/sweep/board-hermes"
BRIEF="$HERE/../lib/sync/sweep/board-brief"
SWEEP="$HERE/../lib/sync/sweep/board-sweep"
BOARD="$HERE/../bin/board"
SKILLS_SRC="$HERE/../adapters/hermes/skills"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got '$2', want '$3')"; }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (missing '$3' in '$2')"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (found '$3' in '$2')" || ok "$1"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"
export DWARVES_HERMES_LINKS="$WORK/links.json"
unset DWARVES_BOARD_CONFIG HERMES_HOME
STUBS="$WORK/stubs"; mkdir -p "$STUBS"
NOW=1790000000

mkhome() {  # mkhome <dir> [profile...]: a Hermes home with a config.yaml and named profiles
  local d="$1"; shift
  mkdir -p "$d"; echo "model: x" > "$d/config.yaml"
  for p in "$@"; do mkdir -p "$d/profiles/$p"; echo "model: x" > "$d/profiles/$p/config.yaml"; done
}
link() { python3 "$HERMES_PY" link "$@" 2>&1 < /dev/null; }   # stdin is never a terminal here
reset() { command rm -rf "$HOME" "$DWARVES_HERMES_LINKS"; mkdir -p "$HOME"; }

# hermes stub: `config path` prints $FAKE_CFG; `chat` emits stream-json as FAKE_MODE says
cat > "$STUBS/hermes" <<'EOF'
#!/usr/bin/env bash
echo "hermes $*" >> "$FAKE_CALLS"
echo "HERMES_HOME=${HERMES_HOME:-UNSET}" >> "$FAKE_CALLS"
if [ "$1 $2" = "config path" ]; then echo "${FAKE_CFG:-}"; exit 0; fi
for a in "$@"; do case "$a" in KITLINK*|*"KITLINK "*) prompt="$a";; esac; done
nonce="$(printf '%s' "${prompt:-}" | sed -n 's/.*KITLINK \([0-9a-f]*\) .*/\1/p')"
echo '{"type":"system","subtype":"init"}'
case "${FAKE_MODE:-ok}" in
  ok) echo '{"type":"tool_use","name":"terminal","input":{"command":"~/.claude/dwarves-kit/bin/board health run --dry-run --force"}}'
      echo "{\"type\":\"result\",\"exit_code\":0,\"text\":\"KITLINK $nonce 4\"}";;
  norun) echo "{\"type\":\"result\",\"exit_code\":0,\"text\":\"KITLINK $nonce 4\"}";;
  nononce) echo '{"type":"tool_use","name":"terminal","input":{"command":"board health run --dry-run"}}'
           echo '{"type":"result","exit_code":0,"text":"9 boards"}';;
esac
exit "${FAKE_RC:-0}"
EOF
# sudo stub: drops `-n -u USER -H` and runs the rest as this user, recording the user
cat > "$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo-as $3" >> "$FAKE_CALLS"
shift 4
exec "$@"
EOF
chmod +x "$STUBS"/*
export FAKE_CALLS="$WORK/calls.log" FAKE_MODE=ok FAKE_RC=0 FAKE_CFG=""
: > "$FAKE_CALLS"
export PATH="$STUBS:$PATH"

SKILL_NAMES="$(ls "$SKILLS_SRC" | tr '\n' ' ' | sed 's/ $//')"

echo "case none (no Hermes found):"
reset
out="$(link --yes)"; rc=$?
eq "exit 0" "$rc" "0"
has "one skip line" "$out" "skip: no Hermes home found"
[ ! -e "$DWARVES_HERMES_LINKS" ]; eq "nothing recorded" "$?" "0"

echo "case detect (homes, profiles, several homes need a choice):"
reset
mkhome "$HOME/hermes-alpha/home" chief
mkhome "$HOME/hermes-beta/home"
mkdir -p "$HOME/hermes-gamma/home"          # no config.yaml: not a Hermes home
out="$(link --yes --no-verify)"; rc=$?
eq "two homes and no terminal is a usage error" "$rc" "64"
has "it names the homes" "$out" "$HOME/hermes-alpha/home"
lacks "and skips a dir with no config.yaml" "$out" "hermes-gamma"
out="$(link --home "$HOME/hermes-alpha/home" --yes --no-verify)"; rc=$?
eq "with a profile choice still open: usage error" "$rc" "64"
has "it lists default and chief" "$out" "chief"
mkhome "$HOME/solo/home"; rm -rf "$HOME/hermes-alpha" "$HOME/hermes-beta"
mv "$HOME/solo/home" "$HOME/hermes-solo-home" 2>/dev/null; mkdir -p "$HOME/hermes-solo"; mv "$HOME/hermes-solo-home" "$HOME/hermes-solo/home"
out="$(link --yes --no-verify)"; rc=$?
eq "one home, one profile: no question" "$rc" "0"
has "installed" "$out" "installed kit-board"

echo "case dry-run and confirmation:"
reset; mkhome "$HOME/hermes-alpha/home"
out="$(link --dry-run)"; rc=$?
eq "dry-run exits 0" "$rc" "0"
has "the plan names the skills dir" "$out" "skills   $HOME/hermes-alpha/home/skills"
has "and each skill as new" "$out" "install  kit-board  (new)"
has "and the verify step" "$out" "verify   one agent turn"
has "and says nothing was written" "$out" "dry-run: nothing written"
[ ! -d "$HOME/hermes-alpha/home/skills" ] && [ ! -e "$DWARVES_HERMES_LINKS" ]; eq "dry-run wrote nothing" "$?" "0"
out="$(link)"; rc=$?
eq "no terminal and no --yes: exit 64" "$rc" "64"
has "it says to pass --yes" "$out" "pass --yes"
[ ! -d "$HOME/hermes-alpha/home/skills" ]; eq "and wrote nothing" "$?" "0"

echo "case install (skills, stamp, record with the cluster's mapping):"
reset; mkhome "$HOME/hermes-alpha/home"
cat > "$WORK/board.json" <<'EOF'
{"cluster_map":"ops=personal,family=family","common":{"hub":["ops=ops-toolkit"],"board":["ops=df-content","family=other"]}}
EOF
out="$(DWARVES_BOARD_CONFIG="$WORK/board.json" link --yes --no-verify --cluster ops --label chonky)"; rc=$?
eq "exit 0" "$rc" "0"
for n in $SKILL_NAMES; do [ -f "$HOME/hermes-alpha/home/skills/$n/SKILL.md" ] && ok "installed $n" || bad "missing $n"; done
stamp="$HOME/hermes-alpha/home/skills/.dwarves-kit-skills.json"
eq "the stamp carries a 16-char digest" "$(jq -r '.skills_digest | length' "$stamp")" "16"
eq "and the skill names" "$(jq -r '.skills | join(" ")' "$stamp")" "$SKILL_NAMES"
eq "and the kit version" "$(jq -r '.kit_version' "$stamp")" "$(cat "$HERE/../VERSION")"
eq "the link is recorded with its label and cluster" "$(jq -r '.links[0] | [.label, .profile, .cluster] | join(" ")' "$DWARVES_HERMES_LINKS")" "chonky default ops"
eq "with the cluster's rail, hub, boards" "$(jq -r '.links[0] | [.rail, .hub, (.boards | join(","))] | join(" ")' "$DWARVES_HERMES_LINKS")" "personal ops-toolkit df-content"
eq "the links file is 0600" "$(stat -f '%Lp' "$DWARVES_HERMES_LINKS" 2>/dev/null || stat -c '%a' "$DWARVES_HERMES_LINKS")" "600"
has "no verify: says so" "$out" "installed, not verified"

echo "case profile:"
reset; mkhome "$HOME/hermes-alpha/home" chief
out="$(link --yes --no-verify --profile chief)"; rc=$?
eq "a named profile installs" "$rc" "0"
[ -f "$HOME/hermes-alpha/home/profiles/chief/skills/kit-board/SKILL.md" ]; eq "under profiles/<name>/skills" "$?" "0"
[ ! -d "$HOME/hermes-alpha/home/skills" ]; eq "and not in the root" "$?" "0"
eq "the label is the profile name" "$(jq -r '.links[0].label' "$DWARVES_HERMES_LINKS")" "chief"
out="$(link --yes --no-verify --profile nope)"; rc=$?
eq "an unknown profile is refused" "$rc" "64"
has "with the choices" "$out" "choices: default, chief"

echo "case re-run (refresh, one record per home and profile):"
reset; mkhome "$HOME/hermes-alpha/home"
link --yes --no-verify >/dev/null
echo "stale local edit" > "$HOME/hermes-alpha/home/skills/kit-board/SKILL.md"
out="$(link --yes --no-verify)"
has "the plan says refresh" "$out" "install  kit-board  (refresh)"
cmp -s "$SKILLS_SRC/kit-board/SKILL.md" "$HOME/hermes-alpha/home/skills/kit-board/SKILL.md"; eq "the skill is back to the kit's" "$?" "0"
eq "one record" "$(jq -r '.links | length' "$DWARVES_HERMES_LINKS")" "1"
link --yes --no-verify --label second >/dev/null
eq "still one record, updated" "$(jq -r '.links | length' "$DWARVES_HERMES_LINKS")" "1"
eq "with the new label" "$(jq -r '.links[0].label' "$DWARVES_HERMES_LINKS")" "second"

echo "case verify (a real turn, the nonce, the command actually run):"
reset; mkhome "$HOME/hermes-alpha/home" chief
: > "$FAKE_CALLS"
out="$(FAKE_MODE=ok link --yes --profile chief)"; rc=$?
eq "exit 0 on success" "$rc" "0"
has "prints linked" "$out" "hermes: linked"
has "and what the agent did" "$out" "counted 4 board(s) over threshold"
has "the turn runs against the profile" "$(cat "$FAKE_CALLS")" "hermes -p chief chat"
has "in its own home" "$(cat "$FAKE_CALLS")" "HERMES_HOME=$HOME/hermes-alpha/home"
has "in a session that is not Bot Chat" "$(cat "$FAKE_CALLS")" "kit-link-verify"
reset; mkhome "$HOME/hermes-alpha/home"
: > "$FAKE_CALLS"
FAKE_MODE=ok link --yes >/dev/null
lacks "the root profile takes no -p" "$(cat "$FAKE_CALLS")" " -p "
out="$(FAKE_MODE=norun link --yes)"; rc=$?
eq "an answer without the command run is not linked" "$rc" "1"
has "and says why" "$out" "installed, not verified: the agent answered without running board health run"
out="$(FAKE_MODE=nononce link --yes)"; rc=$?
eq "an answer without the nonce is not linked" "$rc" "1"
has "and says so" "$out" "no KITLINK answer"
lacks "and never prints linked" "$out" "hermes: linked"
out="$(FAKE_MODE=ok FAKE_RC=3 link --yes)"; rc=$?
eq "a failing agent process is not linked" "$rc" "1"
eq "the skills are still installed after a failed verify" "$([ -f "$HOME/hermes-alpha/home/skills/kit-board/SKILL.md" ] && echo yes)" "yes"

echo "case sudo-user (another account's home, through sudo):"
reset; mkhome "$HOME/hermes-alpha/home" chief
: > "$FAKE_CALLS"
out="$(link --home "$HOME/hermes-alpha/home" --profile chief --sudo-user server --yes)"; rc=$?
eq "exit 0" "$rc" "0"
has "it went through sudo as the named user" "$(cat "$FAKE_CALLS")" "sudo-as server"
[ -f "$HOME/hermes-alpha/home/profiles/chief/skills/kit-board/SKILL.md" ]; eq "the skills landed" "$?" "0"
has "no agent turn for another account's home" "$out" "installed, not verified (--sudo-user home"
eq "the record names the sudo user" "$(jq -r '.links[0].sudo_user' "$DWARVES_HERMES_LINKS")" "server"
out="$(link --home "$HOME/hermes-alpha/home" --profile chief --sudo-user server --dry-run)"
has "its dry-run shows the user" "$out" "(as server)"

echo "case check (fresh, changed, missing stamp, missing skill, --record):"
reset; mkhome "$HOME/hermes-alpha/home" chief
link --yes --no-verify --profile chief --cluster ops >/dev/null
out="$(python3 "$HERMES_PY" check)"
eq "fresh is not stale" "$(jq -r '.stale' <<<"$out")" "false"
sdir="$HOME/hermes-alpha/home/profiles/chief/skills"
jq '.skills_digest = "0000000000000000"' "$sdir/.dwarves-kit-skills.json" > "$WORK/s.json" && command cp "$WORK/s.json" "$sdir/.dwarves-kit-skills.json"
out="$(python3 "$HERMES_PY" check)"
eq "a changed digest is stale" "$(jq -r '.stale' <<<"$out")" "true"
eq "and says the kit's skills changed" "$(jq -r '.reason' <<<"$out")" "the kit's skills changed"
link --yes --no-verify --profile chief --cluster ops >/dev/null
mv "$sdir/.dwarves-kit-skills.json" "$WORK/gone.json"
eq "no stamp is stale" "$(python3 "$HERMES_PY" check | jq -r '.reason')" "no stamp"
mv "$WORK/gone.json" "$sdir/.dwarves-kit-skills.json"
mv "$sdir/kit-board" "$WORK/kit-board.gone"
eq "a missing skill is stale" "$(python3 "$HERMES_PY" check | jq -r '.reason')" "skill kit-board is missing"
mv "$WORK/kit-board.gone" "$sdir/kit-board"
HS="$WORK/health.json"; command rm -f "$HS"
python3 "$HERMES_PY" check --record --health-state-file "$HS" >/dev/null
eq "--record writes hermes_links" "$(jq -r '.hermes_links | length' "$HS")" "1"
eq "with the cluster and the verdict" "$(jq -r '.hermes_links[0] | [.cluster, .stale] | join(" ")' "$HS")" "ops false"
eq "check with no links file is silent and exit 0" "$(DWARVES_HERMES_LINKS="$WORK/none.json" python3 "$HERMES_PY" check | wc -l | tr -d ' ')" "0"

echo "case sweep (records the check every tick):"
reset; mkhome "$HOME/hermes-alpha/home"
link --yes --no-verify >/dev/null
mkdir -p "$WORK/sw/home/.cache/backlog-sync"
cat > "$WORK/swboard" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  sync) echo "synced reminders: 1 spoke items, 1 board rows"; exit 0 ;;
  mirror) echo "    mirror: plan 0 ops"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$WORK/swboard"
mkdir -p "$WORK/repo"; git -C "$WORK/repo" init -q -b main; printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | one | | queued |\n' > "$WORK/repo/BACKLOG.md"
echo "repo  $WORK/repo/BACKLOG.md  rail=r1" > "$WORK/boards.txt"
SWH="$WORK/sw/health.json"; command rm -f "$SWH"
env HOME="$WORK/sw/home" DWARVES_HERMES_LINKS="$DWARVES_HERMES_LINKS" PATH="$PATH" \
  "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/swboard" --state-file "$WORK/sw/digest.json" \
  --health-state-file "$SWH" --cluster-map "c1=r1" >/dev/null 2>&1
eq "the sweep recorded the link check" "$(jq -r '.hermes_links | length' "$SWH" 2>/dev/null)" "1"
eq "fresh" "$(jq -r '.hermes_links[0].stale' "$SWH" 2>/dev/null)" "false"
before="$(cksum < "$DWARVES_HERMES_LINKS")"
env HOME="$WORK/sw/home" DWARVES_HERMES_LINKS="$WORK/none.json" PATH="$PATH" \
  "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/swboard" --state-file "$WORK/sw/digest.json" \
  --health-state-file "$SWH" --cluster-map "c1=r1" >/dev/null 2>&1; rc=$?
eq "a sweep with no links file still exits 0" "$rc" "0"

echo "case brief (a stale link is one decision line, for its cluster):"
cat > "$WORK/kanban" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "boards list" ] && { echo '[]'; exit 0; }
echo '[]'
EOF
chmod +x "$WORK/kanban"
cat > "$WORK/poster" <<'EOF'
#!/usr/bin/env bash
cat >> "$FAKE_POSTED"; echo >> "$FAKE_POSTED"
EOF
chmod +x "$WORK/poster"
export FAKE_POSTED="$WORK/posted.out"
cat > "$WORK/repos.txt" <<EOF
repo  $WORK/repo/BACKLOG.md  rail=r1
other $WORK/repo/BACKLOG.md  rail=r2
EOF
brief() {  # brief <links file> [--force]
  : > "$FAKE_POSTED"; command rm -f "$WORK/bh.json"
  DWARVES_HERMES_LINKS="$1" python3 "$BRIEF" run --registry "$WORK/repos.txt" --cluster-map "c1=r1,c2=r2" \
    --state-file "$WORK/digest.json" --health-state-file "$WORK/bh.json" --poster "$WORK/poster" \
    --kanban "c1=$WORK/kanban" --now "$NOW" 2>/dev/null
}
msg_of() { jq -r --arg c "$1" 'select(.cluster == $c) | [.fields[].value] | join("\n")' "$FAKE_POSTED"; }
echo '{}' > "$WORK/digest.json"
reset; mkhome "$HOME/hermes-alpha/home" chief
link --yes --no-verify --profile chief --cluster c2 >/dev/null
brief "$DWARVES_HERMES_LINKS"
lacks "a fresh link adds no decision" "$(msg_of c2)" "kit skills on"
jq '.skills_digest = "0000000000000000"' "$HOME/hermes-alpha/home/profiles/chief/skills/.dwarves-kit-skills.json" > "$WORK/s.json" \
  && command cp "$WORK/s.json" "$HOME/hermes-alpha/home/profiles/chief/skills/.dwarves-kit-skills.json"
brief "$DWARVES_HERMES_LINKS"
has "a stale link is a decision line for its cluster" "$(msg_of c2)" "• kit skills on chief are stale: re-run board hermes link"
has "under the decision head" "$(msg_of c2)" "🙋 needs your decision (1)"
lacks "and not in another cluster's brief" "$(msg_of c1)" "kit skills on"
python3 - "$DWARVES_HERMES_LINKS" <<'PYEOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["links"][0]["cluster"] = ""; json.dump(d, open(p, "w"))
PYEOF
brief "$DWARVES_HERMES_LINKS"
has "a link with no cluster goes to the first cluster" "$(msg_of c1)" "kit skills on chief are stale"
lacks "and only there" "$(msg_of c2)" "kit skills on"
echo "{\"hermes_links\":[{\"label\":\"recorded\",\"cluster\":\"c1\",\"stale\":true,\"reason\":\"x\"}]}" > "$WORK/bh.json"
: > "$FAKE_POSTED"
DWARVES_HERMES_LINKS="$WORK/none.json" python3 "$BRIEF" run --registry "$WORK/repos.txt" --cluster-map "c1=r1,c2=r2" \
  --state-file "$WORK/digest.json" --health-state-file "$WORK/bh.json" --poster "$WORK/poster" \
  --kanban "c1=$WORK/kanban" --now "$NOW" 2>/dev/null
has "the sweep's recorded state is what the brief reads" "$(msg_of c1)" "kit skills on recorded are stale"

echo "case verb:"
out="$("$BOARD" hermes link --help 2>&1)"
has "board hermes link --help" "$out" "--sudo-user"

echo
echo "board-hermes: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
