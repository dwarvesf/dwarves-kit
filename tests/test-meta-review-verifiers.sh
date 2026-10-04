#!/bin/bash
# test-meta-review-verifiers.sh -- review-verifiers structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-review-verifiers.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

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
TOTAL=$((TOTAL + 1))
if grep -qF '[[QL-VERDICT' "$KIT_DIR/commands/gauntlet.md" 2>/dev/null && grep -qF 'round=N clean=' "$KIT_DIR/commands/gauntlet.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} gauntlet.md emits the QL-VERDICT round marker, preset-invariant (SPEC-235)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} gauntlet.md lost the QL-VERDICT round marker"
  FAIL=$((FAIL + 1))
fi

# SPEC-201: AI-in-the-loop cost-tier taxonomy in /kit:test-plan (Step 1c) + the
# test-plan-review-team's 6th lens (Tiering & floor). DECISION-BRIEF-behavioral-test-tiering.md
# SG-1/SG-2. Pin the 5 doctrine facts test-plan.md must carry (positive), the 6th-lens wiring
# in test-plan-review-team.md, and a negative control: the exact old "5 lenses" framing that
# would silently drop lens 6 must not linger anywhere the lens count is stated.
TP_TIER_CMD="$KIT_DIR/commands/test-plan.md"
TOTAL=$((TOTAL + 1))
if grep -qF 'Step 1c' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF '`mechanical`' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF '`smoke`' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF '`behavioral`' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md Step 1c names all three cost tiers (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md missing Step 1c or one of the three tier names"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'config asserts lie; a behavior claim keeps a real-model probe' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md states the floor rule verbatim (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md lost the verbatim floor rule"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'Never delete or downgrade a behavior/security claim below the `behavioral` tier to cut cost' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF 'Never let a `smoke`-tier run gate a ship' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md states both hard don'ts verbatim (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md lost one or both verbatim hard don'ts"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'smoke-eligible' "$TP_TIER_CMD" 2>/dev/null && grep -qF 'retry-eligible' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF 'allowlist' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md states the smoke/retry doctrine (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md lost the smoke/retry doctrine"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'Tier | Smoke-eligible | Retry-eligible' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF 'AI-in-the-loop doctrine' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md Step 3 template carries the tier columns + doctrine block (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md Step 3 template dropped the tier columns or doctrine block"
  FAIL=$((FAIL + 1))
fi
# AC1(a) (review finding): the detection-signal sentence itself, not just the tier names it
# leads into, must survive a regression.
TOTAL=$((TOTAL + 1))
if grep -qF '### Step 1c: AI-in-the-loop tiering' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF 'operative test' "$TP_TIER_CMD" 2>/dev/null \
   && grep -qF 'observing a live model' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md Step 1c states the AI-in-the-loop detection signal + operative test (SPEC-201 AC1a)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md lost the AI-in-the-loop detection-signal wording"
  FAIL=$((FAIL + 1))
fi
# Review finding: a security/side-effect case must never be smoke-eligible (the brief's exit
# criterion says "never-retry, never-smoke", not just never-retry).
TOTAL=$((TOTAL + 1))
if grep -qF 'security or side-effect case is NEVER smoke-eligible' "$TP_TIER_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan.md states security/side-effect cases are never smoke-eligible (SPEC-201, brief exit criterion c)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan.md lost the never-smoke-eligible rule for security/side-effect cases"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'Tiering & floor' "$TPRT_CMD" 2>/dev/null \
   && grep -qF 'not an AI-in-the-loop plan' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md carries the Tiering & floor lens, N/A-safe (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md missing the Tiering & floor lens"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF '6 lenses' "$TPRT_CMD" 2>/dev/null && grep -qF 'Dispatch 6 lenses' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md lens count is 6 in the title and Step 2 heading (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md lens count not updated to 6 everywhere"
  FAIL=$((FAIL + 1))
fi
# AC3 (review finding): the frontmatter `description:` line is a distinct location from the
# Step 2 heading checked above (a regression could flip one and miss the other). Scope the
# check to the description line itself so it is not vacuously satisfied by Step 2's own text.
TOTAL=$((TOTAL + 1))
TPRT_DESC_LINE=$(grep -m1 '^description:' "$TPRT_CMD" 2>/dev/null || true)
if { trap '' PIPE; printf '%s' "$TPRT_DESC_LINE" 2>/dev/null || :; } | grep -qF '6 test-design lenses'; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md frontmatter description says '6 test-design lenses' (SPEC-201 AC3)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md frontmatter description lost '6 test-design lenses'"
  FAIL=$((FAIL + 1))
fi
# Negative control: the stale "5 subagents"/"5 angles"/"5 test-design lenses" framing
# (pre-SPEC-201) would silently cap the dispatch at 5 and drop lens 6. Must NOT appear anymore.
TOTAL=$((TOTAL + 1))
if grep -qE '5 (subagents|angles|test-design lenses)' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC} [NC] test-plan-review-team.md still says '5 subagents'/'5 angles'/'5 test-design lenses' (lens 6 would be silently dropped)"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC} [NC] test-plan-review-team.md dropped the stale 5-lens framing (SPEC-201)"
  PASS=$((PASS + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qF 'Tiering & floor: [X]/10, or N/A' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md scores template includes the 6th (N/A-able) score line (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md scores template missing the 6th score line"
  FAIL=$((FAIL + 1))
fi
# The pre-registered negative control from the brief: a plan that puts a boundary claim in
# the config (mechanical) tier must be a pattern the lens explicitly names as CRITICAL.
TOTAL=$((TOTAL + 1))
if grep -qF 'config tier' "$TPRT_CMD" 2>/dev/null && grep -qE 'boundary.{0,40}mechanical|mechanical.{0,40}boundary' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} [NC] test-plan-review-team.md lens 6 names the boundary-claim-in-config-tier negative control (SPEC-201, brief exit criterion)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} [NC] test-plan-review-team.md lens 6 does not name the boundary-in-config-tier negative control"
  FAIL=$((FAIL + 1))
fi
# Review finding: "each lens returns 2-5 findings" contradicted lens 6's N/A (0 findings,
# no score) path -- a subagent told a hard floor of 2 would hallucinate on a clean/N/A plan.
TOTAL=$((TOTAL + 1))
if grep -qF '0-5 findings' "$TPRT_CMD" 2>/dev/null && ! grep -qF '2-5 findings' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} [NC] test-plan-review-team.md findings range allows 0, stale '2-5' gone (no forced-finding hallucination risk on N/A/clean, SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} [NC] test-plan-review-team.md still forces a 2-5 finding floor, contradicting lens 6's N/A path"
  FAIL=$((FAIL + 1))
fi
# Review finding: lens 4's ladder "smoke" stage and lens 6's `smoke` cost tier are different
# concepts sharing a word in the same dispatch prompt; the disambiguation must be present.
TOTAL=$((TOTAL + 1))
if grep -qF 'ladder-smoke stage' "$TPRT_CMD" 2>/dev/null || grep -qF 'ladder smoke stage' "$TPRT_CMD" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} test-plan-review-team.md disambiguates lens 6's smoke tier from lens 4's ladder smoke stage (SPEC-201)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-plan-review-team.md missing the smoke-tier vs ladder-smoke-stage disambiguation"
  FAIL=$((FAIL + 1))
fi

# SPEC-201 AC4: the §5b dialect table (SPEC-056/057) stays byte-identical -- same 12 types,
# same row count -- and gains a cross-reference paragraph AFTER the table, not inside it.
TDS_CMD="$KIT_DIR/docs/verification/test-design-standard.md"
TOTAL=$((TOTAL + 1))
DIALECT_ROWS_201=$(awk '/^## 5b/,/^## 6/' "$TDS_CMD" | grep -cE '^\| (incident|learning|planning|operate|eval|research|review|reconcile|doc|migration|data-tool|spec-feature) \|')
if [ "$DIALECT_ROWS_201" = "12" ]; then
  echo -e "  ${GREEN}PASS${NC} test-design-standard.md §5b dialect table still has all 12 rows, untouched (SPEC-201 AC4)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-design-standard.md §5b dialect table row count changed (got $DIALECT_ROWS_201, want 12)"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if awk '/^## 5b/,/^## 6/' "$TDS_CMD" | grep -qF 'Step 1c'; then
  echo -e "  ${GREEN}PASS${NC} test-design-standard.md §5b cross-references Step 1c (SPEC-201 AC4)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} test-design-standard.md §5b missing the Step 1c cross-reference"
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
echo "=== Integration-verifier (SPEC-021) ==="
# ============================================================
# The cross-task wiring verifier must exist, stay read-only (no write tools in
# its frontmatter), and be dispatched by /execute. The generic agent-loop above
# already checks its name/description/model and the MANUAL cross-ref.

ICA="$KIT_DIR/agents/integration-verifier.md"
TOTAL=$((TOTAL + 1))
if [ -f "$ICA" ]; then
  echo -e "  ${GREEN}PASS${NC} agents/integration-verifier.md exists"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} agents/integration-verifier.md missing"
  FAIL=$((FAIL + 1))
