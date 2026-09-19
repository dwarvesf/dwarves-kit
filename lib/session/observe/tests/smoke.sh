#!/usr/bin/env bash
# session-observe smoke test. Parses tests/fixtures/sample.jsonl (a synthetic transcript
# with a known Skill, two Bash calls (one errored), a Read, and a system entry whose
# hookInfos carries a deliberately slow hook (500ms) next to a fast one (12ms)).
#
# Run: bash tests/smoke.sh
# Pass: prints "smoke: all N passed", exit 0. Fail: prints which, exit 1.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CC="${DIR}/bin/session-observe"
CS="${DIR}/bin/session-semantic"                         # SG-04 LLM-derived signals
FIX="${DIR}/tests/fixtures/sample.jsonl"
SEMOUT="${DIR}/tests/fixtures/semantic-llm-out.json"  # injected fake model response
SFIX="${DIR}/tests/fixtures/session-sample.jsonl"  # clean session (no sidechain) for archetype/circadian
LFIX="${DIR}/tests/fixtures/skill-latency-sample.jsonl"  # per-skill wall-time: tiny-frequent 3x50ms=150, rare-slow 1x100ms=100
GFIX="${DIR}/tests/fixtures/goal-hook-sample.jsonl"  # /goal Stop hooks: alpha x3, beta x2 (both first-word "Drive"), gamma x2 (prose mentions build.sh), + one real script hook

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] skills: prose-rag counted once"
out="$("$CC" skills --file "$FIX")"
if grep -q 'prose-rag' <<<"$out" && grep -Eq 'prose-rag[[:space:]]+1' <<<"$out"; then ok "skill prose-rag count 1"; else no "skills output: $out"; fi

echo "[2] tools: Bash counted (3: ls, echo, denied deploy) with two errors"
out="$("$CC" tools --file "$FIX")"
if grep -Eq 'Bash[[:space:]]+3[[:space:]]+2' <<<"$out"; then ok "Bash count 3, errors 2"; else no "tools output: $out"; fi

echo "[3] tools: Read present (count 1, no error)"
if grep -Eq 'Read[[:space:]]+1[[:space:]]+0' <<<"$out"; then ok "Read count 1, errors 0"; else no "Read row wrong: $out"; fi

echo "[4] hooks: slow hook flagged with max >= 500 (negative control vs fast hook)"
out="$("$CC" hooks --file "$FIX")"
slowmax="$(awk '/slow-hook\.sh/ {print $5}' <<<"$out")"
if grep -q 'slow-hook.sh' <<<"$out" && [[ "${slowmax:-0}" -ge 500 ]]; then ok "slow-hook.sh maxms=${slowmax}"; else no "slow hook not flagged: $out"; fi

echo "[5] hooks: fast inline-echo hook stays small (< 100ms)"
fastmax="$(awk '/inline-echo/ {print $5}' <<<"$out")"
if [[ -n "${fastmax:-}" && "${fastmax}" -lt 100 ]]; then ok "inline-echo maxms=${fastmax} (negative control)"; else no "fast hook wrong: $out"; fi

echo "[6] hooks: hook error surfaced (count 1)"
if grep -q '1 hook errors' <<<"$out"; then ok "1 hook error surfaced"; else no "hook errors not surfaced: $out"; fi

echo "[7] --json emits valid JSON"
if "$CC" report --file "$FIX" --json | python3 -m json.tool >/dev/null 2>&1; then ok "valid json"; else no "json invalid"; fi

echo "[8] missing file -> exit 1"
set +e; "$CC" skills --file "${DIR}/tests/fixtures/nope.jsonl" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 1 ]]; then ok "exit 1 on missing file"; else no "got rc=$rc"; fi

echo "[9] report runs all sections"
out="$("$CC" report --file "$FIX")"
if grep -q '# skills' <<<"$out" && grep -q '# tools' <<<"$out" && grep -q '# hooks' <<<"$out" && grep -q '# subagents' <<<"$out" && grep -q '# friction' <<<"$out" && grep -q '# sessions' <<<"$out" && grep -q '# cost' <<<"$out"; then ok "report has all sections"; else no "report incomplete"; fi

echo "[10] subagents: 2 main-session spawns on 2026-06-14, 1 prompt, per100=200.0"
out="$("$CC" subagents --file "$FIX")"
if grep -Eq '2026-06-14[[:space:]]+2[[:space:]]+1[[:space:]]+200.0' <<<"$out"; then ok "day row 2 spawns / 1 prompt / per100 200.0"; else no "subagents day row wrong: $out"; fi

echo "[11] subagents: sidechain spawn EXCLUDED (negative control: total 2 not 3, Explore 1 not 2)"
if grep -q '2 spawns' <<<"$out" && grep -Eq 'Explore[[:space:]]+1[[:space:]]' <<<"$out"; then ok "sidechain Explore excluded (total 2, Explore 1)"; else no "sidechain not excluded: $out"; fi

echo "[12] subagents: general-purpose type counted"
if grep -Eq 'general-purpose[[:space:]]+1[[:space:]]' <<<"$out"; then ok "general-purpose type counted"; else no "type table wrong: $out"; fi

echo "[13] friction thrash: /x/thrash.py edited 3x in 1 session"
out="$("$CC" friction --file "$FIX")"
if grep -Eq '/x/thrash.py[[:space:]]+1[[:space:]]+3' <<<"$out"; then ok "thrash.py 1 session / 3 max-edits"; else no "thrash wrong: $out"; fi

echo "[14] friction thrash negative control: /x/once.py (edited once) NOT flagged"
if ! grep -q '/x/once.py' <<<"$out"; then ok "once.py excluded (< THRASH_MIN)"; else no "once.py wrongly flagged: $out"; fi

