#!/bin/bash
# test-lens-eval.sh -- Proves lib/bench/lens-eval.sh, the treatment-vs-control eval for a
# prompt-only lens (SPEC-316).
#
# Fully offline: a stub `claude` first on PATH answers from the prompt it reads on stdin. A
# prompt carrying `### Reviewer 7` gets a report with Reviewer 7 findings; one without gets a
# six-reviewer report. Env knobs pick calls (1-based, in the script's fixed order) that leak a
# signal, drop the findings, or fail. The command under test lives in a temp git repo: six
# reviewers at HEAD (control), seven in the working tree (treatment). The case file is the
# real SPEC-314 one, tests/fixtures/sustainability-lens/lens-eval.json.
#
# Run: bash tests/test-lens-eval.sh
# Exit 0 = all tests pass. Exit 1 = failures found.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EVAL="$KIT_DIR/lib/bench/lens-eval.sh"
CASES="$KIT_DIR/tests/fixtures/sustainability-lens/lens-eval.json"
PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local NAME="$1" EXPECTED="$2" ACTUAL="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME (expected '$EXPECTED', got '$ACTUAL')"
    FAIL=$((FAIL + 1))
  fi
}

# assert_has <name> <fixed-string> <text>
assert_has() {
  local RC=0
  printf '%s\n' "$3" | grep -qF -- "$2" || RC=1
  assert_eq "$1" 0 "$RC"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-lens-eval.XXXXXX")"
STUB_BIN="$TMP/bin"
REPO="$TMP/repo"
mkdir -p "$STUB_BIN" "$REPO/commands"

# ------------------------------------------------------------------
# The stub claude. Logs argv + prompt per call, answers per the knobs.
# ------------------------------------------------------------------
cat >"$STUB_BIN/claude" <<'STUB'
#!/bin/bash
n=$(( $(cat "$STUB_LOG/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$STUB_LOG/count"
printf '%s\n' "$@" >"$STUB_LOG/argv.$n"
prompt="$(cat)"
printf '%s\n' "$prompt" >"$STUB_LOG/prompt.$n"
on() { case " ${1:-} " in *" $n "*) return 0 ;; esac; return 1; }
on "${STUB_FAIL_CALLS:-}" && exit 1
on "${STUB_EMPTY_CALLS:-}" && { echo '{"result":"","total_cost_usd":0.01}'; exit 0; }
on "${STUB_ISERR_CALLS:-}" && { echo '{"is_error":true,"result":"Credit balance is too low","total_cost_usd":0}'; exit 0; }
r="# Spec Validation Report
## Warnings
1. API keys sit in a plaintext .env file - Reviewer 1 - use a secrets manager
2. IMAP login failure is only retried the next night - Reviewer 2 - retry within the run"
if printf '%s' "$prompt" | grep -q '### Reviewer 7'; then
  if printf '%s' "$prompt" | grep -q 'nightly inbox summarizer'; then
    if ! on "${STUB_MISS_CALLS:-}"; then
      if on "${STUB_SCOPE_CALLS:-}"; then
        r="$r
3. **Nightly job failure.** Reviewer 2.
   - No heartbeat on the nightly job; add one."
      else
        r="$r
3. No heartbeat or alert: a missed launchd fire dies silently - Reviewer 7 - add a heartbeat"
      fi
      r="$r
4. Unbounded run cost: one paid call per email with no cap - Reviewer 7 - cap calls per night
5. No retirement path: unloading the plist leaves the .env keys orphaned - Reviewer 7 - add a retire step
6. **Dependency and credential lifespan.** Reviewer 7.
   - There is no rotation path for the IMAP or API keys.
7. **Discord webhook** Reviewer 1.
   - The webhook URL is unguarded."
    fi
  else
    r="$r
- Reviewer 7: not long-lived: in-repo CLI flag rename covered by existing tests"
    [ -n "${STUB_NOISY:-}" ] && r="$r
3. Unbounded run cost on every call - Reviewer 7 - cap it"
  fi
fi
on "${STUB_LEAK_CALLS:-}" && r="$r
9. The job has no heartbeat and dies silently - Reviewer 2 - add one"
r="$r
## Verdict: APPROVED"
jq -n --arg r "$r" '{result:$r, is_error:false, total_cost_usd:0.01}'
STUB
chmod +x "$STUB_BIN/claude"

# The command under test: six reviewers committed, a seventh added in the working tree.
cat >"$REPO/commands/lens.md" <<'CMD'
# Spec review
### Reviewer 1: Security Auditor
### Reviewer 2: Failure Mode Analyst
### Reviewer 6: Design Record Auditor
CMD
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t add -A
git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm base
printf '### Reviewer 7: Sustainability Critic\n' >>"$REPO/commands/lens.md"
CMDFILE="$REPO/commands/lens.md"
STATUS_BEFORE="$(git -C "$REPO" status --porcelain)"

# run_eval <label> [env assignments...] -- <lens-eval args...>
# Fresh stub log per run; sets OUT (stdout+stderr), RC, CALLS.
run_eval() {
  local label="$1"; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  export STUB_LOG="$TMP/log.$label"
  mkdir -p "$STUB_LOG"
  OUT="$(env PATH="$STUB_BIN:$PATH" "${envs[@]+"${envs[@]}"}" bash "$EVAL" "$@" 2>&1)"
  RC=$?
  CALLS="$(cat "$STUB_LOG/count" 2>/dev/null || echo 0)"
}

# One-case file for the majority / tie / scope math.
ONE="$TMP/one.json"
cp "$KIT_DIR/tests/fixtures/sustainability-lens/long-lived-gaps.md" "$TMP/"
cat >"$ONE" <<'JSON'
{"cases":[{"name":"ll","fixture":"long-lived-gaps.md","signals":[
  {"name":"liveness-r7","reviewer":"Reviewer 7|R7|Sustainab","pattern":"heartbeat|liveness|silent","treatment":"hit"},
  {"name":"liveness-any","pattern":"heartbeat|liveness|dies silently","control":"miss"}]}]}
JSON

echo "=== usage ==="
run_eval u1 -- ;                                                  assert_eq "no args exit 64" 64 "$RC"
run_eval u2 -- "$CMDFILE" HEAD "$CASES" --samples 0 --live;       assert_eq "--samples 0 exit 64" 64 "$RC"
run_eval u3 -- "$CMDFILE" HEAD "$CASES" --samples x --live;       assert_eq "--samples x exit 64" 64 "$RC"
run_eval u4 -- "$REPO/commands/nope.md" HEAD "$CASES" --live;     assert_eq "missing command exit 64" 64 "$RC"
run_eval u5 -- "$CMDFILE" HEAD~5 "$CASES" --live;                 assert_eq "base without the file exit 64" 64 "$RC"
echo '{"cases":[]}' >"$TMP/empty.json"
run_eval u6 -- "$CMDFILE" HEAD "$TMP/empty.json" --live;          assert_eq "no cases exit 64" 64 "$RC"
echo '{"cases":[{"name":"a","fixture":"long-lived-gaps.md","signals":[{"name":"s","pattern":"x"}]}]}' >"$TMP/noarm.json"
run_eval u7 -- "$CMDFILE" HEAD "$TMP/noarm.json" --live;          assert_eq "signal with no arm exit 64" 64 "$RC"
echo '{"cases":[{"name":"a","fixture":"gone.md","signals":[{"name":"s","pattern":"x","treatment":"hit"}]}]}' >"$TMP/nofix.json"
run_eval u8 -- "$CMDFILE" HEAD "$TMP/nofix.json" --live;          assert_eq "missing fixture exit 64" 64 "$RC"
echo '{"cases":[{"name":"a","fixture":"long-lived-gaps.md","signals":[{"name":"s","pattern":"x","treatment":"hit"}]},{"name":"a","fixture":"long-lived-gaps.md","signals":[{"name":"t","pattern":"y","treatment":"hit"}]}]}' >"$TMP/dup.json"
run_eval u11 -- "$CMDFILE" HEAD "$TMP/dup.json" --live;           assert_eq "duplicate case names exit 64" 64 "$RC"
echo '{"cases":[{"name":"a","fixture":"long-lived-gaps.md","signals":[{"name":"s","pattern":"(","control":"miss"}]}]}' >"$TMP/badre.json"
run_eval u12 -- "$CMDFILE" HEAD "$TMP/badre.json" --live;         assert_eq "invalid regex exit 64" 64 "$RC"
run_eval u9 -- "$CMDFILE" HEAD "$CASES" --bogus --live;           assert_eq "unknown flag exit 64" 64 "$RC"
run_eval u10 -- "$CMDFILE" "--output=$TMP/x" "$CASES" --live;     assert_eq "option-shaped base exit 64" 64 "$RC"
assert_eq "option-shaped base wrote no file" no "$([ -e "$TMP/x" ] && echo yes || echo no)"
UCALLS=0; for l in u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12; do UCALLS=$((UCALLS + $(cat "$TMP/log.$l/count" 2>/dev/null || echo 0))); done
assert_eq "usage errors never call claude" 0 "$UCALLS"

echo "=== dry run ==="
run_eval d1 -- "$CMDFILE" HEAD "$CASES"
assert_eq "dry run exit 3" 3 "$RC"
assert_has "dry run verdict NOT RUN" "verdict: NOT RUN" "$OUT"
assert_has "dry run plans 3 calls" "= 3 model calls" "$OUT"
assert_eq "dry run never calls claude" 0 "$CALLS"
run_eval d2 -- "$CMDFILE" HEAD "$CASES" --samples 3
assert_has "--samples 3 plans 9 calls" "= 9 model calls" "$OUT"

echo "=== live pass (SPEC-314 case file) ==="
run_eval p1 -- "$CMDFILE" HEAD "$CASES" --live
assert_eq "live pass exit 0" 0 "$RC"
assert_has "verdict PASS 9/9" "verdict: PASS (9/9 signals)" "$OUT"
assert_eq "3 calls" 3 "$CALLS"
assert_has "liveness row" "| long-lived | liveness-r7 | 1/1 want hit | - | PASS |" "$OUT"
assert_has "detail on an indented line under a Reviewer 7 title hits" "| long-lived | rotation-r7 | 1/1 want hit | - | PASS |" "$OUT"
assert_has "control row" "| long-lived | liveness-any | - | 0/1 want miss | PASS |" "$OUT"
assert_has "quiet row, no control cell" "| short-lived | quiet-pass | 1/1 want hit | - | PASS |" "$OUT"
assert_has "cost sum" "cost: \$0.03 over 3 calls" "$OUT"
ARGV="$(cat "$STUB_LOG/argv.1")"
assert_has "argv -p" "-p" "$ARGV"
assert_has "argv --safe-mode" "--safe-mode" "$ARGV"
assert_has "argv --output-format json" "$(printf -- '--output-format\njson')" "$ARGV"
assert_has "argv --model sonnet" "$(printf -- '--model\nsonnet')" "$ARGV"
assert_eq "argv --tools is followed by an empty value" "" "$(grep -A1 -x -- '--tools' "$STUB_LOG/argv.1" | sed -n 2p)"
assert_eq "argv has --tools" 1 "$(grep -cx -- '--tools' "$STUB_LOG/argv.1")"
assert_eq "treatment prompt carries Reviewer 7" 1 "$(grep -c '### Reviewer 7' "$STUB_LOG/prompt.1")"
assert_eq "control prompt carries no Reviewer 7" 0 "$(grep -c '### Reviewer 7' "$STUB_LOG/prompt.2")"
assert_eq "control prompt carries the fixture" 1 "$(grep -c 'nightly inbox summarizer' "$STUB_LOG/prompt.2")"
SDIR="$(printf '%s\n' "$OUT" | sed -n 's/^samples: //p')"
assert_eq "samples saved" "long-lived.control.1.md long-lived.treatment.1.md short-lived.treatment.1.md" "$(cd "$SDIR" 2>/dev/null && ls -- *.md | tr '\n' ' ' | sed 's/ $//')"
assert_eq "repo untouched" "$STATUS_BEFORE" "$(git -C "$REPO" status --porcelain)"
run_eval p2 -- "$CMDFILE" HEAD "$CASES" --model haiku --live
assert_has "--model haiku passes through" "$(printf -- '--model\nhaiku')" "$(cat "$STUB_LOG/argv.1")"

echo "=== failing signals ==="
run_eval f1 STUB_LEAK_CALLS=2 -- "$CMDFILE" HEAD "$CASES" --live
assert_eq "control leak exit 1" 1 "$RC"
assert_has "control leak row FAIL" "| long-lived | liveness-any | - | 1/1 want miss | FAIL |" "$OUT"
assert_has "verdict names liveness-any" "liveness-any" "$(printf '%s\n' "$OUT" | grep '^verdict: FAIL')"
run_eval f2 STUB_MISS_CALLS=1 -- "$CMDFILE" HEAD "$CASES" --live
assert_eq "treatment miss exit 1" 1 "$RC"
assert_has "treatment miss row FAIL" "| long-lived | retirement-r7 | 0/1 want hit | - | FAIL |" "$OUT"
run_eval f3 STUB_NOISY=1 -- "$CMDFILE" HEAD "$CASES" --live
assert_eq "noisy quiet case exit 1" 1 "$RC"
assert_has "quiet row FAIL" "| short-lived | quiet-no-findings | 1/1 want miss | - | FAIL |" "$OUT"
run_eval f4 STUB_SCOPE_CALLS=1 -- "$CMDFILE" HEAD "$ONE" --live
assert_has "liveness under Reviewer 2 only misses the R7 scope" "| ll | liveness-r7 | 0/1 want hit | - | FAIL |" "$OUT"

echo "=== majority and tie ==="
run_eval m1 STUB_MISS_CALLS=3 -- "$CMDFILE" HEAD "$ONE" --samples 3 --live
assert_has "2/3 hits pass" "| ll | liveness-r7 | 2/3 want hit | - | PASS |" "$OUT"
assert_eq "2/3 exit 0" 0 "$RC"
run_eval m2 "STUB_MISS_CALLS=2 3" -- "$CMDFILE" HEAD "$ONE" --samples 3 --live
assert_has "1/3 hits fail" "| ll | liveness-r7 | 1/3 want hit | - | FAIL |" "$OUT"
run_eval t1 STUB_LEAK_CALLS=3 -- "$CMDFILE" HEAD "$ONE" --samples 2 --live
assert_has "control tie 1/2 counts as miss" "| ll | liveness-any | - | 1/2 want miss | PASS |" "$OUT"
assert_eq "control tie exit 0" 0 "$RC"
run_eval t2 STUB_MISS_CALLS=2 -- "$CMDFILE" HEAD "$ONE" --samples 2 --live
assert_has "treatment tie 1/2 counts as miss" "| ll | liveness-r7 | 1/2 want hit | - | FAIL |" "$OUT"

echo "=== failed samples ==="
for k in STUB_EMPTY_CALLS STUB_FAIL_CALLS STUB_ISERR_CALLS; do
  run_eval "e-$k" "$k=2" -- "$CMDFILE" HEAD "$CASES" --live
  assert_eq "$k exit 2" 2 "$RC"
  assert_has "$k verdict ERROR" "verdict: ERROR (1 failed samples" "$OUT"
  assert_eq "$k prints no table" 0 "$(printf '%s\n' "$OUT" | grep -c '^| long-lived')"
done

rm -rf "$TMP"

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All lens-eval tests passed.${NC}"
  exit 0
fi
