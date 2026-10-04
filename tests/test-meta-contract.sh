#!/bin/bash
# test-meta-contract.sh -- contract structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-contract.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

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
# SPEC-185: WORKFLOW.md's bulk lives at docs/WORKFLOW.md; check both the root stub and the bulk.
for DOC in WORKFLOW.md docs/WORKFLOW.md CLAUDE.md; do
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
echo "=== SPEC-074: composition section + 3-surface parity (ID-066) ==="
# ============================================================
RC=0; grep -qF 'Lane x type composition' "$KIT_DIR/docs/WORKFLOW.md" || RC=1
assert_eq "WORKFLOW carries the lane x type composition rule" 0 $RC
RC=0; grep -qF 'recorded `skipped "<loop-step note>"`' "$KIT_DIR/docs/WORKFLOW.md" || RC=1
assert_eq "composition names the skip-with-loop-note mapping" 0 $RC
# 3-surface parity: every type in the loops table has a registry row and vice versa
LOOPT=$(awk '/## Type loops/,/### Lane x type composition/' "$KIT_DIR/docs/WORKFLOW.md" | grep '^| ' | cut -d'|' -f2 | tr -d ' ' | grep -v '^Type$' | grep -v '^-*$' | sort)
REGT=$(grep '^|' "$KIT_DIR/docs/verification/task-types.md" | cut -d'|' -f2 | tr -d ' ' | grep -v '^task-type$' | grep -v '^-*$' | sort)
assert_eq "type loops table and registry agree on the 12 types" "$LOOPT" "$REGT"


# SPEC-076: descent contract wired
RC=0; grep -qF 'The V-model descent contract' "$KIT_DIR/docs/WORKFLOW.md" || RC=1
assert_eq "WORKFLOW carries the descent contract" 0 $RC
RC=0; grep -q '^  descent)' "$KIT_DIR/lib/gate/gate-ledger.sh" || RC=1
assert_eq "gate-ledger dispatches the descent verb" 0 $RC
RC=0; grep -qF 'descent violation' "$KIT_DIR/hooks/ship-gate.sh" || RC=1
assert_eq "ship-gate carries the descent advisory" 0 $RC


# SPEC-077: per-link self-reconcile wired (the unit fixtures cover the helper; this
# pins the call site that gh-dependent flow tests cannot reach)
RC=0; grep -qF 'ensure_reconciled "$head" "$base"' "$KIT_DIR/lib/goal/stack-merge.sh" || RC=1
assert_eq "stack-merge next_link self-reconciles every link" 0 $RC
RC=0; grep -qF 'start --amend' "$KIT_DIR/lib/gate/gate-ledger.sh" || RC=1
assert_eq "gate-ledger documents the amend path" 0 $RC


# ============================================================
echo ""
echo "=== Self-intro convention (SPEC-222) ==="
# ============================================================
# AGENTS.md carries the self-intro convention (every /kit: command opens its
# first reply with a `[kit:<name>] <purpose>` banner; dispatched agents' reports
# open the same way), and the three highest-traffic entry commands wire it
# concretely. Remaining commands adopt on next touch; the AGENTS.md contract
# covers them meanwhile, so only these four surfaces are pinned.
RC=0; { grep -qF '## Self-intro' "$AGENTS_MD" && grep -qF '[kit:<name>]' "$AGENTS_MD"; } || RC=1
assert_eq "AGENTS.md carries the Self-intro convention section + banner format (SPEC-222)" 0 $RC
for CMD in start assign execute; do
  assert_true "commands/$CMD.md wires the self-intro banner (SPEC-222)" \
    "$(grep -qF "[kit:$CMD]" "$KIT_DIR/commands/$CMD.md" && echo 0 || echo 1)"
done

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
