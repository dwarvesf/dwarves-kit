#!/bin/bash
# test-meta-agents-commands.sh -- agents-commands structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-agents-commands.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

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
  if { trap '' PIPE; echo "$MODEL_VAL" 2>/dev/null || :; } | grep -qE '^(sonnet|haiku|opus)$'; then
    echo -e "  ${GREEN}PASS${NC} agent $AGENT model is sonnet|haiku|opus ($MODEL_VAL)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} agent $AGENT model invalid or missing ('$MODEL_VAL')"
    FAIL=$((FAIL + 1))
  fi
done

# MANUAL.md agent table cross-refs match agents/ files.
# Canonical agent inventory is in MANUAL.md "Agents" section (table rows), whose bulk now
# lives at docs/MANUAL.md (root MANUAL.md is a thin stub, SPEC-185).
# CLAUDE.md no longer mirrors the inventory; see docs/architecture.md for component fit.
MANUAL_BULK="$KIT_DIR/docs/MANUAL.md"
SUBAGENT_NAMES=$(grep '^| `' "$MANUAL_BULK" | sed 's/^| `\([^`]*\)`.*/\1/' | sort -u)
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
  if grep -q "^| \`$AGENT\` " "$MANUAL_BULK"; then
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
echo "=== Plugin-qualified agent dispatch (ID-905) ==="
# ============================================================
# The plugin registers every agents/*.md under `kit:<name>` only; a bare
# `subagent_type`/dispatch name falls through to a stale ~/.claude/agents copy
# (or fails outright, anthropics/claude-code#33689). Every dispatchable
# reference in commands/, skills/, agents/, and MANUAL.md must therefore be
# `kit:`-qualified. Legitimately bare contexts are whitelisted in the scan:
# file paths (`agents/<name>`, `<name>.md`), `name:`/`generated-by:` frontmatter,
# and the `advisor` gate-ledger PHASE (record/outcome lines, `advisor`
# row|entry|bracket|phase|emit|run prose, the kit.toml modules tuple, and the
# non-agent English "product advisor").
BARE_AGENT_HITS=$(awk -v NAMES="$(ls "$KIT_DIR/agents/"*.md | xargs -n1 basename | sed 's/\.md$//' | tr '\n' ' ')" '
BEGIN { n = split(NAMES, A, " ") }
FILENAME ~ /(^|\/)agents\// && /^name:/ { next }
/generated-by:/ { next }
{
  for (i = 1; i <= n; i++) {
    name = A[i]; L = length(name); c = 1
    while ((off = index(substr($0, c), name)) > 0) {
      s = c + off - 1; e = s + L - 1
      c = e + 1
      bc = (s > 1) ? substr($0, s - 1, 1) : " "
      ac = (e < length($0)) ? substr($0, e + 1, 1) : " "
      if (bc ~ /[A-Za-z0-9_-]/ || ac ~ /[A-Za-z0-9_-]/) continue
      if (substr($0, s - 4, 4) == "kit:") continue
      if (substr($0, s - 7, 7) == "agents/") continue
      if (substr($0, e + 1, 3) == ".md") continue
      if (name == "advisor") {
        if ($0 ~ /gate-ledger|record |outcome /) continue
        if (substr($0, e + 1) ~ /^`?[[:space:]]+(rows?|entry|entries|brackets?|emit|grammar|phase|start|end|ran|run)([^[:alnum:]_-]|$)/) continue
        if (substr($0, e + 1) ~ /^[[:space:]]+P[56]=/) continue
        if (substr($0, s - 8, 8) == "product ") continue
        if ($0 ~ /modules \(/) continue
      }
      print FILENAME ":" FNR ": bare " name
    }
  }
}' "$KIT_DIR"/commands/*.md "$KIT_DIR"/skills/*/*.md "$KIT_DIR"/agents/*.md "$KIT_DIR"/MANUAL.md)
TOTAL=$((TOTAL + 1))
if [ -z "$BARE_AGENT_HITS" ]; then
  echo -e "  ${GREEN}PASS${NC} all agent references outside whitelist contexts are kit:-qualified (ID-905)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} bare agent-name references found (dispatch resolves to stale user copies):"
  echo "$BARE_AGENT_HITS" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi

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
