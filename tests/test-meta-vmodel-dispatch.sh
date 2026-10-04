#!/bin/bash
# test-meta-vmodel-dispatch.sh -- vmodel-dispatch structural integrity tests, split from tests/test-meta.sh.
# Run: bash tests/test-meta-vmodel-dispatch.sh   (standalone, or via the tests/test-meta.sh runner)
# Harness (counters, colors, assert_eq/assert_true): tests/lib/meta-stub.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/meta-stub.sh"

# ============================================================
echo ""
echo "=== V-model lens, convergence, and inventory parity (SPEC-031) ==="
# ============================================================

# (a) No "8 (workflow|lifecycle )?phases" string in operating surfaces.
# Scope: docs/, commands/, WORKFLOW.md, README.md, MANUAL.md, AGENTS.md --
# EXCLUDING docs/specs/, docs/decisions/, docs/research/, docs/retro/, docs/handoff/,
# docs/CHANGELOG.md (AMEND-001: archive dirs / the changelog are point-in-time and may
# reference old counts -- a retro or a changelog entry that documents the fix must be
# free to quote the forbidden string; only live surfaces are checked).
# git ls-files, never a filesystem walk (SPEC-029's dead-prefix scan already
# does this): a raw `grep -r` sweeps UNTRACKED gauntlet room copies under
# docs/verification/gauntlet/*/ , which each carry their own test-meta.sh and
# trip on the string this test names to describe itself (ID-640).
# docs/verification/ is also excluded below: a proof-of-done record is a
# point-in-time artifact that legitimately quotes the very string it fixed
# (like retro/handoff), so it is not a live operating surface.
PHASES_8_HITS=$(cd "$KIT_DIR" && git ls-files \
      'docs/*' 'commands/*' 'WORKFLOW.md' 'README.md' 'MANUAL.md' 'AGENTS.md' \
    | grep -vE '^(docs/specs/|docs/decisions/|docs/research/|docs/retro/|docs/handoff/|docs/verification/|docs/CHANGELOG\.md)' \
    | xargs grep -In -E "8 (workflow|lifecycle )?phases" 2>/dev/null | head -1)
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
if grep -q "^## The V-model lens" "$KIT_DIR/docs/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has '## The V-model lens' section (SPEC-031)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing '## The V-model lens' section"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q "^## Lead-owned convergence" "$KIT_DIR/docs/WORKFLOW.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} WORKFLOW.md has '## Lead-owned convergence' section (SPEC-031)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} WORKFLOW.md missing '## Lead-owned convergence' section"
  FAIL=$((FAIL + 1))
fi