fi

# Read-only contract: no bare Bash and no Edit/Write/MultiEdit in the tools list.
# Scoped Bash(...) entries do not match (they have a paren), so they are allowed.
WRITE_TOOLS=$(grep -cE '^[[:space:]]*-[[:space:]]+(Edit|Write|MultiEdit|Bash)[[:space:]]*$' "$ICA" 2>/dev/null || true)
assert_eq "integration-verifier has no write/bare-Bash tools (DEC-006)" "0" "$WRITE_TOOLS"

TOTAL=$((TOTAL + 1))
if grep -q 'integration-verifier' "$KIT_DIR/commands/execute.md" 2>/dev/null \
   && grep -q 'base ref' "$KIT_DIR/commands/execute.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} commands/execute.md dispatches the integration-verifier with a base ref"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} commands/execute.md does not wire the integration-verifier (+base ref)"
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
echo "=== SPEC-078: review-team routing + tiering (ID-076/078) ==="
# ============================================================
RT="$KIT_DIR/commands/review-team.md"
RC=0; grep -qF 'gated_auto' "$RT" && grep -qF 'advisory' "$RT" && grep -qF 'route conservatively' "$RT" || RC=1
assert_eq "review-team carries the 3 apply-classes + conservative rule (ID-076)" 0 $RC
RC=0; grep -qF 'Route:' "$RT" || RC=1
assert_eq "report template carries the Route line" 0 $RC
RC=0; grep -qF 'becomes a board row' "$RT" && grep -qF 'responding-to-review' "$RT" || RC=1
assert_eq "decision gate routes each class to its destination" 0 $RC
RC=0; grep -qF 'matching the session model' "$RT" && grep -qF 'model: sonnet' "$RT" && grep -qF 'silently down-tier' "$RT" || RC=1
assert_eq "model tiering named per lens (ID-078)" 0 $RC
RC=0; grep -qiF 'if the override is unavailable' "$RT" || RC=1
assert_eq "tiering fallback sentence present" 0 $RC


