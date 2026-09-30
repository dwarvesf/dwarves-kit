#!/usr/bin/env bash
# Over-test for the ceremony lens: `stats ceremony` (gate counts, windows, progress, subagent
# dispatch and token reader, fixture exclusion) and the `ceremony_share` anomaly.
# Self-contained, same harness as test-anomalies-advisor.sh: every source env var points at a
# temp dir, a generated git repo has controlled commit dates, a generated `subagents/` tree
# stands in for ~/.claude/projects, and every case runs the REAL end-to-end path
# (source -> lens -> `stats ceremony` / `stats anomalies`). Nothing here touches the real
# ledger or the real transcripts.
#
# Load-bearing negative controls:
#   - A-one-catch: one catch stops the anomaly (proves the caught = 0 clause).
#   - A-unknown / A-thin / A-share-low: each other clause blocks alone, and each has a
#     control run (a lowered floor or threshold) that fires, so the floor is the blocker.
#   - S-tokens: a message id repeated on two lines counts once (the last line wins).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }
# nofire <label> <json>: the output must be valid JSON first, so empty output never passes
nofire() { if printf '%s' "$2" | jq -e . >/dev/null 2>&1; then hasnt "$1" "$FIRES" "$2"; else bad "$1 (output is not JSON)"; fi; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

FIX="$(mktemp -d)"
GITREPO="$FIX/repo"
KITLOG="$FIX/kit-runs"
SESS="$FIX/sessions"

git_init() {
  rm -rf "$GITREPO"; mkdir -p "$GITREPO"
  git -C "$GITREPO" init -q -b main --template=
  git -C "$GITREPO" config user.name "Fixture Bot"
  git -C "$GITREPO" config user.email "fixture@example.com"
  git -C "$GITREPO" config commit.gpgsign false
}

# commit_lines <file> <n-lines> <subject> <iso8601-date>: one commit adding <n-lines> lines.
commit_lines() {
  local rel="$1" n="$2" subject="$3" date="$4"
  seq 1 "$n" > "$GITREPO/$rel"
  git -C "$GITREPO" add "$rel" >/dev/null
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$GITREPO" commit -q -m "$subject" >/dev/null
}

export DWARVES_KIT_LOG_DIR="$KITLOG"
export STATS_GIT_REPO_DIR="$GITREPO"
export STATS_TIDE_DB="$FIX/state.sqlite"
export STATS_TGCLEANUP_DIR="$FIX/tg"
export STATS_LEARNED_MD="$FIX/learned.md"
export STATS_SESSIONS_DIR="$SESS"
export STATS_SECRET_GUARD_LOG="$FIX/nonexistent-safety.log"
export STATS_MEMORY_REPO_DIR="$FIX/nonexistent-memory-repo"
export STATS_MEMORY_PROJECTS_ROOT="$FIX/nonexistent-memory-projects"
export CC_BACKLOG_STAGING="$FIX/backlog-staging.md"
export CC_BACKLOG_BACKLOG="$FIX/BACKLOG.md"
unset STATS_EXCLUDE_RIDS STATS_CEREMONY_PROGRESS_PHASES
mkdir -p "$STATS_TGCLEANUP_DIR" "$KITLOG/runs" "$SESS"
printf '# Backlog\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n' > "$CC_BACKLOG_BACKLOG"

R()   { uv run stats "$@" 2>&1; }
RA()  { uv run stats "$@" 2>/dev/null; }
RJ()  { uv run stats ceremony --json "$@" 2>/dev/null; }
reset() { rm -rf "$KITLOG/runs" "$SESS"; mkdir -p "$KITLOG/runs" "$SESS"; git_init; }
epoch() { python3 -c "import datetime,sys;print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$1"; }

# gl <rid> <iso-ts> <gate> <outcome> <caught|-> [reason]
#   caught != "-" also writes an OUTCOME start/end bracket (the additive marker).
gl() {
  local rid="$1" ts="$2" gate="$3" outcome="$4" caught="$5" reason="${6:-}"
  local f="$KITLOG/runs/$rid.log"
  [ -f "$f" ] || echo "$ts | START | lane=normal classified=normal type=feat ctype=feat repo=fixrepo" > "$f"
  if [ "$caught" != "-" ]; then
    echo "$ts | OUTCOME | $gate | start | at=1" >> "$f"
    echo "$ts | OUTCOME | $gate | end | at=2 caught=$caught dur_s=1" >> "$f"
  fi
  if [ -n "$reason" ]; then echo "$ts | GATE | $gate | $outcome | $reason" >> "$f"
  else echo "$ts | GATE | $gate | $outcome" >> "$f"; fi
}

# fire_fixture <flip-one-catch:0|1> <bracketed:0|1>
#   40 ceremony ran records over 8 rids (5 ceremony gates each) + 10 progress records
#   (build, ship on 5 rids): share 0.80. 12 ceremony rows carry an OUTCOME bracket when
#   bracketed=1, all caught=false (the first one caught=true when flip=1).
fire_fixture() {
  local flip="$1" bracketed="$2" n=0 r gi gate caught day
  for r in 1 2 3 4 5 6 7 8; do
    day=$((14 + r))
    gi=0
    for gate in grill spec validate test-plan review; do
      gi=$((gi + 1)); n=$((n + 1))
      caught="-"
      if [ "$bracketed" = 1 ] && [ "$n" -le 12 ]; then
        caught=false
        if [ "$flip" = 1 ] && [ "$n" -eq 1 ]; then caught=true; fi
      fi
      gl "fire-$r" "$(printf '2026-09-%02dT10:%02d:00Z' "$day" "$gi")" "$gate" ran "$caught"
    done
    if [ "$r" -le 5 ]; then
      gl "fire-$r" "$(printf '2026-09-%02dT11:00:00Z' "$day")" build ran -
      gl "fire-$r" "$(printf '2026-09-%02dT12:00:00Z' "$day")" ship ran -
    fi
  done
}

FIRES='"key": "ceremony_share"'

# =============================================================================================
echo "== A-fire: 40 ceremony records, 12 known, 0 caught, share 0.80 -> fires =="
reset; fire_fixture 0 1
OUT="$(R anomalies --json)"
has "A-fire fires ceremony_share" "$FIRES" "$OUT"
has "A-fire metric ceremony_records=40" "ceremony_records=40" "$OUT"
has "A-fire metric known_caught=12" "known_caught=12" "$OUT"
has "A-fire metric caught=0" "caught=0" "$OUT"
has "A-fire metric share=0.80" "share=0.80" "$OUT"
has "A-fire progress prints ? with no git commits" "lines=?" "$OUT"

echo "== A-one-catch (negative control): one caught=true -> does NOT fire =="
reset; fire_fixture 1 1
nofire "A-one-catch no ceremony_share" "$(RA anomalies --json)"

echo "== A-unknown: same volume, no OUTCOME lines -> does NOT fire; report says ? =="
reset; fire_fixture 0 0
nofire "A-unknown no ceremony_share" "$(RA anomalies --json)"
has   "A-unknown report catches ? (0 known)" "catches: ? (0 known)" "$(R ceremony)"

echo "== A-thin: 20 ceremony records, 12 known, 0 caught -> does NOT fire (records floor) =="
reset
n=0
for r in 1 2 3 4; do
  for gate in grill spec validate test-plan review; do
    n=$((n + 1)); c="-"; [ "$n" -le 12 ] && c=false
    gl "thin-$r" "$(printf '2026-09-%02dT10:%02d:00Z' $((14 + r)) "$n")" "$gate" ran "$c"
  done
done
nofire "A-thin no ceremony_share" "$(RA anomalies --json)"
has   "A-thin control: lowered floor fires" "$FIRES" "$(R anomalies --json --threshold ceremony_min_records=20)"

echo "== A-share-low: 40 records, 25 build/ship, share 0.375, 0 caught -> does NOT fire =="
reset
k=0; m=0
for r in 1 2 3 4 5; do
  for gate in grill spec validate; do
    k=$((k + 1)); c="-"; [ "$k" -le 12 ] && c=false
    gl "low-$r" "$(printf '2026-09-%02dT10:%02d:00Z' $((14 + r)) "$k")" "$gate" ran "$c"
  done
  for gate in build ship build ship build; do
    m=$((m + 1))
    gl "low-$r" "$(printf '2026-09-%02dT11:%02d:00Z' $((14 + r)) "$m")" "$gate" ran -
  done
done
LOWT="--threshold ceremony_min_records=10"
nofire "A-share-low no ceremony_share" "$(RA anomalies --json $LOWT)"
has   "A-share-low control: lowered share fires" "$FIRES" "$(R anomalies --json $LOWT --threshold ceremony_share_max=0.3)"

# =============================================================================================
echo "== C-counts: ran, override, skipped counted apart; skipped stays out of the share =="
reset
gl c1 2026-09-20T10:00:00Z grill ran -
gl c1 2026-09-20T10:01:00Z spec ran -
gl c1 2026-09-20T10:02:00Z validate override -
gl c1 2026-09-20T10:03:00Z test-plan skipped -
gl c1 2026-09-20T10:04:00Z build ran -
gl c1 2026-09-20T10:05:00Z ship ran -
gl c1 2026-09-20T10:06:00Z review skipped -
J="$(RJ)"
eq "C-counts ran"      "$(jq '.records.ran' <<<"$J")" 4
eq "C-counts override" "$(jq '.records.override' <<<"$J")" 1
eq "C-counts skipped"  "$(jq '.records.skipped' <<<"$J")" 2
eq "C-counts active (ran+override)" "$(jq '.records.active' <<<"$J")" 5
eq "C-counts ceremony records" "$(jq '.records.ceremony' <<<"$J")" 3
eq "C-counts ceremony override column" "$(jq '.records.ceremony_override' <<<"$J")" 1
eq "C-counts share 3/5" "$(jq '.records.share' <<<"$J")" 0.6

echo "== C-unknown: a run with no dispatches and no TOKENS prints ? for tokens, not 0 =="
eq "C-unknown tokens null in json" "$(jq '.runs[0].tokens_net' <<<"$J")" null
eq "C-unknown catches null" "$(jq '.catches.value' <<<"$J")" null
TXT="$(R ceremony)"
has "C-unknown text row shows ? cells" "| c1 | 3 | 5 | 1 | 2 | 0.60 | ? | ? | ? | ? | ? | ? | ? | ? |" "$TXT"

echo "== C-progress: only PR-squash commits inside the window count; an older one does not =="
reset
gl p1 2026-09-20T10:00:00Z grill ran -
gl p1 2026-09-30T10:00:00Z ship ran -
commit_lines old.txt 4 "feat: older work (#9)" "2026-08-01T00:00:00+00:00"
commit_lines a.txt 3 "feat: inside work (#12)" "2026-09-22T00:00:00+00:00"
commit_lines b.txt 5 "fix: inside no suffix" "2026-09-23T00:00:00+00:00"
J="$(RJ)"
eq "C-progress lines (only the (#12) commit)" "$(jq '.progress.lines' <<<"$J")" 3
eq "C-progress prs" "$(jq '.progress.prs' <<<"$J")" 1

# =============================================================================================
echo "== X-exclude: fixture ledgers never enter a total, and are listed with counts =="
reset
gl x1 2026-09-20T10:00:00Z grill ran -
gl x1 2026-09-20T10:01:00Z spec ran -
BEFORE="$(RJ | jq -c '.records')"
echo "2026-09-20T10:00:00Z | START | lane=full classified=full type=feat ctype=feat repo=fixrepo" > "$KITLOG/runs/sg-9.log"
echo "2026-09-20T10:00:01Z | TOKENS | in=10 out=1 cache_read=0 cache_create=0" >> "$KITLOG/runs/sg-9.log"
echo "2026-09-20T10:00:00Z | START | lane=full classified=full type=feat ctype=feat repo=fixrepo" > "$KITLOG/runs/turncap-fixture.log"
J="$(RJ)"
eq "X-exclude totals unchanged" "$(jq -c '.records' <<<"$J")" "$BEFORE"
eq "X-exclude sg-9 START count" "$(jq '.excluded[] | select(.rid=="sg-9") | .starts' <<<"$J")" 1
eq "X-exclude sg-9 TOKENS count" "$(jq '.excluded[] | select(.rid=="sg-9") | .tokens' <<<"$J")" 1
eq "X-exclude turncap-fixture listed" "$(jq '[.excluded[].rid] | contains(["turncap-fixture"])' <<<"$J")" true
eq "X-exclude none suspect" "$(jq -c '.suspect_fixtures' <<<"$J")" "[]"

echo "== X-suspect: a new rid with START and no GATE is named =="
echo "2026-09-20T10:00:00Z | START | lane=full classified=full type=feat ctype=feat repo=fixrepo" > "$KITLOG/runs/zz-leak.log"
J="$(RJ)"
eq "X-suspect zz-leak listed" "$(jq -c '.suspect_fixtures' <<<"$J")" '["zz-leak"]'
has "X-suspect text line" "suspect fixtures: zz-leak" "$(R ceremony)"

# =============================================================================================
# subagent fixture: mk_sub <slug> <session> <agent-id> <agentType> <description> <first-ts> [model]
#   jsonl: a user line (first-ts), an assistant line with usage m-<id> (out 5), the SAME message id
#   again (out 290), a last user line. Message text is a sentinel the reader must never keep.
mk_sub() {
  local slug="$1" session="$2" id="$3" type="$4" desc="$5" ts="$6" model="${7:-}"
  local d="$SESS/$slug/$session/subagents"
  mkdir -p "$d"
  if [ -n "$model" ]; then
    printf '{"agentType":"%s","description":"%s","model":"%s"}\n' "$type" "$desc" "$model" > "$d/agent-$id.meta.json"
  else
    printf '{"agentType":"%s","description":"%s"}\n' "$type" "$desc" > "$d/agent-$id.meta.json"
  fi
  {
    printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"SECRET-MSG-TEXT"}}\n' "$ts"
    printf '{"type":"assistant","timestamp":"%s","message":{"id":"m-%s","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":50},"content":[{"type":"text","text":"SECRET-MSG-TEXT"}]}}\n' "$ts" "$id"
    printf '{"type":"assistant","timestamp":"%s","message":{"id":"m-%s","usage":{"input_tokens":10,"output_tokens":290,"cache_read_input_tokens":100,"cache_creation_input_tokens":50},"content":[{"type":"text","text":"SECRET-MSG-TEXT"}]}}\n' "$ts" "$id"
    printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"SECRET-MSG-TEXT"}}\n' "$ts"
  } > "$d/agent-$id.jsonl"
  # mtime follows the fixture time, so the retention check sees the transcript inside its window
  TZ=UTC touch -t "${ts:0:4}${ts:5:2}${ts:8:2}${ts:11:2}${ts:14:2}" "$d/agent-$id.jsonl" "$d/agent-$id.meta.json"
}

