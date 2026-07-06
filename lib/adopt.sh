#!/usr/bin/env bash
# adopt.sh -- idempotently inject the dwarves-kit operate-contract into a target repo.
#
# Adoption = the per-repo trigger that makes an agent classify + pick a lane and that makes the
# ship-gate engage. It injects the CONTRACT + a proof marker + pointers; it never copies the
# engine (lib/, the full WORKFLOW matrix) -- the gate machinery reads those from the install
# ($KIT_ROOT). Non-destructive: AGENTS.md + the proof marker are never overwritten.
#
# The CLAUDE.md loader uses an `@AGENTS.md` import (Claude Code includes the file, not just a
# "go read it" pointer; absorbed from repository-harness's --claude shim).
#
# Usage: adopt.sh [--check | --dry-run | --refresh] <target-dir>
#   --check   : report status only (exit 0 adopted / 1 not), write nothing.
#   --dry-run : print what would change, write nothing.
#   --refresh : re-sync the kit-managed pieces (WORKFLOW pointer + the CLAUDE.md loader block)
#               to their current form. AGENTS.md + the proof marker are still never overwritten.
set -uo pipefail

KIT_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SELF_DIR/.." && pwd)"   # the dwarves-kit repo root when run from its lib/
START="<!-- kit:adopt -->"               # managed-block markers in the consumer CLAUDE.md
END="<!-- /kit:adopt -->"

tmp=""                                   # scratch file; the trap cleans it up on any early exit
trap 'rm -f "$tmp"' EXIT

usage() { echo "usage: adopt.sh [--check | --dry-run | --refresh] [--] <target-dir>" >&2; exit 64; }

CHECK=0 DRY=0 REFRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift;;
    --dry-run) DRY=1; shift;;
    --refresh) REFRESH=1; shift;;
    --) shift; break;;
    -*) usage;;
    *) break;;
  esac
