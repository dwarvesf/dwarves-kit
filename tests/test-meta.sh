#!/bin/bash
# test-meta.sh -- Structural integrity tests for kit artifacts.
# Catches drift the unit tests can't see: version mismatches, missing
# frontmatter, stale references between files, schema violations.
#
# Run: bash tests/test-meta.sh
# Exit 0 = all tests pass. Exit 1 = failures found.
#
# Source: added in v1.5.1 after retro-review of v1.4 and v1.5 surfaced
# a live version drift bug (plugin.json said 1.4.0 while VERSION said 1.5.0).

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

assert_true() {
  local NAME="$1" RC="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$RC" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
echo "=== Plugin manifest schema ==="
# ============================================================

# plugin.json: name, version, description present
PLUGIN_NAME=$(jq -r '.name' "$KIT_DIR/.claude-plugin/plugin.json")
assert_eq "plugin.json name == 'kit'" "kit" "$PLUGIN_NAME"

PLUGIN_VERSION=$(jq -r '.version' "$KIT_DIR/.claude-plugin/plugin.json")
VERSION_FILE=$(cat "$KIT_DIR/VERSION" | tr -d '[:space:]')
assert_eq "plugin.json version matches VERSION file" "$VERSION_FILE" "$PLUGIN_VERSION"

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
      | grep -vE '^(docs/specs/|docs/retro/|docs/decisions/|docs/handoff/|docs/research/|_meta/|CHANGELOG\.md)'; \
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
  [ -e "$TMP_HOME/.claude/dwarves-kit/lib/proof-ledger.sh" ]
  assert_true "install.sh materializes lib/proof-ledger.sh (SPEC-045)" $?
  # SPEC-049: install must materialize the operate-contract too, so adopt (needs a source
  # AGENTS.md) + gate-ledger (reads WORKFLOW.md) work from the install, not only the dev
  # checkout. Asserts the REAL install run, not test-install-contract.sh's simulated layout.
  [ -e "$TMP_HOME/.claude/dwarves-kit/AGENTS.md" ]
  assert_true "install.sh materializes AGENTS.md (SPEC-049)" $?
  [ -e "$TMP_HOME/.claude/dwarves-kit/WORKFLOW.md" ]
  assert_true "install.sh materializes WORKFLOW.md (SPEC-049)" $?
  # SPEC-049: uninstall removes the two contract symlinks (the new uninstall code path).
  HOME="$TMP_HOME" bash "$KIT_DIR/install.sh" --uninstall >/dev/null 2>&1
  { [ ! -L "$TMP_HOME/.claude/dwarves-kit/AGENTS.md" ] && [ ! -L "$TMP_HOME/.claude/dwarves-kit/WORKFLOW.md" ]; }
  assert_true "uninstall removes the AGENTS.md + WORKFLOW.md symlinks (SPEC-049)" $?
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

# ============================================================
echo ""
echo "=== AGENTS.md operating layer (SPEC-024) ==="
# ============================================================
# Part A: pin the cycle's structural outputs so a wording flip fails CI.
#   1. kit-root AGENTS.md exists + carries the four portable zones + the literal
#      "Pause if" + the CC-only-enforcement statement.
#   2. commands/assign.md carries the six-section /goal projection (the writer
#      side of the AGENTS.md->assign.md projection).
#   3. Low-cost regression guards for TASK-003 (hello-spec AGENTS.md) and
#      TASK-006 (spec.md "## After state").

AGENTS_MD="$KIT_DIR/AGENTS.md"
TOTAL=$((TOTAL + 1))
if [ -f "$AGENTS_MD" ]; then
  echo -e "  ${GREEN}PASS${NC} AGENTS.md exists at kit root (SPEC-024)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} AGENTS.md missing at kit root"
  FAIL=$((FAIL + 1))
fi

# The four portable zones (DEC-005). Pin the heading literals, not prose.
for ZONE in "## 1. Read in this order" "## 2. Task loop" "## 3. Done means" "## 4. Pause if (ask a human)"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$ZONE" "$AGENTS_MD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} AGENTS.md has zone '$ZONE'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} AGENTS.md missing zone '$ZONE'"
    FAIL=$((FAIL + 1))
  fi
done

# The literal "Pause if" (the fourth zone's stable phrase, also the goal section).
TOTAL=$((TOTAL + 1))
if grep -qF 'Pause if' "$AGENTS_MD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} AGENTS.md carries the literal 'Pause if'"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} AGENTS.md lost the literal 'Pause if'"
  FAIL=$((FAIL + 1))
fi

# The CC-only-enforcement statement (PHILOSOPHY honesty rule: never over-claim
# portable enforcement). A drift to "enforcement is portable" would be a lie.
TOTAL=$((TOTAL + 1))
if grep -qF 'Enforcement is Claude-Code-only' "$AGENTS_MD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} AGENTS.md states enforcement is Claude-Code-only"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} AGENTS.md lost the CC-only-enforcement statement"
  FAIL=$((FAIL + 1))
fi

# commands/assign.md carries the six-section projection (the writer side). A
# wording flip on any section name breaks the AGENTS.md->assign.md projection.
ASSIGN_MD="$KIT_DIR/commands/assign.md"
for SECTION in "Context-to-read" "Constraints" "Operating rules" "Validation loop" "Done-when" "Pause-if"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$SECTION" "$ASSIGN_MD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} assign.md has projection section '$SECTION'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} assign.md missing projection section '$SECTION'"
    FAIL=$((FAIL + 1))
  fi
done

# Low-cost regression guards: TASK-003 (hello-spec AGENTS.md w/ "Pause if") and
# TASK-006 (spec.md template's "## After state"). Pin both so they cannot silently
# regress.
DEMO_AGENTS="$KIT_DIR/examples/hello-spec/AGENTS.md"
TOTAL=$((TOTAL + 1))
if [ -f "$DEMO_AGENTS" ] && grep -qF 'Pause if' "$DEMO_AGENTS" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} examples/hello-spec/AGENTS.md exists + carries 'Pause if' (TASK-003)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} examples/hello-spec/AGENTS.md missing or lost 'Pause if'"
  FAIL=$((FAIL + 1))
fi

# Review issue 2: the downstream template (the file real projects copy) must pin
# all four zone headings too, not just "Pause if" - same teeth as the kit root.
for ZONE in "## 1. Read in this order" "## 2. Task loop" "## 3. Done means" "## 4. Pause if (ask a human)"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$ZONE" "$DEMO_AGENTS" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} examples/hello-spec/AGENTS.md has zone '$ZONE'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} examples/hello-spec/AGENTS.md missing zone '$ZONE'"
    FAIL=$((FAIL + 1))
  fi
done

TOTAL=$((TOTAL + 1))
if grep -qF '## After state' "$KIT_DIR/commands/spec.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} commands/spec.md template carries '## After state' (TASK-006)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/spec.md template lost '## After state'"
  FAIL=$((FAIL + 1))
fi

# Review issue 6: assign.md Done-when must reference the spec's "## After state"
# (the projection source), not merely carry the "Done-when" label.
TOTAL=$((TOTAL + 1))
if grep -qF '## After state' "$ASSIGN_MD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} assign.md Done-when references the spec's '## After state'"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} assign.md Done-when lost the '## After state' projection source"
  FAIL=$((FAIL + 1))
fi

# Review issue 1 (anti-drift): the spec's primary failure mode is a CC-layer doc
# RESTATING the ordered read-list that AGENTS.md owns (zone 1 is the single source).
# WORKFLOW.md and CLAUDE.md must point, not carry a numbered "1. AGENTS.md /
# 2. CLAUDE.md ..." restatement. A reappearance is drift; fail loudly. Scoped to
# these two CC-layer docs; AGENTS.md itself legitimately carries the list.
for DOC in WORKFLOW.md CLAUDE.md; do
  RESTATE=$(grep -cE '^[0-9]+\.[[:space:]]+(AGENTS|CLAUDE)\.md' "$KIT_DIR/$DOC" 2>/dev/null || true)
  assert_eq "$DOC does not restate the AGENTS.md read-order list (no drift)" "0" "$RESTATE"
done

# ------------------------------------------------------------
# Part B: install.sh merge-with-existing-hooks regression (DEC-004).
# The existing installer test runs into a HOME with NO settings.json, so it never
# exercises the jq clean+merge path. This test pre-seeds settings.json with a
# THIRD-PARTY hook (a command that does NOT contain "dwarves-kit") and asserts the
# merge preserves it, yields valid JSON, and still pulls in a dwarves-kit hook.
MERGE_HOME=$(mktemp -d)
mkdir -p "$MERGE_HOME/.claude"
THIRD_PARTY_CMD="/opt/acme/hooks/audit-log.sh"
# Build the pre-existing settings via jq so it is always well-formed JSON.
jq -n --arg cmd "$THIRD_PARTY_CMD" '{
  hooks: {
    PreToolUse: [
      { matcher: "Bash", hooks: [ { type: "command", command: $cmd } ] }
    ]
  }
}' > "$MERGE_HOME/.claude/settings.json"

HOME="$MERGE_HOME" bash "$KIT_DIR/install.sh" >/dev/null 2>&1
MERGED_SETTINGS="$MERGE_HOME/.claude/settings.json"

# (a) the third-party hook command survived the merge.
TOTAL=$((TOTAL + 1))
if grep -qF "$THIRD_PARTY_CMD" "$MERGED_SETTINGS" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} install merge preserves the third-party hook (DEC-004)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} install merge DROPPED the third-party hook (merge bug)"
  FAIL=$((FAIL + 1))
fi

# (b) the resulting settings.json is valid JSON.
TOTAL=$((TOTAL + 1))
if jq '.' "$MERGED_SETTINGS" >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC} merged settings.json is valid JSON"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} merged settings.json is not valid JSON (merge corrupted it)"
  FAIL=$((FAIL + 1))
fi

# (c) at least one dwarves-kit hook was merged in alongside the third-party one.
TOTAL=$((TOTAL + 1))
KIT_HOOK_COUNT=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | tostring | contains("dwarves-kit"))] | length' "$MERGED_SETTINGS" 2>/dev/null || echo 0)
if [ "${KIT_HOOK_COUNT:-0}" -gt 0 ]; then
  echo -e "  ${GREEN}PASS${NC} install merge added at least one dwarves-kit hook ($KIT_HOOK_COUNT)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} install merge added no dwarves-kit hooks"
  FAIL=$((FAIL + 1))
fi
rm -rf "$MERGE_HOME"

# ============================================================
echo ""
echo "=== Freeform front door (SPEC-026) ==="
# ============================================================
# Pin the SPEC-026 contract in commands/assign.md so a wording flip on any of
# the intake paths, the /kit:think delegation, or the four invariants fails CI.
# All literals exist in assign.md today; this guards them from silent drift.
# ASSIGN_MD is set in the SPEC-024 block above.

# Two-shape resolver: the ID-first regex AND the freeform branch must both be named.
for LITERAL in '^ID-[0-9]+$' 'freeform'; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$LITERAL" "$ASSIGN_MD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} assign.md documents the '$LITERAL' intake shape (SPEC-026)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} assign.md lost the '$LITERAL' intake shape (resolver drift)"
    FAIL=$((FAIL + 1))
  fi
done

# Delegation: the crystallize interview is delegated to /kit:think, not embedded (DEC-003).
TOTAL=$((TOTAL + 1))
if grep -qF '/kit:think' "$ASSIGN_MD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} assign.md delegates crystallize to /kit:think (SPEC-026 DEC-003)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} assign.md lost the /kit:think delegation (interview embedded?)"
  FAIL=$((FAIL + 1))
fi

# The four invariants. atomic-allocate is pinned via BOTH its named marker and the
# 'collision' guard wording, since both literals are load-bearing in assign.md.
for INVARIANT in 'row-before-draft' 'approve-before-allocate' 'sanitize' 'atomic-allocate' 'collision'; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$INVARIANT" "$ASSIGN_MD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} assign.md pins the '$INVARIANT' invariant (SPEC-026)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} assign.md lost the '$INVARIANT' invariant (contract drift)"
    FAIL=$((FAIL + 1))
  fi
