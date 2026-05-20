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

# ============================================================
echo ""
echo "=== Demo project (examples/hello-spec) ==="
# ============================================================

DEMO_DIR="$KIT_DIR/examples/hello-spec"

for f in README.md CLAUDE.md .planning/SPEC.md; do
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
  if grep -q "^${SECTION}" "$DEMO_DIR/.planning/SPEC.md" 2>/dev/null; then
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

# Downstream template uses the .planning/ convention; kit-root uses docs/specs/
# (ADR-0002). Asserting each in its own file catches a copy-paste path error.
TOTAL=$((TOTAL + 1))
if grep -qF '.planning/SPEC.md' "$WF_DEMO" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} examples/hello-spec/WORKFLOW.md uses .planning/SPEC.md"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} examples/hello-spec/WORKFLOW.md missing .planning/SPEC.md"
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
