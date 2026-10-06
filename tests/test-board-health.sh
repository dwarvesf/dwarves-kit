#!/usr/bin/env bash
# test-board-health.sh -- lib/sync/sweep/board-health: the periodic board health
# digest, and its wiring into `board sweep --health`.
#
# Every board is a throwaway git repo, the kanban reader, the poster and the
# board command are stubs, and HOME is a scratch dir: no real board, no spoke,
# no network, no credential.
#
#   AC1  record: spokes, rc and errors from a sync's output; errors only on a failure
#   AC2  hubs: active, parked, and stale rows (git blame age), from the origin copy
#   AC3  kanban: open, stale, and archived-since-last-run from a reader command
#   AC4  cadence: due once, then quiet; --force; --dry-run and --no-state stamp nothing
#   AC5  quiet cluster: clean posts nothing but is stamped; a failed leg posts
#   AC6  a failed post stays due, rides carried_error next time, and clears on delivery
#   AC7  FLAPPING ids and a carried digest error from the digest state need attention
#   AC8  --line hook lines ride the payload; a failing hook never breaks the run
#   AC9  payload shape: kind health, stable key per day, one line per field
#   AC10 board sweep: records every leg; --health runs the leg; no --health, no leg;
#        --dry-run leaves the real health state alone
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HEALTH="$HERE/../lib/sync/sweep/board-health"
SWEEP="$HERE/../lib/sync/sweep/board-sweep"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got '$2', want '$3')"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
NOW=1790000000
DAY=86400

# commit <repo> <epoch> <message>: a commit dated at <epoch>
commit() {
  git -C "$1" add -A >/dev/null
  GIT_AUTHOR_DATE="@$2 +0000" GIT_COMMITTER_DATE="@$2 +0000" \
    git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$3"
}

# hub repo "crew": ID-1 changed 10 days ago (stale), ID-2 one day ago, ID-3 parked, ID-4 shipped
mkdir -p "$WORK/crew/_meta"
git -C "$WORK/crew" init -q -b main
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | old row | | queued |\n| AB-3 | waits | | parked [later] |\n| AB-4 | done | | shipped |\n' > "$WORK/crew/_meta/BACKLOG.md"
commit "$WORK/crew" $((NOW - 10 * DAY)) first
printf '| AB-2 | new row | | executing |\n' >> "$WORK/crew/_meta/BACKLOG.md"
commit "$WORK/crew" $((NOW - 1 * DAY)) second
# the same repo as a bare origin, so the origin copy is what gets read
git clone -q --bare "$WORK/crew" "$WORK/crew-origin.git"
git -C "$WORK/crew" remote add origin "$WORK/crew-origin.git"
git -C "$WORK/crew" fetch -q origin
git -C "$WORK/crew" remote set-head origin main >/dev/null 2>&1
# a working-tree edit that must NOT count when the origin copy is read
printf '| AB-9 | local only | | queued |\n' >> "$WORK/crew/_meta/BACKLOG.md"

# a second hub on another rail, no origin: blame falls back to the working copy
mkdir -p "$WORK/solo"
git -C "$WORK/solo" init -q -b main
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| SO-1 | one | | queued |\n' > "$WORK/solo/BACKLOG.md"
commit "$WORK/solo" $((NOW - 20 * DAY)) first

cat > "$WORK/boards.txt" <<EOF
crew  $WORK/crew/_meta/BACKLOG.md  on rail=crew
solo  $WORK/solo/BACKLOG.md        rail=pers
EOF
MAP="alpha=crew,beta=pers"

# the kanban reader stub: board "work" has 3 open cards (1 stale), "idle" none; archived 5
cat > "$WORK/kanban" <<'EOF'
#!/usr/bin/env bash
echo "kanban $*" >> "${FAKE_CALL_LOG:-/dev/null}"
[ -n "${FAKE_KANBAN_FAIL:-}" ] && { echo "reader exploded" >&2; exit 3; }
if [ "$1 $2" = "boards list" ]; then
  cat <<JSON
[{"slug":"work","archived":false,"counts":{"triage":2,"ready":1,"done":4,"archived":${FAKE_ARCHIVED:-5}}},
 {"slug":"idle","archived":false,"counts":{"done":2}},
 {"slug":"gone","archived":true,"counts":{"ready":9}}]
