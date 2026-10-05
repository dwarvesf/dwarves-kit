#!/usr/bin/env bash
# test-board-digest.sh -- lib/sync/sweep/board-digest.sh, the change-only digest
# behind `board sweep`. Plain bash asserts, no framework, no deps beyond jq and
# shasum. Fixture: tests/fixtures/board-sweep/sync-output.txt (a captured
# `board sync` run, scrubbed, plus synthesized lines for the action kinds the
# live capture did not hold).
#
# Two modes: `--repo <name>` parses one repo's captured stdout into the state
# file (never prints a payload); `--emit --cluster <name>` merges every repo on
# that cluster's rail and prints the one payload to post.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../lib/sync/sweep/board-digest.sh"
FIXTURE="$HERE/fixtures/board-sweep/sync-output.txt"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT

# fake local git repos behind the registry rows, so the ticket-link feature
# resolves a deterministic GitHub URL from a real `git remote get-url origin`
# without depending on the host's layout
mkgitrepo() {  # <dir> <remote-url-or-empty>
  mkdir -p "$1/_meta"
  git -C "$1" init -q
  [ -n "${2:-}" ] && git -C "$1" remote add origin "$2"
}
mkgitrepo "$WORK/repo-team" "git@github.com:acme/team.git"
mkgitrepo "$WORK/repo-solo" "https://github.com/acme/solo.git"
mkgitrepo "$WORK/repo-badrail" "git@github.com:acme/badrail.git"
mkgitrepo "$WORK/repo-nogithub" "https://gitlab.com/acme/nogithub.git"

BOARDS="$WORK/boards.txt"
cat > "$BOARDS" <<EOF
solo      $WORK/repo-solo/_meta/BACKLOG.md      on rail=pers
team      $WORK/repo-team/_meta/BACKLOG.md      rail=crew
badrail   $WORK/repo-badrail/_meta/BACKLOG.md   rail=nope
nogithub  $WORK/repo-nogithub/_meta/BACKLOG.md  rail=crew
EOF
MAP="alpha=crew,beta=pers"

parse() {  # parse <repo> <state-file-basename> [extra args...] < input
  local repo="$1" state="$WORK/$2"; shift 2
  "$SCRIPT" --repo "$repo" --registry "$BOARDS" --state-file "$state" --cluster-map "$MAP" "$@"
}
emit() {  # emit <cluster> <state-file-basename> [extra args...]
  local cluster="$1" state="$WORK/$2"; shift 2
  "$SCRIPT" --emit --cluster "$cluster" --registry "$BOARDS" --state-file "$state" --cluster-map "$MAP" "$@"
}
field() {  # field <payload> <repo> -> that repo's field value
  jq -r --arg n "$2" '.fields[] | select(.name==$n) | .value' <<<"$1"
}

echo "case happy (synthesized block, all describe() kinds, one repo):"
sed -n '135,141p' "$FIXTURE" | parse team state-happy.json
out="$(emit alpha state-happy.json --crit-prefix 'incident:')"
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || bad "exit $rc"
echo "$out" | jq -e . >/dev/null 2>&1 && ok "stdout is valid JSON" || bad "stdout not valid JSON: $out"
[ "$(echo "$out" | jq -r '.rail')" = "crew" ] && ok "rail from the registry" || bad "rail wrong"
[ "$(echo "$out" | jq -r '.cluster')" = "alpha" ] && ok "cluster named in the payload" || bad "cluster wrong"
[ "$(echo "$out" | jq -r '.title')" = "Board sync · alpha" ] && ok "title uses the CLUSTER name" || bad "title wrong: $(echo "$out" | jq -r '.title')"
[ "$(echo "$out" | jq -r '.severity')" = "crit" ] && ok "crit-prefixed adopted row -> severity crit" || bad "severity wrong: $(echo "$out" | jq -r '.severity')"
[ "$(field "$out" team)" \
  = "$(printf '📥 adopted\n• [AB-633](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=AB-633>) · queued · incident: worker host heartbeat lost\n🔀 1 status move (1 shipped)\n✏️ 4 other changes')" ] \
  && ok "subsection body: adopted+moves+other, shipped count, adopted id ticket-linked" \
  || bad "subsection body wrong: $(field "$out" team)"