done

# Slug hardening: the sanitized slug charset must stay pinned (path-traversal guard).
TOTAL=$((TOTAL + 1))
if grep -qF '[a-z0-9-]' "$ASSIGN_MD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} assign.md pins the '[a-z0-9-]' slug charset (SPEC-026 DEC-004)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} assign.md lost the '[a-z0-9-]' slug charset (slug hardening drift)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Agent files ==="
# ============================================================

# Each agent has YAML frontmatter with name + description
for AGENT_FILE in "$KIT_DIR/agents/"*.md; do
  AGENT=$(basename "$AGENT_FILE" .md)
  HEAD3=$(head -1 "$AGENT_FILE")
  assert_eq "agent $AGENT starts with ---" "---" "$HEAD3"
  HAS_NAME=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^name:/' "$AGENT_FILE" | wc -l | tr -d ' ')
  assert_eq "agent $AGENT has name field" "1" "$HAS_NAME"
  HAS_DESC=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^description:/' "$AGENT_FILE" | wc -l | tr -d ' ')
  assert_eq "agent $AGENT has description field" "1" "$HAS_DESC"
  # model: must be present and one of the accepted Claude Code model aliases.
  # Same structural-parity intent as the plugin.json version check: grep-only
  # presence isn't enough, the value has to be in the real model surface.
  MODEL_VAL=$(awk -F': *' '/^---$/{c++; if(c==2)exit} c==1 && /^model:/{print $2; exit}' "$AGENT_FILE" | tr -d '[:space:]')
  TOTAL=$((TOTAL + 1))
  if echo "$MODEL_VAL" | grep -qE '^(sonnet|haiku|opus)$'; then
    echo -e "  ${GREEN}PASS${NC} agent $AGENT model is sonnet|haiku|opus ($MODEL_VAL)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} agent $AGENT model invalid or missing ('$MODEL_VAL')"
    FAIL=$((FAIL + 1))
  fi
done

# MANUAL.md agent table cross-refs match agents/ files.
# Canonical agent inventory is in MANUAL.md "Agents" section (table rows).
# CLAUDE.md no longer mirrors the inventory; see docs/architecture.md for component fit.
SUBAGENT_NAMES=$(grep '^| `' "$KIT_DIR/MANUAL.md" | sed 's/^| `\([^`]*\)`.*/\1/' | sort -u)
for NAME in $SUBAGENT_NAMES; do
  if [ -f "$KIT_DIR/agents/$NAME.md" ]; then
    TOTAL=$((TOTAL + 1))
    echo -e "  ${GREEN}PASS${NC} MANUAL.md row '$NAME' has agents/$NAME.md"
    PASS=$((PASS + 1))
  fi
done

# Reverse: every agent file mentioned in MANUAL.md as a table row.
for AGENT_FILE in "$KIT_DIR/agents/"*.md; do
  AGENT=$(basename "$AGENT_FILE" .md)
  TOTAL=$((TOTAL + 1))
  if grep -q "^| \`$AGENT\` " "$KIT_DIR/MANUAL.md"; then
    echo -e "  ${GREEN}PASS${NC} agent $AGENT listed in MANUAL.md"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} agent $AGENT NOT listed in MANUAL.md"
    FAIL=$((FAIL + 1))
  fi
done

# ============================================================
echo ""
echo "=== Command files ==="
# ============================================================

for CMD_FILE in "$KIT_DIR/commands/"*.md; do
  CMD=$(basename "$CMD_FILE" .md)
  HEAD1=$(head -1 "$CMD_FILE")
  assert_eq "command $CMD starts with ---" "---" "$HEAD1"
  HAS_DESC=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^description:/' "$CMD_FILE" | wc -l | tr -d ' ')
  assert_eq "command $CMD has description field" "1" "$HAS_DESC"
done

# SPEC-011: the opt-in /kit:design command must exist (the frontmatter loop above
# covers its shape; this asserts presence so a deletion fails CI).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/commands/design.md" ]; then
  echo -e "  ${GREEN}PASS${NC} commands/design.md exists (/kit:design lane)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/design.md missing"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Spec / ADR number-collision guard (shared-branch numbering) ==="
# ============================================================
# Two sessions assigning SPEC-NNN / ADR-NNNN against the same tree both read the
# same max and pick max+1, colliding (surfaced only at merge). This turns that
# silent collision into a loud CI failure. Allocation rule + conflict resolution
# live in docs/specs/README.md ("Concurrent numbering").

DUP_SPECS=$(ls "$KIT_DIR/docs/specs/" | grep -oE '^SPEC-[0-9]+' | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')
assert_eq "no duplicate SPEC numbers (dups: ${DUP_SPECS:-none})" "" "$DUP_SPECS"

DUP_ADRS=$(ls "$KIT_DIR/docs/decisions/" | grep -oE '^[0-9]+' | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')
assert_eq "no duplicate ADR numbers (dups: ${DUP_ADRS:-none})" "" "$DUP_ADRS"

# ============================================================
echo ""
echo "=== Debug loop (SPEC-013) ==="
# ============================================================
# The /kit:debug command must exist and carry its load-bearing structure,
# and the guess-fix guard's ledger contract must stay in sync with the hook.

DEBUG_CMD="$KIT_DIR/commands/debug.md"
TOTAL=$((TOTAL + 1))
if [ -f "$DEBUG_CMD" ]; then
  echo -e "  ${GREEN}PASS${NC} commands/debug.md exists (/kit:debug, bug lane)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/debug.md missing"
  FAIL=$((FAIL + 1))
fi

for HEADING in "## Phase 1: Root cause" "## Phase 2: Pattern" "## Phase 3: Hypothesis" "## Phase 4: Implementation"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$HEADING" "$DEBUG_CMD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} debug.md has '$HEADING'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} debug.md missing '$HEADING'"
    FAIL=$((FAIL + 1))
  fi
done

for MARKER in "NO FIX WITHOUT A RECORDED ROOT CAUSE" "git bisect" "3-fix architecture wall"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$MARKER" "$DEBUG_CMD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} debug.md carries '$MARKER'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} debug.md missing '$MARKER'"
    FAIL=$((FAIL + 1))
  fi
done

# DEC-010: the guard's ledger heading "## Root cause" must appear in BOTH the
# command (which writes the ledger) and the hook (which greps it). A rename on
# one side would silently disable the guard; pinning both literals breaks the
# build instead.
RAT_HOOK="$KIT_DIR/hooks/anti-rationalization.sh"
for FILE in "$DEBUG_CMD" "$RAT_HOOK"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF '## Root cause' "$FILE" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} '$(basename "$FILE")' pins the literal '## Root cause' (DEC-010)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} '$(basename "$FILE")' lost the '## Root cause' contract (guard would silently break)"
    FAIL=$((FAIL + 1))
  fi
done

# WORKFLOW.md must carry the bug lane that routes to /debug.
TOTAL=$((TOTAL + 1))
if grep -qE '^\| bug ' "$KIT_DIR/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has the bug lane"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing the bug lane"
  FAIL=$((FAIL + 1))
fi

# SPEC-018 DEC-003/DEC-006: the `## Test plan` heading is the writer/reader
# contract; it must appear in BOTH test-plan.md (writer) and execute.md (reader).
# A rename on one side silently disables execute's consumption of the plan.
TP_CMD="$KIT_DIR/commands/test-plan.md"
EXEC_CMD="$KIT_DIR/commands/execute.md"
for FILE in "$TP_CMD" "$EXEC_CMD"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF '## Test plan' "$FILE" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} '$(basename "$FILE")' pins the literal '## Test plan' (SPEC-018)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} '$(basename "$FILE")' lost the '## Test plan' contract (execute would silently read no plan)"
    FAIL=$((FAIL + 1))
  fi
done

# SPEC-018 DEC-005: the test-plan matrix must carry the proof column.
TOTAL=$((TOTAL + 1))
if grep -qiF 'proof' "$TP_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md carries the 'proof' column (SPEC-018 DEC-005)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md dropped the 'proof' column"
  FAIL=$((FAIL + 1))
fi

# SPEC-018 DEC-001: test-plan writes into the spec, not a root TEST-PLAN.md.
TOTAL=$((TOTAL + 1))
if grep -qF 'TEST-PLAN.md' "$TP_CMD" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC} test-plan.md still references a root TEST-PLAN.md (should write into the spec)"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC} test-plan.md writes into the spec, no root TEST-PLAN.md (SPEC-018 DEC-001)"
  PASS=$((PASS + 1))
fi

# ============================================================
echo ""
echo "=== Concurrency-safe review placement (## Review in the spec) ==="
# ============================================================
# Review output is concurrency-safe: it lives in the active spec as a `## Review`
# section, never a fixed-name root file two worktrees/sessions could clobber. Pin
# the writer/reader/home contract (same drift-guard shape as `## Test plan`):
# spec.md documents the home, review + review-team write it, ship reads its verdict.
REVIEW_CMD="$KIT_DIR/commands/review.md"
RT_CMD="$KIT_DIR/commands/review-team.md"
SHIP_CMD="$KIT_DIR/commands/ship.md"
for FILE in "$KIT_DIR/commands/spec.md" "$REVIEW_CMD" "$RT_CMD" "$SHIP_CMD"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF '## Review' "$FILE" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} '$(basename "$FILE")' carries the '## Review' spec-section contract"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} '$(basename "$FILE")' lost the '## Review' contract (review placement drift)"
    FAIL=$((FAIL + 1))
  fi
done

# No command may write or read a fixed-name root review/todo file (the thing the
# move removes). A `REVIEW.md` / `REVIEW-*.md` / `TODOS.md` mention in review,
# review-team, ship, or start is a regression back to the shared-namespace design.
ROOT_REVIEW_HITS=$(grep -lE 'REVIEW\.md|REVIEW-[a-z]|TODOS\.md' \
  "$REVIEW_CMD" "$RT_CMD" "$SHIP_CMD" "$KIT_DIR/commands/start.md" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
assert_eq "no fixed-name REVIEW*/TODOS root file in review/ship/start (offenders: ${ROOT_REVIEW_HITS:-none})" "" "$ROOT_REVIEW_HITS"

# SPEC-023: devs-team + visual-team write their critiques spec-first. Pin the
# wording on both of devs-team's sides (read AND write) so a one-sided flip back
# to brief-first fails the suite. No command reads these critiques (human-facing),
# so a wording pin is the right guard, not a writer/reader drift-guard.
DT_CMD="$KIT_DIR/commands/devs-team.md"
VT_CMD="$KIT_DIR/commands/visual-team.md"
TOTAL=$((TOTAL + 1))
if grep -qF 'spec-first' "$DT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} devs-team.md reads the design spec-first (SPEC-023)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} devs-team.md lost its spec-first read (reverted to brief-first?)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'the active spec if present, else the pre-spec brief' "$DT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} devs-team.md writes the critique spec-first (SPEC-023)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} devs-team.md lost its spec-first write target (reverted to brief-first?)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'spec-first' "$VT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} visual-team.md writes the critique spec-first (SPEC-023)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} visual-team.md lost its spec-first placement"
  FAIL=$((FAIL + 1))
fi

# SPEC-052: the test-plan-review-team lane. Pin the literal `## Test plan critique`
# heading + the `spec-first` write target (same drift-guard shape as devs-team's
# critique, SPEC-023). No command reads this critique (human-facing), so a wording
# pin is the right guard. Also pin the bounded-loop contract it must carry.
TPRT_CMD="$KIT_DIR/commands/test-plan-review-team.md"
TOTAL=$((TOTAL + 1))
if [ -f "$TPRT_CMD" ] && grep -qF '## Test plan critique' "$TPRT_CMD" && grep -qF 'spec-first' "$TPRT_CMD"; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md exists + writes '## Test plan critique' spec-first (SPEC-052)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md missing or lost its '## Test plan critique' / spec-first contract"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF '[[QL-VERDICT' "$TPRT_CMD" 2>/dev/null && grep -qF 'test-design-standard.md' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md carries the QL-VERDICT loop + encodes test-design-standard.md (SPEC-052)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md lost the QL-VERDICT loop or the standard reference"
  FAIL=$((FAIL + 1))