# Extract phase names from the cycle table (column 1, skipping header and separator).
# Then check each (after stripping ", downstream" qualifier) appears in the lens section.
LENS_SECTION=$(sed -n '/^## The V-model lens/,/^## /p' "$KIT_DIR/docs/WORKFLOW.md")
CYCLE_PHASES=$(sed -n '/^## The cycle/,/^## The V-model lens/p' "$KIT_DIR/docs/WORKFLOW.md" \
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
  if { trap '' PIPE; echo "$LENS_SECTION" 2>/dev/null || :; } | grep -qF "$trimmed"; then
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
DOC_IMPACT_BLOCK=$(sed -n '/^#### Doc-impact map/,/^## Lead-owned convergence/p' "$KIT_DIR/docs/WORKFLOW.md")
HANDS_OFF_ENTRIES=$(sed -n '/^### Hands-off shared-surface list/,/^###/p' "$KIT_DIR/docs/WORKFLOW.md" \
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
  if { trap '' PIPE; echo "$DOC_IMPACT_BLOCK" 2>/dev/null || :; } | grep -qF "$base"; then
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

# No-counts policy (2026-08-10): the docs carry NO literal roster numbers (they churned on
# every addition and cost more to maintain than they informed; the operator retired them).
# Completeness is still pinned below by the ROW checks, live tree vs table rows, both sides
# computed, no hand-maintained number anywhere.
HOOK_COUNT=$(ls "$KIT_DIR/hooks/"*.sh 2>/dev/null | wc -l | tr -d ' ')

# SG-10 (harness-loop): the README inventory TABLES (not just the layout comment) stay
# pinned to live counts , the agents table sat at 11 rows against 25 files because only
# the layout number was pinned. Both the <summary> header number and the table row count
# are computed and compared; a new agent/command/skill without a README row fails here.
SKILL_COUNT=$(ls "$KIT_DIR/skills/"*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
# No-counts policy: header/layout numbers retired; a stray survivor fails here so one can
# never quietly come back and start drifting again.
assert_eq "README carries no literal roster counts (headers/layout)" "0" \
  "$(grep -cE '<b>(Agents|Commands|Skills|Hooks)</b> \([0-9]+|(agents|commands|hooks)/ *\([0-9]+' "$KIT_DIR/README.md" | tr -d ' ')"

# Table row counts (data rows only: exclude the header row and |--- separator).
AGT_DETAILS=$(sed -n '/<summary><b>Agents<\/b>/,/<\/details>/p' "$KIT_DIR/README.md")
README_AGT_ROWS=$(echo "$AGT_DETAILS" | sed -n '/^| Agent |/,/^$/p' | grep '^|' | grep -cv '^| Agent\|^|---' | tr -d ' ')
README_SKILL_ROWS=$(echo "$AGT_DETAILS" | sed -n '/^| Skill |/,/^$/p' | grep '^|' | grep -cv '^| Skill\|^|---' | tr -d ' ')
README_CMD_ROWS=$(sed -n '/<summary><b>Commands<\/b>/,/<\/details>/p' "$KIT_DIR/README.md" \
  | grep '^|' | grep -cv '^| Command\|^|---' | tr -d ' ')
README_HOOK_ROWS=$(sed -n '/<summary><b>Hooks<\/b>/,/<\/details>/p' "$KIT_DIR/README.md" \
  | grep '^|' | grep -cv '^| Hook\|^|---' | tr -d ' ')
assert_eq "README agents table rows == live agents ($README_AGT_ROWS == $AGT_COUNT)" "$AGT_COUNT" "$README_AGT_ROWS"
assert_eq "README skills table rows == live skills ($README_SKILL_ROWS == $SKILL_COUNT)" "$SKILL_COUNT" "$README_SKILL_ROWS"
assert_eq "README commands table rows == live commands ($README_CMD_ROWS == $CMD_COUNT)" "$CMD_COUNT" "$README_CMD_ROWS"
assert_eq "README hooks table rows == live hooks ($README_HOOK_ROWS == $HOOK_COUNT)" "$HOOK_COUNT" "$README_HOOK_ROWS"

# No-counts policy: the architecture.md headline tally is retired the same way.
assert_eq "architecture.md carries no headline roster tally" "0" \
  "$(grep -cE '^Total: [0-9]+ commands' "$KIT_DIR/docs/architecture.md" | tr -d ' ')"

# The README five-stage table covers every module the registry assigns a stage (ADR-0034
# decision 3 rendered without omissions; the two tables share one truth). "leg" renamed to
# "stage" by the 2026-07-18 amendment (ID-292).
FIVE_LEG_BLOCK=$(sed -n '/^## The five stages/,/^## /p' "$KIT_DIR/README.md")
REGISTRY_MODULES=$(sed -n '/^## Module stages/,/^## /p' "$KIT_DIR/lib/config/module-registry.md" \
  | grep '^| ' | grep -v '^| Module\|^|---' | awk -F'|' '{gsub(/ /,"",$2); print $2}')
TOTAL=$((TOTAL + 1))
MISSING_LEG_MODULES=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  { trap '' PIPE; echo "$FIVE_LEG_BLOCK" 2>/dev/null || :; } | grep -q "\`$m\`" || MISSING_LEG_MODULES="$MISSING_LEG_MODULES $m"
done <<< "$REGISTRY_MODULES"
if [ -z "$MISSING_LEG_MODULES" ]; then
  echo -e "  ${GREEN}PASS${NC} README five-stage table covers every module-registry stage row"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} README five-stage table missing module(s):$MISSING_LEG_MODULES"
  FAIL=$((FAIL + 1))
fi

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
   && grep -q "parallel-execution-boundary decision" "$KIT_DIR/commands/kit-health.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} kit-health records the cross-goal fan-out carve-out (parallel-execution-boundary decision)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} kit-health must record the cross-goal fan-out carve-out (parallel-execution-boundary decision)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Dispatch moat: ## Touches + lib/gate/dispatch-gate.sh (SPEC-032) ==="
# ============================================================

# (a) The gate/guard helper exists and is executable (pure-bash moat).
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/gate/dispatch-gate.sh" ] && [ -x "$KIT_DIR/lib/gate/dispatch-gate.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/gate/dispatch-gate.sh exists and is executable (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/gate/dispatch-gate.sh missing or not executable"
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
if grep -q '`lib/\*`' "$KIT_DIR/docs/WORKFLOW.md" 2>/dev/null; then
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
  echo -e "  ${RED}FAIL${NC} dispatch.md must use lib/gate/dispatch-gate.sh, converge via /kit:ship, and refuse auto-merge"
  FAIL=$((FAIL + 1))
fi

# (e2) dispatch.md Step 6 releases each settled task's attempt record, or kit-attempts/ grows forever.
TOTAL=$((TOTAL + 1))
if grep -q 'attempt-state.sh release' "$KIT_DIR/commands/dispatch.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} dispatch.md convergence releases the attempt record"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} dispatch.md Step 6 must call lib/goal/attempt-state.sh release for a settled task"
  FAIL=$((FAIL + 1))
fi

# (f) dispatch.md is registered in the human-facing inventories (README + MANUAL).
TOTAL=$((TOTAL + 1))
if grep -q 'kit:dispatch' "$KIT_DIR/README.md" 2>/dev/null \
   && grep -q 'kit:dispatch' "$KIT_DIR/docs/MANUAL.md" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} /kit:dispatch registered in README + MANUAL command inventories (SPEC-032)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} /kit:dispatch must be in the README command table + MANUAL command list"
  FAIL=$((FAIL + 1))
