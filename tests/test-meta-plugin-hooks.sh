#!/bin/bash
# test-meta-plugin-hooks.sh -- plugin-hooks structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-plugin-hooks.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

# ============================================================
echo "=== Plugin manifest schema ==="
# ============================================================

# plugin.json: name, version, description present
PLUGIN_NAME=$(jq -r '.name' "$KIT_DIR/.claude-plugin/plugin.json")
assert_eq "plugin.json name == 'kit'" "kit" "$PLUGIN_NAME"

PLUGIN_VERSION=$(jq -r '.version' "$KIT_DIR/.claude-plugin/plugin.json")
VERSION_FILE=$(cat "$KIT_DIR/VERSION" | tr -d '[:space:]')
assert_eq "plugin.json version matches VERSION file" "$VERSION_FILE" "$PLUGIN_VERSION"

# SPEC-115: the THIRD version surface (tool.toml) must match too , the v1.7.0 cut
# missed it (tool.toml drifted to 1.6.0); this three-surface pin kills that class.
TOOL_TOML_VERSION=$(grep -E '^version' "$KIT_DIR/tool.toml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
assert_eq "tool.toml version matches VERSION file (3-surface pin, SPEC-115)" "$VERSION_FILE" "$TOOL_TOML_VERSION"

# `bin/learn` (#560, ADR-0036) is a "kept for ONE release" forwarder: it first ships in
# 2.3.0 and is due for deletion starting 2.4.0 (backlog ID-839, docs/CHANGELOG.md
# Deprecated entry). Neither promise was ever mechanically enforced -- the battery's own
# finding -- so this trips red the moment VERSION reaches 2.4.0 while the file still
# exists, instead of the removal silently missing its own release like `bin/skill-
# improve` did. `sort -V` handles "2.10.0" > "2.4.0" correctly; a bare string compare
# would not.
BIN_LEARN_DUE_VERSION="2.4.0"
if [ -e "$KIT_DIR/bin/learn" ]; then
  LOWER="$(printf '%s\n%s\n' "$VERSION_FILE" "$BIN_LEARN_DUE_VERSION" | sort -V | head -1)"
  BIN_LEARN_OVERDUE=1
  [ "$LOWER" = "$VERSION_FILE" ] && [ "$VERSION_FILE" != "$BIN_LEARN_DUE_VERSION" ] && BIN_LEARN_OVERDUE=0
else
  BIN_LEARN_OVERDUE=0
fi
assert_true "bin/learn forwarder is deleted by VERSION $BIN_LEARN_DUE_VERSION (ID-839; currently $VERSION_FILE)" "$BIN_LEARN_OVERDUE"

# ============================================================
echo "=== Invocation namespace guard (SPEC-029, SPEC-030) ==="
# ============================================================
# The kit's commands resolve as /kit:<cmd> (plugin) or bare /<cmd> (bash install).
# /user:<cmd> is the dead reserved-prefix form and must not appear in LIVE docs
# OR in the runtime surfaces that print command hints (install.sh, hooks/*.sh).
# Denylist, not allowlist (DEC-004): scan every tracked *.md EXCEPT the dated,
# point-in-time dirs (specs/retros/ADRs/handoff/research), PLUS install.sh and
# hooks/*.sh (SPEC-030 DEC-003), so a future live doc OR hook is covered
# automatically. tests/ is NOT scanned: this file names /user: to describe the
# guard. Enforces /user: ABSENCE only (DEC-005); bare-/cmd is not auto-checked.
USER_NS_HITS=$(cd "$KIT_DIR" && { git ls-files '*.md' \
      | grep -vE '^(docs/specs/|docs/retro/|docs/decisions/|docs/handoff/|docs/research/|docs/verification/|_meta/|CHANGELOG\.md|docs/CHANGELOG\.md)'; \
    git ls-files 'install.sh' 'hooks/*.sh'; } \
  | xargs grep -l '/user:' 2>/dev/null)
if [ -n "$USER_NS_HITS" ]; then
  echo "  live files still using /user::" >&2
  echo "$USER_NS_HITS" | sed 's/^/    /' >&2
fi
[ -z "$USER_NS_HITS" ]; assert_true "no /user: invocation form in live docs/install/hooks (SPEC-029, SPEC-030)" $?

PLUGIN_DESC=$(jq -r '.description // ""' "$KIT_DIR/.claude-plugin/plugin.json")
TOTAL=$((TOTAL + 1))
if [ -n "$PLUGIN_DESC" ]; then
  echo -e "  ${GREEN}PASS${NC} plugin.json has description"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} plugin.json description empty"
  FAIL=$((FAIL + 1))
