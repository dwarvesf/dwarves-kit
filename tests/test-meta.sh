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
assert_eq "plugin.json name == 'dwarves-kit'" "dwarves-kit" "$PLUGIN_NAME"

PLUGIN_VERSION=$(jq -r '.version' "$KIT_DIR/.claude-plugin/plugin.json")
VERSION_FILE=$(cat "$KIT_DIR/VERSION" | tr -d '[:space:]')
assert_eq "plugin.json version matches VERSION file" "$VERSION_FILE" "$PLUGIN_VERSION"

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

# SPEC-011: the opt-in /user:design command must exist (the frontmatter loop above
# covers its shape; this asserts presence so a deletion fails CI).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/commands/design.md" ]; then
  echo -e "  ${GREEN}PASS${NC} commands/design.md exists (/user:design lane)"
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
# The /user:debug command must exist and carry its load-bearing structure,
# and the guess-fix guard's ledger contract must stay in sync with the hook.

DEBUG_CMD="$KIT_DIR/commands/debug.md"
TOTAL=$((TOTAL + 1))
if [ -f "$DEBUG_CMD" ]; then
  echo -e "  ${GREEN}PASS${NC} commands/debug.md exists (/user:debug, bug lane)"
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

# SPEC-010: no stray .planning/ refs in command prose (the convention unified onto
# docs/specs/). Hooks legitimately keep a bounded .planning/ deprecation fallback
# (behavior-tested in test-hooks.sh), so they are NOT guarded here. The one allowed
# command ref is the explicit "legacy" note in start.md.
STRAY_PLANNING=$(grep -rn '\.planning' "$KIT_DIR/commands/" 2>/dev/null | grep -vi 'legacy' | wc -l | tr -d ' ')
assert_eq "no stray .planning/ refs in commands/ (legacy note excepted)" "0" "$STRAY_PLANNING"

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

# SPEC-005 TASK-2: agents/ carry no stray .planning ref either (same unify); the
# "legacy ... fallback" pointers in task-verifier/responding-to-review are allowed.
STRAY_PLANNING_AGENTS=$(grep -rn '\.planning' "$KIT_DIR/agents/" 2>/dev/null | grep -vi 'legacy' | wc -l | tr -d ' ')
assert_eq "no stray .planning/ refs in agents/ (legacy fallback excepted)" "0" "$STRAY_PLANNING_AGENTS"

# SPEC-006: the orchestration spine is documented + /user:assign exists.
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
  echo -e "  ${GREEN}PASS${NC} commands/assign.md exists (/user:assign, SPEC-006)"
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
    echo -e "  ${GREEN}PASS${NC} commands/$CMD.md exists (/user:$CMD, SPEC-016)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} commands/$CMD.md missing"
    FAIL=$((FAIL + 1))
  fi
done

# SPEC-017: /user:execute expands tasks into bite-sized steps.
TOTAL=$((TOTAL + 1))
if grep -qF 'bite-sized steps' "$KIT_DIR/commands/execute.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} execute.md has the bite-sized step-expansion marker (SPEC-017)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} execute.md missing the bite-sized step-expansion marker"
  FAIL=$((FAIL + 1))
fi

# Review issue 4: command-count strings agree with the actual file count.
ACTUAL_CMDS=$(ls "$KIT_DIR/commands/"*.md | wc -l | tr -d ' ')
for COUNTFILE in ".claude-plugin/plugin.json" ".claude-plugin/marketplace.json" "README.md" "MANUAL.md" "CLAUDE.md"; do
  TOTAL=$((TOTAL + 1))
  if grep -qF "$ACTUAL_CMDS commands" "$KIT_DIR/$COUNTFILE" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} $COUNTFILE states '$ACTUAL_CMDS commands' (count parity)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $COUNTFILE missing '$ACTUAL_CMDS commands' (count drift)"
    FAIL=$((FAIL + 1))
  fi
done

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
