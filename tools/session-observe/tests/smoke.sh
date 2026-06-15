#!/usr/bin/env bash
# cc-observe smoke test. Parses tests/fixtures/sample.jsonl (a synthetic transcript
# with a known Skill, two Bash calls (one errored), a Read, and a system entry whose
# hookInfos carries a deliberately slow hook (500ms) next to a fast one (12ms)).
#
# Run: bash tests/smoke.sh
# Pass: prints "smoke: all N passed", exit 0. Fail: prints which, exit 1.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CC="${DIR}/bin/cc-observe"
CS="${DIR}/bin/cc-semantic"                         # SG-04 LLM-derived signals
FIX="${DIR}/tests/fixtures/sample.jsonl"
SEMOUT="${DIR}/tests/fixtures/semantic-llm-out.json"  # injected fake model response
SFIX="${DIR}/tests/fixtures/session-sample.jsonl"  # clean session (no sidechain) for archetype/circadian

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

echo "[27] cc-semantic: injected model output -> topics + self-corrections, propose-only banner"
out="$(CC_SEMANTIC_CMD="cat $SEMOUT" "$CS" --root "$DIR/tests/fixtures" --days 0)"
if grep -q 'cc-observe tooling' <<<"$out" && grep -q 'self-corrections: 1' <<<"$out" && grep -q 'PROPOSAL ONLY' <<<"$out"; then ok "topics + corrections + propose-only banner"; else no "cc-semantic output wrong: $out"; fi

echo "[28] cc-semantic negative control: failing command -> _unavailable_ (never fabricates)"
out="$(CC_SEMANTIC_CMD="false" "$CS" --root "$DIR/tests/fixtures" --days 0)"
if grep -q '_unavailable_' <<<"$out"; then ok "degrades to _unavailable_ on command failure"; else no "should be unavailable: $out"; fi

echo "[29] cc-semantic: no prompts in window -> empty (no proposal)"
out="$("$CS" --root /tmp/cc-semantic-none-$$ --days 0)"
if grep -q 'no prompts' <<<"$out"; then ok "empty window handled"; else no "empty path wrong: $out"; fi

echo "[30] cc-semantic --json: valid JSON with status ok"
if CC_SEMANTIC_CMD="cat $SEMOUT" "$CS" --root "$DIR/tests/fixtures" --days 0 --json | python3 -m json.tool >/dev/null 2>&1; then ok "valid json"; else no "json invalid"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