echo "[15] friction permission: Bash:deploy denial attributed (1)"
if grep -Eq 'Bash:deploy[[:space:]]+1' <<<"$out"; then ok "permission friction Bash:deploy 1"; else no "perm wrong: $out"; fi

echo "[16] friction context-pressure: 1 compaction on 2026-06-14"
if grep -Eq '2026-06-14[[:space:]]+1' <<<"$out"; then ok "compaction 2026-06-14 = 1"; else no "compaction wrong: $out"; fi

echo "[17] friction skill-precision: flaky-skill 100% inert"
if grep -Eq 'flaky-skill[[:space:]]+1[[:space:]]+1[[:space:]]+100%' <<<"$out"; then ok "flaky-skill inert 100%"; else no "skill-precision wrong: $out"; fi

echo "[18] friction skill-precision negative control: prose-rag (succeeded) NOT in precision"
if ! grep -Eq 'prose-rag[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+%' <<<"$out"; then ok "prose-rag excluded from precision (no mis-fire)"; else no "prose-rag wrongly in precision: $out"; fi

echo "[19] sessions archetype: the 10.5-min / 2-turn session classifies as standard"
out="$("$CC" sessions --file "$SFIX")"
if grep -Eq 'standard[[:space:]]+1[[:space:]]+100%' <<<"$out"; then ok "archetype standard 1 (100%)"; else no "archetype wrong: $out"; fi

echo "[20] sessions interruption: 1 interrupt of 2 turns (negative control: clean turn not counted)"
if grep -q '1 interrupted, 1 interrupts' <<<"$out"; then ok "1 interrupt / 1 session (clean turn excluded)"; else no "interruption wrong: $out"; fi

echo "[21] sessions circadian: hour 08 has 2 turns / 2 tools"
if grep -Eq '08[[:space:]]+2[[:space:]]+2' <<<"$out"; then ok "circadian hour 08 = 2 turns 2 tools"; else no "circadian wrong: $out"; fi

echo "[22] sessions archetype negative control: main fixture (has sidechain) classifies NO session"
out="$("$CC" sessions --file "$FIX")"
if grep -q 'archetype mix:' <<<"$out" && ! grep -Eq '(quick|standard|deep|marathon|automation)[[:space:]]+[0-9]+[[:space:]]+[0-9]+%' <<<"$out"; then ok "sidechain transcript excluded from archetype"; else no "sidechain wrongly classified: $out"; fi

echo "[23] cost by-model: opus est \$93.22 (1M in / 1M out / 900k cache-rd / 100k cache-wr)"
out="$("$CC" cost --file "$FIX")"
if grep -Eq 'claude-opus-4-8[[:space:]]+1000000[[:space:]]+1000000[[:space:]]+900000[[:space:]]+100000[[:space:]]+\$93.22' <<<"$out"; then ok "opus row + est\$93.22"; else no "cost opus row wrong: $out"; fi

echo "[24] cost: haiku priced at \$0.80 (1M input)"
if grep -Eq 'claude-haiku-4-5-20251001[[:space:]]+1000000.+\$0.80' <<<"$out"; then ok "haiku \$0.80"; else no "haiku cost wrong: $out"; fi

echo "[25] cost negative control: fable (unknown family) counts tokens but shows ? not \$"
if grep -Eq 'claude-fable-5[[:space:]]+1000000.+[[:space:]]\?$' <<<"$out"; then ok "fable tokens counted, \$ = ? (unknown pricing)"; else no "fable should be ?: $out"; fi

echo "[26] cost cache-hit ratio: 90% (900k read / 100k write) in header"
if grep -q 'cache-hit 90%' <<<"$out"; then ok "cache-hit 90%"; else no "cache-hit wrong: $out"; fi

echo "[27] session-semantic: injected model output -> topics + self-corrections, propose-only banner"
out="$(SESSION_SEMANTIC_CMD="cat $SEMOUT" "$CS" --root "$DIR/tests/fixtures" --days 0)"
if grep -q 'session-observe tooling' <<<"$out" && grep -q 'self-corrections: 1' <<<"$out" && grep -q 'PROPOSAL ONLY' <<<"$out"; then ok "topics + corrections + propose-only banner"; else no "session-semantic output wrong: $out"; fi

echo "[28] session-semantic negative control: failing command -> _unavailable_ (never fabricates)"
out="$(SESSION_SEMANTIC_CMD="false" "$CS" --root "$DIR/tests/fixtures" --days 0)"
if grep -q '_unavailable_' <<<"$out"; then ok "degrades to _unavailable_ on command failure"; else no "should be unavailable: $out"; fi

echo "[29] session-semantic: no prompts in window -> empty (no proposal)"
out="$("$CS" --root /tmp/session-semantic-none-$$ --days 0)"
if grep -q 'no prompts' <<<"$out"; then ok "empty window handled"; else no "empty path wrong: $out"; fi

echo "[30] session-semantic --json: valid JSON with status ok"
if SESSION_SEMANTIC_CMD="cat $SEMOUT" "$CS" --root "$DIR/tests/fixtures" --days 0 --json | python3 -m json.tool >/dev/null 2>&1; then ok "valid json"; else no "json invalid"; fi

echo "[31] skills --latency: tiny-frequent total 150ms over 3 fires (max 50)"
out="$("$CC" skills --latency --file "$LFIX")"
if grep -Eq 'tiny-frequent[[:space:]]+3[[:space:]]+150[[:space:]]+50[[:space:]]+50[[:space:]]+50' <<<"$out"; then ok "tiny-frequent fires 3 / total 150 / max 50"; else no "skill wall-time tiny-frequent wrong: $out"; fi

