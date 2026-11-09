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
#   AC13 no duplicate rows: a decision row is not an incident row; an emptied block is dropped
#   AC14 boards: count line and triage warning are one line, with up to 3 card titles (40 chars)
#   AC15 healthy sync and bots are one line; any error keeps two; Details drops the archived count
#   AC16 a hook line that opens with the pointing hand is a decision, every day; other hook lines stay in Boards
#   AC17 Your call: incident decision rows use their action, hook 👉 lines, board triage past its
#        threshold; the cap counts the merged list and the overflow is a +N more line
#   AC18 one Handled line: hook 🤖 fragments, open incidents, sync and bots state
#   AC19 clear day: ✅ heading, the Handled line, nothing else
#   AC20 Details: Mondays (VN) only, with the board lines, hook info lines and incident stats;
#        other days only when an error exists
#   AC21 severity warn only for Your call or an error; footer_tail only on Mondays
#   AC12 formatting: small headings, a blank line between sections, ids as masked links with the
#        preview suppressed (inline code with no URL), the question in bold, hosts in inline code,
#        the main message kept under --main-chars
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'command rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export HOME="$WORK/home"; mkdir -p "$HOME"
# The data-path resolver honors these; a real host sets them, so pin them to the temp HOME.
unset XDG_STATE_HOME XDG_CACHE_HOME XDG_CONFIG_HOME KIT_DATA_ROOT
export KIT_CONFIG_OPERATOR="$HOME/.config/dwarves-kit"
unset DWARVES_BOARD_CONFIG
NOW=1790000000
# local calendar day of an epoch: BSD `date -r <epoch>` first, GNU `date -d @<epoch>` second
# (on GNU, `-r` takes a FILE, so the BSD form errors and the fallback runs)
epoch_day() { date -r "$1" +%Y-%m-%d 2>/dev/null || date -d "@$1" +%Y-%m-%d; }
DAY=86400
# NOW is a Monday in Vietnam (UTC+7), so the weekly Details ride it; TUE is the day after
TUE=$((NOW + DAY)); NEXTMON=$((NOW + 7 * DAY))

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

# a GitHub origin, so a board row id links to its line
git -C "$WORK/crew" remote add origin git@github.com:acme/crew.git
git -C "$WORK/crew" update-ref refs/remotes/origin/main HEAD
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
  SIDE=''
  [ -n "${FAKE_SIDE:-}" ] && SIDE=',{"slug":"side","archived":false,"counts":{"triage":1}}'
  cat <<JSON
[{"slug":"work","archived":false,"counts":{"triage":2,"ready":1,"done":4,"archived":${FAKE_ARCHIVED:-5}}},
 {"slug":"crew","archived":false,"counts":{"ready":4}}${SIDE}]
JSON
elif [ "$2" = "side" ]; then
  printf '[{"id":"s","title":"untrusted Side board card","status":"triage","created_at":%s}]' "$((FAKE_NOW - 6 * 86400))"
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
  T='"title":"Fix the long running sync problem on the notion bridge",'; U='"title":"Y",'; V='"title":"Fine",'
  [ -n "${FAKE_NO_TITLES:-}" ] && { T=''; U=''; V=''; }
  cat <<JSON
[{"id":"a",$T"status":"triage","created_at":$((FAKE_NOW - 3 * 86400))},
 {"id":"c",$U"status":"triage","created_at":$((FAKE_NOW - 2 * 86400))},
 {"id":"b",$V"status":"ready","created_at":$((FAKE_NOW - 1 * 86400))}]
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

# operator line hook stub: prints $FAKE_LINES, one line per row
cat > "$WORK/linehook" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_LINES:-}" ] && printf '%s\n' "$FAKE_LINES"
exit 0
EOF
chmod +x "$WORK/linehook"

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
    --board alpha=work --incidents "alpha=$WORK/incidents" --line "alpha=$WORK/linehook" --now "$now" "$@" 2>"$WORK/run.err"
}
last() { tail -n 1 "$FAKE_POSTED"; }
npost() { grep -c . "$FAKE_POSTED"; }
msg() { jq -r '[.fields[].value] | join("\n")' <<<"$(last)"; }
det() { jq -r '(.details // []) | join("\n")' <<<"$(last)"; }

