#!/usr/bin/env bash
# adopt.sh -- idempotently inject the dwarves-kit operate-contract into a target repo.
#
# Adoption = the per-repo trigger that makes an agent classify + pick a lane and that makes the
# ship-gate engage. It injects the CONTRACT + a proof marker + pointers; it never copies the
# engine (lib/, the full WORKFLOW matrix) -- the gate machinery reads those from the install
# ($KIT_ROOT). Non-destructive: existing files are never overwritten; re-run is a clean no-op.
#
# Usage: adopt.sh [--check] <target-dir>
#   --check : report status only (exit 0 adopted / 1 not), write nothing.
set -uo pipefail

KIT_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SELF_DIR/.." && pwd)"   # the dwarves-kit repo root when run from its lib/
MARKER="<!-- kit:adopt -->"              # idempotency sentinel in the consumer CLAUDE.md

usage() { echo "usage: adopt.sh [--check] <target-dir>" >&2; exit 64; }

CHECK=0
[ "${1:-}" = "--check" ] && { CHECK=1; shift; }
TARGET="${1:-}"; [ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { echo "adopt: target dir not found: $TARGET" >&2; exit 1; }

agents="$TARGET/AGENTS.md"
workflow="$TARGET/WORKFLOW.md"
claude="$TARGET/CLAUDE.md"
marker="$TARGET/docs/verification/README.md"

is_adopted() {
  [ -f "$agents" ] && [ -f "$marker" ] && [ -f "$claude" ] \
    && grep -q "$MARKER" "$claude" 2>/dev/null
}

if [ "$CHECK" -eq 1 ]; then
  is_adopted && { echo "adopted: $TARGET"; exit 0; } || { echo "not adopted: $TARGET"; exit 1; }
fi

# Adoption is filesystem-level, but a non-git target usually means a wrong path; warn (SPEC-047 edge 3).
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || echo "adopt: warning: $TARGET is not a git repo (adopting at filesystem level anyway)" >&2

# Resolve a source AGENTS.md: the kit repo (dev) first, then the install.
src_agents=""
for c in "$SRC_ROOT/AGENTS.md" "$KIT_ROOT/AGENTS.md"; do
  [ -f "$c" ] && { src_agents="$c"; break; }
done
[ -n "$src_agents" ] || { echo "adopt: no source AGENTS.md (looked in $SRC_ROOT, $KIT_ROOT)" >&2; exit 1; }

changed=0

# 1. AGENTS.md -- the operate-contract. Never overwrite.
if [ ! -f "$agents" ]; then cp "$src_agents" "$agents"; changed=1; fi

# 2. WORKFLOW.md -- a POINTER, not the 49KB matrix (the gate reads the install's copy).
if [ ! -f "$workflow" ]; then
  cat > "$workflow" <<EOF
# WORKFLOW.md (pointer)

This repo is adopted into the dwarves-kit. The canonical lanes and the lane x phase gate matrix
live in the installed kit: \`$KIT_ROOT/WORKFLOW.md\`. Read that for the lanes and the gate at each
phase boundary. The gate machinery (gate-ledger, ship-gate) parses that copy, not this file.
EOF
  changed=1
fi

# 3. CLAUDE.md loader pointer -- Claude Code auto-loads CLAUDE.md, not AGENTS.md. Append once.
if [ ! -f "$claude" ] || ! grep -q "$MARKER" "$claude" 2>/dev/null; then
  {
    printf '\n%s\n' "$MARKER"
    printf '## Operating layer (dwarves-kit)\n\n'
    printf 'Read **AGENTS.md** first: it is the operate-contract. Before touching code, classify\n'
    printf 'the work and pick a lane: `bash %s/lib/lane-classify.sh classify "<task>"`. A full-lane\n' "$KIT_ROOT"
    printf 'change records its gates via `%s/lib/gate-ledger.sh` or the ship-gate blocks the push.\n' "$KIT_ROOT"
  } >> "$claude"
  changed=1
fi

# 4. proof marker -- presence opts this repo into the ship-gate.
if [ ! -f "$marker" ]; then
  mkdir -p "$(dirname "$marker")"
  cat > "$marker" <<EOF
# Verification (proof-of-done marker)

Presence of this file opts this repo into the dwarves-kit proof-of-done ship-gate. A
behavioral/stateful change owes a recorded run here; the shape per loop type comes from the
install: \`bash $KIT_ROOT/lib/proof-gate.sh contract "<task>"\`.
EOF
  changed=1
fi

echo "adopt: $TARGET ($([ "$changed" -eq 1 ] && echo updated || echo 'already adopted, no-op'))"
