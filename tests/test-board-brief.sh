#!/usr/bin/env bash
# test-board-brief.sh -- lib/sync/sweep/board-brief: ONE message per cluster per
# day, built on `board health`.
#
# Every board is a throwaway git repo; the kanban reader, the incident hook, the
# poster and HOME are stubs or scratch dirs: no real board, no spoke, no network,
# no credential.
#
#   AC1  decisions: hub/mirror drift becomes one question per row, three at most
#   AC2  incident hook: open rows, needs_you rows become decisions, bots, faults
#   AC3  a failing or malformed hook is a fault line, never an all-clear; the hook is
#        told when the run is a preview or a test (BOARD_BRIEF_READ_ONLY)
#   AC4  no decision: one all-clear line; --decisions-only posts nothing (and stamps)
#   AC5  boards section: first run, every third day, or when a decision exists;
#        otherwise its lines ride the details (a sync fault does not bring them back)
#   AC6  bots line: hook counts, cards archived since the last brief, sync errors
#   AC7  cadence: due once a day, --force, --dry-run and --no-state stamp nothing
#   AC8  a failed post stays due, rides carried_error, clears on delivery
#   AC9  payload shape: kind brief, stable key per day, details only when there are some
#   AC10 --config / $DWARVES_BOARD_CONFIG feed the flags for brief and health; a bad file is an error
#   AC11 the board verb reaches the script
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BRIEF="$HERE/../lib/sync/sweep/board-brief"
HEALTH="$HERE/../lib/sync/sweep/board-health"
BOARD="$HERE/../bin/board"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got '$2', want '$3')"; }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (missing '$3' in '$2')"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (found '$3' in '$2')" || ok "$1"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export HOME="$WORK/home"; mkdir -p "$HOME"
unset DWARVES_BOARD_CONFIG
NOW=1790000000
DAY=86400

commit() {
  git -C "$1" add -A >/dev/null
  GIT_AUTHOR_DATE="@$2 +0000" GIT_COMMITTER_DATE="@$2 +0000" \
    git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$3"
}

# hub "crew": AB-1 queued, AB-2 executing, AB-3 parked, AB-4 shipped, AB-5 claimed
mkdir -p "$WORK/crew/_meta"
git -C "$WORK/crew" init -q -b main
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | one | | queued |\n| AB-2 | two | | executing |\n| AB-3 | waits | | parked [later] |\n| AB-4 | done | | shipped |\n| AB-5 | five | | claimed |\n' > "$WORK/crew/_meta/BACKLOG.md"
commit "$WORK/crew" $((NOW - 1 * DAY)) first
mkdir -p "$WORK/solo"
git -C "$WORK/solo" init -q -b main
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| SO-1 | one | | queued |\n' > "$WORK/solo/BACKLOG.md"
commit "$WORK/solo" $((NOW - 1 * DAY)) first

cat > "$WORK/boards.txt" <<EOF
crew  $WORK/crew/_meta/BACKLOG.md  on rail=crew
solo  $WORK/solo/BACKLOG.md        rail=pers
EOF
MAP="alpha=crew,beta=pers"
# the mirror cards that match the hub: the four live rows (AB-4 is shipped)
CLEAN="AB-1:ready,AB-2:ready,AB-3:ready,AB-5:ready"

# kanban stub: board "crew" mirrors cards from $FAKE_CARDS ("AB-1:ready,AB-4:done"); board "work" has triage cards
cat > "$WORK/kanban" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_KANBAN_FAIL:-}" ] && { echo "reader exploded" >&2; exit 3; }
if [ "$1 $2" = "boards list" ]; then
  cat <<JSON
[{"slug":"work","archived":false,"counts":{"triage":2,"ready":1,"done":4,"archived":${FAKE_ARCHIVED:-5}}},
 {"slug":"crew","archived":false,"counts":{"ready":4}}]
JSON
elif [ "$2" = "crew" ]; then
  printf '['; first=1
  IFS=',' read -ra cards <<< "${FAKE_CARDS:-AB-1:ready,AB-2:ready,AB-3:ready,AB-4:ready}"
  for c in "${cards[@]}"; do
    [ -n "$c" ] || continue
    [ "$first" -eq 0 ] && printf ','; first=0
    printf '{"id":"m-%s","status":"%s","body":"origin: crew:%s\\nnotes: x","created_at":%s}' "${c%%:*}" "${c##*:}" "${c%%:*}" "$((FAKE_NOW - 86400))"
  done
  printf ']'
