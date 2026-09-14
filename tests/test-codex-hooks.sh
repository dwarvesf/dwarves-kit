#!/usr/bin/env bash
# Contract tests for the Codex hook package and runtime adapter.
# shellcheck disable=SC2016,SC2088

set -uo pipefail

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CODEX_MANIFEST="${CODEX_MANIFEST:-$KIT_DIR/.codex-plugin/plugin.json}"
CODEX_HOOKS_FILE="${CODEX_HOOKS_FILE:-$KIT_DIR/hooks/codex-hooks.json}"
ADAPTER="$KIT_DIR/hooks/codex-hook-adapter.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dwarves-kit-codex-hooks.XXXXXX")"
export DWARVES_KIT_LOG_DIR="$TEST_DIR/logs"
export PLUGIN_ROOT="$KIT_DIR"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
}

assert_success() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

assert_equal() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$name"; else fail "$name: expected $expected, got $actual"; fi
}

run_adapter() {
  local event="$1" policy="$2" payload="$3"
  local stdout_file="$TEST_DIR/stdout" stderr_file="$TEST_DIR/stderr" rc=0
  printf '%s' "$payload" | bash "$ADAPTER" "$event" "$policy" >"$stdout_file" 2>"$stderr_file" || rc=$?
  printf '%s' "$rc"
}

run_adapter_in() {
  local cwd="$1" event="$2" policy="$3" payload="$4"
  local stdout_file="$TEST_DIR/stdout" stderr_file="$TEST_DIR/stderr" rc=0
  printf '%s' "$payload" | (cd "$cwd" && bash "$ADAPTER" "$event" "$policy") >"$stdout_file" 2>"$stderr_file" || rc=$?
  printf '%s' "$rc"
}

run_manifest_hook() {
  local policy="$1" payload="$2" plugin_root="${3:-$KIT_DIR}" command rc=0
  command=$(jq -r --arg policy "$policy" '.hooks[][]?.hooks[]? | select(.command | contains($policy)) | .command' "$CODEX_HOOKS_FILE")
  printf '%s' "$payload" | PLUGIN_ROOT="$plugin_root" /bin/bash -c "$command" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr" || rc=$?
  printf '%s' "$rc"
}

echo "Codex package"
assert_success "Codex manifest is valid JSON" jq -e . "$CODEX_MANIFEST"
assert_success "Codex hooks are valid JSON" jq -e . "$CODEX_HOOKS_FILE"

if [ -f "$CODEX_MANIFEST" ] && [ -f "$CODEX_HOOKS_FILE" ]; then
  CLAUDE_NAME=$(jq -r '.name' "$KIT_DIR/.claude-plugin/plugin.json")
  CLAUDE_VERSION=$(jq -r '.version' "$KIT_DIR/.claude-plugin/plugin.json")
  assert_equal "plugin name matches Claude package" "$CLAUDE_NAME" "$(jq -r '.name' "$CODEX_MANIFEST")"
  assert_equal "plugin version matches Claude package" "$CLAUDE_VERSION" "$(jq -r '.version' "$CODEX_MANIFEST")"
  assert_equal "manifest selects Codex hook file" "./hooks/codex-hooks.json" "$(jq -r '.hooks' "$CODEX_MANIFEST")"

  UNSUPPORTED=$(jq -r '.hooks | keys[]' "$CODEX_HOOKS_FILE" | grep -Ev '^(PreToolUse|Stop)$' || true)
  assert_equal "only supported phase-one events ship" "" "$UNSUPPORTED"

  for policy in safety-gate.sh secrets-guard.sh ship-gate.sh commit-format.sh anti-rationalization.sh; do
    COUNT=$(jq --arg policy "$policy" '[.hooks[][]?.hooks[]? | select(.command | contains($policy))] | length' "$CODEX_HOOKS_FILE")
    assert_equal "$policy appears exactly once" "1" "$COUNT"
    POLICY_HASH=$(shasum -a 256 "$KIT_DIR/hooks/$policy" | awk '{print $1}')
    HASH_COUNT=$(jq --arg policy "$policy" --arg hash "$POLICY_HASH" '[.hooks[][]?.hooks[]? | select(.command | contains($policy) and contains($hash))] | length' "$CODEX_HOOKS_FILE")
    assert_equal "$policy trust command pins its content hash" "1" "$HASH_COUNT"
  done

  ADAPTER_HASH=$(shasum -a 256 "$ADAPTER" | awk '{print $1}')
  HASHED_ADAPTER_COUNT=$(jq --arg hash "$ADAPTER_HASH" '[.hooks[][]?.hooks[]? | select(.command | contains($hash))] | length' "$CODEX_HOOKS_FILE")
  assert_equal "every trust command pins the adapter content hash" "5" "$HASHED_ADAPTER_COUNT"
  PORTABLE_HASH_COUNT=$(jq '[.hooks[][]?.hooks[]? | select(.command | contains("sha256sum"))] | length' "$CODEX_HOOKS_FILE")
  assert_equal "every trust command has a Linux checksum fallback" "5" "$PORTABLE_HASH_COUNT"
  FIXED_SHASUM_COUNT=$(jq '[.hooks[][]?.hooks[]? | select(.command | contains("/usr/bin/shasum"))] | length' "$CODEX_HOOKS_FILE")
  assert_equal "trust commands do not require a fixed shasum path" "0" "$FIXED_SHASUM_COUNT"

  MISSING=0
  while IFS= read -r command; do
    target=$(printf '%s\n' "$command" | awk '{print $NF}')
    [ -n "$target" ] && [ -x "$KIT_DIR/hooks/$target" ] || MISSING=$((MISSING + 1))
  done < <(jq -r '.hooks[][]?.hooks[]?.command' "$CODEX_HOOKS_FILE")
  assert_equal "every policy target exists and is executable" "0" "$MISSING"
  if [ -x "$ADAPTER" ]; then pass "adapter command target is executable"; else fail "adapter command target is executable"; fi

  if command -v codex >/dev/null 2>&1; then
    LOADER_HOME="$TEST_DIR/codex-home"
    mkdir -p "$LOADER_HOME"
    if CODEX_HOME="$LOADER_HOME" codex plugin marketplace add "$KIT_DIR" --json >/dev/null 2>&1 \
      && CODEX_HOME="$LOADER_HOME" codex plugin add kit@dwarves-marketplace --json >/dev/null 2>&1; then
      pass "Codex loader accepts and installs the package"
    else
      fail "Codex loader accepts and installs the package"
    fi
  fi
