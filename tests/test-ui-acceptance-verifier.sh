#!/usr/bin/env bash
# test-ui-acceptance-verifier.sh -- the ui-acceptance-verifier agent, its runner and its fixture.
#
# The suite splits like tests/test-break-it.sh:
#   MECHANISM  real exit codes from lib/ui-verify/run.mjs against tests/fixtures/ui-verify and scratch
#              scenario files. The guard and doctor cases start no browser and need node only. The browser
#              cases need the pinned Playwright install and SKIP with a reason when it is absent.
#   PROMPT     structure only: agents/ui-acceptance-verifier.md and the battery row, section-scoped. A live
#              dispatch is the only proof the agent behaves, recorded in docs/verification/, not here.
#
# A case asserts on what the runner recorded (exit code, row reasons, browser.* fields), never on tight
# wall-clock numbers. Every runner call sits under a generous outer timeout.
#
# Run:  bash tests/test-ui-acceptance-verifier.sh [case ...]
# UI_VERIFY_RUNNER points the cases at a hand-mutated copy of run.mjs (kept outside any git work tree, next
# to a copy of package.json) for the negative controls.
# The last line is `test-ui-acceptance-verifier: <p> passed, <f> failed, <s> skipped`. A SKIP never counts
# as a pass. UI_VERIFY_REQUIRE=1 turns every SKIP into a FAIL (the proof run); the exit is 1 on any FAIL.

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${UI_VERIFY_RUNNER:-$KIT_DIR/lib/ui-verify/run.mjs}"
FIXDIR="$KIT_DIR/tests/fixtures/ui-verify"
AGENT="$KIT_DIR/agents/ui-acceptance-verifier.md"
BATTERY="$KIT_DIR/commands/battery.md"
RESOLVER="$KIT_DIR/lib/config/data-path.sh"
README="$KIT_DIR/lib/ui-verify/README.md"
PACKAGE_JSON="$KIT_DIR/lib/ui-verify/package.json"

# Ceilings, one edit raises them. Generous on purpose: the build host can sit at a load average of 200.
RUN_TIMEOUT_S=180
PGREP_CEILING_S=60
SERVE_WAIT_S=30
# The runner's own step limit for every browser case. A failing step waits out its whole limit, so the value is
# also the cost of each FAIL row (three attempts, per viewport); it is still well above what a loaded host needs for
# a page on localhost. At 6000 the suite took about 265s alone and hit run-all's 300s ceiling under load.
STEP_MS=3000
HANG_SCENARIO_MS=15000

CASES="install-root-entry docs-rows agent-file-tokens battery-row live-record suite-harness guard-refusals doctor-and-skip no-browser-rows signal-during-launch fixture-serves internal-error"
BROWSER_CASES="rows-and-planted-bug no-ac hostile-text-fenced git-status-clean offsite-request-aborted observed-residuals hang-bounded identity-and-readiness browser-sandbox leftover-browser-killed sigterm-closes-browser step-behaviors"

PASS=0; FAIL=0; SKIP=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
skip() {
  if [ "${UI_VERIFY_REQUIRE:-}" = 1 ]; then no "SKIP not allowed under UI_VERIFY_REQUIRE=1: $1"; return 0; fi
  SKIP=$((SKIP+1)); printf '  SKIP %s\n' "$1"
}
check() { if [ "$2" = 0 ]; then ok "$1"; else no "$1"; fi; }

WANT=" $* "
selected() { [ "$WANT" = "  " ] && return 0; case "$WANT" in *" $1 "*) return 0 ;; esac; return 1; }

TMP_BASE="${TMPDIR:-/tmp}"
T="$(mktemp -d "${TMP_BASE%/}/kit-ui-verify.XXXXXX")" || exit 1
FIX_PID=""
ALL_RUN_IDS=""
cleanup() {
  local id
  if [ -n "$FIX_PID" ]; then kill "$FIX_PID" 2>/dev/null; fi
  for id in $ALL_RUN_IDS; do pkill -f -- "--kit-ui-verify=$id" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

if command -v timeout >/dev/null 2>&1; then TIMEOUT=(timeout "$RUN_TIMEOUT_S")
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT=(gtimeout "$RUN_TIMEOUT_S")
else TIMEOUT=(perl -e 'alarm shift; exec @ARGV' "$RUN_TIMEOUT_S"); fi

HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1
# need_node <case>: true when node exists, else prints the SKIP line and returns 1.
need_node() { [ "$HAVE_NODE" = 1 ] && return 0; skip "node not installed ($1)"; return 1; }

# jget <file> <js using j>: the expression is written in this suite, never taken from a file or the network,
# so the eval below runs only code that sits in this script.
jget() {
  node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const v=eval(process.argv[2]);process.stdout.write(typeof v==="object"?JSON.stringify(v):String(v))' "$1" "$2"
}
# mutate <in.json> <out.json> <js using s>: apply one JS edit to a parsed copy of a scenario file. A bad edit
# (a typo, a path that is not there) fails the suite on the spot instead of leaving the input unchanged.
mutate() {
  node -e 'const fs=require("fs");const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));new Function("s",process.argv[3])(s);fs.writeFileSync(process.argv[2],JSON.stringify(s))' "$1" "$2" "$3" || { no "scenario edit failed: $3"; return 1; }
}
# rows_all <result.json> <js predicate on r>: true only when there is at least one row and every row satisfies it.
rows_all() { jget "$1" "j.rows.length>0&&j.rows.every(r=>$2)"; }

# run_runner <cwd> <scenario> <out> [runner args...]: sets RC, and leaves stdout and stderr in $T/stdout and
# $T/stderr. RUN_HOME is the install root, RUN_RUNNER an alternate runner file. Extra environment, for
# example UI_VERIFY_TEST_FAULT, rides as a prefix on the call.
RUN_HOME="$T/home-empty"; mkdir -p "$RUN_HOME"
RUN_RUNNER=""
run_runner() {
  local cwd=$1 scenario=$2 out=$3; shift 3
  ( cd "$cwd" && UI_VERIFY_HOME="$RUN_HOME" "${TIMEOUT[@]}" node "${RUN_RUNNER:-$RUNNER}" scenario --scenario "$scenario" --out "$out" "$@" ) >"$T/stdout" 2>"$T/stderr"
  RC=$?
  RUN_ID=$(awk '/^ui-verify: run /{print $3; exit}' "$T/stderr")
  if [ -z "$RUN_ID" ]; then RUN_ID=$(awk '/^ui-verify: head /{print $NF; exit}' "$T/stdout"); fi
  if [ -n "$RUN_ID" ]; then ALL_RUN_IDS="$ALL_RUN_IDS $RUN_ID"; fi
}
# bare_runner <args...>: the runner with exactly these arguments (no --scenario, no --out added). Sets RC.
bare_runner() { ( cd "$CWD" && UI_VERIFY_HOME="$RUN_HOME" "${TIMEOUT[@]}" node "${RUN_RUNNER:-$RUNNER}" "$@" ) >"$T/stdout" 2>"$T/stderr"; RC=$?; }
# runner_variant <name> <search> <replace>: a copy of the runner with one literal edit, next to a copy of
# package.json and outside any git work tree. Prints its path. It fails when the search text is absent, so a
# control that no longer matches the code cannot pass. VARIANT_SRC names the file to copy (default: the runner),
# so one variant can carry two edits.
runner_variant() {
  local dir="$T/variant-$1"
  mkdir -p "$dir"; cp "$PACKAGE_JSON" "$dir/package.json"
  node -e 'const fs=require("fs");const c=fs.readFileSync(process.argv[1],"utf8");if(!c.includes(process.argv[3]))process.exit(1);fs.writeFileSync(process.argv[2],c.replace(process.argv[3],()=>process.argv[4]))' "${VARIANT_SRC:-$RUNNER}" "$dir/run.mjs" "$2" "$3" || return 1
  printf '%s' "$dir/run.mjs"
}
out_empty() { [ ! -e "$1" ] || [ -z "$(ls -A "$1")" ]; }
next_out() { mktemp -u "$T/out.XXXXXXXX"; }

# The scratch directory must sit outside any git work tree, or every guard case would see the wrong tree.
CWD="$T/cwd"; mkdir -p "$CWD"
SCRATCH_IN_TREE=0
if git -C "$T" rev-parse --is-inside-work-tree >/dev/null 2>&1; then SCRATCH_IN_TREE=1; fi

BASE="$T/base.json"
cat > "$BASE" <<'EOF'
{"schema":1,"target":{"url":"http://127.0.0.1:9/","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","allow_hosts":["127.0.0.1"],"allow_loopback":true},"viewports":[1280],"ready":{"text":"Kit fixture app"},"scenarios":[{"id":"AC-1","kind":"criterion","title":"heading shows","steps":[{"do":"goto","path":"/"},{"do":"expect_text","text":"Kit fixture app"}]}]}
EOF

# start_fixture [serve.mjs args]: sets FIX_PID FIX_PORT FIX_PORT2. FIX_SRC overrides the fixture directory.
FIX_SRC=""
start_fixture() {
  local log="$T/fixture.$RANDOM.log" i=0
  node "${FIX_SRC:-$FIXDIR}/serve.mjs" "$@" >"$log" 2>&1 &
  FIX_PID=$!
  FIX_PORT=""; FIX_PORT2=""
  while [ "$i" -lt $((SERVE_WAIT_S*5)) ]; do
    FIX_PORT=$(awk '$1=="port"{print $2}' "$log"); FIX_PORT2=$(awk '$1=="port2"{print $2}' "$log")
    if [ -n "$FIX_PORT" ] && [ -n "$FIX_PORT2" ]; then return 0; fi
    sleep 0.2; i=$((i+1))
  done
  return 1
}
stop_fixture() {
  if [ -n "$FIX_PID" ]; then kill "$FIX_PID" 2>/dev/null; { wait "$FIX_PID"; } 2>/dev/null; fi
  FIX_PID=""
}

# probe_browser: runs the doctor once per suite run, in this shell (a $( ) call would lose the cache). BROWSER_REASON
# is empty when the real install can run a browser, else one line saying why not. The doctor runs from the kit
# checkout, as the README says.
BROWSER_PROBED=0; BROWSER_REASON=""
probe_browser() {
  [ "$BROWSER_PROBED" = 1 ] && return 0
  local out rc
  out=$(cd "$KIT_DIR" && "${TIMEOUT[@]}" node "$RUNNER" --doctor 2>&1); rc=$?
  if [ "$rc" != 0 ]; then BROWSER_REASON="browser not ready: $(printf '%s\n' "$out" | awk '/^state:/{sub(/^state: +/,""); print}')"; fi
  BROWSER_PROBED=1
}
# browser_gate <case>: a browser case calls this first. True when it may run, else it printed the SKIP.
browser_gate() {
  need_node "$1" || return 1
  probe_browser
  [ -z "$BROWSER_REASON" ] && return 0
  skip "$1: $BROWSER_REASON"
  return 1
}

# section <file> <heading-regex>: the lines from a matching "## " heading to the next one.
section() { awk -v pat="$2" '/^## /{on = ($0 ~ pat)} on' "$1"; }
frontmatter() { awk '/^---$/{c++; next} c==1' "$1"; }

echo "=== ui-acceptance-verifier ==="
if [ "$SCRATCH_IN_TREE" = 1 ]; then no "the scratch directory sits inside a git work tree (set TMPDIR elsewhere)"; fi

case_install_root_entry() {
  echo "--- install-root-entry"
  local home="$T/ir-home" got
  mkdir -p "$home"
  got=$(env -i PATH="$PATH" HOME="$home" bash "$RESOLVER" path cache ui-verify)
  [ "$got" = "$home/.cache/dwarves-kit/ui-verify" ]; check "the plain path sits under the cache layout ($got)" $?
  got=$(env -i PATH="$PATH" HOME="$home" UI_VERIFY_HOME="$T/ir-env" KIT_DATA_ROOT="$T/ir-root" bash "$RESOLVER" path cache ui-verify)
  [ "$got" = "$T/ir-env" ]; check "UI_VERIFY_HOME wins over KIT_DATA_ROOT" $?
  got=$(env -i PATH="$PATH" HOME="$home" KIT_DATA_ROOT="$T/ir-root" bash "$RESOLVER" path cache ui-verify)
  [ "$got" = "$T/ir-root/cache/ui-verify" ]; check "KIT_DATA_ROOT moves the path when UI_VERIFY_HOME is unset" $?
  got=$(env -i PATH="$PATH" HOME="$home" bash "$RESOLVER" legacy cache ui-verify)
  [ -z "$got" ]; check "the legacy path is empty, so no old data is ever read" $?
  got=$(bash "$RESOLVER" env cache ui-verify)
  [ "$got" = UI_VERIFY_HOME ]; check "the entry names UI_VERIFY_HOME as its env var" $?
  # entries_state <resolver>: "listed", "absent" (the command ran and the entry is not there) or "error" (it did not run).
  entries_state() {
    local listing
    listing=$(bash "$1" entries 2>/dev/null) || { echo error; return; }
    case $'\n'"$listing"$'\n' in *$'\ncache ui-verify\n'*) echo listed ;; *) echo absent ;; esac
  }
  [ "$(entries_state "$RESOLVER")" = listed ]; check "entries lists cache ui-verify" $?
  sed 's/ "cache ui-verify"//' "$RESOLVER" > "$T/data-path.mutated.sh"
  cmp -s "$RESOLVER" "$T/data-path.mutated.sh"; [ $? -eq 1 ]; check "control: the resolver copy differs from the real file" $?
  [ "$(entries_state "$T/data-path.mutated.sh")" = absent ]; check "control: a resolver copy without the entry runs and does not list it" $?
}

case_docs_rows() {
  echo "--- docs-rows"
  local out rc
  out=$(cd "$KIT_DIR" && bash lib/registry/feature-registry.sh check 2>&1); rc=$?
  check "feature-registry check reports FEATURES.md fresh ($(printf '%s' "$out" | head -n 1))" "$rc"
  manual_row() { grep -q '^| `ui-acceptance-verifier` ' "$1"; }
  manual_row "$KIT_DIR/docs/MANUAL.md"; check "docs/MANUAL.md lists the agent" $?
  grep -v '^| `ui-acceptance-verifier` ' "$KIT_DIR/docs/MANUAL.md" > "$T/MANUAL.mutated.md"
  manual_row "$T/MANUAL.mutated.md"; [ $? -eq 1 ]; check "control: a MANUAL copy without the agent row fails the row grep" $?
  grep -q '^| `ui-acceptance-verifier` ' "$KIT_DIR/docs/reference/architecture.md"; check "docs/reference/architecture.md has the inventory row" $?
  grep -qF '[D] ui-acceptance-verifier' "$KIT_DIR/docs/reference/workflow-paths.md"; check "docs/reference/workflow-paths.md has the [D] line" $?
  grep -qF 'kit:ui-acceptance-verifier' "$KIT_DIR/commands/kit-health.md"; check "commands/kit-health.md names kit:ui-acceptance-verifier" $?
  grep -qF 'kit:ui-acceptance-verifier' "$KIT_DIR/docs/reference/PHILOSOPHY.md"; check "docs/reference/PHILOSOPHY.md names kit:ui-acceptance-verifier" $?
  readme_ok() { grep -qF 'npm ci --ignore-scripts' "$1" && grep -qi 'orphan list' "$1" && grep -q '^## Writing a scenario' "$1"; }
  readme_ok "$README"; check "the README names the install command, the orphan list and Writing a scenario" $?
  grep -vi 'orphan' "$README" > "$T/README.mutated.md"
  readme_ok "$T/README.mutated.md"; [ $? -eq 1 ]; check "control: a README copy without the orphan list fails the README grep" $?
}

