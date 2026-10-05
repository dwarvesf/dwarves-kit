#!/usr/bin/env bash
# Tests for lib/board/board-mirror-cleanup.py (`board mirror-cleanup`): the reconcile of open Hermes cards
# against the BACKLOG.md hub. A stateful stub stands in for `hermes kanban`; no
# real Hermes, board, or snapshot is touched.
#
#   AC1  classification: a / b / c / d / e land where the design says, per board
#   AC2  dry run is the default: zero archive calls, snapshot byte-identical
#   AC3  apply archives b, c, wrong-state e, and the decomposer chain; leaves a,
#        bot cards, unregistered repos, chatter, and done cards alone
#   AC4  apply drops exactly the archived origins from the snapshot, keeps a backup
#   NC1  IDEMPOTENT: a second apply plans and runs nothing
#   NC2  NO RESURRECTION: archived cards never come back as open cards
#   NC3  never deletes: only list / show / boards / archive verbs are ever called
#   NC4  a refused archive keeps that origin in the snapshot and exits nonzero
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
mkdir -p "$STUB_DIR" "$WORK/fixA/_meta/megagoals/live" "$WORK/fixA/_meta/megagoals/finished"
cp "$STUB_SRC" "$WORK/hermes-stub"; chmod +x "$WORK/hermes-stub"
export HERMES_BIN="$WORK/hermes-stub"

cat > "$WORK/fixA/BACKLOG.md" <<'EOF'
# Backlog
| ID | Item | Notes & source | Status |
|----|------|----------------|--------|
| A-1 | Queued row | n | queued |
| A-2 | Parked row | n | parked [revisit] |
| A-3 | Shipped row | n | shipped |
| A-4 | Dropped row | n | dropped |
| A-5 | Claimed row | n | claimed |
| A-6 | Row whose card is done | n | queued |
EOF
cat > "$WORK/fixA/BACKLOG-archive.md" <<'EOF'
| ID | Item | Notes & source | Status |
|----|------|----------------|--------|
| A-7 | Moved to the archive file | n | shipped |
EOF
printf '# Mega-goal: Live\n\n- [x] 01 done\n- [ ] 02 pending\n' > "$WORK/fixA/_meta/megagoals/live/ROADMAP.md"
printf '# Mega-goal: Finished\n\n- [x] 01 done\n- [x] 02 done\n' > "$WORK/fixA/_meta/megagoals/finished/ROADMAP.md"
printf 'fixA  %s/fixA/BACKLOG.md  on\nfixOff  %s/nowhere/BACKLOG.md  off\n' "$WORK" "$WORK" > "$WORK/boards.txt"

python3 - "$STUB_DIR" <<'EOF'
import json, sys, time
d = sys.argv[1]
now = int(time.time())
def card(cid, status, origin=None, by="user", title="t", age_days=0):
    body = "[AUTOMATED MIRROR]\norigin: %s\nnotes: n" % origin if origin else "free text"
    return {"id": cid, "title": title, "body": body, "status": status,
            "created_by": by, "created_at": now - age_days * 86400}
boards = [{"slug": s, "archived": False} for s in ("fixA", "megagoals", "chatter", "default")]
json.dump(boards, open(d + "/boards.json", "w"))
json.dump([
    card("c1", "triage", "fixA:A-1"),
    card("c2", "blocked", "fixA:A-2"),
    card("c3", "triage", "fixA:A-3"),
    card("c4", "blocked", "fixA:A-4"),
    card("c5", "triage", "fixA:A-5"),
    card("c6", "ready", "fixA:A-7"),
    card("c7", "triage", "fixA:A-99"),
    card("c8", "done", "fixA:A-6"),
    card("kid1", "scheduled", None, by="auto-decomposer"),
    card("kid2", "scheduled", None, by="auto-decomposer"),
    card("c10", "ready", None, by="default"),
    card("c11", "triage", "fixZ:Z-1"),
], open(d + "/fixA.json", "w"))
json.dump([
    card("m1", "ready", "megagoals:fixA/live"),
    card("m2", "ready", "megagoals:fixA/finished"),
    card("m3", "ready", "megagoals:fixA/ghost"),
], open(d + "/megagoals.json", "w"))
json.dump([card("s1", "triage", None, by="chat-desk", age_days=1),
           card("s2", "triage", None, by="chat-desk", age_days=9),
           card("s3", "triage", None, by="chat-aux", age_days=20)],
          open(d + "/chatter.json", "w"))
