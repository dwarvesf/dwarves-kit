#!/usr/bin/env bash
# Tests for the age expiry in lib/board/board-mirror-cleanup.py: a kinds-file rule
# with an "expire" block archives its cards after N days in triage, per board.
# A stateful stub stands in for `hermes kanban`; no real Hermes store is touched.
#
#   AC1  dry run (--expire-only) reports what would expire and when the next card
#        crosses the limit, and makes no archive call
#   AC2  apply archives exactly the eligible cards and prints one line
#   AC3  eligibility: age at or past the limit, status triage, the listed board
#   AC4  idempotent: a second apply expires 0
#   NC1  a kinds file without an expire block never archives by age
#   NC2  --expire-only without an expire rule is refused
#   NC3  a malformed expire block fails loudly
#   NC4  a refused archive exits nonzero and is not counted as expired
#   NC5  --expire-only reads no registry and never touches a card with an origin line
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLEANUP="$HERE/../lib/board/board-mirror-cleanup.py"
STUB_SRC="$HERE/fixtures/board-sweep/stub-hermes-kanban"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT

export STUB_DIR="$WORK/stub"
mkdir -p "$STUB_DIR"
cp "$STUB_SRC" "$WORK/hermes-stub"; chmod +x "$WORK/hermes-stub"
export HERMES_BIN="$WORK/hermes-stub"

python3 - "$STUB_DIR" <<'EOF'
import json, sys, time
d = sys.argv[1]
now = int(time.time())
def card(cid, status="triage", by="social-desk", age_s=0, body="[x] mention", created=True):
    c = {"id": cid, "title": "t", "body": body, "status": status, "created_by": by}
    if created:
        c["created_at"] = now - age_s
    return c
D = 86400
json.dump([{"slug": s, "archived": False} for s in ("social", "chatter", "default")], open(d + "/boards.json", "w"))
json.dump([
    card("s1", age_s=15 * D),                       # old: expires
    card("s2", age_s=14 * D + 60),                  # just past the limit: expires
    card("s3", age_s=14 * D - 3600),                # one hour short: stays
    card("s4", age_s=3 * D),                        # young: stays
    card("s5", by="circle-social", age_s=30 * D),   # the second desk: expires
    card("s6", status="ready", age_s=20 * D),       # not triage: stays
    card("s7", age_s=30 * D, created=False),        # unknown age: stays
    card("s8", status="done", age_s=30 * D),        # closed: stays
    card("s9", age_s=30 * D, body="origin: fixA:A-1\nnotes: n"),  # a mirror card: stays
    card("s10", by="user", age_s=40 * D),           # a person's card on the board: expires
], open(d + "/social.json", "w"))
json.dump([card("c1", by="social-desk", age_s=30 * D)], open(d + "/chatter.json", "w"))   # right creator, wrong board
json.dump([card("d1", by="user", age_s=30 * D)], open(d + "/default.json", "w"))
EOF