# A late GATE line pins the window end (the default window ends at the latest GATE timestamp).
# It also plants one old transcript (never opened, mtime 2026-01-01): retention must reach back past
# the window start, or the lens rightly prints ? for every dispatch and token cell.
clock() {
  gl clk 2026-09-30T00:00:00Z grill ran -
  local d="$SESS/anchor-project/sess-anchor/subagents"; mkdir -p "$d"
  echo '{"agentType":"kit:task-verifier","description":"anchor"}' > "$d/agent-anchor.meta.json"
  echo '{}' > "$d/agent-anchor.jsonl"
  TZ=UTC touch -t 202601010000 "$d/agent-anchor.jsonl" "$d/agent-anchor.meta.json"
}

SLUG="-Users-x-some-other-repo"   # NOT the ledger repo: the join must never use cwd or slug

echo "== S-tag: tagged dispatches attribute by rid and agentType, from a different project slug =="
reset
clock
gl r1 2026-09-20T09:00:00Z build ran -
mk_sub "$SLUG" sess1 a1 kit:task-verifier "verify rid=r1 SECRET-DESC-TEXT" 2026-09-20T10:00:00.000Z
mk_sub "$SLUG" sess1 a2 kit:task-verifier "verify rid=r1 again" 2026-09-20T10:05:00.000Z
mk_sub "$SLUG" sess1 a3 general-purpose "build rid=r1 task" 2026-09-20T10:10:00.000Z opus
J="$(RJ)"
eq "S-tag r1 dispatches" "$(jq '.runs[] | select(.rid=="r1") | .dispatches' <<<"$J")" 3
eq "S-tag r1 verifier count" "$(jq '.runs[] | select(.rid=="r1") | .by_type["kit:task-verifier"]' <<<"$J")" 2
eq "S-tag r1 general-purpose count" "$(jq '.runs[] | select(.rid=="r1") | .by_type["general-purpose"]' <<<"$J")" 1
eq "S-tag join source tag=3" "$(jq '.dispatch.rid_source.tag' <<<"$J")" 3
echo "== S-privacy: no description text and no message text reaches any output =="
ALL="$(RJ; R ceremony; R show subagent_runs --json)"
printf '%s' "$J" | jq -e . >/dev/null 2>&1 && ok "S-privacy output is JSON" || bad "S-privacy output is not JSON"
has "S-privacy output holds the run r1" '"rid": "r1"' "$(jq '.runs[] | select(.rid=="r1")' <<<"$J")"
has "S-privacy output holds dispatch a1" "a1" "$(R show subagent_runs --json)"
hasnt "S-privacy no description text" "SECRET-DESC-TEXT" "$ALL"
hasnt "S-privacy no message text" "SECRET-MSG-TEXT" "$ALL"