json.dump([card("i1", "blocked", None, title="[alarm] CRIT x")], open(d + "/default.json", "w"))
# c3 is the root of a decomposition: its children are listed as its parents
json.dump({"parents": [{"id": "kid1"}, {"id": "kid2"}]}, open(d + "/show-c3.json", "w"))
EOF

SNAP="$WORK/snapshot.jsonl"
for pair in "fixA:A-1 c1" "fixA:A-2 c2" "fixA:A-3 c3" "fixA:A-4 c4" "fixA:A-5 c5" "fixA:A-7 c6" "fixA:A-99 c7" "megagoals:fixA/finished m2"; do
  set -- $pair
  jq -nc --arg o "$1" --arg h "$2" '{origin:$o,repo:"x",id:"x",board:"fixA",hermes_id:$h,row_hash:"h",hermes_status:"triage",seen_at:"t"}'
done > "$SNAP"
SNAP_BEFORE="$(cksum < "$SNAP")"

cat > "$WORK/kinds.json" <<'EOF'
[
 {"kind": "alert", "owner_rule": "closes with its ticket: archive the card when the alert recovers",
  "match": {"title_prefix": "[alarm]", "body_prefix": "filed-by: alarm-bot"}},
 {"kind": "decomposer-child", "owner_rule": "owned by its root mirror card: archived with the root",
  "match": {"created_by": ["auto-decomposer"]}},
 {"kind": "chatter", "owner_rule": "owned by the chat desk: expires by age, see the age distribution",
  "age_report": "archive chatter cards still in triage after 14 days (not applied)",
  "match": {"board": "chatter", "created_by": ["chat-desk", "chat-aux"]}}
]
EOF
run() { python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$SNAP" --hermes-home "$WORK/home" --kinds-file "$WORK/kinds.json" --source working "$@"; }
col() { printf '%s\n' "$1" | awk -v b="$2" -v c="$3" '$1==b { print $c }'; }
archived_ids() { jq -r '.[] | select(.status=="archived") | .id' "$STUB_DIR"/fixA.json "$STUB_DIR"/megagoals.json "$STUB_DIR"/chatter.json "$STUB_DIR"/default.json | sort | paste -sd, -; }

echo "AC1/AC2: dry run classifies and changes nothing"
: > "$STUB_DIR/calls.log"
OUT="$(run)"; RC=$?
check "dry run exits 0" "$RC"
# columns: board open a b c d e closed
check "fixA: 11 open, a=2 b=3 c=1 d=3 e=2, 1 closed" "$([ "$(col "$OUT" fixA 2)-$(col "$OUT" fixA 3)-$(col "$OUT" fixA 4)-$(col "$OUT" fixA 5)-$(col "$OUT" fixA 6)-$(col "$OUT" fixA 7)-$(col "$OUT" fixA 8)" = "11-2-3-1-3-2-1" ]; echo $?)"
check "megagoals: a=1 b=1 c=1" "$([ "$(col "$OUT" megagoals 3)-$(col "$OUT" megagoals 4)-$(col "$OUT" megagoals 5)" = "1-1-1" ]; echo $?)"
check "chatter: all 3 are class d" "$([ "$(col "$OUT" chatter 6)" = "3" ]; echo $?)"
check "an archive-file row is class b" "$(printf '%s\n' "$OUT" | grep -q 'b:in-archive-file *1' ; echo $?)"
check "the unregistered repo is class e, reported" "$(printf '%s\n' "$OUT" | grep -q 'e:repo-not-in-registry *1'; echo $?)"
check "wrong-state card shows what it is and what it should be" "$(printf '%s\n' "$OUT" | grep -q 'e:state-drift triage->ready'; echo $?)"
check "class d is reported by kind with an owner rule" "$(printf '%s\n' "$OUT" | grep -q 'alert' && printf '%s\n' "$OUT" | grep -q 'owner rule: closes with its ticket'; echo $?)"
check "an age_report rule prints the age distribution and the proposed expiry" "$(printf '%s\n' "$OUT" | grep -q 'age distribution: 0-1d=.*15d+=1' && printf '%s\n' "$OUT" | grep -q 'proposed expiry: archive chatter cards'; echo $?)"
check "dry run made no archive call" "$(grep -q ' archive ' "$STUB_DIR/calls.log"; [ $? -ne 0 ]; echo $?)"
check "dry run left the snapshot byte-identical" "$([ "$(cksum < "$SNAP")" = "$SNAP_BEFORE" ]; echo $?)"
check "dry run archived nothing" "$([ -z "$(archived_ids)" ]; echo $?)"

echo "AC3/AC4: apply"
OUT="$(run --apply)"; RC=$?
check "apply exits 0" "$RC"
check "apply archives b, c, wrong-state e, and the decomposer chain" "$([ "$(archived_ids)" = "c3,c4,c5,c6,c7,kid1,kid2,m2,m3" ]; echo $?)"
check "apply leaves a, bot cards, the unregistered repo, chatter and done alone" \
  "$([ "$(jq -r '[.[] | select(.id=="c1" or .id=="c2" or .id=="c8" or .id=="c10" or .id=="c11") | .status] | join(",")' "$STUB_DIR/fixA.json")" = "triage,blocked,done,ready,triage" ] && [ "$(jq -r '[.[]|.status]|join(",")' "$STUB_DIR/chatter.json")" = "triage,triage,triage" ] && [ "$(jq -r '.[0].status' "$STUB_DIR/megagoals.json")" = "ready" ]; echo $?)"
check "the root's decomposer children went with it" "$([ "$(jq -r '[.[] | select(.id|startswith("kid")) | .status] | join(",")' "$STUB_DIR/fixA.json")" = "archived,archived" ]; echo $?)"
check "snapshot keeps only the untouched origins (A-1, A-2)" "$([ "$(jq -r '.origin' "$SNAP" | paste -sd, -)" = "fixA:A-1,fixA:A-2" ]; echo $?)"
check "a snapshot backup was kept" "$(ls "$WORK"/snapshot.jsonl.pre-cleanup-* >/dev/null 2>&1; echo $?)"

echo "NC1/NC2/NC3: idempotent, no resurrection, never deletes"
: > "$STUB_DIR/calls.log"
BEFORE_ARCHIVED="$(archived_ids)"
OUT="$(run --apply)"; RC=$?
check "second apply exits 0" "$RC"
check "second apply plans nothing" "$(printf '%s\n' "$OUT" | grep -q '^actions: 0 archive'; echo $?)"
check "second apply made no archive call" "$(grep -q ' archive ' "$STUB_DIR/calls.log"; [ $? -ne 0 ]; echo $?)"
check "archived set is unchanged" "$([ "$(archived_ids)" = "$BEFORE_ARCHIVED" ]; echo $?)"
check "no archived card is listed as open (fixA keeps c1 c2 c10 c11; 9 open in all)" "$([ "$(col "$OUT" fixA 2)" = "4" ] && [ "$(printf '%s\n' "$OUT" | awk '$1=="TOTAL"{print $2}')" = "9" ]; echo $?)"
VERBS="$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^(list|show|archive|boards|create|complete|delete|rm|unarchive|reopen|edit)$/) { print $i; break } }' "$STUB_DIR/calls.log" | sort -u | paste -sd, -)"
check "only read verbs on the second run (no archive, no delete)" "$([ "$VERBS" = "boards,list" ] || [ "$VERBS" = "boards,list,show" ]; echo $?)"

echo "NC4: a refused archive keeps its snapshot line and exits nonzero"
python3 - "$STUB_DIR" <<'EOF'
import json, sys, time
d = sys.argv[1]
now = int(time.time())
cards = json.load(open(d + "/fixA.json"))
cards.append({"id": "c20", "title": "t", "body": "origin: fixA:A-3\nnotes: n", "status": "triage", "created_by": "user", "created_at": now})
cards.append({"id": "c21", "title": "t", "body": "origin: fixA:A-4\nnotes: n", "status": "triage", "created_by": "user", "created_at": now})
json.dump(cards, open(d + "/fixA.json", "w"))
EOF
jq -nc '{origin:"fixA:A-3",repo:"x",id:"x",board:"fixA",hermes_id:"c20",row_hash:"h",hermes_status:"triage",seen_at:"t"}' >> "$SNAP"
jq -nc '{origin:"fixA:A-4",repo:"x",id:"x",board:"fixA",hermes_id:"c21",row_hash:"h",hermes_status:"triage",seen_at:"t"}' >> "$SNAP"
STUB_FAIL_ARCHIVE=c20 run --apply >/dev/null 2>&1; RC=$?
check "exit is nonzero when an archive is refused" "$([ "$RC" -ne 0 ]; echo $?)"
check "the refused card keeps its snapshot line, the archived one loses it" "$([ "$(jq -r '.origin' "$SNAP" | paste -sd, -)" = "fixA:A-1,fixA:A-2,fixA:A-3" ]; echo $?)"

echo "KINDS: the rule list is data, and the defaults carry no operator rules"
python3 - "$STUB_DIR" <<'EOF'
import json, sys, time
d = sys.argv[1]
now = int(time.time())
cards = json.load(open(d + "/fixA.json"))
# a decomposer child on a board a later rule claims: the FIRST matching rule wins
json.dump([{"id": "k9", "title": "t", "body": "free text", "status": "scheduled", "created_by": "auto-decomposer", "created_at": now}],
          open(d + "/chatter.json", "w"))
EOF
OUT="$(run)"
check "first matching rule wins: a decomposer child on the chatter board is a decomposer-child" "$(printf '%s\n' "$OUT" | grep -q 'decomposer-child *1 *boards={.chatter.: 1}'; echo $?)"
OUT="$(python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$SNAP" --hermes-home "$WORK/home" --source working)"
check "no --kinds-file: only the decomposer rule is built in" "$(printf '%s\n' "$OUT" | grep -q 'decomposer-child' && ! printf '%s\n' "$OUT" | grep -q ' alert '; echo $?)"
check "no --kinds-file: an unmatched bot card is kind agent with the generic owner rule" "$(printf '%s\n' "$OUT" | grep -q 'agent' && printf '%s\n' "$OUT" | grep -q 'owner rule: owned by the creating profile'; echo $?)"
env -u HERMES_HOME python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$SNAP" >/dev/null 2>"$WORK/nohome.err"; RC=$?
check "no --hermes-home and no HERMES_HOME is refused, there is no default store" "$([ "$RC" -ne 0 ] && grep -q 'need --hermes-home' "$WORK/nohome.err"; echo $?)"
printf 'not json' > "$WORK/bad-kinds.json"
python3 "$CLEANUP" --registry "$WORK/boards.txt" --snapshot "$SNAP" --hermes-home "$WORK/home" --kinds-file "$WORK/bad-kinds.json" >/dev/null 2>&1; RC=$?
check "a malformed --kinds-file fails loudly" "$([ "$RC" -ne 0 ]; echo $?)"

echo
echo "  TOTAL: $((PASS+FAIL))   PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