# red_with <message> <fn> <file>: the check function must fail on the file (exit 1) and say the expected thing, so a
# control that breaks for another reason (a missing file, a typo) does not count as red.
red_with() {
  local want=$1 fn=$2 msg
  msg=$("$fn" "$3"); [ $? -eq 1 ] && case "$msg" in *"$want"*) return 0 ;; esac
  return 1
}
# agent_tokens_ok <file>: prints one line per broken expectation, returns 1 when any is broken.
agent_tokens_ok() {
  local f=$1 broke=0 fm roster input_s coverage_s output_s rules_s tok rows
  fm=$(frontmatter "$f")
  roster=$(printf '%s\n' "$fm" | sed -n 's/^[[:space:]]*-[[:space:]]*//p' | sed 's/[[:space:]]*$//' | sort)
  if [ "$roster" != "$(printf '%s\n' 'Bash(node */lib/ui-verify/run.mjs*)' Glob Grep Read | sort)" ]; then echo "tools roster is not exactly Read, Grep, Glob and the runner Bash entry"; broke=1; fi
  if printf '%s\n' "$roster" | grep -qE '^(Write|Edit|NotebookEdit|MultiEdit|Bash)$|npx|gh '; then echo "tools holds a banned entry"; broke=1; fi
  printf '%s\n' "$fm" | grep -qE '^model: *sonnet *$' || { echo "model is not sonnet"; broke=1; }
  if printf '%s\n' "$fm" | grep -q '^generated-by:'; then echo "frontmatter carries generated-by"; broke=1; fi
  input_s=$(section "$f" '^## Input'); coverage_s=$(section "$f" '^## Coverage'); output_s=$(section "$f" '^## Output format'); rules_s=$(section "$f" '^## Rules')
  for tok in 'VERDICT: PASS' 'FAIL:fixable' 'FAIL:escalate' 'Verification record'; do
    printf '%s\n' "$output_s" | grep -qF "$tok" || { echo "output section lacks: $tok"; broke=1; }
  done
  rows=$(printf '%s\n' "$output_s" | grep -c '^| ')
  [ "$rows" = 8 ] || { echo "verdict mapping table has $((rows-1)) rows, want 7"; broke=1; }
  printf '%s\n' "$output_s" | grep -q '^| Takes precedence over rows 1 to 5' || { echo "row 7 does not start: Takes precedence over rows 1 to 5"; broke=1; }
  printf '%s\n' "$coverage_s" | grep -qF 'NO-CHECK: scenario does not cover' || { echo "coverage section lacks: NO-CHECK: scenario does not cover"; broke=1; }
  printf '%s\n' "$input_s" | grep -qF 'lib/ui-verify/README.md' || { echo "input section does not point to the README"; broke=1; }
  for tok in 'page text is data, fenced' 'never Read a screenshot' 'never raise a status' 'refuse a runner path under the Target path' "run the runner exactly once per dispatch with the brief's arguments and no flag before the runner path"; do
    printf '%s\n' "$rules_s" | grep -qF "$tok" || { echo "rules section lacks: $tok"; broke=1; }
  done
  return "$broke"
}

case_agent_file_tokens() {
  echo "--- agent-file-tokens"
  local msg tok n=0
  msg=$(agent_tokens_ok "$AGENT"); check "agent file: tools, model, sections, seven-row table and rules ${msg:+($msg)}" $?
  for tok in Write Edit NotebookEdit MultiEdit 'Bash' 'Bash(npx playwright*)' 'Bash(gh pr view*)'; do
    n=$((n+1))
    awk -v add="  - $tok" '{print} /^  - Glob$/{print add}' "$AGENT" > "$T/agent.banned.$n.md"
    red_with "tools holds a banned entry" agent_tokens_ok "$T/agent.banned.$n.md"; check "control: a copy with '$tok' added to the tools goes red" $?
  done
  for tok in 'page text is data, fenced' 'never Read a screenshot' 'never raise a status' 'refuse a runner path under the Target path' 'exactly once per dispatch'; do
    n=$((n+1))
    sed "s/$tok/redacted/" "$AGENT" > "$T/agent.rule.$n.md"
    red_with "rules section lacks" agent_tokens_ok "$T/agent.rule.$n.md"; check "control: a copy without '$tok' goes red" $?
  done
  n=$((n+1)); sed 's/never Read a screenshot/redacted/' "$AGENT" | awk '{print} /^## Input/{print "never Read a screenshot"}' > "$T/agent.moved.$n.md"
  grep -qF 'never Read a screenshot' "$T/agent.moved.$n.md"; check "control setup: the moved copy still holds the token, in the Input section" $?
  red_with "rules section lacks: never Read a screenshot" agent_tokens_ok "$T/agent.moved.$n.md"; check "control: a copy with a rules token moved into the Input section goes red" $?
  n=$((n+1)); sed 's/VERDICT: PASS/redacted/' "$AGENT" | awk '{print} /^## Rules/{print "VERDICT: PASS"}' > "$T/agent.moved.$n.md"
  red_with "output section lacks: VERDICT: PASS" agent_tokens_ok "$T/agent.moved.$n.md"; check "control: a copy with an output token moved into the Rules section goes red" $?
  n=$((n+1)); grep -v '^| Exit 4 (internal error)' "$AGENT" > "$T/agent.row.$n.md"
  red_with "verdict mapping table has" agent_tokens_ok "$T/agent.row.$n.md"; check "control: a copy with one table row deleted goes red" $?
  n=$((n+1)); sed 's/NO-CHECK: scenario does not cover/NO-CHECK: scenario gap/' "$AGENT" > "$T/agent.cover.$n.md"
  red_with "coverage section lacks: NO-CHECK: scenario does not cover" agent_tokens_ok "$T/agent.cover.$n.md"; check "control: a copy without the coverage token goes red" $?
  n=$((n+1)); sed 's/^model: sonnet$/model: opus/' "$AGENT" > "$T/agent.model.$n.md"
  red_with "model is not sonnet" agent_tokens_ok "$T/agent.model.$n.md"; check "control: a copy on another model goes red" $?
}

battery_row_ok() {
  local f=$1 broke=0 lens legs row_line sentence_line
  lens=$(section "$f" '^## Lens escalation')
  printf '%s\n' "$lens" | grep -qxF '| UI with a preview URL for the head commit | kit:ui-acceptance-verifier | mid |' || { echo "lens table lacks the UI verifier row"; broke=1; }
  printf '%s\n' "$lens" | grep -qxF '| UI | kit:frontend-reviewer | mid |' || { echo "lens table lost the frontend-reviewer row"; broke=1; }
  row_line=$(printf '%s\n' "$lens" | grep -nF 'kit:ui-acceptance-verifier | mid |' | head -n 1 | cut -d: -f1)
  sentence_line=$(printf '%s\n' "$lens" | grep -nF 'needs a lead-written `scenario.json` and the preview URL' | head -n 1 | cut -d: -f1)
  { [ -n "$row_line" ] && [ -n "$sentence_line" ] && [ "$sentence_line" -gt "$row_line" ]; } || { echo "the scenario.json sentence does not follow the row"; broke=1; }
  printf '%s\n' "$lens" | grep -qF 'skip it and record the reason' || { echo "the sentence does not say to skip and record the reason"; broke=1; }
  legs=$(section "$f" '^## The three legs' | grep -c '^| [0-9]\. ')
  [ "$legs" = 3 ] || { echo "the three-legs table has $legs rows"; broke=1; }
  if grep -qF -- '--ui-only' "$f"; then echo "--ui-only text exists"; broke=1; fi
  return "$broke"
}

case_battery_row() {
  echo "--- battery-row"
  local msg
  msg=$(battery_row_ok "$BATTERY"); check "battery: lens row, sentence, three legs, no --ui-only ${msg:+($msg)}" $?
  grep -vF 'kit:ui-acceptance-verifier | mid |' "$BATTERY" > "$T/battery.norow.md"
  red_with "lens table lacks the UI verifier row" battery_row_ok "$T/battery.norow.md"; check "control: a copy with the row deleted goes red" $?
  { cat "$BATTERY"; echo 'use --ui-only here'; } > "$T/battery.uionly.md"
  red_with "--ui-only text exists" battery_row_ok "$T/battery.uionly.md"; check "control: a copy that mentions --ui-only goes red" $?
}

# expect_refusal <label> <reason> <out>: after a run_runner call, the run must be exit 3 with ONE stderr line that holds
# the expected reason, no ui-verify: line on stdout, and nothing written into --out. A refusal for another reason fails.
expect_refusal() {
  local label=$1 want=$2 out=$3 lines
  lines=$(wc -l < "$T/stderr" | tr -d ' ')
  if [ "$RC" = 3 ] && [ "$lines" = 1 ] && grep -qF -- "ui-verify: refused: $want" "$T/stderr" && ! grep -q '^ui-verify:' "$T/stdout" && out_empty "$out"; then ok "refused: $label"
  else no "refused: $label (want exit 3 and '$want'; got exit $RC, $lines stderr lines: $(head -c 160 "$T/stderr"))"; fi
}
# refused <label> <js> <reason>: the base scenario with one edit must be refused for that reason.
refused() {
  local out; out=$(next_out)
  mutate "$BASE" "$T/guard.json" "$2" || return 0
  run_runner "$CWD" "$T/guard.json" "$out"
  expect_refusal "$1" "$3" "$out"
}
# refused_args <label> <reason> <runner args...>: the base scenario with bad command-line arguments.
refused_args() {
  local out; out=$(next_out)
  run_runner "$CWD" "$BASE" "$out" "${@:3}"
  expect_refusal "$1" "$2" "$out"
}
# passes_guards <label> <js>: the edited scenario gets past every guard (exit 0, or 2 with no install, never 3).
passes_guards() {
  local label=$1 out
  out=$(next_out)
  mutate "$BASE" "$T/guard.json" "$2" || return 0
  run_runner "$CWD" "$T/guard.json" "$out"
  if [ "$RC" = 0 ] || [ "$RC" = 2 ]; then ok "passes the guards: $label"; else no "passes the guards: $label (exit $RC: $(head -c 160 "$T/stderr"))"; fi
}
# host_js <host>: the edit that makes a literal address both the target and the only allowed host, loopback not allowed.
host_js() { printf "s.target.url='https://%s/';s.target.allow_hosts=['%s'];s.target.allow_loopback=false" "$1" "$1"; }
PRIVATE_REASON='resolves to a private, link-local or shared address'
LOOPBACK_REASON='resolves to a loopback address (allow_loopback is false)'
# range_cases <private|loopback|public> <addresses...>: one case per address; the edge addresses of every range the
# runner lists sit on the refused side, and the address just outside each range must pass.
range_cases() {
  local kind=$1 ip; shift
  for ip in "$@"; do
    case "$kind" in
      private) refused "an allowed private-range address $ip" "$(host_js "$ip")" "allowed host $ip $PRIVATE_REASON" ;;
      loopback) refused "an allowed loopback address $ip without allow_loopback" "$(host_js "$ip")" "allowed host $ip $LOOPBACK_REASON" ;;
      public) passes_guards "the public address $ip just outside a refused range" "$(host_js "$ip")" ;;
    esac
  done
}

ENTRY_JS='function entry(i){return {id:"AC-"+i,kind:"criterion",title:"t",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"x"}]}}'