echo "== S-window / S-ambiguous / S-none: untagged dispatches join by build bracket only =="
reset
clock
gl r2 2026-09-20T09:00:00Z build ran -
E1="$(epoch 2026-09-20T10:00:00Z)"; E2="$(epoch 2026-09-20T12:00:00Z)"
echo "2026-09-20T10:00:00Z | OUTCOME | build | start | at=$E1" >> "$KITLOG/runs/r2.log"
echo "2026-09-20T12:00:00Z | OUTCOME | build | end | at=$E2 caught=false dur_s=7200" >> "$KITLOG/runs/r2.log"
for spec in "r3 2026-09-21T10:00:00Z 2026-09-21T14:00:00Z" "r4 2026-09-21T11:00:00Z 2026-09-21T15:00:00Z"; do
  set -- $spec
  gl "$1" "$2" build ran -
  echo "$2 | OUTCOME | build | start | at=$(epoch "$2")" >> "$KITLOG/runs/$1.log"
  echo "$3 | OUTCOME | build | end | at=$(epoch "$3") caught=false dur_s=1" >> "$KITLOG/runs/$1.log"
done
mk_sub "$SLUG" sess2 w1 kit:task-verifier "no tag here" 2026-09-20T11:00:00.000Z
mk_sub "$SLUG" sess2 w2 kit:task-verifier "no tag here either" 2026-09-21T12:30:00.000Z
mk_sub "$SLUG" sess2 w3 kit:task-verifier "no tag, outside all" 2026-09-19T03:00:00.000Z
J="$(RJ)"
eq "S-window r2 attributed" "$(jq '.runs[] | select(.rid=="r2") | .dispatches' <<<"$J")" 1
eq "S-window join window=1" "$(jq '.dispatch.rid_source.window' <<<"$J")" 1
eq "S-ambiguous join ambiguous=1" "$(jq '.dispatch.rid_source.ambiguous' <<<"$J")" 1
eq "S-ambiguous r3 has none" "$(jq '.runs[] | select(.rid=="r3") | .dispatches' <<<"$J")" null
eq "S-ambiguous r4 has none" "$(jq '.runs[] | select(.rid=="r4") | .dispatches' <<<"$J")" null
eq "S-none join none=1" "$(jq '.dispatch.rid_source.none' <<<"$J")" 1
eq "S-none only the window dispatch is attributed" "$(jq '.dispatch.attributed' <<<"$J")" 1

