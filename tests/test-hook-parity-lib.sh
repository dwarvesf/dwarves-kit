#!/usr/bin/env bash
# test-hook-parity-lib.sh -- self-test for tests/lib/hook-parity.sh. A tiny fake hook
# stands in for a real port so the library's contract (null-unset, ROOT expansion,
# BAD-EPOCH tagging, stray detection, hp_check's mismatch report, hp_gen_expected's
# rev extraction) is checked without depending on any real hook's behavior.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hook-parity.sh
source "$KIT_DIR/tests/lib/hook-parity.sh"

FAKE="$(mktemp -d)"
cat > "$FAKE/fake-hook.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
payload=$(cat)
if [ -n "${FAKE_HOOK_LOG:-}" ]; then
  mkdir -p "$(dirname "$FAKE_HOOK_LOG")" 2>/dev/null
  printf '%s\t%s\n' "${FAKE_EPOCH:-1}" "logged" >> "$FAKE_HOOK_LOG"
fi
[ "${FAKE_STRAY:-0}" = 1 ] && : > "./stray-file.txt"
jq -n -c --arg payload "$payload" --arg root "${FAKE_ROOTVAR:-}" \
  --arg rootkey "${FAKE_ROOT_MARKER:-}" --arg unset "${FAKE_UNSETVAR-ABSENT}" \
  '{payload:$payload, root:$root, rootkey:$rootkey, unset:$unset}'
echo "fake-stderr" >&2
exit "${FAKE_EXIT:-0}"
EOS
chmod +x "$FAKE/fake-hook.sh"

