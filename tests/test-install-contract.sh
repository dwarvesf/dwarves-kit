#!/usr/bin/env bash
# test-install-contract.sh -- adopt.sh + gate-ledger work from an INSTALL that has AGENTS.md +
# WORKFLOW.md deployed (SPEC-049). Simulates install.sh's out-of-place symlink layout.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

mkinstall() { # $1=dir  $2=with-contract(yes/no): mirror install.sh's out-of-place symlinks
  mkdir -p "$1"
  ln -s "$KIT/lib" "$1/lib"
  if [ "$2" = yes ]; then ln -s "$KIT/AGENTS.md" "$1/AGENTS.md"; ln -s "$KIT/WORKFLOW.md" "$1/WORKFLOW.md"; fi
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

# 2. gate-ledger reads the lane matrix from the install's WORKFLOW.md
N=$(CLAUDE_PLUGIN_ROOT="$INSTALL" bash "$INSTALL/lib/gate/gate-ledger.sh" required full 2>/dev/null | wc -l | tr -d ' ')
[ "${N:-0}" -ge 5 ] && ok "gate-ledger reads the lane matrix from the install ($N gates)" || no "gate-ledger could not read WORKFLOW.md from the install (got $N)"

# 3. CONTROL: an install WITHOUT the contract symlinks -> adopt fails (proves the fix is load-bearing)
BARE="$(mktemp -d)/dwarves-kit"; mkinstall "$BARE" no
TMP2="$(mktemp -d)"; git -C "$TMP2" init -q
if CLAUDE_PLUGIN_ROOT="$BARE" bash "$BARE/lib/adopt.sh" "$TMP2" >/dev/null 2>&1; then
  no "control: adopt should FAIL from an install without the contract symlinks"
else
  ok "control: adopt without the contract symlinks fails as expected"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