echo "== S-tokens: a repeated message id counts its LAST line (290), not the sum (295) =="
reset
clock
gl r5 2026-09-20T09:00:00Z build ran -
mk_sub "$SLUG" sess3 t1 kit:task-verifier "rid=r5" 2026-09-20T10:00:00.000Z
J="$(RJ)"
eq "S-tokens output 290" "$(jq '.runs[] | select(.rid=="r5") | .tokens.output' <<<"$J")" 290
eq "S-tokens net 350 (in 10 + out 290 + cache-creation 50)" "$(jq '.runs[] | select(.rid=="r5") | .tokens_net' <<<"$J")" 350
eq "S-tokens cache-read 100 reported apart" "$(jq '.runs[] | select(.rid=="r5") | .tokens_cache_read' <<<"$J")" 100
has "S-tokens text labels the total incl. cache-read" "total incl. cache-read=450" "$(R ceremony)"

echo "== S-unknown: a run with no attributed dispatch prints ? for dispatches and tokens =="
gl r8 2026-09-20T09:30:00Z grill ran -
J="$(RJ)"
eq "S-unknown dispatches null" "$(jq '.runs[] | select(.rid=="r8") | .dispatches' <<<"$J")" null
eq "S-unknown tokens null" "$(jq '.runs[] | select(.rid=="r8") | .tokens_net' <<<"$J")" null
has "S-unknown text ?" "| r8 | 1 | 1 | 0 | 0 | 1.00 | ? | ? | ? | ? | ? | ? | ? | ? |" "$(R ceremony)"