fi

# SPEC-020: the ui-design loop. Assert the command exists, delegates generation
# to frontend-design (the kit ships no renderer), critiques via visual-team, and
# carries the `## UI design` brief heading. Downstream-facing; no behavior harness.
UID_CMD="$KIT_DIR/commands/ui-design.md"
TOTAL=$((TOTAL + 1))
if [ -f "$UID_CMD" ] && grep -qF 'frontend-design' "$UID_CMD" && grep -qF '## UI design' "$UID_CMD" && grep -qF 'visual-team' "$UID_CMD"; then
  echo -e "  ${GREEN}PASS${NC} ui-design.md exists + delegates generation + critiques via visual-team (SPEC-020)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} ui-design.md missing or not wired (needs frontend-design + visual-team + '## UI design')"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Integration-checker (SPEC-021) ==="
# ============================================================
# The cross-task wiring verifier must exist, stay read-only (no write tools in
# its frontmatter), and be dispatched by /execute. The generic agent-loop above
# already checks its name/description/model and the MANUAL cross-ref.

ICA="$KIT_DIR/agents/integration-checker.md"
TOTAL=$((TOTAL + 1))
if [ -f "$ICA" ]; then
  echo -e "  ${GREEN}PASS${NC} agents/integration-checker.md exists"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} agents/integration-checker.md missing"
  FAIL=$((FAIL + 1))
fi

# Read-only contract: no bare Bash and no Edit/Write/MultiEdit in the tools list.
# Scoped Bash(...) entries do not match (they have a paren), so they are allowed.
WRITE_TOOLS=$(grep -cE '^[[:space:]]*-[[:space:]]+(Edit|Write|MultiEdit|Bash)[[:space:]]*$' "$ICA" 2>/dev/null || true)
assert_eq "integration-checker has no write/bare-Bash tools (DEC-006)" "0" "$WRITE_TOOLS"

TOTAL=$((TOTAL + 1))
if grep -q 'integration-checker' "$KIT_DIR/commands/execute.md" 2>/dev/null \
   && grep -q 'base ref' "$KIT_DIR/commands/execute.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} commands/execute.md dispatches the integration-checker with a base ref"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/execute.md does not wire the integration-checker (+base ref)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Doc-verifier (SPEC-022) ==="
# ============================================================
# The doc-vs-code fact-checker must exist, stay read-only (no write tools), and
# be dispatched by /docs. The generic agent-loop above checks name/desc/model
# and the MANUAL cross-ref.

DVA="$KIT_DIR/agents/doc-verifier.md"
TOTAL=$((TOTAL + 1))
if [ -f "$DVA" ]; then
  echo -e "  ${GREEN}PASS${NC} agents/doc-verifier.md exists"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} agents/doc-verifier.md missing"
  FAIL=$((FAIL + 1))
fi

DV_WRITE=$(grep -cE '^[[:space:]]*-[[:space:]]+(Edit|Write|MultiEdit|Bash)[[:space:]]*$' "$DVA" 2>/dev/null || true)
assert_eq "doc-verifier has no write/bare-Bash tools (DEC-002)" "0" "$DV_WRITE"

TOTAL=$((TOTAL + 1))
if grep -q 'doc-verifier' "$KIT_DIR/commands/docs.md" 2>/dev/null \
   && grep -q 'Step 4.5' "$KIT_DIR/commands/docs.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} commands/docs.md dispatches the doc-verifier at Step 4.5"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/docs.md does not wire the doc-verifier (+Step 4.5)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Spec-authoring depth contract (SPEC-008) ==="
# ============================================================
# The /spec Solution template must scaffold design depth (2-3 approaches +
# chosen + extensibility), and /spec-validate must carry the 5th reviewer.
# Assert on heading/marker presence only, not prose, to avoid brittle coupling.

SPEC_CMD="$KIT_DIR/commands/spec.md"
for HEADING in "### Approaches considered" "### Chosen approach" "### Extensibility & boundaries"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$HEADING" "$SPEC_CMD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} spec.md Solution template has '$HEADING'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} spec.md Solution template missing '$HEADING'"
    FAIL=$((FAIL + 1))
  fi
done

# SPEC-009: the I/O contract (under Technical Design) + the Failure modes section.
for HEADING in "### Interfaces (I/O contract)" "## Failure modes"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$HEADING" "$SPEC_CMD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} spec.md template has '$HEADING'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} spec.md template missing '$HEADING'"
    FAIL=$((FAIL + 1))
  fi
done

# SPEC-012 P1: the /spec template carries goal stop-criteria (so any spec is pointer-/goal-ready).
for HEADING in "## Verification" "## Open questions"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$HEADING" "$SPEC_CMD" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} spec.md template has '$HEADING'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} spec.md template missing '$HEADING'"
    FAIL=$((FAIL + 1))
  fi
done

# SPEC-010 + concurrency sweep (ADR-0010): docs/specs/ is the SOLE spec location;
# the legacy .planning/ deprecation fallback is fully removed from every live surface
# (commands, hooks, agents). No exception remains -- ANY .planning ref in these dirs
# is a regression. (Dated ledgers under docs/specs|decisions|retro may still name it
# as history; this file names it to describe the guard, so tests/ is not scanned.)
STRAY_PLANNING=$(grep -rn '\.planning' "$KIT_DIR/commands/" "$KIT_DIR/hooks/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no .planning/ refs in commands/ or hooks/ (fallback removed)" "0" "$STRAY_PLANNING"

# SPEC-005: the state model is documented (the dual-mode detection itself is
# behavior-tested in test-hooks.sh). Backlog schema + architecture state-model
# section + the goal-registry ADR must exist; agents/ carry no stray .planning ref.
TOTAL=$((TOTAL + 1))
if grep -qF '## Schema' "$KIT_DIR/_meta/BACKLOG.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} BACKLOG.md has the Active-queue Schema section (SPEC-005)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} BACKLOG.md missing the Schema section"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF '## State model' "$KIT_DIR/docs/architecture.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} architecture.md has the State model section (SPEC-005)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} architecture.md missing the State model section"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/docs/decisions/0011-goal-registry.md" ]; then
  echo -e "  ${GREEN}PASS${NC} ADR-0011 goal-registry exists (SPEC-005)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} ADR-0011 goal-registry missing"
  FAIL=$((FAIL + 1))
fi

# SPEC-005 TASK-2 + concurrency sweep: agents/ carry no .planning ref at all (the
# legacy fallback pointers in task-verifier/responding-to-review were removed).
STRAY_PLANNING_AGENTS=$(grep -rn '\.planning' "$KIT_DIR/agents/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no .planning/ refs in agents/ (fallback removed)" "0" "$STRAY_PLANNING_AGENTS"

# SPEC-006: the orchestration spine is documented + /kit:assign exists.
WF_SPINE="$KIT_DIR/WORKFLOW.md"
for HEADING in "## The spine" "#### Doc-impact map"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$HEADING" "$WF_SPINE" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has '$HEADING' (SPEC-006)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing '$HEADING'"
    FAIL=$((FAIL + 1))
  fi
done
TOTAL=$((TOTAL + 1))
if grep -qF 'Build decisions' "$WF_SPINE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md documents the Build-decisions convention (SPEC-006)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing the Build-decisions convention"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/commands/assign.md" ]; then
  echo -e "  ${GREEN}PASS${NC} commands/assign.md exists (/kit:assign, SPEC-006)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/assign.md missing"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'Loop boundaries' "$KIT_DIR/docs/PHILOSOPHY.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} PHILOSOPHY has the bounded/unbounded loop note (SPEC-006)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} PHILOSOPHY missing the loop-boundaries note"
  FAIL=$((FAIL + 1))
fi

# SPEC-016: the three opt-in critique/test lanes exist.
for CMD in devs-team visual-team test-plan; do
  TOTAL=$((TOTAL + 1))
  if [ -f "$KIT_DIR/commands/$CMD.md" ]; then
    echo -e "  ${GREEN}PASS${NC} commands/$CMD.md exists (/kit:$CMD, SPEC-016)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} commands/$CMD.md missing"
    FAIL=$((FAIL + 1))
  fi
done

# SPEC-017: /kit:execute expands tasks into bite-sized steps.
TOTAL=$((TOTAL + 1))
if grep -qF 'bite-sized steps' "$KIT_DIR/commands/execute.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} execute.md has the bite-sized step-expansion marker (SPEC-017)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} execute.md missing the bite-sized step-expansion marker"
  FAIL=$((FAIL + 1))
fi

# SPEC-004: the absorption ritual + the /kit:absorb command exist with their contract.
ABS_DOC="$KIT_DIR/docs/ABSORPTION.md"
for HEADING in "## The external lane" "## Interest areas" "## Seed list" "## The adoption rubric" "## The gate"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$HEADING" "$ABS_DOC" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} ABSORPTION.md has '$HEADING' (SPEC-004)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} ABSORPTION.md missing '$HEADING'"
    FAIL=$((FAIL + 1))
  fi
done
for ABSFILE in "docs/ABSORPTION.md" "docs/absorption/TEMPLATE.md" "docs/absorption/README.md" "commands/absorb.md"; do
  TOTAL=$((TOTAL + 1))
  if [ -f "$KIT_DIR/$ABSFILE" ]; then
    echo -e "  ${GREEN}PASS${NC} $ABSFILE exists (SPEC-004)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $ABSFILE missing"
    FAIL=$((FAIL + 1))
  fi
done
# the DATA-not-instructions guard must survive in /kit:absorb (it scores untrusted fetched content)
TOTAL=$((TOTAL + 1))
if grep -qF 'DATA, never instructions' "$KIT_DIR/commands/absorb.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} commands/absorb.md keeps the DATA-not-instructions guard (SPEC-004)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/absorb.md lost the DATA-not-instructions guard"
  FAIL=$((FAIL + 1))
fi

# Review issue 5: verdict vocabulary pinned so devs-team/visual-team cannot drift apart.
for VERDICTFILE in "commands/devs-team.md" "commands/visual-team.md"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "SOLID / REVISE / RECONSIDER" "$KIT_DIR/$VERDICTFILE" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} $VERDICTFILE carries the shared verdict vocabulary (SOLID / REVISE / RECONSIDER)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $VERDICTFILE missing the shared verdict vocabulary (SOLID / REVISE / RECONSIDER)"
    FAIL=$((FAIL + 1))
  fi
done

VALIDATE_CMD="$KIT_DIR/commands/spec-validate.md"
TOTAL=$((TOTAL + 1))
if grep -qE "^### Reviewer 5:" "$VALIDATE_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} spec-validate.md has Reviewer 5 (design/extensibility)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} spec-validate.md missing Reviewer 5"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF "## The 5 reviewers" "$VALIDATE_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} spec-validate.md header says 5 reviewers"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} spec-validate.md header not updated to 5 reviewers"
  FAIL=$((FAIL + 1))
fi

# Count-drift guard: no live "4 reviewer(s)" reference may remain in the command
# (the heading, frontmatter, and output-format intro must all agree). Historical
# "4 reviewers run <date>" lines live in docs/specs/, not here, so this file is safe
# to assert clean. Caught a real regression in the SPEC-008 review.
STALE_COUNT=$(grep "4 reviewer" "$VALIDATE_CMD" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "spec-validate.md has no stale '4 reviewer' references" "0" "$STALE_COUNT"

# ============================================================
echo ""
echo "=== Demo project (examples/hello-spec) ==="
# ============================================================

DEMO_DIR="$KIT_DIR/examples/hello-spec"

for f in README.md CLAUDE.md docs/specs/SPEC-001-version-flag.md; do
  TOTAL=$((TOTAL + 1))
  if [ -f "$DEMO_DIR/$f" ]; then
    echo -e "  ${GREEN}PASS${NC} examples/hello-spec/$f exists"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} examples/hello-spec/$f missing"
    FAIL=$((FAIL + 1))
  fi