fi

# (g) The lane classifier exists, is executable, and is wired into the intake/dispatch path.
TOTAL=$((TOTAL + 1))
if [ -f "$KIT_DIR/lib/classify/lane-classify.sh" ] && [ -x "$KIT_DIR/lib/classify/lane-classify.sh" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/classify/lane-classify.sh exists and is executable (lane auto-classification)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lib/classify/lane-classify.sh missing or not executable"
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
if grep -qE '^[[:space:]]*check\)' "$KIT_DIR/lib/classify/lane-classify.sh" 2>/dev/null; then
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
  if (v ~ /preassigned|dynamic|per lane/) ok++ } END { print (n==12 && ok==12) ? "yes" : "no" }' "$KIT_DIR/docs/verification/task-types.md")
if [ "$AGENT_OK" = "yes" ]; then
  echo -e "  ${GREEN}PASS${NC} task-types registry: all 12 rows carry an agent entry (SPEC-054/057)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} task-types registry agent column incomplete (SPEC-054/057)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
LOOP_ROWS=$(awk '/^## Type loops/,/^## [^T]/' "$KIT_DIR/docs/WORKFLOW.md" | grep -cE '^\| (incident|learning|planning|operate|eval|research|review|reconcile|doc|migration|data-tool|spec-feature) \|')
if [ "$(grep -c '^## Type loops' "$KIT_DIR/docs/WORKFLOW.md")" -eq 1 ] && [ "$LOOP_ROWS" -eq 12 ]; then
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
if [ -x "$KIT_DIR/lib/board/backlog.sh" ] && grep -qF -- '--next' "$KIT_DIR/commands/assign.md" \
   && grep -qF '`claimed`' "$KIT_DIR/_meta/BACKLOG.md"; then
  echo -e "  ${GREEN}PASS${NC} backlog kanban wired: lib/board/backlog.sh + assign --next + claimed state (SPEC-055)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} backlog kanban incomplete: need lib/board/backlog.sh executable + assign --next + claimed vocab (SPEC-055)"
  FAIL=$((FAIL + 1))
fi

# SPEC-146: the cockpit board command. board.sh + parse-board.sh exist and are executable,
# board.sh actually delegates base render to backlog.sh (never reimplements it), and the
# doc-impact map (README + architecture.md) mentions both new lib files. A drop on any leg
# means the render-migration contract this depends on is silently unwired.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/board/board.sh" ] && [ -x "$KIT_DIR/lib/board/parse-board.sh" ] \
   && grep -qF 'backlog.sh' "$KIT_DIR/lib/board/board.sh" \
   && grep -qF 'lib/board/board.sh' "$KIT_DIR/README.md" \
   && grep -qF 'lib/board/parse-board.sh' "$KIT_DIR/README.md" \
   && grep -qF 'board.sh' "$KIT_DIR/docs/architecture.md"; then
  echo -e "  ${GREEN}PASS${NC} cockpit board wired: lib/board/board.sh + lib/board/parse-board.sh executable, delegates to backlog.sh, doc-impact map updated (SPEC-146)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} cockpit board incomplete: need lib/board/board.sh + lib/board/parse-board.sh executable, backlog.sh delegation, README + architecture.md mentions (SPEC-146)"
  FAIL=$((FAIL + 1))
fi