# ============================================================
echo ""
echo "=== SPEC-081: anchored-confidence merge (ID-075) ==="
# ============================================================
RT81="$KIT_DIR/commands/review-team.md"
RC=0; grep -qF 'Confidence anchors (EveryInc findings-schema)' "$RT81" || RC=1
assert_eq "Step 2 carries the confidence-anchor contract" 0 $RC
for a in "another lens would likely agree" "I can name the failing input" "the logic is airtight"; do
  RC=0; grep -qF "$a" "$RT81" || RC=1
  assert_eq "anchor self-test present: $a" 0 $RC
done
RC=0; grep -qF 'line-bucket' "$RT81" && grep -qF 'normalized title' "$RT81" || RC=1
assert_eq "fingerprint dedup rule present" 0 $RC
RC=0; grep -qF 'ONE anchor step' "$RT81" || RC=1
assert_eq "corroboration promotion rule present" 0 $RC
RC=0; grep -qF 'below 75 are suppressed' "$RT81" && grep -qF 'CRITICAL survives at 50' "$RT81" || RC=1
assert_eq "late confidence gate present (<75; CRITICAL at 50+)" 0 $RC
RC=0; grep -qF 'never silently dropped' "$RT81" && grep -qF 'Suppressed findings (below the confidence gate, or refuted by a validator)' "$RT81" || RC=1
assert_eq "suppressed-appendix never-drop rule + template section present" 0 $RC
RC=0; grep -qF 'Confidence: ' "$RT81" || RC=1
assert_eq "report rows carry Confidence" 0 $RC
# AC4 ordering: promotion paragraph before the gate paragraph
# (one-occurrence assumption: both anchor strings must stay unique in the file)
RC=0; [ "$(grep -c 'ONE anchor step' "$RT81")" = "1" ] && [ "$(grep -c 'below 75 are suppressed' "$RT81")" = "1" ] || RC=1
assert_eq "ordering-pin anchor strings are unique" 0 $RC
P=$(grep -n 'ONE anchor step' "$RT81" | head -1 | cut -d: -f1)
G=$(grep -n 'below 75 are suppressed' "$RT81" | head -1 | cut -d: -f1)
RC=0; [ -n "$P" ] && [ -n "$G" ] && [ "$P" -lt "$G" ] || RC=1
assert_eq "the confidence gate runs LATE (after promotion, by file order)" 0 $RC