fi

# marketplace.json: plugins[0].name matches plugin.json.name
MP_PLUGIN_NAME=$(jq -r '.plugins[0].name' "$KIT_DIR/.claude-plugin/marketplace.json")
assert_eq "marketplace.json plugins[0].name == plugin.json name" "$PLUGIN_NAME" "$MP_PLUGIN_NAME"

MP_NAME=$(jq -r '.name' "$KIT_DIR/.claude-plugin/marketplace.json")
assert_eq "marketplace.json name == 'dwarves-marketplace'" "dwarves-marketplace" "$MP_NAME"

# ============================================================
echo ""
echo "=== Hook registration parity (settings.json vs hooks/hooks.json) ==="
# ============================================================

H1=$(jq '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$KIT_DIR/settings.json")
H2=$(jq '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$KIT_DIR/hooks/hooks.json")
assert_eq "hook count parity (settings.json == hooks.json)" "$H1" "$H2"

# All hooks.json paths use ${CLAUDE_PLUGIN_ROOT}
NON_PLUGIN_PATHS=$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[].command] | .[]' "$KIT_DIR/hooks/hooks.json" | grep -v '\${CLAUDE_PLUGIN_ROOT}' | wc -l | tr -d ' ')
assert_eq "all hooks.json paths use \${CLAUDE_PLUGIN_ROOT}" "0" "$NON_PLUGIN_PATHS"

# Same set of event types in both
EVENTS_SETTINGS=$(jq -r '.hooks | keys | sort | join(",")' "$KIT_DIR/settings.json")
EVENTS_HOOKS=$(jq -r '.hooks | keys | sort | join(",")' "$KIT_DIR/hooks/hooks.json")
assert_eq "same event types in both files" "$EVENTS_SETTINGS" "$EVENTS_HOOKS"

# ============================================================
echo ""
echo "=== Hook executability ==="
# ============================================================

# Every hook script must carry the exec bit. They run via `bash <script>`
# at runtime so a missing bit is silent, which is exactly why CI never
# caught session-state-save.sh shipping as 100644. kit-health flags it;
# this asserts it so it cannot regress past CI again. Offenders are named
# in the test label on failure.
NON_EXEC=$(for f in "$KIT_DIR"/hooks/*.sh; do [ -x "$f" ] || basename "$f"; done | tr '\n' ' ' | sed 's/ $//')
NON_EXEC_COUNT=$(printf '%s' "$NON_EXEC" | wc -w | tr -d ' ')
assert_eq "all hooks/*.sh are executable (non-exec: ${NON_EXEC:-none})" "0" "$NON_EXEC_COUNT"

# ============================================================
echo ""
echo "=== Installer materializes the hooks settings.json references ==="
# ============================================================
# settings.json hard-codes $HOME/.claude/dwarves-kit/hooks/<script>.sh for every
# hook (and the statusline). install.sh must place each script at that path, or
# every hook fails at runtime with "No such file or directory". This regressed
# once: settings referenced the hooks but install.sh never installed them, so a
# fresh session greeted the user with a SessionStart hook error.

# (1) Each referenced script exists in the repo's hooks/ dir.
MISSING_IN_REPO=$(grep -oE 'dwarves-kit/hooks/[A-Za-z0-9._-]+\.sh' "$KIT_DIR/settings.json" \
  | sed 's#.*/##' | sort -u \
  | while read -r s; do [ -f "$KIT_DIR/hooks/$s" ] || echo "$s"; done \
  | tr '\n' ' ' | sed 's/ $//')
assert_eq "every settings.json hook script exists in hooks/ (missing: ${MISSING_IN_REPO:-none})" "" "$MISSING_IN_REPO"

# (2) A real install into a throwaway HOME leaves every referenced path resolvable.
# This is the direct regression guard: it fails on the buggy installer that never
# materialized the scripts, and passes once install.sh links them into place.
TMP_HOME=$(mktemp -d)
if HOME="$TMP_HOME" bash "$KIT_DIR/install.sh" >/dev/null 2>&1; then
  UNRESOLVED=$(grep -oE '\$HOME/\.claude/dwarves-kit/hooks/[A-Za-z0-9._-]+\.sh' "$TMP_HOME/.claude/settings.json" \
    | sort -u \
    | while read -r raw; do p=${raw/\$HOME/$TMP_HOME}; [ -f "$p" ] || echo "$p"; done \
    | tr '\n' ' ' | sed 's/ $//')
  assert_eq "install.sh resolves every dwarves-kit hook path (unresolved: ${UNRESOLVED:-none})" "" "$UNRESOLVED"
  # SPEC-045: install must materialize lib/ so the gates resolve from the stable
  # install path in consumer repos (else the proof-of-done gate fails open everywhere
  # but dwarves-kit). -e follows the dir symlink to the real file.
  [ -e "$TMP_HOME/.claude/dwarves-kit/lib/gate/proof-ledger.sh" ]
  assert_true "install.sh materializes lib/gate/proof-ledger.sh (SPEC-045)" $?
  # SPEC-049: install must materialize the operate-contract too, so adopt (needs a source
  # AGENTS.md) + gate-ledger (reads WORKFLOW.md) work from the install, not only the dev
  # checkout. Asserts the REAL install run, not test-install-contract.sh's simulated layout.
  [ -e "$TMP_HOME/.claude/dwarves-kit/AGENTS.md" ]
  assert_true "install.sh materializes AGENTS.md (SPEC-049)" $?
  [ -e "$TMP_HOME/.claude/dwarves-kit/WORKFLOW.md" ]
  assert_true "install.sh materializes WORKFLOW.md (SPEC-049)" $?
  # SPEC-185: WORKFLOW.md's bulk moved to docs/WORKFLOW.md (root is a thin stub); gate-ledger
  # reads $KIT_ROOT/docs/WORKFLOW.md at runtime, so install.sh must ALSO materialize that file
  # or every installed consumer's gate machinery 404s against an uncopied docs/ path.
  [ -e "$TMP_HOME/.claude/dwarves-kit/docs/WORKFLOW.md" ]
  assert_true "install.sh materializes docs/WORKFLOW.md bulk (SPEC-185)" $?
  N_INSTALLED=$(CLAUDE_PLUGIN_ROOT="$TMP_HOME/.claude/dwarves-kit" bash "$TMP_HOME/.claude/dwarves-kit/lib/gate/gate-ledger.sh" required full 2>/dev/null | wc -l | tr -d ' ')
  assert_true "installed stub's pointer resolves: gate-ledger reads the lane matrix from the install ($N_INSTALLED gates, SPEC-185)" "$([ "${N_INSTALLED:-0}" -ge 5 ]; echo $?)"
  # SPEC-049: uninstall removes the two contract symlinks (the new uninstall code path).
  HOME="$TMP_HOME" bash "$KIT_DIR/install.sh" --uninstall >/dev/null 2>&1
  { [ ! -L "$TMP_HOME/.claude/dwarves-kit/AGENTS.md" ] && [ ! -L "$TMP_HOME/.claude/dwarves-kit/WORKFLOW.md" ]; }
  assert_true "uninstall removes the AGENTS.md + WORKFLOW.md symlinks (SPEC-049)" $?
  [ ! -L "$TMP_HOME/.claude/dwarves-kit/docs/WORKFLOW.md" ]
  assert_true "uninstall removes the docs/WORKFLOW.md symlink (SPEC-185)" $?
else
  assert_eq "install.sh runs cleanly into an isolated HOME" "ok" "failed"
fi
rm -rf "$TMP_HOME"

# (3) In-place layout (README Option 2: the kit is cloned to ~/.claude/dwarves-kit)
# must NOT clobber the real hook scripts. Regression: when KIT_DIR == the install
# destination, the per-file link step rm'd each script and replaced it with a
# self-referential broken symlink. Here the scripts must stay resolvable.
INPLACE_HOME=$(mktemp -d)
mkdir -p "$INPLACE_HOME/.claude/dwarves-kit"
cp -R "$KIT_DIR/hooks" "$KIT_DIR/commands" "$KIT_DIR/agents" "$KIT_DIR/skills" \
      "$KIT_DIR/settings.json" "$KIT_DIR/install.sh" "$INPLACE_HOME/.claude/dwarves-kit/" 2>/dev/null
HOME="$INPLACE_HOME" bash "$INPLACE_HOME/.claude/dwarves-kit/install.sh" >/dev/null 2>&1
INPLACE_BROKEN=$(for f in "$INPLACE_HOME/.claude/dwarves-kit/hooks/"*.sh; do [ -f "$f" ] || basename "$f"; done \
  | tr '\n' ' ' | sed 's/ $//')
assert_eq "in-place install keeps hook scripts resolvable (broken: ${INPLACE_BROKEN:-none})" "" "$INPLACE_BROKEN"
rm -rf "$INPLACE_HOME"

echo "=== codebase-memory auto-index hook (SPEC-043) ==="
# ============================================================
# The opt-in SessionStart hook must exist, be executable, be registered in both hook
# registries, and guard on git rev-parse (NOT '[ -d .git ]', which silently skips
# worktrees because .git is a file there).

assert_true "hooks/codebase-index.sh exists and is executable" \
  "$([ -x "$KIT_DIR/hooks/codebase-index.sh" ] && echo 0 || echo 1)"

assert_true "auto-index hook guards on git rev-parse (worktree-correct, not [ -d .git ])" \
  "$(grep -q 'git rev-parse --is-inside-work-tree' "$KIT_DIR/hooks/codebase-index.sh" && ! grep -qE '^\[ -d \.git \]' "$KIT_DIR/hooks/codebase-index.sh" && echo 0 || echo 1)"

assert_true "auto-index hook registered as SessionStart in both registries" \
  "$(grep -q 'codebase-index.sh' "$KIT_DIR/settings.json" && grep -q 'codebase-index.sh' "$KIT_DIR/hooks/hooks.json" && echo 0 || echo 1)"

# ============================================================
echo ""
echo "=== SPEC-083: session-start board wire (ID-033) ==="
# ============================================================
CR83="$KIT_DIR/hooks/context-readiness.sh"
RC=0; grep -qF 'board:${BOARD_Q}q' "$CR83" || RC=1
assert_eq "hook emits the board state token" 0 $RC
RC=0; grep -qF 'Twin of lib/board/backlog.sh _rows' "$CR83" || RC=1
assert_eq "hook documents the parser-twin coupling" 0 $RC
RC=0; grep -qF 'state the task, or /kit:assign --next' "$CR83" || RC=1
assert_eq "queue suggestion is intent-first + assign --next" 0 $RC
RC=0; [ "$(grep -cF "say '" "$CR83")" -ge 4 ] || RC=1
assert_eq "cycle suggestions speak intent-first (4+ say-branches)" 0 $RC
RC=0; grep -qF '`_meta/BACKLOG.md` queue)' "$KIT_DIR/docs/MANUAL.md" || RC=1
assert_eq "MANUAL /kit:start Reads mentions the board" 0 $RC
RC=0; grep -qF 'board:Nq' "$KIT_DIR/docs/MANUAL.md" || RC=1
assert_eq "MANUAL hook row carries the board token" 0 $RC


# ============================================================
echo ""
echo "=== SPEC-084: hook fallback layer (ID-036) ==="
# ============================================================
ARCH84="$KIT_DIR/docs/architecture.md"
RC=0; grep -qF '## Hook fallback layer (closing the layering contract)' "$ARCH84" || RC=1
assert_eq "the section exists" 0 $RC
RC=0; grep -qF 'fallback for failure modes that survive prose instruction' "$ARCH84" || RC=1
assert_eq "the 3-layer fallback rule stated" 0 $RC
RC=0; grep -qF 'survive prose AND the damage is irreversible' "$ARCH84" || RC=1
assert_eq "placement decision test: hard criterion" 0 $RC
# parity: one table row per hooks/*.sh file, both sides computed
HOOK_FILES=$(ls "$KIT_DIR"/hooks/*.sh | wc -l | tr -d ' ')
HOOK_ROWS=$(awk '/^## Hook fallback layer/,/^## [^H]/' "$ARCH84" | grep -cE '^\| `[a-z-]+` \|' || true)
assert_eq "parity: table rows == hook files ($HOOK_FILES)" "$HOOK_FILES" "$HOOK_ROWS"
for H in safety-gate secrets-guard ship-gate commit-format anti-rationalization; do
  RC=0; awk '/^## Hook fallback layer/,/^## [^H]/' "$ARCH84" | grep -E "^\| .$H. \|" | grep -q 'hard' || RC=1
  assert_eq "hard class declared: $H" 0 $RC
done
RC=0; grep -qF 'guardrail = the hard subset' "$ARCH84" || RC=1
assert_eq "C3 reconciliation present (bounded guardrail)" 0 $RC
RC=0; grep -qF 'ID-012 P2' "$ARCH84" && grep -qF 'ID-027' "$ARCH84" || RC=1
assert_eq "folded concerns dispositioned" 0 $RC
RC=0; grep -qF 'autonomous loop' "$KIT_DIR/commands/spec-validate.md" || RC=1
assert_eq "spec-validate Reviewer 4 autonomy-gate bullet" 0 $RC
RC=0; grep -qF 'the hook-fallback layer is still open' "$ARCH84" && RC=1
assert_eq "the still-open marker is gone" 0 $RC
RC=0; grep -qF '"Hook fallback layer"' "$KIT_DIR/AGENTS.md" || RC=1
assert_eq "AGENTS.md points at the layering contract" 0 $RC


# ============================================================
echo ""
echo "=== kit-health symlink check (check 12: broken-symlink detection) ==="
# ============================================================
# Behavioral, not just textual: extract check 12 from kit-health.md's Step-1
# bash block (bounded by its own start/end comments) and run it against a
# synthetic kit root with one good symlink and one dangling one. Regression
# guard for the WORKFLOW.md-after-repo-move incident: a stale symlink under
# the installed kit root went unnoticed until the gate ledger needed a manual
# override.
SYMLINK_FIXTURE=$(mktemp -d)
mkdir -p "$SYMLINK_FIXTURE/kit-root/docs" "$SYMLINK_FIXTURE/real-target"
echo "real" > "$SYMLINK_FIXTURE/real-target/WORKFLOW.md"
ln -s "$SYMLINK_FIXTURE/real-target/WORKFLOW.md" "$SYMLINK_FIXTURE/kit-root/AGENTS.md"          # good
ln -s "$SYMLINK_FIXTURE/real-target/missing.md" "$SYMLINK_FIXTURE/kit-root/docs/WORKFLOW.md"    # dangling

CHECK_SCRIPT=$(sed -n '/^# 12\. Symlink health/,/^# --- end check 12 ---$/p' "$KIT_DIR/commands/kit-health.md")
TOTAL=$((TOTAL + 1))
if [ -z "$CHECK_SCRIPT" ]; then
  echo -e "  ${RED}FAIL${NC} could not extract check 12 from kit-health.md (start/end markers missing)"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC} check 12 extracted from kit-health.md"
  PASS=$((PASS + 1))
fi

CHECK_OUT=$(DWARVES_KIT="$SYMLINK_FIXTURE/kit-root" bash -c "$CHECK_SCRIPT" 2>&1)

TOTAL=$((TOTAL + 1))
if echo "$CHECK_OUT" | grep -q "\[BROKEN\].*docs/WORKFLOW.md"; then
  echo -e "  ${GREEN}PASS${NC} kit-health symlink check reports the dangling docs/WORKFLOW.md link"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health symlink check did not report the dangling link"
  echo "$CHECK_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if echo "$CHECK_OUT" | grep -q "\[BROKEN\].*AGENTS.md"; then
  echo -e "  ${RED}FAIL${NC} kit-health symlink check wrongly flagged the good AGENTS.md link"
  echo "$CHECK_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC} kit-health symlink check leaves the good AGENTS.md link unreported"
  PASS=$((PASS + 1))
fi

TOTAL=$((TOTAL + 1))
if echo "$CHECK_OUT" | grep -qi "re-run install.sh"; then
  echo -e "  ${GREEN}PASS${NC} kit-health symlink check names the fix (re-run install.sh)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health symlink check should point at re-running install.sh"
  FAIL=$((FAIL + 1))
fi

rm -rf "$SYMLINK_FIXTURE"

echo ""
echo "=== Results ==="
# ============================================================
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All meta tests passed.${NC}"
  exit 0
fi