echo "[32] skills --latency: rare-slow total 100ms over 1 fire (max 100)"
if grep -Eq 'rare-slow[[:space:]]+1[[:space:]]+100[[:space:]]+100[[:space:]]+100[[:space:]]+100' <<<"$out"; then ok "rare-slow fires 1 / total 100 / max 100"; else no "skill wall-time rare-slow wrong: $out"; fi

echo "[33] skills --latency: ranked by TOTAL not max (tiny-frequent 150 above rare-slow 100, death-by-a-thousand-cuts)"
tf="$(awk '/# skill wall-time/{f=1} f&&/tiny-frequent/{print NR; exit}' <<<"$out")"
rs="$(awk '/# skill wall-time/{f=1} f&&/rare-slow/{print NR; exit}' <<<"$out")"
if [[ -n "$tf" && -n "$rs" && "$tf" -lt "$rs" ]]; then ok "tiny-frequent (line $tf) ranked above rare-slow (line $rs)"; else no "sort-by-total wrong: tf=$tf rs=$rs : $out"; fi

echo "[34] skills (no --latency) negative control: wall-time table NOT printed"
out="$("$CC" skills --file "$LFIX")"
if ! grep -q '# skill wall-time' <<<"$out"; then ok "wall-time table absent without --latency (existing view unchanged)"; else no "wall-time leaked into default skills view: $out"; fi

echo "[35] skills --latency --json: skill_latency present, ranked by total_ms"
jout="$("$CC" skills --latency --file "$LFIX" --json)"
if echo "$jout" | python3 -c 'import json,sys; d=json.load(sys.stdin); sl=d["skill_latency"]; assert sl[0]["skill"]=="tiny-frequent" and sl[0]["total_ms"]==150 and sl[0]["fires"]==3, sl; assert sl[1]["skill"]=="rare-slow" and sl[1]["total_ms"]==100, sl'; then ok "json skill_latency ranked + correct totals"; else no "json skill_latency wrong: $jout"; fi

echo "[36] hooks: the alpha /goal Stop hook (fired 3 turns) collapses to ONE hash-keyed row of count 3 (not N first-word rows)"
gjson="$("$CC" hooks --file "$GFIX" --json)"
if echo "$gjson" | python3 -c '
import json,sys,hashlib
d=json.load(sys.stdin)
# recompute the inline-echo label for the alpha goal command straight from the fixture
import re
cmds=[]
for line in open(sys.argv[1],encoding="utf-8"):
    line=line.strip()
    if not line: continue
    e=json.loads(line)
    for h in e.get("hookInfos") or []:
        cmds.append(h["command"])
alpha=cmds[0].strip()
lab="inline-echo:"+hashlib.sha1(alpha.encode()).hexdigest()[:8]
rows=[h for h in d["hooks"] if h["hook"]==lab]
assert len(rows)==1, ("alpha goal not a single row: "+str(rows))
assert rows[0]["count"]==3, ("alpha goal count != 3 (turns merged wrong): "+str(rows[0]))
' "$GFIX"; then ok "alpha goal = one inline-echo row, count 3"; else no "alpha goal row wrong: $gjson"; fi

echo "[37] hooks: each unique /goal collapses to its own row (3 distinct inline-echo rows, counts 3/2/2)"
if echo "$gjson" | python3 -c '
import json,sys
d=json.load(sys.stdin)
ie=sorted(h["count"] for h in d["hooks"] if h["hook"].startswith("inline-echo:"))
assert ie==[2,2,3], ("expected 3 inline-echo rows with counts [2,2,3], got "+str(ie))
'; then ok "3 inline-echo rows, counts [2,2,3]"; else no "inline-echo rows wrong: $gjson"; fi

echo "[38] hooks negative control: first-word 'Drive' merge bug gone (no row labelled exactly 'Drive')"
if echo "$gjson" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert not any(h["hook"]=="Drive" for h in d["hooks"]), "a first-word Drive row survived (alpha+beta wrongly merged)"
'; then ok "no first-word 'Drive' row (alpha/beta not merged)"; else no "Drive merge row present: $gjson"; fi

echo "[39] hooks negative control: prose-mentioned filename not mislabelled (no phantom 'build.sh' row)"
if echo "$gjson" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert not any(h["hook"]=="build.sh" for h in d["hooks"]), "gamma goal mislabelled as build.sh (regex matched prose, not the executable)"
'; then ok "no phantom 'build.sh' row from gamma prose"; else no "build.sh phantom row present: $gjson"; fi

echo "[40] hooks negative control: a REAL script hook still labels by basename (real-hook.sh, count 1)"
if echo "$gjson" | python3 -c '
import json,sys
d=json.load(sys.stdin)
rows=[h for h in d["hooks"] if h["hook"]=="real-hook.sh"]
assert len(rows)==1 and rows[0]["count"]==1, ("real script hook label/count changed: "+str(rows))
'; then ok "real-hook.sh unchanged (script-hook labelling preserved)"; else no "real script hook wrong: $gjson"; fi

BURNFIX="${DIR}/tests/fixtures/burn"     # fake projects root: proj-a/<sid>.jsonl [+ subagents/], pids/<pid>.json
BURNNOW="2026-09-10T08:00:00Z"           # fixed simulated clock (SESSION_OBSERVE_NOW), paired with fixed fixture timestamps
# Pin every burn fixture's mtime safely after BURNNOW so the coarse file-mtime
# skip (real disk time) never races the simulated clock above.
python3 -c "
import os, glob, calendar, time
epoch = calendar.timegm(time.strptime('2026-09-10T09:00:00Z', '%Y-%m-%dT%H:%M:%SZ'))
for p in glob.glob(os.path.join('$BURNFIX', '**', '*.jsonl'), recursive=True):
    os.utime(p, (epoch, epoch))