# ============================================================
echo ""
echo "=== SPEC-082: per-finding validators (ID-079) ==="
# ============================================================
RT82="$KIT_DIR/commands/review-team.md"
RC=0; grep -qF 'Step 3b: Validate verdict-driving findings' "$RT82" || RC=1
assert_eq "Step 3b exists" 0 $RC
RC=0; grep -qF 'PER finding, never batched' "$RT82" || RC=1
assert_eq "per-finding never-batch rule present" 0 $RC
RC=0; grep -qF 'recreates the persona-bias problem' "$RT82" || RC=1
assert_eq "upstream rationale quoted" 0 $RC
RC=0; grep -qF 'adversarial REFUTER' "$RT82" && grep -qF 'DEMOTE to the suppressed appendix carrying the refutation' "$RT82" || RC=1
assert_eq "refuter framing + refuted disposition present" 0 $RC
RC=0; grep -qF 'marked validated' "$RT82" || RC=1
assert_eq "confirmed disposition present" 0 $RC
RC=0; grep -qF 'NEVER drops a CRITICAL/HIGH' "$RT82" && grep -qF 'unvalidated' "$RT82" || RC=1
assert_eq "infra-failure fail-safe present" 0 $RC
RC=0; grep -qF 'UNSUPPRESSED finding with severity CRITICAL or HIGH' "$RT82" || RC=1
assert_eq "scope line present (unsuppressed P0/P1 only)" 0 $RC
# ordering: 3b after the late gate, before Step 4
G=$(grep -n 'below 75 are suppressed' "$RT82" | head -1 | cut -d: -f1)
B=$(grep -n 'Step 3b: Validate verdict-driving findings' "$RT82" | head -1 | cut -d: -f1)
S4=$(grep -n '### Step 4' "$RT82" | head -1 | cut -d: -f1)
RC=0; [ -n "$G" ] && [ -n "$B" ] && [ -n "$S4" ] && [ "$G" -lt "$B" ] && [ "$B" -lt "$S4" ] || RC=1
assert_eq "Step 3b sits between the confidence gate and Step 4" 0 $RC


# ============================================================
echo ""
echo "=== ADR-0029: review-function naming convention (SG-08) ==="
# ============================================================
# The SG-08 rename (three retired-suffix agent names migrated onto the
# reviewer/verifier/team axis; see ADR-0029) is a one-time migration; this
# block is the machine enforcement that keeps a FUTURE off-axis review-agent
# name from landing silently. Two pure-function checks below (name -> pass/fail)
# back both the real-roster scan (a)/(b) and the negative control (c), so the
# same logic that gates the repo is the logic proven to discriminate.

# is_retired_suffix NAME -> 0 (banned) | 1 (not banned)
# Retired per the ADR-0029 rename map: -checker, -auditor, bare "reviewer",
# and "-validate" used as a review-function suffix.
is_retired_suffix() {
  case "$1" in
    *-checker) return 0 ;;
    *-auditor) return 0 ;;
    reviewer) return 0 ;;
    *-validate) return 0 ;;
    *) return 1 ;;
  esac
}

# is_on_review_axis NAME -> 0 (conforms) | 1 (off-axis)
# The convention's positive axis: a review-function name ends in -reviewer
# (static/left-arm), -verifier (dynamic/right-arm), or -team (panel command).
# advisor, agent-effectiveness, and break-it are the named-noun exceptions (see (b)).
is_on_review_axis() {
  case "$1" in
    *-reviewer) return 0 ;;
    *-verifier) return 0 ;;
    *-team) return 0 ;;
    advisor) return 0 ;;
    agent-effectiveness) return 0 ;;
    # break-it reads the WHOLE branch for an unconstrained input, so it is a
    # cross-cutting named-noun lens like advisor, not a per-artifact -reviewer.
    break-it) return 0 ;;
    *) return 1 ;;
  esac
}

