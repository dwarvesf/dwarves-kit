#!/bin/bash
# test-kit-foldin-hooks.sh -- fixture tests for the 4 kit-foldin hooks (kit-foldin
# sub-goal 02): backlog-stage, citation-guard, context-hints, harvest. Each is a
# function-named port of an ops-toolkit cc-* tool (design note
# research/2026-07-05-cc-elevation-kit-foldin-design.md); this pins the ported
# behavior + fail-open/fail-closed posture + the two-manifest registration.
#
# Run: bash tests/test-kit-foldin-hooks.sh
# Exit 0 = all tests pass. Exit 1 = failures found.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TD="$(mktemp -d "${TMPDIR:-/tmp}/kit-foldin-hooks-test.XXXXXX")"
trap 'rm -rf "${TD:?}"' EXIT

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_exit() {
  local NAME="$1" EXPECTED="$2" ACTUAL="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$ACTUAL" -eq "$EXPECTED" ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME (exit $ACTUAL)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME (expected exit $EXPECTED, got $ACTUAL)"
    FAIL=$((FAIL + 1))
  fi
}

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

assert_contains() {
  local NAME="$1" NEEDLE="$2" HAY="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$HAY" | grep -qF "$NEEDLE"; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME (missing '$NEEDLE')"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
echo "=== context-hints.sh (UserPromptSubmit) ==="
# ============================================================
MAP="$TD/skillmap.json"
printf '{"ocr": "local-ocr-skill"}\n' > "$MAP"
STATE="$TD/ch-state"

OUT=$(CONTEXT_HINTS_SKILLMAP="$MAP" CONTEXT_HINTS_STATE="$STATE" CONTEXT_HINTS_NOW=1000 \
  bash -c "echo '{\"prompt\":\"can you OCR this file\",\"session_id\":\"sess1\"}' | bash '$KIT_DIR/hooks/context-hints.sh'")
RC=$?
assert_exit "row 1: skill hint fires on keyword match" 0 $RC
assert_contains "row 1: hint names the mapped skill" "local-ocr-skill (keyword: ocr)" "$OUT"

# NC: empty stdin never crashes / never blocks.
RC=0; echo '' | bash "$KIT_DIR/hooks/context-hints.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: empty stdin exits 0" 0 $RC

# NC: malformed JSON never crashes / never blocks.
RC=0; echo 'not json' | bash "$KIT_DIR/hooks/context-hints.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: malformed JSON exits 0" 0 $RC

# ============================================================
echo ""
echo "=== citation-guard.sh (Stop) ==="
# ============================================================
mkdir -p "$TD/cg-repo"
printf 'line1\nline2\nline3\n' > "$TD/cg-repo/foo.txt"
CG_TRANS="$TD/cg-transcript.jsonl"
cat > "$CG_TRANS" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"See foo.txt:2 for the good ref and foo.txt:99 for the bad ref."}]}}
EOF

RC=0
echo "{\"transcript_path\":\"$CG_TRANS\",\"cwd\":\"$TD/cg-repo\"}" \
  | bash "$KIT_DIR/hooks/citation-guard.sh" >/dev/null 2>&1 || RC=$?
assert_exit "row 2: log-only default never blocks on a bad ref" 0 $RC

CG_LOG="$TD/cg.log"
STRICT_OUT=$(CITATION_GUARD_STRICT=1 CITATION_GUARD_LOG="$CG_LOG" bash -c \
  "echo '{\"transcript_path\":\"$CG_TRANS\",\"cwd\":\"$TD/cg-repo\"}' | bash '$KIT_DIR/hooks/citation-guard.sh'" 2>&1)
RC=$?
assert_exit "row 2b: strict mode blocks (exit 2) on the bad ref" 2 $RC
assert_contains "row 2b: strict mode names the bad ref" "foo.txt:99" "$STRICT_OUT"
assert_contains "row 2b: bad ref logged" "foo.txt:99" "$(cat "$CG_LOG" 2>/dev/null)"

# NC: empty stdin never crashes.
RC=0; echo '' | bash "$KIT_DIR/hooks/citation-guard.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: empty stdin exits 0" 0 $RC

# NC: malformed JSON never crashes.
RC=0; echo 'not json' | bash "$KIT_DIR/hooks/citation-guard.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: malformed JSON exits 0" 0 $RC