JSON
else
  cat <<JSON
[{"id":"a","status":"triage","created_at":$((FAKE_NOW - 12 * 86400)),"started_at":null,"completed_at":null},
 {"id":"b","status":"ready","created_at":$((FAKE_NOW - 12 * 86400)),"started_at":$((FAKE_NOW - 1 * 86400)),"completed_at":null},
 {"id":"c","status":"triage","created_at":$((FAKE_NOW - 2 * 86400)),"started_at":null,"completed_at":null},
 {"id":"d","status":"done","created_at":$((FAKE_NOW - 30 * 86400)),"started_at":null,"completed_at":null}]
JSON
fi
EOF
chmod +x "$WORK/kanban"
export FAKE_NOW="$NOW" FAKE_KANBAN_FAIL FAKE_ARCHIVED FAKE_CALL_LOG

cat > "$WORK/poster" <<'EOF'
#!/usr/bin/env bash
cat >> "$FAKE_POSTED"; echo >> "$FAKE_POSTED"
[ "${FAKE_POSTER_RC:-0}" -ne 0 ] && echo "${FAKE_POSTER_ERR:-fake poster failure}" >&2
exit "${FAKE_POSTER_RC:-0}"
EOF
chmod +x "$WORK/poster"
FAKE_POSTED="$WORK/posted.out"; FAKE_POSTER_RC=0; FAKE_POSTER_ERR=""; FAKE_KANBAN_FAIL=""; FAKE_ARCHIVED=5; FAKE_CALL_LOG="$WORK/calls.log"
export FAKE_POSTED FAKE_POSTER_RC FAKE_POSTER_ERR FAKE_KANBAN_FAIL FAKE_ARCHIVED FAKE_CALL_LOG

HS="$WORK/health.json"; DS="$WORK/digest.json"
echo '{}' > "$DS"
fresh() { command rm -f "$HS" "$FAKE_POSTED" 2>/dev/null; FAKE_POSTER_RC=0; FAKE_KANBAN_FAIL=""; FAKE_ARCHIVED=5; FAKE_POSTED="$WORK/posted.out"; : > "$FAKE_POSTED"; }
rec() {  # rec <repo> <rc> <now> < output
  python3 "$HEALTH" record --repo "$1" --rc "$2" --now "$3" --health-state-file "$HS"
}
run() {  # run <now> [extra args]
  local now="$1"; shift
  python3 "$HEALTH" run --registry "$WORK/boards.txt" --cluster-map "$MAP" --state-file "$DS" \
    --health-state-file "$HS" --poster "$WORK/poster" --now "$now" "$@" 2>"$WORK/run.err"
}
last_payload() { tail -n 1 "$FAKE_POSTED"; }
npost() { grep -c . "$FAKE_POSTED"; }
field() { jq -r --arg n "$1" '[.fields[] | select(.name == $n) | .value] | join("\n")' <<<"$(last_payload)"; }

echo "case record (spokes, rc, errors only on failure):"
fresh
printf '  synced reminders: 3 spoke items, 9 board rows\n  synced notion: 2 spoke items, 9 board rows\n  (nothing to do)\nWARNING: malformed board rows for AB-8\n' | rec crew 0 "$NOW"
eq "spokes parsed" "$(jq -c '.sync.crew.spokes' "$HS")" '["notion","reminders"]'
eq "rc recorded" "$(jq '.sync.crew.rc' "$HS")" '0'
eq "no errors on a clean sync" "$(jq -c '.sync.crew.errors' "$HS")" '[]'
eq "warnings counted" "$(jq '.sync.crew.warnings' "$HS")" '1'
printf 'ERROR notion: 401 unauthorized\n' | rec crew 1 "$NOW"
eq "failed sync keeps its error line" "$(jq -r '.sync.crew.errors[0]' "$HS")" 'ERROR notion: 401 unauthorized'
printf 'mirror: plan 0 ops\n' | python3 "$HEALTH" record --leg mirror --rc 0 --now "$NOW" --health-state-file "$HS"
eq "mirror leg recorded" "$(jq -c '[.mirror.rc, .mirror.skipped]' "$HS")" '[0,false]'
eq "state file is 0600" "$(stat -f '%Lp' "$HS" 2>/dev/null || stat -c '%a' "$HS")" '600'
printf 'x\n' | python3 "$HEALTH" record --rc 0 --health-state-file "$HS" 2>/dev/null
eq "record without --repo is a usage error" "$?" '64'