# (a) GLOBAL BAN, roster-scanning: no agent, command, or skill name may use a
# retired suffix. The roster is DERIVED from the live dirs (same derivation
# style as the SPEC-219 registry-freshness pin), so a new commands/foo-checker.md
# or skills/foo-validate/ fails here the moment it lands, without anyone
# updating this test. Grandfathered names predate this widening and are pinned
# pending the operator decisions recorded in
# docs/research/2026-08-01-naming-reconciliation.md (visible debt, not license):
#   spec-validate -- finding 3 / proposal "/kit:spec-validate -> /kit:spec-team"
#                    (a dedicated migration PR with a legacy alias window).
RETIRED_GRANDFATHERED="spec-validate"
ALL_NAMES=""
for AGENT_FILE in "$KIT_DIR/agents/"*.md; do
  ALL_NAMES="$ALL_NAMES agents/$(awk -F': ' '/^name:/{print $2; exit}' "$AGENT_FILE" | tr -d '[:space:]')"
done
for CMD_FILE in "$KIT_DIR/commands/"*.md; do
  ALL_NAMES="$ALL_NAMES commands/$(basename "$CMD_FILE" .md)"
done
for SKILL_DIR in "$KIT_DIR/skills/"*/; do
  ALL_NAMES="$ALL_NAMES skills/$(basename "$SKILL_DIR")"
done
for ENTRY in $ALL_NAMES; do
  NAME="${ENTRY#*/}"
  TOTAL=$((TOTAL + 1))
  if ! is_retired_suffix "$NAME"; then
    echo -e "  ${GREEN}PASS${NC} $ENTRY is not a retired suffix"
    PASS=$((PASS + 1))
  else
    case " $RETIRED_GRANDFATHERED " in
      *" $NAME "*)
        echo -e "  ${GREEN}PASS${NC} $ENTRY uses a retired suffix but is GRANDFATHERED (naming-reconciliation report, pending operator decision)"
        PASS=$((PASS + 1))
        ;;
      *)
        echo -e "  ${RED}FAIL${NC} $ENTRY uses a retired suffix"
        FAIL=$((FAIL + 1))
        ;;
    esac
  fi
done

# (b) POSITIVE AXIS, roster-scanning: every current V-model review agent must
# be on-axis, i.e. end in -reviewer/-verifier/-team, OR be one of the three
# allowed named-noun validators. `advisor` is the ADR-0028 cross-cutting
# generic lens (not per-artifact, so it earns its own noun).
# `agent-effectiveness` (SPEC-088, SG-01) is intentionally allowed too: it
# reviews an AGENT DEFINITION, not a V-model work artifact, so like `advisor`
# it is a named-noun validator, NOT a naming violation -- do not "fix" its
# name to *-reviewer.
# `break-it` (SPEC-247) joins them: it probes the WHOLE branch for an input the
# suite does not constrain, a cross-cutting lens like `advisor`, so a
# *-reviewer suffix would misname it as per-artifact -- do not "fix" it either.
# The review-agent roster is DERIVED from the live agents/ dir instead of a
# frozen name list (the pre-widening hardcoded 11 names missed every agent
# added after the list froze; naming-reconciliation finding 6): a review agent
# is any agent whose tools roster is read-only (no Write/Edit), minus the
# ADR-0029:89 out-of-scope names (the research-* prefix family and
# responding-to-review; finding 7). Grandfathered off-axis names are pinned
# pending the operator decisions in the same report:
#   audit-scanner -- finding 4 / proposal: amend ADR-0029 to sanction -scanner
#                    as the evidence-gathering class, or rename audit-reviewer.
# (claim-verifier passes this suffix scan but wears the wrong CLASS of suffix,
#  finding 2 / proposal claim-reviewer or a -team shape; a suffix scan cannot
#  police semantics, so that stays a report proposal, not a test.)
# devops-triage -- shipped read-only with no axis suffix (SPEC-239 era);
#                  proposal: triage-reviewer, or sanction -triage as an
#                  incident class. Pending operator decision (ID-639).
AXIS_GRANDFATHERED="audit-scanner devops-triage"
REVIEW_AGENTS=""
for AGENT_FILE in "$KIT_DIR/agents/"*.md; do
  AGENT_NAME=$(awk -F': ' '/^name:/{print $2; exit}' "$AGENT_FILE" | tr -d '[:space:]')
  case "$AGENT_NAME" in research-*|responding-to-review) continue ;; esac
  WRITECAP=$(awk '/^---$/{c++; next} c==1' "$AGENT_FILE" | grep -cE '^[[:space:]]*-[[:space:]]*(Write|Edit|MultiEdit|NotebookEdit)$')
  [ "$WRITECAP" -eq 0 ] || continue
  REVIEW_AGENTS="$REVIEW_AGENTS $AGENT_NAME"