done
TARGET="${1:-}"; [ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { echo "adopt: target dir not found: $TARGET" >&2; exit 1; }

agents="$TARGET/AGENTS.md"
workflow="$TARGET/WORKFLOW.md"
claude="$TARGET/CLAUDE.md"
marker="$TARGET/docs/verification/README.md"

is_adopted() {
  # -qxF: the marker must be its own full line (matches how awk strips the block). A substring
  # grep would mis-detect a marker quoted inside prose and skip the append path (review #6).
  [ -f "$agents" ] && [ -f "$marker" ] && [ -f "$claude" ] \
    && grep -qxF "$START" "$claude" 2>/dev/null
}

if [ "$CHECK" -eq 1 ]; then
  is_adopted && { echo "adopted: $TARGET"; exit 0; } || { echo "not adopted: $TARGET"; exit 1; }
fi

git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || echo "adopt: warning: $TARGET is not a git repo (adopting at filesystem level anyway)" >&2

# Resolve a source AGENTS.md: the kit repo (dev) first, then the install.
src_agents=""
for c in "$SRC_ROOT/AGENTS.md" "$KIT_ROOT/AGENTS.md"; do
  [ -f "$c" ] && { src_agents="$c"; break; }
done
[ -n "$src_agents" ] || { echo "adopt: no source AGENTS.md (looked in $SRC_ROOT, $KIT_ROOT)" >&2; exit 1; }

workflow_block() {
  cat <<EOF
# WORKFLOW.md (pointer)

This repo is adopted into the dwarves-kit. The canonical lanes and the lane x phase gate matrix
live in the installed kit: \`$KIT_ROOT/WORKFLOW.md\`. Read that for the lanes and the gate at each
phase boundary. The gate machinery (gate-ledger, ship-gate) parses that copy, not this file.
EOF
}

claude_block() {
  printf '%s\n' "$START"
  printf '## Operating layer (dwarves-kit)\n\n'
  printf '@AGENTS.md\n\n'
  printf 'Before touching code, classify the lane: `bash %s/bin/classify lane classify "<task>"`.\n' "$KIT_ROOT"
  printf 'A full-lane change records its gates via `%s/bin/gate ledger` or the ship-gate blocks the push.\n' "$KIT_ROOT"
  printf '%s\n' "$END"
}

did=0
note() { echo "adopt: would $*"; }

# 1. AGENTS.md -- the operate-contract. NEVER overwritten (even on --refresh).
if [ ! -f "$agents" ]; then
  if [ "$DRY" -eq 1 ]; then note "create AGENTS.md (from $src_agents)"; else cp "$src_agents" "$agents"; fi
  did=1
fi

# 2. WORKFLOW.md pointer -- create if absent; --refresh overwrites to current. Write atomically
# (tmp + mv) so a kill / full disk mid-write can't leave a half-written pointer (review #3).
if [ ! -f "$workflow" ] || { [ "$REFRESH" -eq 1 ] && ! cmp -s <(workflow_block) "$workflow"; }; then
  if [ "$DRY" -eq 1 ]; then note "write WORKFLOW.md pointer"; else
    tmp="$(mktemp)"; workflow_block > "$tmp"; mv "$tmp" "$workflow"
  fi
  did=1
fi

# 3. CLAUDE.md loader (@AGENTS.md import) -- append once; --refresh replaces the managed block.
if [ ! -f "$claude" ] || ! grep -qxF "$START" "$claude" 2>/dev/null; then
  if [ "$DRY" -eq 1 ]; then note "append the CLAUDE.md @AGENTS.md loader block"; else
    tmp="$(mktemp)"; { [ -f "$claude" ] && cat "$claude"; printf '\n'; claude_block; } > "$tmp"; mv "$tmp" "$claude"
  fi
  did=1
elif [ "$REFRESH" -eq 1 ]; then
  # Refuse to refresh a block with a START but no END: the awk strip would drop everything from
  # START to EOF and mv would install the truncated file (silent data loss; review CRITICAL #1).
  # This is exactly the legacy single-sentinel shape, so the operator migrates it by hand.
  if ! grep -qxF "$END" "$claude" 2>/dev/null; then
    echo "adopt: $claude has '$START' but no '$END' line; refusing --refresh (would truncate)." >&2
    echo "adopt: add an '$END' line after the managed block, or delete the block, then re-run." >&2
    exit 1
  fi
  if [ "$DRY" -eq 1 ]; then note "refresh the CLAUDE.md loader block"; did=1; else
    tmp="$(mktemp)"
    # END{if(drop)exit 3}: belt-and-suspenders against an unterminated block slipping past the
    # guard above; the `|| exit` stops us from mv-ing a truncated file when awk bails.
    awk -v s="$START" -v e="$END" '
      $0==s{drop=1; next} drop&&$0==e{drop=0; next} !drop{print}
      END{if(drop) exit 3}' "$claude" > "$tmp" \
      || { echo "adopt: failed to strip the managed block from $claude (unterminated?)" >&2; exit 1; }
    claude_block >> "$tmp"
    if cmp -s "$tmp" "$claude"; then rm -f "$tmp"; else mv "$tmp" "$claude"; did=1; fi
  fi
fi

# 4. proof marker -- presence opts this repo into the ship-gate. NEVER overwritten.
if [ ! -f "$marker" ]; then
  if [ "$DRY" -eq 1 ]; then note "create docs/verification/README.md (proof marker)"; else
    mkdir -p "$(dirname "$marker")"
    cat > "$marker" <<EOF
# Verification (proof-of-done marker)

Presence of this file opts this repo into the dwarves-kit proof-of-done ship-gate. A
behavioral/stateful change owes a recorded run here; the shape per loop type comes from the
install: \`bash $KIT_ROOT/lib/gate/proof-gate.sh contract "<task>"\`.
EOF
  fi
  did=1
fi

if [ "$DRY" -eq 1 ]; then
  echo "adopt: --dry-run for $TARGET ($([ "$did" -eq 1 ] && echo 'changes above' || echo 'already adopted, nothing to do'))"
else
  echo "adopt: $TARGET ($([ "$did" -eq 1 ] && echo updated || echo 'already adopted, no-op'))"
fi