echo "case hubs (active, parked, stale from the origin copy):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
run "$NOW" --dry-run > "$WORK/dry.out"
p="$(grep '"cluster":"alpha"' "$WORK/dry.out" | tail -n 1)"
eq "crew open counts the active rows only (origin copy, not the local edit)" "$(jq '.data.hubs.crew.open' <<<"$p")" '2'
eq "one active row is stale" "$(jq '.data.hubs.crew.stale' <<<"$p")" '1'
eq "parked counted apart" "$(jq '.data.hubs.crew.parked' <<<"$p")" '1'
eq "hubs line reads open and stale" "$(jq -r '.fields[] | select(.name=="hubs") | .value' <<<"$p")" '⚠️ hubs: crew 2 open (1 stale) · 1 parked'
p2="$(grep '"cluster":"beta"' "$WORK/dry.out" | tail -n 1)"
eq "a hub with no origin falls back to the working copy" "$(jq -c '.data.hubs.solo | [.open, .stale]' <<<"$p2")" '[1,1]'

echo "case kanban (open, stale, archived since the last run):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
KB=(--kanban "alpha=$WORK/kanban" --cluster alpha)
run "$NOW" --dry-run "${KB[@]}" > "$WORK/dry.out"
p="$(tail -n 1 "$WORK/dry.out")"
eq "open cards counted, done and archived boards left out" "$(jq -c '.data.kanban | keys' <<<"$p")" '["idle","work"]'
eq "work: 3 open" "$(jq '.data.kanban.work.open' <<<"$p")" '3'
eq "work: one stale card, by the latest of created/started/completed" "$(jq '.data.kanban.work.stale' <<<"$p")" '1'
eq "kanban line" "$(jq -r '.fields[] | select(.name=="kanban") | .value' <<<"$p")" '⚠️ kanban: work 3 open (1 stale, oldest 12d)'
eq "first run has no archived delta" "$(jq -r '[.fields[] | select(.name=="archived")] | length' <<<"$p")" '0'
run "$NOW" "${KB[@]}" --force; FAKE_ARCHIVED=9
run $((NOW + 3 * DAY)) "${KB[@]}"
eq "archived since the last run is the count delta" "$(field archived)" '🧹 archived this period: work 4'

echo "case cadence (due once, then quiet; force; dry-run and no-state stamp nothing):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
run "$NOW" --cluster alpha
eq "first run posts" "$(npost)" '1'
run $((NOW + 3600)) --cluster alpha
eq "an hour later it is not due" "$(npost)" '1'
grep -q 'skipped(not-due) alpha' "$WORK/run.err" && ok "not-due is logged with the next date" || bad "no not-due log"
run $((NOW + 3 * DAY)) --cluster alpha
eq "three days later it is due again" "$(npost)" '2'
run $((NOW + 3 * DAY + 60)) --cluster alpha --force
eq "--force ignores the cadence" "$(npost)" '3'
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
run "$NOW" --cluster alpha --dry-run >/dev/null
eq "--dry-run posts nothing" "$(npost)" '0'
eq "--dry-run stamps nothing" "$(jq -c '.last_run // {}' "$HS")" '{}'
run "$NOW" --cluster alpha --no-state
eq "--no-state still posts" "$(npost)" '1'
eq "--no-state stamps nothing" "$(jq -c '.last_run // {}' "$HS")" '{}'
run "$NOW" --cluster alpha
eq "so the real run after a test post is still due" "$(npost)" '2'

echo "case quiet (clean posts nothing but is stamped; a failed leg posts):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
run "$NOW" --cluster alpha --quiet alpha
eq "a clean quiet cluster posts nothing" "$(npost)" '0'
eq "and is stamped so it does not retry hourly" "$(jq -r '.last_run.alpha' "$HS")" "$NOW"
printf 'ERROR notion: 401 unauthorized\n' | rec crew 1 "$((NOW + 4 * DAY))"
run $((NOW + 4 * DAY)) --cluster alpha --quiet alpha
eq "a failed sync needs attention, so it posts" "$(npost)" '1'
eq "severity warn" "$(jq -r '.severity' <<<"$(last_payload)")" 'warn'
eq "attention flag" "$(jq -r '.attention' <<<"$(last_payload)")" 'true'
eq "the failing repo and its error ride an attention line" "$(field attention)" '❌ sync failed: crew · ERROR notion: 401 unauthorized'