pass=0; fail=0
check() {
  local desc="$1" cond="$2"
  if [ "$cond" = 1 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $desc"; fi
}

# --- null-unset: a case env value of null excludes the var entirely ---
c=$(jq -n '{name:"null-unset", env:{FAKE_UNSETVAR:null}, payload:"hi"}')
got=$(hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.stdout | fromjson | .unset' <<<"$got")" = "ABSENT" ] && ok=1 || ok=0
check "null-unset excludes the var from the hook's env" "$ok"

# --- ROOT-in-value-only: expands inside a value, never inside a key ---
HROOT="$(mktemp -d)"
c=$(jq -n '{name:"root-expand", env:{FAKE_ROOTVAR:"ROOT/leaf", FAKE_ROOT_MARKER:"plain"}, payload:"hi"}')
got=$(HP_ROOT="$HROOT" hp_run_case "$c" bash "$FAKE/fake-hook.sh")
root_out=$(jq -r '.stdout | fromjson | .root' <<<"$got")
rootkey_out=$(jq -r '.stdout | fromjson | .rootkey' <<<"$got")
[ "$root_out" = "$HROOT/leaf" ] && [ "$rootkey_out" = "plain" ] && ok=1 || ok=0
check "ROOT expands in a value; a key merely containing ROOT is untouched" "$ok"

# --- BAD-EPOCH: a non-digit first field flags the whole log ---
LOGDIR="$(mktemp -d)"
c=$(jq -n --arg log "$LOGDIR/bad.log" '{name:"bad-epoch", env:{FAKE_HOOK_LOG:$log, FAKE_EPOCH:"nope"}, payload:"hi"}')
got=$(HP_LOG_VAR=FAKE_HOOK_LOG hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.log' <<<"$got")" = "BAD-EPOCH logged" ] && ok=1 || ok=0
check "BAD-EPOCH prefix on a non-digit epoch field" "$ok"

c=$(jq -n --arg log "$LOGDIR/good.log" '{name:"good-epoch", env:{FAKE_HOOK_LOG:$log, FAKE_EPOCH:"12345"}, payload:"hi"}')
got=$(HP_LOG_VAR=FAKE_HOOK_LOG hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.log' <<<"$got")" = "logged" ] && ok=1 || ok=0
check "no BAD-EPOCH prefix on an all-digit epoch field" "$ok"

# --- harness default log path when the case omits the log var entirely ---
c=$(jq -n '{name:"default-log", payload:"hi"}')
got=$(HP_LOG_VAR=FAKE_HOOK_LOG hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.log' <<<"$got")" = "logged" ] && ok=1 || ok=0
check "harness default log path used when the case omits the var" "$ok"

# --- stray detection: an extra file under cwd shows up; the log itself never does ---
c=$(jq -n --arg log "$LOGDIR/stray.log" '{name:"stray", env:{FAKE_HOOK_LOG:$log, FAKE_EPOCH:"1", FAKE_STRAY:"1"}, payload:"hi"}')
got=$(HP_LOG_VAR=FAKE_HOOK_LOG hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.stray' <<<"$got")" = "cwd/stray-file.txt" ] && ok=1 || ok=0
check "stray file detected under cwd, effective log path excluded" "$ok"

c=$(jq -n --arg log "$LOGDIR/clean.log" '{name:"no-stray", env:{FAKE_HOOK_LOG:$log, FAKE_EPOCH:"1"}, payload:"hi"}')
got=$(HP_LOG_VAR=FAKE_HOOK_LOG hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.stray' <<<"$got")" = "" ] && ok=1 || ok=0
check "no stray reported when the hook writes only its log" "$ok"

# --- rc and stderr pass through ---
c=$(jq -n '{name:"exit-code", env:{FAKE_EXIT:"7"}, payload:"hi"}')
got=$(hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.rc' <<<"$got")" = "7" ] && [ "$(jq -r '.stderr' <<<"$got")" = "fake-stderr" ] && ok=1 || ok=0
check "rc and stderr pass through unchanged" "$ok"

# --- payload: RAW: prefix stripped on a string, object fed as compact JSON ---
c=$(jq -n '{name:"raw-payload", payload:"RAW:hello"}')
got=$(hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.stdout | fromjson | .payload' <<<"$got")" = "hello" ] && ok=1 || ok=0
check "RAW: prefix stripped from a string payload" "$ok"

c=$(jq -n '{name:"object-payload", payload:{a:1,b:"x"}}')
got=$(hp_run_case "$c" bash "$FAKE/fake-hook.sh")
[ "$(jq -r '.stdout | fromjson | .payload' <<<"$got")" = '{"a":1,"b":"x"}' ] && ok=1 || ok=0
check "object payload fed as compact JSON" "$ok"

# --- hp_check: a deliberate mismatch must FAIL and return non-zero ---
CASES="$FAKE/cases.jsonl"; EXPECTED="$FAKE/expected.jsonl"
jq -n -c '{name:"mismatch-case", env:{FAKE_EXIT:"0"}, payload:"hi"}' > "$CASES"
jq -n -c '{name:"mismatch-case", rc:99, stdout:"nope", stderr:"nope", log:"", stray:""}' > "$EXPECTED"
out=$(hp_check "$CASES" "$EXPECTED" bash "$FAKE/fake-hook.sh" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "FAIL mismatch-case" && echo "$out" | grep -q "0 passed, 1 failed"; then
  ok=1
else
  ok=0
fi
check "hp_check reports FAIL and returns non-zero on a mismatch" "$ok"

jq -n -c '{name:"match-case", env:{FAKE_EXIT:"0"}, payload:"hi"}' > "$CASES"
hp_run_case "$(head -1 "$CASES")" bash "$FAKE/fake-hook.sh" > "$EXPECTED"
out=$(hp_check "$CASES" "$EXPECTED" bash "$FAKE/fake-hook.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "1 passed, 0 failed"; then ok=1; else ok=0; fi
check "hp_check passes and returns zero on a match" "$ok"

# --- hp_gen_expected: extracts a rev's hooks/<name>.sh (+ .py) and runs cases through it ---
GITROOT="$(mktemp -d)"
git -C "$GITROOT" init -q
git -C "$GITROOT" config user.email test@example.com
git -C "$GITROOT" config user.name test
mkdir -p "$GITROOT/hooks"
cp "$FAKE/fake-hook.sh" "$GITROOT/hooks/fake.sh"
echo "# stub, never executed by hp_gen_expected" > "$GITROOT/hooks/fake.py"
git -C "$GITROOT" add -A
git -C "$GITROOT" commit -q -m fixture
REV=$(git -C "$GITROOT" rev-parse HEAD)
jq -n -c '{name:"gen-case", env:{FAKE_EXIT:"0"}, payload:"gen-hi"}' > "$FAKE/gen-cases.jsonl"
HP_KIT_ROOT="$GITROOT" hp_gen_expected "$REV" fake "$FAKE/gen-cases.jsonl" "$FAKE/gen-expected.jsonl"
lines=$(wc -l < "$FAKE/gen-expected.jsonl" | tr -d ' ')
grep -q '"name":"gen-case"' "$FAKE/gen-expected.jsonl" && [ "$lines" = 1 ] && ok=1 || ok=0
check "hp_gen_expected extracts the rev's hook and runs cases through it" "$ok"

echo "hook-parity-lib self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
