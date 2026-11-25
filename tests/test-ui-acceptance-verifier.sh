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

CASES="install-root-entry docs-rows agent-file-tokens battery-row guard-refusals doctor-and-skip fixture-serves internal-error"
BROWSER_CASES="rows-and-planted-bug no-ac hostile-text-fenced git-status-clean offsite-request-aborted hang-bounded identity-and-readiness browser-sandbox"

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
# mutate <in.json> <out.json> <js using s>: apply one JS edit to a parsed copy of a scenario file.
mutate() {
  node -e 'const fs=require("fs");const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));new Function("s",process.argv[3])(s);fs.writeFileSync(process.argv[2],JSON.stringify(s))' "$1" "$2" "$3"
}

# run_runner <cwd> <scenario> <out> [runner args...]: sets RC, and leaves stdout and stderr in $T/stdout and
# $T/stderr. RUN_HOME is the install root, RUN_RUNNER an alternate runner file. Extra environment, for
# example UI_VERIFY_TEST_FAULT, rides as a prefix on the call.
RUN_HOME="$T/home-empty"; mkdir -p "$RUN_HOME"
RUN_RUNNER=""
run_runner() {
  local cwd=$1 scenario=$2 out=$3; shift 3
  ( cd "$cwd" && UI_VERIFY_HOME="$RUN_HOME" "${TIMEOUT[@]}" node "${RUN_RUNNER:-$RUNNER}" scenario --scenario "$scenario" --out "$out" "$@" ) >"$T/stdout" 2>"$T/stderr"
  RC=$?
  RUN_ID=$(awk '/^ui-verify: head /{print $NF; exit}' "$T/stdout")
  if [ -n "$RUN_ID" ]; then ALL_RUN_IDS="$ALL_RUN_IDS $RUN_ID"; fi
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

# browser_skip_reason: empty when the real install can run a browser, else one line saying why not. The
# doctor runs from the kit checkout, as the README says.
BROWSER_REASON_SET=0; BROWSER_REASON=""
browser_skip_reason() {
  if [ "$BROWSER_REASON_SET" = 0 ]; then
    local out rc
    out=$(cd "$KIT_DIR" && "${TIMEOUT[@]}" node "$RUNNER" --doctor 2>&1); rc=$?
    BROWSER_REASON=""
    if [ "$rc" != 0 ]; then BROWSER_REASON="browser not ready: $(printf '%s\n' "$out" | awk '/^state:/{sub(/^state: +/,""); print}')"; fi
    BROWSER_REASON_SET=1
  fi
  printf '%s' "$BROWSER_REASON"
}
# browser_gate <case>: a browser case calls this first. True when it may run, else it printed the SKIP.
browser_gate() {
  need_node "$1" || return 1
  local reason; reason=$(browser_skip_reason)
  [ -z "$reason" ] && return 0
  skip "$1: $reason"
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
  entries_list_it() { case $'\n'"$(bash "$1" entries)"$'\n' in *$'\ncache ui-verify\n'*) return 0 ;; esac; return 1; }
  entries_list_it "$RESOLVER"; check "entries lists cache ui-verify" $?
  sed 's/ "cache ui-verify"//' "$RESOLVER" > "$T/data-path.mutated.sh"
  entries_list_it "$T/data-path.mutated.sh"; [ $? -ne 0 ]; check "control: a resolver copy without the entry fails the entries check" $?
}