fi

echo "Codex adapter behavior"
RC=0
printf '{}' | bash "$ADAPTER" >/dev/null 2>&1 || RC=$?
assert_equal "standalone no-op smoke event is allowed" "0" "$RC"
RC=0
printf '{"hook_event_name":"PreToolUse"}' | bash "$ADAPTER" >/dev/null 2>&1 || RC=$?
assert_equal "untargeted real hook event fails closed" "2" "$RC"
RC=$(run_adapter PreToolUse safety-gate.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /workspace/source"}}')
assert_equal "destructive Bash command is blocked" "2" "$RC"
RC=$(run_adapter PreToolUse safety-gate.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}')
assert_equal "harmless Bash command is allowed" "0" "$RC"
RC=$(run_manifest_hook safety-gate.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}')
assert_equal "trusted manifest command executes verified hook content" "0" "$RC"

MUTATED_ROOT="$TEST_DIR/mutated-plugin"
mkdir -p "$MUTATED_ROOT/hooks"
cp "$ADAPTER" "$KIT_DIR/hooks/safety-gate.sh" "$MUTATED_ROOT/hooks/"
printf '\n# disposable trust mutation\n' >> "$MUTATED_ROOT/hooks/safety-gate.sh"
RC=$(run_manifest_hook safety-gate.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$MUTATED_ROOT")
assert_equal "changed hook content is refused before execution" "2" "$RC"
if grep -q 'trusted hook content changed' "$TEST_DIR/stderr"; then pass "trust refusal names changed content"; else fail "trust refusal names changed content"; fi

RC=$(run_adapter PreToolUse commit-format.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"bad subject\""}}')
assert_equal "invalid commit subject is blocked" "2" "$RC"
RC=$(run_adapter PreToolUse commit-format.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"test(hooks): verify adapter\""}}')
assert_equal "valid commit subject is allowed" "0" "$RC"

