#!/bin/bash
# test-meta-spec-depth.sh -- spec-depth structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-spec-depth.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

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

# WORKFLOW.md must carry the bug lane that routes to /debug. Bulk lives at
# docs/WORKFLOW.md (root is a thin stub, SPEC-185).
TOTAL=$((TOTAL + 1))
if grep -qE '^\| bug ' "$KIT_DIR/docs/WORKFLOW.md" 2>/dev/null; then
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
# Bulk lives at docs/WORKFLOW.md (root WORKFLOW.md is a thin stub, SPEC-185).
WF_SPINE="$KIT_DIR/docs/WORKFLOW.md"
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

# /kit:execute hands the builder the standing grant instead of a bite-sized step mandate.
TOTAL=$((TOTAL + 1))
if grep -qF 'Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.' "$KIT_DIR/commands/execute.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} execute.md carries the builder's standing grant sentence"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} execute.md missing the builder's standing grant sentence"
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
if grep -qF "## The 7 reviewers" "$VALIDATE_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} spec-validate.md header says 7 reviewers"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} spec-validate.md header not updated to 7 reviewers"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qE "^### Reviewer 6:" "$VALIDATE_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} spec-validate.md has Reviewer 6 (design record, ADR-0031 §1, blocking)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} spec-validate.md missing Reviewer 6"
  FAIL=$((FAIL + 1))
fi

