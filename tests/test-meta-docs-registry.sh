#!/bin/bash
# test-meta-docs-registry.sh -- docs-registry structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-docs-registry.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

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
if [ -f "$KIT_DIR/tests/test-hooks.sh" ] && grep -q "tests/run-all.sh" "$WF"; then
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

# Bulk lives at docs/WORKFLOW.md (root WORKFLOW.md is a thin stub, SPEC-185).
WF_ROOT="$KIT_DIR/docs/WORKFLOW.md"
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
if grep -qF 'Mid-flight amend' "$KIT_DIR/docs/WORKFLOW.md" 2>/dev/null; then
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
echo "=== SPEC-073 + ID-060: doc-loop second entry + eval design parked ==="
# ============================================================
RC=0; grep -qF 'standalone revision, content brief' "$KIT_DIR/docs/WORKFLOW.md" || RC=1
assert_eq "doc loop carries the standalone-revision entry path (ID-060)" 0 $RC
RC=0; grep -qF 'doc-verifier confirming docs match code' "$KIT_DIR/docs/WORKFLOW.md" || RC=1
assert_eq "doc loop both entries share the doc-verifier exit" 0 $RC
RC=0; grep -qF 'EXECUTION PARKED until 3-5 days' "$KIT_DIR/docs/specs/SPEC-073-telemetry-eval-design.md" || RC=1
assert_eq "telemetry eval design exists and is parked-until-data (ID-067)" 0 $RC
RC=0; grep -qF 'the design pins the WINDOW, not the flag' "$KIT_DIR/docs/specs/SPEC-073-telemetry-eval-design.md" || RC=1
assert_eq "eval design pins its data window honestly" 0 $RC