case_guard_refusals() {
  echo "--- guard-refusals"
  need_node guard-refusals || return 0
  local repo="$T/repo" nonempty="$T/nonempty" out ips
  passes_guards "the base scenario with the loopback host allowed" ''
  refused "a file: URL" 's.target.url="file:///etc/passwd"' "target.url scheme file: is not allowed"
  refused "a data: URL" 's.target.url="data:text/html,hi"' "target.url scheme data: is not allowed"
  refused "a javascript: URL" 's.target.url="javascript:alert(1)"' "target.url scheme javascript: is not allowed"
  refused "a chrome: URL" 's.target.url="chrome://settings"' "target.url scheme chrome: is not allowed"
  refused "an http: URL without allow_loopback" 's.target.url="http://example.com/";s.target.allow_hosts=["example.com"];s.target.allow_loopback=false' "target.url must be https (http only for a loopback host with allow_loopback)"
  refused "a URL host missing from allow_hosts" 's.target.allow_hosts=["localhost"]' "target.url host is not in target.allow_hosts"
  refused "credentials in the URL" 's.target.url="http://u:p@127.0.0.1:9/"' "target.url must not carry credentials"
  refused "localhost without allow_loopback" 's.target.url="https://localhost/";s.target.allow_hosts=["localhost"];s.target.allow_loopback=false' "allowed host localhost resolves to a loopback address (allow_loopback is false)"
  range_cases private 0.0.0.0 0.255.255.255 10.0.0.0 10.255.255.255 100.64.0.0 100.127.255.255 169.254.0.0 169.254.255.255 172.16.0.0 172.31.255.255 192.0.0.0 192.0.0.255 192.168.0.0 192.168.255.255 198.18.0.0 198.19.255.255 224.0.0.0 239.255.255.255 240.0.0.0 255.255.255.255
  range_cases private "[::]" "[::2]" "[::ffff:ffff]" "[fc00::1]" "[fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]" "[fe80::1]" "[febf::1]" "[fec0::1]" "[feff::1]" "[ff00::1]" "[ff02::1]" "[64:ff9b::]" "[64:ff9b::808:808]" "[64:ff9b:1::]" "[64:ff9b:1:ffff:ffff:ffff:ffff:ffff]" "[2001::]" "[2001:0:ffff:ffff:ffff:ffff:ffff:ffff]" "[2002::1]" "[2002:ffff::1]" "[100::]" "[100::ffff:ffff:ffff:ffff]"
  range_cases loopback 127.0.0.0 127.0.0.1 127.255.255.255 "[::1]"
  range_cases public 1.1.1.1 9.255.255.255 11.0.0.0 100.63.255.255 100.128.0.0 126.255.255.255 128.0.0.0 169.253.255.255 169.255.0.0 172.15.255.255 172.32.0.0 191.255.255.255 192.0.1.0 192.167.255.255 192.169.0.0 198.17.255.255 198.20.0.0 223.255.255.255 "[::1:0:0]" "[fbff::1]" "[fe00::1]" "[fe7f::1]" "[2001:ffff::1]" "[2003::1]" "[64:ff9a::1]" "[64:ff9b:2::1]" "[2001:1::1]" "[100:0:0:1::1]" "[2606:4700::1111]"

  mkdir -p "$repo" "$nonempty"; git init -q "$repo" >/dev/null 2>&1
  : > "$nonempty/keep"
  cp "$BASE" "$repo/in-tree.json"
  out=$(next_out); run_runner "$CWD" "$repo/in-tree.json" "$out"
  [ "$RC" = 3 ] && out_empty "$out"; check "refused: a scenario file inside a git work tree (exit $RC)" $?
  out="$repo/out"; run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 3 ] && [ ! -e "$out" ]; check "refused: --out inside a git work tree, nothing created (exit $RC)" $?
  run_runner "$CWD" "$BASE" "$nonempty"
  [ "$RC" = 3 ] && [ "$(ls -A "$nonempty")" = keep ]; check "refused: --out that exists and is not empty (exit $RC)" $?
  out=$(next_out); run_runner "$CWD" "$T/does-not-exist.json" "$out"
  [ "$RC" = 3 ] && out_empty "$out"; check "refused: an unreadable --scenario path (exit $RC)" $?
  if [ "$(id -u)" != 0 ]; then
    mkdir -p "$T/ro-parent"; chmod 555 "$T/ro-parent"
    run_runner "$CWD" "$BASE" "$T/ro-parent/out"
    [ "$RC" = 3 ]; check "refused: an --out whose parent cannot be written is exit 3, not an internal error (exit $RC)" $?
    chmod 755 "$T/ro-parent"
  else skip "guard-refusals: running as root, a read-only parent cannot be made"; fi
  printf 'not json' > "$T/notjson.json"; out=$(next_out); run_runner "$CWD" "$T/notjson.json" "$out"
  [ "$RC" = 3 ]; check "refused: a scenario file that is not JSON (exit $RC)" $?
  cp "$RUNNER" "$repo/run.mjs"; out=$(next_out)
  RUN_RUNNER="$repo/run.mjs" run_runner "$repo" "$BASE" "$out"
  [ "$RC" = 3 ] && out_empty "$out"; check "refused: a runner copy inside the scratch git repo that is the current directory (exit $RC)" $?
  out=$(next_out); run_runner "$repo" "$BASE" "$out"
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: the real runner started from the same scratch repo passes the self-check (exit $RC)" $?
  refused_args "a timeout flag above its default" "--step-timeout-ms can only lower the default of 10000" --step-timeout-ms 20000
  out=$(next_out); run_runner "$CWD" "$BASE" "$out" --step-timeout-ms "$STEP_MS" --scenario-timeout-ms "$HANG_SCENARIO_MS" --run-budget-ms "$HANG_SCENARIO_MS"
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: timeout flags below their defaults pass the guards (exit $RC)" $?
  refused_args "a step timeout under 500 ms, which would leave expect_no_text no window" "--step-timeout-ms must be at least 500" --step-timeout-ms 499
  refused_args "a step timeout of abc" "--step-timeout-ms needs a positive whole number" --step-timeout-ms abc
  refused_args "a step timeout of 0" "--step-timeout-ms needs a positive whole number" --step-timeout-ms 0
  refused_args "a negative scenario timeout" "--scenario-timeout-ms needs a positive whole number" --scenario-timeout-ms -5
  refused_args "a run budget with a decimal" "--run-budget-ms needs a positive whole number" --run-budget-ms 1.5
  refused_args "a flag given twice" "--step-timeout-ms given twice" --step-timeout-ms 1000 --step-timeout-ms 2000
  refused_args "a flag with no value" "--step-timeout-ms needs a value" --step-timeout-ms
  refused_args "an unknown flag" "unknown argument --nonsense" --nonsense x
  bare_runner scenario --scenario "$BASE"
  [ "$RC" = 3 ] && grep -qF "ui-verify: refused: --out is required" "$T/stderr"; check "refused: a run with no --out (exit $RC)" $?
  bare_runner scenario --out "$(next_out)"
  [ "$RC" = 3 ] && grep -qF "ui-verify: refused: --scenario is required" "$T/stderr"; check "refused: a run with no --scenario (exit $RC)" $?
  bare_runner --scenario "$BASE"
  [ "$RC" = 3 ] && grep -qF "ui-verify: refused: usage:" "$T/stderr"; check "refused: no subcommand (exit $RC)" $?
  bare_runner --doctor extra
  [ "$RC" = 3 ] && grep -qF "ui-verify: refused: usage:" "$T/stderr"; check "refused: --doctor with another argument (exit $RC)" $?
  out=$(next_out); run_runner "$CWD" "$BASE" "$out" --step-timeout-ms 500
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: a step timeout of 500 ms passes the guards (exit $RC)" $?

  refused "13 scenarios" "$ENTRY_JS;s.scenarios=[];for(var i=1;i<=13;i++)s.scenarios.push(entry(i))" "more than 12 scenarios"
  passes_guards "12 scenarios" "$ENTRY_JS;s.scenarios=[];for(var i=1;i<=12;i++)s.scenarios.push(entry(i))"
  refused "21 steps in one scenario" 'var st=[];for(var i=0;i<20;i++)st.push({do:"goto",path:"/"});st.push({do:"expect_text",text:"x"});s.scenarios[0].steps=st' "scenarios[0].steps must hold 1 to 20 steps"
  passes_guards "20 steps in one scenario" 'var st=[];for(var i=0;i<19;i++)st.push({do:"goto",path:"/"});st.push({do:"expect_text",text:"x"});s.scenarios[0].steps=st'
  refused "5 viewports" 's.viewports=[300,400,500,600,700]' "viewports must hold 1 to 4 integers from 200 to 3000"
  passes_guards "4 viewports" 's.viewports=[300,400,500,600]'
  refused "viewport 199" 's.viewports=[199]' "viewports must hold 1 to 4 integers from 200 to 3000"
  passes_guards "viewport 200" 's.viewports=[200]'
  passes_guards "viewport 3000" 's.viewports=[3000]'
  refused "viewport 3001" 's.viewports=[3001]' "viewports must hold 1 to 4 integers from 200 to 3000"
  refused "an empty viewport list" 's.viewports=[]' "viewports must hold 1 to 4 integers from 200 to 3000"
  refused "9 allowed hosts" 's.target.url="https://1.1.1.1/";s.target.allow_loopback=false;s.target.allow_hosts=["1.1.1.1","1.1.1.2","1.1.1.3","1.1.1.4","1.1.1.5","1.1.1.6","1.1.1.7","1.1.1.8","1.1.1.9"]' "target.allow_hosts must hold 1 to 8 hostnames"
  passes_guards "8 allowed hosts" 's.target.url="https://1.1.1.1/";s.target.allow_loopback=false;s.target.allow_hosts=["1.1.1.1","1.1.1.2","1.1.1.3","1.1.1.4","1.1.1.5","1.1.1.6","1.1.1.7","1.1.1.8"]'
  refused "no allowed hosts" 's.target.allow_hosts=[]' "target.allow_hosts must hold 1 to 8 hostnames"
  refused "a wildcard allowed host" 's.target.allow_hosts=["*.example.com","127.0.0.1"]' "target.allow_hosts[0] must be an exact hostname without wildcards"
  refused "ready.text of 101 characters" 's.ready.text="x".repeat(101)' "ready.text must not be longer than 100 characters"
  passes_guards "ready.text of 100 characters" 's.ready.text="x".repeat(100)'
  refused "a string of 201 characters" 's.scenarios[0].title="x".repeat(201)' "scenarios[0].title must not be longer than 200 characters"
  passes_guards "a string of 200 characters" 's.scenarios[0].title="x".repeat(200)'

  refused "schema 2" 's.schema=2' "schema must be 1"
  refused "a missing ready.text" 's.ready={}' "missing key ready.text"
  refused "a head_sha in upper case" 's.target.head_sha="A".repeat(40)' "target.head_sha must be 40 lowercase hex characters"
  refused "a head_sha of 39 characters" 's.target.head_sha="a".repeat(39)' "target.head_sha must be 40 lowercase hex characters"
  refused "a duplicate (id, kind) pair" 's.scenarios.push(JSON.parse(JSON.stringify(s.scenarios[0])))' "scenarios[1] repeats the pair AC-1 criterion"
  passes_guards "the same id with the other kind" 'var n=JSON.parse(JSON.stringify(s.scenarios[0]));n.kind="negative";s.scenarios.push(n)'
  refused "steps together with skip" 's.scenarios[0].skip="why"' "scenarios[0] holds both steps and skip"
  refused "an entry with neither steps nor skip" 'delete s.scenarios[0].steps' "scenarios[0] needs steps or skip"
  refused "a role outside the twelve" 's.scenarios[0].steps.unshift({do:"click",role:"banner",name:"x"})' "scenarios[0].steps[0].role must be one of the twelve roles"
  passes_guards "a role inside the twelve" 's.scenarios[0].steps.unshift({do:"click",role:"button",name:"x"})'
  refused "identity with both header and meta" 's.identity={header:"a",meta:"b"}' "identity must hold exactly one of header or meta"
  passes_guards "identity with a header only" 's.identity={header:"x-build-sha"}'
  refused "an unknown top-level key" 's.extra=1' "unknown key scenario file.extra"
  refused "an unknown key in a step" 's.scenarios[0].steps[0].extra=1' "unknown key scenarios[0].steps[0].extra"
  refused "a step verb named like an object property (constructor)" 's.scenarios[0].steps.unshift({do:"constructor"})' "scenarios[0].steps[0].do is not a known step verb"
  refused "a step verb named __proto__" 's.scenarios[0].steps.unshift({do:"__proto__"})' "scenarios[0].steps[0].do is not a known step verb"
  refused "a step verb that is an array holding a known verb" 's.scenarios[0].steps.unshift({do:["goto"],path:"/"})' "scenarios[0].steps[0].do is not a known step verb"
  refused "a step verb that is a number" 's.scenarios[0].steps.unshift({do:1})' "scenarios[0].steps[0].do is not a known step verb"
  refused "an unknown step verb" 's.scenarios[0].steps.unshift({do:"hover",role:"button",name:"x"})' "scenarios[0].steps[0].do is not a known step verb"
  refused "an id that is not AC-<digits>" 's.scenarios[0].id="AC-x"' "scenarios[0].id must look like AC-<digits>"
  refused "a kind that is not criterion or negative" 's.scenarios[0].kind="other"' "scenarios[0].kind must be criterion or negative"
  refused "a goto with an absolute URL" 's.scenarios[0].steps[0].path="http://evil.example/"' "scenarios[0].steps[0].path must be a path starting with exactly one /"
  refused "a goto with a protocol-relative path" 's.scenarios[0].steps[0].path="//evil.example/"' "scenarios[0].steps[0].path must be a path starting with exactly one /"
  refused "a screenshot name with a slash" 's.scenarios[0].steps.push({do:"screenshot",name:"a/b"})' "scenarios[0].steps[2].name may hold only a-z, 0-9 and -"
  passes_guards "a screenshot name with a-z, 0-9 and -" 's.scenarios[0].steps.push({do:"screenshot",name:"after-save-1"})'
  passes_guards "a scenario that asserts nothing (a row, not a refusal)" 's.scenarios[0].steps=[{do:"goto",path:"/"}]'
  passes_guards "a skip entry" 's.scenarios=[{id:"AC-1",kind:"criterion",skip:"needs login"}]'
  ips=$(ls -A "$T/home-empty" | wc -l | tr -d ' ')
  [ "$ips" = 0 ]; check "no guard case wrote into the install root" $?
}

# fake_install <dir> <version> [with-browser]: the files the doctor reads, nothing more.
fake_install() {
  mkdir -p "$1/node_modules/playwright"; chmod 755 "$1"
  printf '{"name":"playwright","version":"%s"}\n' "$2" > "$1/node_modules/playwright/package.json"
  chmod -R go-w "$1/node_modules"
  if [ "${3:-}" = with-browser ]; then mkdir -p "$1/browsers/chromium-1"; chmod -R go-w "$1/browsers"; fi
}
# doctor <home> [runner] [package.json dir used by the runner copy]: sets RC and the doctor text in DOC.
doctor() {
  DOC=$(cd "${DOCTOR_CWD:-$KIT_DIR}" && UI_VERIFY_HOME="$1" "${TIMEOUT[@]}" node "${2:-$RUNNER}" --doctor 2>&1); RC=$?
}
days_ago() { node -e 'process.stdout.write(new Date(Date.now()-Number(process.argv[1])*864e5).toISOString().slice(0,10))' "$1"; }

# untrusted_case <label> <dir> <detail> <pin>: a complete install at <dir> that must not be used, in the doctor and in a run.
# The dir name picks how it is made untrusted.
untrusted_case() {
  local label=$1 home=$2 detail=$3 pin=$4 out want="install root not trusted: $3"
  case "$home" in
    */dr-intree) mkdir -p "$home"; git init -q "$home" >/dev/null 2>&1; fake_install "$home" "$pin" with-browser ;;
    */dr-group) fake_install "$home" "$pin" with-browser; chmod 775 "$home" ;;
    */dr-world) fake_install "$home" "$pin" with-browser; chmod 777 "$home" ;;
    */dr-parent/root) fake_install "$home" "$pin" with-browser; chmod 775 "$(dirname "$home")" ;;
    */dr-pw) fake_install "$home" "$pin" with-browser; chmod 775 "$home/node_modules/playwright" ;;
    */dr-nm) fake_install "$home" "$pin" with-browser; chmod 775 "$home/node_modules" ;;
    */dr-deepfile) fake_install "$home" "$pin" with-browser; mkdir -p "$home/node_modules/playwright-core/lib"; printf 'x\n' > "$home/node_modules/playwright-core/lib/deep.js"; chmod 664 "$home/node_modules/playwright-core/lib/deep.js" ;;
    */dr-link) fake_install "$home" "$pin" with-browser; mkdir -p "$T/dr-outside"; ln -s "$T/dr-outside" "$home/node_modules/escape" ;;
    */dr-fifo) fake_install "$home" "$pin" with-browser; mkfifo "$home/node_modules/pipe" ;;
    */dr-unreadable) fake_install "$home" "$pin" with-browser; mkdir -p "$home/node_modules/sub"; chmod 000 "$home/node_modules/sub" ;;
    */dr-browsers) fake_install "$home" "$pin" with-browser; printf 'x\n' > "$home/browsers/chromium-1/chrome"; chmod 664 "$home/browsers/chromium-1/chrome" ;;
    */dr-weird) fake_install "$home" "$pin" with-browser; printf 'x\n' > "$home/node_modules/a\`b|c"; chmod 664 "$home/node_modules/a\`b|c" ;;
    */dr-dangling) fake_install "$home" "$pin" with-browser; ln -s "$home/node_modules/not-there" "$home/node_modules/dangling" ;;
    */dr-elsewhere) fake_install "$home" "$pin" with-browser; mkdir -p "$home/elsewhere"; printf 'x\n' > "$home/elsewhere/code.js"; ln -s "$home/elsewhere/code.js" "$home/node_modules/aside.js" ;;
    */dr-core) fake_install "$home" "$pin" with-browser; mkdir -p "$home/node_modules/playwright-core"; chmod 775 "$home/node_modules/playwright-core" ;;
  esac
  doctor "$home"
  { [ "$RC" = 20 ] && printf '%s\n' "$DOC" | grep -qF "NOT READY: $want"; }; check "doctor: $label is not used, state 'NOT READY: $want' (exit $RC)" $?
  RUN_HOME="$home"; out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" "r.status==='NO-CHECK'&&r.reason===\"$want\"")" = true ]; }; check "run: $label is NO-CHECK '$want' (exit $RC)" $?
  RUN_HOME="$T/home-empty"
}

# quoted_install_command <root>: the install command the doctor prints must not run anything from the root path.
quoted_install_command() {
  local root=$1 first
  doctor "$root"
  first=$(printf '%s\n' "$DOC" | sed -n 's/^install: *//p' | sed 's/ && cp .*//')
  ( cd "$CWD" && bash -c "$first" ) >/dev/null 2>&1
  [ -d "$root" ] && [ ! -e "$T/pwned" ]; check "doctor: an install root with a space, a quote and a command substitution is quoted, nothing runs from it"  $?
}