"

echo "[41] burn: streamed-chunk repeat of (message.id, requestId) collapses to one req (session A reqs=4, not 5)"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" SESSION_OBSERVE_PIDS_DIR="$BURNFIX/pids" "$CC" burn --root "$BURNFIX" --since 60)"
if grep -Eq 'aaaaaaaa[[:space:]]+55555[[:space:]]+/x/proj-a[[:space:]]+4[[:space:]]' <<<"$out"; then ok "session A reqs=4 (dup chunk deduped)"; else no "session A reqs wrong: $out"; fi

echo "[42] burn: subagent transcript rolls into its parent (subs=1, cache-wr/cache-rd/out fold in its tokens)"
if grep -Eq 'aaaaaaaa[[:space:]]+55555[[:space:]]+/x/proj-a[[:space:]]+4[[:space:]]+1[[:space:]]+601[[:space:]]+206500[[:space:]]+11100[[:space:]]+90' <<<"$out"; then ok "session A subs=1, cache-wr=206500, cache-rd=11100, out=90 (subagent tokens folded in)"; else no "session A rollup wrong: $out"; fi

echo "[43] burn: ctx ignores sidechain usage (601 from the last main-chain entry, not the larger sidechain one)"
if grep -q '[[:space:]]601[[:space:]]' <<<"$out" && ! grep -q '10020' <<<"$out"; then ok "ctx=601, sidechain entry's larger total (10020) absent"; else no "ctx leaked sidechain usage: $out"; fi

echo "[44] burn: rank order, high cache-write session A outranks higher-reqs low-token session B"
al="$(awk '/^  aaaaaaaa/{print NR; exit}' <<<"$out")"
bl="$(awk '/^  bbbbbbbb/{print NR; exit}' <<<"$out")"
if [[ -n "$al" && -n "$bl" && "$al" -lt "$bl" ]]; then ok "A (line $al) ranked above B (line $bl)"; else no "rank order wrong: A=$al B=$bl : $out"; fi

echo "[45] burn: PID maps via SESSION_OBSERVE_PIDS_DIR (session A -> 55555); unmapped session B shows -"
if grep -Eq '^  aaaaaaaa[[:space:]]+55555' <<<"$out" && grep -Eq '^  bbbbbbbb[[:space:]]+-[[:space:]]' <<<"$out"; then ok "A mapped to 55555, B shows -"; else no "pid mapping wrong: $out"; fi

echo "[46] burn --since 60 (default): session C's entry (2h old) predates the cutoff, row absent"
if ! grep -q 'cccccccc' <<<"$out"; then ok "session C absent under --since 60"; else no "session C wrongly present: $out"; fi

echo "[47] burn --since 180: negative control of [46], the same old entry is now inside the window"
out2="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --root "$BURNFIX" --since 180)"
if grep -Eq 'cccccccc[[:space:]]+-[[:space:]]+/x/proj-c[[:space:]]+1[[:space:]]' <<<"$out2"; then ok "session C present under --since 180 (reqs=1)"; else no "session C not counted with wider window: $out2"; fi

echo "[48] burn --json: valid JSON, window_min echoes --since, sessions in rank order"
jout="$(SESSION_OBSERVE_NOW="$BURNNOW" SESSION_OBSERVE_PIDS_DIR="$BURNFIX/pids" "$CC" burn --root "$BURNFIX" --since 60 --json)"
if echo "$jout" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["window_min"] == 60, d
sids = [s["session_id"] for s in d["sessions"]]
assert sids[0].startswith("aaaaaaaa") and sids[1].startswith("bbbbbbbb"), sids
'; then ok "json window_min=60, rank order A then B"; else no "json wrong: $jout"; fi

echo "[49] report has no burn section (existing views unchanged)"
out="$("$CC" report --file "$FIX")"
if ! grep -q '# burn' <<<"$out"; then ok "report has no burn section"; else no "burn leaked into report: $out"; fi

BEDGE="${DIR}/tests/burn-edge"   # single-file edge-case fixtures for F1-F4/F6, deliberately OUTSIDE tests/fixtures/
                                  # (f1's non-dict top-level line would otherwise also break session-semantic's
                                  # own --root tests/fixtures walk, an unrelated tool with the same un-scoped bug)
BURNFIX5="${DIR}/tests/fixtures/burn5"    # isolated root for the F5 mtime-skip case, kept apart from $BURNFIX's rank-order assertions above

echo "[50] burn F1: non-dict top-level JSONL line (\"[\\\"x\\\"]\") does not crash; valid session's row still printed"
set +e
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --file "$BEDGE/f1-baddict.jsonl" --since 60 2>&1)"
rc=$?
set -e
if [[ $rc -eq 0 ]] && grep -q 'f1-baddi' <<<"$out"; then ok "F1 non-dict entry skipped, exit 0, valid session row present"; else no "F1 crashed or row missing (rc=$rc): $out"; fi

echo "[51] burn F2: non-dict message / non-dict usage fields do not crash; valid session's row still printed"
set +e
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --file "$BEDGE/f2-badmsg.jsonl" --since 60 2>&1)"
rc=$?
set -e
if [[ $rc -eq 0 ]] && grep -q 'f2-badms' <<<"$out"; then ok "F2 non-dict message/usage skipped, exit 0, valid session row present"; else no "F2 crashed or row missing (rc=$rc): $out"; fi

