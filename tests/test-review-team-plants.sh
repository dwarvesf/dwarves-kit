#!/usr/bin/env bash
# test-review-team-plants.sh -- Behavioral regression guard for the /review-team
# security lens. Plants known-bad fixtures (out of the repo, under $TMPDIR) and
# asserts the kit's security-review prompts still carry the detection vocabulary
# needed to catch each planted class.
#
# We cannot dispatch a live Claude reviewer in CI, so we test prompt completeness
# instead: every required term must appear in security-reviewer.md OR code-reviewer.md.
# A term missing from BOTH means a vulnerability class was silently dropped from
# the review checklist -- the exact drift observed when adopting superpowers
# v5.1.0. See SPEC-002 TASK-1 (DEC-001, DEC-006, DEC-007).
#
# Fixture credential values are deliberate placeholders, never real-looking
# secret patterns: the fixture only needs to REPRESENT each class; the actual
# assertion greps the prompt vocabulary, not the fixture.
#
# Run: bash tests/test-review-team-plants.sh
# Exit 0 = every required term present. Exit 1 = a class dropped.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert() {
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

# --- Plant the fixture OUT of the repo; trap-clean on exit -------------------
# ${TMPDIR:-/tmp} so this works on Ubuntu CI runners where TMPDIR is unset.
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dwarves-kit-test.XXXXXX")"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Class 1: SQL injection (string-interpolated query)
cat > "$FIXTURE_DIR/db.py" <<'PLANT'
def lookup(user_id):
    return db.execute("SELECT * FROM users WHERE id = '%s'" % user_id)
PLANT

# Class 2: hardcoded credential (placeholder value, not a real key pattern)
cat > "$FIXTURE_DIR/config.ini" <<'PLANT'
[auth]
# gitleaks:allow  representative fixture, not a real secret
credential = "PLACEHOLDER_not_a_real_secret"
PLANT

# Class 3: command injection (unsanitized input to a shell)
cat > "$FIXTURE_DIR/run.py" <<'PLANT'
import os
def ping(host):
    os.system("ping -c1 " + host)
PLANT

PLANTED=$(find "$FIXTURE_DIR" -type f | wc -l | tr -d ' ')

echo "=== /review-team security-lens prompt coverage ==="
echo "  (fixture: $PLANTED planted files under $FIXTURE_DIR, removed on exit)"

# At least 3 planted files covering 3 distinct vulnerability classes.
# The fixture covers 3 vulnerability classes (SQL injection, hardcoded
# credential, command injection). The 7-term prompt check below is broader by
# design (DEC-001): it greps the review prompts for the full vocabulary, the
# fixtures only represent the planted-bad shape, they are not fed to a scanner.
if [ "$PLANTED" -ge 3 ]; then
  assert "fixture has >= 3 planted files (SQL-i, hardcoded cred, command-i)" 0
else
  assert "fixture has >= 3 planted files (SQL-i, hardcoded cred, command-i; got $PLANTED)" 1
fi

SEC="$KIT_DIR/agents/security-reviewer.md"
REV="$KIT_DIR/agents/code-reviewer.md"

# Each required term must appear in security-reviewer.md OR code-reviewer.md. The
# code-reviewer's security lens inherits the security-reviewer checklist, so a term in
# either file covers the class; a term missing from BOTH fails the build.
for TERM in "SQL injection" "Command injection" "Path traversal" "XSS" "hardcoded" "PII" "CORS"; do
  if grep -qi "$TERM" "$SEC" || grep -qi "$TERM" "$REV"; then
    assert "security vocab present: '$TERM'" 0
  else
    assert "security vocab MISSING from both prompts: '$TERM'" 1
  fi
done

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All review-team plant tests passed.${NC}"
  exit 0
fi
