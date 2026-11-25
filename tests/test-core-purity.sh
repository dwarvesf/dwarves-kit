#!/usr/bin/env bash
# test-core-purity.sh -- core `lib/board` and `lib/sync` name no specific app. The four apps are
# Hermes, Notion, Reminders and Multica; their code, text, names and dated records live under
# `lib/adapters/`. The scan covers tracked files only (`git grep`, `git ls-files`): ignored
# `__pycache__` directories of an old checkout hold app names and survive a `git mv`, so a scan
# of the work tree would lie.
#
# Negative control: the tracked files of the two core trees are copied to a scratch dir, a file
# that names `Hermes` and a file named `notion_named.sh` are planted there, and the scanner must
# report both. A scanner that prints nothing for the plant fails the suite.
#
# Run: bash tests/test-core-purity.sh
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$KIT" || exit 1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

WORDS='hermes|notion|reminders|multica'
ROOTS="lib/board lib/sync"

W="$(mktemp -d "${TMPDIR:-/tmp}/kit-purity.XXXXXX")" || exit 1
W="$(cd "$W" && pwd -P)"
trap 'command rm -rf "$W"' EXIT

git rev-parse --git-dir >/dev/null 2>&1 || { echo "  SKIP not a git checkout: the scan needs tracked files"; exit 0; }

echo "=== the tracked tree ==="
# shellcheck disable=SC2086
content_hits="$(git grep -ilE -e "$WORDS" -- $ROOTS 2>/dev/null)"
eq "no tracked file under lib/board or lib/sync names an app (content)" "$content_hits" ""
for w in hermes notion reminders multica; do
  # shellcheck disable=SC2086
  eq "git grep -il $w -- lib/board lib/sync prints nothing" "$(git grep -il "$w" -- $ROOTS 2>/dev/null)" ""
done
# shellcheck disable=SC2086
name_hits="$(git ls-files $ROOTS | grep -iE "$WORDS")"
eq "no tracked file name under lib/board or lib/sync names an app" "$name_hits" ""
eq "no tracked file remains under lib/sync/sources" "$(git ls-files lib/sync/sources)" ""
eq "no tracked file remains under lib/sync/docs" "$(git ls-files lib/sync/docs)" ""

echo "=== the scanner finds a plant (negative control) ==="
# scan_dir <dir>: the same two scans over a directory that is not a git tree (content, then names)
scan_dir() {
  ( cd "$1" && { grep -rIliE -e "$WORDS" lib 2>/dev/null; find lib -type f 2>/dev/null | grep -iE "$WORDS"; } | sort -u )
}
mkdir -p "$W/copy"
# shellcheck disable=SC2086
git ls-files -z $ROOTS | tar --null -T - -cf - | tar -xf - -C "$W/copy"
eq "the scanner reports nothing on an unplanted copy of the tracked files" "$(scan_dir "$W/copy")" ""
printf 'the Hermes spoke\n' > "$W/copy/lib/sync/planted.py"
printf 'echo hi\n' > "$W/copy/lib/board/notion_named.sh"
planted="$(scan_dir "$W/copy")"
case "$planted" in *planted.py*) ok "negative control: a file that names Hermes is reported" ;; *) bad "negative control: the planted word was not found (got '$planted')" ;; esac
case "$planted" in *notion_named.sh*) ok "negative control: a file named notion_named.sh is reported" ;; *) bad "negative control: the planted file name was not found (got '$planted')" ;; esac
mkdir -p "$W/copy2"
# shellcheck disable=SC2086
git ls-files -z $ROOTS | tar --null -T - -cf - | tar -xf - -C "$W/copy2"
printf 'Multica\n' >> "$W/copy2/lib/sync/sync_core.py"
case "$(scan_dir "$W/copy2")" in *sync_core.py*) ok "negative control: a word added to a core module is reported" ;; *) bad "negative control: a word added to sync_core.py was not found" ;; esac

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