echo "[52] burn F3: a sessions pid file that is valid JSON but not an object does not crash; valid session's row still printed"
set +e
out="$(SESSION_OBSERVE_NOW="$BURNNOW" SESSION_OBSERVE_PIDS_DIR="$BEDGE/pids" "$CC" burn --file "$BEDGE/f3-session.jsonl" --since 60 2>&1)"
rc=$?
set -e
if [[ $rc -eq 0 ]] && grep -q 'f3-sessi' <<<"$out"; then ok "F3 non-dict pid file skipped, exit 0, valid session row present"; else no "F3 crashed or row missing (rc=$rc): $out"; fi

echo "[53] burn F4: two id-less usage entries (msg.id and requestId both None) count as reqs=2, not merged into 1"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --file "$BEDGE/f4-noids.jsonl" --since 60)"
if grep -Eq 'f4-noids[[:space:]]+-[[:space:]]+/x/proj-f4[[:space:]]+2[[:space:]]' <<<"$out"; then ok "F4 reqs=2 for two id-less entries (not deduped to 1)"; else no "F4 dedup wrong: $out"; fi

echo "[54] burn F5: a fixture file mtime BEFORE the --since cutoff is skipped (coarse file-mtime skip fires)"
python3 -c "
import os, calendar, time
epoch = calendar.timegm(time.strptime('2026-09-10T06:00:00Z', '%Y-%m-%dT%H:%M:%SZ'))
os.utime('$BURNFIX5/proj-d/dddddddd.jsonl', (epoch, epoch))
"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --root "$BURNFIX5" --since 60)"
if ! grep -q 'dddddddd' <<<"$out"; then ok "session absent, file mtime predates cutoff"; else no "session wrongly present despite old mtime: $out"; fi

echo "[55] burn F5 negative control: same file, mtime moved INSIDE the window -> session now present"
python3 -c "
import os, calendar, time
epoch = calendar.timegm(time.strptime('2026-09-10T07:30:00Z', '%Y-%m-%dT%H:%M:%SZ'))
os.utime('$BURNFIX5/proj-d/dddddddd.jsonl', (epoch, epoch))
"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --root "$BURNFIX5" --since 60)"
if grep -Eq 'dddddddd[[:space:]]+-[[:space:]]+/x/proj-d[[:space:]]+1[[:space:]]' <<<"$out"; then ok "session present once mtime is inside the window"; else no "session should be present: $out"; fi

echo "[56] burn F6: ctx uses the LAST main-chain usage in file order, even with no timestamp (ctx=7001, not 900001)"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --file "$BEDGE/f6-ctxorder.jsonl" --since 60)"
if grep -Eq 'f6-ctxor[[:space:]]+-[[:space:]]+/x/proj-f6[[:space:]]+1[[:space:]]+0[[:space:]]+7001[[:space:]]+0[[:space:]]+900000[[:space:]]+1[[:space:]]' <<<"$out"; then ok "F6 ctx=7001 (last main-chain entry wins, timestamp irrelevant)"; else no "F6 ctx wrong: $out"; fi

NEDGE="${DIR}/tests/nondict-edge"   # non-dict-line/message fixtures for cost/report/session-semantic, OUTSIDE tests/fixtures/

echo "[57] cost: a non-dict top-level JSONL line (\"[\\\"x\\\"]\") does not crash; the valid entry is still counted"
out="$("$CC" cost --file "$BEDGE/f1-baddict.jsonl")"
if grep -Eq 'claude-sonnet-5[[:space:]]+1[[:space:]]+1[[:space:]]+1[[:space:]]+1' <<<"$out"; then ok "F1 non-dict line skipped, valid entry counted"; else no "F1 cost wrong: $out"; fi

echo "[58] report: a non-dict message and non-dict usage field do not crash any section; the valid entry is still counted"
out="$("$CC" report --file "$BEDGE/f2-badmsg.jsonl")"
if grep -q '^# cost' <<<"$out" && grep -Eq 'claude-sonnet-5[[:space:]]+1[[:space:]]+1[[:space:]]+1[[:space:]]+1' <<<"$out"; then ok "F2 non-dict message/usage skipped, report ran end to end, valid entry counted"; else no "F2 report wrong: $out"; fi

echo "[59] session-semantic: a non-dict top-level line and a non-dict user message are skipped; the two valid prompts are still sampled"
out="$(SESSION_SEMANTIC_CMD="cat $SEMOUT" "$CS" --root "$NEDGE" --days 0 --json)"
if grep -q '"prompts": 2' <<<"$out"; then ok "2 valid prompts sampled, non-dict line/message skipped"; else no "session-semantic nondict-edge wrong: $out"; fi

echo "[60] burn F7: model share is PRICED, not token-counted; equal opus and sonnet tokens read 83/17, not 50/50"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --file "$BEDGE/f7-priced.jsonl" --since 60 2>&1)"
if grep -q 'opus 83% sonnet 17%' <<<"$out"; then ok "F7 equal tokens priced 83/17 (opus lists at 5x sonnet on every axis)"; else no "F7 share not priced: $out"; fi

echo "[61] burn F8: one unknown family (fable) drops the whole row to the token weight, marked with a tilde"
out="$(SESSION_OBSERVE_NOW="$BURNNOW" "$CC" burn --file "$BEDGE/f8-unpriced.jsonl" --since 60 2>&1)"
if grep -q 'opus 50% fable 50% ~' <<<"$out"; then ok "F8 unpriced row falls back to token weight, tilde present"; else no "F8 fallback wrong: $out"; fi

