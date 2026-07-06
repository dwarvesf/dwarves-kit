#!/usr/bin/env bash
# test-install-contract.sh -- adopt.sh + gate-ledger work from an INSTALL that has AGENTS.md +
# WORKFLOW.md (+ docs/WORKFLOW.md bulk, SPEC-185) deployed (SPEC-049). Simulates install.sh's
# out-of-place symlink layout.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

mkinstall() { # $1=dir  $2=with-contract(yes/no/stub-only): mirror install.sh's out-of-place symlinks
  mkdir -p "$1"
  ln -s "$KIT/lib" "$1/lib"
  if [ "$2" = yes ]; then
    ln -s "$KIT/AGENTS.md" "$1/AGENTS.md"
    ln -s "$KIT/WORKFLOW.md" "$1/WORKFLOW.md"
    mkdir -p "$1/docs"
    ln -s "$KIT/docs/WORKFLOW.md" "$1/docs/WORKFLOW.md"
  elif [ "$2" = stub-only ]; then
    # the root stub deployed, but NOT the docs/ bulk -- the exact SPEC-185 install-copy gap
    ln -s "$KIT/AGENTS.md" "$1/AGENTS.md"
    ln -s "$KIT/WORKFLOW.md" "$1/WORKFLOW.md"
  fi
}

# 1. adopt run FROM the install finds the source AGENTS.md + lands the contract
INSTALL="$(mktemp -d)/dwarves-kit"; mkinstall "$INSTALL" yes
TMP="$(mktemp -d)"; git -C "$TMP" init -q
if CLAUDE_PLUGIN_ROOT="$INSTALL" bash "$INSTALL/lib/adopt.sh" "$TMP" >/dev/null 2>&1 \
  && [ -f "$TMP/AGENTS.md" ] && [ -f "$TMP/WORKFLOW.md" ]; then
  ok "adopt from the install creates the contract (source AGENTS.md resolved)"
else
  no "adopt from the install failed to find/create the contract"
fi

# 2. gate-ledger reads the lane matrix from the install's docs/WORKFLOW.md (SPEC-185 bulk)
N=$(CLAUDE_PLUGIN_ROOT="$INSTALL" bash "$INSTALL/lib/gate/gate-ledger.sh" required full 2>/dev/null | wc -l | tr -d ' ')
[ "${N:-0}" -ge 5 ] && ok "gate-ledger reads the lane matrix from the install ($N gates)" || no "gate-ledger could not read docs/WORKFLOW.md from the install (got $N)"

# 3. CONTROL: an install WITHOUT the contract symlinks -> adopt fails (proves the fix is load-bearing)
BARE="$(mktemp -d)/dwarves-kit"; mkinstall "$BARE" no
TMP2="$(mktemp -d)"; git -C "$TMP2" init -q
if CLAUDE_PLUGIN_ROOT="$BARE" bash "$BARE/lib/adopt.sh" "$TMP2" >/dev/null 2>&1; then
  no "control: adopt should FAIL from an install without the contract symlinks"
else
  ok "control: adopt without the contract symlinks fails as expected"
fi

# 4. NEGATIVE CONTROL (SPEC-185): an install with the root STUB but WITHOUT the docs/ bulk ->
# gate-ledger must FAIL to resolve the lane matrix, proving the repoint to docs/WORKFLOW.md is
# real (a reader still pointed at the old flat WORKFLOW.md, which is now stub-only, gets nothing).
STUB="$(mktemp -d)/dwarves-kit"; mkinstall "$STUB" stub-only
N4=$(CLAUDE_PLUGIN_ROOT="$STUB" bash "$STUB/lib/gate/gate-ledger.sh" required full 2>/dev/null | wc -l | tr -d ' ')
[ "${N4:-0}" -lt 5 ] && ok "NC: gate-ledger fails against a stub-only WORKFLOW.md with no docs/ bulk (got $N4 rows)" \
  || no "NC: gate-ledger should NOT resolve the lane matrix from the stub alone (got $N4 rows, expected <5)"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