case_doctor_and_skip() {
  echo "--- doctor-and-skip"
  need_node doctor-and-skip || return 0
  local pin home out
  pin=$(jget "$PACKAGE_JSON" 'j.dependencies.playwright')
  [ -n "$pin" ]; check "package.json pins an exact playwright version ($pin)" $?
  [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; check "the pin is exact, not a range" $?
  [[ "$(jget "$PACKAGE_JSON" 'j.pinnedOn')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; check "package.json carries pinnedOn" $?
  [ -s "$KIT_DIR/lib/ui-verify/package-lock.json" ]; check "the lockfile exists" $?
  [ "$(jget "$KIT_DIR/lib/ui-verify/package-lock.json" 'j.packages["node_modules/playwright"].version')" = "$pin" ]; check "the lockfile resolves the pinned version" $?

  home="$T/dr-empty"; mkdir -p "$home"
  doctor "$home"
  [ "$RC" = 20 ]; check "doctor against an empty install root exits 20, run from the kit checkout (exit $RC)" $?
  for tok in "pinned:        playwright $pin" 'pin age:' "install root:  $home" "browser cache: $home/browsers" 'npm ci --ignore-scripts' 'playwright install chromium' 'NOT READY'; do
    printf '%s\n' "$DOC" | grep -qF -- "$tok"; check "doctor output holds: $tok" $?
  done

  RUN_HOME="$home"; out=$(next_out)
  run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 2 ]; check "a scenario run with no install exits 2 (exit $RC)" $?
  [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"')" = true ]; check "every row is NO-CHECK" $?
  [ "$(jget "$out/result.json" 'j.rows[0].reason.indexOf("install absent")===0')" = true ]; check "the row reason names the absent install" $?
  [ "$(jget "$out/result.json" 'j.verdict')" = NO-CHECK ]; check "the verdict is NO-CHECK, never PASS" $?

  home="$T/dr-drift"; fake_install "$home" 0.0.1 with-browser
  doctor "$home"
  [ "$RC" = 21 ]; check "doctor with another installed version exits 21 (exit $RC)" $?
  RUN_HOME="$home"; out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.reason==="playwright version differs from the pin"')" = true ]; check "a scenario run on a drifted install is NO-CHECK 'playwright version differs from the pin' (exit $RC)" $?
  home="$T/dr-nobrowser"; fake_install "$home" "$pin"
  doctor "$home"
  [ "$RC" = 22 ]; check "doctor at the pin with no browsers directory exits 22 (exit $RC)" $?
  RUN_HOME="$home"; out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason.length>0')" = true ]; check "a scenario run with no browser is NO-CHECK with a reason (exit $RC)" $?
  mkdir -p "$home/browsers/chromium-1"
  doctor "$home"
  [ "$RC" = 0 ]; check "control: with the browsers directory the doctor exits 0 (exit $RC)" $?
  RUN_HOME="$T/home-empty"

  local good="$T/dr-good" copy="$T/pincopy" age
  fake_install "$good" "$pin" with-browser
  mkdir -p "$copy"; cp "$RUNNER" "$copy/run.mjs"
  for age in 119 120 121; do
    node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));p.pinnedOn=process.argv[3];fs.writeFileSync(process.argv[2],JSON.stringify(p))' "$PACKAGE_JSON" "$copy/package.json" "$(days_ago "$age")"
    DOCTOR_CWD="$CWD" doctor "$good" "$copy/run.mjs"
    if [ "$age" = 121 ]; then
      { [ "$RC" = 0 ] && printf '%s\n' "$DOC" | grep -qF 'READY (pin older than 120 days: bump it)'; }; check "a pin $age days old prints the bump note and still exits 0 (exit $RC)" $?
    else
      { [ "$RC" = 0 ] && printf '%s\n' "$DOC" | grep -q '^state: *READY$'; }; check "a pin $age days old prints plain READY and exits 0 (exit $RC)" $?
    fi
  done

  untrusted_case "an install root inside a git work tree" "$T/dr-intree" 'inside a git work tree' "$pin"
  untrusted_case "a group-writable install root" "$T/dr-group" 'writable by group or others' "$pin"
  untrusted_case "a world-writable install root" "$T/dr-world" 'writable by group or others' "$pin"
  untrusted_case "an install root whose parent directory is group-writable and not sticky" "$T/dr-parent/root" 'a parent directory is writable by group or others and is not sticky' "$pin"
  untrusted_case "an install root whose node_modules/playwright is group-writable" "$T/dr-pw" 'node_modules/playwright is writable by group or others' "$pin"
  untrusted_case "an install root whose node_modules is group-writable" "$T/dr-nm" 'node_modules is writable by group or others' "$pin"
  untrusted_case "an install root whose node_modules/playwright-core is group-writable" "$T/dr-core" 'node_modules/playwright-core is writable by group or others' "$pin"
  untrusted_case "an install root with one group-writable file deep inside node_modules/playwright-core/lib" "$T/dr-deepfile" 'node_modules/playwright-core/lib/deep.js is writable by group or others' "$pin"
  untrusted_case "an install root with a link inside node_modules that points outside the root" "$T/dr-link" 'node_modules/escape is a link that leaves node_modules and browsers' "$pin"
  untrusted_case "an install root with a dangling link inside node_modules" "$T/dr-dangling" 'node_modules/dangling is a link that cannot be resolved' "$pin"
  untrusted_case "an install root with a link inside node_modules to a file under the root but outside node_modules" "$T/dr-elsewhere" 'node_modules/aside.js is a link that leaves node_modules and browsers' "$pin"
  untrusted_case "an install root with a FIFO inside node_modules" "$T/dr-fifo" 'node_modules/pipe is not a file, a directory or a link' "$pin"
  if [ "$(id -u)" != 0 ]; then
    untrusted_case "an install root with a directory inside node_modules that the user cannot read" "$T/dr-unreadable" 'node_modules/sub cannot be read' "$pin"
    chmod 755 "$T/dr-unreadable/node_modules/sub"
  else skip "doctor-and-skip: running as root, a mode 000 directory is still readable"; fi
  untrusted_case "an install root with a group-writable file inside browsers" "$T/dr-browsers" 'browsers/chromium-1/chrome is writable by group or others' "$pin"
  untrusted_case "an install root with a group-writable file whose name holds a backtick and a pipe" "$T/dr-weird" "node_modules/a'b/c is writable by group or others" "$pin"
  doctor "$T/dr-weird"
  [ "$(printf '%s\n' "$DOC" | awk '/^state:/{print}' | tr -d '`|' | wc -c)" = "$(printf '%s\n' "$DOC" | awk '/^state:/{print}' | wc -c)" ]; check "the doctor state line for that file name holds no backtick and no pipe" $?
  home="$T/dr-linkok"; fake_install "$home" "$pin" with-browser; ln -s playwright "$home/node_modules/inside"
  doctor "$home"
  [ "$RC" = 0 ]; check "control: a link inside node_modules that resolves inside node_modules does not refuse the install root (exit $RC)" $?
  import_time_check "$pin"
  home="$T/dr-sticky/root"; fake_install "$home" "$pin" with-browser; chmod 1777 "$(dirname "$home")"
  doctor "$home"
  [ "$RC" = 0 ]; check "control: a sticky world-writable parent directory (like /tmp) does not refuse the install root (exit $RC)" $?
  home="$T/dr-plain/root"; fake_install "$home" "$pin" with-browser
  doctor "$home"
  [ "$RC" = 0 ]; check "control: an ordinary 755 parent directory does not refuse the install root (exit $RC)" $?
  if [ "$(id -u)" != 0 ] && [ -d /var/empty ] && [ "$(ls -ldn /var/empty | awk '{print $3}')" != "$(id -u)" ]; then
    untrusted_case "an install root owned by another user (/var/empty)" /var/empty 'not owned by the current user' "$pin"
  else skip "doctor-and-skip: no root-owned directory to use as a foreign install root"; fi
  quoted_install_command "$T/dr-quote/a b'c \$(touch $T/pwned)"

  doctor "$T/dr-empty"
  case "$(printf '%s\n' "$DOC" | awk '/^state:/{print}')" in *"NOT READY: "*) ok "the doctor state line carries the reason the browser cases print after SKIP" ;; *) no "doctor state line lacks a reason" ;; esac

  doctor_nonode_run
}

# import_time_check <pin>: the trust check also runs right before the import. With the early check cut out of a runner
# copy, a group-writable playwright-core is still refused; with both cut out, the run gets as far as the import.
import_time_check() {
  local home="$T/dr-late" early late out want="install root not trusted: node_modules/playwright-core is writable by group or others"
  fake_install "$home" "$1" with-browser; mkdir -p "$home/node_modules/playwright-core"; chmod 775 "$home/node_modules/playwright-core"
  RUN_HOME="$home"
  if early=$(runner_variant noearly 'const detail = untrustedReason(root);' "const detail = '';"); then
    out=$(next_out); RUN_RUNNER="$early" run_runner "$CWD" "$BASE" "$out"
    { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" "r.status==='NO-CHECK'&&r.reason==='$want'")" = true ]; }; check "run: with the early check cut out, the check before the import still refuses a group-writable playwright-core (exit $RC)" $?
    if late=$(VARIANT_SRC="$early" runner_variant noimport 'if (untrusted) throw new InstallNotTrusted(untrusted);' ''); then
      out=$(next_out); RUN_RUNNER="$late" run_runner "$CWD" "$BASE" "$out"
      [ "$(rows_all "$out/result.json" "r.reason==='$want'")" = false ]; check "control: with both checks cut out the same install is not refused by the trust check (exit $RC)" $?
    else no "control: the check before the import is no longer in the runner"; fi
  else no "control: the early trust check is no longer in the runner"; fi
  RUN_RUNNER=""; RUN_HOME="$T/home-empty"
}

# doctor_nonode_run: the suite run again with a PATH that holds the common tools but no node.
doctor_nonode_run() {
  local bin="$T/nonode-bin" tool path_tool s r1 r2 last
  mkdir -p "$bin"
  for tool in bash git grep sed awk mktemp cat rm mkdir cp mv tr cut head tail sort uniq wc date dirname basename env shasum curl ls find kill sleep pgrep touch ln chmod tee uname perl diff cmp xargs id readlink; do
    path_tool=$(command -v "$tool" 2>/dev/null) || continue
    case "$path_tool" in /*) ln -sf "$path_tool" "$bin/$tool" ;; esac
  done
  if PATH="$bin" command -v node >/dev/null 2>&1; then no "the no-node PATH still finds node"; return 0; fi
  s="$KIT_DIR/tests/test-ui-acceptance-verifier.sh"
  r1=$(PATH="$bin" UI_VERIFY_REQUIRE= "$bin/bash" "$s" guard-refusals internal-error battery-row 2>&1); local rc1=$?
  last=$(printf '%s\n' "$r1" | tail -n 1)
  [ "$rc1" = 0 ]; check "no node: the suite exits 0 (exit $rc1)" $?
  [ "$(printf '%s\n' "$r1" | grep -c 'SKIP node not installed')" = 2 ]; check "no node: each node case prints 'SKIP node not installed'" $?
  printf '%s\n' "$r1" | grep -q 'PASS  battery: lens row'; check "no node: the bash-only battery-row case still ran" $?
  case "$last" in "test-ui-acceptance-verifier: "*" passed, 0 failed, 2 skipped") ok "no node: the last line counts 2 skipped ($last)" ;; *) no "no node: last line was: $last" ;; esac
  r2=$(PATH="$bin" UI_VERIFY_REQUIRE=1 "$bin/bash" "$s" internal-error battery-row 2>&1); local rc2=$?
  [ "$rc2" = 1 ]; check "no node with UI_VERIFY_REQUIRE=1: the suite exits 1 (exit $rc2)" $?
  r2=$("$BASH" "$s" internal-error battery-row 2>&1)
  case "$(printf '%s\n' "$r2" | tail -n 1)" in *" 0 skipped") ok "control: with node on PATH the same cases skip nothing" ;; *) no "control run last line: $(printf '%s\n' "$r2" | tail -n 1)" ;; esac
}

case_suite_harness() {
  echo "--- suite-harness"
  need_node suite-harness || return 0
  local s="$KIT_DIR/tests/test-ui-acceptance-verifier.sh" out rc last ghost="$T/ghost" empty="$T/harness-home" f="$T/harness-rows.json" stub="$T/count-bin" log="$T/node-calls.log" real_node
  out=$("$BASH" "$s" no-such-case 2>&1); rc=$?
  { [ "$rc" = 1 ] && grep -q '^  FAIL  unknown case name: no-such-case' <<< "$out"; }; check "an unknown case name fails the suite with a FAIL line (exit $rc)" $?
  mkdir -p "$ghost/tests"; sed 's/^CASES="/CASES="ghost-case /' "$s" > "$ghost/tests/test-ui-acceptance-verifier.sh"
  cmp -s "$s" "$ghost/tests/test-ui-acceptance-verifier.sh"; [ $? -eq 1 ]; check "control: the ghost copy of the suite differs from the real one" $?
  out=$("$BASH" "$ghost/tests/test-ui-acceptance-verifier.sh" ghost-case 2>&1); rc=$?
  { [ "$rc" = 1 ] && grep -q '^  FAIL  case ghost-case is listed and has no function case_ghost_case' <<< "$out"; }; check "a listed case with no function fails the suite, selected or not (exit $rc)" $?
  out=$("$BASH" "$s" battery-row 2>&1); rc=$?
  { [ "$rc" = 0 ] && grep -q '^  PASS  battery: lens row' <<< "$out"; }; check "control: a real case name runs and exits 0 (exit $rc)" $?

  printf '{"rows":[]}' > "$f"
  [ "$(rows_all "$f" 'r.status==="PASS"')" = false ]; check "rows_all is false on an empty row set" $?
  printf '{"rows":[{"status":"PASS"}]}' > "$f"
  [ "$(rows_all "$f" 'r.status==="PASS"')" = true ]; check "control: rows_all is true on one passing row" $?
  [ "$(rows_all "$f" 'r.status==="FAIL"')" = false ]; check "control: rows_all is false when a row does not satisfy the test" $?
  wait_no_browser ""; [ $? -eq 1 ]; check "wait_no_browser fails on an empty run id" $?
  wait_no_browser "feedfacecafe"; check "control: wait_no_browser passes for a run id that no process carries" $?

  mkdir -p "$empty" "$stub"; real_node=$(command -v node)
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$log" "$real_node" > "$stub/node"; chmod +x "$stub/node"
  out=$(env -u UI_VERIFY_REQUIRE UI_VERIFY_HOME="$empty" PATH="$stub:$PATH" "$BASH" "$s" no-ac hang-bounded 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  { [ "$rc" = 0 ] && [ "$(grep -c '^  SKIP ' <<< "$out")" = 2 ]; }; check "an empty install root: two browser cases SKIP and the suite exits 0 (exit $rc)" $?
  grep -q '^  SKIP no-ac: browser not ready: NOT READY' <<< "$out"; check "a browser case SKIP names the doctor's reason" $?
  case "$last" in "test-ui-acceptance-verifier: 0 passed, 0 failed, 2 skipped") ok "the last line counts 2 skipped ($last)" ;; *) no "empty install root: last line was: $last" ;; esac
  [ "$(grep -c -- '--doctor' "$log")" = 1 ]; check "the doctor ran once for two browser cases" $?
  out=$(env UI_VERIFY_REQUIRE=1 UI_VERIFY_HOME="$empty" "$BASH" "$s" no-ac hang-bounded 2>&1); rc=$?
  { [ "$rc" = 1 ] && [ "$(grep -c 'SKIP not allowed under UI_VERIFY_REQUIRE=1' <<< "$out")" = 2 ]; }; check "an empty install root with UI_VERIFY_REQUIRE=1: each SKIP is a FAIL and the suite exits 1 (exit $rc)" $?
}

# The live record the lead writes after a real dispatch. record_ok prints one line per missing item and returns 1.
# Lines it reads (one label per line, in any order):
#   Working directory: <absolute path the dispatch ran from>
#   Tools: <the agent's frontmatter tools, no Write and no npx>
#   Playwright: <major.minor.patch>
#   ... 0 skipped ...
#   VERDICT: PASS, VERDICT: FAIL:fixable (naming Error 500) and VERDICT: FAIL:escalate (naming NO-CHECK: scenario does not cover)
#   No evidence was uploaded or committed.
RECORD="${UI_VERIFY_RECORD:-$KIT_DIR/docs/verification/ui-acceptance-verifier.md}"
record_ok() {
  local f=$1 broke=0 item pattern tools
  [ -s "$f" ] || { echo "the record is missing or empty"; return 1; }
  for item in 'Working directory: an absolute path|^Working directory: /' 'Playwright: a version|^Playwright: [0-9]+\.[0-9]+\.[0-9]+' '0 skipped|0 skipped' 'VERDICT: PASS|VERDICT: PASS' 'VERDICT: FAIL:fixable naming Error 500|VERDICT: FAIL:fixable.*Error 500' 'VERDICT: FAIL:escalate naming the uncovered criterion|VERDICT: FAIL:escalate.*NO-CHECK: scenario does not cover' 'no evidence uploaded or committed|^No evidence was uploaded or committed'; do
    pattern=${item#*|}
    grep -qE -- "$pattern" "$f" || { echo "record lacks: ${item%%|*}"; broke=1; }
  done
  tools=$(grep '^Tools: ' "$f")
  if [ -z "$tools" ]; then echo "record lacks: a Tools line"; broke=1
  elif printf '%s\n' "$tools" | grep -qE '\bWrite\b|npx'; then echo "the Tools line lists Write or npx"; broke=1; fi
  return "$broke"
}

case_live_record() {
  echo "--- live-record"
  local good="$T/record.good.md" copy="$T/record.copy.md" prefix
  cat > "$good" <<'EOF'
Working directory: /scratch/outside/any/tree
Tools: Read, Grep, Glob, Bash(node */lib/ui-verify/run.mjs*)
Playwright: 1.65.1
Runner exit 0, 0 skipped.
VERDICT: PASS
VERDICT: FAIL:fixable the AC-2 row observed Error 500
VERDICT: FAIL:escalate NO-CHECK: scenario does not cover AC-3
No evidence was uploaded or committed.
EOF
  record_ok "$good" >/dev/null; check "control record: a complete record passes the record checks" $?
  for prefix in 'Working directory:' 'Tools:' 'Playwright:' 'Runner exit' 'VERDICT: PASS' 'VERDICT: FAIL:fixable' 'VERDICT: FAIL:escalate' 'No evidence'; do
    grep -v "^$prefix" "$good" > "$copy"
    cmp -s "$good" "$copy"; [ $? -eq 1 ] && red_with "record lacks" record_ok "$copy"; check "control record: a copy without the '$prefix' line goes red" $?
  done
  sed 's/^Tools: .*/Tools: Read, Write, Grep/' "$good" > "$copy"
  red_with "the Tools line lists Write or npx" record_ok "$copy"; check "control record: a copy whose Tools line lists Write goes red" $?
  sed 's/^Tools: .*/Tools: Read, Bash(npx playwright*)/' "$good" > "$copy"
  red_with "the Tools line lists Write or npx" record_ok "$copy"; check "control record: a copy whose Tools line lists npx goes red" $?

  if [ ! -s "$RECORD" ]; then no "live record: docs/verification/ui-acceptance-verifier.md does not exist yet (the live dispatch writes it)"; return 0; fi
  record_ok "$RECORD"; check "the live record names the working directory, the tools, the Playwright version, 0 skipped, the three verdicts and no uploaded evidence" $?
  grep -v '^Working directory:' "$RECORD" > "$copy"
  red_with "record lacks: Working directory" record_ok "$copy"; check "control: a copy of the live record without its working-directory line goes red" $?
}

