#!/usr/bin/env bash
# test-install-compat.sh -- install.sh is plugin-aware: when the kit plugin is
# installed, it does a COMPAT-ONLY install (legacy path symlinks) and must NOT
# merge settings.json hooks or add flat commands (that would double-register).
set -euo pipefail
KIT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

# --- plugin present -> compat-only ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "${TMP2:-}"' EXIT
mkdir -p "$TMP/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
out="$(CLAUDE_DIR="$TMP" bash "$KIT_DIR/install.sh" 2>&1)"

printf '%s' "$out" | grep -q 'COMPAT-ONLY'; chk "took the compat branch" $?
[ -L "$TMP/dwarves-kit/lib" ];         chk "lib symlink created" $?
[ -L "$TMP/dwarves-kit/WORKFLOW.md" ]; chk "WORKFLOW.md symlink created" $?
[ -L "$TMP/dwarves-kit/AGENTS.md" ];   chk "AGENTS.md symlink created" $?
[ ! -e "$TMP/settings.json" ];         chk "settings.json NOT written (no double hooks)" $?
[ -e "$TMP/dwarves-kit/lib/lane-classify.sh" ]; chk "compat lib resolves to a real script" $?

# --- KIT_FORCE_FULL bypasses compat even with the plugin present ---
TMP2="$(mktemp -d)"
mkdir -p "$TMP2/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
out2="$(CLAUDE_DIR="$TMP2" KIT_FORCE_FULL=1 bash "$KIT_DIR/install.sh" 2>&1 || true)"
if printf '%s' "$out2" | grep -q 'COMPAT-ONLY'; then echo "FAIL KIT_FORCE_FULL still compat"; fail=1; else echo "ok   KIT_FORCE_FULL bypasses compat"; fi

[ "$fail" -eq 0 ] && echo "PASS: install compat" || { echo "SOME TESTS FAILED"; exit 1; }