[ "$(jq -r '.team.ids | index("AB-633") != null' "$WORK/state-happy.json")" = "true" ] \
  && ok "prefix-generic id regex: AB- (not ID-) lands in current_ids state" \
  || bad "AB-633 missing from current_ids: $(jq -c '.team.ids' "$WORK/state-happy.json")"
out_plain="$(emit alpha state-happy.json)"
[ "$(echo "$out_plain" | jq -r '.severity')" = "info" ] && ok "no --crit-prefix -> the same row stays info" || bad "severity without a prefix: $(echo "$out_plain" | jq -r '.severity')"

echo "case quiet (WARNING lines + dry-run header, no action lines):"
sed -n '1,3p' "$FIXTURE" | parse team state-quiet.json 2>"$WORK/quiet-parse.err"
out="$(emit alpha state-quiet.json 2>"$WORK/quiet.err")"
[ -z "$out" ] && ok "no stdout payload" || bad "unexpected payload: $out"
grep -q "skipped(no-change) team" "$WORK/quiet-parse.err" && ok "parse-time skipped(no-change) logged" || bad "no parse-time skipped(no-change)"
grep -q "skipped(no-change) alpha" "$WORK/quiet.err" && ok "emit-time skipped(no-change) logged" || bad "no emit-time skipped(no-change)"

echo "case warn-only (WARNING lines are not changes):"
printf 'WARNING: duplicate board rows for ID-1; fix the board\nWARNING: malformed board rows for ID-2\n' | parse team state-warnonly.json
out="$(emit alpha state-warnonly.json)"
[ -z "$out" ] && ok "WARNING-only input produces no payload" || bad "WARNING lines counted as changes"

echo "case nothing-to-do ((nothing to do) literal is not a change):"
printf '  (nothing to do)\n' | parse team state-ntd.json
out="$(emit alpha state-ntd.json)"
[ -z "$out" ] && ok "(nothing to do) alone produces no payload" || bad "(nothing to do) counted as a change: $out"

echo "case multi-spoke (reminders + notion + hermes in one repo, dedup by id):"
sed -n '1,131p' "$FIXTURE" | parse team state-multispoke.json
# a raised cap: this case asserts full created-line content; the default cap has its own case below
out="$(emit alpha state-multispoke.json --field-cap 100000)"
value="$(field "$out" team)"
created_block="$(printf '%s\n' "$value" | awk '/^✨ created$/{p=1;next} /^(📥 adopted|🔀 |✏️ )/{p=0} p')"
created_count="$(printf '%s\n' "$created_block" | grep -c .)"
id629_count="$(printf '%s\n' "$created_block" | grep -c '^• \[AB-629\](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=AB-629>) ')"
id630_count="$(printf '%s\n' "$created_block" | grep -c '^• \[AB-630\](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=AB-630>) ')"
[ "$id629_count" -eq 1 ] && ok "AB-629 pushed to notion+hermes -> appears once, ticket-linked" || bad "AB-629 not deduped/linked ($id629_count)"
[ "$id630_count" -eq 1 ] && ok "AB-630 pushed to notion+hermes -> appears once, ticket-linked" || bad "AB-630 not deduped/linked ($id630_count)"
[ "$created_count" -eq 22 ] && ok "created field line count (22 unique board rows across both apps)" || bad "created line count $created_count (want 22)"
[ "$(jq -r '.team.ids | index("AB-629") != null' "$WORK/state-multispoke.json")" = "true" ] \
  && ok "a '+ spoke' id lands in current_ids state" \
  || bad "AB-629 missing from current_ids: $(jq -c '.team.ids' "$WORK/state-multispoke.json")"

echo "case unknown-line (unrecognized line -> other change, never dropped):"
printf '  ? mystery    something the parser has never seen\n' | parse team state-unknown.json 2>"$WORK/unknown.err"
out="$(emit alpha state-unknown.json)"
[ -n "$out" ] && ok "unrecognized line still produces a payload" || bad "unrecognized line dropped the digest"
[ "$(field "$out" team)" = "✏️ 1 other change" ] && ok "folded into the other-change count" || bad "unknown-line field wrong: $(field "$out" team)"
grep -q "WARN parse-degraded" "$WORK/unknown.err" && ok "WARN logged for the unrecognized line" || bad "no parse-degraded WARN"