SHIP_REPO="$TEST_DIR/ship-repo"
mkdir -p "$SHIP_REPO/docs/verification" "$SHIP_REPO/docs/specs"
git -C "$SHIP_REPO" init -q -b main
git -C "$SHIP_REPO" config user.name test
git -C "$SHIP_REPO" config user.email test@example.invalid
printf '# Verification contract\n' > "$SHIP_REPO/docs/verification/README.md"
printf '# Fixture\n' > "$SHIP_REPO/README.md"
git -C "$SHIP_REPO" add .
git -C "$SHIP_REPO" commit -qm 'test: initialize fixture'
git -C "$SHIP_REPO" switch -qc feat/ship-case
printf 'Status: VALIDATED\nLane: normal\n' > "$SHIP_REPO/docs/specs/SPEC-001-ship-case.md"
printf '\nchange\n' >> "$SHIP_REPO/README.md"
git -C "$SHIP_REPO" add .
git -C "$SHIP_REPO" commit -qm 'test: add fixture change'
SHIP_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push origin feat/ship-case"}}'
RC=$(run_adapter_in "$SHIP_REPO" PreToolUse ship-gate.sh "$SHIP_PAYLOAD")
assert_equal "incomplete feature push is blocked" "2" "$RC"
mkdir -p "$DWARVES_KIT_LOG_DIR/runs"
printf '2026-09-14T00:00:00Z | START | lane=normal classified=normal type=spec-feature repo=%s\n2026-09-14T00:01:00Z | GATE | spec | ran | fixture\n2026-09-14T00:02:00Z | GATE | build | ran | fixture\n2026-09-14T00:03:00Z | GATE | ship | ran | fixture\n' "$SHIP_REPO" > "$DWARVES_KIT_LOG_DIR/runs/ship-case.log"
RC=$(run_adapter_in "$SHIP_REPO" PreToolUse ship-gate.sh "$SHIP_PAYLOAD")
assert_equal "complete feature push is allowed" "0" "$RC"
RC=$(run_adapter PreToolUse ship-gate.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}')
assert_equal "non-shipping command bypasses ship gate" "0" "$RC"

SECRET_PATHS=(
  '/workspace/app/.env'
  '/workspace/app/.env.local'
  '~/.docker/config.json'
  '~/.config/gh/hosts.yml'
  '~/.ssh/id_ed25519'
  '~/.aws/credentials'
  '~/.cloudflared/cert.pem'
  '~/.config/cloudflared/config.yml'
  '~/.codex/auth.json'
  '~/.codex/.codex-global-state.json'
)

for secret_path in "${SECRET_PATHS[@]}"; do
  BASH_PAYLOAD=$(jq -cn --arg command "cat $secret_path" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command}}')
  RC=$(run_adapter PreToolUse secrets-guard.sh "$BASH_PAYLOAD")
  assert_equal "Bash blocks $secret_path" "2" "$RC"

  PATCH_COMMAND=$(printf '*** Begin Patch\n*** Update File: %s\n@@\n-old\n+new\n*** End Patch' "$secret_path")
  PATCH_PAYLOAD=$(jq -cn --arg command "$PATCH_COMMAND" '{hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{command:$command}}')
  RC=$(run_adapter PreToolUse secrets-guard.sh "$PATCH_PAYLOAD")
  assert_equal "apply_patch blocks $secret_path" "2" "$RC"
done


QUOTED_HOME_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat \"${HOME}/.codex/auth.json\""}}'
RC=$(run_adapter PreToolUse secrets-guard.sh "$QUOTED_HOME_PAYLOAD")
assert_equal "Bash blocks braced HOME credential path" "2" "$RC"

SPLIT_HOME_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat \"$HOME\"/.codex/auth.json"}}'
RC=$(run_adapter PreToolUse secrets-guard.sh "$SPLIT_HOME_PAYLOAD")
assert_equal "Bash blocks split-quoted HOME credential path" "2" "$RC"

SPLIT_TILDE_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat \"~\"/.codex/auth.json"}}'
RC=$(run_adapter PreToolUse secrets-guard.sh "$SPLIT_TILDE_PAYLOAD")
assert_equal "Bash blocks split-quoted tilde credential path" "2" "$RC"

RELATIVE_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cd ~/.codex && cat auth.json"}}'
RC=$(run_adapter PreToolUse secrets-guard.sh "$RELATIVE_PAYLOAD")
assert_equal "Bash blocks secret path relative to cd" "2" "$RC"

TRAVERSAL_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat ~/.codex/cache/../auth.json"}}'
RC=$(run_adapter PreToolUse secrets-guard.sh "$TRAVERSAL_PAYLOAD")
assert_equal "Bash blocks traversed credential path" "2" "$RC"

CRLF_PATCH=$(printf '*** Begin Patch\r\n*** Update File: ~/.codex/auth.json\r\n*** Move to: ~/.codex/auth-copy.json\r\n*** End Patch')
CRLF_PAYLOAD=$(jq -cn --arg command "$CRLF_PATCH" '{hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{command:$command}}')
RC=$(run_adapter PreToolUse secrets-guard.sh "$CRLF_PAYLOAD")
assert_equal "apply_patch blocks CRLF path headers" "2" "$RC"

