#!/usr/bin/env bash
# test-board-sweep-post.sh -- lib/sync/sweep/board-sweep-post.sh, the layer
# between a digest payload and the operator's poster command.
#
# The kit decides WHAT to post and when a post counts as delivered; the poster
# decides HOW. Every poster here is a local stub: no network, no secret.
#
#   AC1  a poster that exits 0 -> posted, `unsent` stays empty
#   AC2  nothing pending -> the poster is never invoked
#   AC3  --dry-run prints the payload, never invokes the poster, never mutates state
#   AC4  a poster that fails -> exit 0 still, the change lands in `unsent`, the
#        poster's stderr rides the reason
#   AC5  the next sweep merges `unsent` with new changes and posts ONCE
#   AC6  the failure reason surfaces on the next payload (carried_error, severity warn)
#   AC7  credential shapes are redacted from the stored reason; the state file is 0600
#   AC8  many dirty repos on one rail stay inside the 25-field / 6000-char embed limits
#   AC9  a poster that is missing or not executable is a failure, never a silent skip
#   AC10 the payload reaches the poster on stdin, whole
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
POST="$HERE/../lib/sync/sweep/board-sweep-post.sh"
DIGEST="$HERE/../lib/sync/sweep/board-digest.sh"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT

BOARDS="$WORK/boards.txt"
cat > "$BOARDS" <<'EOF'
team   /nowhere/team/_meta/BACKLOG.md   rail=crew
solo   /nowhere/solo/_meta/BACKLOG.md   rail=pers
EOF
MAP="alpha=crew,beta=pers"

POSTER="$WORK/poster"
cat > "$POSTER" <<'EOF'
#!/usr/bin/env bash
echo "poster called" >> "${FAKE_CALL_LOG:-/dev/null}"
cat > "${FAKE_PAYLOAD_FILE:-/dev/null}"
[ "${FAKE_POSTER_RC:-0}" -ne 0 ] && echo "${FAKE_POSTER_ERR:-fake-poster-error-detail}" >&2
echo "stdout noise the kit must ignore"
exit "${FAKE_POSTER_RC:-0}"
EOF
chmod +x "$POSTER"
export FAKE_CALL_LOG FAKE_POSTER_RC FAKE_POSTER_ERR FAKE_PAYLOAD_FILE

parse() {  # parse <repo> <state-file-basename> < input
  local repo="$1" state="$WORK/$2"; shift 2
  bash "$DIGEST" --repo "$repo" --registry "$BOARDS" --state-file "$state" --cluster-map "$MAP" "$@"
}
post() {  # post <cluster> <state-file-basename> [extra args...]
  local cluster="$1" state="$WORK/$2"; shift 2
  "$POST" --cluster "$cluster" --registry "$BOARDS" --state-file "$state" --cluster-map "$MAP" --poster "$POSTER" "$@"
}

echo "case happy (poster succeeds -> posted, state cleared):"
FAKE_CALL_LOG="$WORK/happy.log"; FAKE_PAYLOAD_FILE="$WORK/happy.payload"
printf '  + spoke     ID-1 · test\n' | parse team state-happy.json
FAKE_POSTER_RC=0 post alpha state-happy.json >/dev/null 2>"$WORK/happy.err"
[ $? -eq 0 ] && ok "exits 0" || bad "nonzero exit"
grep -q "poster called" "$WORK/happy.log" && ok "the poster was invoked" || bad "poster never called"
grep -q "digest: alpha posted" "$WORK/happy.err" && ok "posted log line" || bad "no posted log line"
[ "$(jq -c '.team.unsent' "$WORK/state-happy.json")" = "[]" ] && ok "unsent stays empty after a clean post" || bad "unsent not empty"
[ "$(jq -r '.cluster + "/" + .rail + "/" + .title' "$WORK/happy.payload")" = "alpha/crew/Board sync · alpha" ] \
  && ok "the payload arrived on the poster's stdin, whole" || bad "payload wrong: $(cat "$WORK/happy.payload")"

echo "case no-content (nothing pending -> no post attempted):"
FAKE_CALL_LOG="$WORK/no-content.log"; : > "$FAKE_CALL_LOG"
post alpha state-no-content.json >/dev/null 2>"$WORK/no-content.err"
[ ! -s "$WORK/no-content.log" ] && ok "no poster was invoked" || bad "a poster ran with nothing pending"