done

# Demo SPEC.md must contain the standard sections
for SECTION in "## Problem" "## Solution" "## Technical Design" "## Task Breakdown" "## Acceptance Criteria" "## Edge Cases" "## Out of Scope" "## Decision Log"; do
  TOTAL=$((TOTAL + 1))
  if grep -q "^${SECTION}" "$DEMO_DIR/docs/specs/SPEC-001-version-flag.md" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} demo SPEC has '$SECTION'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} demo SPEC missing '$SECTION'"
    FAIL=$((FAIL + 1))
  fi
done

# Demo CLAUDE.md must have kit-template sections
for SECTION in "## Project" "## Tech Stack" "## Commands" "## Repository Structure" "## Code Quality Rules" "## Workflow" "## Spec Location"; do
  TOTAL=$((TOTAL + 1))
  if grep -q "^${SECTION}" "$DEMO_DIR/CLAUDE.md" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} demo CLAUDE.md has '$SECTION'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} demo CLAUDE.md missing '$SECTION'"
    FAIL=$((FAIL + 1))
  fi
done

# ============================================================
echo ""
echo "=== Workflow file ==="
# ============================================================

WF="$KIT_DIR/.github/workflows/test.yml"
TOTAL=$((TOTAL + 1))
if [ -f "$WF" ]; then
  echo -e "  ${GREEN}PASS${NC} .github/workflows/test.yml exists"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} workflow file missing"
  FAIL=$((FAIL + 1))
fi

# Heuristic YAML structure (no python/yq dep): top-level keys present
for KEY in "^name:" "^on:" "^jobs:"; do
  TOTAL=$((TOTAL + 1))
  if grep -q "$KEY" "$WF"; then
    echo -e "  ${GREEN}PASS${NC} workflow has top-level '$KEY'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} workflow missing '$KEY'"
    FAIL=$((FAIL + 1))
  fi
done

# Permissions block (security best practice)
TOTAL=$((TOTAL + 1))
if grep -q "^permissions:" "$WF"; then
  echo -e "  ${GREEN}PASS${NC} workflow has explicit permissions block"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} workflow missing permissions block (security warning)"
  FAIL=$((FAIL + 1))
fi

# Test runner step references the actual test file
TOTAL=$((TOTAL + 1))
if grep -q "tests/test-hooks.sh" "$WF"; then
  echo -e "  ${GREEN}PASS${NC} workflow references tests/test-hooks.sh"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} workflow does not reference tests/test-hooks.sh"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== CONTRIBUTING.md cross-links ==="
# ============================================================

if [ -f "$KIT_DIR/CONTRIBUTING.md" ]; then
  # Extract relative .md links and check each path exists
  RELATIVE_LINKS=$(grep -oE '\[`?[^]]+`?\]\(([^)]+\.md)\)' "$KIT_DIR/CONTRIBUTING.md" | grep -oE '\(([^)]+\.md)\)' | tr -d '()')
  for LINK in $RELATIVE_LINKS; do
    # Skip absolute URLs
    case "$LINK" in http*) continue ;; esac
    TOTAL=$((TOTAL + 1))
    if [ -f "$KIT_DIR/$LINK" ]; then
      echo -e "  ${GREEN}PASS${NC} link '$LINK' resolves"
      PASS=$((PASS + 1))
    else
      echo -e "  ${RED}FAIL${NC} broken link in CONTRIBUTING.md: '$LINK'"
      FAIL=$((FAIL + 1))
    fi
  done
fi

# ============================================================
echo ""
echo "=== WORKFLOW.md contract ==="
# ============================================================

WF_ROOT="$KIT_DIR/WORKFLOW.md"
WF_DEMO="$KIT_DIR/examples/hello-spec/WORKFLOW.md"

# Kit-root WORKFLOW.md carries the four pinned sections (matched on ASCII prefixes
# so the grep cannot drift on a parenthetical or a Unicode glyph in the header).
for SECTION in "^## Required reading" "^## Size the work first" "^## The cycle" "^## Completion contract"; do
  TOTAL=$((TOTAL + 1))
  if grep -q "$SECTION" "$WF_ROOT" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has '$SECTION'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing '$SECTION'"
    FAIL=$((FAIL + 1))
  fi
done

# Both the downstream template and the kit root now use docs/specs/ (post-unify, SPEC-010).
# (ADR-0002). Asserting each in its own file catches a copy-paste path error.
TOTAL=$((TOTAL + 1))
if grep -qF 'docs/specs/' "$WF_DEMO" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} examples/hello-spec/WORKFLOW.md uses docs/specs/"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} examples/hello-spec/WORKFLOW.md missing docs/specs/"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'docs/specs/' "$WF_ROOT" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md uses docs/specs/ convention"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing docs/specs/ convention"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Mid-flight amend convention (SPEC-027) ==="
# ============================================================
# Pin the BUILDING -> SPECIFYING -> BUILDING amend convention across its four
# surfaces so a wording flip on any of them fails CI. WORKFLOW.md is the canonical
# home of the rule; the other three are projections/the model row that point at it.

# (a) execute.md reroutes the "don't modify the spec" anti-pattern to the declared
# amend path: it must reference BOTH "amend" and "checkpoint".
TOTAL=$((TOTAL + 1))
if grep -qF 'amend' "$KIT_DIR/commands/execute.md" 2>/dev/null \
   && grep -qF 'checkpoint' "$KIT_DIR/commands/execute.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} execute.md references the amend path (amend + checkpoint) (SPEC-027)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} execute.md lost the amend path (needs amend + checkpoint)"
  FAIL=$((FAIL + 1))
fi

# (b) WORKFLOW.md is the canonical home: it must carry the "Mid-flight amend" rule.
TOTAL=$((TOTAL + 1))
if grep -qF 'Mid-flight amend' "$KIT_DIR/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md documents the Mid-flight amend rule (SPEC-027, canonical)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md lost the Mid-flight amend rule"
  FAIL=$((FAIL + 1))
fi

# (c) spec.md documents the optional on-demand "## Amendments" provenance section.
TOTAL=$((TOTAL + 1))
if grep -qF '## Amendments' "$KIT_DIR/commands/spec.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} spec.md documents the '## Amendments' section (SPEC-027)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} spec.md lost the '## Amendments' section"
  FAIL=$((FAIL + 1))
fi

# (d) architecture.md "## SDLC state machine" carries the BUILDING -> SPECIFYING amend
# transition row. Pin the whole row (From cell BUILDING, the amend trigger, To cell
# SPECIFYING) so the model stays legible; brittle-proofed via the full-row regex.
# (This guard moved here when the operating-layer-vision doc was folded into architecture.md.)
TOTAL=$((TOTAL + 1))
if grep -qE '\| BUILDING \|.*amend the spec.*\| SPECIFYING' "$KIT_DIR/docs/architecture.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} architecture.md has the BUILDING -> SPECIFYING amend row (SPEC-027)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} architecture.md lost the BUILDING -> SPECIFYING amend transition row"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Release-hygiene guard (SPEC-028) ==="
# ============================================================
# Pin the PRESENCE of the phantom-cut warn on its two surfaces so a deletion or a
# wording flip fails CI. DEC-004: assert the surfaces carry the check, NEVER that
# the working tree is currently tag-clean ("VERSION named but untagged" is a
# legitimate transient during a release and CI often does not fetch tags). So we
# grep the command-prompt files; we never run the phantom-cut check against the repo.

# (a) ship.md (Step 4a) carries the phantom-cut / git-tag check AND the warn-not-block stance.
TOTAL=$((TOTAL + 1))
if grep -qF 'git tag -l' "$KIT_DIR/commands/ship.md" 2>/dev/null \
   && grep -qiF 'phantom' "$KIT_DIR/commands/ship.md" 2>/dev/null \
   && grep -qiF 'warn, not block' "$KIT_DIR/commands/ship.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} ship.md carries the release-hygiene warn (phantom-cut git-tag check + warn-not-block) (SPEC-028)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} ship.md lost the release-hygiene warn (needs git-tag phantom-cut check + warn-not-block stance)"
  FAIL=$((FAIL + 1))
fi

# (b) kit-health.md carries the phantom-cut check.
TOTAL=$((TOTAL + 1))
if grep -qF 'git tag -l' "$KIT_DIR/commands/kit-health.md" 2>/dev/null \
   && grep -qiF 'phantom' "$KIT_DIR/commands/kit-health.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} kit-health.md carries the phantom-cut check (git-tag check + phantom) (SPEC-028)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health.md lost the phantom-cut check (needs git-tag check + phantom)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== V-model lens, convergence, and inventory parity (SPEC-031) ==="
# ============================================================

# (a) No "8 (workflow|lifecycle )?phases" string in operating surfaces.
# Scope: docs/, commands/, WORKFLOW.md, README.md, MANUAL.md, AGENTS.md --
# EXCLUDING docs/specs/, docs/decisions/, docs/research/, docs/retro/, docs/handoff/
# (AMEND-001: archive dirs are point-in-time and may reference old counts -- a retro
# that documents the fix must be free to quote the forbidden string; only live
# surfaces are checked).
PHASES_8_HITS=$(cd "$KIT_DIR" && grep -rIn \
  --exclude-dir=research --exclude-dir=specs --exclude-dir=decisions \
  --exclude-dir=retro --exclude-dir=handoff \
  -E "8 (workflow|lifecycle )?phases" \
  docs/ commands/ WORKFLOW.md README.md MANUAL.md AGENTS.md 2>/dev/null | head -1)
TOTAL=$((TOTAL + 1))
if [ -z "$PHASES_8_HITS" ]; then
  echo -e "  ${GREEN}PASS${NC} no '8 (workflow|lifecycle )?phases' string in operating surfaces (SPEC-031, AMEND-001)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} stale '8 phases' string found in operating surfaces (SPEC-031, AMEND-001)"
  echo "    first hit: $PHASES_8_HITS" >&2
  FAIL=$((FAIL + 1))
fi

# (b) WORKFLOW.md carries both "## The V-model lens" and "## Lead-owned convergence"
# sections, and the lens section lists every phase name from the cycle table.
#
# Implementation notes (simplification logged):
# - Phase names are extracted from the cycle table (## The cycle ... ## The V-model lens).
# - The "UI design (opt-in, downstream)" cycle-table entry is abbreviated to
#   "UI design (opt-in)" in the lens's phase-names sentence. We strip the
#   ", downstream" qualifier before matching so the test is not brittle to this
#   intentional abbreviation. All other phase names are matched verbatim.
# - We assert BOTH section headings PLUS each phase name within the lens block,
#   not merely heading existence, so the test is not silently weakened.
TOTAL=$((TOTAL + 1))
if grep -q "^## The V-model lens" "$KIT_DIR/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has '## The V-model lens' section (SPEC-031)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing '## The V-model lens' section"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q "^## Lead-owned convergence" "$KIT_DIR/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has '## Lead-owned convergence' section (SPEC-031)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing '## Lead-owned convergence' section"
  FAIL=$((FAIL + 1))
fi

# Extract phase names from the cycle table (column 1, skipping header and separator).
# Then check each (after stripping ", downstream" qualifier) appears in the lens section.
LENS_SECTION=$(sed -n '/^## The V-model lens/,/^## /p' "$KIT_DIR/WORKFLOW.md")
CYCLE_PHASES=$(sed -n '/^## The cycle/,/^## The V-model lens/p' "$KIT_DIR/WORKFLOW.md" \
  | grep "^| " | grep -v "^| Phase\|^|---" \
  | sed 's/^| \([^|]*\)|.*/\1/' | sed 's/[[:space:]]*$//')