echo "== S-per-task: tasks=4 and 8 dispatches -> 2.0 per task; no tasks= -> ? =="
reset
clock
gl r6 2026-09-20T09:00:00Z build ran - "tasks=4/4 verified=4 tests=pass"
gl r7 2026-09-20T09:00:00Z build ran - "did some work"
for i in 1 2 3 4 5 6 7 8; do
  mk_sub "$SLUG" sess4 k$i kit:task-verifier "rid=r6 t$i" "2026-09-20T10:0$i:00.000Z"
done
mk_sub "$SLUG" sess4 j1 kit:task-verifier "rid=r7" 2026-09-20T11:00:00.000Z
mk_sub "$SLUG" sess4 j2 kit:task-verifier "rid=r7" 2026-09-20T11:01:00.000Z
J="$(RJ)"
eq "S-per-task r6 tasks" "$(jq '.runs[] | select(.rid=="r6") | .tasks' <<<"$J")" 4
eq "S-per-task r6 2.0" "$(jq '.runs[] | select(.rid=="r6") | .dispatches_per_task == 2' <<<"$J")" true
eq "S-per-task r7 null" "$(jq '.runs[] | select(.rid=="r7") | .dispatches_per_task' <<<"$J")" null

# =============================================================================================
echo "== W-range: gates on days 1-30, --from day 10 --to day 20 -> only days 10..20 =="
reset
for d in $(seq 1 30); do gl w1 "$(printf '2026-09-%02dT10:00:00Z' "$d")" grill ran -; done
eq "W-range default window (last 14 days)" "$(RJ | jq '.records.ceremony')" 15
eq "W-range explicit bounds" "$(RJ --from 2026-09-10T00:00:00Z --to 2026-09-20T23:59:59Z | jq '.records.ceremony')" 11