echo "case dry-run (prints, never posts, never mutates state):"
printf '  + spoke     ID-2 · test\n' | parse team state-dryrun.json
FAKE_CALL_LOG="$WORK/dryrun.log"; : > "$FAKE_CALL_LOG"
before="$(cksum < "$WORK/state-dryrun.json")"
out="$(post alpha state-dryrun.json --dry-run 2>"$WORK/dryrun.err")"
echo "$out" | jq -e . >/dev/null 2>&1 && ok "dry-run prints the payload" || bad "dry-run printed no/invalid payload"
[ ! -s "$WORK/dryrun.log" ] && ok "dry-run never invokes the poster" || bad "dry-run invoked the poster"
grep -q "digest: alpha posted" "$WORK/dryrun.err" && bad "dry-run logged posted" || ok "dry-run does not claim posted"
[ "$(cksum < "$WORK/state-dryrun.json")" = "$before" ] && ok "dry-run left the state byte-identical" || bad "dry-run mutated the state"

echo "case fail (poster fails -> ERROR, change lands in unsent):"
printf '  + spoke     ID-3 · first change\n' | parse team state-carry.json
FAKE_CALL_LOG="$WORK/fail.log"
FAKE_POSTER_RC=1 post alpha state-carry.json 2>"$WORK/fail.err" >/dev/null
rc=$?
[ "$rc" -eq 0 ] && ok "still exits 0 on a post failure (the sweep's rc is untouched)" || bad "nonzero exit on post failure: $rc"
grep -q "ERROR(fake-poster-error-detail) alpha" "$WORK/fail.err" \
  && ok "the poster's stderr is the logged reason" || bad "reason lost: $(grep ERROR "$WORK/fail.err")"
[ "$(jq '.team.unsent | length' "$WORK/state-carry.json")" -eq 1 ] && ok "the failed change landed in unsent" || bad "unsent has $(jq '.team.unsent | length' "$WORK/state-carry.json") entries (want 1)"
grep -q "digest: alpha posted" "$WORK/fail.err" && bad "counted posted despite the failure" || ok "not counted posted"

echo "case carry-forward (next sweep merges unsent + new change, posts once):"
printf '  + spoke     ID-4 · second change\n' | parse team state-carry.json
FAKE_CALL_LOG="$WORK/retry.log"; : > "$FAKE_CALL_LOG"; FAKE_PAYLOAD_FILE="$WORK/retry.payload"
FAKE_POSTER_RC=0 post alpha state-carry.json 2>"$WORK/retry.err" >/dev/null
[ "$(grep -c "poster called" "$WORK/retry.log")" -eq 1 ] && ok "exactly one post attempt for the merged set" || bad "poster called $(grep -c "poster called" "$WORK/retry.log") times"
jq -r '.fields[] | select(.name=="team") | .value' "$WORK/retry.payload" | grep -q 'ID-3' \
  && jq -r '.fields[] | select(.name=="team") | .value' "$WORK/retry.payload" | grep -q 'ID-4' \
  && ok "the one post carries both the carried and the new change" || bad "merged payload wrong: $(cat "$WORK/retry.payload")"
[ "$(jq -c '.team.unsent' "$WORK/state-carry.json")" = "[]" ] && ok "unsent cleared after the merged post succeeds" || bad "unsent not cleared"

echo "case carry-forward-notice (a failed post's reason surfaces on the next payload):"
printf '  + spoke     ID-10 · first change\n' | parse solo state-notice.json
FAKE_CALL_LOG="$WORK/notice-fail.log"
FAKE_POSTER_RC=1 FAKE_POSTER_ERR="upstream said no" post beta state-notice.json 2>/dev/null >/dev/null
[ "$(jq -r '._cluster_errors.beta // empty' "$WORK/state-notice.json")" = "upstream said no" ] \
  && ok "failure reason stashed in state" || bad "stashed reason wrong: $(jq -r '._cluster_errors.beta // empty' "$WORK/state-notice.json")"
printf '  + spoke     ID-11 · second change\n' | parse solo state-notice.json
out="$(post beta state-notice.json --dry-run 2>/dev/null)"
[ "$(jq -r '.carried_error' <<<"$out")" = "upstream said no" ] && ok "the retry payload carries the stashed reason" || bad "carried_error wrong: $(jq -r '.carried_error' <<<"$out")"
[ "$(jq -r '.severity' <<<"$out")" = "warn" ] && ok "carry-forward renders at severity warn" || bad "severity wrong: $(jq -r '.severity' <<<"$out")"

