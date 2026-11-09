#!/usr/bin/env bash
# test-proof-green-reader.sh
# What counts as a green run in a proof file. Green iff NOT vetoed and one of:
#   (a) the last line-start `Verdict:` is PASS     (b) an `Exit: 0` line
#   (c) a markdown table cell starting PASS/PASSED, with no cell that is exactly FAIL/INCONCLUSIVE
#   (d) a line-start `PASS` harness token (`PASS  C-cut fires`)
# Veto: the last line-start `Verdict:` reads FAIL or INCONCLUSIVE. A bare PASS in prose is not green.
# Every case carries an `Output:` slot with real lines, so only the green reader decides.
# module under test: lib/gate/proof-ledger.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0; total=0
pass(){ total=$((total+1)); echo "PASS $*"; }
fail(){ total=$((total+1)); echo "FAIL $*"; fails=$((fails+1)); }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-proof-green.XXXXXX")" || exit 1
trap 'rm -rf "$TMPD"' EXIT
export KIT_LEDGER_DIR="$TMPD/ledger" KIT_CONFIG_OPERATOR="$TMPD/no-operator-config"
export GIT_TEMPLATE_DIR="$TMPD/no-git-template"; mkdir -p "$GIT_TEMPLATE_DIR"

n=0
# behavioral -- a behavioral diff plus a proof file holding stdin; prints the repo path
behavioral() {
  n=$((n+1)); local d="$TMPD/r$n"
  mkdir -p "$d/docs/verification" "$d/lib"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  echo "# Verification log" > "$d/docs/verification/README.md"; echo baseline > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"
  { echo "# Verification"; echo "## NEGATIVE CONTROL"; echo "reverting the change turns this RED."; cat; } > "$d/docs/verification/vf.md"
  printf '%s\n' "$d"
}
gate(){ bash "$LIB" check "$1" "$(git -C "$1" rev-parse HEAD)" vf 2>&1; }
accepts(){ if gate "$2" >/dev/null; then pass "$1"; else fail "$1 (BLOCKED, want ACCEPT)"; fi; }
blocks(){ if gate "$2" >/dev/null; then fail "$1 (ACCEPTED, want BLOCK)"; else pass "$1"; fi; }

echo "=== not green ==="
D="$(behavioral prose <<'EOF'
Command: `bash lib/thing.sh`
Output:
the run printed some lines
a false PASS is worse than an honest gap
EOF
)"
blocks "PASS only in prose is not green" "$D"

D="$(behavioral failcell <<'EOF'
Output:
the table below is the run
| case | result |
| a | PASS |
| b | FAIL |
EOF
)"
blocks "a PASS cell beside a FAIL cell is not green" "$D"

D="$(behavioral inconccell <<'EOF'
Output:
| a | PASS |
| b | INCONCLUSIVE |
EOF
)"
blocks "a PASS cell beside an INCONCLUSIVE cell is not green" "$D"

D="$(behavioral veto <<'EOF'
Command: `bash lib/thing.sh`
Exit: 0
Output:
| a | PASS |
Verdict: FAIL
EOF
)"
blocks "a last Verdict: FAIL vetoes Exit: 0 and PASS cells" "$D"

echo "=== green ==="
D="$(behavioral exit0 <<'EOF'
Command: `bash lib/thing.sh`
Exit: 0
Output:
test-thing: ok
EOF
)"
accepts "an Exit: 0 line is green" "$D"

D="$(behavioral verdict <<'EOF'
Command: `bash lib/thing.sh`
Output:
test-thing: ok
Verdict: PASS
EOF
)"
accepts "a last Verdict: PASS is green" "$D"

D="$(behavioral cell <<'EOF'
Output:
| AC1 | schema parity | PASS |
| AC2 | other | PASS (trace 3) |
EOF
)"
accepts "a PASS table cell is green" "$D"

D="$(behavioral passed <<'EOF'
Output:
| Runner suite | `python3 tests/test_bench.py` | PASSED 6/6 |
EOF
)"
accepts "a table cell starting PASSED is green" "$D"

D="$(behavioral harness <<'EOF'
Output:
PASS  C-cut fires ceremony
PASS  C-cut action=CUT
EOF
)"
accepts "line-start PASS harness lines are green" "$D"

echo
[ "$fails" -eq 0 ] && { echo "test-proof-green-reader: all $total passed"; exit 0; } || { echo "test-proof-green-reader: $fails FAILED of $total"; exit 1; }
