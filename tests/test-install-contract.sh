#!/usr/bin/env bash
# test-install-contract.sh -- adopt.sh + gate-ledger work from an INSTALL that has AGENTS.md +
# WORKFLOW.md (+ docs/WORKFLOW.md bulk, SPEC-185) + kit.toml (the lane data, SPEC-368) deployed
# (SPEC-049). Simulates install.sh's out-of-place symlink layout.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

mkinstall() { # $1=dir  $2=with-contract(yes/no/stub-only/no-lane-data): mirror install.sh's out-of-place symlinks
  mkdir -p "$1"
  ln -s "$KIT/lib" "$1/lib"
  # lane data lives in kit.toml since lanes-as-data (148c6923); gate-ledger reads it from the install
  [ "$2" = no-lane-data ] || ln -s "$KIT/kit.toml" "$1/kit.toml"
  if [ "$2" = yes ] || [ "$2" = no-lane-data ]; then
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

# 2. gate-ledger reads the lane matrix from the install's kit.toml (lane data, 148c6923)
N=$(CLAUDE_PLUGIN_ROOT="$INSTALL" bash "$INSTALL/lib/gate/gate-ledger.sh" required full 2>/dev/null | wc -l | tr -d ' ')
[ "${N:-0}" -ge 5 ] && ok "gate-ledger reads the lane matrix from the install ($N gates)" || no "gate-ledger could not read the lane data from the install (got $N)"

# 3. adopt from an install WITHOUT the contract symlinks. Before ca34e023 (small AGENTS.md pointer)
# adopt copied the install's AGENTS.md and had to fail without it, so this was a "must fail" control.
# Now adopt writes the self-contained pointer from lib/adopt/ and reads the full contract only to
# measure drift, so the assertion flips: it lands the pointer and exits 0.
BARE="$(mktemp -d)/dwarves-kit"; mkinstall "$BARE" no
TMP2="$(mktemp -d)"; git -C "$TMP2" init -q
if CLAUDE_PLUGIN_ROOT="$BARE" bash "$BARE/lib/adopt.sh" "$TMP2" >/dev/null 2>&1 \
  && [ -f "$TMP2/AGENTS.md" ] && cmp -s "$TMP2/AGENTS.md" "$KIT/lib/adopt/AGENTS.pointer.md"; then
  ok "adopt without the contract symlinks lands the self-contained pointer (ca34e023)"
else
  no "adopt without the contract symlinks should still land the AGENTS.md pointer"
fi

# 4. NEGATIVE CONTROL: an install with the full contract (stub + docs/ bulk) but WITHOUT kit.toml ->
# gate-ledger must FAIL to resolve the lane matrix, proving the kit.toml read is real (SPEC-185 made
# docs/WORKFLOW.md the human view; 148c6923 moved the lane data into kit.toml, so a reader pointed
# at WORKFLOW.md gets nothing from the contract files alone).
NOLD="$(mktemp -d)/dwarves-kit"; mkinstall "$NOLD" no-lane-data
N4=$(CLAUDE_PLUGIN_ROOT="$NOLD" bash "$NOLD/lib/gate/gate-ledger.sh" required full 2>/dev/null | wc -l | tr -d ' ')
[ "${N4:-0}" -lt 5 ] && ok "NC: gate-ledger fails against an install with no kit.toml lane data (got $N4 rows)" \
  || no "NC: gate-ledger should NOT resolve the lane matrix without kit.toml (got $N4 rows, expected <5)"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