TOTAL=$((TOTAL + 1))
if [ "$(printf '%s\n' "$CYCLE_PHASES" | grep -c .)" -ge 13 ]; then
  echo -e "  ${GREEN}PASS${NC} CYCLE_PHASES extracted >= 13 entries (extraction not vacuous)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} CYCLE_PHASES extracted fewer than 13 entries (heading rename or parse break?)"
  FAIL=$((FAIL + 1))
fi
PHASE_FAIL=0
while IFS= read -r phase; do
  # Strip ", downstream" qualifier (lens abbreviates "UI design (opt-in, downstream)"
  # to "UI design (opt-in)"); all other names match verbatim.
  trimmed=$(echo "$phase" | sed 's/, downstream//')
  TOTAL=$((TOTAL + 1))
  if echo "$LENS_SECTION" | grep -qF "$trimmed"; then
    echo -e "  ${GREEN}PASS${NC} V-model lens references cycle phase '$phase'"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} V-model lens missing cycle phase '$phase' (searched as '$trimmed')"
    FAIL=$((FAIL + 1))
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi
done <<< "$CYCLE_PHASES"

# (c) Every entry in the hands-off list (## Lead-owned convergence -> ### Hands-off
# shared-surface list) also appears in the WORKFLOW.md #### Doc-impact map.
# This enforces the "subset invariant" stated in WORKFLOW.md itself.
# Implementation note: entries with wildcards (e.g. docs/retro/v*.md) are matched
# on their base path (docs/retro/) since the doc-impact map uses the base path.
# DOC_IMPACT_BLOCK intentionally spans the map + version-surfaces note (the range
# ends at the next ## heading, which includes both the map table and the note below
# it); matching against the full block is correct per DEC-005 (looser match is deliberate).
DOC_IMPACT_BLOCK=$(sed -n '/^#### Doc-impact map/,/^## Lead-owned convergence/p' "$KIT_DIR/WORKFLOW.md")
HANDS_OFF_ENTRIES=$(sed -n '/^### Hands-off shared-surface list/,/^###/p' "$KIT_DIR/WORKFLOW.md" \
  | grep "^-" \
  | sed "s/^- \`\([^\`]*\)\`.*/\1/" | sed "s/^- //")
TOTAL=$((TOTAL + 1))
if [ "$(printf '%s\n' "$HANDS_OFF_ENTRIES" | grep -c .)" -ge 8 ]; then
  echo -e "  ${GREEN}PASS${NC} HANDS_OFF_ENTRIES extracted >= 8 entries (extraction not vacuous)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} HANDS_OFF_ENTRIES extracted fewer than 8 entries (heading rename or parse break?)"
  FAIL=$((FAIL + 1))
fi
while IFS= read -r entry; do
  # Strip wildcard suffix for matching (docs/retro/v*.md -> docs/retro/)
  base=$(echo "$entry" | sed 's/\*\.md[^)]*$//' | sed 's/v\*$//')
  TOTAL=$((TOTAL + 1))
  if echo "$DOC_IMPACT_BLOCK" | grep -qF "$base"; then
    echo -e "  ${GREEN}PASS${NC} hands-off entry '$entry' appears in doc-impact map (SPEC-031)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} hands-off entry '$entry' NOT in doc-impact map (subset invariant broken)"
    FAIL=$((FAIL + 1))
  fi
done <<< "$HANDS_OFF_ENTRIES"

# (d) The command/agent V-phase inventory table in docs/architecture.md has a row
# count equal to the live file count (ls commands/*.md + ls agents/*.md).
# Implementation note: rows are counted from the inventory table only, delimited
# between "## Command and agent V-phase inventory" and "## State model" (the next
# ## heading after the table). Only pipe-prefixed data rows are counted (excluding
# the header row and separator row identified by "| Entry" and "|---").
ARCH_TABLE_ROWS=$(sed -n '/^## Command and agent V-phase inventory/,/^## /p' \
  "$KIT_DIR/docs/architecture.md" \
  | grep "^|" | grep -v "^| Entry\|^|---" | wc -l | tr -d ' ')
CMD_COUNT=$(ls "$KIT_DIR/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
AGT_COUNT=$(ls "$KIT_DIR/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
LIVE_COUNT=$((CMD_COUNT + AGT_COUNT))
assert_eq "architecture.md inventory table rows == live file count ($ARCH_TABLE_ROWS == $LIVE_COUNT)" \
  "$LIVE_COUNT" "$ARCH_TABLE_ROWS"

# ============================================================
echo ""
echo "=== Parallel-execution boundary un-nerf (SPEC-032 C1 / ADR-0019) ==="
# ============================================================

# (a) The superseding ADR exists (the goal's "conflict settled by a recorded ADR").
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/docs/decisions/0019-parallel-execution-boundary.md" ]; then
  echo -e "  ${GREEN}PASS${NC} ADR-0019 (parallel-execution-boundary) exists (SPEC-032 C1)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} ADR-0019 (parallel-execution-boundary) missing"
  FAIL=$((FAIL + 1))
fi

# (b) The un-nerf is cross-referenced from the live policy + map docs (not silently
# broken): PHILOSOPHY and architecture.md both cite ADR-0019.
for doc in "docs/PHILOSOPHY.md" "docs/architecture.md"; do
  TOTAL=$((TOTAL + 1))
  if grep -q "ADR-0019" "$KIT_DIR/$doc" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} $doc cross-references ADR-0019 (un-nerf recorded)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $doc must cross-reference ADR-0019"
    FAIL=$((FAIL + 1))
  fi
done

# (c) The old hard-forbid claim no longer survives as a live PHILOSOPHY statement.
# The bald "not competing with agent runtimes" ban was the C1 boundary; its reworded
# form is the cross-goal fan-out carve-out. Scoped to PHILOSOPHY.md (the live policy);
# specs/ADRs that QUOTE the old wording to document the supersession are exempt.
TOTAL=$((TOTAL + 1))
if grep -q "not competing with agent runtimes" "$KIT_DIR/docs/PHILOSOPHY.md" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC} stale C1 ban ('not competing with agent runtimes') still live in PHILOSOPHY.md"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC} stale C1 ban absent from PHILOSOPHY.md (boundary reworded, ADR-0019)"
  PASS=$((PASS + 1))
fi

# (d) kit-health carries the recorded fan-out carve-out so it does not flag dispatch.
TOTAL=$((TOTAL + 1))
if grep -qi "cross-goal fan-out" "$KIT_DIR/commands/kit-health.md" 2>/dev/null \
   && grep -q "ADR-0019" "$KIT_DIR/commands/kit-health.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} kit-health records the cross-goal fan-out carve-out (ADR-0019)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health must record the cross-goal fan-out carve-out (ADR-0019)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Dispatch moat: ## Touches + lib/dispatch-gate.sh (SPEC-032) ==="
# ============================================================

# (a) The gate/guard helper exists and is executable (pure-bash moat).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/dispatch-gate.sh" ] && [ -x "$KIT_DIR/lib/dispatch-gate.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/dispatch-gate.sh exists and is executable (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/dispatch-gate.sh missing or not executable"
  FAIL=$((FAIL + 1))
fi

# (b) The spec template documents the `## Touches` section + the prefix-glob constraint.
TOTAL=$((TOTAL + 1))
if grep -q '^## Touches' "$KIT_DIR/commands/spec.md" 2>/dev/null \
   && grep -qi 'directory-prefix' "$KIT_DIR/commands/spec.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} commands/spec.md documents ## Touches + the prefix-glob constraint (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/spec.md must document ## Touches + the directory-prefix-glob constraint"
  FAIL=$((FAIL + 1))
fi

# (c) The new lib/ dir is registered in the WORKFLOW doc-impact map (new-top-level-dir rule).
TOTAL=$((TOTAL + 1))
if grep -q '`lib/\*`' "$KIT_DIR/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} lib/* row present in the WORKFLOW doc-impact map (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW doc-impact map missing the lib/* row"
  FAIL=$((FAIL + 1))
fi

# (d) The /kit:dispatch command exists with a description and is wired to the moat.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/commands/dispatch.md" ] && grep -q '^description:' "$KIT_DIR/commands/dispatch.md"; then
  echo -e "  ${GREEN}PASS${NC} commands/dispatch.md exists with a description (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/dispatch.md missing or has no description"
  FAIL=$((FAIL + 1))
fi

# (e) dispatch.md runs the gate + drift guard and converges without auto-merge.
TOTAL=$((TOTAL + 1))
if grep -q 'dispatch-gate.sh' "$KIT_DIR/commands/dispatch.md" 2>/dev/null \
   && grep -qi 'no auto-merge\|never auto-merge\|NEVER auto-merge\|not.*auto-merge' "$KIT_DIR/commands/dispatch.md" 2>/dev/null \
   && grep -q 'kit:ship' "$KIT_DIR/commands/dispatch.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} dispatch.md wires the gate + lead-owned convergence, no auto-merge (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} dispatch.md must use lib/dispatch-gate.sh, converge via /kit:ship, and refuse auto-merge"
  FAIL=$((FAIL + 1))
fi

# (f) dispatch.md is registered in the human-facing inventories (README + MANUAL).
TOTAL=$((TOTAL + 1))
if grep -q 'kit:dispatch' "$KIT_DIR/README.md" 2>/dev/null \
   && grep -q 'kit:dispatch' "$KIT_DIR/MANUAL.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} /kit:dispatch registered in README + MANUAL command inventories (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} /kit:dispatch must be in the README command table + MANUAL command list"
  FAIL=$((FAIL + 1))
fi

# (g) The lane classifier exists, is executable, and is wired into the intake/dispatch path.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/lane-classify.sh" ] && [ -x "$KIT_DIR/lib/lane-classify.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/lane-classify.sh exists and is executable (lane auto-classification)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/lane-classify.sh missing or not executable"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q 'lane-classify.sh' "$KIT_DIR/commands/assign.md" 2>/dev/null \
   && grep -q 'lane-classify.sh' "$KIT_DIR/commands/dispatch.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} lane-classify.sh wired into the intake (/kit:assign) + dispatch paths"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lane-classify.sh must be wired into /kit:assign + /kit:dispatch"
  FAIL=$((FAIL + 1))
fi

# SPEC-053: the advisory lane floor-check must exist in the classifier AND be wired
# into /kit:assign Step 5. A drop on either side makes the under-size guard a phantom.
TOTAL=$((TOTAL + 1))
if grep -qE '^[[:space:]]*check\)' "$KIT_DIR/lib/lane-classify.sh" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} lane-classify.sh exposes a 'check' subcommand (SPEC-053 floor guard)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lane-classify.sh lost the 'check' subcommand (SPEC-053 floor guard)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'lane-classify.sh check' "$KIT_DIR/commands/assign.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} assign.md wires the lane floor-check into Step 5 (SPEC-053)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} assign.md lost the lane floor-check wiring (SPEC-053)"
  FAIL=$((FAIL + 1))
fi

# SPEC-054: every work type has a defined loop + executor. Three legs: the registry's agent
# column (all 6 rows), the WORKFLOW Type-loops table (all 6 types), the assign type-routing.
TOTAL=$((TOTAL + 1))
AGENT_OK=$(awk -F'|' '/^\|/ {f2=$2; gsub(/^[ \t]+|[ \t]+$/, "", f2);
  if (f2 == "task-type" || f2 ~ /^-+$/) next; n++
  v=$6; gsub(/^[ \t]+|[ \t]+$/, "", v)
  if (v ~ /preassigned|dynamic|per lane/) ok++ } END { print (n==11 && ok==11) ? "yes" : "no" }' "$KIT_DIR/docs/verification/task-types.md")
if [ "$AGENT_OK" = "yes" ]; then
  echo -e "  ${GREEN}PASS${NC} task-types registry: all 11 rows carry an agent entry (SPEC-054/057)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} task-types registry agent column incomplete (SPEC-054/057)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