echo "case decisions (hub/mirror drift, one question per row):"
fresh
run "$NOW" --cluster alpha
has "the shipped row with an open card is a question" "$(msg)" "[AB-4](<https://github.com/acme/crew/blob/main/_meta/BACKLOG.md?plain=1#L6>) hub/mirror drift: board says shipped, the Hermes card is still open. **Ship or reopen?**"
has "the lede counts the items" "$(msg)" "▌ One thing waits on you today"
eq "a decision makes the payload warn" "$(jq -r '.severity' <<<"$(last)")" "warn"
eq "and flags attention" "$(jq -r '.attention' <<<"$(last)")" "true"
fresh
FAKE_CARDS="AB-1:ready,AB-2:done,AB-4:done" run "$NOW" --cluster alpha
has "a done card on a live row is a question" "$(msg)" "[AB-2](<https://github.com/acme/crew/blob/main/_meta/BACKLOG.md?plain=1#L4>) hub/mirror drift: the Hermes card is done, the board says executing. **Ship or reopen?**"
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
has "the lede counts the whole list" "$(msg)" "▌ 4 things wait on you today"
eq "three lines and the +N more line show in the message" "$(jq -r '[.fields[] | select(.name == "decision")] | length' <<<"$(last)")" "4"
has "the rest is named as a count, in the Your call block" "$(msg)" "+1 more"
lacks "and is never moved to the details" "$(det)" "alpha three"
lacks "nor does the old pointer remain" "$(msg)" "more in details"

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
has "open non-decision incidents are one count in the Handled line" "$(msg)" "5 incidents are with chonky."
lacks "no Open incidents block" "$(msg)" "Open incidents"
lacks "and no incident rows in the body" "$(msg)" "gateway-run-crit"
has "an explicit hook decision is a decision" "$(msg)" "\`fixbox\` **Retry the failed job?**"
has "the hook's fault line is an error line in Details" "$(det)" "⚠️ auditor: violations 2"
has "and the Handled line marks the feed" "$(msg)" "the incident feed reported 1 fault."
has "hook details ride the weekly Details" "$(det)" "AI spend 24h: 1.20 USD"
has "the bot counts ride the weekly Details, zeros dropped" "$(det)" "🤖 bots: auto-resolved 3, parked 2"
lacks "the old two-line bots heading is gone" "$(msg)" "### 🤖 Bots"

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
{"open":[{"id":"t1","label":"hermes_state_registry-crit @ `hermes-personal`","needs_you":true},
         {"id":"t2","label":"leak 0123456789abcdef0123456789abcdef0123 op://Vault/item/field https://discord.com/api/webhooks/1/abc","needs_you":true}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a long rule name is not masked" "$(msg)" "hermes_state_registry-crit @ \`hermes-personal\`"
has "hex runs are masked" "$(msg)" "leak [redacted]"
has "secret references are masked" "$(msg)" "[ref-redacted]"
has "webhook URLs are masked" "$(msg)" "[webhook-redacted]"
fresh
FAKE_LINES="🤖 closed 1 website chat ([memo.d.foundation, 15 days](<https://discord.com/channels/462663954813157376/1562522344654901299>)) token QWxhZGRpbjpvcGVuIHNlc2FtZQQWxhZGRpbjpvcGVuIHNlc2FtZQ." FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a Discord channel link in a hook line is kept whole" "$(msg)" "(<https://discord.com/channels/462663954813157376/1562522344654901299>)"
has "a base64 run beside it is still masked" "$(msg)" "token [redacted]"

echo "case formatting (headings, blank lines, links, bold question, code hosts):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t_96178862","label":"hermes_state_registry-crit","host":"hermes-personal","age":"1d ago","needs_you":true,
          "url":"https://hermes.example/kanban?task=t_96178862","question":"new alert kind, triage or add a rule. Act or close?"},
         {"id":"t_ec9c213b","label":"heartbeat-silent @ restic-backup","age":"2d ago","needs_you":true,"url":"https://hermes.example/kanban?task=t_ec9c213b"},
         {"id":"t_bad","label":"x","host":"h","needs_you":true,"url":"http://plain.example/x"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
text="$(msg)"
has "the header is bold, with no count" "$text" "**🙋 Your call**"
has "a decision follows its header with no blank line" "$text" $'**🙋 Your call**\n• [t_96178862]'
has "the Handled line follows the items after a blank line" "$text" $'\n\n▌ Handled by bots: '
lacks "no heading below the first" "$(printf '%s' "$text" | tail -n +2)" "### "
has "a ticket id is a masked link with the preview suppressed" "$text" "[t_96178862](<https://hermes.example/kanban?task=t_96178862>)"
has "the decision question is bold" "$text" "**Act or close?**"
has "the host after @ is inline code" "$text" "hermes_state_registry-crit @ \`hermes-personal\`"
has "a host inside a legacy label is inline code too" "$text" "heartbeat-silent @ \`restic-backup\`"
has "an http URL is refused: the id is inline code" "$text" "\`t_bad\`"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t_inj","label":"y","host":"h","needs_you":true,"url":"https://ok.example/x)[evil](https://evil.example"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a URL carrying markup characters is refused" "$(msg)" "\`t_inj\`"
lacks "no forged link survives" "$(msg)" "evil"
lacks "no bare URL is left to unfurl" "$(msg)" " https://"
has "the healthy sync and bots state is in the Handled line" "$(msg)" "Handled by bots: sync and bots ran clean."
git -C "$WORK/crew" remote set-url origin /srv/local/crew.git
fresh
run "$NOW" --cluster alpha
has "a board that is not on GitHub: the row id is inline code" "$(msg)" "\`AB-4\` hub/mirror drift"
git -C "$WORK/crew" remote set-url origin git@github.com:acme/crew.git
fresh
echo '{"crew":{"pending":{"flapping_ids":["AB-1"]}}}' > "$DS"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --show-boards
has "an id in a flapping line links to its row" "$(det)" "⚠️ [AB-1](<https://github.com/acme/crew/blob/main/_meta/BACKLOG.md?plain=1#L3>) flapping between the board and a spoke (crew)"
echo '{}' > "$DS"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "a clean weekday: the Handled line carries sync and bots, no heading" "$(msg)" "Handled by bots: sync and bots ran clean."
lacks "and no bots heading" "$(msg)" "### 🤖 Bots"
lacks "and no sync heading" "$(msg)" "### 🔄 Sync"
eq "and no Details field at all" "$(jq -r 'has("details")' <<<"$(last)")" "false"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
text="$(det)"
has "the Monday details open with the Details heading" "$text" "### ℹ️ Details"
[[ "$text" == "### ℹ️ Details"* ]] && ok "and it leads" || bad "details rhythm: $text"
eq "one heading only" "$(printf '%s' "$text" | grep -c '^### ')" "1"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"a","label":"one","age":"1d","needs_you":true},{"id":"b","label":"two","age":"2d","needs_you":true},{"id":"c","label":"three","age":"3d","needs_you":true}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --main-chars 100
has "over the budget the rows past the first collapse to +N more" "$(msg)" "+2 more"
has "the lede still counts all of them" "$(msg)" "▌ Three things wait on you today"
lacks "and nothing moves to the details" "$(det)" "three"

echo "case no duplicate rows (a decision row is not an incident row):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"question":"Fix or close?"},
         {"id":"t2","label":"alpha two","age":"1d ago"},{"id":"t3","label":"alpha three"}],
 "decisions":[{"id":"t3","question":"Retry?"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "the decision row stays a decision" "$(msg)" "\`t1\` alpha one: **Fix or close?**"
has "the Handled count skips rows already asked about" "$(msg)" "1 incident is with chonky."
lacks "the other row is not listed in the body" "$(msg)" "alpha two"
eq "the decision row appears once" "$(msg | grep -cF '`t1`')" "1"
eq "a hook decision id appears once too" "$(msg | grep -cF '`t3`')" "1"
eq "the payload still counts every open row" "$(jq -r '.data.open_incidents' <<<"$(last)")" "3"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"question":"Fix or close?"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
lacks "every row a decision: no incident count" "$(msg)" "with chonky"
has "and the decision shows" "$(msg)" "**🙋 Your call**"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"question":"Fix or close?"}],"faults":["auditor: violations 2"]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a feed fault is marked in the Handled line" "$(msg)" "the incident feed reported 1 fault."
has "and its line rides the Details" "$(det)" "⚠️ auditor: violations 2"
lacks "there is no incident feed block" "$(msg)" "Incident feed"

echo "case boards (count line and triage warning are one line, with card titles):"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "no warning: one short count line in the Monday Details" "$(det)" "🗂️ work: 3 open (triage 2, ready 1)"
lacks "and not in the body" "$(msg)" "🗂️ work"
lacks "and no stale count at zero" "$(det)" "0 stale"
lacks "and no Triage action while under the threshold" "$(msg)" "Triage"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force --triage-days 2 --stale-days 2
has "a board past its triage threshold is a Your call item, two titles" "$(msg)" 'oldest: "Fix the long running sync problem on th…", "Y". **move each card to ready, blocked or done.**'
has "the item sits under the Your call header" "$(msg)" "**🙋 Your call**"
eq "the triage action is a decision in the data" "$(jq -r '.data.decisions | length' <<<"$(last)")" "1"
eq "so the card warns and flags attention" "$(jq -r '[.severity, .attention] | join(" ")' <<<"$(last)")" "warn true"
lacks "the separate waiting line is gone" "$(msg)" "waiting in triage"
has "the Monday Details keep the count line with the warning folded in" "$(det)" '⚠️ work: 3 open (triage 2 oldest 3d, ready 1) · stale: "Fix the long running sync problem on th…"'
FAKE_NO_TITLES=1 FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force --triage-days 2 --stale-days 2
has "a reader with no titles: the item has none" "$(msg)" "2 cards wait in work triage"
lacks "and no empty quotes" "$(msg)" '""'
has "and the Details show the stale count" "$(det)" "⚠️ work: 3 open (triage 2 oldest 3d, ready 1) · 1 stale"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force --triage-days 2 --stale-days 20
has "triage titles when nothing is stale" "$(msg)" 'oldest: "Fix the long running sync problem on th…", "Y".'
has "the Details list triage cards when nothing is stale" "$(det)" '· triage: "Fix the long running sync problem on th…", "Y"'
eq "every title is 40 chars or fewer" "$( (msg; det) | grep -o '"[^"]*"' | jq -R 'select(length - 2 > 40)' | grep -c .)" "0"

echo "case sync and bots (one healthy line; any error keeps two; Details):"
fresh
FAKE_ARCHIVED=5 FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
FAKE_ARCHIVED=11 FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "the healthy state is one Handled line" "$(msg | grep -c '^▌ Handled by bots: sync and bots ran clean\.$')" "1"
lacks "a weekday does not repeat the archived count" "$(msg)" "archived"
FAKE_ARCHIVED=17 FAKE_CARDS="$CLEAN" run $NEXTMON --cluster alpha
has "the weekly Details carry the archived count" "$(det)" "🤖 bots: archived 6"
fresh
echo '{"details":["AI spend 24h: 1.20 USD"]}' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run $NEXTMON --cluster alpha
has "the details field is named Details" "$(det)" "### ℹ️ Details"
lacks "and not More" "$(det)" "### ℹ️ More"
eq "a clean day is severity info" "$(jq -r '.severity' <<<"$(last)")" "info"
fresh
echo '{"details":["AI spend 24h: 1.20 USD"]}' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "a weekday has no Details field, hook stats included" "$(jq -r 'has("details")' <<<"$(last)")" "false"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
FAKE_SYNC_RC=1 FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "a sync error is in the Handled line" "$(msg)" "Handled by bots: sync hit 1 error."
lacks "and there is no collapsed healthy line" "$(msg)" "sync and bots clean"
lacks "and no Sync heading" "$(msg)" "### 🔄 Sync"
has "a weekday with an error shows Details with the error line" "$(det)" "❌ sync failed: crew"
eq "and the Details hold the error lines only" "$(det | grep -c '🗂️')" "0"
eq "a sync error makes the card warn" "$(jq -r '.severity' <<<"$(last)")" "warn"
lacks "and the clear lede is gone" "$(msg)" "Nothing waits on you"

echo "case hook lines (👉 is Your call, 🤖 is Handled, other lines are Monday Details):"
fresh
FAKE_LINES="👉 desks: 42 turns on 4 of 6 · 2 need you: R-14 open 2d: keep task deadlines (followup-track) (details in Desk self-review)" FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
FAKE_LINES="👉 desks: 42 turns on 4 of 6 · 2 need you: R-14 open 2d: keep task deadlines (followup-track) (details in Desk self-review)" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "the line is under Your call in the main message" "$(msg)" "**🙋 Your call**"
has "the line shows under the head, without the marker" "$(msg)" "• desks: 42 turns on 4 of 6 · 2 need you: R-14 open 2d"
lacks "the marker itself is not repeated" "$(msg)" "👉"
lacks "and the boards stay out of the body" "$(msg)" "🗂️ crew"
lacks "and it is not in the details" "$(det)" "desks:"
eq "the card warns and flags attention" "$(jq -r '[.severity, .attention] | join(" ")' <<<"$(last)")" "warn true"
eq "the data lists it" "$(jq -r '.data.decisions | length' <<<"$(last)")" "1"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"question":"Fix or close?"}]}
EOF
FAKE_LINES="👉 desks: 1 needs you" FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "after the incident decisions, counted in the lede" "$(msg)" "▌ Two things wait on you today"
eq "the incident decision comes first" "$(msg | grep -n -e 'alpha one' -e 'desks: 1' | cut -d: -f1 | tr '\n' ' ')" "4 5 "
fresh
FAKE_LINES="💼 desks: 42 turns on 4 of 6, all clear" FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "an info line rides the Monday Details" "$(det)" "💼 desks: 42 turns on 4 of 6, all clear"
lacks "and not the body" "$(msg)" "💼"
has "and nothing needs you" "$(msg)" "▌ Nothing waits on you today."
FAKE_LINES="💼 desks: 42 turns on 4 of 6, all clear" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "on a weekday an info line is dropped: no Details" "$(jq -r 'has("details")' <<<"$(last)")" "false"
fresh
FAKE_LINES=$'🤖 neko-chief tool error filed as `t_abcd`\n🤖 +2 agent faults' FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "hook 🤖 fragments join ONE Handled line, marker dropped" "$(msg)" '▌ Handled by bots: neko-chief tool error filed as `t_abcd`. +2 agent faults. sync and bots ran clean.'
eq "one Handled line" "$(msg | grep -c 'Handled')" "1"
has "a Handled-only day is still a clear day" "$(msg)" "▌ Nothing waits on you today."
eq "and info severity" "$(jq -r '.severity' <<<"$(last)")" "info"
fresh
echo '{"open":[{"id":"a","label":"one"},{"id":"b","label":"two"}]}' > "$FAKE_INC_FILE"
FAKE_LINES="🤖 desk fix filed" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "Handled order: hook fragments, incidents, sync" "$(msg)" "Handled by bots: desk fix filed. 2 incidents are with chonky. sync and bots ran clean."
fresh
FAKE_LINES=$'👉 Review brainery [#457](<https://x.example/457>) by Sun 8 Nov, or it parks (4 drafts waiting)\n💼 info' FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "a 👉 draft line keeps its link" "$(msg)" "• Review brainery [#457](<https://x.example/457>) by Sun 8 Nov, or it parks (4 drafts waiting)"
fresh
FAKE_LINES="👉 desks: 1 needs you" FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --decisions-only alpha
eq "decisions-only posts it" "$(npost)" "1"

echo "case hook failure is a fault, never an all-clear:"
fresh
FAKE_INC_FAIL=1 FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "an exit failure shows as a fault in the Handled line" "$(msg)" "the incident feed was unreadable."
has "with the reason in the Details, even on a weekday" "$(det)" "⚠️ incident feed unreadable: feed exploded"
lacks "and no all-clear line" "$(msg)" "Nothing waits on you"
eq "and the card warns" "$(jq -r '.severity' <<<"$(last)")" "warn"
fresh
FAKE_INC_FAIL=1 FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "a weekday keeps the error line in Details" "$(det)" "⚠️ incident feed unreadable: feed exploded"
fresh
echo 'not json' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "malformed output is a fault" "$(det)" "⚠️ incident feed unreadable: hook printed no JSON"
echo '[1,2]' > "$FAKE_INC_FILE"
fresh; echo '[1,2]' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "a non-object is a fault" "$(det)" "hook JSON is not an object"

echo "case all clear and --decisions-only:"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "no decision: the all-clear lede" "$(msg)" "▌ Nothing waits on you today. The bots handled everything."
lacks "and no decision head" "$(msg)" "🙋"
eq "severity info" "$(jq -r '.severity' <<<"$(last)")" "info"
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "a clear weekday is the all-clear lede, a gap and the Handled line" "$(jq -r '[.fields[].value] | length' <<<"$(last)")" "3"
eq "the first is the all-clear" "$(jq -r '.fields[0].value' <<<"$(last)")" "▌ Nothing waits on you today. The bots handled everything."
eq "the third is Handled" "$(jq -r '.fields[2].value' <<<"$(last)")" "▌ Handled by bots: sync and bots ran clean."
eq "no Details on a clear weekday" "$(jq -r 'has("details")' <<<"$(last)")" "false"
eq "info severity, no attention" "$(jq -r '[.severity, .attention] | join(" ")' <<<"$(last)")" "info false"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --decisions-only alpha
eq "decisions-only posts nothing when clean" "$(npost)" "0"
eq "but stamps the run" "$(jq -r '.brief.last_run.alpha' "$HS")" "$NOW"
fresh
run "$NOW" --cluster alpha --decisions-only alpha
eq "decisions-only posts when a decision exists" "$(npost)" "1"
eq "and the message is the decision lines alone" "$(jq -r '[.fields[].name] | unique | join(",")' <<<"$(last)")" "decision,decision-head"

echo "case weekly Details (Mondays in Vietnam; a decision or --show-boards does not change the day):"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "Monday: the hub line is in the Details" "$(det)" "🗂️ crew: 3 active, 1 parked · Hermes mirror 4 open = hub ✅"
lacks "and not in the body" "$(msg)" "🗂️ crew"
eq "the footer tail applies on Monday" "$(jq -r '.footer_tail' <<<"$(last)")" "true"
eq "boards_shown follows the weekly Details" "$(jq -r '.data.boards_shown' <<<"$(last)")" "true"
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "Tuesday: no Details field" "$(jq -r 'has("details")' <<<"$(last)")" "false"
eq "and no footer tail" "$(jq -r '.footer_tail' <<<"$(last)")" "false"
eq "boards_shown is false" "$(jq -r '.data.boards_shown' <<<"$(last)")" "false"
FAKE_CARDS="$CLEAN" run $((NOW + 3 * DAY)) --cluster alpha
eq "Thursday: none either, the old three-day clock is gone" "$(jq -r 'has("details")' <<<"$(last)")" "false"
run $((NOW + 5 * DAY)) --cluster alpha
eq "a decision day that is not Monday has no Details" "$(jq -r 'has("details")' <<<"$(last)")" "false"
FAKE_CARDS="$CLEAN" run $NEXTMON --cluster alpha
has "next Monday the Details are back" "$(det)" "🗂️ crew: 3 active, 1 parked"
FAKE_CARDS="$CLEAN" run $((NEXTMON + DAY)) --cluster alpha --show-boards
has "--show-boards forces the weekly Details (a preview)" "$(det)" "🗂️ crew"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
FAKE_SYNC_RC=1 FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
lacks "a sync fault does not bring the boards back" "$(det)" "🗂️ crew"
has "the Handled line counts it" "$(msg)" "sync hit 1 error."
has "and the Details name it" "$(det)" "❌ sync failed: crew"

echo "case bots (archived since the last brief, sync errors):"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "baseline: the healthy Handled line" "$(msg)" "Handled by bots: sync and bots ran clean."
FAKE_ARCHIVED=17 FAKE_CARDS="$CLEAN" run $NEXTMON --cluster alpha
has "archived since the last brief rides the weekly Details" "$(det)" "🤖 bots: archived 12"
lacks "and not the body" "$(msg)" "archived"
FAKE_SYNC_RC=1 FAKE_ARCHIVED=17 FAKE_CARDS="$CLEAN" run $((NEXTMON + DAY)) --cluster alpha
has "a failed leg counts" "$(msg)" "sync hit 1 error."

echo "case Your call (action rows, the merged list, the cap):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"hb-silent @ box","host":"","needs_you":true,"action":"Close","url":"https://hermes.example/t1","question":"fired 3x · quiet 5d, close?"},
         {"id":"t2","label":"alpha two","needs_you":true,"action":"Triage or map","question":"fired 3x, quiet 5h · new alert kind: map it or close"},
         {"id":"t3","label":"alpha three","needs_you":true,"action":"Triage or map","question":"fired 9x, quiet 2d"}]}
EOF
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "form a (quiet 3d or more): tag from the quiet days, host from the label" "$(msg)" $'• `[quiet 5d]` [t1 hb-silent](<https://hermes.example/t1>)\nfired 3x on box. **close the ticket.**'
has "form b (recent): the hint is cut, the colon in it is harmless" "$(msg)" $'• `[quiet 5h]` `t2` alpha two\nfired 3x'
has "a row with only fired and quiet facts" "$(msg)" $'• `[quiet 2d]` `t3` alpha three\nfired 9x'
lacks "an action row has no bold question" "$(msg)" "Act or close"
has "the lede counts the rows" "$(msg)" "▌ Three things wait on you today"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t4","label":"alpha four","needs_you":true,"question":"new alert kind. Act or close?"},
         {"id":"t5","label":"alpha five","needs_you":true,"action":"Close","question":"new alert kind, triage or add a rule. Act or close?"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "no action: today's rendering with the bold question" "$(msg)" "\`t4\` alpha four: new alert kind. **Act or close?**"
has "form c (no ticket body): no tag, no facts, just the instruction" "$(msg)" $'• `t5` alpha five\n**close the ticket.** ignored, it stays open and keeps showing here.'
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t6","label":"alpha six","needs_you":true,"action":"Close this one with a very long action text past the cap","question":"fired 1x, quiet 4d"}]}
EOF
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha
has "an action is cut to 40 chars" "$(msg)" "**close this one with a very long action t.**"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"action":"Close","question":"fired 3x, quiet 5d"}],
 "decisions":[{"id":"fixbox","question":"Retry the failed job?"}]}
EOF
FAKE_LINES="👉 Review brainery [#9](<https://x.example/9>) by Sun 8 Nov, or it parks (2 drafts waiting)" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force --triage-days 2 --stale-days 2
eq "incident, hook decision, 👉 line and triage action are one merged list of 4" "$(jq -r '.data.decisions | length' <<<"$(last)")" "4"
has "counted in one lede" "$(msg)" "▌ 4 things wait on you today"
has "the cap holds at three lines plus +N more" "$(msg)" "+1 more"
lacks "the +N more line is not a Details block" "$(det)" "Triage"
order=""; for pat in 'Review brainery' '[quiet 5d]' 'fixbox'; do order="$order$(msg | grep -n -F -- "$pat" | head -n 1 | cut -d: -f1) "; done
eq "the order is the dated 👉, incident, hook decision; the triage item is cut" "$order" "4 5 7 "
lacks "the cap dropped the triage item" "$(msg)" "cards wait in work triage"

echo "case Your call order (urgency first; the cap cuts the least urgent):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"alpha one","needs_you":true,"action":"Close","question":"fired 3x, quiet 5d"},
         {"id":"t2","label":"alpha two","needs_you":true,"action":"Triage or map","question":"fired 1x, quiet 1d"}],
 "decisions":[{"id":"fixbox","question":"Retry the failed job?"}]}
EOF
cat > "$WORK/links.json" <<EOF
{"links":[{"label":"chief","home":"$WORK/nohome","profile":"p","cluster":"alpha","skills_dir":"$WORK/noskills"}]}
EOF
LINES_IN=$'👉 Review brainery [#9](<https://x.example/9>) by Sun 8 Nov, or it parks (2 drafts waiting)\n👉 desks: 1 needs you\n👉 Review brainery [#7](<https://x.example/7>) by Fri 6 Nov, or it parks (1 drafts waiting)'
FAKE_SIDE=1 DWARVES_HERMES_LINKS="$WORK/links.json" FAKE_LINES="$LINES_IN" run $TUE --cluster alpha --triage-days 1 --stale-days 20
decs="$(jq -r '.data.decisions[]' <<<"$(last)")"
order=""
for pat in '#7' '#9' 'triage it or add a rule' 'close the ticket' 'fixbox' 'desks: 1' 'hub/mirror drift' 'in side triage' 'in work triage' 'kit skills on'; do
  order="$order$(printf '%s\n' "$decs" | grep -n -F -- "$pat" | head -n 1 | cut -d: -f1) "
done
eq "dated 👉 (nearest first), Triage or map, Close, hook decision, other 👉, drift, triage by wait, stale skills" "$order" "1 2 3 4 5 6 7 8 9 10 "
has "the lede counts all ten" "$(msg)" "▌ 10 things wait on you today"
has "the cap shows the most urgent three" "$(msg)" "• Review brainery [#7]"
has "and names the rest as a count" "$(msg)" "+7 more"
lacks "the cap dropped the least urgent from the body" "$(msg)" "kit skills on"
lacks "and Close is below the cap" "$(msg)" "close the ticket"
has "triage titles drop the untrusted marker" "$decs" '1 card waits in side triage "Side board card". **move the card'
lacks "no untrusted marker in any Your call line" "$decs" "untrusted"
FAKE_SIDE=1 FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force --triage-days 1 --stale-days 1
lacks "nor in the Details board lines" "$(det)" "untrusted"
eq "the health payload still carries the raw title" "$(FAKE_SIDE=1 python3 "$HEALTH" run --registry "$WORK/boards.txt" --cluster-map "$MAP" --state-file "$DS" --health-state-file "$HS" --kanban "alpha=$WORK/kanban" --hub alpha=crew --board alpha=side --now "$TUE" --force --dry-run 2>/dev/null | jq -r 'select(.cluster == "alpha") | .data.kanban.side.cards[0].title')" "untrusted Side board card"

echo "case editorial layout (lede, Your call header, Handled sentence line, clear day):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"a","label":"one"},{"id":"b","label":"two"}]}
EOF
DUE=$((TUE + 3600))
L1='👉 {"tag":"20:00 today","title":"Draft #457: A topic-first loop","url":"https://github.com/dwarvesf/brainery/pull/457","lines":["a content-desk draft, waiting 14 days. **merge the PR to publish it on memo.** do nothing and it parks tonight.","3 more drafts wait."],"lede":"a memo draft that parks tonight","due":'"$DUE"',"wait_days":14}'
L2='🤖 closed 2 website chats where the visitor left no email ([memo.d.foundation, 16 days](<https://discord.com/channels/1/2>))'
L3='🤖 neko-chief tool error filed as `t_xxxx`'
FAKE_LINES="$(printf '%s\n%s\n%s' "$L1" "$L2" "$L3")" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
want=$'▌ One thing waits on you today: a memo draft that parks tonight. The bots handled the rest.\n\n**🙋 Your call**\n• `[20:00 today]` [Draft #457: A topic-first loop](<https://github.com/dwarvesf/brainery/pull/457>)\na content-desk draft, waiting 14 days. **merge the PR to publish it on memo.** do nothing and it parks tonight.\n3 more drafts wait.\n\n▌ Handled by bots: closed 2 website chats where the visitor left no email ([memo.d.foundation, 16 days](<https://discord.com/channels/1/2>)). neko-chief tool error filed as `t_xxxx`. 2 incidents are with chonky. sync and bots ran clean.'
eq "the approved layout, exactly" "$(msg)" "$want"
eq "the header carries no count" "$(msg | grep -c '^\*\*🙋 Your call\*\*$')" "1"
eq "the data still counts the items" "$(jq -r '.data.decisions | length' <<<"$(last)")" "1"
eq "the payload names the date and the next brief for the poster" "$(jq -r '[.date_label, .next_due_label] | join("|")' <<<"$(last)")" "Tue 22 Sep|Wed 23 Sep"
fresh
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "clear day: the lede, then the Handled line" "$(msg)" $'▌ Nothing waits on you today. The bots handled everything.\n\n▌ Handled by bots: sync and bots ran clean.'
eq "and info severity" "$(jq -r '.severity' <<<"$(last)")" "info"
fresh
FAKE_LINES="🤖 desk fix filed. already closed." FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "a fragment that already ends in a period keeps one" "$(msg)" "desk fix filed. already closed. sync and bots ran clean."
FAKE_LINES="🤖 one fragment" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force
has "a fragment without a period gets one" "$(msg)" "one fragment. sync and bots ran clean."
echo '{"open":[{"id":"a","label":"one"}]}' > "$FAKE_INC_FILE"
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force
has "one open incident is singular" "$(msg)" "1 incident is with chonky."
FAKE_SYNC_RC=1 FAKE_CARDS="$CLEAN" run $((TUE + DAY)) --cluster alpha
has "a sync error is a Handled sentence" "$(msg)" "sync hit 1 error."
lacks "and the clear form is not claimed" "$(msg)" "Nothing waits on you today. The bots handled everything"

echo "case lede (count words, up to two phrases, and N more):"
fresh
mk() { printf '👉 {"tag":"t","title":"%s","lines":["x"]%s}' "$1" "$2"; }
FAKE_LINES="$(mk A ',"lede":"a first thing","due":1900000001'; echo; mk B ',"lede":"a second thing","due":1900000002'; echo; mk C ',"wait_days":5'; echo; mk D ',"lede":"a fourth thing"')" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "four items, two phrases, the rest counted" "$(msg)" "▌ 4 things wait on you today: a first thing, a second thing and 2 more. The bots handled the rest."
fresh
FAKE_LINES="$(mk A ',"lede":"a first thing","due":1900000001'; echo; mk C ',"wait_days":5')" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "two items, one phrase" "$(msg)" "▌ Two things wait on you today: a first thing and 1 more. The bots handled the rest."
fresh
FAKE_LINES="$(mk A ',"wait_days":1'; echo; mk C ',"wait_days":5'; echo; mk E '')" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "no lede at all: no colon" "$(msg)" "▌ Three things wait on you today. The bots handled the rest."
fresh
FAKE_LINES="$(mk A ',"lede":"a first thing"')" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "one item, one phrase" "$(msg)" "▌ One thing waits on you today: a first thing. The bots handled the rest."

echo "case structured 👉 items (C4: order, links, fallback):"
fresh
FAKE_LINES="$(mk Late ',"wait_days":3'; echo; mk Soon ',"due":1900000001'; echo; mk Wait ',"wait_days":30'; echo; mk Bare '')" FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
eq "due ascending, then wait_days descending, then the rest" "$(jq -r '.data.decisions[]' <<<"$(last)" | cut -c1-12 | tr '\n' '|')" "Soon x|Wait x|Late x|Bare x|"
fresh
FAKE_LINES='👉 {"tag":"t","title":"No url","lines":["l"]}' FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "no url: the title is plain" "$(msg)" $'• `[t]` No url\nl'
FAKE_LINES='👉 {"tag":"t","title":"Bad url","url":"http://plain.example/x","lines":["l"]}' FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force
has "an http url is refused: the title is plain" "$(msg)" '• `[t]` Bad url'
lacks "and no link" "$(msg)" "plain.example"
FAKE_LINES='👉 {not json at all' FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force
has "a 👉 line that is not JSON keeps the one-line rendering" "$(msg)" "• {not json at all"
FAKE_LINES='👉 plain review line' FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force
has "a plain 👉 line is one bullet" "$(msg)" "• plain review line"
lacks "with no tag" "$(msg)" '`['

echo "case kit items in the same shape (incident rows, board triage, drift):"
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t1","label":"hb-silent @ box","needs_you":true,"action":"Close","url":"https://hermes.example/t1","question":"fired 3x · quiet 5d, close?"},
         {"id":"t2","label":"alpha two","host":"hostb","needs_you":true,"action":"Triage or map","question":"fired 1x, quiet 1d · new alert kind"},
         {"id":"t3","label":"alpha three","host":"hostc","needs_you":true,"firing":true,"action":"Triage or map","question":"fired 4x"}]}
EOF
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
text="$(msg)"
has "a Close row: tag, linked id and label (host moved to the line)" "$text" $'• `[quiet 5d]` [t1 hb-silent](<https://hermes.example/t1>)\nfired 3x on box. **close the ticket.** ignored, it stays open and keeps showing here.'
has "a Triage or map row: id in code without a url" "$text" $'• `[quiet 1d]` `t2` alpha two\nfired 1x on hostb. **triage it or add a rule.** ignored, it stays open and keeps showing here.'
fresh
cat > "$FAKE_INC_FILE" <<'EOF'
{"open":[{"id":"t3","label":"alpha three","host":"hostc","needs_you":true,"firing":true,"action":"Triage or map","question":"fired 4x"},
         {"id":"t1","label":"hb-silent @ box","needs_you":true,"action":"Close","question":"fired 3x · quiet 5d, close?"}]}
EOF
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
has "a firing row is tagged firing" "$(msg)" '• `[firing]` `t3` alpha three'
has "the lede names a new alert kind and an alert to close" "$(msg)" "▌ Two things wait on you today: a new alert kind to triage and an alert to close. The bots handled the rest."
fresh
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha --force --triage-days 2 --stale-days 20
has "board triage: tag, count title" "$(msg)" $'• `[waiting 4d]` 2 cards wait in work triage'
has "with up to two quoted titles and the instruction" "$(msg)" $'oldest: "Fix the long running sync problem on th…", "Y". **move each card to ready, blocked or done.** ignored, they stay here daily.'
has "and its lede" "$(msg)" "▌ One thing waits on you today: 2 cards to triage. The bots handled the rest."
fresh
FAKE_CARDS="" run $TUE --cluster alpha
has "drift stays one plain line, no tag" "$(msg)" "• [AB-4](<https://github.com/acme/crew/blob/main/_meta/BACKLOG.md?plain=1#L6>) hub/mirror drift: board says shipped, the Hermes card is still open. **Ship or reopen?**"
lacks "and adds no lede phrase" "$(msg)" "today:"

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
eq "date and next due" "$(jq -r '[.date, .next_due] | join(" ")' <<<"$p")" "$(epoch_day "$NOW") $(epoch_day $((NOW + DAY)))"
eq "key is 32 hex" "$(jq -r '.key | test("^[0-9a-f]{32}$")' <<<"$p")" "true"
fresh
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha; k1="$(jq -r .key <<<"$(last)")"
FAKE_CARDS="$CLEAN" run "$NOW" --cluster alpha --force; k2="$(jq -r .key <<<"$(last)")"
eq "the key is stable within a day" "$k1" "$k2"
FAKE_CARDS="$CLEAN" run $((NOW + DAY)) --cluster alpha; k3="$(jq -r .key <<<"$(last)")"
[ "$k1" != "$k3" ]; eq "and changes the next day" "$?" "0"
fresh
FAKE_CARDS="$CLEAN" run $TUE --cluster alpha
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