# Count-drift guard: no live "4 reviewer(s)" / "5 reviewer(s)" reference may remain in the
# command (the heading, frontmatter, and output-format intro must all agree). Historical
# "N reviewers run <date>" lines live in docs/specs/, not here, so this file is safe
# to assert clean. Caught a real regression in the SPEC-008 review; SPEC-122 bumps 5 -> 6.
STALE_COUNT=$(grep -E "4 reviewer|5 reviewer|6 reviewer|6 specialist lenses" "$VALIDATE_CMD" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "spec-validate.md has no stale 4/5/6 reviewer or '6 specialist lenses' references" "0" "$STALE_COUNT"
# spec.md's Design-block comment names the advisory reviewers too; a count there rots on every new lens.
STALE_SPEC=$(grep -cE "[0-9]+ advisory reviewers" "$KIT_DIR/commands/spec.md")
assert_eq "commands/spec.md names the advisory reviewers without a count" "0" "$STALE_SPEC"

# SPEC-314: Reviewer 7 (sustainability) exists and stays advisory. The BLOCKING check is scoped
# to Reviewer 7's own section, because that section may name Reviewer 6 as the blocking one.
RC=0; grep -qE "^### Reviewer 7:" "$VALIDATE_CMD" || RC=1
assert_eq "spec-validate.md has Reviewer 7 (sustainability)" "0" "$RC"
R7_BLOCKING=$(awk '/^### Reviewer 7/{f=1} /^## Output format/{f=0} f' "$VALIDATE_CMD" | grep -c 'BLOCKING')
R7_LINES=$(awk '/^### Reviewer 7/{f=1} /^## Output format/{f=0} f' "$VALIDATE_CMD" | wc -l | tr -d ' ')
assert_eq "spec-validate.md Reviewer 7 section carries no BLOCKING marker" "0" "$R7_BLOCKING"
RC=0; [ "$R7_LINES" -gt 5 ] || RC=1
assert_eq "spec-validate.md Reviewer 7 section is non-empty (scope guard can match)" "0" "$RC"

# Fresh-context spec validation: every entry point dispatches the same read-only validator and
# the lead owns the records; a self-run pass never counts, and spec-validate records ran on
# APPROVED only.
SPEC_CMD_F="$KIT_DIR/commands/spec.md"; EXEC_CMD_F="$KIT_DIR/commands/execute.md"; WRAP_CMD_F="$KIT_DIR/commands/wrap.md"
fhas() { grep -qF -- "$2" "$1"; }
RC=0; fhas "$SPEC_CMD_F" 'fresh-context `general-purpose` subagent' || RC=1
assert_eq "spec.md dispatches a fresh general-purpose validator" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'Invoke `kit:spec-validate` through the Skill tool' && fhas "$SPEC_CMD_F" 'READ-ONLY' || RC=1
assert_eq "spec.md validator prompt: Skill kit:spec-validate, read-only" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'Sonnet for Reviewers 1 to 5 and 7 on every lane, Reviewer 6 on Opus' || RC=1
assert_eq "spec.md validator tier: Sonnet for Reviewers 1-5 and 7 on every lane, Reviewer 6 on Opus" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'Opus on the full lane' && RC=1
assert_eq "spec.md: no reviewer tier rides the lane any more (old Opus-on-full wording gone)" "0" "$RC"
RC=0; fhas "$EXEC_CMD_F" 'Sonnet for Reviewers 1 to 5 and 7 on every lane, Reviewer 6 on Opus' || RC=1
assert_eq "execute.md preflight dispatches the same tiers as spec.md step 5" "0" "$RC"
# Review diet: round cap, critical bar, fold-diff check, warning routing, lane rule.
RC=0; fhas "$SPEC_CMD_F" 'The normal lane gets 1 validation round' && fhas "$SPEC_CMD_F" 'The full lane keeps its ceiling of 3 rounds' || RC=1
assert_eq "spec.md step 5: normal lane gets 1 validation round, full lane keeps ceiling 3" "0" "$RC"
RC=0; fhas "$VALIDATE_CMD" "A finding is CRITICAL only if the spec's own tests would miss it" || RC=1
assert_eq "spec-validate.md: critical only if the spec's own tests would miss it" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'one reviewer reads only the fold diff' || RC=1
assert_eq "spec.md step 5: fold-diff check is the default re-check" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'Validate ran "fold-diff check pass after NEEDS REVISION"' || RC=1
assert_eq "spec.md step 5: a clean normal-lane fold-diff check records Validate ran" "0" "$RC"
RC=0; grep -rqE '^\|\|\|\|\|\|\| ' "$KIT_DIR/commands" && RC=1
assert_eq "commands/: no leftover diff3 conflict-base markers" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'docs/implementation-notes/<slug>.md` for the builder' && fhas "$VALIDATE_CMD" 'docs/implementation-notes/<slug>.md` for the builder' || RC=1
assert_eq "spec.md and spec-validate.md route build-catchable warnings to implementation notes" "0" "$RC"
RC=0; fhas "$KIT_DIR/docs/WORKFLOW.md" 'copies its `Lane:` from `lib/classify/lane-classify.sh`' && fhas "$KIT_DIR/docs/WORKFLOW.md" 'a misroute' || RC=1
assert_eq "WORKFLOW.md: a kit spec copies its lane from the classifier; full by habit is a misroute" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'Validate ran "APPROVED critical=0 warnings=<K> fresh agent=<id>"' && fhas "$SPEC_CMD_F" 'Validate skipped "NEEDS REVISION: <criticals>"' || RC=1
assert_eq "spec.md: the lead records ran on APPROVED, skipped otherwise" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'VALIDATE PENDING: <spec path>' || RC=1
assert_eq "spec.md: no subagent tool stops with VALIDATE PENDING" "0" "$RC"
RC=0; fhas "$SPEC_CMD_F" 'Remind the user they can run `/kit:spec-validate`' && RC=1
assert_eq "spec.md: the validate reminder line is gone" "0" "$RC"
S_SPECRAN=$(grep -n 'record <rid> Spec ran' "$SPEC_CMD_F" | head -1 | cut -d: -f1)
S_DISPATCH=$(grep -n 'fresh-context `general-purpose` subagent' "$SPEC_CMD_F" | head -1 | cut -d: -f1)
RC=0; [ -n "$S_SPECRAN" ] && [ -n "$S_DISPATCH" ] && [ "$S_DISPATCH" -gt "$S_SPECRAN" ] || RC=1
assert_eq "spec.md dispatches the validator after recording Spec ran" "0" "$RC"
RC=0; fhas "$EXEC_CMD_F" "awk -F' [|] ' '\$2==\"GATE\" && \$3==\"validate\"{s=\$4} END{exit !(s==\"ran\"||s==\"override\")}'" || RC=1
assert_eq "execute.md preflight carries the field-parsed last-line-wins validate read" "0" "$RC"
E_RECHECK=$(grep -n '^### Spec->build lane re-check' "$EXEC_CMD_F" | cut -d: -f1)
E_PRE=$(grep -n '^### Validation preflight' "$EXEC_CMD_F" | cut -d: -f1)
RC=0; [ -n "$E_RECHECK" ] && [ -n "$E_PRE" ] && [ "$E_PRE" -gt "$E_RECHECK" ] || RC=1
assert_eq "execute.md preflight sits after the lane re-check" "0" "$RC"
RC=0; fhas "$EXEC_CMD_F" 'stops before the build with nothing folded' && fhas "$EXEC_CMD_F" 'Execute never builds a spec whose validation did not pass' || RC=1
assert_eq "execute.md preflight: a critical stops before the build" "0" "$RC"
RC=0; fhas "$EXEC_CMD_F" 'outcome <rid> Validate end caught=true' || RC=1
assert_eq "execute.md preflight: the stop path records and closes the bracket" "0" "$RC"
RC=0; fhas "$WRAP_CMD_F" 'stops with `VALIDATE PENDING: <spec path>`' && fhas "$WRAP_CMD_F" 'SendMessage' && fhas "$WRAP_CMD_F" 'fresh builder' || RC=1
assert_eq "wrap.md step 10 splits write and validate (VALIDATE PENDING, SendMessage, fresh builder)" "0" "$RC"
RC=0; fhas "$WRAP_CMD_F" 'runs the `kit:spec-validate` lenses' && RC=1
assert_eq "wrap.md: the self-run validate sentence is gone" "0" "$RC"
RC=0; fhas "$WRAP_CMD_F" 'nothing is committed and the item stays' && RC=1
assert_eq "wrap.md: the nothing-is-committed BLOCK sentence is gone" "0" "$RC"
RC=0; fhas "$VALIDATE_CMD" 'On APPROVED only' && fhas "$VALIDATE_CMD" 'Validate skipped "NEEDS REVISION: <criticals>"' || RC=1
assert_eq "spec-validate.md records ran on APPROVED only, skipped otherwise" "0" "$RC"
RC=0; fhas "$VALIDATE_CMD" 'design-record skipped "critical: <finding>"' || RC=1
assert_eq "spec-validate.md records a Reviewer 6 critical as design-record skipped" "0" "$RC"
RC=0; fhas "$VALIDATE_CMD" 'Validate ran "<APPROVED|NEEDS REVISION>' && RC=1
assert_eq "spec-validate.md no longer records ran on NEEDS REVISION" "0" "$RC"

# ============================================================
echo ""
echo "=== SPEC-357 T18: wrap.distill harvest mode documented in wrap.md ==="
# ============================================================
# The command doc must carry all three states of the third knob value: active
# (sweep marker + harvest.enable on THIS host), inactive (knob resolves as
# true), and the explicit `distill` word override, plus the two FYI STATE rows
# AC28 pins (the knob row and the --status row).
WRAPF="$KIT_DIR/commands/wrap.md"
RC=0; grep -q '`harvest`' "$WRAPF" || RC=1
assert_eq "wrap.md names the third wrap.distill value" 0 $RC
RC=0; grep -qF 'sweep/installed' "$WRAPF" || RC=1
assert_eq "wrap.md scopes harvest mode to the installed marker" 0 $RC
RC=0; grep -qF 'SKIPPED: distill runs in the harvest sweep' "$WRAPF" || RC=1
assert_eq "wrap.md pins the harvest SKIPPED Built/Seam wording" 0 $RC
RC=0; grep -qF 'in phase 1 the sweep reports candidates and builds none' "$WRAPF" || RC=1
assert_eq "wrap.md carries the harvest FYI STATE knob row" 0 $RC
RC=0; grep -qF 'harvest_sweep.py --status' "$WRAPF" || RC=1
assert_eq "wrap.md carries the --status STATE row for the newest report" 0 $RC
RC=0; grep -qF 'not installed on this host' "$WRAPF" || RC=1
assert_eq "wrap.md carries the inactive-host STATE row (knob resolves as true)" 0 $RC
RC=0; grep -qF 'sweep will also see this session' "$WRAPF" || RC=1
assert_eq "wrap.md carries the explicit-distill override FYI" 0 $RC

# Validate by size: a small normal-lane spec records an override instead of the 7-reviewer round;
# the battery review leg rides Sonnet on normal and Opus on full.
BATTERY_CMD_F="$KIT_DIR/commands/battery.md"
RC=0; fhas "$SPEC_CMD_F" 'spec.sh depth size' && fhas "$SPEC_CMD_F" 'small spec: normal lane, standard depth, N tasks; post-build review covers it' || RC=1
assert_eq "spec.md step 5: a small spec records a Validate override, sized by the depth size verb" "0" "$RC"
RC=0; fhas "$EXEC_CMD_F" 'spec.sh depth size' && fhas "$EXEC_CMD_F" 'small spec: normal lane, standard depth, N tasks; post-build review covers it' || RC=1
assert_eq "execute.md preflight: the same size check and override line" "0" "$RC"
RC=0; fhas "$BATTERY_CMD_F" 'Sonnet (mid) on the normal lane, high (Opus-class) on the full lane' || RC=1
assert_eq "battery.md leg 2: Sonnet on normal, Opus on full" "0" "$RC"
RC=0; fhas "$KIT_DIR/docs/WORKFLOW.md" 'runs on large specs only' || RC=1
assert_eq "WORKFLOW.md: fresh-context validation no longer runs at every depth" "0" "$RC"
RC=0; grep -qF 'validator runs at every depth' "$KIT_DIR/docs/WORKFLOW.md" && RC=1
assert_eq "WORKFLOW.md Depth paragraph: no stale 'validator runs at every depth' claim" "0" "$RC"
RC=0; fhas "$KIT_DIR/docs/WORKFLOW.md" 'The fresh-context validator runs on every full-lane spec and on large normal-lane specs' || RC=1
assert_eq "WORKFLOW.md Depth paragraph: validator follows the size rule" "0" "$RC"

RC=0; for F in execute spec; do grep -qF 'include `rid=<rid>`' "$KIT_DIR/commands/$F.md" || RC=1; done
assert_eq "execute.md and spec.md state the rid=<rid> dispatch-description convention" 0 $RC

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