LOOP_ROWS=$(awk '/^## Type loops/,/^## [^T]/' "$KIT_DIR/WORKFLOW.md" | grep -cE '^\| (incident|learning|planning|operate|eval|research|reconcile|doc|migration|data-tool|spec-feature) \|')
if [ "$(grep -c '^## Type loops' "$KIT_DIR/WORKFLOW.md")" -eq 1 ] && [ "$LOOP_ROWS" -eq 11 ]; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md Type-loops table covers all 11 types (SPEC-054/057)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md Type-loops table missing or incomplete (SPEC-054, rows=$LOOP_ROWS)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'task-type-classify.sh classify' "$KIT_DIR/commands/assign.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} assign.md routes by task type before sizing (SPEC-054)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} assign.md lost the type-routing step (SPEC-054)"
  FAIL=$((FAIL + 1))
fi

# SPEC-055: the backlog kanban. The helper exists, assign documents pull mode, the
# vocabulary carries the claimed state. A drop on any leg makes pull a phantom.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/backlog.sh" ] && grep -qF -- '--next' "$KIT_DIR/commands/assign.md" \
   && grep -qF '`claimed`' "$KIT_DIR/_meta/BACKLOG.md"; then
  echo -e "  ${GREEN}PASS${NC} backlog kanban wired: lib/backlog.sh + assign --next + claimed state (SPEC-055)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} backlog kanban incomplete: need lib/backlog.sh executable + assign --next + claimed vocab (SPEC-055)"
  FAIL=$((FAIL + 1))
fi

# SPEC-056: per-type test dialects. Three legs: the 6-row dialect table, the type-aware
# test-plan step, the default flip in the cycle table.
TOTAL=$((TOTAL + 1))
DIALECT_ROWS=$(awk '/^## 5b/,/^## 6/' "$KIT_DIR/docs/verification/test-design-standard.md" | grep -cE '^\| (incident|learning|planning|operate|eval|research|reconcile|doc|migration|data-tool|spec-feature) \|')
if [ "$DIALECT_ROWS" -eq 11 ] && grep -qF 'task-type-classify' "$KIT_DIR/commands/test-plan.md" \
   && grep -qF 'Test plan (default' "$KIT_DIR/WORKFLOW.md"; then
  echo -e "  ${GREEN}PASS${NC} test dialects wired: 11-type table + type-aware test-plan + default flip (SPEC-056/057)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test dialects incomplete (rows=$DIALECT_ROWS) (SPEC-056/057)"
  FAIL=$((FAIL + 1))
fi

# SPEC-057 parity: every registry type has BOTH a WORKFLOW loop row AND a dialect row.
# A half-added type (registry row without loop/dialect) is a phantom and goes RED here.
TOTAL=$((TOTAL + 1))
REG_N=$(awk -F'|' '/^\|/ {f2=$2; gsub(/^[ \t]+|[ \t]+$/, "", f2); if (f2 == "task-type" || f2 ~ /^-+$/) next; print f2}' "$KIT_DIR/docs/verification/task-types.md" | sort)
PARITY_OK=yes
while IFS= read -r ty; do
  grep -qE "^\| ${ty} \|" <(awk '/^## Type loops/,/^## [^T]/' "$KIT_DIR/WORKFLOW.md") || PARITY_OK="no-loop:$ty"
  grep -qE "^\| ${ty} \|" <(awk '/^## 5b/,/^## 6/' "$KIT_DIR/docs/verification/test-design-standard.md") || PARITY_OK="no-dialect:$ty"
done <<< "$REG_N"
if [ "$PARITY_OK" = "yes" ] && [ "$(echo "$REG_N" | grep -c .)" -eq 11 ]; then
  echo -e "  ${GREEN}PASS${NC} type parity: every registry type has a loop row AND a dialect row (SPEC-057)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} type parity broken: $PARITY_OK (SPEC-057)"
  FAIL=$((FAIL + 1))
fi

# SPEC-057 operating-layer parity: AGENTS.md (the adopt-shipped contract) must carry the
# intake story: board pull, type-first classification, done-first phase 0. Losing any leg
# strands consumer repos on the old code-only contract.
TOTAL=$((TOTAL + 1))
if grep -qF 'backlog.sh next' "$KIT_DIR/AGENTS.md" && grep -qF 'task-type-classify.sh classify' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'Done =' "$KIT_DIR/AGENTS.md" && grep -qF 'Where work comes from' "$KIT_DIR/WORKFLOW.md"; then
  echo -e "  ${GREEN}PASS${NC} operating layer carries the intake story: board + type-first + done-first (SPEC-057)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} AGENTS.md/WORKFLOW.md lost the intake story (board/type/done-first) (SPEC-057)"
  FAIL=$((FAIL + 1))
fi

# SPEC-058: the grill. The command exists with all 11 type banks AND the three wiring legs
# (AGENTS task loop, assign, WORKFLOW phase-0) route classify -> grill -> Done=.
TOTAL=$((TOTAL + 1))
GRILL_BANKS=$(grep -cE '^### (incident|reconcile|operate|planning|learning|eval|research|doc|migration|data-tool|spec-feature)$' "$KIT_DIR/commands/grill.md" 2>/dev/null || echo 0)
if [ "$GRILL_BANKS" -eq 11 ] && grep -qF 'kit:grill' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'kit:grill' "$KIT_DIR/commands/assign.md" && grep -qF 'grill' "$KIT_DIR/WORKFLOW.md"; then
  echo -e "  ${GREEN}PASS${NC} grill intake wired: 11 type banks + AGENTS/assign/WORKFLOW legs (SPEC-058)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} grill intake incomplete (banks=$GRILL_BANKS) (SPEC-058)"
  FAIL=$((FAIL + 1))
fi

# SPEC-059: the absorb wave. (a) debug.md opens with the feedback-loop-first phase and its
# load-bearing catalog tactics; (b) review-team's architecture lens carries the deep-module
# vocabulary; (c) PHILOSOPHY carries the skill-routing rule that routes future absorbs.
TOTAL=$((TOTAL + 1))
if grep -qF '## Phase 0: Build a feedback loop' "$KIT_DIR/commands/debug.md" \
   && grep -qF 'Differential loop' "$KIT_DIR/commands/debug.md" \
   && grep -qF 'bisect run' "$KIT_DIR/commands/debug.md"; then
  echo -e "  ${GREEN}PASS${NC} debug.md has Phase 0 feedback-loop catalog (SPEC-059)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} debug.md missing Phase 0 feedback-loop catalog (SPEC-059)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'deletion test' "$KIT_DIR/commands/review-team.md" \
   && grep -qF 'locality' "$KIT_DIR/commands/review-team.md"; then
  echo -e "  ${GREEN}PASS${NC} review-team architecture lens carries deep-module vocabulary (SPEC-059)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} review-team architecture lens missing deep-module vocabulary (SPEC-059)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'Skill routing: what belongs in the kit' "$KIT_DIR/docs/PHILOSOPHY.md"; then
  echo -e "  ${GREEN}PASS${NC} PHILOSOPHY carries the skill-routing rule (SPEC-059)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} PHILOSOPHY missing skill-routing rule (SPEC-059)"
  FAIL=$((FAIL + 1))
fi

# SPEC-061: lane telemetry. (a) gate-ledger has the start verb; (b) the read-side
# aggregator exists with both subcommands; (c) retro carries the disposition contract;
# (d) WORKFLOW names the judging criteria.
TOTAL=$((TOTAL + 1))
if grep -qF 'start)    start "$@" ;;' "$KIT_DIR/lib/gate-ledger.sh" \
   && grep -qF 'usage: start <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]' "$KIT_DIR/lib/gate-ledger.sh"; then
  echo -e "  ${GREEN}PASS${NC} gate-ledger has the START routing verb (SPEC-061)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} gate-ledger missing the START verb (SPEC-061)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/lane-telemetry.sh" ] && grep -qF 'report)' "$KIT_DIR/lib/lane-telemetry.sh" \
   && grep -qF 'misfires)' "$KIT_DIR/lib/lane-telemetry.sh"; then
  echo -e "  ${GREEN}PASS${NC} lane-telemetry.sh exists with report+misfires (SPEC-061)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lane-telemetry.sh missing or incomplete (SPEC-061)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'Lane telemetry sweep (SPEC-061)' "$KIT_DIR/commands/retro.md" \
   && grep -qF 'Disposition contract' "$KIT_DIR/commands/retro.md" \
   && grep -qF 'How lanes are judged' "$KIT_DIR/WORKFLOW.md" \
   && grep -qF 'gate-ledger.sh start' "$KIT_DIR/commands/assign.md"; then
  echo -e "  ${GREEN}PASS${NC} telemetry wired: retro Step 1d + WORKFLOW criteria + assign START (SPEC-061)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} telemetry wiring incomplete (SPEC-061)"
  FAIL=$((FAIL + 1))
fi

# SPEC-062: telemetry closure. The operator scenarios live in WORKFLOW; debug carries the
# escaped-from marker; test-plan commands record their outcome.
TOTAL=$((TOTAL + 1))
if grep -qF 'What the operator sees, and when (SPEC-062)' "$KIT_DIR/WORKFLOW.md" \
   && grep -qF 'escaped-from=' "$KIT_DIR/commands/debug.md" \
   && grep -qF 'gate-ledger.sh record <spec-slug> test-plan ran' "$KIT_DIR/commands/test-plan.md" \
   && grep -qF 'gate-ledger.sh record <spec-slug> test-plan ran' "$KIT_DIR/commands/test-plan-review-team.md" \
   && grep -qF 'classified-type' "$KIT_DIR/lib/gate-ledger.sh"; then
  echo -e "  ${GREEN}PASS${NC} telemetry closure wired: scenarios + escaped-from + test-plan records + ctype (SPEC-062)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} telemetry closure wiring incomplete (SPEC-062)"
  FAIL=$((FAIL + 1))
fi

# SPEC-063: run legibility. plan/progress/trace exist; AGENTS carries the show-the-road
# rule + grill disposition recording; assign prints the plan; grill records itself.
TOTAL=$((TOTAL + 1))
if grep -qF 'plan)     plan "$@" ;;' "$KIT_DIR/lib/gate-ledger.sh" \
   && grep -qF 'progress) progress "$@" ;;' "$KIT_DIR/lib/gate-ledger.sh" \
   && grep -qF 'trace)    trace "$@" ;;' "$KIT_DIR/lib/lane-telemetry.sh" \
   && grep -qF 'Show the road, then your position on it (SPEC-063)' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'record <slug> grill' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'gate-ledger.sh plan' "$KIT_DIR/commands/assign.md" \
   && grep -qF 'record <slug> grill ran' "$KIT_DIR/commands/grill.md"; then
  echo -e "  ${GREEN}PASS${NC} run legibility wired: plan/progress/trace + AGENTS/assign/grill (SPEC-063)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} run legibility wiring incomplete (SPEC-063)"
  FAIL=$((FAIL + 1))
fi

# SPEC-065: stack-merge exists with both verbs + dry-run; ship.md points at it.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/stack-merge.sh" ] && grep -qF 'next_link' "$KIT_DIR/lib/stack-merge.sh" \
   && grep -qF 'dry-run' "$KIT_DIR/lib/stack-merge.sh" \
   && grep -qF 'stack-merge.sh chain' "$KIT_DIR/commands/ship.md"; then
  echo -e "  ${GREEN}PASS${NC} stack-merge codified + wired into ship (SPEC-065)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} stack-merge missing or unwired (SPEC-065)"
  FAIL=$((FAIL + 1))
fi

# SPEC-066: the install copies (no ln -s on hook files) and stamps; kit-health probes staleness.
TOTAL=$((TOTAL + 1))
if grep -qF 'cp "$HOOK_FILE" "$LINK"' "$KIT_DIR/install.sh" \
   && ! grep -qF 'ln -s "$HOOK_FILE"' "$KIT_DIR/install.sh" \
   && grep -qF 'INSTALL-STAMP' "$KIT_DIR/install.sh" \
   && grep -qF 'INSTALL-STAMP' "$KIT_DIR/commands/kit-health.md"; then
  echo -e "  ${GREEN}PASS${NC} install-by-copy + stamp + staleness probe (SPEC-066)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} install-by-copy incomplete (SPEC-066)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Multi-session: goal-registry + ADR-0022 (SPEC-036) ==="