# ============================================================
echo ""
echo "=== SPEC-085: operator doc sync (ID-070) ==="
# ============================================================
RM85="$KIT_DIR/README.md"
# parity: ROW counts only (summary-header numbers retired by the no-counts policy 2026-08-10)
HF=$(ls "$KIT_DIR"/hooks/*.sh | wc -l | tr -d ' ')
HROWS=$(awk '/<summary><b>Hooks<\/b>/,/<\/details>/' "$RM85" | grep -cE '^\| [a-z]' || true)
assert_eq "README hooks rows == hook files ($HF)" "$HF" "$HROWS"
CF=$(ls "$KIT_DIR"/commands/*.md | wc -l | tr -d ' ')
CROWS=$(awk '/<summary><b>Commands<\/b>/,/<\/details>/' "$RM85" | grep -cE '^\| /kit:' || true)
assert_eq "README commands rows == command files ($CF)" "$CF" "$CROWS"
# content: the hard hook is in the public table; the two missing commands exist
RC=0; awk '/<summary><b>Hooks<\/b>/,/<\/details>/' "$RM85" | grep -q '^| ship-gate' || RC=1
assert_eq "README hooks table carries ship-gate" 0 $RC
RC=0; awk '/<summary><b>Commands<\/b>/,/<\/details>/' "$RM85" | grep -q 'kit:adopt' && awk '/<summary><b>Commands<\/b>/,/<\/details>/' "$RM85" | grep -q 'kit:test-plan-review-team' || RC=1
assert_eq "README commands table carries adopt + test-plan-review-team" 0 $RC
RC=0; awk '/<summary><b>Hooks<\/b>/,/<\/details>/' "$RM85" | grep '^| context-readiness' | grep -q 'board' || RC=1
assert_eq "README context-readiness row is board-aware (SPEC-083)" 0 $RC

# ============================================================
echo ""
echo "=== Feature-registry freshness pin (SPEC-219) ==="
# ============================================================
# docs/FEATURES.md is a generated projection (lib/registry/feature-registry.sh).
# Same class as the derived-count pins above: regenerate and diff against the
# committed copy; ANY drift (a feature added/removed/renamed, a description or
# wiring change) fails here until the registry is regenerated.
#
# The regenerate-and-diff is the registry's own `check` verb, not a hand-rolled
# copy of it: hooks/ship-gate.sh refuses a push on the same verb, and two
# definitions of "fresh" would eventually disagree.
bash "$KIT_DIR/lib/registry/feature-registry.sh" check "$KIT_DIR/docs/FEATURES.md" >/dev/null 2>&1
assert_true "docs/FEATURES.md is fresh (check verb, SPEC-219)" $?
REG_TMP=$(mktemp)
bash "$KIT_DIR/lib/registry/feature-registry.sh" generate "$REG_TMP" 2>/dev/null
# AC-1 determinism pin (review finding): a second run must be byte-identical, so a
# future edit that reintroduces nondeterminism (locale, glob order, a timestamp)
# fails HERE even when the committed file was regenerated in the same PR.
REG_TMP2=$(mktemp)
bash "$KIT_DIR/lib/registry/feature-registry.sh" generate "$REG_TMP2" 2>/dev/null
cmp -s "$REG_TMP" "$REG_TMP2"
assert_true "feature-registry generator is deterministic (double run byte-identical, SPEC-219)" $?
# Skill-dispatcher derivation pin: an agent dispatched only by skills must not
# show `-`; audit-scanner is dispatched by the doc-drift + topology-drift + ci-drift skills
# (cap_list caps the shown names at 3 alphabetically then "+N" for the rest, so a fourth
# dispatcher pushes the last name into the overflow count rather than dropping it silently).
ASROW=$(grep -E '^\| `audit-scanner` ' "$KIT_DIR/docs/FEATURES.md")
RC=0; { { trap '' PIPE; echo "$ASROW" 2>/dev/null || :; } | grep -q 'doc-drift (skill)' && { trap '' PIPE; echo "$ASROW" 2>/dev/null || :; } | grep -q 'ci-drift (skill)' && { trap '' PIPE; echo "$ASROW" 2>/dev/null || :; } | grep -qE '\+[0-9]+ *\|'; } || RC=1
assert_eq "audit-scanner dispatched-by names doc-drift + ci-drift, overflow count covers the rest" 0 $RC
rm -f "$REG_TMP" "$REG_TMP2"

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

assert_true "lib/gate/proof-gate.sh exists and is executable" \
  "$([ -x "$KIT_DIR/lib/gate/proof-gate.sh" ] && echo 0 || echo 1)"

assert_true "proof-gate names the three proof classes (stateful, behavioral, inert)" \
  "$(out=$(bash "$KIT_DIR/lib/gate/proof-gate.sh" classes 2>/dev/null); { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q stateful && { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q behavioral && { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q inert && echo 0 || echo 1)"

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

assert_true "lib/gate/proof-ledger.sh exists and is executable" \
  "$([ -x "$KIT_DIR/lib/gate/proof-ledger.sh" ] && echo 0 || echo 1)"

assert_true "ship-gate wires the diff-keyed proof-of-done gate" \
  "$(grep -q 'proof-ledger.sh' "$KIT_DIR/hooks/ship-gate.sh" && echo 0 || echo 1)"

assert_true "proof gate is opt-in (engages only where docs/verification/README.md exists)" \
  "$(grep -q 'docs/verification/README.md' "$KIT_DIR/hooks/ship-gate.sh" && echo 0 || echo 1)"

assert_true "proof-ledger provides a logged override (no silent bypass)" \
  "$(grep -q 'override' "$KIT_DIR/lib/gate/proof-ledger.sh" && grep -qi 'OVERRIDE' "$KIT_DIR/lib/gate/proof-ledger.sh" && echo 0 || echo 1)"

assert_true "ADR records the proof-of-done ship gate" \
  "$([ -f "$KIT_DIR/docs/decisions/0025-proof-of-done-ship-gate.md" ] && echo 0 || echo 1)"

assert_true "convention documents the enforcement gate + override" \
  "$(grep -qi 'ship/merge gate\|enforcement' "$KIT_DIR/docs/verification/README.md" && grep -q 'proof-ledger' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"

assert_true "PHILOSOPHY records the deferred enforcement hook is now built" \
  "$(grep -q 'proof-ledger' "$KIT_DIR/docs/PHILOSOPHY.md" && echo 0 || echo 1)"

# ---- single-source numbers: borrowed from the experiment sibling (no hand-typed drift) ----

assert_true "lib/gate/verify-counts.sh exists and is executable" \
  "$([ -x "$KIT_DIR/lib/gate/verify-counts.sh" ] && echo 0 || echo 1)"

# ID-291: the gate dispatcher routes BOTH `verify-counts` and its legacy `verif-counts`
# alias to verify-counts.sh. The real target regenerates COUNTS.md by running every
# suite, so stub it and prove routing cheaply -- a future edit that drops the alias arm
# (or misroutes the verb) is then caught in CI, not by eyeballing the case statement.
_gate_route_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dk-gate-route.XXXXXX")"
cp "$KIT_DIR/lib/gate/gate.sh" "$_gate_route_tmp/gate.sh"
printf '#!/usr/bin/env bash\necho "ROUTED $*"\n' > "$_gate_route_tmp/verify-counts.sh"
chmod +x "$_gate_route_tmp/verify-counts.sh"
assert_true "gate dispatch routes 'verify-counts' to verify-counts.sh" \
  "$(bash "$_gate_route_tmp/gate.sh" verify-counts probe 2>/dev/null | grep -q '^ROUTED probe' && echo 0 || echo 1)"
assert_true "gate dispatch routes legacy 'verif-counts' alias to verify-counts.sh" \
  "$(bash "$_gate_route_tmp/gate.sh" verif-counts probe 2>/dev/null | grep -q '^ROUTED probe' && echo 0 || echo 1)"
rm -rf "$_gate_route_tmp"

assert_true "COUNTS.md carries the generated single-source block" \
  "$(grep -q 'BEGIN GEN:counts' "$KIT_DIR/docs/verification/COUNTS.md" 2>/dev/null && echo 0 || echo 1)"

assert_true "convention names the experiment sibling + single-source borrow" \
  "$(grep -qi 'sibling' "$KIT_DIR/docs/verification/README.md" && grep -qi 'single-source\|codebase-tool-benchmark\|falsifiab' "$KIT_DIR/docs/verification/README.md" && echo 0 || echo 1)"
# ============================================================
echo ""
echo "=== ID-651: wrap Step 7a reports a structural skip, not a clean one ==="
# ============================================================
# Landing from master/main makes gate-ledger.sh rid refuse outright, so the DEBT marker was
# never reachable this run. That is a different fact than "nothing to record", and Step 7a
# must say so instead of printing the same wording as a genuinely clean skip.
RC=0; grep -q 'rid_rc' "$KIT_DIR/commands/wrap.md" || RC=1
assert_eq "wrap.md Step 7a captures the rid exit code, not just stdout" 0 $RC
RC=0; grep -q 'skipped (structural)' "$KIT_DIR/commands/wrap.md" || RC=1
assert_eq "wrap.md Step 7a names the structural-skip wording" 0 $RC
RC=0; grep -q 'Do not synthesize a rid' "$KIT_DIR/commands/wrap.md" || RC=1
assert_eq "wrap.md Step 7a rules out a session-derived rid (ledger key stays branch-only)" 0 $RC


# ============================================================
echo ""
echo "=== Task-type contracts (SPEC-044) ==="
# ============================================================
# Second axis of the verification gate: task TYPE -> proof artifact + owning skill,
# composed with the proof CLASS. Pins the classifier, the registry, and the
# proof-gate `contract` compose. These go RED if SPEC-044 is reverted (negative control).

TTC="$KIT_DIR/lib/classify/task-type-classify.sh"
TTREG="$KIT_DIR/docs/verification/task-types.md"

assert_true "lib/classify/task-type-classify.sh exists and is executable" \
  "$([ -x "$TTC" ] && echo 0 || echo 1)"

assert_eq "classify -> eval" "eval" "$(bash "$TTC" classify 'benchmark X vs Y for retrieval' 2>/dev/null)"
assert_eq "classify -> research" "research" "$(bash "$TTC" classify 'research the tooling landscape' 2>/dev/null)"
assert_eq "classify -> doc" "doc" "$(bash "$TTC" classify 'write the README for the tool' 2>/dev/null)"
assert_eq "classify -> migration" "migration" "$(bash "$TTC" classify 'migrate the database schema' 2>/dev/null)"
assert_eq "classify -> data-tool" "data-tool" "$(bash "$TTC" classify 'build a CLI to pull data from the API' 2>/dev/null)"
# Negative control: an unmatched description falls through to the default, not a wrong type.
assert_eq "classify default (neg control) -> spec-feature" "spec-feature" "$(bash "$TTC" classify 'add a sort button to the trade log' 2>/dev/null)"

assert_eq "task-type-classify types lists 12" "12" "$(bash "$TTC" types 2>/dev/null | grep -c .)"

assert_true "task-types.md registry exists" "$([ -f "$TTREG" ] && echo 0 || echo 1)"
for T in eval research doc migration data-tool spec-feature; do
  assert_true "registry has a row for '$T'" \
    "$(grep -qE "^\| *$T *\|" "$TTREG" && echo 0 || echo 1)"
done

CONTRACT_OUT="$(bash "$KIT_DIR/lib/gate/proof-gate.sh" contract 'build a CLI to pull data from the API' 2>/dev/null)"
assert_true "proof-gate contract names the data-tool type" \
  "$({ trap '' PIPE; printf '%s' "$CONTRACT_OUT" 2>/dev/null || :; } | grep -q 'type=data-tool' && echo 0 || echo 1)"
assert_true "proof-gate contract names the recorded-run artifact + owning skill" \
  "$({ trap '' PIPE; printf '%s' "$CONTRACT_OUT" 2>/dev/null || :; } | grep -qi 'recorded live run' && { trap '' PIPE; printf '%s' "$CONTRACT_OUT" 2>/dev/null || :; } | grep -qi 'ops-tool-shape' && echo 0 || echo 1)"
assert_true "proof-gate contract upgrades a migration to stateful (class wins on rigor)" \
  "$(bash "$KIT_DIR/lib/gate/proof-gate.sh" contract 'migrate the database schema' 2>/dev/null | grep -q 'class=stateful' && echo 0 || echo 1)"
assert_true "proof-gate contract points at the skeleton subcommand" \
  "$(bash "$KIT_DIR/lib/gate/proof-gate.sh" contract 'add a flag to the CLI' 2>/dev/null | grep -q 'proof-gate.sh skeleton' && echo 0 || echo 1)"

SKEL_BEHAVIORAL="$(bash "$KIT_DIR/lib/gate/proof-gate.sh" skeleton 'add-cli-flag' 'add a flag to the CLI' 2>/dev/null)"
assert_true "proof-gate skeleton names the slug in the title" \
  "$({ trap '' PIPE; printf '%s' "$SKEL_BEHAVIORAL" 2>/dev/null || :; } | grep -q '# Verification -- add-cli-flag' && echo 0 || echo 1)"
assert_true "proof-gate skeleton carries Green run + Negative control" \
  "$({ trap '' PIPE; printf '%s' "$SKEL_BEHAVIORAL" 2>/dev/null || :; } | grep -q '## Green run' && { trap '' PIPE; printf '%s' "$SKEL_BEHAVIORAL" 2>/dev/null || :; } | grep -q '## Negative control' && echo 0 || echo 1)"
assert_true "proof-gate skeleton omits Rollback for a behavioral task" \
  "$({ trap '' PIPE; printf '%s' "$SKEL_BEHAVIORAL" 2>/dev/null || :; } | grep -q '## Rollback' && echo 1 || echo 0)"

SKEL_STATEFUL="$(bash "$KIT_DIR/lib/gate/proof-gate.sh" skeleton 'deploy-worker' 'deploy to production' 2>/dev/null)"
assert_true "proof-gate skeleton adds Rollback for a stateful task" \
  "$({ trap '' PIPE; printf '%s' "$SKEL_STATEFUL" 2>/dev/null || :; } | grep -q '## Rollback' && echo 0 || echo 1)"

SKEL_NO_DESC="$(bash "$KIT_DIR/lib/gate/proof-gate.sh" skeleton 'no-desc-given' 2>/dev/null)"
assert_true "proof-gate skeleton with no task arg says so in a comment line" \
  "$({ trap '' PIPE; printf '%s' "$SKEL_NO_DESC" 2>/dev/null || :; } | grep -q 'no task description given' && echo 0 || echo 1)"
assert_true "proof-gate skeleton with no task arg defaults to behavioral (no Rollback)" \
  "$({ trap '' PIPE; printf '%s' "$SKEL_NO_DESC" 2>/dev/null || :; } | grep -q '## Rollback' && echo 1 || echo 0)"

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