echo "case reason-redaction (webhook URL + token shapes scrubbed; state file 0600):"
printf '  + spoke     ID-11 · redaction change\n' | parse team state-redact.json
FAKE_CALL_LOG="$WORK/redact.log"
FAKE_POSTER_RC=1 \
  FAKE_POSTER_ERR="boom https://discord.com/api/webhooks/1234567890/abcdefghijklmnopqrstuvwxyz0123456789 tok_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef end" \
  post alpha state-redact.json 2>"$WORK/redact.err" >/dev/null
stored="$(jq -r '._cluster_errors.alpha // ""' "$WORK/state-redact.json")"
case "$stored" in
  *1234567890*|*discord.com/api/webhooks*) bad "webhook URL survived into state: $stored";;
  *) ok "webhook URL redacted from the stored reason";;
esac
case "$stored" in
  *ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef*) bad "token shape survived into state: $stored";;
  *) ok "long token shape redacted from the stored reason";;
esac
[ -n "$stored" ] && ok "a (scrubbed) reason was still stashed" || bad "reason lost entirely by redaction"
perm="$(stat -f %Lp "$WORK/state-redact.json" 2>/dev/null || stat -c %a "$WORK/state-redact.json" 2>/dev/null)"
[ "$perm" = "600" ] && ok "state file written 0600" || bad "state file perms $perm (want 600)"

echo "case embed-budget (8 fat repos on one rail -> total <= 6000, summary field):"
BUDGET_BOARDS="$WORK/budget-boards.txt"
: >| "$BUDGET_BOARDS"
for i in 1 2 3 4 5 6 7 8; do
  echo "repo$i /nonexistent/r$i/BACKLOG.md on rail=crew" >> "$BUDGET_BOARDS"
done
for i in 1 2 3 4 5 6 7 8; do
  for j in $(seq 1 12); do
    printf '  + spoke     ID-%d%02d · a very long synthetic board row title to fatten this repo field %d %02d\n' "$i" "$j" "$i" "$j"
  done | bash "$DIGEST" --repo "repo$i" --registry "$BUDGET_BOARDS" --state-file "$WORK/state-budget.json" --cluster-map "$MAP" 2>/dev/null
done
bout="$(bash "$DIGEST" --emit --cluster alpha --registry "$BUDGET_BOARDS" --state-file "$WORK/state-budget.json" --cluster-map "$MAP" 2>/dev/null)"
nf="$(jq '.fields | length' <<<"$bout")"
total="$(jq '[.fields[] | (.name | length) + (.value | length)] | add' <<<"$bout")"
[ "$nf" -le 25 ] && ok "field count $nf <= 25" || bad "field count $nf exceeds 25"
[ "$total" -le 6000 ] && ok "embed total $total <= 6000" || bad "embed total $total exceeds 6000"
jq -e '.fields[-1] | select(.name == "…") | .value | test("more repos truncated")' <<<"$bout" >/dev/null \
  && ok "dropped repos surfaced in a summary field" || bad "no truncation summary field: $(jq -c '.fields[-1]' <<<"$bout")"

echo "case poster-missing (a poster that cannot run is a failure, never a silent skip):"
printf '  + spoke     ID-20 · nobody home\n' | parse solo state-missing.json
"$POST" --cluster beta --registry "$BOARDS" --state-file "$WORK/state-missing.json" --cluster-map "$MAP" \
  --poster "$WORK/no-such-poster" 2>"$WORK/missing.err" >/dev/null
[ $? -eq 0 ] && ok "exits 0" || bad "nonzero exit"
grep -q "ERROR(poster not executable" "$WORK/missing.err" && ok "named in the log" || bad "no ERROR: $(cat "$WORK/missing.err")"
[ "$(jq '.solo.unsent | length' "$WORK/state-missing.json")" -eq 1 ] && ok "the change is carried, not dropped" || bad "change not carried"

echo "case usage (missing flags are a usage error, 64):"
"$POST" --registry "$BOARDS" --poster "$POSTER" >/dev/null 2>&1; [ $? -eq 64 ] && ok "no --cluster -> 64" || bad "no --cluster did not exit 64"
"$POST" --cluster alpha --registry "$BOARDS" >/dev/null 2>&1;   [ $? -eq 64 ] && ok "no --poster (and no --dry-run) -> 64" || bad "no --poster did not exit 64"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