EFIX="${DIR}/tests/fixtures/entryfee"   # fake projects root for entry-fee:
# proj-alpha fees 1000 (2026-09-01) / 2000 / 3000, proj-beta fee 500, plus two
# negative controls (a subagents/ transcript at 99999, a sidechain-only transcript).

echo "[62] entry-fee: 4 sessions across 2 projects, median measured fee 2000"
out="$("$CC" entry-fee --root "$EFIX")"
if grep -q '4 sessions, 2 projects' <<<"$out" && grep -q 'median 2000 tokens' <<<"$out"; then ok "4 sessions / 2 projects / median 2000"; else no "entry-fee header wrong: $out"; fi

echo "[63] entry-fee: component split sized at 4 chars/token (instructions 800 chars -> 200, skill_listing 400 -> 100)"
if grep -Eq 'instructions[[:space:]]+200[[:space:]]+10%' <<<"$out" && grep -Eq 'skill_listing[[:space:]]+100[[:space:]]+5%' <<<"$out"; then ok "instructions 200 (10%), skill_listing 100 (5%)"; else no "component split wrong: $out"; fi

echo "[64] entry-fee: unattributed = measured fee minus the sized components (2000 - 350 = 1650)"
if grep -Eq '\(unattributed\)[[:space:]]+1650[[:space:]]+82%' <<<"$out"; then ok "unattributed 1650 (82%)"; else no "unattributed wrong: $out"; fi

echo "[65] entry-fee negative control: a subagents/ transcript is excluded (its 99999 fee absent, proj-alpha stays 3 sessions)"
if ! grep -q '99999' <<<"$out" && grep -Eq 'proj-alpha[[:space:]]+3[[:space:]]+2000' <<<"$out"; then ok "subagent transcript excluded"; else no "subagent transcript counted: $out"; fi

echo "[66] entry-fee negative control: a sidechain-only transcript contributes no session (4, not 5)"
if ! grep -q '5 sessions' <<<"$out" && ! grep -q '88888' <<<"$out"; then ok "sidechain-only transcript excluded"; else no "sidechain transcript counted: $out"; fi

echo "[67] entry-fee negative control: a later, larger turn does not replace the FIRST-turn fee (2000, not 18000)"
if ! grep -q '18000' <<<"$out"; then ok "first-turn usage wins (18000 second turn ignored)"; else no "later turn overwrote the fee: $out"; fi

echo "[68] entry-fee per repo: proj-beta's smaller preamble is its own row (1 session, median 500)"
if grep -Eq 'proj-beta[[:space:]]+1[[:space:]]+500' <<<"$out"; then ok "proj-beta 1 session / median 500"; else no "per-repo rows wrong: $out"; fi

echo "[69] entry-fee --trend: weekly medians, newest first (2026-W37 3/2000 above 2026-W36 1/1000)"
tout="$("$CC" entry-fee --root "$EFIX" --trend)"
w37="$(awk '/^  2026-W37/{print NR; exit}' <<<"$tout")"
w36="$(awk '/^  2026-W36/{print NR; exit}' <<<"$tout")"
if grep -Eq '2026-W37[[:space:]]+3[[:space:]]+2000' <<<"$tout" && grep -Eq '2026-W36[[:space:]]+1[[:space:]]+1000' <<<"$tout" && [[ -n "$w37" && -n "$w36" && "$w37" -lt "$w36" ]]; then ok "W37 3/2000 (line $w37) above W36 1/1000 (line $w36)"; else no "trend wrong: $tout"; fi

echo "[70] entry-fee negative control: without --trend the weekly table is absent"
if ! grep -q 'weekly trend' <<<"$out"; then ok "weekly table absent without --trend"; else no "trend leaked into the default view: $out"; fi

echo "[71] entry-fee --project resolves a bare repo name to its slug (alpha -> proj-alpha only)"
pout="$("$CC" entry-fee --root "$EFIX" --project alpha)"
if grep -q '3 sessions, 1 projects' <<<"$pout" && ! grep -q 'proj-beta' <<<"$pout"; then ok "bare name alpha resolved to proj-alpha (3 sessions, beta absent)"; else no "project resolution wrong: $pout"; fi

echo "[72] entry-fee --json: valid JSON, median_fee 2000, split flagged as an estimate"
jout="$("$CC" entry-fee --root "$EFIX" --trend --json)"
if echo "$jout" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["sessions"] == 4, d["sessions"]
assert d["median_fee"] == 2000, d["median_fee"]
assert d["components_estimated"] is True and d["chars_per_token"] == 4, d
comps = {c["component"]: c["est_tokens"] for c in d["split_components"]}
assert comps["instructions"] == 200 and comps["skill_listing"] == 100, comps
assert comps["(unattributed)"] == 1650, comps
assert [w["week"] for w in d["by_week"]] == ["2026-W37", "2026-W36"], d["by_week"]
'; then ok "json median_fee 2000, estimated split, weeks newest-first"; else no "entry-fee json wrong: $jout"; fi

echo "[73] report negative control: no entry-fee section (existing views unchanged)"
out="$("$CC" report --file "$FIX")"
if ! grep -q '# entry-fee' <<<"$out"; then ok "report has no entry-fee section"; else no "entry-fee leaked into report: $out"; fi

EEDGE="${DIR}/tests/entryfee-edge"   # entry-fee edge roots, deliberately OUTSIDE tests/fixtures/
# (the untrusted root's numeric-timestamp and non-dict-message lines would otherwise
# also break session-semantic's own --root tests/fixtures walk)