echo "case unknown-line-collision (two unmatched lines never dedup-collide on an empty id):"
printf '  ? mystery1  first unrecognized line\n  ? mystery2  second unrecognized line\n' \
  | parse team state-unknown2.json 2>"$WORK/unknown2.err"
out="$(emit alpha state-unknown2.json)"
[ "$(field "$out" team)" = "✏️ 2 other changes" ] \
  && ok "both distinct unmatched lines survive dedup (line-text fallback key)" \
  || bad "unmatched lines collided: $(field "$out" team)"

echo "case scope-reenter (↩ app: a row re-entering this app's scope is a change):"
sed -n '150,151p' "$FIXTURE" | parse team state-scope-reenter.json
out="$(emit alpha state-scope-reenter.json)"
[ "$(field "$out" team)" = "✏️ 1 other change" ] \
  && ok "↩ app parses as a single other-kind change" \
  || bad "scope-reenter not parsed: $(field "$out" team)"

echo "case bad-state (corrupt state file -> first-sweep behavior):"
printf 'not valid json {{{' > "$WORK/state-corrupt.json"
printf '  + spoke     ID-1 · test row\n' | parse team state-corrupt.json 2>"$WORK/corrupt.err"
grep -q "WARN state file corrupt" "$WORK/corrupt.err" && ok "WARN logged for corrupt state" || bad "no corrupt-state WARN"
out="$(emit alpha state-corrupt.json)"
[ "$(field "$out" team)" \
  = "$(printf '✨ created\n• [ID-1](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=ID-1>) · test row')" ] \
  && ok "no FLAPPING flagged on first sweep" || bad "unexpected content on first sweep: $(field "$out" team)"
jq -e . "$WORK/state-corrupt.json" >/dev/null 2>&1 && ok "state file rewritten as valid JSON" || bad "state file not rewritten"

echo "case unmapped (repo with no registry row -> ERROR, never posted):"
printf '  + spoke     ID-1 · test\n' | parse stray state-unmapped.json 2>"$WORK/unmapped.err"
grep -q "ERROR(no rail" "$WORK/unmapped.err" && ok "ERROR(no rail...) logged" || bad "no ERROR(no rail line"
out_beta="$(emit beta state-unmapped.json)"
[ -z "$out_beta" ] && ok "the stray repo never surfaces in any cluster's emit" || bad "stray repo leaked into a cluster payload"

echo "case bad-rail (rail=nope is not in the cluster map -> treated as unmapped):"
printf '  + spoke     ID-1 · test\n' | parse badrail state-badrail.json 2>"$WORK/badrail.err"
grep -q "ERROR(no rail" "$WORK/badrail.err" && ok "ERROR(no rail...) logged for a rail outside the map" || bad "no ERROR(no rail line for bad rail"
out_alpha="$(emit alpha state-badrail.json)"
echo "$out_alpha" | jq -e '.fields[] | select(.name=="badrail")' >/dev/null 2>&1 \
  && bad "badrail leaked into the alpha cluster payload" || ok "badrail never surfaces in any cluster"

echo "case key-determinism (same input twice -> identical key):"
in="$(sed -n '135,141p' "$FIXTURE")"
printf '%s\n' "$in" | parse team state-key1.json
key1="$(emit alpha state-key1.json | jq -r '.key')"
printf '%s\n' "$in" | parse team state-key2.json
key2="$(emit alpha state-key2.json | jq -r '.key')"
[ -n "$key1" ] && [ "$key1" = "$key2" ] && ok "identical key across independent runs ($key1)" || bad "keys differ: $key1 vs $key2"

echo "case flapping (same id changes again next sweep -> FLAPPING):"
printf '  ~ spoke     rid-abc -> shipped\n' | parse team state-flap.json
emit alpha state-flap.json > /dev/null
printf '  ~ spoke     rid-abc -> dropped\n' | parse team state-flap.json
out="$(emit alpha state-flap.json)"
field "$out" team | grep -q "FLAPPING: rid-abc" \
  && ok "second sweep's moves line calls out the flapping id" || bad "FLAPPING not surfaced: $(field "$out" team)"

