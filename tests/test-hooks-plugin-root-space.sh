#!/bin/bash
# test-hooks-plugin-root-space.sh -- hooks/hooks.json commands survive a plugin root path with a space.
#
# Orca runs Claude Code with a CLAUDE_CONFIG_DIR under "Application Support", so
# ${CLAUDE_PLUGIN_ROOT} holds a space. /bin/sh word-splits an unquoted expansion: bash then runs
# a stray path prefix, exits 0, and every gate silently does nothing. This suite runs the REAL
# safety-gate entry from hooks.json through /bin/sh -c with the kit copied to a spaced path and
# asserts it still blocks (exit 2). A negative control strips the quotes from the same entry and
# asserts the block disappears, so the green result cannot be vacuous.
#
# The known-bad payload rides a heredoc into a file: the live ship-gate inspects command lines.
#
# Run: bash tests/test-hooks-plugin-root-space.sh   Exit 0 = pass, 1 = failures.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-rootspace.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

SPACED="$TMP/Application Support/kit"
mkdir -p "$SPACED" "$TMP/repo"
cp -R "$KIT_DIR/hooks" "$KIT_DIR/lib" "$SPACED/"
( cd "$TMP/repo" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m base )

# The known-bad input: a force push to main, which safety-gate refuses.
cat > "$TMP/payload.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}
EOF

# entry_command <hooks.json> <hook basename> : the first command that runs that hook.
entry_command() {
  jq -r --arg h "/hooks/$2" '[.hooks[][].hooks[].command | select(contains($h))][0] // empty' "$1"
}

# run_entry <command> : run it the way Claude Code does, from a repo subdirectory, rooted at the spaced kit.
run_entry() {
  ( cd "$TMP/repo" && env CLAUDE_PLUGIN_ROOT="$SPACED" DWARVES_KIT_LOG_DIR="$TMP/log" \
      /bin/sh -c "$1" < "$TMP/payload.json" >/dev/null 2>&1 )
  echo $?
}

echo "=== hooks.json: the real safety-gate entry, plugin root with a space ==="
CMD="$(entry_command "$KIT_DIR/hooks/hooks.json" safety-gate.sh)"
if [ -n "$CMD" ]; then ok "hooks.json has a safety-gate entry"; else bad "hooks.json has a safety-gate entry"; fi

RC="$(run_entry "$CMD")"
if [ "$RC" = 2 ]; then
  ok "quoted entry blocks the bad input through /bin/sh -c (exit $RC)"
else
  bad "quoted entry blocks the bad input through /bin/sh -c (want exit 2, got $RC)"
fi

echo "=== negative control: the same entry with its quotes stripped ==="
UNQUOTED="$(printf '%s' "$CMD" | tr -d '"')"
RC_UQ="$(run_entry "$UNQUOTED")"
if [ "$RC_UQ" != 2 ]; then
  ok "unquoted entry does NOT block, the bug reproduces (exit $RC_UQ)"
else
  bad "unquoted entry does NOT block, the bug reproduces (got exit 2, so this test proves nothing)"
fi

echo "=== hooks.json: every \${CLAUDE_PLUGIN_ROOT} use sits inside double quotes ==="
BARE="$(jq -r '.hooks[][].hooks[].command
  | gsub("\"[^\"]*\""; "")
  | select(contains("${CLAUDE_PLUGIN_ROOT}"))' "$KIT_DIR/hooks/hooks.json")"
if [ -z "$BARE" ]; then
  ok "no unquoted \${CLAUDE_PLUGIN_ROOT} in any hooks.json command"
else
  bad "no unquoted \${CLAUDE_PLUGIN_ROOT} in any hooks.json command"
  printf '        %s\n' "$BARE" | head -3
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
