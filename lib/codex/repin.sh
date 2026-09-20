#!/usr/bin/env bash
# repin.sh -- recompute the sha256 trust pins in hooks/codex-hooks.json.
#
# Every command in codex-hooks.json pins the content of the file it execs (and
# of codex-hook-adapter.sh) through an inline check of the shape:
#
#   hash_file "${PLUGIN_ROOT}/hooks/<name>.sh" | /usr/bin/grep -q '^<sha256> '
#
# Editing any pinned file makes the pins stale and turns tests/test-codex-hooks.sh
# red until they are rewritten. This verb is the committed replacement for the
# hand-rolled one-offs that did that rewrite (PRs #653, #656).
#
# Usage:
#   repin.sh [kit-root]          recompute every pin, rewrite the file in place;
#                                a no-op (nothing written) when all pins are fresh
#   repin.sh check [kit-root]    verify only: exit 0 when fresh, exit 1 naming
#                                each file whose pin is stale
#
# kit-root defaults to the repo this script sits in. Hashing follows the same
# portable chain the embedded hash_file() does: shasum -a 256, else sha256sum.
set -euo pipefail
export LC_ALL=C

MODE=repin
case "${1:-}" in
  check) MODE=check; shift ;;
  repin) shift ;;
  -h|--help) sed -n '10,20p' "$0"; exit 0 ;;
esac

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
JSON="$ROOT/hooks/codex-hooks.json"
[ -f "$JSON" ] || { echo "repin: no codex-hooks.json under $ROOT" >&2; exit 2; }
command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1 \
  || { echo "repin: need shasum or sha256sum" >&2; exit 2; }

hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1";
  else sha256sum "$1"; fi
}

# Pinned names as written in the commands: "hooks/<name>.sh" directly ahead of
# each '^<hex> ' pin. Derived from the file, so a hook added to the manifest is
# repinned without a code change here.
PINNED=$(grep -oE "hooks/[A-Za-z0-9._-]+\.sh[^']*'\^[0-9a-f]{64} '" "$JSON" \
  | grep -oE '^hooks/[A-Za-z0-9._-]+\.sh' | sort -u)
[ -n "$PINNED" ] || { echo "repin: no trust pins found in $JSON" >&2; exit 2; }

NEW="$(mktemp "${TMPDIR:-/tmp}/codex-hooks-repin.XXXXXX")"
trap 'rm -f "$NEW" "$NEW.tmp"' EXIT
cp "$JSON" "$NEW"

STALE=""
while IFS= read -r name; do
  file="$ROOT/$name"
  [ -f "$file" ] || { echo "repin: pinned file missing: $name" >&2; exit 2; }
  fresh=$(hash_file "$file" | awk '{print $1}')
  esc="${name//./\\.}"
  pins=$(grep -oE "${esc}[^']*'\^[0-9a-f]{64} '" "$NEW" || true)
  [ -n "$pins" ] || { echo "repin: no pin found for $name" >&2; exit 2; }
  stale=$(printf '%s\n' "$pins" | grep -cvF "^${fresh} " || true)
  [ "${stale:-0}" -gt 0 ] || continue
  STALE="${STALE:+$STALE }$name"
  [ "$MODE" = check ] && continue
  sed -E "s#(${esc}[^']*'\^)[0-9a-f]{64}( ')#\1${fresh}\2#g" "$NEW" > "$NEW.tmp"
  mv "$NEW.tmp" "$NEW"
done <<< "$PINNED"

if [ -z "$STALE" ]; then
  echo "repin: all pins fresh in hooks/codex-hooks.json"
  exit 0
fi
if [ "$MODE" = check ]; then
  for name in $STALE; do echo "repin: stale pin: $name" >&2; done
  exit 1
fi
mv "$NEW" "$JSON"
for name in $STALE; do echo "repin: repinned $name"; done