echo "case hostile-title (quotes, backticks, @mention stay inert, valid JSON):"
printf '  + spoke     ID-9 · title with @everyone, `code`, "double" and '"'"'single'"'"' quotes\n' | parse team state-hostile.json
out="$(emit alpha state-hostile.json)"
echo "$out" | jq -e . >/dev/null 2>&1 && ok "JSON stays valid with quotes/backticks/@mention in the title" || bad "invalid JSON: $out"
field "$out" team | grep -q '@everyone' \
  && ok "the raw text (incl. @mention) lands as inert field value text" || bad "title text missing/mangled"

echo "case apostrophe-title (repr() double-quote form decoded):"
sed -n '145,146p' "$FIXTURE" | parse team state-apostrophe.json
out="$(emit alpha state-apostrophe.json)"
echo "$out" | jq -e . >/dev/null 2>&1 && ok "JSON stays valid" || bad "invalid JSON: $out"
field "$out" team | grep -qF "AB-634 · The board's title with an apostrophe" \
  && ok "double-quoted repr() form decoded, apostrophe intact, no stray quote chars" \
  || bad "apostrophe title not decoded: $(field "$out" team)"

echo "case single-quote-title (repr()'s default form):"
printf "  ~ board     ID-124 item -> 'Retitled item text'\n" | parse team state-singlequote.json
out="$(emit alpha state-singlequote.json)"
field "$out" team | grep -qF "1 other change" \
  && ok "single-quote repr() form parses cleanly (no parse-degraded)" || bad "single-quote form mishandled: $out"

echo "case cluster-merge (repos sharing a rail merge into ONE payload):"
printf '  + spoke     ID-11 · from team\n' | parse team state-cluster.json
printf '  + spoke     ID-12 · from nogithub\n' | parse nogithub state-cluster.json
out="$(emit alpha state-cluster.json)"
echo "$out" | jq -e '.fields[] | select(.name=="team")' >/dev/null 2>&1 && ok "team subsection present" || bad "team subsection missing"
echo "$out" | jq -e '.fields[] | select(.name=="nogithub")' >/dev/null 2>&1 && ok "nogithub subsection present" || bad "nogithub subsection missing"
[ "$(echo "$out" | jq -r '.severity')" = "info" ] && ok "routine sweep -> severity info" || bad "severity wrong: $(echo "$out" | jq -r '.severity')"
[ "$(jq -r 'has("carried_error")' <<<"$out")" = "false" ] && ok "routine sweep carries no carried_error" || bad "carried_error present on a routine sweep"
out_solo="$(emit beta state-cluster.json)"
[ -z "$out_solo" ] && ok "the other cluster stays quiet" || bad "other cluster leaked: $out_solo"

echo "case carry-forward (--mark-failed --reason rides the next --emit as carried_error, severity warn):"
printf '  + spoke     ID-14 · from solo\n' | parse solo state-carry.json
"$SCRIPT" --mark-failed --cluster beta --reason "poster refused the payload" \
  --registry "$BOARDS" --state-file "$WORK/state-carry.json" --cluster-map "$MAP" 2>/dev/null
out="$(emit beta state-carry.json)"
[ "$(echo "$out" | jq -r '.carried_error')" = "poster refused the payload" ] \
  && ok "carried reason rides the next emit" || bad "carried_error wrong: $(echo "$out" | jq -r '.carried_error')"
[ "$(echo "$out" | jq -r '.severity')" = "warn" ] && ok "bare carry-forward -> severity warn" || bad "severity wrong: $(echo "$out" | jq -r '.severity')"
echo "$out" | jq -e '.fields[] | select(.name=="↻ retry")' >/dev/null 2>&1 \
  && ok "a retry field notes the carry-forward" || bad "no retry field"
"$SCRIPT" --mark-posted --cluster beta --registry "$BOARDS" --state-file "$WORK/state-carry.json" --cluster-map "$MAP" 2>/dev/null
printf '  + spoke     ID-15 · another change\n' | parse solo state-carry.json
out2="$(emit beta state-carry.json)"
[ "$(echo "$out2" | jq -r '.severity')" = "info" ] && ok "--mark-posted clears the carried error" || bad "severity wrong after mark-posted: $(echo "$out2" | jq -r '.severity')"
[ "$(jq -r 'has("carried_error")' <<<"$out2")" = "false" ] && ok "no stale carried_error after mark-posted" || bad "stale carried_error lingered"