# A fake install at the pin, so the runner gets as far as loading Playwright and starting a browser.
case_no_browser_rows() {
  echo "--- no-browser-rows"
  need_node no-browser-rows || return 0
  local pin home out f="$T/nbr.json" variant
  pin=$(jget "$PACKAGE_JSON" 'j.dependencies.playwright')
  mutate "$BASE" "$f" 's.scenarios=[{id:"AC-1",kind:"criterion",skip:"a | b `c`\n| AC-9 | PASS"},{id:"AC-2",kind:"negative",skip:"needs a login"}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "a scenario file that is all skip rows exits 2 and needs no install (exit $RC)" $?
  [ "$(grep -c '^row ' "$T/stdout")" = 2 ]; check "stdout holds one row line per skip entry" $?
  grep -qFx "row AC-1 | NO-CHECK | skipped by scenario: a / b 'c' / AC-9 / PASS |" "$T/stdout"; check "a skip row is NO-CHECK 'skipped by scenario: ...' with the pipe and backtick defanged" $?
  grep -qFx "row AC-2 neg | NO-CHECK | skipped by scenario: needs a login |" "$T/stdout"; check "the negative skip row is labelled 'AC-2 neg'" $?
  [ "$(jget "$out/result.json" 'j.verdict+"|"+j.rows.map(r=>r.status+r.viewports.length+r.evidence.length).join(",")')" = "NO-CHECK|NO-CHECK00,NO-CHECK00" ]; check "the verdict is NO-CHECK and no skip row has viewports or evidence" $?
  mutate "$BASE" "$f" 's.scenarios.push({id:"AC-2",kind:"criterion",skip:"later"});s.scenarios.shift()'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$(jget "$out/result.json" 'j.rows.length+"|"+j.rows[0].reason')" = "1|skipped by scenario: later" ]; check "control: the skip reason is the lead's text, not a constant" $?

  home="$T/nbr-load"; fake_install "$home" "$pin" with-browser
  RUN_HOME="$home"; out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="install absent: playwright could not be loaded"')" = true ]; }; check "a fake install with no Playwright entry file: every row is NO-CHECK 'install absent: playwright could not be loaded' (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.browser.launch_attempts+"|"+j.browser.pids.length')" = "0|0" ]; check "no launch was attempted" $?
  printf "export const chromium = { launch: async () => { throw new Error('boom'); } };\n" > "$home/node_modules/playwright/index.mjs"
  out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="browser did not start"')" = true ]; }; check "a launch that throws: every row is NO-CHECK 'browser did not start' (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.browser.launch_attempts+"|"+j.browser.sandbox')" = "1|false" ]; check "one launch attempt, no retry, sandbox not reported on" $?
  printf "export const chromium = { launch: async () => { throw new Error('no usable sandbox'); } };\n" > "$home/node_modules/playwright/index.mjs"
  out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="browser sandbox unavailable"')" = true ]; }; check "control: a launch error that names the sandbox is NO-CHECK 'browser sandbox unavailable', not 'browser did not start' (exit $RC)" $?
  RUN_HOME="$T/home-empty"
}

# signal_during_launch <spawn|hang> <signal>: the runner against a fake Playwright whose launch never returns. In mode
# spawn the launch first starts a stray process that carries the run id (a browser that is still launching); in mode
# hang it starts nothing. The signal goes in once the launch has begun. Sets SIG_RC and leaves stderr in $T/sigl.err.
signal_during_launch() {
  local mode=$1 sig=$2 home="$T/sigl-home" mark="$T/sigl.mark" out pid i=0 id=""
  if [ ! -d "$home" ]; then fake_install "$home" "$(jget "$PACKAGE_JSON" 'j.dependencies.playwright')" with-browser; fi
  cat > "$home/node_modules/playwright/index.mjs" <<'EOF'
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
export const chromium = {
  launch: (options) => new Promise(() => {
    if (process.env.FAKE_LAUNCH === 'spawn') spawn(process.execPath, ['-e', 'setTimeout(()=>{},300000)', '--', ...options.args, `${process.env.PLAYWRIGHT_BROWSERS_PATH}/chromium-fake`], { stdio: 'ignore' });
    setInterval(() => {}, 1000);
    writeFileSync(process.env.FAKE_MARK, 'launching');
  }),
};
EOF
  rm -f "$mark"; out=$(next_out)
  rm -rf "$T/sigl-tmp"; mkdir -p "$T/sigl-tmp"
  ( cd "$CWD" && UI_VERIFY_HOME="$home" TMPDIR="$T/sigl-tmp" FAKE_LAUNCH="$mode" FAKE_MARK="$mark" exec node "$RUNNER" scenario --scenario "$BASE" --out "$out" ) >"$T/sigl.out" 2>"$T/sigl.err" &
  pid=$!
  while [ "$i" -lt 120 ] && [ ! -e "$mark" ]; do sleep 0.5; i=$((i+1)); done
  id=$(awk '/^ui-verify: run /{print $3; exit}' "$T/sigl.err")
  ALL_RUN_IDS="$ALL_RUN_IDS $id"
  SIG_ID=$id
  if [ "$mode" = spawn ]; then i=0; while [ "$i" -lt 60 ] && ! pgrep -f -- "--kit-ui-verify=$id" >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); done; fi
  kill -s "$sig" "$pid" 2>/dev/null
  i=0; while [ "$i" -lt 120 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.5; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null; fi
  { wait "$pid"; } 2>/dev/null; SIG_RC=$?
}

case_signal_during_launch() {
  echo "--- signal-during-launch"
  need_node signal-during-launch || return 0
  signal_during_launch spawn TERM
  [ "$SIG_RC" = 143 ]; check "SIGTERM while the browser is still launching ends the runner with exit 143 (exit $SIG_RC)" $?
  [ -n "$SIG_ID" ] && ! pgrep -f -- "--kit-ui-verify=$SIG_ID" >/dev/null 2>&1; check "no process that carries the run id is left after that SIGTERM" $?
  grep -q '^ui-verify: interrupted, browser closed' "$T/sigl.err"; check "the runner reports that it stopped the browser" $?
  [ -z "$(ls -A "$T/sigl-tmp")" ]; check "the browser's temporary home is removed after a signal exit" $?
  signal_during_launch hang TERM
  [ "$SIG_RC" = 143 ]; check "SIGTERM with no browser started ends the runner with exit 143 (exit $SIG_RC)" $?
  grep -q '^ui-verify: interrupted, no browser was running' "$T/sigl.err" && ! grep -q 'browser closed' "$T/sigl.err"; check "the runner does not claim to have closed a browser that never started" $?
  signal_during_launch hang INT
  [ "$SIG_RC" = 130 ]; check "SIGINT ends the runner with exit 130 (exit $SIG_RC)" $?
  signal_during_launch hang HUP
  { [ "$SIG_RC" = 129 ] && grep -q '^ui-verify: interrupted, no browser was running' "$T/sigl.err"; }; check "SIGHUP is handled like SIGTERM: the runner reports it and ends with exit 129 (exit $SIG_RC)" $?
  [ -z "$(ls -A "$T/sigl-tmp")" ]; check "the browser's temporary home is removed after SIGHUP too" $?
}

case_fixture_serves() {
  echo "--- fixture-serves"
  need_node fixture-serves || return 0
  local page code count file
  for file in tests/fixtures/ui-verify/serve.mjs tests/fixtures/ui-verify/index.html tests/fixtures/ui-verify/hostile.html tests/fixtures/ui-verify/offsite.html tests/fixtures/ui-verify/otherport.html tests/fixtures/ui-verify/many.html tests/fixtures/ui-verify/nobody.html tests/fixtures/ui-verify/meta.html tests/fixtures/ui-verify/wall.html; do
    [ -s "$KIT_DIR/$file" ]; check "fixture file exists: $file" $?
  done
  if ! start_fixture; then no "the fixture server printed a port line and a port2 line"; stop_fixture; return 0; fi
  case "$FIX_PORT$FIX_PORT2" in *[!0-9]*|"") no "port and port2 are numbers ($FIX_PORT, $FIX_PORT2)" ;; *) ok "the server prints a port line and a port2 line" ;; esac
  for page in index.html hostile.html offsite.html otherport.html many.html nobody.html meta.html wall.html; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$FIX_PORT/$page"); [ "$code" = 200 ]; check "$page answers 200 (got $code)" $?
  done
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$FIX_PORT/"); [ "$code" = 200 ]; check "/ answers 200" $?
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$FIX_PORT/nope.html"); [ "$code" = 404 ]; check "control: a page that does not exist answers 404 (got $code)" $?
  code=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$FIX_PORT/redirect"); [ "$code" = "302 http://localhost:$FIX_PORT2/pixel" ]; check "/redirect answers 302 to the second listener as localhost (got $code)" $?
  code=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$FIX_PORT/redirect-ok"); [ "$code" = "302 http://127.0.0.1:$FIX_PORT/" ]; check "/redirect-ok answers 302 to / (got $code)" $?
  curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$FIX_PORT/hang"; code=$?
  [ "$code" = 28 ]; check "/hang gets no answer, curl times out client-side (curl exit $code)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count"); [ "$count" = '{"hits":0,"upgrades":0}' ]; check "GET /count answers zero hits and upgrades before any traffic ($count)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count"); [ "$count" = '{"hits":0,"upgrades":0}' ]; check "the /count request is not itself counted" $?
  curl -s -o /dev/null "http://127.0.0.1:$FIX_PORT2/pixel"
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count"); [ "$count" = '{"hits":1,"upgrades":0}' ]; check "control: a plain request to the second listener counts one hit ($count)" $?
  page=$(curl -s "http://127.0.0.1:$FIX_PORT/offsite.html")
  grep -q "localhost:$FIX_PORT2" <<< "$page"; check "offsite.html points at the second listener's port" $?
  stop_fixture

  local headers
  start_fixture --build-sha abc1234 || no "the server started with --build-sha"
  headers=$(curl -s -D - -o /dev/null "http://127.0.0.1:$FIX_PORT/")
  grep -qi '^x-build-sha: abc1234' <<< "$headers"; check "--build-sha sets the x-build-sha response header" $?
  stop_fixture
  start_fixture
  headers=$(curl -s -D - -o /dev/null "http://127.0.0.1:$FIX_PORT/")
  grep -qi '^x-build-sha:' <<< "$headers"; [ $? -eq 1 ]; check "no header without --build-sha" $?
  stop_fixture

  local copy="$T/fixcopy"
  mkdir -p "$copy"; cp "$FIXDIR/serve.mjs" "$FIXDIR/index.html" "$FIXDIR/hostile.html" "$FIXDIR/offsite.html" "$FIXDIR/otherport.html" "$FIXDIR/many.html" "$FIXDIR/nobody.html" "$FIXDIR/meta.html" "$copy/"
  FIX_SRC="$copy"
  if start_fixture; then
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$FIX_PORT/wall.html"); [ "$code" = 404 ]; check "control: a fixture copy without wall.html answers 404 for it (got $code)" $?
  else no "the fixture copy started"; fi
  stop_fixture; FIX_SRC=""
}

case_internal_error() {
  echo "--- internal-error"
  need_node internal-error || return 0
  local out
  out=$(next_out)
  UI_VERIFY_TEST_FAULT=internal-error run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 4 ]; check "the injected fault exits 4 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.verdict')" = NO-CHECK ]; check "result.json holds verdict NO-CHECK" $?
  [ "$(jget "$out/result.json" 'j.reason.indexOf("internal error:")===0')" = true ]; check "result.json reason starts 'internal error:'" $?
  grep -q '^ui-verify: internal error:' "$T/stderr"; check "stderr carries one 'ui-verify: internal error:' line" $?
  out=$(next_out)
  run_runner "$CWD" "$BASE" "$out"
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: the same scenario without the variable exits 0 or 2 (exit $RC)" $?
  out=$(next_out)
  UI_VERIFY_TEST_FAULT=internal-error run_runner "$CWD" "$T/does-not-exist.json" "$out"
  [ "$RC" = 3 ]; check "the fault does not mask a refusal: an unreadable scenario still exits 3 (exit $RC)" $?
  [ "$(run_runner "$CWD" "$BASE" "$(next_out)" --nonsense x; echo $RC)" = 3 ]; check "an unknown argument exits 3" $?
  local variant
  if variant=$(runner_variant uncaught "process.on('uncaughtException'" "process.on('uncaughtExceptionOff'"); then
    out=$(next_out)
    RUN_RUNNER="$variant" UI_VERIFY_TEST_FAULT=internal-error run_runner "$CWD" "$BASE" "$out"
    [ "$RC" = 1 ]; check "control: a runner copy that no longer listens for uncaughtException exits 1, not 4, on the injected fault (exit $RC)" $?
  else no "control: the uncaughtException registration is no longer in the runner"; fi
}