echo "== W-sha: --since-sha starts the window at that commit's timestamp =="
commit_lines s.txt 2 "feat: marker (#1)" "2026-09-15T12:00:00+00:00"
SHA="$(git -C "$GITREPO" rev-parse HEAD)"
J="$(RJ --since-sha "$SHA")"
eq "W-sha window start" "$(jq -r '.window.start' <<<"$J")" "2026-09-15T12:00:00Z"
eq "W-sha gates from day 16" "$(jq '.records.ceremony' <<<"$J")" 15
R ceremony --since-sha deadbeef >/dev/null; eq "W-sha unknown sha exits 2" "$?" 2

echo "== W-bounded: a commit and a transcript older than the window start are never read =="
commit_lines old2.txt 2 "feat: ancient (#0)" "2026-09-01T00:00:00+00:00"
commit_lines new2.txt 2 "feat: recent (#2)" "2026-09-20T00:00:00+00:00"
eq "W-bounded git_lines holds only in-window commits" \
   "$(uv run stats query "SELECT count(*) AS n FROM git_lines" 2>/dev/null | jq '.[0].n')" 1
old="$SESS/$SLUG/sess-old/subagents"; mkdir -p "$old"
echo '{"agentType":"kit:task-verifier","description":"rid=w1"}' > "$old/agent-old.meta.json"
echo 'this is not json' > "$old/agent-old.jsonl"
TZ=UTC touch -t 202601010000 "$old/agent-old.jsonl" "$old/agent-old.meta.json"
mk_sub "$SLUG" sess-new n1 kit:task-verifier "rid=w1" 2026-09-20T10:00:00.000Z
J="$(RJ)"
eq "W-bounded files seen" "$(jq '.transcripts.files_seen' <<<"$J")" 2
eq "W-bounded files read (old one skipped by mtime)" "$(jq '.transcripts.files_read' <<<"$J")" 1
eq "W-bounded skipped-files 0 (old file never opened)" "$(jq '.transcripts.skipped_files' <<<"$J")" 0
has "W-bounded earliest is the old file's date" "2026-01-01" "$(jq -r '.transcripts.earliest' <<<"$J")"