echo "case ticket-link (leading id -> masked link, <> suppresses the preview embed):"
printf '  + spoke     LK-20 · verify masked link format\n' | parse team state-link.json
out="$(emit alpha state-link.json)"
expect="$(printf '✨ created\n• [LK-20](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=LK-20>) · verify masked link format')"
[ "$(field "$out" team)" = "$expect" ] && ok "id wrapped with the correct repo URL, title stays plain" || bad "link wrong: $(field "$out" team)"

echo "case ticket-link-multi (multiple leading ids in one field value, each wrapped):"
printf '  + spoke     LK-21 · first row\n  + spoke     LK-22 · second row\n' | parse team state-linkmulti.json
val="$(field "$(emit alpha state-linkmulti.json)" team)"
echo "$val" | grep -qF '• [LK-21](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=LK-21>) · first row' && ok "first id wrapped" || bad "first id not wrapped: $val"
echo "$val" | grep -qF '• [LK-22](<https://github.com/acme/team/blob/main/_meta/BACKLOG.md#:~:text=LK-22>) · second row' && ok "second id wrapped" || bad "second id not wrapped: $val"

echo "case ticket-link-nogithub (non-github remote -> id left unlinked):"
printf '  + spoke     LK-23 · no github remote here\n' | parse nogithub state-nogithub.json
val="$(field "$(emit alpha state-nogithub.json)" nogithub)"
[ "$val" = "$(printf '✨ created\n• LK-23 · no github remote here')" ] \
  && ok "non-github-remote repo: id left plain, no masked-link syntax" || bad "nogithub value wrong: $val"

echo "case ticket-link-key-unaffected (masked links never change the content-derived key):"
printf '  + spoke     LK-30 · linkify key test\n' | parse team state-keylink.json
key_linked="$(emit alpha state-keylink.json | jq -r '.key')"
BOARDS_NOLINK="$WORK/boards-nolink.txt"
printf 'team  %s/no-such-repo/_meta/BACKLOG.md  rail=crew\n' "$WORK" > "$BOARDS_NOLINK"
printf '  + spoke     LK-30 · linkify key test\n' \
  | "$SCRIPT" --repo team --registry "$BOARDS_NOLINK" --state-file "$WORK/state-keynolink.json" --cluster-map "$MAP"
key_unlinked="$("$SCRIPT" --emit --cluster alpha --registry "$BOARDS_NOLINK" --state-file "$WORK/state-keynolink.json" --cluster-map "$MAP" | jq -r '.key')"
[ -n "$key_linked" ] && [ "$key_linked" = "$key_unlinked" ] \
  && ok "key identical whether or not the repo resolves to a linkable remote ($key_linked)" \
  || bad "key differs: linked=$key_linked unlinked=$key_unlinked"

echo "case concurrent-state (the state lock: two concurrent --repo writers both land):"
BOARDS_CONC="$WORK/boards-concurrent.txt"
cat > "$BOARDS_CONC" <<EOF
repo-a  $WORK/repo-a/_meta/BACKLOG.md  rail=crew
repo-b  $WORK/repo-b/_meta/BACKLOG.md  rail=crew
EOF
STATE_CONC="$WORK/state-concurrent.json"
( printf '  + spoke     AB-1 · from repo-a\n' | "$SCRIPT" --repo repo-a --registry "$BOARDS_CONC" --state-file "$STATE_CONC" ) &
pid_a=$!
( printf '  + spoke     AB-2 · from repo-b\n' | "$SCRIPT" --repo repo-b --registry "$BOARDS_CONC" --state-file "$STATE_CONC" ) &
pid_b=$!
wait "$pid_a" "$pid_b"
has_a="$(jq 'has("repo-a")' "$STATE_CONC" 2>/dev/null)"
has_b="$(jq 'has("repo-b")' "$STATE_CONC" 2>/dev/null)"
[ "$has_a" = "true" ] && [ "$has_b" = "true" ] \
  && ok "both concurrent repo writes landed in state" \
  || bad "concurrent write lost a repo's state (repo-a=$has_a repo-b=$has_b)"

echo "case field-cap (whole-line truncation + '+N more' under the 1024 limit):"
for i in $(seq 1 40); do
  printf '  + spoke     ID-9%02d · a deliberately long synthetic board row title to inflate the digest field value %02d\n' "$i" "$i"