echo "[74] entry-fee: an estimate ABOVE the measured fee prints as an overshoot, never a negative measurement"
out="$("$CC" entry-fee --root "$EEDGE/overshoot")"
if grep -Eq '\(estimate over measured\)[[:space:]]+1000[[:space:]]+-' <<<"$out" && ! grep -q -- '-1000' <<<"$out"; then ok "overshoot row 1000, no negative token count"; else no "overshoot row wrong: $out"; fi

echo "[75] entry-fee: the overshooting component's share reads above 100% (the estimate saying it broke)"
if grep -Eq 'instructions[[:space:]]+2000[[:space:]]+200%' <<<"$out"; then ok "instructions 2000 (200%)"; else no "overshoot share wrong: $out"; fi

echo "[76] entry-fee: untrusted fields (numeric timestamp, dict attachment type, numeric content, non-dict message) do not crash"
set +e
out="$("$CC" entry-fee --root "$EEDGE/untrusted" 2>&1)"
rc=$?
set -e
if [[ $rc -eq 0 ]] && grep -q 'median 700 tokens' <<<"$out"; then ok "exit 0, the valid turn's fee 700 still measured"; else no "untrusted input crashed or row missing (rc=$rc): $out"; fi

echo "[77] entry-fee negative control: the dict-typed attachment contributes no component row"
if ! grep -q 'nested' <<<"$out"; then ok "unhashable attachment type skipped, not keyed"; else no "dict attachment type leaked into the split: $out"; fi

echo "[78] entry-fee: a worktree slug folds into its repo row (2 sessions under one proj-alpha, not two rows)"
out="$("$CC" entry-fee --root "$EEDGE/worktrees")"
if grep -Eq 'proj-alpha[[:space:]]+2[[:space:]]+2000' <<<"$out" && ! grep -q 'wt-one' <<<"$out"; then ok "proj-alpha 2 sessions, worktree slug folded in"; else no "worktree grouping wrong: $out"; fi

echo "[79] entry-fee: a multi-slug --project match is announced on stderr (never a silent merge)"
err="$("$CC" entry-fee --root "$EEDGE/worktrees" --project alpha 2>&1 >/dev/null)"
if grep -q "matched 2 slugs" <<<"$err" && grep -q 'proj-alpha--claude-worktrees-wt-one' <<<"$err"; then ok "multi-match announced with the resolved slugs"; else no "multi-match not announced: $err"; fi

TFIX="${DIR}/tests/fixtures/tool-errors-sample.jsonl"  # 5 Bash errors: 127-msg x3 + exit-1 x2 (whitespace variants), 1 Read error (list-block content)

echo "[80] tools --errors Bash: groups the 5 error results into 2 prefix rows, ranked by count"
out="$("$CC" tools --errors Bash --file "$TFIX")"
if grep -q '# tool errors: Bash' <<<"$out" \
  && grep -Eq 'Exit code 127: command not found: frobnicate[[:space:]]+3[[:space:]]+60%' <<<"$out" \
  && grep -Eq 'Exit code 1 See deploy.log for details[[:space:]]+2[[:space:]]+40%' <<<"$out"; then ok "Bash errors grouped 3+2 with shares"; else no "tools --errors output wrong: $out"; fi

echo "[81] tools --errors: whitespace variants of the same message merge into one row (newline and multi-space)"
if [[ "$(grep -c 'See deploy.log' <<<"$out")" -eq 1 ]]; then ok "whitespace-normalised prefix merged"; else no "whitespace variants did not merge: $out"; fi

echo "[82] tools --errors Read: list-block content extracts the text, not the JSON wrapper"
out="$("$CC" tools --errors Read --file "$TFIX")"
if grep -Eq 'File does not exist\.[[:space:]]+1[[:space:]]+100%' <<<"$out" && ! grep -q 'type.*text' <<<"$out"; then ok "list-block error text extracted"; else no "Read --errors wrong: $out"; fi

echo "[83] tools --errors on a tool with no errors prints an honest empty state"
out="$("$CC" tools --errors Agent --file "$TFIX")"
if grep -q 'no error results recorded for Agent' <<<"$out"; then ok "empty state honest"; else no "empty state wrong: $out"; fi

echo "[84] tools without --errors is unchanged (standard table, no group view leaks)"
out="$("$CC" tools --file "$TFIX")"
if grep -Eq 'Bash[[:space:]]+6[[:space:]]+5' <<<"$out" && ! grep -q '# tool errors' <<<"$out"; then ok "standard tools table unchanged"; else no "tools table wrong or group view leaked: $out"; fi

echo "[85] tools --errors --json: tool_error_groups carries the same groups"
jout="$("$CC" tools --errors Bash --file "$TFIX" --json)"
if echo "$jout" | python3 -c '
import json,sys
d=json.load(sys.stdin)
g=d["tool_error_groups"]
assert g["tool"]=="Bash" and g["total"]==5, g
assert g["groups"][0]["prefix"].startswith("Exit code 127") and g["groups"][0]["count"]==3, g
assert len(g["groups"])==2, g
'; then ok "json tool_error_groups correct"; else no "json groups wrong: $jout"; fi

echo "[86] --errors on a non-tools view refuses (exit 2, no silent ignore)"
set +e; "$CC" skills --errors Bash --file "$TFIX" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 2 ]]; then ok "non-tools --errors exits 2"; else no "got rc=$rc"; fi

echo "[87] --errors on report refuses too (the report view stays unchanged)"
set +e; "$CC" report --errors Bash --file "$TFIX" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 2 ]]; then ok "report --errors exits 2"; else no "got rc=$rc"; fi

