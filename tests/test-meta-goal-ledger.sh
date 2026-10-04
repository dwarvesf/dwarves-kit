#!/bin/bash
# test-meta-goal-ledger.sh -- goal-ledger structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-goal-ledger.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

# ============================================================
echo ""
echo "=== Multi-session: goal-registry + ADR-0022 (SPEC-036) ==="
# ============================================================

# (a) The cross-session registry helper exists and is executable (pure-bash substrate).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/goal/goal-registry.sh" ] && [ -x "$KIT_DIR/lib/goal/goal-registry.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/goal/goal-registry.sh exists and is executable (SPEC-036)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/goal/goal-registry.sh missing or not executable"
  FAIL=$((FAIL + 1))
fi

# (b) goal-registry reuses the dispatch-gate disjointness rule (no second moat).
TOTAL=$((TOTAL + 1))
if grep -q 'dispatch-gate.sh' "$KIT_DIR/lib/goal/goal-registry.sh" 2>/dev/null \
   && ! grep -q '^prefix_overlap()' "$KIT_DIR/lib/goal/goal-registry.sh" 2>/dev/null; then
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
   && grep -q 'cross-session registry decision' "$KIT_DIR/commands/kit-health.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} kit-health carries the running-goal-registry carve-out (cross-session registry decision)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health must record the running-goal-registry carve-out citing the cross-session registry decision"
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

# (a) lib/goal/goal-drafts.sh exists and is executable.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/goal/goal-drafts.sh" ] && [ -x "$KIT_DIR/lib/goal/goal-drafts.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/goal/goal-drafts.sh exists and is executable (SPEC-037)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/goal/goal-drafts.sh missing or not executable"
  FAIL=$((FAIL + 1))
fi

# (b) The LIVE goal-draft contract carries no INDEX.md (the phantom is gone; only the
#     annotated historical record in ADR-0011/ADR-0023/SPEC-005 keeps the word).
LIVE_INDEX=$(grep -l 'INDEX\.md' "$KIT_DIR/commands/assign.md" "$KIT_DIR/commands/start.md" "$KIT_DIR/commands/next.md" "$KIT_DIR/docs/WORKFLOW.md" "$KIT_DIR/docs/architecture.md" 2>/dev/null | wc -l | tr -d ' ')
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
if { trap '' PIPE; printf '%s' "$SM_SECTION" 2>/dev/null || :; } | grep -q '\.claude/goals' && { trap '' PIPE; printf '%s' "$SM_SECTION" 2>/dev/null || :; } | grep -q 'kit-goals'; then
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
  echo -e "  ${RED}FAIL${NC} /kit:ship must run lib/goal/goal-drafts.sh archive"
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
   && grep -q 'integration-verifier' "$KIT_DIR/commands/verify.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} verify.md dispatches task-verifier + integration-verifier (SPEC-035)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} verify.md must dispatch task-verifier + integration-verifier"
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

assert_true "lib/gate/gate-ledger.sh exists and is executable" "$([ -x "$KIT_DIR/lib/gate/gate-ledger.sh" ] && echo 0 || echo 1)"
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
' "$KIT_DIR/docs/WORKFLOW.md")
assert_eq "lane×phase matrix cells are all measure-twice|run-lite|skip" "0" "$GL_BADCELLS"

GL_REQ="$(bash "$KIT_DIR/lib/gate/gate-ledger.sh" required normal 2>/dev/null | tr '\n' ' ')"
assert_true "gate-ledger required(normal) derives spec+build+ship from the matrix" "$({ trap '' PIPE; echo "$GL_REQ" 2>/dev/null || :; } | grep -q 'spec' && { trap '' PIPE; echo "$GL_REQ" 2>/dev/null || :; } | grep -q 'build' && { trap '' PIPE; echo "$GL_REQ" 2>/dev/null || :; } | grep -q 'ship' && echo 0 || echo 1)"
assert_true "WORKFLOW documents the gate-ledger + ship-enforcement convention" "$(grep -q 'Gate ledger and ship enforcement' "$KIT_DIR/docs/WORKFLOW.md" && echo 0 || echo 1)"
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
echo "=== SPEC-070: rid standardization pins ==="
# ============================================================
# Agreement pin (INTENTIONAL SEAM): both ends of the rid contract carry the
# exact #*/ strip transform; if either drops it, the contract is broken.
RC=0; grep -qF '#*/' "$KIT_DIR/hooks/ship-gate.sh" || RC=1
assert_eq "agreement pin: ship-gate carries the #*/ transform" 0 $RC
RC=0; grep -qF '#*/' "$KIT_DIR/lib/gate/gate-ledger.sh" || RC=1
assert_eq "agreement pin: gate-ledger rid carries the #*/ transform" 0 $RC
RC=0; grep -q '^  rid)' "$KIT_DIR/lib/gate/gate-ledger.sh" || RC=1
assert_eq "gate-ledger dispatches the rid verb" 0 $RC

# Sweep pin (AC5): no gate-ledger call site still uses <spec-slug> as a rid
# (debug.md's escaped-from spec REFERENCE is exempt; doc-path uses are not calls).
RESIDUAL=$(grep -rn 'spec-slug\|record <slug>' "$KIT_DIR/commands/" "$KIT_DIR/AGENTS.md" "$KIT_DIR/docs/WORKFLOW.md" 2>/dev/null | grep 'gate-ledger' | grep -v 'escaped-from' | wc -l | tr -d ' ')
assert_eq "sweep pin: zero gate-ledger rid call sites say spec-slug" "0" "$RESIDUAL"

# Entry-point wiring: assign derives the rid; AGENTS documents the contract once.
RC=0; grep -q 'gate-ledger.sh rid' "$KIT_DIR/commands/assign.md" || RC=1
assert_eq "assign.md derives RID via gate-ledger rid" 0 $RC
RC=0; grep -q 'SPEC-070' "$KIT_DIR/AGENTS.md" || RC=1
assert_eq "AGENTS.md carries the one-rid-per-run contract" 0 $RC

# ============================================================
echo ""
echo "=== SPEC-080: verify-this delta + tripwires (ID-077/080) ==="
# ============================================================
VF="$KIT_DIR/commands/verify.md"
RT80="$KIT_DIR/commands/review-team.md"
RC=0; grep -qF 'condition + metric + threshold' "$VF" || RC=1
assert_eq "verify carries the claim-restatement preamble (ID-077)" 0 $RC
RC=0; grep -qF 'PASS / FAIL / INCONCLUSIVE' "$VF" && grep -qF 'honest third verdict' "$VF" || RC=1
assert_eq "INCONCLUSIVE is a legal verdict with named causes" 0 $RC
RC=0; grep -qF 'Baseline:' "$KIT_DIR/docs/verification/README.md" || RC=1
assert_eq "verification README carries the comparative-evidence line" 0 $RC
RC=0; grep -qF '1k lines' "$RT80" && grep -qiF 'spaghetti' "$RT80" || RC=1
assert_eq "Reviewer 2 carries both tripwires (ID-080)" 0 $RC
RC=0; grep -qiE "Verdict:.*INCONCLUSIVE" "$KIT_DIR/lib/gate/proof-ledger.sh" || RC=1
assert_eq "proof-ledger REJECTS an INCONCLUSIVE verdict (SPEC-080 guard present)" 0 $RC


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