# ============================================================

# (a) The cross-session registry helper exists and is executable (pure-bash substrate).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/goal-registry.sh" ] && [ -x "$KIT_DIR/lib/goal-registry.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/goal-registry.sh exists and is executable (SPEC-036)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/goal-registry.sh missing or not executable"
  FAIL=$((FAIL + 1))
fi

# (b) goal-registry reuses the dispatch-gate disjointness rule (no second moat).
TOTAL=$((TOTAL + 1))
if grep -q 'dispatch-gate.sh' "$KIT_DIR/lib/goal-registry.sh" 2>/dev/null \
   && ! grep -q '^prefix_overlap()' "$KIT_DIR/lib/goal-registry.sh" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} goal-registry.sh sources dispatch-gate.sh, does not re-implement the gate (SPEC-036 DEC-002)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} goal-registry.sh must source dispatch-gate.sh and not redefine prefix_overlap"
  FAIL=$((FAIL + 1))
fi

# (c) The multi-session boundary ADR exists.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/docs/decisions/0022-multi-session-boundary.md" ]; then
  echo -e "  ${GREEN}PASS${NC} ADR-0022 (multi-session boundary) exists (SPEC-036)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} docs/decisions/0022-multi-session-boundary.md missing"
  FAIL=$((FAIL + 1))
fi

# (d) PHILOSOPHY's multi-session boundary is reworded (the blanket "stays L5" claim is
#     gone) and references ADR-0022, so the bend is recorded, not silent.
TOTAL=$((TOTAL + 1))
if ! grep -q 'multi-session coordination across machines or live operators stays L5' "$KIT_DIR/docs/PHILOSOPHY.md" 2>/dev/null \
   && grep -q 'ADR-0022' "$KIT_DIR/docs/PHILOSOPHY.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} PHILOSOPHY multi-session boundary reworded + cites ADR-0022 (SPEC-036 C4)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} PHILOSOPHY must rework the blanket multi-session 'stays L5' claim and cite ADR-0022"
  FAIL=$((FAIL + 1))
fi

# (e) The claim is wired into /kit:assign and the monitor into /kit:start.
TOTAL=$((TOTAL + 1))
if grep -q 'goal-registry.sh' "$KIT_DIR/commands/assign.md" 2>/dev/null \
   && grep -q 'goal-registry.sh' "$KIT_DIR/commands/start.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} goal-registry wired: claim in /kit:assign, monitor in /kit:start (SPEC-036)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} goal-registry must be wired into /kit:assign (claim) + /kit:start (list)"
  FAIL=$((FAIL + 1))
fi

# (f) kit-health carries the recorded running-goal-registry carve-out (so it does not
#     flag the registry as runtime duplication).
TOTAL=$((TOTAL + 1))
if grep -qi 'running-goal registry' "$KIT_DIR/commands/kit-health.md" 2>/dev/null \
   && grep -q 'ADR-0022' "$KIT_DIR/commands/kit-health.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} kit-health carries the running-goal-registry carve-out (ADR-0022) (SPEC-036)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health must record the running-goal-registry carve-out citing ADR-0022"
  FAIL=$((FAIL + 1))
fi

# (g) ADR-0022 is cross-referenced from architecture.md (the concurrency boundary).
TOTAL=$((TOTAL + 1))
if grep -q 'ADR-0022' "$KIT_DIR/docs/architecture.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} architecture.md cross-references ADR-0022 (SPEC-036)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} docs/architecture.md must cross-reference ADR-0022"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Goal-draft lifecycle: goal-drafts.sh + ADR-0023 (SPEC-037) ==="
# ============================================================

# (a) lib/goal-drafts.sh exists and is executable.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/goal-drafts.sh" ] && [ -x "$KIT_DIR/lib/goal-drafts.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/goal-drafts.sh exists and is executable (SPEC-037)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/goal-drafts.sh missing or not executable"
  FAIL=$((FAIL + 1))
fi