done
for NAME in $REVIEW_AGENTS; do
  TOTAL=$((TOTAL + 1))
  if is_on_review_axis "$NAME"; then
    echo -e "  ${GREEN}PASS${NC} review agent '$NAME' is on the naming axis (reviewer|verifier|team|named-noun)"
    PASS=$((PASS + 1))
  else
    case " $AXIS_GRANDFATHERED " in
      *" $NAME "*)
        echo -e "  ${GREEN}PASS${NC} review agent '$NAME' is OFF-axis but GRANDFATHERED (naming-reconciliation report, pending operator decision)"
        PASS=$((PASS + 1))
        ;;
      *)
        echo -e "  ${RED}FAIL${NC} review agent '$NAME' is OFF the ADR-0029 naming axis"
        FAIL=$((FAIL + 1))
        ;;
    esac
  fi
done
# Derivation floor: an awk/frontmatter format change must not silently derive
# an empty (or gutted) roster and pass vacuously. Two anchors: one pre-freeze
# name, one post-freeze addition the old hardcoded list missed.
RC=0
case " $REVIEW_AGENTS " in *" task-verifier "*) : ;; *) RC=1 ;; esac
case " $REVIEW_AGENTS " in *" api-reviewer "*) : ;; *) RC=1 ;; esac
assert_eq "derived review-agent roster contains task-verifier + api-reviewer (derivation not vacuous)" 0 $RC

# (c) NEGATIVE CONTROL: prove the ban logic actually discriminates, not just
# that it always passes. Feed it fake names only (never a real agents/ file).
RC=0
is_retired_suffix "foo-checker" || RC=1
is_retired_suffix "foo-auditor" || RC=1
is_retired_suffix "reviewer" || RC=1
is_retired_suffix "foo-validate" || RC=1
assert_eq "negative control: is_retired_suffix REJECTS foo-checker/foo-auditor/reviewer/foo-validate" 0 $RC

RC=0
is_retired_suffix "foo-reviewer" && RC=1
is_retired_suffix "foo-verifier" && RC=1
is_retired_suffix "foo-team" && RC=1
is_retired_suffix "advisor" && RC=1
assert_eq "negative control: is_retired_suffix does NOT flag conforming names (no false positives)" 0 $RC

RC=0
is_on_review_axis "foo-checker" && RC=1
is_on_review_axis "foo-auditor" && RC=1
is_on_review_axis "foo-scanner" && RC=1
assert_eq "negative control: is_on_review_axis REJECTS off-axis fake names" 0 $RC

# ============================================================
# SPEC-107: cheap-tier defaults , three authoring surfaces, one sonnet-first stance.
# (Surface 2, the plan-for-mega-goal subgoal-template, lives in the dotfiles repo and
#  is proven by a LOCAL diff, not here , its path is absent in CI.)
# ============================================================
EX="$KIT_DIR/commands/execute.md"
RC=0; grep -qiE 'workers dispatch at .?sonnet.? by default' "$EX" || RC=1
assert_eq "execute.md workers default to sonnet (SPEC-107 surface 1)" 0 $RC
RC=0; grep -qiE 'Model:.*(escape hatch|hard[- ]reasoning|override)' "$EX" || RC=1
assert_eq "execute.md names the spec Model: escape hatch (SPEC-107 surface 1)" 0 $RC

MA="$KIT_DIR/agents/meta-agent.md"
RC=0; grep -qiE 'write .?Model: sonnet' "$MA" || RC=1
assert_eq "meta-agent Mode B writes Model: sonnet on abstain (SPEC-107 surface 3)" 0 $RC
# Negative controls: the OLD contradicting stance is GONE, not merely supplemented.
RC=0; grep -qF "human's call, not a silent auto-write" "$MA" && RC=1
assert_eq "negative control: old 'human's call' contradiction removed from meta-agent" 0 $RC
RC=0; grep -qE 'OMIT the .?Model:.? line' "$MA" && RC=1
assert_eq "negative control: old 'OMIT the Model: line' abstain removed from meta-agent" 0 $RC