# SPEC-147: the board-bridge mirror. board-mirror.sh exists and is executable, board.sh wires
# both mirror and status dispatch cases to it, and the doc-impact map (README + architecture.md)
# mentions the new lib file. A drop on any leg means the bridge is silently unwired.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/board/board-mirror.sh" ] \
   && grep -qF 'mirror) shift; cmd_mirror "$@" ;;' "$KIT_DIR/lib/board/board.sh" \
   && grep -qF 'status) shift; cmd_status "$@" ;;' "$KIT_DIR/lib/board/board.sh" \
   && grep -qF 'lib/board/board-mirror.sh' "$KIT_DIR/README.md" \
   && grep -qF 'board-mirror.sh' "$KIT_DIR/docs/architecture.md"; then
  echo -e "  ${GREEN}PASS${NC} board-bridge mirror wired: lib/board/board-mirror.sh executable, board.sh dispatches mirror+status, doc-impact map updated (SPEC-147)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} board-bridge mirror incomplete: need lib/board/board-mirror.sh executable, board.sh mirror/status dispatch, README + architecture.md mentions (SPEC-147)"
  FAIL=$((FAIL + 1))
fi

# SPEC-149: the board-bridge writeback (the reverse leg). board-writeback.sh exists and is
# executable, board.sh wires the writeback dispatch case to it, and the doc-impact map
# (README + architecture.md) mentions the new lib file. A drop on any leg means the writeback
# leg is silently unwired.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/board/board-writeback.sh" ] \
   && grep -qF 'writeback) shift; cmd_writeback "$@" ;;' "$KIT_DIR/lib/board/board.sh" \
   && grep -qF 'lib/board/board-writeback.sh' "$KIT_DIR/README.md" \
   && grep -qF 'board-writeback.sh' "$KIT_DIR/docs/architecture.md"; then
  echo -e "  ${GREEN}PASS${NC} board-bridge writeback wired: lib/board/board-writeback.sh executable, board.sh dispatches writeback, doc-impact map updated (SPEC-149)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} board-bridge writeback incomplete: need lib/board/board-writeback.sh executable, board.sh writeback dispatch, README + architecture.md mentions (SPEC-149)"
  FAIL=$((FAIL + 1))
fi

# SPEC-056: per-type test dialects. Three legs: the 6-row dialect table, the type-aware
# test-plan step, the default flip in the cycle table.
TOTAL=$((TOTAL + 1))
DIALECT_ROWS=$(awk '/^## 5b/,/^## 6/' "$KIT_DIR/docs/verification/test-design-standard.md" | grep -cE '^\| (incident|learning|planning|operate|eval|research|review|reconcile|doc|migration|data-tool|spec-feature) \|')
if [ "$DIALECT_ROWS" -eq 12 ] && grep -qF 'task-type-classify' "$KIT_DIR/commands/test-plan.md" \
   && grep -qF 'Test plan (default' "$KIT_DIR/docs/WORKFLOW.md"; then
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
  grep -qE "^\| ${ty} \|" <(awk '/^## Type loops/,/^## [^T]/' "$KIT_DIR/docs/WORKFLOW.md") || PARITY_OK="no-loop:$ty"
  grep -qE "^\| ${ty} \|" <(awk '/^## 5b/,/^## 6/' "$KIT_DIR/docs/verification/test-design-standard.md") || PARITY_OK="no-dialect:$ty"
done <<< "$REG_N"
if [ "$PARITY_OK" = "yes" ] && [ "$(echo "$REG_N" | grep -c .)" -eq 12 ]; then
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
if grep -qE 'backlog\.sh"? next' "$KIT_DIR/AGENTS.md" && grep -qE 'task-type-classify\.sh"? classify' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'Done =' "$KIT_DIR/AGENTS.md" && grep -qF 'Where work comes from' "$KIT_DIR/docs/WORKFLOW.md"; then
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
   && grep -qF 'kit:grill' "$KIT_DIR/commands/assign.md" && grep -qF 'grill' "$KIT_DIR/docs/WORKFLOW.md"; then
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
if grep -qF 'start)    start "$@" ;;' "$KIT_DIR/lib/gate/gate-ledger.sh" \
   && grep -qF 'usage: $uprefix <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]' "$KIT_DIR/lib/gate/gate-ledger.sh"; then
  echo -e "  ${GREEN}PASS${NC} gate-ledger has the START routing verb (SPEC-061)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} gate-ledger missing the START verb (SPEC-061)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/telemetry/lane-telemetry.sh" ] && grep -qF 'report)' "$KIT_DIR/lib/telemetry/lane-telemetry.sh" \
   && grep -qF 'misfires)' "$KIT_DIR/lib/telemetry/lane-telemetry.sh"; then
  echo -e "  ${GREEN}PASS${NC} lane-telemetry.sh exists with report+misfires (SPEC-061)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} lane-telemetry.sh missing or incomplete (SPEC-061)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'Lane telemetry sweep' "$KIT_DIR/commands/retro.md" \
   && grep -qF 'Disposition contract' "$KIT_DIR/commands/retro.md" \
   && grep -qF 'How lanes are judged' "$KIT_DIR/docs/WORKFLOW.md" \
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
if grep -qF 'What the operator sees, and when' "$KIT_DIR/docs/WORKFLOW.md" \
   && grep -qF 'escaped-from=' "$KIT_DIR/commands/debug.md" \
   && grep -qF 'gate-ledger.sh record <rid> test-plan ran' "$KIT_DIR/commands/test-plan.md" \
   && grep -qF 'gate-ledger.sh record <rid> test-plan ran' "$KIT_DIR/commands/test-plan-review-team.md" \
   && grep -qF 'classified-type' "$KIT_DIR/lib/gate/gate-ledger.sh"; then
  echo -e "  ${GREEN}PASS${NC} telemetry closure wired: scenarios + escaped-from + test-plan records + ctype (SPEC-062)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} telemetry closure wiring incomplete (SPEC-062)"
  FAIL=$((FAIL + 1))