# ============================================================
echo ""
echo "=== backlog-stage.sh (SessionEnd) ==="
# ============================================================
mkdir -p "$TD/bs-repo/_meta"
git -C "$TD/bs-repo" init -q
BS_TRANS="$TD/bs-transcript.jsonl"
cat > "$BS_TRANS" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"we should add a backlog item to fix the flaky deploy script later"}]}}
EOF
cat > "$TD/bs-extractor.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"title":"fix flaky deploy script","intent":"stop deploy flakiness","approach":"investigate retries","u":"hi","f":"mid","home":""}]
JSON
EOF
chmod +x "$TD/bs-extractor.sh"

RC=0
REPO_ROOT="$TD/bs-repo" BACKLOG_STAGE_EXTRACTOR="$TD/bs-extractor.sh" BACKLOG_STAGE_STATE_DIR="$TD/bs-state" \
  bash -c "echo '{\"transcript_path\":\"$BS_TRANS\"}' | bash '$KIT_DIR/hooks/backlog-stage.sh'" >/dev/null 2>&1 || RC=$?
assert_exit "row 3: stages a candidate, exits 0" 0 $RC
STAGED=$(cat "$TD/bs-repo/_meta/backlog-staging.md" 2>/dev/null)
assert_contains "row 3: staged file has the candidate (repo-relative default)" "fix flaky deploy script" "$STAGED"

# NC: empty stdin never blocks a session end.
RC=0; echo '' | bash "$KIT_DIR/hooks/backlog-stage.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: empty stdin exits 0" 0 $RC

# NC: malformed JSON never blocks a session end.
RC=0; echo 'not json' | bash "$KIT_DIR/hooks/backlog-stage.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: malformed JSON exits 0" 0 $RC

# ============================================================
echo ""
echo "=== harvest.sh (PreCompact / SessionEnd) ==="
# ============================================================
mkdir -p "$TD/hv-repo"
git -C "$TD/hv-repo" init -q
HV_TRANS="$TD/hv-transcript.jsonl"
cat > "$HV_TRANS" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"we decided to use REPO_ROOT as the seam"}]}}
EOF
cat > "$TD/hv-extractor.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"item":"repo-root-seam","kind":"decision","home":"drop","why":"consumer config seam"}]
JSON
EOF
chmod +x "$TD/hv-extractor.sh"

RC=0
REPO_ROOT="$TD/hv-repo" HARVEST_EXTRACTOR="$TD/hv-extractor.sh" HARVEST_MIN_INTERVAL=0 \
  bash -c "echo '{\"transcript_path\":\"$HV_TRANS\"}' | bash '$KIT_DIR/hooks/harvest.sh'" >/dev/null 2>&1 || RC=$?
assert_exit "row 4: PreCompact-mode harvest stages a learning, exits 0" 0 $RC
LEDGER=$(cat "$TD/hv-repo/_meta/learned-ledger.md" 2>/dev/null)
assert_contains "row 4: ledger created at repo-relative default with no ledger dir pre-existing" "repo-root-seam" "$LEDGER"

# --lab-log mode
cat > "$TD/hv-lablog.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
## 2026-07-05 - repo-root-seam: adopted repo-relative default via REPO_ROOT
- decided to mirror lib/board/board.sh's repo-root precedent
OUT
EOF
chmod +x "$TD/hv-lablog.sh"
RC=0
REPO_ROOT="$TD/hv-repo" HARVEST_EXTRACTOR="$TD/hv-lablog.sh" HARVEST_MIN_INTERVAL=0 \
  bash -c "echo '{\"transcript_path\":\"$HV_TRANS\"}' | bash '$KIT_DIR/hooks/harvest.sh' --lab-log" >/dev/null 2>&1 || RC=$?
assert_exit "row 4b: --lab-log drafts an entry, exits 0" 0 $RC
DRAFT=$(cat "$TD/hv-repo/_meta/.lab-log-draft.md" 2>/dev/null)
assert_contains "row 4b: draft never writes the real LAB_LOG.md" "repo-root-seam" "$DRAFT"

# NC: empty stdin never blocks a compaction/session-end.
RC=0; echo '' | bash "$KIT_DIR/hooks/harvest.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: empty stdin exits 0" 0 $RC

# NC: malformed JSON never blocks a compaction/session-end.
RC=0; echo 'not json' | bash "$KIT_DIR/hooks/harvest.sh" >/dev/null 2>&1 || RC=$?
assert_exit "NC: malformed JSON exits 0" 0 $RC

# NC: --cleanup on a missing ledger path handles cleanly (no crash, no dir created).
RC=0; HARVEST_LEDGER="$TD/hv-repo/_meta/no-such-ledger.md" bash "$KIT_DIR/hooks/harvest.sh" --cleanup >/dev/null 2>&1 || RC=$?
assert_exit "NC: --cleanup on missing ledger dir exits 0" 0 $RC