else
  cat <<JSON
[{"id":"a","status":"triage","created_at":$((FAKE_NOW - 3 * 86400))},
 {"id":"c","status":"triage","created_at":$((FAKE_NOW - 2 * 86400))},
 {"id":"b","status":"ready","created_at":$((FAKE_NOW - 1 * 86400))}]
JSON
fi
EOF
chmod +x "$WORK/kanban"

# incident hook stub: prints $FAKE_INC_FILE, or fails
cat > "$WORK/incidents" <<'EOF'
#!/usr/bin/env bash
echo "${BOARD_BRIEF_READ_ONLY:-unset}" >> "$FAKE_INC_FLAG"
[ -n "${FAKE_INC_FAIL:-}" ] && { echo "feed exploded" >&2; exit 4; }
cat "$FAKE_INC_FILE"
EOF
chmod +x "$WORK/incidents"

cat > "$WORK/poster" <<'EOF'
#!/usr/bin/env bash
cat >> "$FAKE_POSTED"; echo >> "$FAKE_POSTED"
[ "${FAKE_POSTER_RC:-0}" -ne 0 ] && echo "${FAKE_POSTER_ERR:-fake poster failure}" >&2
exit "${FAKE_POSTER_RC:-0}"
EOF
chmod +x "$WORK/poster"
export FAKE_NOW="$NOW" FAKE_POSTED="$WORK/posted.out" FAKE_INC_FILE="$WORK/inc.json" FAKE_INC_FLAG="$WORK/inc.flag"
export FAKE_KANBAN_FAIL="" FAKE_ARCHIVED=5 FAKE_POSTER_RC=0 FAKE_POSTER_ERR="" FAKE_CARDS="" FAKE_INC_FAIL=""

HS="$WORK/health.json"; DS="$WORK/digest.json"
echo '{}' > "$DS"
echo '{}' > "$FAKE_INC_FILE"
fresh() {
  command rm -f "$HS" 2>/dev/null; : > "$FAKE_POSTED"
  FAKE_POSTER_RC=0; FAKE_KANBAN_FAIL=""; FAKE_ARCHIVED=5; FAKE_CARDS=""; FAKE_INC_FAIL=""
  echo '{}' > "$FAKE_INC_FILE"
}
run() {  # run <now> [extra args]: the sweep ticks first, as it does every hour
  local now="$1"; shift
  if [ "${FAKE_SYNC_RC:-0}" -eq 0 ]; then
    printf 'synced notion: 1 spoke items\n' | python3 "$HEALTH" record --repo crew --rc 0 --now "$now" --health-state-file "$HS"
    printf 'synced notion: 1 spoke items\n' | python3 "$HEALTH" record --repo solo --rc 0 --now "$now" --health-state-file "$HS"
  else
    printf 'synced notion: 1\nERROR notion: 401\n' | python3 "$HEALTH" record --repo crew --rc 1 --now "$now" --health-state-file "$HS"
  fi
  python3 "$BRIEF" run --registry "$WORK/boards.txt" --cluster-map "$MAP" --state-file "$DS" \
    --health-state-file "$HS" --poster "$WORK/poster" --kanban "alpha=$WORK/kanban" --hub alpha=crew \
    --board alpha=work --incidents "alpha=$WORK/incidents" --now "$now" "$@" 2>"$WORK/run.err"
}
last() { tail -n 1 "$FAKE_POSTED"; }
npost() { grep -c . "$FAKE_POSTED"; }
msg() { jq -r '[.fields[].value] | join("\n")' <<<"$(last)"; }
det() { jq -r '(.details // []) | join("\n")' <<<"$(last)"; }

echo "case decisions (hub/mirror drift, one question per row):"
fresh
run "$NOW" --cluster alpha
has "the shipped row with an open card is a question" "$(msg)" "AB-4 hub/mirror drift: board says shipped, the Hermes card is still open. Ship or reopen?"
has "the head counts the items" "$(msg)" "🙋 needs your decision (1)"
eq "a decision makes the payload warn" "$(jq -r '.severity' <<<"$(last)")" "warn"
eq "and flags attention" "$(jq -r '.attention' <<<"$(last)")" "true"
fresh
FAKE_CARDS="AB-1:ready,AB-2:done,AB-4:done" run "$NOW" --cluster alpha
has "a done card on a live row is a question" "$(msg)" "AB-2 hub/mirror drift: the Hermes card is done, the board says executing. Ship or reopen?"
lacks "a done card on a shipped row is settled" "$(msg)" "AB-4 hub/mirror drift"
fresh
FAKE_CARDS="AB-1:ready,AB-2:ready,AB-3:ready,AB-4:ready,AB-5:done" run "$NOW" --cluster alpha
eq "one drift row is the only decision here" "$(jq -r '.data.decisions | length' <<<"$(last)")" "2"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"question":"Fix or close?"},
         {"id":"t2","label":"alpha two","needs_you":true},{"id":"t3","label":"alpha three","needs_you":true}]}