for patch_header in 'Add File' 'Delete File' 'Move to'; do
  EDGE_PATCH=$(printf '*** Begin Patch\n*** %s: ~/.codex/auth.json\n*** End Patch' "$patch_header")
  EDGE_PAYLOAD=$(jq -cn --arg command "$EDGE_PATCH" '{hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{command:$command}}')
  RC=$(run_adapter PreToolUse secrets-guard.sh "$EDGE_PAYLOAD")
  assert_equal "apply_patch blocks $patch_header secret path" "2" "$RC"
done

RC=$(run_adapter PreToolUse secrets-guard.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat /workspace/app/main.go"}}')
assert_equal "normal source read is allowed" "0" "$RC"
BENIGN_PATCH=$(printf '*** Begin Patch\n*** Update File: /workspace/app/main.go\n*** End Patch')
BENIGN_PAYLOAD=$(jq -cn --arg command "$BENIGN_PATCH" '{hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{command:$command}}')
RC=$(run_adapter PreToolUse secrets-guard.sh "$BENIGN_PAYLOAD")
assert_equal "normal source patch is allowed" "0" "$RC"

STOP_PAYLOAD='{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"I will leave this as a follow-up task."}'
RC=$(run_adapter Stop anti-rationalization.sh "$STOP_PAYLOAD")
assert_equal "Codex Stop message requests continuation" "2" "$RC"
RC=$(run_adapter Stop anti-rationalization.sh '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"All requested checks passed."}')
assert_equal "clean Codex Stop is allowed" "0" "$RC"
RC=$(run_adapter Stop anti-rationalization.sh '{"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"follow-up task"}')
assert_equal "active Stop hook does not loop" "0" "$RC"

RC=$(run_adapter PreToolUse safety-gate.sh '[]')
assert_equal "non-object hook input fails closed" "2" "$RC"
RC=$(run_adapter PreToolUse safety-gate.sh '{"hook_event_name":"Stop","tool_name":"Bash","tool_input":{"command":"git status"}}')
assert_equal "wrong event payload fails closed" "2" "$RC"

for policy in safety-gate.sh secrets-guard.sh ship-gate.sh commit-format.sh anti-rationalization.sh; do
  event=PreToolUse
  [ "$policy" = "anti-rationalization.sh" ] && event=Stop
  RC=0
  printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' | PATH="$TEST_DIR" /bin/bash "$ADAPTER" "$event" "$policy" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr" || RC=$?
  assert_equal "$policy fails closed without jq" "2" "$RC"
  if grep -q 'jq is required' "$TEST_DIR/stderr"; then pass "$policy names the missing dependency"; else fail "$policy names the missing dependency"; fi
done

SYNTHETIC_TOKEN='ghp_abcd1234abcd1234abcd1234abcd1234abcd'
TOKEN_PAYLOAD=$(jq -cn --arg command "cat /workspace/app/.env # $SYNTHETIC_TOKEN" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command}}')
RC=$(run_adapter PreToolUse secrets-guard.sh "$TOKEN_PAYLOAD")
assert_equal "token-shaped secret attempt is blocked" "2" "$RC"
if grep -R -F "$SYNTHETIC_TOKEN" "$TEST_DIR/stdout" "$TEST_DIR/stderr" "$DWARVES_KIT_LOG_DIR" >/dev/null 2>&1; then
  fail "token fixture is absent from hook output and logs"
else
  pass "token fixture is absent from hook output and logs"
fi

AWS_FIXTURE='AKIAABCDEFGHIJKLMNOP'
AWS_PAYLOAD=$(jq -cn --arg command "cat /workspace/$AWS_FIXTURE/.env" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command}}')
RC=$(run_adapter PreToolUse secrets-guard.sh "$AWS_PAYLOAD")
assert_equal "AWS-shaped secret attempt is blocked" "2" "$RC"
if grep -R -F "$AWS_FIXTURE" "$TEST_DIR/stdout" "$TEST_DIR/stderr" "$DWARVES_KIT_LOG_DIR" >/dev/null 2>&1; then
  fail "AWS fixture is absent from hook output and logs"
else
  pass "AWS fixture is absent from hook output and logs"
fi

AWS_CWD="$TEST_DIR/$AWS_FIXTURE"
mkdir -p "$AWS_CWD"
RC=$(run_adapter_in "$AWS_CWD" PreToolUse secrets-guard.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat .env"}}')
assert_equal "secret attempt from AWS-shaped working directory is blocked" "2" "$RC"
if grep -R -F "$AWS_FIXTURE" "$TEST_DIR/stdout" "$TEST_DIR/stderr" "$DWARVES_KIT_LOG_DIR" >/dev/null 2>&1; then
  fail "working directory token fixture is absent from output and logs"
else
  pass "working directory token fixture is absent from output and logs"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