# raw_sub <session> <id> <ts>: meta for a tag-less dispatch of rid=x1; the caller writes the jsonl
raw_sub() {
  local d="$SESS/$SLUG/$1/subagents"; mkdir -p "$d"
  printf '{"agentType":"kit:task-verifier","description":"rid=x1"}\n' > "$d/agent-$2.meta.json"
  RAWDIR="$d"; RAWID="$2"; RAWTS="$3"
}
raw_touch() { TZ=UTC touch -t "${RAWTS:0:4}${RAWTS:5:2}${RAWTS:8:2}${RAWTS:11:2}${RAWTS:14:2}" "$RAWDIR/agent-$RAWID.jsonl" "$RAWDIR/agent-$RAWID.meta.json"; }
USE='{"type":"assistant","timestamp":"2026-09-20T10:00:00.000Z","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":7,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'

echo "== P-pruned: a window starting before the earliest transcript prints ? for dispatch and token cells =="
reset
gl clk 2026-09-30T00:00:00Z grill ran -
gl p1 2026-09-12T09:00:00Z build ran -
mk_sub "$SLUG" sessp p1a kit:task-verifier "rid=p1" 2026-09-25T10:00:00.000Z
J="$(RJ --from 2026-09-10T00:00:00Z)"
printf '%s' "$J" | jq -e . >/dev/null 2>&1 && ok "P-pruned output is JSON" || bad "P-pruned output is not JSON"
eq "P-pruned dispatch count null" "$(jq '.dispatch.count' <<<"$J")" null
eq "P-pruned tokens null" "$(jq '.dispatch.tokens' <<<"$J")" null
eq "P-pruned run dispatches null" "$(jq '.runs[] | select(.rid=="p1") | .dispatches' <<<"$J")" null
eq "P-pruned earliest still reported" "$(jq -r '.transcripts.earliest' <<<"$J")" "2026-09-25T10:00:00Z"
has "P-pruned text says ?" "dispatches: ? (?)" "$(R ceremony --from 2026-09-10T00:00:00Z)"
J="$(RJ --from 2026-09-25T10:00:00Z)"
eq "P-pruned control: window inside retention counts the dispatch" "$(jq '.dispatch.count' <<<"$J")" 1