# ============================================================
echo ""
echo "=== Registration parity: settings.json AND hooks/hooks.json ==="
# ============================================================
for NAME in backlog-stage citation-guard context-hints harvest; do
  RC=0; grep -q "dwarves-kit/hooks/${NAME}.sh" "$KIT_DIR/settings.json" || RC=1
  assert_exit "settings.json registers $NAME" 0 $RC
  RC=0; grep -q "hooks/${NAME}.sh" "$KIT_DIR/hooks/hooks.json" || RC=1
  assert_exit "hooks/hooks.json registers $NAME" 0 $RC
done

# ============================================================
echo ""
echo "=== Installer materializes all 4 hooks + companions into a temp HOME ==="
# ============================================================
INSTALL_HOME="$TD/install-home"
if HOME="$INSTALL_HOME" bash "$KIT_DIR/install.sh" >/dev/null 2>&1; then
  DEST="$INSTALL_HOME/.claude/dwarves-kit/hooks"
  for NAME in backlog-stage citation-guard context-hints harvest; do
    RC=0; [ -f "$DEST/${NAME}.sh" ] || RC=1
    assert_exit "install.sh materializes hooks/${NAME}.sh" 0 $RC
    RC=0; [ -x "$DEST/${NAME}.sh" ] || RC=1
    assert_exit "install.sh materializes hooks/${NAME}.sh executable" 0 $RC
    RC=0; [ -f "$DEST/${NAME}.py" ] || RC=1
    assert_exit "install.sh materializes hooks/${NAME}.py (companion)" 0 $RC
  done
  RC=0; [ -f "$DEST/context-hints-skills-map.json" ] || RC=1
  assert_exit "install.sh materializes context-hints-skills-map.json (companion)" 0 $RC

  # jq the merged settings.json in the temp HOME to confirm all 4 paths are wired.
  for NAME in backlog-stage citation-guard context-hints harvest; do
    RC=0
    jq -e --arg n "$NAME" \
      '[.hooks | to_entries[] | .value[] | .hooks[].command] | any(contains("dwarves-kit/hooks/" + $n + ".sh"))' \
      "$INSTALL_HOME/.claude/settings.json" >/dev/null 2>&1 || RC=1
    assert_exit "temp-HOME settings.json wires $NAME" 0 $RC
  done
else
  assert_exit "install.sh ran cleanly into a temp HOME" 0 1
fi

# ============================================================
echo ""
echo "=== Skill-copy loop generalization (install.sh) ==="
# ============================================================
# Fabricate a SECOND skill dir the kit ships alongside get-api-docs, so the loop
# is proven to copy every skills/*/SKILL.md, not just the one hardcoded name.
FAKE_KIT="$TD/fake-kit"
cp -R "$KIT_DIR" "$FAKE_KIT"
mkdir -p "$FAKE_KIT/skills/fake-second-skill"
printf '# fake-second-skill\n\nA fixture skill to prove the install.sh copy loop globs.\n' \
  > "$FAKE_KIT/skills/fake-second-skill/SKILL.md"
SKILL_HOME="$TD/skill-home"
if HOME="$SKILL_HOME" bash "$FAKE_KIT/install.sh" >/dev/null 2>&1; then
  RC=0; [ -f "$SKILL_HOME/.claude/skills/get-api-docs/SKILL.md" ] || RC=1
  assert_exit "skill-copy loop still installs get-api-docs" 0 $RC
  RC=0; [ -f "$SKILL_HOME/.claude/skills/fake-second-skill/SKILL.md" ] || RC=1
  assert_exit "skill-copy loop installs a SECOND, non-hardcoded skill (glob proof)" 0 $RC
else
  assert_exit "fake-kit install.sh ran cleanly" 0 1
fi

# ============================================================
echo ""
echo "=== Done gate: no ops-toolkit path leaked into the new files ==="
# ============================================================
LEAK=$(grep -rln 'workspace/tieubao' \
  "$KIT_DIR/hooks/backlog-stage.sh" "$KIT_DIR/hooks/backlog-stage.py" \
  "$KIT_DIR/hooks/citation-guard.sh" "$KIT_DIR/hooks/citation-guard.py" \
  "$KIT_DIR/hooks/context-hints.sh" "$KIT_DIR/hooks/context-hints.py" \
  "$KIT_DIR/hooks/context-hints-skills-map.json" \
  "$KIT_DIR/hooks/harvest.sh" "$KIT_DIR/hooks/harvest.py" 2>/dev/null || true)
assert_eq "no 'workspace/tieubao' in any new file" "" "$LEAK"

# ============================================================
echo ""
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
echo -e "${GREEN}All kit-foldin hooks tests passed.${NC}"