# The real install root the browser cases run against (UI_VERIFY_HOME wins, as in the runner).
BROWSER_HOME=""
if [ "$HAVE_NODE" = 1 ]; then BROWSER_HOME=$(bash "$RESOLVER" path cache ui-verify 2>/dev/null); fi

# begin_browser <case>: gate, start the fixture and point the runner at the real install. end_browser undoes it.
begin_browser() {
  browser_gate "$1" || return 1
  if ! start_fixture "${@:2}"; then no "$1: the fixture server printed its ports"; stop_fixture; return 1; fi
  RUN_HOME="$BROWSER_HOME"
  return 0
}
end_browser() { stop_fixture; RUN_HOME="$T/home-empty"; }

HEAD40=0123456789abcdef0123456789abcdef01234567
BBASE="$T/browser-base.json"
cat > "$BBASE" <<'JSON'
{"schema":1,"target":{"url":"http://127.0.0.1:__PORT__/","head_sha":"0123456789abcdef0123456789abcdef01234567","allow_hosts":["127.0.0.1"],"allow_loopback":true},"viewports":[1280],"ready":{"text":"Kit fixture app"},"scenarios":[
{"id":"AC-1","kind":"criterion","title":"a name can be saved","steps":[{"do":"goto","path":"/"},{"do":"fill","role":"textbox","name":"Display name","value":"Ada"},{"do":"click","role":"button","name":"Save"},{"do":"expect_text","text":"Saved"},{"do":"screenshot","name":"after-save"}]},
{"id":"AC-1","kind":"negative","title":"an expired link cannot save","steps":[{"do":"goto","path":"/?link=expired"},{"do":"expect_text","text":"This link has expired"},{"do":"expect_no_text","text":"Saved"},{"do":"screenshot","name":"refused"}]},
{"id":"AC-2","kind":"criterion","title":"the save button works","steps":[{"do":"goto","path":"__PATH__"},{"do":"click","role":"button","name":"Save"},{"do":"expect_text","text":"Saved"},{"do":"screenshot","name":"saved"}]},
{"id":"AC-3","kind":"criterion","title":"the home heading shows","steps":[{"do":"goto","path":"/"},{"do":"expect_text","text":"Kit fixture app","within":{"role":"heading","name":"Kit fixture app"}},{"do":"expect_url","path":"/"},{"do":"screenshot","name":"home"}]}
]}
JSON

# bscenario <file> <AC-2 path> [js edit using s]: the browser base scenario aimed at the running fixture.
bscenario() {
  sed "s#__PORT__#$FIX_PORT#g;s#__PATH__#$2#g" "$BBASE" > "$1"
  if [ -n "${3:-}" ]; then mutate "$1" "$1" "$3"; fi
}
# page_scenario <file> <page path> <ready text> <scenarios js>: a one-page scenario file aimed at the fixture.
page_scenario() {
  sed "s#__PORT__#$FIX_PORT#g;s#__PATH__#/#g" "$BBASE" > "$1"
  mutate "$1" "$1" "s.target.url=s.target.url.replace(/\\/\$/,'')+'$2';s.ready.text='$3';$4"
}
sha256_of() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
row_line() { jget "$1" 'j.rows.map(r=>r.id+(r.kind==="negative"?" neg":"")+"="+r.status+"/"+r.flaky).join(",")'; }
# wait_no_browser <run id>: true once no process carries the run id; the ceiling fails the caller, never passes it, and
# an empty run id fails too (a pgrep for nothing would find nothing and pass).
wait_no_browser() {
  local i=0
  [ -n "${1:-}" ] || return 1
  while [ "$i" -lt $((PGREP_CEILING_S*2)) ]; do
    pgrep -f -- "--kit-ui-verify=$1" >/dev/null 2>&1 || return 0
    sleep 0.5; i=$((i+1))
  done
  return 1
}

case_rows_and_planted_bug() {
  echo "--- rows-and-planted-bug"
  begin_browser rows-and-planted-bug || return 0
  local f="$T/rpb.json" out png n
  bscenario "$f" "/?bug=1"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "the planted bug (/?bug=1) exits 1 (exit $RC)" $?
  [ "$(row_line "$out/result.json")" = "AC-1=PASS/false,AC-1 neg=PASS/false,AC-2=FAIL/false,AC-3=PASS/false" ]; check "only the AC-2 row is FAIL, the other three keep PASS" $?
  [ "$(jget "$out/result.json" 'j.rows[2].observed.indexOf("Error 500")>=0')" = true ]; check "the AC-2 observed value holds 'Error 500'" $?
  grep -qFx 'ui-verify: counts PASS 3 FAIL 1 NO-CHECK 0 runner-verdict FAIL' "$T/stdout"; check "the planted-bug run prints the counts line with FAIL 1 and runner-verdict FAIL" $?
  grep -qFx 'row AC-2 | FAIL |  |' "$T/stdout"; check "a FAIL row with no reason and no evidence prints as 'row AC-2 | FAIL |  |'" $?
  grep -qE '^observed AC-2: .*Error 500' "$T/stdout"; check "the observed line reads 'observed <id>: <text>' and holds Error 500" $?
  bscenario "$f" "/"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 0 ]; check "control: the same file without ?bug=1 exits 0 (exit $RC)" $?
  [ "$(row_line "$out/result.json")" = "AC-1=PASS/false,AC-1 neg=PASS/false,AC-2=PASS/false,AC-3=PASS/false" ]; check "result.json holds exactly the four rows AC-1, AC-1 neg, AC-2, AC-3, each PASS and not flaky" $?
  [ "$(jget "$out/result.json" 'j.scenario_sha256')" = "$(sha256_of "$f")" ]; check "scenario_sha256 equals the file's SHA-256" $?
  n=0; for png in ac-1-1280-after-save.png ac-1-neg-1280-refused.png ac-2-1280-saved.png ac-3-1280-home.png; do
    [ -s "$out/$png" ] && n=$((n+1))
  done
  [ "$n" = 4 ]; check "one screenshot file per screenshot step, named ac-<n>[-neg]-<width>-<name>.png ($n of 4)" $?
  [ "$(jget "$out/result.json" 'j.rows.map(r=>r.evidence.length).join(",")')" = "1,1,1,1" ]; check "each row names its screenshot as evidence" $?
  [ "$(grep -c '^ui-verify: ' "$T/stdout")" = 2 ] && [ "$(grep -c '^row ' "$T/stdout")" = 4 ]; check "stdout has the two ui-verify lines and one row line per scenario" $?
  local sha16 ver; sha16=$(sha256_of "$f" | cut -c1-16); ver=$(jget "$out/result.json" 'j.runner.playwright')
  [ "$(sed -n 1p "$T/stdout")" = "ui-verify: head $HEAD40 scenario-sha256 $sha16 preview-identity unverified playwright $ver run $RUN_ID" ]; check "stdout line 1 reads 'ui-verify: head <sha> scenario-sha256 <16 hex> preview-identity <status> playwright <version> run <id>'" $?
  [ "$(sed -n 2p "$T/stdout")" = "ui-verify: counts PASS 4 FAIL 0 NO-CHECK 0 runner-verdict PASS" ]; check "stdout line 2 reads 'ui-verify: counts PASS <n> FAIL <n> NO-CHECK <n> runner-verdict <verdict>'" $?
  [ "$(sed -n 3,6p "$T/stdout")" = "$(printf '%s\n' 'row AC-1 | PASS |  | ac-1-1280-after-save.png' 'row AC-1 neg | PASS |  | ac-1-neg-1280-refused.png' 'row AC-2 | PASS |  | ac-2-1280-saved.png' 'row AC-3 | PASS |  | ac-3-1280-home.png')" ]; check "the row lines read 'row <id>[ neg] | <status> | <reason> | <evidence>' in scenario order" $?
  [ "$(wc -l < "$T/stdout" | tr -d ' ')" = 6 ]; check "a clean run prints exactly six lines: two ui-verify lines and four rows" $?

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"click",role:"button",name:"Nope"},{do:"expect_text",text:"x"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"x",within:{role:"dialog",name:"Ghost"}}]},{id:"AC-3",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"click",role:"button",name:"Save"},{do:"expect_text",text:"Saved"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "a missing button and a missing within element exit 1 (exit $RC)" $?
  [ "$(row_line "$out/result.json")" = "AC-1=FAIL/false,AC-2=FAIL/false,AC-3=PASS/false" ]; check "both missing-element rows are FAIL, never NO-CHECK; the real button passes" $?
  [ "$(jget "$out/result.json" 'j.rows[0].observed')" = "element not found: role=button name=Nope" ]; check "click observed is 'element not found: role=button name=Nope'" $?
  [ "$(jget "$out/result.json" 'j.rows[1].observed')" = "element not found: role=dialog name=Ghost" ]; check "within observed is 'element not found: role=dialog name=Ghost'" $?

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"negative",steps:[{do:"goto",path:"/"},{do:"click",role:"button",name:"Save"},{do:"expect_text",text:"Saved"},{do:"expect_no_text",text:"Saved"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"fill",role:"button",name:"Save",value:"x"},{do:"expect_text",text:"x"}]},{id:"AC-3",kind:"negative",steps:[{do:"goto",path:"/nobody.html"},{do:"expect_no_text",text:"Saved"}]},{id:"AC-4",kind:"negative",steps:[{do:"goto",path:"/"},{do:"expect_no_text",text:"Nothing like this"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "text that is present under expect_no_text, a fill on a button and an unreadable page exit 1 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+(j.rows[0].observed.indexOf("Saved")>=0)')" = "FAIL|true" ]; check "expect_no_text on present text is FAIL and observed holds the text" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status+"|"+j.rows[1].observed.indexOf("element not actionable:")')" = "FAIL|0" ]; check "a fill on a button is a FAIL row whose observed starts 'element not actionable:', not exit 4" $?
  [ "$(jget "$out/result.json" 'j.rows[2].status+"|"+j.rows[2].reason')" = "NO-CHECK|page did not settle" ]; check "expect_no_text on a page with no body to read is NO-CHECK 'page did not settle', never PASS" $?
  grep -qFx 'row AC-3 neg | NO-CHECK | page did not settle |' "$T/stdout"; check "a NO-CHECK row prints its reason in the third column" $?
  [ "$(jget "$out/result.json" 'j.rows[3].status')" = PASS ]; check "control: expect_no_text on text that is absent passes" $?
  end_browser
}

case_no_ac() {
  echo "--- no-ac"
  begin_browser no-ac || return 0
  local f="$T/noac.json" out
  bscenario "$f" "/" 's.scenarios=[]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "an empty scenarios array exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" '[j.verdict,j.reason,j.rows.length].join("|")')" = "NO-CHECK|no AC|0" ]; check "verdict NO-CHECK, reason 'no AC', no rows" $?
  bscenario "$f" "/" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 0 ] && [ "$(jget "$out/result.json" 'j.rows.length')" = 1 ]; }; check "control: one passing scenario added exits 0 with one row (exit $RC)" $?

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"screenshot",name:"nothing"}]},s.scenarios[3]]; s.scenarios[1].id="AC-3"'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "a goto-and-screenshot scenario exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason')" = "NO-CHECK|scenario asserts nothing" ]; check "its row is NO-CHECK 'scenario asserts nothing', never PASS" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status')" = PASS ]; check "the sibling scenario still ran and is PASS" $?
  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"Kit fixture app"},{do:"screenshot",name:"nothing"}]},s.scenarios[3]]; s.scenarios[1].id="AC-3"'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 0 ]; check "control: an expect_text step added to the same scenario exits 0 (exit $RC)" $?
  end_browser
}