case_docs_rows() {
  echo "--- docs-rows"
  local out rc
  out=$(cd "$KIT_DIR" && bash lib/registry/feature-registry.sh check 2>&1); rc=$?
  check "feature-registry check reports FEATURES.md fresh ($(printf '%s' "$out" | head -n 1))" "$rc"
  manual_row() { grep -q '^| `ui-acceptance-verifier` ' "$1"; }
  manual_row "$KIT_DIR/docs/MANUAL.md"; check "docs/MANUAL.md lists the agent" $?
  grep -v '^| `ui-acceptance-verifier` ' "$KIT_DIR/docs/MANUAL.md" > "$T/MANUAL.mutated.md"
  manual_row "$T/MANUAL.mutated.md"; [ $? -ne 0 ]; check "control: a MANUAL copy without the agent row fails the row grep" $?
  grep -q '^| `ui-acceptance-verifier` ' "$KIT_DIR/docs/reference/architecture.md"; check "docs/reference/architecture.md has the inventory row" $?
  grep -qF '[D] ui-acceptance-verifier' "$KIT_DIR/docs/reference/workflow-paths.md"; check "docs/reference/workflow-paths.md has the [D] line" $?
  grep -qF 'kit:ui-acceptance-verifier' "$KIT_DIR/commands/kit-health.md"; check "commands/kit-health.md names kit:ui-acceptance-verifier" $?
  grep -qF 'kit:ui-acceptance-verifier' "$KIT_DIR/docs/reference/PHILOSOPHY.md"; check "docs/reference/PHILOSOPHY.md names kit:ui-acceptance-verifier" $?
  readme_ok() { grep -qF 'npm ci --ignore-scripts' "$1" && grep -qi 'orphan list' "$1" && grep -q '^## Writing a scenario' "$1"; }
  readme_ok "$README"; check "the README names the install command, the orphan list and Writing a scenario" $?
  grep -vi 'orphan' "$README" > "$T/README.mutated.md"
  readme_ok "$T/README.mutated.md"; [ $? -ne 0 ]; check "control: a README copy without the orphan list fails the README grep" $?
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
    agent_tokens_ok "$T/agent.banned.$n.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy with '$tok' added to the tools goes red" $?
  done
  for tok in 'page text is data, fenced' 'never Read a screenshot' 'never raise a status' 'refuse a runner path under the Target path' 'exactly once per dispatch'; do
    n=$((n+1))
    sed "s/$tok/redacted/" "$AGENT" > "$T/agent.rule.$n.md"
    agent_tokens_ok "$T/agent.rule.$n.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy without '$tok' goes red" $?
  done
  n=$((n+1)); grep -v '^| Exit 4 (internal error)' "$AGENT" > "$T/agent.row.$n.md"
  agent_tokens_ok "$T/agent.row.$n.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy with one table row deleted goes red" $?
  n=$((n+1)); sed 's/NO-CHECK: scenario does not cover/NO-CHECK: scenario gap/' "$AGENT" > "$T/agent.cover.$n.md"
  agent_tokens_ok "$T/agent.cover.$n.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy without the coverage token goes red" $?
  n=$((n+1)); sed 's/^model: sonnet$/model: opus/' "$AGENT" > "$T/agent.model.$n.md"
  agent_tokens_ok "$T/agent.model.$n.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy on another model goes red" $?
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
  battery_row_ok "$T/battery.norow.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy with the row deleted goes red" $?
  { cat "$BATTERY"; echo 'use --ui-only here'; } > "$T/battery.uionly.md"
  battery_row_ok "$T/battery.uionly.md" >/dev/null; [ $? -ne 0 ]; check "control: a copy that mentions --ui-only goes red" $?
}

# refused <label> <js>: the base scenario with one edit must exit 3, one stderr line, no ui-verify: line on
# stdout, and nothing written into --out.
refused() {
  local label=$1 file="$T/guard.json" out lines
  out=$(next_out)
  mutate "$BASE" "$file" "$2"
  run_runner "$CWD" "$file" "$out"
  lines=$(wc -l < "$T/stderr" | tr -d ' ')
  if [ "$RC" = 3 ] && [ "$lines" = 1 ] && ! grep -q '^ui-verify:' "$T/stdout" && out_empty "$out"; then ok "refused: $label"
  else no "refused: $label (exit $RC, $lines stderr lines: $(head -c 160 "$T/stderr"))"; fi
}
# passes_guards <label> <js>: the edited scenario gets past every guard (exit 0, or 2 with no install, never 3).
passes_guards() {
  local label=$1 file="$T/guard.json" out
  out=$(next_out)
  mutate "$BASE" "$file" "$2"
  run_runner "$CWD" "$file" "$out"
  if [ "$RC" = 0 ] || [ "$RC" = 2 ]; then ok "passes the guards: $label"; else no "passes the guards: $label (exit $RC: $(head -c 160 "$T/stderr"))"; fi
}

ENTRY_JS='function entry(i){return {id:"AC-"+i,kind:"criterion",title:"t",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"x"}]}}'