echo "== M-malformed / L-lastline / N-noid: bad transcripts inside the window =="
reset
clock
gl m1 2026-09-20T09:00:00Z build ran -
mk_sub "$SLUG" sessm good1 kit:task-verifier "rid=m1" 2026-09-20T10:00:00.000Z
mk_sub "$SLUG" sessm good2 kit:task-verifier "rid=m1" 2026-09-20T10:05:00.000Z
raw_sub sessm bad1 2026-09-20T10:10:00.000Z
{ echo "$USE"; echo '{"usage": not json'; echo "$USE"; } > "$RAWDIR/agent-bad1.jsonl"; raw_touch
raw_sub sessm live1 2026-09-20T10:15:00.000Z
{ echo "$USE"; printf '{"type":"assistant","timestamp":"2026-09-20T10:15:'; } > "$RAWDIR/agent-live1.jsonl"; raw_touch
raw_sub sessm noid1 2026-09-20T10:20:00.000Z
{ echo '{"type":"assistant","timestamp":"2026-09-20T10:20:00.000Z","message":{"usage":{"input_tokens":1,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  echo '{"type":"assistant","timestamp":"2026-09-20T10:20:01.000Z","message":{"usage":{"input_tokens":1,"output_tokens":290,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
} > "$RAWDIR/agent-noid1.jsonl"; raw_touch
J="$(RJ)"
printf '%s' "$J" | jq -e . >/dev/null 2>&1 && ok "M-malformed output is JSON" || bad "M-malformed output is not JSON"
eq "M-malformed skipped-files 1" "$(jq '.transcripts.skipped_files' <<<"$J")" 1
eq "M-malformed files seen 6 (5 + anchor)" "$(jq '.transcripts.files_seen' <<<"$J")" 6
eq "M-malformed siblings still count" "$(jq '.runs[] | select(.rid=="m1") | .dispatches' <<<"$J")" 2
eq "L-lastline truncated last line tolerated (live1 read)" "$(jq '.transcripts.files_read' <<<"$J")" 4
eq "N-noid no id: last line wins, not the sum" \
   "$(uv run stats query "SELECT output_tokens AS o FROM subagent_runs WHERE agent_id='noid1'" 2>/dev/null | jq '.[0].o')" 290

echo "== Q-fifo / Q-symlink: a FIFO transcript never hangs the scan; a symlinked dir is not followed =="
reset
clock
gl q1 2026-09-20T09:00:00Z build ran -
mk_sub "$SLUG" sessq q-ok kit:task-verifier "rid=q1" 2026-09-20T10:00:00.000Z
raw_sub sessq qfifo 2026-09-20T10:05:00.000Z
mkfifo "$RAWDIR/agent-qfifo.jsonl"
mkdir -p "$FIX/outside/sessz/subagents"
cp "$SESS/$SLUG/sessq/subagents/agent-q-ok.meta.json" "$FIX/outside/sessz/subagents/agent-out.meta.json"
cp "$SESS/$SLUG/sessq/subagents/agent-q-ok.jsonl" "$FIX/outside/sessz/subagents/agent-out.jsonl"
ln -s "$FIX/outside" "$SESS/linked-project"
RJ > "$FIX/q.json" &
QPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  kill -0 "$QPID" 2>/dev/null || break
  sleep 2
done
if kill -0 "$QPID" 2>/dev/null; then kill "$QPID" 2>/dev/null; bad "Q-fifo scan hung on a FIFO"; else ok "Q-fifo scan finished"; fi
J="$(cat "$FIX/q.json")"
printf '%s' "$J" | jq -e . >/dev/null 2>&1 && ok "Q-fifo output is JSON" || bad "Q-fifo output is not JSON"
eq "Q-fifo only the regular file counts" "$(jq '.dispatch.count' <<<"$J")" 1
eq "Q-symlink linked project not followed (regular + fifo + anchor seen only)" "$(jq '.transcripts.files_seen' <<<"$J")" 3
rm -f "$RAWDIR/agent-qfifo.jsonl"; rm -f "$SESS/linked-project"

echo "== F-casefold: Ship and ship are one gate; Build is progress, not ceremony =="
reset
gl f1 2026-09-20T10:00:00Z Ship ran -
gl f1 2026-09-20T10:01:00Z ship ran -
gl f1 2026-09-20T10:02:00Z Build ran -
gl f1 2026-09-20T10:03:00Z build ran -
J="$(RJ)"
eq "F-casefold by_gate" "$(jq -c '.records.by_gate' <<<"$J")" '{"build":2,"ship":2}'
eq "F-casefold no ceremony records" "$(jq '.records.ceremony' <<<"$J")" 0

echo "== E-empty: a window with no GATE records is an honest empty state, exit 0 =="
reset
OUT="$(R ceremony)"; RC=$?
eq "E-empty exit 0" "$RC" 0
has "E-empty says 0 gate records" "of 0 gate records" "$OUT"
nofire "E-empty anomaly stays quiet" "$(RA anomalies --json)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
rm -rf "$FIX"
[ "$FAIL" -eq 0 ]