# ============================================================
# SPEC-244: verifier tier parity , a verifier is never dumber than its worker.
# ============================================================
PARITY='dispatch with an explicit model override matching the spec tier'
RC=0; grep -qE '^model: opus$' "$KIT_DIR/agents/recheck-verifier.md" || RC=1
assert_eq "recheck-verifier pins model: opus (SPEC-244)" 0 $RC
RC=0; grep -qF "$PARITY" "$EX" || RC=1
assert_eq "execute.md carries the verifier parity override sentence (SPEC-244)" 0 $RC
RC=0; grep -qF "$PARITY" "$KIT_DIR/commands/verify.md" || RC=1
assert_eq "verify.md carries the verifier parity override sentence (SPEC-244)" 0 $RC
# Negative control: the OLD wall-off stance is GONE from execute.md, not merely supplemented.
RC=0; grep -qF 'Verifiers keep their own frontmatter tiers (unchanged).' "$EX" && RC=1
assert_eq "negative control: old verifier wall-off sentence removed from execute.md" 0 $RC
# doc-verifier is deliberately out of scope (docs phase, not spec-tier-bound).
RC=0; grep -qE '^model: sonnet$' "$KIT_DIR/agents/doc-verifier.md" || RC=1
assert_eq "doc-verifier stays sonnet (SPEC-244 decision c)" 0 $RC

# ============================================================
# SPEC-108: meta-agent provenance , the generated agents carry a well-formed generated-by:,
# and the key is SET-EQUAL to the known generated roster (no silent spread to hand-written agents).
# ============================================================
GEN_ROSTER="acceptance-verifier advisor brief-reviewer recheck-verifier system-verifier api-reviewer data-etl-worker db-migration-worker frontend-reviewer infra-reviewer performance-reviewer"
for a in $GEN_ROSTER; do
  RC=0; grep -qE '^generated-by: draft-agent [0-9]{4}-[0-9]{2}-[0-9]{2} .+' "$KIT_DIR/agents/$a.md" || RC=1
  assert_eq "generated agent $a carries a well-formed generated-by (SPEC-108)" 0 $RC
done
GEN_ACTUAL=$(grep -lE '^generated-by:' "$KIT_DIR/agents/"*.md 2>/dev/null | while read -r f; do basename "$f" .md; done | sort | tr '\n' ' ' | sed 's/ *$//')
GEN_EXPECTED=$(printf '%s\n' $GEN_ROSTER | sort | tr '\n' ' ' | sed 's/ *$//')
assert_eq "generated-by key set-equals the known generated roster (no spread to hand-written agents)" "$GEN_EXPECTED" "$GEN_ACTUAL"

# ============================================================
# SPEC-109: operator-persona design lens , opt-in 6th visual-team lens GATED on persona-supplied
# (byte-compatible without the arg), persisted + threaded from ui-design, boundary recorded (DEC-017).
# ============================================================
VT="$KIT_DIR/commands/visual-team.md"
RC=0; grep -qF 'persona: <archetype>' "$VT" || RC=1
assert_eq "visual-team accepts a persona: <archetype> arg (SPEC-109)" 0 $RC
RC=0; grep -qiF 'operator persona' "$VT" || RC=1
assert_eq "visual-team has an operator-persona 6th lens (SPEC-109)" 0 $RC
# F1 conditionality pins , the 6th lens AND the 6th Scores row carry a persona-supplied guard,
# so an UNCONDITIONAL 6th lens (which would break byte-compat) fails the test, not just its absence.
RC=0; grep -qiE 'ONLY when a .?persona' "$VT" || RC=1
assert_eq "6th persona lens is GATED on persona-supplied (SPEC-109 conditionality)" 0 $RC
RC=0; grep -qiE 'row appears ONLY when a .?persona' "$VT" || RC=1
assert_eq "6th Scores row is GATED on persona-supplied (SPEC-109 conditionality)" 0 $RC
# NEGATIVE CONTROL: the 5 existing lenses present verbatim + no-arg fires exactly 5, byte-identical.
for L in 'Hierarchy / typography' 'System-consistency' 'Accessibility / contrast' 'Restraint / simplicity' 'Expressiveness / brand-fit'; do
  RC=0; grep -qF "$L" "$VT" || RC=1
  assert_eq "visual-team 5-lens NC: '$L' present unchanged (SPEC-109)" 0 $RC