cat > "$WORK/kinds.json" <<'EOF'
[
 {"kind": "social", "owner_rule": "owned by social-desk: expires by age",
  "expire": {"days": 14, "board": "social", "status": "triage"},
  "match": {"board": "social", "created_by": ["social-desk", "circle-social"]}}
]
EOF
cat > "$WORK/kinds-noexpire.json" <<'EOF'
[
 {"kind": "social", "owner_rule": "owned by social-desk",
  "match": {"board": "social", "created_by": ["social-desk", "circle-social"]}}
]
EOF
NOREG="$WORK/no-such-registry.txt"
run() { python3 "$CLEANUP" --registry "$NOREG" --snapshot "$WORK/snap.jsonl" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds.json" "$@"; }
archived_ids() { jq -r '.[] | select(.status=="archived") | .id' "$STUB_DIR"/social.json "$STUB_DIR"/chatter.json "$STUB_DIR"/default.json | sort | paste -sd, -; }

echo "AC1: dry run"
: > "$STUB_DIR/calls.log"
OUT="$(run --expire-only)"; RC=$?
check "dry run exits 0" "$RC"
check "the line says what would expire: s1 s2 s5 s10 is 4" "$(printf '%s\n' "$OUT" | grep -qx 'would expire 4 cards on social (limit 14d)'; echo $?)"
check "it names when the next card crosses the limit" "$(printf '%s\n' "$OUT" | grep -q '^next card on social crosses 14d at 20[0-9][0-9]-'; echo $?)"
check "dry run made no archive call" "$(grep -q ' archive ' "$STUB_DIR/calls.log"; [ $? -ne 0 ]; echo $?)"
check "dry run archived nothing" "$([ -z "$(archived_ids)" ]; echo $?)"
check "only the listed board was read" "$([ "$(grep -c -- '--board chatter' "$STUB_DIR/calls.log")" = "0" ] && [ "$(grep -c -- '--board default' "$STUB_DIR/calls.log")" = "0" ]; echo $?)"

echo "AC2/AC3: apply"
OUT="$(run --expire-only --apply)"; RC=$?
check "apply exits 0" "$RC"
check "one line: expired 4 cards on social (limit 14d)" "$([ "$OUT" = "expired 4 cards on social (limit 14d)" ]; echo $?)"
check "archived exactly the eligible cards" "$([ "$(archived_ids)" = "s1,s10,s2,s5" ]; echo $?)"
check "boundary: one hour short, young, not triage, no created_at, closed, mirror card all stay" \
  "$([ "$(jq -r '[.[] | select(.status != "archived") | .id] | sort | join(",")' "$STUB_DIR/social.json")" = "s3,s4,s6,s7,s8,s9" ]; echo $?)"
check "another board's card stays, even from the same creator" "$([ "$(jq -r '.[0].status' "$STUB_DIR/chatter.json")" = "triage" ] && [ "$(jq -r '.[0].status' "$STUB_DIR/default.json")" = "triage" ]; echo $?)"
check "the snapshot was never created" "$([ ! -e "$WORK/snap.jsonl" ]; echo $?)"

echo "AC4: idempotent"
: > "$STUB_DIR/calls.log"
OUT="$(run --expire-only --apply)"; RC=$?
check "second apply exits 0" "$RC"
check "second apply: expired 0 cards on social (limit 14d)" "$([ "$OUT" = "expired 0 cards on social (limit 14d)" ]; echo $?)"
check "second apply made no archive call" "$(grep -q ' archive ' "$STUB_DIR/calls.log"; [ $? -ne 0 ]; echo $?)"
OUT="$(run --expire-only)"
check "second dry run: would expire 0" "$(printf '%s\n' "$OUT" | grep -qx 'would expire 0 cards on social (limit 14d)'; echo $?)"

echo "NC1: no expire block, no expiry"
python3 - "$STUB_DIR" <<'EOF'
import json, sys, time
d = sys.argv[1]
c = json.load(open(d + "/social.json"))
c.append({"id": "s11", "title": "t", "body": "x", "status": "triage", "created_by": "social-desk", "created_at": int(time.time()) - 90 * 86400})
json.dump(c, open(d + "/social.json", "w"))
EOF
printf 'fixA  %s/none/BACKLOG.md  off\n' "$WORK" > "$WORK/boards.txt"
python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$WORK/snap.jsonl" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds-noexpire.json" --apply >/dev/null 2>&1; RC=$?
check "a full apply with a no-expire kinds file exits 0" "$RC"
check "the 90-day-old social card is still triage" "$([ "$(jq -r '.[] | select(.id=="s11") | .status' "$STUB_DIR/social.json")" = "triage" ]; echo $?)"
OUT="$(python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$WORK/snap.jsonl" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds-noexpire.json")"
check "and the plain report prints no expiry line" "$(printf '%s\n' "$OUT" | grep -q 'expire [0-9]'; [ $? -ne 0 ]; echo $?)"

echo "full dry run: the plain verb reports the expiry too"
OUT="$(python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$WORK/snap.jsonl" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds.json")"
check "plain dry run prints would expire 1 (s11)" "$(printf '%s\n' "$OUT" | grep -qx 'would expire 1 cards on social (limit 14d)'; echo $?)"
OUT="$(python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$WORK/snap.jsonl" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds.json" --json)"
check "--json carries the expiry count" "$([ "$(printf '%s\n' "$OUT" | jq -r '.expire["social/social"]')" = "1" ]; echo $?)"
OUT="$(python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$WORK/snap.jsonl" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds.json" --apply)"
check "plain apply expires s11 and prints the line" "$(printf '%s\n' "$OUT" | grep -qx 'expired 1 cards on social (limit 14d)'; echo $?)"
check "plain apply leaves the same creator's old card on another board alone" "$([ "$(jq -r '.[0].status' "$STUB_DIR/chatter.json")" = "triage" ] && [ "$(jq -r '.[] | select(.id=="s11") | .status' "$STUB_DIR/social.json")" = "archived" ]; echo $?)"

echo "NC2/NC3: refusals"
python3 "$CLEANUP" --registry "$NOREG" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds-noexpire.json" --expire-only >/dev/null 2>"$WORK/err"; RC=$?
check "--expire-only with no expire rule is refused" "$([ "$RC" -ne 0 ] && grep -q 'needs a rule with an expire block' "$WORK/err"; echo $?)"
echo '[{"kind":"social","match":{"board":"social"},"expire":{"days":0,"board":"social"}}]' > "$WORK/bad1.json"
echo '[{"kind":"social","match":{"board":"social"},"expire":{"days":14}}]' > "$WORK/bad2.json"
echo '[{"kind":"social","match":{"board":"social"},"expire":"14d"}]' > "$WORK/bad3.json"
for f in bad1 bad2 bad3; do
  python3 "$CLEANUP" --registry "$NOREG" --hermes-home "$WORK/home" --kinds-file "$WORK/$f.json" --expire-only >/dev/null 2>&1; RC=$?
  check "malformed expire block $f fails loudly" "$([ "$RC" -ne 0 ]; echo $?)"
done

echo "NC4: a refused archive"
python3 - "$STUB_DIR" <<'EOF'
import json, sys, time
d = sys.argv[1]
c = json.load(open(d + "/social.json"))
for i in (12, 13, 14):
    c.append({"id": f"s{i}", "title": "t", "body": "x", "status": "triage", "created_by": "social-desk", "created_at": int(time.time()) - 20 * 86400})
json.dump(c, open(d + "/social.json", "w"))
EOF
OUT="$(STUB_FAIL_ARCHIVE=s12 run --expire-only --apply 2>/dev/null)"; RC=$?
check "exit is nonzero when an archive is refused" "$([ "$RC" -ne 0 ]; echo $?)"
check "only the archived cards are counted: s13 and s14 of the three eligible" "$([ "$OUT" = "expired 2 cards on social (limit 14d)" ]; echo $?)"

echo "NC5: no registry read, origin cards untouched"
check "s9 (a mirror card, 30 days old) is still triage" "$([ "$(jq -r '.[] | select(.id=="s9") | .status' "$STUB_DIR/social.json")" = "triage" ]; echo $?)"
check "the missing registry never mattered" "$([ ! -e "$NOREG" ]; echo $?)"

echo
echo "  TOTAL: $((PASS+FAIL))   PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