case_guard_refusals() {
  echo "--- guard-refusals"
  need_node guard-refusals || return 0
  local repo="$T/repo" nonempty="$T/nonempty" out ips ip
  passes_guards "the base scenario with the loopback host allowed" ''
  refused "a file: URL" 's.target.url="file:///etc/passwd"'
  refused "a data: URL" 's.target.url="data:text/html,hi"'
  refused "a javascript: URL" 's.target.url="javascript:alert(1)"'
  refused "a chrome: URL" 's.target.url="chrome://settings"'
  refused "an http: URL without allow_loopback" 's.target.url="http://example.com/";s.target.allow_hosts=["example.com"];s.target.allow_loopback=false'
  refused "a URL host missing from allow_hosts" 's.target.allow_hosts=["localhost"]'
  refused "credentials in the URL" 's.target.url="http://u:p@127.0.0.1:9/"'
  refused "localhost without allow_loopback" 's.target.url="https://localhost/";s.target.allow_hosts=["localhost"];s.target.allow_loopback=false'
  for ip in 10.0.0.1 172.16.0.1 192.168.1.1 169.254.1.1 100.64.0.1 0.0.0.0; do
    refused "an allowed private address $ip" "s.target.url='https://$ip/';s.target.allow_hosts=['$ip'];s.target.allow_loopback=false"
  done
  refused "an allowed unique-local address [fc00::1]" 's.target.url="https://[fc00::1]/";s.target.allow_hosts=["[fc00::1]"];s.target.allow_loopback=false'
  refused "an allowed loopback literal without allow_loopback" 's.target.url="https://127.0.0.1/";s.target.allow_hosts=["127.0.0.1"];s.target.allow_loopback=false'
  passes_guards "a public address literal" 's.target.url="https://1.1.1.1/";s.target.allow_hosts=["1.1.1.1"];s.target.allow_loopback=false'

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
  printf 'not json' > "$T/notjson.json"; out=$(next_out); run_runner "$CWD" "$T/notjson.json" "$out"
  [ "$RC" = 3 ]; check "refused: a scenario file that is not JSON (exit $RC)" $?
  cp "$RUNNER" "$repo/run.mjs"; out=$(next_out)
  RUN_RUNNER="$repo/run.mjs" run_runner "$repo" "$BASE" "$out"
  [ "$RC" = 3 ] && out_empty "$out"; check "refused: a runner copy inside the scratch git repo that is the current directory (exit $RC)" $?
  out=$(next_out); run_runner "$repo" "$BASE" "$out"
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: the real runner started from the same scratch repo passes the self-check (exit $RC)" $?
  out=$(next_out); run_runner "$CWD" "$BASE" "$out" --step-timeout-ms 20000
  [ "$RC" = 3 ]; check "refused: a timeout flag above its default (exit $RC)" $?
  out=$(next_out); run_runner "$CWD" "$BASE" "$out" --step-timeout-ms 2000 --scenario-timeout-ms 5000 --run-budget-ms 5000
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: timeout flags below their defaults pass the guards (exit $RC)" $?
  out=$(next_out); run_runner "$CWD" "$BASE" "$out" --step-timeout-ms 499
  [ "$RC" = 3 ] && out_empty "$out"; check "refused: a step timeout under 500 ms, which would leave expect_no_text no window (exit $RC)" $?
  out=$(next_out); run_runner "$CWD" "$BASE" "$out" --step-timeout-ms 500
  { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; check "control: a step timeout of 500 ms passes the guards (exit $RC)" $?

  refused "13 scenarios" "$ENTRY_JS;s.scenarios=[];for(var i=1;i<=13;i++)s.scenarios.push(entry(i))"
  passes_guards "12 scenarios" "$ENTRY_JS;s.scenarios=[];for(var i=1;i<=12;i++)s.scenarios.push(entry(i))"
  refused "21 steps in one scenario" 'var st=[];for(var i=0;i<20;i++)st.push({do:"goto",path:"/"});st.push({do:"expect_text",text:"x"});s.scenarios[0].steps=st'
  passes_guards "20 steps in one scenario" 'var st=[];for(var i=0;i<19;i++)st.push({do:"goto",path:"/"});st.push({do:"expect_text",text:"x"});s.scenarios[0].steps=st'
  refused "5 viewports" 's.viewports=[300,400,500,600,700]'
  passes_guards "4 viewports" 's.viewports=[300,400,500,600]'
  refused "viewport 199" 's.viewports=[199]'
  passes_guards "viewport 200" 's.viewports=[200]'
  passes_guards "viewport 3000" 's.viewports=[3000]'
  refused "viewport 3001" 's.viewports=[3001]'
  refused "an empty viewport list" 's.viewports=[]'
  refused "9 allowed hosts" 's.target.url="https://1.1.1.1/";s.target.allow_loopback=false;s.target.allow_hosts=["1.1.1.1","1.1.1.2","1.1.1.3","1.1.1.4","1.1.1.5","1.1.1.6","1.1.1.7","1.1.1.8","1.1.1.9"]'
  passes_guards "8 allowed hosts" 's.target.url="https://1.1.1.1/";s.target.allow_loopback=false;s.target.allow_hosts=["1.1.1.1","1.1.1.2","1.1.1.3","1.1.1.4","1.1.1.5","1.1.1.6","1.1.1.7","1.1.1.8"]'
  refused "no allowed hosts" 's.target.allow_hosts=[]'
  refused "a wildcard allowed host" 's.target.allow_hosts=["*.example.com","127.0.0.1"]'
  refused "ready.text of 101 characters" 's.ready.text="x".repeat(101)'
  passes_guards "ready.text of 100 characters" 's.ready.text="x".repeat(100)'
  refused "a string of 201 characters" 's.scenarios[0].title="x".repeat(201)'
  passes_guards "a string of 200 characters" 's.scenarios[0].title="x".repeat(200)'

  refused "schema 2" 's.schema=2'
  refused "a missing ready.text" 's.ready={}'
  refused "a head_sha in upper case" 's.target.head_sha="A".repeat(40)'
  refused "a head_sha of 39 characters" 's.target.head_sha="a".repeat(39)'
  refused "a duplicate (id, kind) pair" 's.scenarios.push(JSON.parse(JSON.stringify(s.scenarios[0])))'
  passes_guards "the same id with the other kind" 'var n=JSON.parse(JSON.stringify(s.scenarios[0]));n.kind="negative";s.scenarios.push(n)'
  refused "steps together with skip" 's.scenarios[0].skip="why"'
  refused "an entry with neither steps nor skip" 'delete s.scenarios[0].steps'
  refused "a role outside the twelve" 's.scenarios[0].steps.unshift({do:"click",role:"banner",name:"x"})'
  passes_guards "a role inside the twelve" 's.scenarios[0].steps.unshift({do:"click",role:"button",name:"x"})'
  refused "identity with both header and meta" 's.identity={header:"a",meta:"b"}'
  passes_guards "identity with a header only" 's.identity={header:"x-build-sha"}'
  refused "an unknown top-level key" 's.extra=1'
  refused "an unknown key in a step" 's.scenarios[0].steps[0].extra=1'
  refused "an unknown step verb" 's.scenarios[0].steps.unshift({do:"hover",role:"button",name:"x"})'
  refused "an id that is not AC-<digits>" 's.scenarios[0].id="AC-x"'
  refused "a kind that is not criterion or negative" 's.scenarios[0].kind="other"'
  refused "a goto with an absolute URL" 's.scenarios[0].steps[0].path="http://evil.example/"'
  refused "a goto with a protocol-relative path" 's.scenarios[0].steps[0].path="//evil.example/"'
  refused "a screenshot name with a slash" 's.scenarios[0].steps.push({do:"screenshot",name:"a/b"})'
  passes_guards "a screenshot name with a-z, 0-9 and -" 's.scenarios[0].steps.push({do:"screenshot",name:"after-save-1"})'
  passes_guards "a scenario that asserts nothing (a row, not a refusal)" 's.scenarios[0].steps=[{do:"goto",path:"/"}]'
  passes_guards "a skip entry" 's.scenarios=[{id:"AC-1",kind:"criterion",skip:"needs login"}]'
  ips=$(ls -A "$T/home-empty" | wc -l | tr -d ' ')
  [ "$ips" = 0 ]; check "no guard case wrote into the install root" $?
}

# fake_install <dir> <version> [with-browser]: the files the doctor reads, nothing more.
fake_install() {
  mkdir -p "$1/node_modules/playwright"
  printf '{"name":"playwright","version":"%s"}\n' "$2" > "$1/node_modules/playwright/package.json"
  if [ "${3:-}" = with-browser ]; then mkdir -p "$1/browsers/chromium-1"; fi
}
# doctor <home> [runner] [package.json dir used by the runner copy]: sets RC and the doctor text in DOC.
doctor() {
  DOC=$(cd "${DOCTOR_CWD:-$KIT_DIR}" && UI_VERIFY_HOME="$1" "${TIMEOUT[@]}" node "${2:-$RUNNER}" --doctor 2>&1); RC=$?
}
days_ago() { node -e 'process.stdout.write(new Date(Date.now()-Number(process.argv[1])*864e5).toISOString().slice(0,10))' "$1"; }

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
  [ "$(jget "$out/result.json" 'j.rows.length>0&&j.rows.every(r=>r.status==="NO-CHECK")')" = true ]; check "every row is NO-CHECK" $?
  [ "$(jget "$out/result.json" 'j.rows[0].reason.indexOf("install absent")===0')" = true ]; check "the row reason names the absent install" $?
  [ "$(jget "$out/result.json" 'j.verdict')" = NO-CHECK ]; check "the verdict is NO-CHECK, never PASS" $?

  home="$T/dr-drift"; fake_install "$home" 0.0.1 with-browser
  doctor "$home"
  [ "$RC" = 21 ]; check "doctor with another installed version exits 21 (exit $RC)" $?
  RUN_HOME="$home"; out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 2 ] && [ "$(jget "$out/result.json" 'j.rows.every(r=>r.reason==="playwright version differs from the pin")')" = true ]; check "a scenario run on a drifted install is NO-CHECK 'playwright version differs from the pin' (exit $RC)" $?
  home="$T/dr-nobrowser"; fake_install "$home" "$pin"
  doctor "$home"
  [ "$RC" = 22 ]; check "doctor at the pin with no browsers directory exits 22 (exit $RC)" $?
  RUN_HOME="$home"; out=$(next_out); run_runner "$CWD" "$BASE" "$out"
  [ "$RC" = 2 ] && [ "$(jget "$out/result.json" 'j.rows.every(r=>r.status==="NO-CHECK"&&r.reason.length>0)')" = true ]; check "a scenario run with no browser is NO-CHECK with a reason (exit $RC)" $?
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

  doctor "$T/dr-empty"
  case "$(printf '%s\n' "$DOC" | awk '/^state:/{print}')" in *"NOT READY: "*) ok "the doctor state line carries the reason the browser cases print after SKIP" ;; *) no "doctor state line lacks a reason" ;; esac

  doctor_nonode_run
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
  r1=$(PATH="$bin" "$bin/bash" "$s" guard-refusals internal-error battery-row 2>&1); local rc1=$?
  last=$(printf '%s\n' "$r1" | tail -n 1)
  [ "$rc1" = 0 ]; check "no node: the suite exits 0 (exit $rc1)" $?
  [ "$(printf '%s\n' "$r1" | grep -c 'SKIP node not installed')" = 2 ]; check "no node: each node case prints 'SKIP node not installed'" $?
  printf '%s\n' "$r1" | grep -q 'PASS  battery: lens row'; check "no node: the bash-only battery-row case still ran" $?
  case "$last" in "test-ui-acceptance-verifier: "*" passed, 0 failed, 2 skipped") ok "no node: the last line counts 2 skipped ($last)" ;; *) no "no node: last line was: $last" ;; esac
  r2=$(PATH="$bin" UI_VERIFY_REQUIRE=1 "$bin/bash" "$s" internal-error battery-row 2>&1); local rc2=$?
  [ "$rc2" != 0 ]; check "no node with UI_VERIFY_REQUIRE=1: the suite exits non-zero (exit $rc2)" $?
  r2=$("$BASH" "$s" internal-error battery-row 2>&1)
  case "$(printf '%s\n' "$r2" | tail -n 1)" in *" 0 skipped") ok "control: with node on PATH the same cases skip nothing" ;; *) no "control run last line: $(printf '%s\n' "$r2" | tail -n 1)" ;; esac
}

