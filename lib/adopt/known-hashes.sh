#!/usr/bin/env bash
# known-hashes.sh -- regenerate agents-known.sha256: the sha256 of every version of the kit's
# AGENTS.md ever committed, plus every version of the pointer template (committed and current).
# adopt.sh reads the list to tell an unmodified old kit copy from a file the operator edited.
# Refuses in a shallow clone: a shallow history silently drops old versions, and a dropped
# version reads as "edited" and is never swapped.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/../.." && pwd)"
LIST="$SELF_DIR/agents-known.sha256"

sha256_stdin() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -d' ' -f1; }

if [ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" != "false" ]; then
  echo "known-hashes: refusing in a shallow clone (or a non-git tree): history is incomplete, $LIST left unchanged" >&2
  exit 1
fi

out="$(mktemp)"; trap 'rm -f "$out"' EXIT

versions() { # $1 = repo path, $2 = label
  local c h
  for c in $(git -C "$REPO" log --format=%H -- "$1"); do
    h="$(git -C "$REPO" show "$c:$1" 2>/dev/null | sha256_stdin)" || continue
    git -C "$REPO" cat-file -e "$c:$1" 2>/dev/null && echo "$h $2:${c:0:12}"
  done
}

{
  versions AGENTS.md agents
  versions lib/adopt/AGENTS.pointer.md pointer
  [ -f "$SELF_DIR/AGENTS.pointer.md" ] && echo "$(sha256_stdin < "$SELF_DIR/AGENTS.pointer.md") pointer:current"
} | awk '!seen[$1]++' | sort > "$out"

mv "$out" "$LIST"; trap - EXIT
echo "known-hashes: wrote $(wc -l < "$LIST" | tr -d ' ') entries to $LIST"