EOF
run "$NOW" --cluster alpha
eq "four decisions are counted" "$(jq -r '.data.decisions | length' <<<"$(last)")" "4"
has "the head shows the true count" "$(msg)" "🙋 needs your decision (4)"
eq "three lines show in the message" "$(jq -r '[.fields[] | select(.name == "decision")] | length' <<<"$(last)")" "4"
has "the rest is named, not dropped" "$(msg)" "+1 more in details"
has "the rest is in the details" "$(det)" "t3 alpha three"

echo "case incident hook (rows, bots, faults, explicit decisions):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t9","label":"gateway-run-crit @ host","age":"3h ago","firing":true},
         {"id":"t8","label":"disk-warn","age":"1d ago"},{"id":"t7","label":"x","age":"2d ago"},
         {"id":"t6","label":"y","age":"3d ago"},{"id":"t5","label":"z","age":"4d ago"}],
 "decisions":[{"id":"fixbox","question":"Retry the failed job?"}],
 "bots":{"auto-resolved":3,"fixbox done":0,"parked":2},
 "faults":["auditor: violations 2"],
 "details":["AI spend 24h: 1.20 USD"]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "the incident head" "$(msg)" "🔥 open incidents (5)"
has "a firing row says so" "$(msg)" "• 3h ago t9 gateway-run-crit @ host · firing"
has "three rows, then the rest named" "$(msg)" "+2 more in details"
has "the hook's fault line shows under incidents" "$(msg)" "⚠️ auditor: violations 2"
has "an explicit hook decision is a decision" "$(msg)" "fixbox Retry the failed job?"
has "hook details ride the details" "$(det)" "AI spend 24h: 1.20 USD"
has "the overflow rows ride the details" "$(det)" "t5"
has "bots show as given, zeros dropped" "$(msg)" "🤖 24h: auto-resolved 3 · parked 2 · sync errors 0"

echo "case hook flag (read-only under a preview or a test):"
fresh; : > "$FAKE_INC_FLAG"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
eq "a real run gives the hook no read-only flag" "$(< "$FAKE_INC_FLAG")" "unset"
: > "$FAKE_INC_FLAG"; FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force --dry-run > /dev/null
eq "--dry-run sets BOARD_BRIEF_READ_ONLY" "$(< "$FAKE_INC_FLAG")" "1"
: > "$FAKE_INC_FLAG"; FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force --no-state
eq "--no-state sets it too" "$(< "$FAKE_INC_FLAG")" "1"