echo "case failed post (stays due, carried, cleared on delivery):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
FAKE_POSTER_RC=1; FAKE_POSTER_ERR='bridge said https://discord.com/api/webhooks/123/abcdefghijklmnopqrstuvwxyz0123456789'
run "$NOW" --cluster alpha
eq "no stamp after a failed post" "$(jq -r '.last_run.alpha // "none"' "$HS")" 'none'
case "$(jq -r '.errors.alpha' "$HS")" in *"[webhook-redacted]"*) ok "the reason is stored, webhook redacted";; *) bad "reason not redacted: $(jq -r '.errors.alpha' "$HS")";; esac
FAKE_POSTER_RC=0; : > "$FAKE_POSTED"
run $((NOW + 3600)) --cluster alpha
eq "an hour later it retries (still due)" "$(npost)" '1'
eq "the retry carries the reason" "$(jq -r 'has("carried_error")' <<<"$(last_payload)")" 'true'
eq "and is a warn" "$(jq -r '.severity' <<<"$(last_payload)")" 'warn'
eq "delivery clears the error" "$(jq -r '.errors.alpha // "none"' "$HS")" 'none'
eq "and stamps the run" "$(jq -r '.last_run.alpha' "$HS")" "$((NOW + 3600))"

echo "case digest state (FLAPPING ids, a carried digest error):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
printf '%s' '{"crew":{"pending":{"flapping_ids":["AB-1"]}},"_cluster_errors":{"alpha":"post failed last sweep"}}' > "$DS"
run "$NOW" --cluster alpha --quiet alpha
eq "flapping makes a quiet cluster post" "$(npost)" '1'
eq "flapping line names the id and repo" "$(field attention | head -1)" '⚠️ AB-1 flapping between the board and a spoke (crew)'
eq "carried digest error is attention too" "$(field attention | tail -1)" '⚠️ last change digest failed to post: post failed last sweep'
echo '{}' > "$DS"

echo "case sync health (stale record, unreadable kanban, mirror):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$((NOW - 8 * 3600))"
run "$NOW" --cluster alpha
case "$(field attention)" in *"sweep record is 8h old"*) ok "an old sweep record is reported";; *) bad "no lag line: $(field attention)";; esac
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
FAKE_KANBAN_FAIL=1
run "$NOW" --cluster alpha --kanban "alpha=$WORK/kanban"
case "$(field attention)" in *"kanban unreadable for alpha: reader exploded"*) ok "an unreadable kanban is attention, not a crash";; *) bad "no kanban error: $(field attention)";; esac
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
printf 'board-mirror: ERROR cannot complete t_8fbaac45\n' | python3 "$HEALTH" record --leg mirror --rc 0 --now "$NOW" --health-state-file "$HS"
run "$NOW" --cluster alpha
case "$(field attention)" in *"hermes mirror failed: board-mirror: ERROR cannot complete"*) ok "a mirror error line is attention even at rc 0";; *) bad "no mirror error: $(field attention)";; esac
eq "sync line shows the mirror down" "$(field sync)" '🔄 sync: reminders ✅ · hermes mirror ❌ · last sweep 1 error'
fresh
run "$NOW" --cluster beta
case "$(field attention)" in *"no sweep record yet"*) ok "no record at all is said, not hidden";; *) bad "silent on no data: $(field attention)";; esac

echo "case line hook (extra lines ride; a failing hook never breaks the run):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
printf '#!/usr/bin/env bash\necho "📝 drafts: 2 waiting"\necho\necho "second line"\n' > "$WORK/hook"
printf '#!/usr/bin/env bash\nexit 7\n' > "$WORK/hook-bad"
chmod +x "$WORK/hook" "$WORK/hook-bad"
run "$NOW" --cluster alpha --line "alpha=$WORK/hook" --line "alpha=$WORK/hook-bad"
eq "each non-blank stdout line is a field" "$(field extra)" "$(printf '📝 drafts: 2 waiting\nsecond line')"
eq "still delivered" "$(npost)" '1'
grep -q 'WARN line hook exited 7' "$WORK/run.err" && ok "the failing hook is logged" || bad "no hook warning"