done
RC=0; grep -qiF 'byte-identical' "$VT" || RC=1
assert_eq "visual-team no-arg path is byte-identical / exactly 5 lenses (SPEC-109 NC)" 0 $RC
# F2 ui-design PERSISTS (brief line) AND THREADS (forwards to visual-team $ARGUMENTS).
UIDESIGN="$KIT_DIR/commands/ui-design.md"
RC=0; grep -qiF 'Persona (optional)' "$UIDESIGN" || RC=1
assert_eq "ui-design brief seeds a Persona line (SPEC-109 persist)" 0 $RC
RC=0; grep -qF 'persona: <archetype>' "$UIDESIGN" || RC=1
assert_eq "ui-design Step 3 forwards Persona into visual-team ARGUMENTS (SPEC-109 thread)" 0 $RC
# Governance: DEC-017 formal in SPEC-109 + reciprocal pointer in SPEC-016 + kit-health carve-out.
RC=0; { grep -q 'DEC-017' "$KIT_DIR/docs/specs/SPEC-109-persona-lens.md" && grep -q 'DEC-017' "$KIT_DIR/docs/specs/SPEC-016-critique-and-test-lanes.md"; } || RC=1
assert_eq "DEC-017 recorded in SPEC-109 + reciprocal pointer in SPEC-016 (SPEC-109)" 0 $RC
RC=0; grep -qiF 'operator-supplied' "$KIT_DIR/commands/kit-health.md" || RC=1
assert_eq "kit-health check-13 carries the operator-persona carve-out (SPEC-109)" 0 $RC

# ============================================================
# SPEC-112: UI done-modes , the Done-mode flag + the TWO-SIDED quiescence stop (the no-false-
# quiescence NC pinned as the full conjunction) + the fixture traces in the proof-of-done.
# ============================================================
UIDM="$KIT_DIR/commands/ui-design.md"
RC=0; grep -qiE 'Done-mode' "$UIDM" || RC=1
assert_eq "ui-design consumes a Done-mode flag (SPEC-112)" 0 $RC
RC=0; grep -qiE 'zero NEW findings >=HIGH AND no OPEN finding >=HIGH' "$UIDM" || RC=1
assert_eq "quiescence stop is TWO-SIDED: zero NEW >=HIGH AND no OPEN >=HIGH (no-false-quiescence NC)" 0 $RC
RC=0; grep -qiE 'does NOT quiesce|re-finds an|falsely-calm' "$UIDM" || RC=1
assert_eq "the re-found-CRITICAL-does-not-quiesce trap is stated (SPEC-112)" 0 $RC
RC=0; grep -qF '[[QL-VERDICT' "$UIDM" || RC=1
assert_eq "quiescence emits QL-VERDICT round markers (SPEC-112)" 0 $RC
RC=0; grep -qiE 'Deferred findings' "$UIDM" || RC=1
assert_eq "Deferred findings subsection defined (SPEC-112)" 0 $RC
RC=0; { grep -qiE 'Round cap: 3' "$UIDM" && grep -qiE 'cap of 2' "$UIDM"; } || RC=1
assert_eq "cap divergence pinned: quiescence 3, plain REVISE 2 (SPEC-112 DEC-018)" 0 $RC
RC=0; grep -qiE 'COVERAGE-DELTA|ACs-covered' "$UIDM" || RC=1
assert_eq "over-test coverage-delta row defined (SPEC-112)" 0 $RC
# fixture TRACES pinned in the proof-of-done (the goal's crux proof, not just the contract text):
DMPROOF="$KIT_DIR/docs/verification/done-modes.md"
RC=0; { grep -qiE 'converge' "$DMPROOF" && grep -qiE 'cap-out|round 3|round cap 3' "$DMPROOF" && grep -qiE 're-found|does NOT quiesce|falsely' "$DMPROOF" && grep -qiE 'plain REVISE|cap.*2' "$DMPROOF"; } || RC=1
assert_eq "done-modes proof carries the 3 quiescence fixtures + plain-REVISE regression (SPEC-112)" 0 $RC

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
