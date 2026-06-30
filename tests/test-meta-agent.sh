#!/bin/bash
# test-meta-agent.sh -- the meta-agent drafter (token-optim-v3 SG-05).
# Validates: (1) agents/meta-agent.md is a well-formed kit agent; (2) the
# committed golden drafts (a subagent + a sub-goal file the drafter produced)
# pass the kit's frontmatter/structure checks AND carry the DRAFT marker.
#
# Run: bash tests/test-meta-agent.sh   (exit 0 = pass, 1 = fail)

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/meta-agent"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

ok()   { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} $1"; }
bad()  { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} $1"; }
chk()  { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

# Lint a file's YAML frontmatter the same way test-meta.sh lints agents/.
# $1 label  $2 file  $3 first-content-line (1 = real first line, 2 = after a marker line)
lint_agent_frontmatter() {
  local label="$1" f="$2" start="${3:-1}"
  local body; body=$(tail -n +"$start" "$f")
  [ "$(printf '%s\n' "$body" | head -1)" = "---" ]; chk "$label: frontmatter opens with ---" $?
  local name desc model tools
  name=$(printf '%s\n' "$body" | awk '/^---$/{c++; if(c==2)exit} c==1 && /^name:/' | wc -l | tr -d ' ')
  desc=$(printf '%s\n' "$body" | awk '/^---$/{c++; if(c==2)exit} c==1 && /^description:/' | wc -l | tr -d ' ')
  tools=$(printf '%s\n' "$body" | awk '/^---$/{c++; if(c==2)exit} c==1 && /^tools:/' | wc -l | tr -d ' ')
  model=$(printf '%s\n' "$body" | awk -F': *' '/^---$/{c++; if(c==2)exit} c==1 && /^model:/{print $2; exit}' | tr -d '[:space:]')
  [ "$name" = "1" ];  chk "$label: has name field" $?
  [ "$desc" = "1" ];  chk "$label: has description field" $?
  [ "$tools" = "1" ]; chk "$label: has tools field" $?
  echo "$model" | grep -qE '^(sonnet|haiku|opus)$'; chk "$label: model is sonnet|haiku|opus ($model)" $?
  # minimal tools: never a bare unscoped Bash entry
  if printf '%s\n' "$body" | awk '/^---$/{c++; if(c==2)exit} c==1' | grep -qE '^[[:space:]]*-[[:space:]]*Bash[[:space:]]*$'; then
    bad "$label: tools are minimal (no bare 'Bash')"
  else
    ok "$label: tools are minimal (no bare 'Bash')"
  fi
}

echo "=== meta-agent definition ==="
MA="$KIT_DIR/agents/meta-agent.md"
[ -f "$MA" ]; chk "agents/meta-agent.md exists" $?
lint_agent_frontmatter "meta-agent" "$MA" 1
grep -q "Mode A" "$MA" && grep -q "Mode B" "$MA"; chk "meta-agent documents both draft modes" $?
grep -q "DRAFT" "$MA" && grep -qi "never" "$MA"; chk "meta-agent states DRAFT-only / never installs" $?
grep -q '^| `meta-agent` ' "$KIT_DIR/MANUAL.md"; chk "meta-agent listed in MANUAL.md (test-meta.sh cross-ref)" $?
[ -f "$KIT_DIR/commands/draft-agent.md" ] && head -1 "$KIT_DIR/commands/draft-agent.md" | grep -q '^---$'; chk "commands/draft-agent.md exists with frontmatter" $?

MARKER='<!-- DRAFT , review before use. Drafted by meta-agent. Not installed. -->'

echo ""
echo "=== golden draft: subagent (Mode A) ==="
DA="$FIX/drafted-agent.md"
[ -f "$DA" ]; chk "drafted-agent.md exists" $?
[ "$(head -1 "$DA")" = "$MARKER" ]; chk "drafted-agent.md: DRAFT marker is line 1" $?
lint_agent_frontmatter "drafted-agent" "$DA" 2   # frontmatter starts after the marker line
EMDASH=$(printf '\xe2\x80\x94')   # U+2014 as raw UTF-8 bytes (portable: no grep -P)
LC_ALL=C grep -qF "$EMDASH" "$DA" && bad "drafted-agent.md: no em-dash" || ok "drafted-agent.md: no em-dash"

echo ""
echo "=== golden draft: sub-goal file (Mode B) ==="
DS="$FIX/drafted-subgoal.md"
[ -f "$DS" ]; chk "drafted-subgoal.md exists" $?
[ "$(head -1 "$DS")" = "$MARKER" ]; chk "drafted-subgoal.md: DRAFT marker is line 1" $?
grep -qE '^# Sub-goal [0-9]+:' "$DS"; chk "drafted-subgoal.md: has '# Sub-goal NN:' heading" $?
for FIELD in 'Merge policy:' 'Time budget:' 'Proof:' 'Depends on:' 'Branch:' 'PR base:'; do
  grep -qF "$FIELD" "$DS"; chk "drafted-subgoal.md: has '$FIELD'" $?
done
grep -qE '^Model:' "$DS";  chk "drafted-subgoal.md: bare Model: line (orchestrator-parsable)" $?
grep -qE '^Effort:' "$DS"; chk "drafted-subgoal.md: bare Effort: line (orchestrator-parsable)" $?
grep -qF '**Done =**' "$DS"; chk "drafted-subgoal.md: has bold **Done =** boolean" $?
for SEC in '## Outcome' '## Quality bar' '## How to close the loop' '## Scope edges' '## PR body'; do
  grep -qF "$SEC" "$DS"; chk "drafted-subgoal.md: has '$SEC'" $?
done
LC_ALL=C grep -qF "$EMDASH" "$DS" && bad "drafted-subgoal.md: no em-dash" || ok "drafted-subgoal.md: no em-dash"

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