FREXFIX="${DIR}/tests/fixtures/skill-freshness-sample.jsonl"  # fresh-skill fires 09-10 + 09-18, stale-skill fires 06-01 only
FRNOW="2026-09-19T00:00:00Z"  # so 09-10/09-18 fall inside the 14d window and 06-01 falls outside it

echo "[88] skills: 14d column counts only fires inside the window, last carries the most recent fire date"
out="$(SESSION_OBSERVE_NOW="$FRNOW" "$CC" skills --file "$FREXFIX")"
if grep -Eq 'fresh-skill[[:space:]]+2[[:space:]]+0[[:space:]]+0%[[:space:]]+2[[:space:]]+2026-09-18' <<<"$out"; then ok "fresh-skill count 2, 14d 2, last 2026-09-18"; else no "fresh-skill row wrong: $out"; fi

echo "[89] skills negative control: a skill fired only outside the window still shows count 1 but 14d 0 (rotting, not hidden)"
if grep -Eq 'stale-skill[[:space:]]+1[[:space:]]+0[[:space:]]+0%[[:space:]]+0[[:space:]]+2026-06-01' <<<"$out"; then ok "stale-skill count 1, 14d 0, last 2026-06-01"; else no "stale-skill row wrong: $out"; fi

echo "[90] skills --json: count_14d and last ride alongside count/errors"
jout="$(SESSION_OBSERVE_NOW="$FRNOW" "$CC" skills --file "$FREXFIX" --json)"
if echo "$jout" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = {r["skill"]: r for r in d["skills"]}
assert rows["fresh-skill"]["count_14d"] == 2 and rows["fresh-skill"]["last"] == "2026-09-18", rows
assert rows["stale-skill"]["count_14d"] == 0 and rows["stale-skill"]["last"] == "2026-06-01", rows
'; then ok "json count_14d + last correct"; else no "json skills wrong: $jout"; fi

LEFIX="${DIR}/tests/fixtures/entryfee-listing"
# proj-a (2026-09-15, newer): attachment-shaped record; 4 entries (alpha/bravo/charlie/delta),
# bravo's description is 450 chars (over the 400 flag), charlie's is empty, delta continues
# onto an indented line, and the block ends immediately at a non-entry line (no blank line).
# proj-b (2026-09-08, older): user-message-shaped record; a blank line precedes the first
# entry, 2 entries (echo/foxtrot), and the list ends at a blank-line-then-non-entry.

echo "[91] entry-fee: skill listing measured-from-transcript table is its own section, labelled measured"
out="$("$CC" entry-fee --root "$LEFIX")"
if grep -q 'MEASURED-FROM-TRANSCRIPT' <<<"$out" && grep -q '2 sessions carry the real listing' <<<"$out"; then ok "measured-from-transcript section present"; else no "measured section missing: $out"; fi

echo "[92] entry-fee: the disk-sized split is explicitly labelled an estimate (not confused with the measured listing)"
if grep -q 'ESTIMATED from disk' <<<"$out"; then ok "disk-sized split labelled estimated"; else no "disk-sized split not labelled: $out"; fi

echo "[93] entry-fee: listing median across the 2 sessions (entries 2, chars 158, tokens 39, over400 0, empty-desc 0)"
if grep -Eq 'median[[:space:]]+2[[:space:]]+158[[:space:]]+39[[:space:]]+0[[:space:]]+0' <<<"$out"; then ok "median row correct"; else no "median row wrong: $out"; fi

echo "[94] entry-fee: most-recent session's own figures (proj-a, entries 4, chars 614, tokens 153, over400 1, empty-desc 1)"
if grep -Eq 'most-recent[[:space:]]+4[[:space:]]+614[[:space:]]+153[[:space:]]+1[[:space:]]+1' <<<"$out"; then ok "most-recent row correct"; else no "most-recent row wrong: $out"; fi

echo "[95] entry-fee: top 8 descriptions by length, most-recent session, ranked (bravo 450 first, charlie 0 last)"
b8="$(awk '/^  bravo/{print NR; exit}' <<<"$out")"
c8="$(awk '/^  charlie/{print NR; exit}' <<<"$out")"
if grep -Eq 'bravo[[:space:]]+450' <<<"$out" && grep -Eq 'charlie[[:space:]]+0' <<<"$out" && [[ -n "$b8" && -n "$c8" && "$b8" -lt "$c8" ]]; then ok "top8 ranked, bravo 450 above charlie 0"; else no "top8 wrong: $out"; fi

echo "[96] entry-fee: --json carries skill_listing_measured with median + most_recent + top8"
jout="$("$CC" entry-fee --root "$LEFIX" --json)"
if echo "$jout" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sl = d["skill_listing_measured"]
assert sl["sessions"] == 2, sl
assert sl["median"] == {"entries": 2, "chars": 158, "tokens": 39, "over_400": 0, "empty_desc": 0}, sl["median"]
mr = sl["most_recent"]
assert mr["entries"] == 4 and mr["chars"] == 614 and mr["tokens"] == 153 and mr["over_400"] == 1 and mr["empty_desc"] == 1, mr
top = sl["most_recent_top8"]
assert top[0] == {"skill": "bravo", "chars": 450} and top[-1] == {"skill": "charlie", "chars": 0}, top
'; then ok "json skill_listing_measured correct"; else no "json skill_listing_measured wrong: $jout"; fi

echo "[97] entry-fee negative control: report has no skill-listing section (existing views unchanged)"
out="$("$CC" report --file "$FIX")"
if ! grep -q 'MEASURED-FROM-TRANSCRIPT' <<<"$out"; then ok "report has no skill-listing section"; else no "skill-listing section leaked into report: $out"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