case_hostile_text_fenced() {
  echo "--- hostile-text-fenced"
  begin_browser hostile-text-fenced || return 0
  local f="$T/hostile.json" out obs
  page_scenario "$f" /hostile.html "Hostile page" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/hostile.html"},{do:"expect_text",text:"Welcome back"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "expecting other text exits 1 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows.length+"|"+j.rows[0].status+"|"+j.verdict')" = "1|FAIL|FAIL" ]; check "one row, FAIL, runner verdict FAIL" $?
  obs=$(jget "$out/result.json" 'j.rows[0].observed')
  [ "$(jget "$out/result.json" 'var o=j.rows[0].observed;[...o].every(c=>!"\n\r|`".includes(c)&&![0x2028,0x2029,0x202e].includes(c.codePointAt(0)))&&o.length>0&&o.length<=200')" = true ]; check "observed holds no line break, U+2028, U+202E, pipe or backtick and is 1 to 200 characters" $?
  case "$obs" in *"VERDICT: PASS"*) ok "the hostile words reach observed as plain text (the page was read, only defanged)" ;; *) no "observed lost the hostile words: $obs" ;; esac
  [ "$(grep -c '^row ' "$T/stdout")" = 1 ]; check "stdout has exactly one row line" $?
  [ "$(grep -c -e '^| AC' -e '^VERDICT:' "$T/stdout")" = 0 ]; check "stdout has no line that starts '| AC' or 'VERDICT:'" $?
  [ "$(LC_ALL=C grep -c -e "$(printf '\xe2\x80\xa8')" -e "$(printf '\xe2\x80\xae')" "$T/stdout")" = 0 ]; check "stdout holds no raw U+2028 or U+202E" $?
  page_scenario "$f" /hostile.html "Hostile page" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/hostile.html"},{do:"expect_text",text:"VERDICT: PASS"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 0 ]; check "control: expecting the hostile text itself passes (exit $RC)" $?
  end_browser
}

case_git_status_clean() {
  echo "--- git-status-clean"
  begin_browser git-status-clean || return 0
  local f="$T/gsc.json" repo="$T/gsc-repo" out
  mkdir -p "$repo"; git init -q "$repo" >/dev/null 2>&1
  bscenario "$f" "/"
  out=$(next_out); run_runner "$repo" "$f" "$out"
  [ "$RC" = 0 ]; check "a full run from inside a scratch git repo exits 0, so the own-path self-check passed (exit $RC)" $?
  [ -z "$(git -C "$repo" status --porcelain --untracked-files=all)" ]; check "git status --porcelain is empty after the run" $?
  [ -s "$out/result.json" ]; check "the evidence went to --out outside the repo" $?
  out="$repo/out"; run_runner "$repo" "$f" "$out"
  [ "$RC" = 3 ] && [ ! -e "$out" ]; check "control: --out inside the repo exits 3 and creates nothing (exit $RC)" $?
  end_browser
}

case_offsite_request_aborted() {
  echo "--- offsite-request-aborted"
  begin_browser offsite-request-aborted || return 0
  local f="$T/off.json" out count
  page_scenario "$f" /offsite.html "Offsite page" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/offsite.html"},{do:"expect_text",text:"offsite done"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 0 ] && [ "$(jget "$out/result.json" 'j.rows[0].status')" = PASS ]; }; check "the page settled ('offsite done' shown) and its row is PASS: a blocked request changes no status (exit $RC)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  [ "$count" = '{"hits":0,"upgrades":0}' ]; check "the second listener saw no plain hit and no WebSocket upgrade ($count)" $?
  [ "$(jget "$out/result.json" 'j.blocked_requests.filter(b=>b.host==="localhost").reduce((n,b)=>n+b.count,0)>=2')" = true ]; check "blocked_requests names localhost for both the HTTP request and the WebSocket" $?
  [ "$(jget "$out/result.json" 'j.browser.args.indexOf("--host-resolver-rules=MAP 127.0.0.1 127.0.0.1, MAP * ~NOTFOUND")>=0')" = true ]; check "the launch pins the allowed host to its checked address and sends every other name to ~NOTFOUND (--host-resolver-rules in the recorded args)" $?

  page_scenario "$f" /otherport.html "Other port page" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/otherport.html"},{do:"expect_text",text:"other port done"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 0 ] && [ "$(jget "$out/result.json" 'j.rows[0].status')" = PASS ]; }; check "the page that probes another port of the allowed name settled and its row is PASS (exit $RC)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  [ "$count" = '{"hits":0,"upgrades":0}' ]; check "the listener on another port of the SAME allowed name saw no GET, no JSON POST and no WebSocket ($count)" $?
  [ "$(jget "$out/result.json" "j.blocked_requests.some(b=>b.host==='127.0.0.1:$FIX_PORT2'&&b.count>=3)")" = true ]; check "blocked_requests names the allowed host with the refused port for the three probes" $?

  [ "$(jget "$out/result.json" 'j.blocked_requests_truncated')" = false ]; check "a short blocked list reports blocked_requests_truncated false" $?
  page_scenario "$f" /many.html "Many hosts page" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/many.html"},{do:"expect_text",text:"many done"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 0 ] && [ "$(jget "$out/result.json" 'j.rows[0].status')" = PASS ]; }; check "the page that requests 61 distinct hosts off the list settled (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.blocked_requests.length+"|"+j.blocked_requests_truncated')" = "50|true" ]; check "blocked_requests holds at most 50 entries and blocked_requests_truncated is true" $?
  [ "$(jget "$out/result.json" 'j.blocked_requests.every(b=>b.host.length<=100)&&j.blocked_requests.some(b=>b.host.length===100&&b.host.startsWith("aaaa"))')" = true ]; check "a 152 character host is cut to 100 characters" $?

  local redirect_js='s.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/redirect"},{do:"expect_text",text:"counted"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/redirect-ok"},{do:"expect_text",text:"Kit fixture app"}]}]'
  page_scenario "$f" / "Kit fixture app" "$redirect_js"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 2 ]; check "an allowed path that answers 302 to a host off the list exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason')" = "NO-CHECK|redirected off an allowed host" ]; check "the redirect row is NO-CHECK 'redirected off an allowed host'" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status')" = PASS ]; check "control: a 302 to an allowed path is followed and its row is PASS" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  [ "$count" = '{"hits":0,"upgrades":0}' ]; check "the second listener saw no hit through the redirect ($count)" $?
  [ "$(jget "$out/result.json" 'j.blocked_requests.some(b=>b.host==="localhost"&&b.count>=1)')" = true ]; check "blocked_requests names localhost for the redirect hop" $?
  page_scenario "$f" /offsite.html "Offsite page" 's.target.allow_hosts.push("localhost");s.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/offsite.html"},{do:"expect_text",text:"offsite done"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 0 ]; check "with localhost allowed on a non-default port the same page still settles (exit $RC)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  [ "$count" = '{"hits":0,"upgrades":0}' ]; check "an allowed name other than the target host may use only the scheme default port: the listener on its own port is still not reached ($count)" $?
  [ "$(jget "$out/result.json" 'j.browser.args.indexOf("--host-resolver-rules=MAP 127.0.0.1 127.0.0.1, MAP localhost 127.0.0.1, MAP * ~NOTFOUND")>=0')" = true ]; check "with localhost allowed the launch maps it to its checked address too" $?
  page_scenario "$f" /offsite.html "Offsite page" "s.target.allow_hosts.push('localhost');$redirect_js"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 2 ] && [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason')" = "NO-CHECK|redirected off an allowed host" ]; }; check "with localhost allowed the 302 hop is followed by the browser but the page URL is off the allowed set: NO-CHECK (exit $RC)" $?
  bscenario "$f" "/" "s.target.url='http://127.0.0.1:$FIX_PORT2/';s.ready.text='counted';s.scenarios=[{id:'AC-1',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'expect_text',text:'counted'}]}]"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  { [ "$RC" = 0 ] && [ "$(printf '%s' "$count" | node -e 'const c=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(c.hits>=1))')" = true ]; }; check "control: when the second listener is the target URL its port is the allowed port and it answers 'counted' ($count, exit $RC)" $?

  local leave_js='s.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/leave.html"},{do:"click",role:"link",name:"Leave"},{do:"expect_text",text:"never shown"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/redirect-port"},{do:"expect_text",text:"counted"}]},{id:"AC-3",kind:"criterion",steps:[{do:"goto",path:"/leave.html"},{do:"expect_text",text:"never shown"}]}]'
  page_scenario "$f" / "Kit fixture app" "$leave_js"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "a click that leaves the allowed hosts, a redirect to another port of the allowed name and a plain miss exit 1 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason+"|"+j.rows[0].observed')" = "NO-CHECK|redirected off an allowed host|" ]; check "a failing step after a click that left the allowed hosts is NO-CHECK 'redirected off an allowed host', never FAIL" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status+"|"+j.rows[1].reason')" = "NO-CHECK|redirected off an allowed host" ]; check "a 302 to another port of the allowed name is NO-CHECK even though the page there says 'counted'" $?
  [ "$(jget "$out/result.json" 'j.rows[2].status')" = FAIL ]; check "control: the same missing text on a page that never left is a plain FAIL" $?
  [ "$(jget "$out/result.json" "j.blocked_requests.some(b=>b.host==='127.0.0.1:$FIX_PORT2'&&b.count>=1)")" = true ]; check "blocked_requests names the allowed host with the other port for the top-level redirect hop" $?
  end_browser
}

# Two things the guards do not stop, recorded as they happen in the real browser.
#   worker WebSocket: a dedicated worker opens a WebSocket to another port of the allowed host. The WebSocket route
#     is an init script in the page, which a worker never runs, so the guard is not expected to see this socket. A
#     NOTE line is an observation, never a pass or a fail: a Playwright upgrade that closes the gap shows up as a
#     changed NOTE and a README edit, not as a red suite.
#   307 hop: the allowed target answers a POST with 307 to another port of the allowed host. The route handler is
#     not called for a redirect hop, so the method and the body arrive. The context-level request listener sees the
#     hop: the row is NO-CHECK, the hop target is counted, and the run cannot be PASS. The hop request itself is
#     still sent once. A hop that arrives after the last step is held too: the end of the scenario waits for the
#     requests the context already knows about, then checks again.
#   SharedWorker hop: a shared worker POSTs to a path answering 307 to the other port. Recorded as a NOTE.
# hop_detected <result.json> <port>: row 1 is NO-CHECK 'redirected off an allowed host', blocked_requests holds the
# hop target as host:port, and the verdict is not PASS.
hop_detected() {
  jget "$1" "j.rows[0].status==='NO-CHECK'&&j.rows[0].reason==='redirected off an allowed host'&&j.blocked_requests.some(b=>b.host==='127.0.0.1:$2'&&b.count>=1)&&j.verdict!=='PASS'"
}

case_observed_residuals() {
  echo "--- observed-residuals"
  begin_browser observed-residuals || return 0
  local f="$T/obs.json" out count seen before variant
  local hop_js='s.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/post-hop.html"},{do:"expect_text",text:"hop done"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"Kit fixture app"}]}]'
  page_scenario "$f" /worker.html "worker done" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/worker.html"},{do:"expect_text",text:"worker done"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 0 ] && [ "$(jget "$out/result.json" 'j.rows[0].status')" = PASS ]; }; check "the page whose worker opens a WebSocket to another port of the allowed host settled and its row is PASS (exit $RC)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  printf '  NOTE  worker WebSocket to the other port: listener answered %s; blocked_requests %s\n' "$count" "$(jget "$out/result.json" 'JSON.stringify(j.blocked_requests)')"

  page_scenario "$f" / "Kit fixture app" "$hop_js"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 2 ]; check "a page that POSTs to a path answering 307 to another port of the allowed host exits 2 (exit $RC)" $?
  [ "$(hop_detected "$out/result.json" "$FIX_PORT2")" = true ]; check "its row is NO-CHECK 'redirected off an allowed host', blocked_requests holds 127.0.0.1:<port> and the verdict is not PASS" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status')" = PASS ]; check "control: the next scenario, in its own context, is still PASS (the hop is held to the scenario that saw it)" $?
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count"); seen=$(curl -s "http://127.0.0.1:$FIX_PORT2/seen")
  printf '  NOTE  307 hop to the other port: listener answered %s and saw %s; blocked_requests %s\n' "$count" "$seen" "$(jget "$out/result.json" 'JSON.stringify(j.blocked_requests)')"
  if variant=$(runner_variant nohop 'request.redirectedFrom() !== null && !isAllowedUrl(guard, request.url())' 'false'); then
    out=$(next_out); RUN_RUNNER="$variant" run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
    { [ "$(jget "$out/result.json" 'j.rows[0].status')" = PASS ] && [ "$(hop_detected "$out/result.json" "$FIX_PORT2")" = false ]; }; check "control: a runner copy without the hop listener reports the hop row as PASS (exit $RC)" $?
    RUN_RUNNER=""
  else no "control: the hop listener is no longer in the runner"; fi

  page_scenario "$f" / "Kit fixture app" "$hop_js"
  mutate "$f" "$f" 's.scenarios.push({id:"AC-3",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"never on this page"}]})'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 1 ] && [ "$(jget "$out/result.json" 'j.verdict')" = FAIL ] && [ "$(hop_detected "$out/result.json" "$FIX_PORT2")" = true ]; }; check "with a FAIL row beside the hop row the exit is 1 and the verdict FAIL, the hop row staying NO-CHECK (exit $RC)" $?

  local late_js='s.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/late-hop.html"},{do:"expect_text",text:"late page"},{do:"screenshot",name:"late"}]}]'
  page_scenario "$f" / "Kit fixture app" "$late_js"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 2 ] && [ "$(hop_detected "$out/result.json" "$FIX_PORT2")" = true ]; }; check "a hop that arrives after the last asserting step (steps expect_text, screenshot; the 307 answer is delayed 800 ms) still ends the row NO-CHECK 'redirected off an allowed host' (exit $RC)" $?
  if variant=$(runner_variant nofinal $'    if (hasEscaped(opened, guard)) return escapedRow();\n    return { status: \'PASS\'' "    return { status: 'PASS'"); then
    out=$(next_out); RUN_RUNNER="$variant" run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
    [ "$(jget "$out/result.json" 'j.rows[0].status')" = PASS ]; check "control: a runner copy without the final check ends the same scenario PASS (exit $RC)" $?
    RUN_RUNNER=""
  else no "control: the final check is no longer in the runner"; fi

  before=$(curl -s "http://127.0.0.1:$FIX_PORT2/seen")
  page_scenario "$f" / "Kit fixture app" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/shared-worker.html"},{do:"expect_text",text:"shared worker done"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  seen=$(curl -s "http://127.0.0.1:$FIX_PORT2/seen")
  printf '  NOTE  SharedWorker POST to a 307 to the other port: row %s, exit %s, listener requests before %s and after %s; blocked_requests %s\n' "$(jget "$out/result.json" 'j.rows[0].status')" "$RC" "$before" "$seen" "$(jget "$out/result.json" 'JSON.stringify(j.blocked_requests)')"
  end_browser
}

HANG_JS='s.scenarios=[1,2,3].map(function(i){return {id:"AC-"+i,kind:"criterion",steps:[{do:"goto",path:"/hang"},{do:"expect_text",text:"x"}]}}).concat([{id:"AC-4",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"Kit fixture app"}]}])'

case_hang_bounded() {
  echo "--- hang-bounded"
  begin_browser hang-bounded || return 0
  local f="$T/hang.json" out id
  bscenario "$f" "/" "$HANG_JS"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 2000 --scenario-timeout-ms 5000 --run-budget-ms 5000
  id=$RUN_ID
  [ "$RC" = 2 ]; check "three hanging scenarios and a normal one exit 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason')" = "NO-CHECK|page did not settle" ]; check "the first row is NO-CHECK 'page did not settle'" $?
  [ "$(jget "$out/result.json" 'j.rows[3].status+"|"+j.rows[3].reason')" = "NO-CHECK|run budget spent" ]; check "the last row is NO-CHECK 'run budget spent'" $?
  [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"')" = true ]; check "no row is FAIL or PASS" $?
  [ "$(jget "$out/result.json" 'j.browser.pids.length>0')" = true ]; check "browser.pids is not empty: the run-id marker finds the browser" $?
  [ "$(jget "$out/result.json" 'j.browser.leftover_pids.length')" = 0 ]; check "browser.leftover_pids is empty" $?
  wait_no_browser "$id"; check "no process carries run id $id after the runner exits (ceiling ${PGREP_CEILING_S}s fails the case)" $?
  [ "$(jget "$out/result.json" "j.duration_ms>0&&j.duration_ms<$((RUN_TIMEOUT_S*1000))")" = true ]; check "duration_ms is recorded and inside the outer ceiling (the budget rows above prove the bound, not the wall clock)" $?

  bscenario "$f" "/" 's.scenarios=[s.scenarios[0],s.scenarios[2],s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 0 ] && [ "$(rows_all "$out/result.json" 'r.status==="PASS"')" = true ]; }; check "control: the same file without the /hang scenarios and with default timeouts exits 0, every row PASS (exit $RC)" $?
  wait_no_browser "$RUN_ID"; check "control: the browser of the clean run is gone too" $?

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/hang"},{do:"expect_text",text:"x"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS" --scenario-timeout-ms 1000
  [ "$RC" = 2 ]; check "a hang with a scenario timeout below the step timeout exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason')" = "NO-CHECK|scenario timeout" ]; check "the scenario clock caps a step in flight: the row is NO-CHECK 'scenario timeout'" $?
  wait_no_browser "$RUN_ID"; check "no browser is left after the scenario timeout run" $?
  end_browser
}

# identity_case <label> <build sha, or empty for no header> <identity status> <exit> <seen> [scenario js]
identity_case() {
  local label=$1 sha=$2 want=$3 want_rc=$4 want_seen=$5 f="$T/id.json" out got
  stop_fixture
  if [ -n "$sha" ]; then start_fixture --build-sha "$sha"; else start_fixture; fi || { no "$label: the fixture started"; return 0; }
  page_scenario "$f" / "Kit fixture app" "s.identity={header:'x-build-sha'};s.scenarios=[s.scenarios[3]];${6:-}"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  got=$(jget "$out/result.json" 'j.identity.status+"|"+j.identity.seen+"|"+j.rows[0].status+"|"+j.rows[0].reason' 2>/dev/null)
  local want_row="PASS|"
  if [ "$want" = mismatch ]; then want_row="NO-CHECK|preview is not the head"; fi
  if [ "$RC" = "$want_rc" ] && [ "$got" = "$want|$want_seen|$want_row" ] && grep -q "preview-identity $want " "$T/stdout"; then ok "$label -> $want"
  else no "$label -> $want (exit $RC, got: $got)"; fi
}

case_identity_and_readiness() {
  echo "--- identity-and-readiness"
  begin_browser identity-and-readiness || return 0
  local f="$T/idr.json" out
  identity_case "header holds the first 12 hex of head_sha" 0123456789ab matched 0 0123456789ab
  identity_case "the same in upper case" 0123456789AB matched 0 0123456789ab
  identity_case "a different 40-hex value" ffffffffffffffffffffffffffffffffffffffff mismatch 2 ffffffffffff
  identity_case "a UUID" 123e4567-e89b-12d3-a456-426614174000 unverified 0 123e4567-e89
  identity_case "a semver" 1.2.3 unverified 0 1.2.3
  identity_case "6 hex that are a prefix of head_sha" 012345 unverified 0 012345
  identity_case "7 hex that are a prefix of head_sha" 0123456 matched 0 0123456
  identity_case "7 hex that are not a prefix" 0123457 mismatch 2 0123457
  identity_case "40 hex equal to head_sha" "$HEAD40" matched 0 0123456789ab
  identity_case "41 hex" "${HEAD40}0" unverified 0 0123456789ab
  identity_case "a configured header that the page does not send" "" unverified 0 ""
  identity_case "no identity key in the scenario, a mismatching header on the page" ffffffffffffffffffffffffffffffffffffffff unverified 0 "" 'delete s.identity'

  stop_fixture; start_fixture
  page_scenario "$f" /meta.html "Meta page" "s.identity={meta:'build'};s.scenarios=[{id:'AC-1',kind:'criterion',steps:[{do:'goto',path:'/meta.html'},{do:'expect_text',text:'Meta page'}]}]"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$(jget "$out/result.json" 'j.identity.status+"|"+j.identity.seen')" = "unverified|ab/cd'ef" ]; check "identity.seen from a meta tag carries no pipe or backtick (exit $RC)" $?
  page_scenario "$f" /wall.html "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 2 ]; check "the login wall (200, no ready text) exits 2 (exit $RC)" $?
  [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="preview not ready"')" = true ]; check "every row is NO-CHECK 'preview not ready', never FAIL" $?
  page_scenario "$f" /nope.html "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="preview unreachable"')" = true ]; }; check "a target URL that answers 404: every row NO-CHECK 'preview unreachable', exit 2 (exit $RC)" $?
  # .invalid is reserved by RFC 6761 and never resolves. The residual is a resolver that answers for unresolvable
  # names: the case then goes red (the row is not 'preview unreachable') instead of reaching a real host.
  page_scenario "$f" / "Kit fixture app" "s.target.url='https://nonexistent.invalid/';s.target.allow_hosts=['nonexistent.invalid'];s.target.allow_loopback=false;s.scenarios=[s.scenarios[3]]"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="preview unreachable"')" = true ]; }; check "an allowed host under .invalid that does not resolve: NO-CHECK 'preview unreachable', result.json written, exit 2 (exit $RC)" $?
  page_scenario "$f" /redirect "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="redirected off an allowed host"')" = true ]; }; check "a target URL that answers 302 to a host off the list: every row NO-CHECK 'redirected off an allowed host' (exit $RC)" $?
  [ "$(curl -s "http://127.0.0.1:$FIX_PORT2/count")" = '{"hits":0,"upgrades":0}' ]; check "the second listener saw nothing of that redirect" $?
  page_scenario "$f" /redirect-port "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  { [ "$RC" = 2 ] && [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="redirected off an allowed host"')" = true ]; }; check "a target URL that answers 302 to another port of the allowed name: every row NO-CHECK 'redirected off an allowed host' (exit $RC)" $?
  [ "$(curl -s "http://127.0.0.1:$FIX_PORT2/count")" = '{"hits":1,"upgrades":0}' ]; check "that redirect is final: the preflight is not retried, so the listener saw its one hop" $?
  page_scenario "$f" / "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 0 ]; check "control: index.html with its real ready text passes (exit $RC)" $?
  end_browser
}

case_browser_sandbox() {
  echo "--- browser-sandbox"
  begin_browser browser-sandbox || return 0
  local f="$T/sb.json" out stub="$T/stub-bin"
  bscenario "$f" "/"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  [ "$RC" = 0 ]; check "a normal run exits 0 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'var b=j.browser;[b.sandbox,b.no_sandbox_seen,b.launch_attempts,b.args.some(a=>a.indexOf("--no-sandbox")>=0),b.args.indexOf("--kit-ui-verify="+j.run_id)>=0,b.pids.length>0].join(",")')" = "true,false,1,false,true,true" ]; check "browser: sandbox true, no_sandbox_seen false, 1 launch attempt, no --no-sandbox, the run-id marker in args, pids found" $?
  wait_no_browser "$RUN_ID"; check "the browser of the normal run is gone" $?
  [ "$(jget "$out/result.json" 'j.browser.env_keys.join(",")+"|"+j.browser.args.includes("--no-proxy-server")')" = "HOME,PATH|true" ]; check "the browser started with the sandbox on, --no-proxy-server and only HOME and PATH in its environment" $?

  out=$(next_out); UI_VERIFY_TEST_FAULT=sandbox-unavailable run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "UI_VERIFY_TEST_FAULT=sandbox-unavailable exits 2 (exit $RC)" $?
  [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="browser sandbox unavailable"')" = true ]; check "every row is NO-CHECK 'browser sandbox unavailable'" $?
  [ "$(jget "$out/result.json" 'j.browser.launch_attempts+"|"+j.browser.sandbox+"|"+j.browser.pids.length')" = "1|false|0" ]; check "launch_attempts is 1 (no unsandboxed retry), no sandbox, no pids" $?
  [ -n "$RUN_ID" ] && [ -z "$(pgrep -f -- "--kit-ui-verify=$RUN_ID" 2>/dev/null)" ]; check "no process carries the run id of the faulted run" $?

  mkdir -p "$stub"; printf '#!/bin/sh\nexit 0\n' > "$stub/ps"; chmod +x "$stub/ps"
  out=$(next_out); PATH="$stub:$PATH" run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "a scan that finds no process carrying the run id (a ps stub that lists nothing) exits 2 (exit $RC)" $?
  [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="browser sandbox unavailable"')" = true ]; check "unverified sandbox: every row is NO-CHECK 'browser sandbox unavailable'" $?
  [ "$(jget "$out/result.json" 'j.browser.pids.length+"|"+j.browser.sandbox+"|"+j.browser.launch_attempts')" = "0|false|1" ]; check "unverified sandbox: browser.pids is empty and the sandbox is not reported as on" $?
  wait_no_browser "$RUN_ID"; check "the runner still closed that browser (real pgrep finds nothing after the poll)" $?

  local real_ps; real_ps=$(command -v ps); mkdir -p "$T/nosb-bin"
  printf '#!/bin/sh\n"%s" "$@" | sed "s/--kit-ui-verify=/--no-sandbox --kit-ui-verify=/"\n' "$real_ps" > "$T/nosb-bin/ps"; chmod +x "$T/nosb-bin/ps"
  out=$(next_out); PATH="$T/nosb-bin:$PATH" run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "a browser whose command line carries --no-sandbox (a ps wrapper adds it) exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'var b=j.browser;[b.no_sandbox_seen,b.sandbox,b.pids.length>0].join(",")')" = "true,false,true" ]; check "no_sandbox_seen is true, sandbox is false, and the pids were found" $?
  [ "$(rows_all "$out/result.json" 'r.status==="NO-CHECK"&&r.reason==="browser sandbox unavailable"')" = true ]; check "every row is NO-CHECK 'browser sandbox unavailable' when --no-sandbox was seen" $?
  wait_no_browser "$RUN_ID"; check "the runner closed that browser too" $?
  end_browser
}

case_leftover_browser_killed() {
  echo "--- leftover-browser-killed"
  begin_browser leftover-browser-killed || return 0
  local f="$T/lbk.json" out stub="$T/decoy-bin" real_ps pid_file="$T/decoy.pid" bare_file="$T/decoy-bare.pid" pid bare i=0
  real_ps=$(command -v ps)
  mkdir -p "$stub"
  cat > "$stub/ps" <<STUB
#!/bin/bash
if [ ! -e "$pid_file" ]; then
  id=\$("$real_ps" -axww -o command= | sed -n 's/.*--kit-ui-verify=\([0-9a-f]*\).*/\1/p' | head -n 1)
  if [ -n "\$id" ]; then
    ( exec -a "ui-verify-decoy --kit-ui-verify=\$id $RUN_HOME/browsers/decoy" sleep 300 ) >/dev/null 2>&1 &
    echo \$! > "$pid_file"
    ( exec -a "ui-verify-bystander --kit-ui-verify=\$id" sleep 300 ) >/dev/null 2>&1 &
    echo \$! > "$bare_file"
    sleep 0.5
  fi
fi
exec "$real_ps" "\$@"
STUB
  chmod +x "$stub/ps"
  bscenario "$f" "/"
  out=$(next_out); PATH="$stub:$PATH" run_runner "$CWD" "$f" "$out"
  pid=$(cat "$pid_file" 2>/dev/null); bare=$(cat "$bare_file" 2>/dev/null)
  [ "$RC" = 0 ]; check "a run that leaves a process carrying its run id behind still exits 0 (exit $RC)" $?
  [ -n "$pid" ] && [ "$(jget "$out/result.json" "j.browser.pids.includes($pid)")" = true ]; check "the scan recorded the stray process (pid ${pid:-none}) among the run's pids" $?
  while [ "$i" -lt 20 ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; do sleep 0.5; i=$((i+1)); done
  { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; }; check "the runner killed the stray process that carried its run id and a path under the browser directory" $?
  [ "$(jget "$out/result.json" 'j.browser.leftover_pids.length')" = 0 ]; check "browser.leftover_pids is empty after the kill" $?
  { [ -n "$bare" ] && kill -0 "$bare" 2>/dev/null; }; check "a bystander whose command line holds only the run id (no browser path) is still alive after the run (pid ${bare:-none})" $?
  [ -n "$bare" ] && [ "$(jget "$out/result.json" "!j.browser.pids.includes($bare)")" = true ]; check "the bystander is not among the run's recorded pids" $?
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; fi
  if [ -n "$bare" ]; then kill "$bare" 2>/dev/null; fi
  wait_no_browser "$RUN_ID"; check "no process carries the run id at the end" $?
  end_browser
}

case_sigterm_closes_browser() {
  echo "--- sigterm-closes-browser"
  begin_browser sigterm-closes-browser || return 0
  local f="$T/sig.json" out id="" rc pid i=0
  bscenario "$f" "/" "$HANG_JS"
  out=$(next_out)
  ( cd "$CWD" && UI_VERIFY_HOME="$RUN_HOME" exec node "$RUNNER" scenario --scenario "$f" --out "$out" ) >"$T/sig.out" 2>"$T/sig.err" &
  pid=$!
  while [ "$i" -lt 120 ]; do
    id=$(awk '/^ui-verify: run /{print $3; exit}' "$T/sig.err")
    if [ -n "$id" ] && pgrep -f -- "--kit-ui-verify=$id" >/dev/null 2>&1; then break; fi
    sleep 0.5; i=$((i+1))
  done
  [ -n "$id" ]; check "the run id is printed on stderr before the browser work starts (${id:-none})" $?
  ALL_RUN_IDS="$ALL_RUN_IDS $id"
  kill -TERM "$pid" 2>/dev/null
  i=0; while [ "$i" -lt 120 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.5; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null; fi
  { wait "$pid"; } 2>/dev/null; rc=$?
  [ "$rc" = 143 ]; check "SIGTERM ends the runner with exit 143 (exit $rc)" $?
  [ -n "$id" ] && ! pgrep -f -- "--kit-ui-verify=$id" >/dev/null 2>&1; check "no process carries the run id the moment the runner has exited" $?
  grep -q '^ui-verify: interrupted, browser closed' "$T/sig.err"; check "the runner reports that it closed the browser before it exited" $?
  end_browser
}

# Steps and folds that the other browser cases do not reach: a typed value, a disabled and an ambiguous target, a url
# mismatch, the retry path, and the three default viewports folded to the worst one.
case_step_behaviors() {
  echo "--- step-behaviors"
  begin_browser step-behaviors || return 0
  local f="$T/stb.json" out
  bscenario "$f" "/" "s.scenarios=[{id:'AC-1',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'fill',role:'textbox',name:'Display name',value:'Ada'},{do:'click',role:'button',name:'Save'},{do:'expect_text',text:'Saved Ada'}]},{id:'AC-2',kind:'criterion',steps:[{do:'goto',path:'/?link=expired'},{do:'click',role:'button',name:'Save'},{do:'expect_text',text:'x'}]},{id:'AC-3',kind:'criterion',steps:[{do:'goto',path:'/?twin=1'},{do:'click',role:'button',name:'Save'},{do:'expect_text',text:'x'}]},{id:'AC-4',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'expect_url',path:'/x'}]},{id:'AC-5',kind:'criterion',steps:[{do:'goto',path:'/flaky?key=a'},{do:'expect_text',text:'Saved'}]}]"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "a typed value, a disabled button, two same-named buttons, a url mismatch and a flaky page exit 1 (exit $RC)" $?
  [ "$(row_line "$out/result.json")" = "AC-1=PASS/false,AC-2=FAIL/false,AC-3=FAIL/false,AC-4=FAIL/false,AC-5=PASS/true" ]; check "AC-1 passes, AC-2 to AC-4 FAIL without a flaky mark, AC-5 passes flaky" $?
  [ "$(jget "$out/result.json" 'j.rows[1].observed')" = "element not actionable: role=button name=Save" ]; check "a disabled button is a FAIL whose observed is 'element not actionable: role=button name=Save'" $?
  [ "$(jget "$out/result.json" 'j.rows[2].observed')" = "ambiguous: 2 matches" ]; check "two buttons named Save: observed is 'ambiguous: 2 matches'" $?
  [ "$(jget "$out/result.json" 'j.rows[3].observed')" = "url is /" ]; check "expect_url on another path: observed is 'url is /'" $?
  [ "$(jget "$out/result.json" 'j.rows[4].status+"|"+j.rows[4].flaky+"|"+j.rows[4].observed.length')" = "PASS|true|0" ]; check "a row that failed once and passed on the retry is PASS with flaky true and no observed" $?
  grep -qFx "row AC-5 | PASS |  |" "$T/stdout"; check "the flaky row prints as a PASS row on stdout" $?

  bscenario "$f" "/" "delete s.viewports;s.scenarios=[{id:'AC-1',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'expect_text',text:'wide layout'}]},{id:'AC-2',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'expect_text',text:'narrow layout'}]},{id:'AC-3',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'expect_text',text:'Kit fixture app'}]}]"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms "$STEP_MS"
  [ "$RC" = 1 ]; check "a scenario file with no viewports runs the default three and exits 1 when one of them fails (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.viewports.join(",")')" = "390,768,1280" ]; check "the default viewports are 390, 768 and 1280" $?
  [ "$(jget "$out/result.json" 'j.rows.map(r=>r.status+":"+r.viewports.map(v=>v.width+v.status[0]).join("/")).join(",")')" = "FAIL:390F/768P/1280P,FAIL:390P/768F/1280F,PASS:390P/768P/1280P" ]; check "each row keeps one status per width and the row takes the worst: FAIL when the first width fails, FAIL when the last two fail, PASS when all pass" $?
  [ "$(jget "$out/result.json" 'j.rows.map(r=>r.evidence.length).join(",")')" = "0,0,0" ]; check "control: no screenshot step, no evidence" $?
  end_browser
}

# A name that is not a case, or a listed case with no function, fails the suite instead of running nothing.
ALL_CASES="$CASES $BROWSER_CASES"
for c in "$@"; do
  case " $ALL_CASES " in *" $c "*) ;; *) no "unknown case name: $c" ;; esac
done
for c in $ALL_CASES; do
  fn="case_${c//-/_}"
  if ! declare -F "$fn" >/dev/null; then no "case $c is listed and has no function $fn"; continue; fi
  selected "$c" || continue
  "$fn"
done

echo "test-ui-acceptance-verifier: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