case_fixture_serves() {
  echo "--- fixture-serves"
  need_node fixture-serves || return 0
  local page code count file
  for file in tests/fixtures/ui-verify/serve.mjs tests/fixtures/ui-verify/index.html tests/fixtures/ui-verify/hostile.html tests/fixtures/ui-verify/offsite.html tests/fixtures/ui-verify/otherport.html tests/fixtures/ui-verify/many.html tests/fixtures/ui-verify/nobody.html tests/fixtures/ui-verify/wall.html; do
    [ -s "$KIT_DIR/$file" ]; check "fixture file exists: $file" $?
  done
  if ! start_fixture; then no "the fixture server printed a port line and a port2 line"; stop_fixture; return 0; fi
  case "$FIX_PORT$FIX_PORT2" in *[!0-9]*|"") no "port and port2 are numbers ($FIX_PORT, $FIX_PORT2)" ;; *) ok "the server prints a port line and a port2 line" ;; esac
  for page in index.html hostile.html offsite.html otherport.html many.html nobody.html wall.html; do
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
  grep -qi '^x-build-sha:' <<< "$headers"; [ $? -ne 0 ]; check "no header without --build-sha" $?
  stop_fixture

  local copy="$T/fixcopy"
  mkdir -p "$copy"; cp "$FIXDIR/serve.mjs" "$FIXDIR/index.html" "$FIXDIR/hostile.html" "$FIXDIR/offsite.html" "$FIXDIR/otherport.html" "$FIXDIR/many.html" "$FIXDIR/nobody.html" "$copy/"
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
# wait_no_browser <run id>: true once no process carries the run id; the ceiling fails the caller, never passes it.
wait_no_browser() {
  local i=0
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
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 3000
  [ "$RC" = 1 ]; check "the planted bug (/?bug=1) exits 1 (exit $RC)" $?
  [ "$(row_line "$out/result.json")" = "AC-1=PASS/false,AC-1 neg=PASS/false,AC-2=FAIL/false,AC-3=PASS/false" ]; check "only the AC-2 row is FAIL, the other three keep PASS ($(row_line "$out/result.json"))" $?
  [ "$(jget "$out/result.json" 'j.rows[2].observed.indexOf("Error 500")>=0')" = true ]; check "the AC-2 observed value holds 'Error 500'" $?
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

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"click",role:"button",name:"Nope"},{do:"expect_text",text:"x"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"expect_text",text:"x",within:{role:"dialog",name:"Ghost"}}]},{id:"AC-3",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"click",role:"button",name:"Save"},{do:"expect_text",text:"Saved"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 2000
  [ "$RC" = 1 ]; check "a missing button and a missing within element exit 1 (exit $RC)" $?
  [ "$(row_line "$out/result.json")" = "AC-1=FAIL/false,AC-2=FAIL/false,AC-3=PASS/false" ]; check "both missing-element rows are FAIL, never NO-CHECK; the real button passes ($(row_line "$out/result.json"))" $?
  [ "$(jget "$out/result.json" 'j.rows[0].observed')" = "element not found: role=button name=Nope" ]; check "click observed is 'element not found: role=button name=Nope'" $?
  [ "$(jget "$out/result.json" 'j.rows[1].observed')" = "element not found: role=dialog name=Ghost" ]; check "within observed is 'element not found: role=dialog name=Ghost'" $?

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"negative",steps:[{do:"goto",path:"/"},{do:"click",role:"button",name:"Save"},{do:"expect_text",text:"Saved"},{do:"expect_no_text",text:"Saved"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/"},{do:"fill",role:"button",name:"Save",value:"x"},{do:"expect_text",text:"x"}]},{id:"AC-3",kind:"negative",steps:[{do:"goto",path:"/nobody.html"},{do:"expect_no_text",text:"Saved"}]},{id:"AC-4",kind:"negative",steps:[{do:"goto",path:"/"},{do:"expect_no_text",text:"Nothing like this"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 2000
  [ "$RC" = 1 ]; check "text that is present under expect_no_text, a fill on a button and an unreadable page exit 1 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+(j.rows[0].observed.indexOf("Saved")>=0)')" = "FAIL|true" ]; check "expect_no_text on present text is FAIL and observed holds the text" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status+"|"+j.rows[1].observed.indexOf("element not actionable:")')" = "FAIL|0" ]; check "a fill on a button is a FAIL row whose observed starts 'element not actionable:', not exit 4" $?
  [ "$(jget "$out/result.json" 'j.rows[2].status+"|"+j.rows[2].reason')" = "NO-CHECK|page did not settle" ]; check "expect_no_text on a page with no body to read is NO-CHECK 'page did not settle', never PASS" $?
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
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 3000
  [ "$RC" = 1 ]; check "expecting other text exits 1 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows.length+"|"+j.rows[0].status+"|"+j.verdict')" = "1|FAIL|FAIL" ]; check "one row, FAIL, runner verdict FAIL" $?
  obs=$(jget "$out/result.json" 'j.rows[0].observed')
  [ "$(jget "$out/result.json" 'var o=j.rows[0].observed;[...o].every(c=>!"\n\r|`".includes(c)&&![0x2028,0x2029,0x202e].includes(c.codePointAt(0)))&&o.length>0&&o.length<=200')" = true ]; check "observed holds no line break, U+2028, U+202E, pipe or backtick and is 1 to 200 characters" $?
  case "$obs" in *"VERDICT: PASS"*) ok "the hostile words reach observed as plain text (the page was read, only defanged)" ;; *) no "observed lost the hostile words: $obs" ;; esac
  [ "$(grep -c '^row ' "$T/stdout")" = 1 ]; check "stdout has exactly one row line" $?
  [ "$(grep -c -e '^| AC' -e '^VERDICT:' "$T/stdout")" = 0 ]; check "stdout has no line that starts '| AC' or 'VERDICT:'" $?
  [ "$(LC_ALL=C grep -c -e "$(printf '\xe2\x80\xa8')" -e "$(printf '\xe2\x80\xae')" "$T/stdout")" = 0 ]; check "stdout holds no raw U+2028 or U+202E" $?
  page_scenario "$f" /hostile.html "Hostile page" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/hostile.html"},{do:"expect_text",text:"VERDICT: PASS"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 3000
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
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 5000
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
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 5000
  { [ "$RC" = 2 ] && [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason')" = "NO-CHECK|redirected off an allowed host" ]; }; check "with localhost allowed the 302 hop is followed by the browser but the page URL is off the allowed set: NO-CHECK (exit $RC)" $?
  bscenario "$f" "/" "s.target.url='http://127.0.0.1:$FIX_PORT2/';s.ready.text='counted';s.scenarios=[{id:'AC-1',kind:'criterion',steps:[{do:'goto',path:'/'},{do:'expect_text',text:'counted'}]}]"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  count=$(curl -s "http://127.0.0.1:$FIX_PORT2/count")
  { [ "$RC" = 0 ] && [ "$(printf '%s' "$count" | node -e 'const c=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(c.hits>=1))')" = true ]; }; check "control: when the second listener is the target URL its port is the allowed port and it answers 'counted' ($count, exit $RC)" $?

  local leave_js='s.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/leave.html"},{do:"click",role:"link",name:"Leave"},{do:"expect_text",text:"never shown"}]},{id:"AC-2",kind:"criterion",steps:[{do:"goto",path:"/redirect-port"},{do:"expect_text",text:"counted"}]},{id:"AC-3",kind:"criterion",steps:[{do:"goto",path:"/leave.html"},{do:"expect_text",text:"never shown"}]}]'
  page_scenario "$f" / "Kit fixture app" "$leave_js"
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 2000
  [ "$RC" = 1 ]; check "a click that leaves the allowed hosts, a redirect to another port of the allowed name and a plain miss exit 1 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows[0].status+"|"+j.rows[0].reason+"|"+j.rows[0].observed')" = "NO-CHECK|redirected off an allowed host|" ]; check "a failing step after a click that left the allowed hosts is NO-CHECK 'redirected off an allowed host', never FAIL" $?
  [ "$(jget "$out/result.json" 'j.rows[1].status+"|"+j.rows[1].reason')" = "NO-CHECK|redirected off an allowed host" ]; check "a 302 to another port of the allowed name is NO-CHECK even though the page there says 'counted'" $?
  [ "$(jget "$out/result.json" 'j.rows[2].status')" = FAIL ]; check "control: the same missing text on a page that never left is a plain FAIL" $?
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
  [ "$(jget "$out/result.json" 'j.rows.every(r=>r.status==="NO-CHECK")')" = true ]; check "no row is FAIL or PASS" $?
  [ "$(jget "$out/result.json" 'j.browser.pids.length>0')" = true ]; check "browser.pids is not empty: the run-id marker finds the browser" $?
  [ "$(jget "$out/result.json" 'j.browser.leftover_pids.length')" = 0 ]; check "browser.leftover_pids is empty" $?
  wait_no_browser "$id"; check "no process carries run id $id after the runner exits (ceiling ${PGREP_CEILING_S}s fails the case)" $?
  [ "$(jget "$out/result.json" 'j.duration_ms<=100000')" = true ]; check "duration_ms is at most 100000" $?

  bscenario "$f" "/" 's.scenarios=[s.scenarios[0],s.scenarios[2],s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 0 ] && [ "$(jget "$out/result.json" 'j.rows.every(r=>r.status==="PASS")')" = true ]; }; check "control: the same file without the /hang scenarios and with default timeouts exits 0, every row PASS (exit $RC)" $?
  wait_no_browser "$RUN_ID"; check "control: the browser of the clean run is gone too" $?

  bscenario "$f" "/" 's.scenarios=[{id:"AC-1",kind:"criterion",steps:[{do:"goto",path:"/hang"},{do:"expect_text",text:"x"}]}]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 5000 --scenario-timeout-ms 1000
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
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 5000
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
  identity_case "no identity key in the scenario, a mismatching header on the page" ffffffffffffffffffffffffffffffffffffffff unverified 0 "" 'delete s.identity'

  stop_fixture; start_fixture
  page_scenario "$f" /wall.html "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 3000
  [ "$RC" = 2 ]; check "the login wall (200, no ready text) exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows.every(r=>r.status==="NO-CHECK"&&r.reason==="preview not ready")')" = true ]; check "every row is NO-CHECK 'preview not ready', never FAIL" $?
  page_scenario "$f" /nope.html "Kit fixture app" 's.scenarios=[s.scenarios[3]]'
  out=$(next_out); run_runner "$CWD" "$f" "$out" --step-timeout-ms 3000
  { [ "$RC" = 2 ] && [ "$(jget "$out/result.json" 'j.rows.every(r=>r.status==="NO-CHECK"&&r.reason==="preview unreachable")')" = true ]; }; check "a target URL that answers 404: every row NO-CHECK 'preview unreachable', exit 2 (exit $RC)" $?
  page_scenario "$f" / "Kit fixture app" "s.target.url='https://nonexistent.invalid/';s.target.allow_hosts=['nonexistent.invalid'];s.target.allow_loopback=false;s.scenarios=[s.scenarios[3]]"
  out=$(next_out); run_runner "$CWD" "$f" "$out"
  { [ "$RC" = 2 ] && [ "$(jget "$out/result.json" 'j.rows.every(r=>r.status==="NO-CHECK"&&r.reason==="preview unreachable")')" = true ]; }; check "an allowed host under .invalid that does not resolve: NO-CHECK 'preview unreachable', result.json written, exit 2 (exit $RC)" $?
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

  out=$(next_out); UI_VERIFY_TEST_FAULT=sandbox-unavailable run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "UI_VERIFY_TEST_FAULT=sandbox-unavailable exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows.length>0&&j.rows.every(r=>r.status==="NO-CHECK"&&r.reason==="browser sandbox unavailable")')" = true ]; check "every row is NO-CHECK 'browser sandbox unavailable'" $?
  [ "$(jget "$out/result.json" 'j.browser.launch_attempts+"|"+j.browser.sandbox+"|"+j.browser.pids.length')" = "1|false|0" ]; check "launch_attempts is 1 (no unsandboxed retry), no sandbox, no pids" $?
  [ -z "$(pgrep -f -- "--kit-ui-verify=$RUN_ID" 2>/dev/null)" ]; check "no process carries the run id of the faulted run" $?

  mkdir -p "$stub"; printf '#!/bin/sh\nexit 0\n' > "$stub/ps"; chmod +x "$stub/ps"
  out=$(next_out); PATH="$stub:$PATH" run_runner "$CWD" "$f" "$out"
  [ "$RC" = 2 ]; check "a scan that finds no process carrying the run id (a ps stub that lists nothing) exits 2 (exit $RC)" $?
  [ "$(jget "$out/result.json" 'j.rows.length>0&&j.rows.every(r=>r.status==="NO-CHECK"&&r.reason==="browser sandbox unavailable")')" = true ]; check "unverified sandbox: every row is NO-CHECK 'browser sandbox unavailable'" $?
  [ "$(jget "$out/result.json" 'j.browser.pids.length+"|"+j.browser.sandbox+"|"+j.browser.launch_attempts')" = "0|false|1" ]; check "unverified sandbox: browser.pids is empty and the sandbox is not reported as on" $?
  wait_no_browser "$RUN_ID"; check "the runner still closed that browser (real pgrep finds nothing after the poll)" $?
  end_browser
}

for c in $CASES; do
  selected "$c" || continue
  "case_${c//-/_}"
done
for c in $BROWSER_CASES; do
  selected "$c" || continue
  fn="case_${c//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; fi
done

echo "test-ui-acceptance-verifier: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