echo "case payload shape (kind, key, one line per field):"
fresh
printf '  synced reminders: 1 spoke items, 4 board rows\n' | rec crew 0 "$NOW"
run "$NOW" --cluster alpha --force; k1="$(jq -r .key <<<"$(last_payload)")"
run $((NOW + 60)) --cluster alpha --force; k2="$(jq -r .key <<<"$(last_payload)")"
eq "same cluster and day, same key (the poster's idempotency key)" "$k1" "$k2"
run $((NOW + 2 * DAY)) --cluster alpha --force; k3="$(jq -r .key <<<"$(last_payload)")"
[ "$k1" != "$k3" ] && ok "another day, another key" || bad "key did not change"
p="$(last_payload)"
eq "kind health" "$(jq -r .kind <<<"$p")" 'health'
eq "cluster, rail, title" "$(jq -r '[.cluster, .rail, .title] | join("|")' <<<"$p")" 'alpha|crew|Board health · alpha'
eq "period and next due" "$(jq -r '[.period_days, .next_due] | join("|")' <<<"$p")" "3|$(date -j -f %s $((NOW + 2 * DAY + 3 * DAY)) +%Y-%m-%d 2>/dev/null || date -d "@$((NOW + 5 * DAY))" +%Y-%m-%d)"
eq "no field value has a newline" "$(jq -r '[.fields[].value | select(contains("\n"))] | length' <<<"$p")" '0'

echo "case sweep (records each leg; --health runs the leg; --dry-run leaves real state alone):"
mkdir -p "$WORK/sw/home/.cache/backlog-sync"
cat > "$WORK/swboard" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  sync) echo "  synced reminders: 2 spoke items, 5 board rows"; echo "  (nothing to do)"; exit 0 ;;
  mirror) echo "    mirror: plan 0 ops"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$WORK/swboard"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/hermes"; chmod +x "$WORK/hermes"
SWH="$WORK/sw/health.json"; SWD="$WORK/sw/digest.json"
sweep() {  # sweep [args]
  env HOME="$WORK/sw/home" PATH="$WORK:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
    "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/swboard" --state-file "$SWD" \
    --health-state-file "$SWH" --poster "$WORK/poster" --cluster-map "$MAP" "$@" 2>&1
}
command rm -f "$SWH" "$SWD"; : > "$FAKE_POSTED"
out="$(sweep)"
eq "a plain sweep records the sync of every repo" "$(jq -c '.sync | keys' "$SWH")" '["crew","solo"]'
eq "and posts no health digest" "$(grep -c '"kind":"health"' "$FAKE_POSTED")" '0'
out="$(sweep --health --health-quiet beta --health-kanban "alpha=$WORK/kanban")"
eq "--health posts the due clusters through the poster" "$(grep -c '"kind":"health"' "$FAKE_POSTED")" '1'
eq "the quiet clean cluster stays silent" "$(jq -r 'select(.kind=="health" and .cluster=="beta") | .cluster' "$FAKE_POSTED" | wc -l | tr -d ' ')" '0'
eq "and its stamp lands in the health state" "$(jq -r '.last_run.alpha != null and .last_run.beta != null' "$SWH")" 'true'
out="$(sweep --health)"
eq "the next tick is not due" "$(grep -c '"kind":"health"' "$FAKE_POSTED")" '1'
before="$(cksum < "$SWH")"
out="$(sweep --health --health-force --dry-run)"
eq "--dry-run prints the payload, posts nothing" "$(grep -c '"kind":"health"' "$FAKE_POSTED")" '1'
case "$out" in *'"kind":"health"'*) ok "the dry run shows the payload";; *) bad "dry run printed no payload";; esac
eq "--dry-run leaves the real health state alone" "$(cksum < "$SWH")" "$before"

echo "case verb (board health reaches the script):"
"$HERE/../bin/board" health run --help 2>&1 | grep -q -e '--stale-days' && ok "board health run --help" || bad "board health verb not wired"

echo
echo "board-health: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