echo "case hook text (names kept whole, secrets masked):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"hermes_state_registry-crit @ hermes-personal"},
         {"id":"t2","label":"leak 0123456789abcdef0123456789abcdef0123 op://Vault/item/field https://discord.com/api/webhooks/1/abc"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a long rule name is not masked" "$(msg)" "hermes_state_registry-crit @ hermes-personal"
has "hex runs are masked" "$(msg)" "leak [redacted]"
has "secret references are masked" "$(msg)" "[ref-redacted]"
has "webhook URLs are masked" "$(msg)" "[webhook-redacted]"

echo "case hook failure is a fault, never an all-clear:"
fresh
FAKE_INC_FAIL=1 FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "an exit failure shows as a fault" "$(msg)" "⚠️ incident feed unreadable: feed exploded"
lacks "and no all-clear line" "$(msg)" "nothing needs you"
fresh
echo 'not json' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "malformed output is a fault" "$(msg)" "⚠️ incident feed unreadable: hook printed no JSON"
echo '[1,2]' > "$FAKE_INC_FILE"
fresh; echo '[1,2]' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a non-object is a fault" "$(msg)" "hook JSON is not an object"

echo "case all clear and --decisions-only:"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "no decision: one all-clear line" "$(msg)" "✅ nothing needs you"
lacks "and no decision head" "$(msg)" "🙋"
eq "severity info" "$(jq -r '.severity' <<<"$(last)")" "info"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --decisions-only alpha
eq "decisions-only posts nothing when clean" "$(npost)" "0"
eq "but stamps the run" "$(jq -r '.brief.last_run.alpha' "$HS")" "$NOW"
fresh
run "$NOW" --cluster alpha --decisions-only alpha
eq "decisions-only posts when a decision exists" "$(npost)" "1"
eq "and the message is the decision lines alone" "$(jq -r '[.fields[].name] | unique | join(",")' <<<"$(last)")" "decision,decision-head"

echo "case boards section (slow clock, reason, details):"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "first run shows the hub line" "$(msg)" "🗂️ crew: 3 active, 1 parked · Hermes mirror 4 open = hub ✅"
eq "boards_last stamped" "$(jq -r '.brief.boards_last.alpha' "$HS")" "$NOW"
FAKE_CARDS="$CLEAN" run $((NOW + 1 * DAY)) --cluster alpha
lacks "the next day hides the boards lines" "$(msg)" "🗂️ crew"
has "they ride the details" "$(det)" "🗂️ crew: 3 active, 1 parked"
eq "boards_last did not move" "$(jq -r '.brief.boards_last.alpha' "$HS")" "$NOW"
FAKE_CARDS="$CLEAN" run $((NOW + 3 * DAY)) --cluster alpha
has "three days on, they show again" "$(msg)" "🗂️ crew"
FAKE_CARDS="$CLEAN" run $((NOW + 4 * DAY)) --cluster alpha
lacks "and hide again" "$(msg)" "🗂️ crew"
run $((NOW + 5 * DAY)) --cluster alpha
has "a decision item brings them back" "$(msg)" "🗂️ crew"
FAKE_CARDS="$CLEAN" run $((NOW + 6 * DAY)) --cluster alpha --show-boards
has "--show-boards forces them" "$(msg)" "🗂️ crew"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
FAKE_SYNC_RC=1 FAKE_CARDS="$CLEAN" run $((NOW + DAY)) --cluster alpha
lacks "a sync fault does not bring the boards back" "$(msg)" "❌ sync failed: crew"
has "the bots line counts it" "$(msg)" "sync errors 1"
has "and the details name it" "$(det)" "❌ sync failed: crew"

echo "case bots line (archived since the last brief, sync errors):"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "baseline: sync errors only" "$(msg)" "🤖 24h: sync errors 0"
FAKE_ARCHIVED=17 FAKE_CARDS="$CLEAN" run $((NOW + DAY)) --cluster alpha
has "archived since the last brief" "$(msg)" "🤖 24h: archived 12 · sync errors 0"
FAKE_SYNC_RC=1 FAKE_ARCHIVED=17 FAKE_CARDS="$CLEAN" run $((NOW + 2 * DAY)) --cluster alpha
has "a failed leg counts" "$(msg)" "sync errors 1"

echo "case cadence:"
fresh
FAKE_CARDS="$CLEAN" run "$NOW"
eq "both clusters post once" "$(npost)" "2"
FAKE_CARDS="$CLEAN" run $((NOW + 3600))
eq "a second run the same day posts nothing" "$(npost)" "2"
has "and says so" "$(cat "$WORK/run.err")" "skipped(not-due)"
FAKE_CARDS="$CLEAN" run $((NOW + DAY))
eq "a day later both are due again" "$(npost)" "4"
FAKE_CARDS="$CLEAN" run $((NOW + DAY + 60)) --force --cluster alpha
eq "--force ignores the cadence" "$(npost)" "5"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --dry-run > "$WORK/dry.out"
eq "--dry-run prints a payload per cluster" "$(grep -c . "$WORK/dry.out")" "2"
eq "and posts nothing" "$(npost)" "0"
eq "and writes no brief state" "$(jq -r 'has("brief")' "$HS")" "false"
FAKE_CARDS="$CLEAN" run "$NOW" --no-state --cluster alpha
eq "--no-state posts" "$(npost)" "1"
eq "but writes no brief state" "$(jq -r 'has("brief")' "$HS")" "false"

echo "case failed post (carried, then cleared):"
fresh
FAKE_POSTER_RC=1 FAKE_POSTER_ERR="post eventbridge failed" FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
eq "no stamp after a failure" "$(jq -r '.brief.last_run.alpha // "none"' "$HS")" "none"
eq "the reason is kept" "$(jq -r '.brief.errors.alpha' "$HS")" "post eventbridge failed"
FAKE_CARDS="$CLEAN" run $((NOW + 3600)) --cluster alpha
eq "it stays due and retries" "$(npost)" "2"
eq "the retry carries the reason" "$(jq -r '.carried_error' <<<"$(last)")" "post eventbridge failed"
has "and shows a retry line" "$(msg)" "↻ retry"
eq "delivery clears it" "$(jq -r '.brief.errors | length' "$HS")" "0"

echo "case payload shape:"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
p="$(last)"
eq "kind" "$(jq -r '.kind' <<<"$p")" "brief"
eq "title names the cluster" "$(jq -r '.title' <<<"$p")" "Daily brief · alpha"
eq "period one day" "$(jq -r '.period_days' <<<"$p")" "1"
eq "date and next due" "$(jq -r '[.date, .next_due] | join(" ")' <<<"$p")" "$(date -r "$NOW" +%Y-%m-%d) $(date -r $((NOW + DAY)) +%Y-%m-%d)"
eq "key is 32 hex" "$(jq -r '.key | test("^[0-9a-f]{32}$")' <<<"$p")" "true"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha; k1="$(jq -r .key <<<"$(last)")"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force; k2="$(jq -r .key <<<"$(last)")"
eq "the key is stable within a day" "$k1" "$k2"
FAKE_CARDS="$CLEAN" run $((NOW + DAY)) --cluster alpha; k3="$(jq -r .key <<<"$(last)")"
[ "$k1" != "$k3" ]; eq "and changes the next day" "$?" "0"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --show-boards
eq "details are absent when there are none" "$(jq -r 'has("details")' <<<"$(last)")" "false"

echo "case --config:"
fresh
cat > "$WORK/cfg.json" <<EOF
{"registry":"$WORK/boards.txt","cluster_map":"$MAP","state_file":"$DS","health_state_file":"$HS",
 "common":{"kanban":["alpha=$WORK/kanban"],"hub":["alpha=crew"]},
 "brief":{"poster":"$WORK/poster","incidents":["alpha=$WORK/incidents"],"decisions_only":["beta"]},
 "health":{"every_days":3}}
EOF
FAKE_CARDS="$CLEAN" python3 "$BRIEF" run --config "$WORK/cfg.json" --now "$NOW" 2>"$WORK/run.err"
eq "a config file alone runs the brief" "$(npost)" "1"
eq "decisions_only came from the file" "$(jq -r '.brief.last_run | keys | join(",")' "$HS")" "alpha,beta"
fresh
DWARVES_BOARD_CONFIG="$WORK/cfg.json" FAKE_CARDS="$CLEAN" python3 "$BRIEF" run --now "$NOW" --cluster alpha 2>/dev/null
eq "the env var names the file" "$(npost)" "1"
DWARVES_BOARD_CONFIG="$WORK/cfg.json" FAKE_CARDS="$CLEAN" python3 "$BRIEF" run --now "$NOW" --cluster alpha --force --dry-run | jq -r '.cluster' > "$WORK/c.out"
eq "command-line flags come after the file" "$(cat "$WORK/c.out")" "alpha"
fresh
mkdir -p "$HOME/.config/dwarves-kit"; cp "$WORK/cfg.json" "$HOME/.config/dwarves-kit/board.json"
FAKE_CARDS="$CLEAN" python3 "$BRIEF" run --now "$NOW" --cluster alpha 2>/dev/null
eq "the default path is read when it exists" "$(npost)" "1"
fresh
out="$(DWARVES_BOARD_CONFIG="$WORK/cfg.json" python3 "$HEALTH" run --now "$NOW" --force --dry-run 2>/dev/null)"
eq "board health reads the same file (its own section)" "$(printf '%s\n' "$out" | jq -r '.kind' | sort -u)" "health"
command rm -f "$HOME/.config/dwarves-kit/board.json"
echo '{oops' > "$WORK/bad.json"
python3 "$BRIEF" run --config "$WORK/bad.json" --now "$NOW" 2>"$WORK/bad.err"; rc=$?
[ "$rc" -ne 0 ]; eq "a bad config file is an error" "$?" "0"
has "naming the file" "$(cat "$WORK/bad.err")" "cannot read config"
python3 "$BRIEF" run --config 2>"$WORK/bad.err"; rc=$?
[ "$rc" -ne 0 ]; eq "--config without a file is an error" "$?" "0"

echo "case verb:"
out="$("$BOARD" brief run --help 2>&1)"
has "board brief run --help" "$out" "--incidents"

echo
echo "board-brief: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