fi

# SPEC-063: run legibility. plan/progress/trace exist; AGENTS carries the show-the-road
# rule + grill disposition recording; assign prints the plan; grill records itself.
TOTAL=$((TOTAL + 1))
if grep -qF 'plan)     plan "$@" ;;' "$KIT_DIR/lib/gate/gate-ledger.sh" \
   && grep -qF 'progress) progress "$@" ;;' "$KIT_DIR/lib/gate/gate-ledger.sh" \
   && grep -qF 'trace)    trace "$@" ;;' "$KIT_DIR/lib/telemetry/lane-telemetry.sh" \
   && grep -qF 'Show the road, then your position on it' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'record <rid> grill' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'gate-ledger.sh plan' "$KIT_DIR/commands/assign.md" \
   && grep -qF 'record <rid> grill ran' "$KIT_DIR/commands/grill.md"; then
  echo -e "  ${GREEN}PASS${NC} run legibility wired: plan/progress/trace + AGENTS/assign/grill (SPEC-063)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} run legibility wiring incomplete (SPEC-063)"
  FAIL=$((FAIL + 1))
fi

# SPEC-065: stack-merge exists with both verbs + dry-run; ship.md points at it.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/lib/goal/stack-merge.sh" ] && grep -qF 'next_link' "$KIT_DIR/lib/goal/stack-merge.sh" \
   && grep -qF 'dry-run' "$KIT_DIR/lib/goal/stack-merge.sh" \
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

# SPEC-067: the golden run exists, is executable, and CI runs it.
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/tests/test-e2e.sh" ] && grep -qF 'tests/run-all.sh' "$KIT_DIR/.github/workflows/test.yml"; then
  echo -e "  ${GREEN}PASS${NC} golden-run e2e exists + CI runs it (SPEC-067)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} golden-run e2e missing or not in CI (SPEC-067)"
  FAIL=$((FAIL + 1))
fi

# SPEC-068: precedent lookup exists and intake reads it (assign + grill).
TOTAL=$((TOTAL + 1))
if [ -x "$KIT_DIR/bin/precedent" ] \
   && grep -qF 'precedent find' "$KIT_DIR/commands/assign.md" \
   && grep -qF 'precedent find' "$KIT_DIR/commands/grill.md"; then
  echo -e "  ${GREEN}PASS${NC} precedent lookup wired into intake (SPEC-068)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} precedent lookup missing or unwired (SPEC-068)"
  FAIL=$((FAIL + 1))
fi

# SPEC-069: retro follow-ups wired (escalation rule, advisory, grill line, color gate).
TOTAL=$((TOTAL + 1))
if grep -qF 'Review escalation' "$KIT_DIR/docs/WORKFLOW.md" \
   && grep -qF 'review-team' "$KIT_DIR/AGENTS.md" \
   && grep -qF 'codebase-memory' "$KIT_DIR/commands/grill.md" \
   && grep -qF 'appears nowhere in _meta/BACKLOG.md' "$KIT_DIR/hooks/ship-gate.sh" \
   && grep -qF 'NO_COLOR' "$KIT_DIR/lib/gate/gate-ledger.sh" \
   && grep -qF '_boardless' "$KIT_DIR/lib/telemetry/lane-telemetry.sh"; then
  echo -e "  ${GREEN}PASS${NC} retro follow-ups wired: escalation + advisory + grill + colors + detectors (SPEC-069)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} retro follow-ups incomplete (SPEC-069)"
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