# (b) The LIVE goal-draft contract carries no INDEX.md (the phantom is gone; only the
#     annotated historical record in ADR-0011/ADR-0023/SPEC-005 keeps the word).
LIVE_INDEX=$(grep -l 'INDEX\.md' "$KIT_DIR/commands/assign.md" "$KIT_DIR/commands/start.md" "$KIT_DIR/commands/next.md" "$KIT_DIR/WORKFLOW.md" "$KIT_DIR/docs/architecture.md" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no INDEX.md in the live goal-draft contract (SPEC-037 / ADR-0023)" "0" "$LIVE_INDEX"

# (c) ADR-0023 exists and ADR-0011 records the supersession (supersede, not rewrite).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/docs/decisions/0023-goal-draft-lifecycle.md" ] \
   && grep -q 'ADR-0023' "$KIT_DIR/docs/decisions/0011-goal-registry.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} ADR-0023 exists + ADR-0011 Status line names it (SPEC-037)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} ADR-0023 missing, or ADR-0011 does not record the supersession"
  FAIL=$((FAIL + 1))
fi

# (d) The State model section names BOTH stores side by side (draft + registry).
SM_SECTION=$(awk '/^## State model/{f=1; print; next} f && /^## /{exit} f{print}' "$KIT_DIR/docs/architecture.md" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if printf '%s' "$SM_SECTION" | grep -q '\.claude/goals' && printf '%s' "$SM_SECTION" | grep -q 'kit-goals'; then
  echo -e "  ${GREEN}PASS${NC} architecture.md State model names both the draft store and kit-goals registry (SPEC-037)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} architecture.md State model must show both .claude/goals and kit-goals side by side"
  FAIL=$((FAIL + 1))
fi

# (e) The archive is wired into /kit:ship.
TOTAL=$((TOTAL + 1))
if grep -q 'goal-drafts.sh' "$KIT_DIR/commands/ship.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} goal-drafts.sh archive wired into /kit:ship (SPEC-037)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} /kit:ship must run lib/goal-drafts.sh archive"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== /kit:verify command (SPEC-035) ==="
# ============================================================

# (a) commands/verify.md exists with a one-line description.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/commands/verify.md" ] && grep -q '^description:' "$KIT_DIR/commands/verify.md"; then
  echo -e "  ${GREEN}PASS${NC} commands/verify.md exists with a description (SPEC-035)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/verify.md missing or has no description"
  FAIL=$((FAIL + 1))
fi

# (b) verify.md dispatches both read-only test agents (the right-arm levels).
TOTAL=$((TOTAL + 1))
if grep -q 'task-verifier' "$KIT_DIR/commands/verify.md" 2>/dev/null \
   && grep -q 'integration-checker' "$KIT_DIR/commands/verify.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} verify.md dispatches task-verifier + integration-checker (SPEC-035)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} verify.md must dispatch task-verifier + integration-checker"
  FAIL=$((FAIL + 1))
fi

# (c) verify.md is read-only: it must DECLARE that it never dispatches fix-agent.
# Asserting the invariant is stated (not the mere absence of the string, which the
# file's own "to fix, run /execute" prose would defeat). A missing/empty file yields
# no match and fails, so this cannot pass vacuously.
TOTAL=$((TOTAL + 1))
if grep -qiE 'never dispatch[^.]*fix-agent' "$KIT_DIR/commands/verify.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} verify.md declares the read-only invariant (no fix-agent) (SPEC-035)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} verify.md must declare it does not dispatch fix-agent (read-only)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Gate ledger + ship enforcement (ADR-0024) ==="

assert_true "lib/gate-ledger.sh exists and is executable" "$([ -x "$KIT_DIR/lib/gate-ledger.sh" ] && echo 0 || echo 1)"
assert_true "hooks/ship-gate.sh exists and is executable" "$([ -x "$KIT_DIR/hooks/ship-gate.sh" ] && echo 0 || echo 1)"
assert_true "ADR-0024 (gate ledger + ship enforcement) exists" "$([ -f "$KIT_DIR/docs/decisions/0024-gate-ledger-and-ship-enforcement.md" ] && echo 0 || echo 1)"
assert_true "ship-gate registered in hooks.json (plugin path)" "$(grep -q 'hooks/ship-gate.sh' "$KIT_DIR/hooks/hooks.json" && echo 0 || echo 1)"
assert_true "ship-gate registered in settings.json (bash-install path)" "$(grep -q 'hooks/ship-gate.sh' "$KIT_DIR/settings.json" && echo 0 || echo 1)"
assert_true "PHILOSOPHY records the ADR-0024 ship-boundary bend" "$(grep -q 'ADR-0024' "$KIT_DIR/docs/PHILOSOPHY.md" && echo 0 || echo 1)"
assert_true "kit-health records the ship-gate carve-out" "$(grep -q 'ship-gate' "$KIT_DIR/commands/kit-health.md" && echo 0 || echo 1)"

# The lane×phase matrix is the single source for the lane->gate map; every value
# cell must be one of the three tokens so gate-ledger.sh can parse it (ADR-0024).
GL_BADCELLS=$(awk '
  /^## Lane.*depth matrix/ {inmx=1; next}
  inmx && /^## / {exit}
  inmx && /^\| *Phase *\|/ {hdr=1; next}
  inmx && hdr && /^\|/ {
    if ($0 ~ /^\| *-+/) next;
    n=split($0, c, "|");
    for (i=3;i<n;i++){ v=c[i]; gsub(/^ +| +$/,"",v);
      if (v!="" && v!="measure-twice" && v!="run-lite" && v!="skip") bad++ }
  }
  END{print bad+0}
' "$KIT_DIR/WORKFLOW.md")
assert_eq "lane×phase matrix cells are all measure-twice|run-lite|skip" "0" "$GL_BADCELLS"

GL_REQ="$(bash "$KIT_DIR/lib/gate-ledger.sh" required normal 2>/dev/null | tr '\n' ' ')"
assert_true "gate-ledger required(normal) derives spec+build+ship from the matrix" "$(echo "$GL_REQ" | grep -q 'spec' && echo "$GL_REQ" | grep -q 'build' && echo "$GL_REQ" | grep -q 'ship' && echo 0 || echo 1)"
assert_true "WORKFLOW documents the gate-ledger + ship-enforcement convention" "$(grep -q 'Gate ledger and ship enforcement' "$KIT_DIR/WORKFLOW.md" && echo 0 || echo 1)"
assert_true "ship.md records the Ship gate + names the override path" "$(grep -q 'gate-ledger.sh' "$KIT_DIR/commands/ship.md" && echo 0 || echo 1)"
assert_true "AGENTS operate-contract points at the gate-ledger convention" "$(grep -q 'gate-ledger' "$KIT_DIR/AGENTS.md" && echo 0 || echo 1)"

# SPEC-051 (A4-lite): /kit:retro carries the advisory decision-capture nudge, and it is framed
# advisory (the assertion pins both, so a future edit cannot quietly turn it into a hard gate).
assert_true "retro.md has the decision-capture nudge pointing at docs/decisions/" \
  "$(awk '/Decision-capture nudge/{f=1} f && /^### Step 2/{exit} f && /docs\/decisions\//{found=1} END{exit !found}' "$KIT_DIR/commands/retro.md" && echo 0 || echo 1)"
assert_true "retro decision-capture nudge is framed advisory, never a block" \
  "$(awk '/Decision-capture nudge/{f=1} f && /advisory, never a block/{found=1} END{exit !found}' "$KIT_DIR/commands/retro.md" && echo 0 || echo 1)"

# ============================================================
echo ""
echo "=== Implementation-notes log (SPEC-041 / ID-041) ==="
# ============================================================
# The worker template + the orchestrator summary + the /kit:next hand-off must
# carry the implementation-notes rule so any spec-driven build leaves an anchor
# for the PR reviewer and the /wrap-session LAB_LOG entry. Four pins so the
# rule cannot regress silently across the three insertion points.

assert_true "execute.md worker template carries the implementation-notes rule" \
  "$(grep -q 'implementation-notes' "$KIT_DIR/commands/execute.md" && echo 0 || echo 1)"

assert_true "execute.md 'When done' reporting names the implementation-notes path" \
  "$(awk '/^## When done/{f=1;next} f && /^## /{exit} f && /implementation-notes/{found=1} END{exit !found}' "$KIT_DIR/commands/execute.md" >/dev/null && echo 0 || echo 1)"

assert_true "execute.md Step 4 completion summary surfaces the implementation-notes file" \
  "$(awk '/^### Step 4: Completion/{f=1;next} f && /^### /{exit} f && /implementation-notes/{found=1} END{exit !found}' "$KIT_DIR/commands/execute.md" >/dev/null && echo 0 || echo 1)"

assert_true "next.md Step 4 hand-off carries the implementation-notes reminder" \
  "$(awk '/^### Step 4: Hand off/{f=1;next} f && /^### /{exit} f && /implementation-notes/{found=1} END{exit !found}' "$KIT_DIR/commands/next.md" >/dev/null && echo 0 || echo 1)"

# ============================================================
echo ""
echo "=== Verification log (execution-backed verify) ==="
# ============================================================
# "Verify before proceeding" is only real if the verification was actually run
# and the run is recorded as a re-runnable artifact: command + exit + output
# excerpt + verdict. Prose "Tests: passing" is not proof. Eight pins so the
# convention cannot regress: a convention doc (+ its required fields), the
# no-check marker, the agent's captured record, the two write-sites (execute +
# verify), the completion-summary surface, and the PHILOSOPHY bend.

assert_true "docs/verification/ convention doc exists" \
  "$([ -f "$KIT_DIR/docs/verification/README.md" ] && echo 0 || echo 1)"

assert_true "verification convention records command + exit + output excerpt + verdict" \
  "$(grep -q 'Command:' "$KIT_DIR/docs/verification/README.md" && grep -q 'Exit:' "$KIT_DIR/docs/verification/README.md" && grep -q 'Output (excerpt)' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"

assert_true "task-verifier emits the explicit no-check marker (no fake pass)" \
  "$(grep -q '\[NO EXECUTABLE CHECK:' "$KIT_DIR/agents/task-verifier.md" && echo 0 || echo 1)"

assert_true "task-verifier verdict captures the executed command + exit code" \
  "$(grep -q 'Verification record' "$KIT_DIR/agents/task-verifier.md" && grep -q 'Command:' "$KIT_DIR/agents/task-verifier.md" && echo 0 || echo 1)"

assert_true "execute.md writes the verification log (docs/verification/)" \
  "$(grep -q 'docs/verification/' "$KIT_DIR/commands/execute.md" && echo 0 || echo 1)"

assert_true "execute.md Step 4 completion summary surfaces the verification-log path" \
  "$(awk '/^### Step 4: Completion/{f=1;next} f && /^### /{exit} f && /docs\/verification\//{found=1} END{exit !found}' "$KIT_DIR/commands/execute.md" >/dev/null && echo 0 || echo 1)"

assert_true "verify.md records the read-only run to the verification log" \
  "$(grep -q 'docs/verification/' "$KIT_DIR/commands/verify.md" && echo 0 || echo 1)"

assert_true "review.md reads test state from the verification log (static-judgment boundary)" \
  "$(grep -q 'docs/verification/' "$KIT_DIR/commands/review.md" && echo 0 || echo 1)"

assert_true "PHILOSOPHY records the execution-backed-verify bend" \
  "$(grep -q 'docs/verification/' "$KIT_DIR/docs/PHILOSOPHY.md" && echo 0 || echo 1)"

# ---- proof of done: the negative control (a green check is only proof if it can fail) ----

assert_true "convention defines proof of done (green + negative control + reproducible)" \
  "$(grep -qi 'Proof of done' "$KIT_DIR/docs/verification/README.md" && grep -qi 'negative control' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"

assert_true "task-verifier can run a bash/make project suite (not only npm/go/pytest/cargo)" \
  "$(grep -qE 'Bash\(bash tests/\*\)|Bash\(make test\*\)' "$KIT_DIR/agents/task-verifier.md" && echo 0 || echo 1)"

assert_true "task-verifier flags a weak/absent negative control on load-bearing tasks" \
  "$(grep -qi 'Negative control' "$KIT_DIR/agents/task-verifier.md" && echo 0 || echo 1)"

assert_true "execute.md produces a negative control for load-bearing builds" \
  "$(grep -qi 'NEGATIVE CONTROL' "$KIT_DIR/commands/execute.md" && echo 0 || echo 1)"

assert_true "verify.md produces a negative control for load-bearing specs" \
  "$(grep -qi 'NEGATIVE CONTROL' "$KIT_DIR/commands/verify.md" && echo 0 || echo 1)"

# ---- risk-gated proof of done: the class gate (stateful | behavioral | inert) ----

assert_true "lib/proof-gate.sh exists and is executable" \
  "$([ -x "$KIT_DIR/lib/proof-gate.sh" ] && echo 0 || echo 1)"

assert_true "proof-gate names the three proof classes (stateful, behavioral, inert)" \
  "$(out=$(bash "$KIT_DIR/lib/proof-gate.sh" classes 2>/dev/null); echo "$out" | grep -q stateful && echo "$out" | grep -q behavioral && echo "$out" | grep -q inert && echo 0 || echo 1)"

assert_true "convention defines the risk-class gate (stateful/behavioral/inert + proof-gate)" \
  "$(grep -qi 'proof class' "$KIT_DIR/docs/verification/README.md" && grep -q 'proof-gate.sh' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"

assert_true "convention names the inert exempt marker + the run-the-real-flow rule" \
  "$(grep -q 'PROOF OF DONE: exempt' "$KIT_DIR/docs/verification/README.md" && grep -qi 'real primary flow' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"

assert_true "execute.md gates the proof by class (proof-gate)" \
  "$(grep -q 'proof-gate.sh' "$KIT_DIR/commands/execute.md" && echo 0 || echo 1)"

assert_true "verify.md gates the proof by class (proof-gate)" \
  "$(grep -q 'proof-gate.sh' "$KIT_DIR/commands/verify.md" && echo 0 || echo 1)"

assert_true "task-verifier reads proof class (inert exempt ok; stateful needs rollback)" \
  "$(grep -q 'proof-gate.sh' "$KIT_DIR/agents/task-verifier.md" && grep -q 'PROOF OF DONE: exempt' "$KIT_DIR/agents/task-verifier.md" && echo 0 || echo 1)"

# ---- proof-of-done ENFORCEMENT: the ship/merge gate (advice -> wall) ----

assert_true "lib/proof-ledger.sh exists and is executable" \
  "$([ -x "$KIT_DIR/lib/proof-ledger.sh" ] && echo 0 || echo 1)"

assert_true "ship-gate wires the diff-keyed proof-of-done gate" \
  "$(grep -q 'proof-ledger.sh' "$KIT_DIR/hooks/ship-gate.sh" && echo 0 || echo 1)"

assert_true "proof gate is opt-in (engages only where docs/verification/README.md exists)" \
  "$(grep -q 'docs/verification/README.md' "$KIT_DIR/hooks/ship-gate.sh" && echo 0 || echo 1)"

assert_true "proof-ledger provides a logged override (no silent bypass)" \
  "$(grep -q 'override' "$KIT_DIR/lib/proof-ledger.sh" && grep -qi 'OVERRIDE' "$KIT_DIR/lib/proof-ledger.sh" && echo 0 || echo 1)"

assert_true "ADR records the proof-of-done ship gate" \
  "$([ -f "$KIT_DIR/docs/decisions/0025-proof-of-done-ship-gate.md" ] && echo 0 || echo 1)"

assert_true "convention documents the enforcement gate + override" \
  "$(grep -qi 'ship/merge gate\|enforcement' "$KIT_DIR/docs/verification/README.md" && grep -q 'proof-ledger' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"

assert_true "PHILOSOPHY records the deferred enforcement hook is now built" \
  "$(grep -q 'proof-ledger' "$KIT_DIR/docs/PHILOSOPHY.md" && echo 0 || echo 1)"

# ---- single-source numbers: borrowed from the experiment sibling (no hand-typed drift) ----

assert_true "lib/verif-counts.sh exists and is executable" \
  "$([ -x "$KIT_DIR/lib/verif-counts.sh" ] && echo 0 || echo 1)"

assert_true "COUNTS.md carries the generated single-source block" \
  "$(grep -q 'BEGIN GEN:counts' "$KIT_DIR/docs/verification/COUNTS.md" 2>/dev/null && echo 0 || echo 1)"

assert_true "convention names the experiment sibling + single-source borrow" \
  "$(grep -qi 'sibling' "$KIT_DIR/docs/verification/README.md" && grep -qi 'single-source\|codebase-tool-benchmark\|falsifiab' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"
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
echo "=== Task-type contracts (SPEC-044) ==="
# ============================================================
# Second axis of the verification gate: task TYPE -> proof artifact + owning skill,
# composed with the proof CLASS. Pins the classifier, the registry, and the
# proof-gate `contract` compose. These go RED if SPEC-044 is reverted (negative control).

TTC="$KIT_DIR/lib/task-type-classify.sh"
TTREG="$KIT_DIR/docs/verification/task-types.md"

assert_true "lib/task-type-classify.sh exists and is executable" \
  "$([ -x "$TTC" ] && echo 0 || echo 1)"

assert_eq "classify -> eval" "eval" "$(bash "$TTC" classify 'benchmark X vs Y for retrieval' 2>/dev/null)"
assert_eq "classify -> research" "research" "$(bash "$TTC" classify 'research the tooling landscape' 2>/dev/null)"
assert_eq "classify -> doc" "doc" "$(bash "$TTC" classify 'write the README for the tool' 2>/dev/null)"
assert_eq "classify -> migration" "migration" "$(bash "$TTC" classify 'migrate the database schema' 2>/dev/null)"
assert_eq "classify -> data-tool" "data-tool" "$(bash "$TTC" classify 'build a CLI to pull data from the API' 2>/dev/null)"
# Negative control: an unmatched description falls through to the default, not a wrong type.
assert_eq "classify default (neg control) -> spec-feature" "spec-feature" "$(bash "$TTC" classify 'add a sort button to the trade log' 2>/dev/null)"

assert_eq "task-type-classify types lists 11" "11" "$(bash "$TTC" types 2>/dev/null | grep -c .)"

assert_true "task-types.md registry exists" "$([ -f "$TTREG" ] && echo 0 || echo 1)"
for T in eval research doc migration data-tool spec-feature; do
  assert_true "registry has a row for '$T'" \
    "$(grep -qE "^\| *$T *\|" "$TTREG" && echo 0 || echo 1)"
done

CONTRACT_OUT="$(bash "$KIT_DIR/lib/proof-gate.sh" contract 'build a CLI to pull data from the API' 2>/dev/null)"
assert_true "proof-gate contract names the data-tool type" \
  "$(printf '%s' "$CONTRACT_OUT" | grep -q 'type=data-tool' && echo 0 || echo 1)"
assert_true "proof-gate contract names the recorded-run artifact + owning skill" \
  "$(printf '%s' "$CONTRACT_OUT" | grep -qi 'recorded live run' && printf '%s' "$CONTRACT_OUT" | grep -qi 'ops-tool-shape' && echo 0 || echo 1)"
assert_true "proof-gate contract upgrades a migration to stateful (class wins on rigor)" \
  "$(bash "$KIT_DIR/lib/proof-gate.sh" contract 'migrate the database schema' 2>/dev/null | grep -q 'class=stateful' && echo 0 || echo 1)"

# ============================================================
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