done | parse team state-cap.json
out="$(emit alpha state-cap.json)"
caplen="$(echo "$out" | jq -r '.fields[] | select(.name=="team") | .value | length')"
[ "$caplen" -le 1024 ] && ok "field value capped at <=1024 (got $caplen)" || bad "field value $caplen exceeds 1024"
field "$out" team | tail -1 | grep -q "more (see the board)" \
  && ok "truncation names the dropped remainder" || bad "no '+N more' tail on the capped field"
key1="$(echo "$out" | jq -r '.key')"
for i in $(seq 1 40); do
  printf '  + spoke     ID-9%02d · a deliberately long synthetic board row title to inflate the digest field value %02d\n' "$i" "$i"
done | parse team state-cap2.json
key2="$(emit alpha state-cap2.json --field-cap 100000 | jq -r '.key')"
[ "$key1" = "$key2" ] && ok "cap is display-only: key still tuple-derived and deterministic" || bad "key changed under truncation"
out_small="$(emit alpha state-cap2.json --field-cap 200)"
smalllen="$(echo "$out_small" | jq -r '.fields[] | select(.name=="team") | .value | length')"
[ "$smalllen" -le 200 ] && ok "--field-cap tightens the cap (got $smalllen)" || bad "--field-cap 200 gave $smalllen"

echo "case clusters (map order, and the no-map identity default):"
[ "$("$SCRIPT" --list-clusters --registry "$BOARDS" --cluster-map "$MAP" | paste -sd, -)" = "alpha,beta" ] \
  && ok "--list-clusters follows the map order" || bad "map clusters wrong: $("$SCRIPT" --list-clusters --registry "$BOARDS" --cluster-map "$MAP" | paste -sd, -)"
[ "$("$SCRIPT" --list-clusters --registry "$BOARDS" | paste -sd, -)" = "pers,crew,nope" ] \
  && ok "no map: each distinct registry rail is its own cluster, first-seen order" || bad "no-map clusters wrong: $("$SCRIPT" --list-clusters --registry "$BOARDS" | paste -sd, -)"
printf '  + spoke     ID-16 · identity cluster\n' | "$SCRIPT" --repo team --registry "$BOARDS" --state-file "$WORK/state-identity.json" 2>/dev/null
out="$("$SCRIPT" --emit --cluster crew --registry "$BOARDS" --state-file "$WORK/state-identity.json" 2>/dev/null)"
[ "$(echo "$out" | jq -r '.cluster + "/" + .rail')" = "crew/crew" ] && ok "no map: a cluster is its rail" || bad "identity cluster wrong: $out"
"$SCRIPT" --emit --cluster ghost --registry "$BOARDS" --state-file "$WORK/state-identity.json" >/dev/null 2>&1
[ $? -eq 64 ] && ok "an unknown cluster is a usage error (64)" || bad "unknown cluster did not exit 64"
"$SCRIPT" --emit --cluster alpha --state-file "$WORK/state-identity.json" >/dev/null 2>&1
[ $? -eq 64 ] && ok "a missing --registry is a usage error (64)" || bad "missing --registry did not exit 64"

echo "case rc-passthrough (the digest never signals a data problem through its exit code):"
allzero=1
printf '  + spoke     ID-1 · x\n' | parse stray state-rc1.json >/dev/null 2>&1;      [ $? -eq 0 ] || allzero=0
printf '  + spoke     ID-1 · x\n' | parse badrail state-rc2.json >/dev/null 2>&1;    [ $? -eq 0 ] || allzero=0
printf '  ? mystery    x\n'       | parse team state-rc3.json >/dev/null 2>&1;       [ $? -eq 0 ] || allzero=0
printf 'not json' > "$WORK/state-rc4.json"
printf '  + spoke     ID-1 · x\n' | parse team state-rc4.json >/dev/null 2>&1;       [ $? -eq 0 ] || allzero=0
emit alpha state-rc4.json >/dev/null 2>&1;                                           [ $? -eq 0 ] || allzero=0
[ "$allzero" -eq 1 ] && ok "unmapped/bad-rail/unknown-line/corrupt-state all exit 0" || bad "digest exited non-zero on a non-usage error"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
