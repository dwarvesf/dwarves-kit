#!/usr/bin/env bash
# test-release-notes.sh - run release-notes.sh against fixture changelogs. No network. The tags
# come from the stamped list, so the cases hold for any list that has `dev` and one product tag.
# The script runs with python3 and jq absent from PATH. Leaves its temp dir behind; the path is
# printed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/release-notes.sh"
TAGS='{{TAGS}}'
T="$(mktemp -d "${TMPDIR:-/tmp}/release-notes-test.XXXXXX")"
echo "test dir: $T"

# P1 and P2: the first two product tags (P2 is P1 again when the list has only one)
P1=""
P2=""
oldifs="$IFS"
IFS=','
for t in $TAGS; do
    [ "$t" = dev ] && continue
    if [ -z "$P1" ]; then P1="$t"; elif [ -z "$P2" ]; then P2="$t"; fi
done
IFS="$oldifs"
[ -n "$P1" ] || { echo "test needs one product tag besides dev in: $TAGS"; exit 1; }
[ -n "$P2" ] || P2="$P1"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}
has() { grep -Fq -- "$2" "$T/$1"; }
lacks() { ! grep -Fq -- "$2" "$T/$1"; }
empty() { [ ! -s "$T/$1" ]; }
no_double_blank() { awk 'BEGIN { b = 0; bad = 0 } /^$/ { b++; if (b > 1) bad = 1; next } { b = 0 } END { exit bad }' "$T/$1"; }
first_line_is() { [ "$(awk 'NR == 1' "$T/$1")" = "$2" ]; }
last_line_not_blank() { [ -n "$(awk 'END { print }' "$T/$1")" ]; }
# pair <name>: stderr is exactly the two-line refusal
pair() {
    [ "$(wc -l <"$T/$1.err" | tr -d ' ')" -eq 2 ] \
        && awk 'NR == 1' "$T/$1.err" | grep -q '^release-notes: ' \
        && awk 'NR == 2' "$T/$1.err" | grep -q '^Fix: '
}

# run <name> <section> <changelog>: stdout in $T/<name>, stderr in $T/<name>.err, exit in $rc
run() {
    rc=0
    bash "$SCRIPT" "$2" "$3" >"$T/$1" 2>"$T/$1.err" || rc=$?
}

cat >"$T/mixed.md" <<EOF
# Changelog

## [Unreleased]

### Added

- $P1: A new weather card.
- dev: A CI job for the shell tests.
  It runs on every pull request.
- $P2: The second tag records what is live.

### Changed

- dev: The rules moved to a new file.
- dev: A hook blocks a bare merge.

### Fixed

- $P1: A job that panics now ends with a kind.
- $P2: The seal vectors gained a case.

## [0.2.0] - 2026-10-29

### Added

- Old entry without a tag.

[Unreleased]: https://example.invalid/compare/v0.2.0...HEAD
EOF

# 1. a mixed section
run mixed Unreleased "$T/mixed.md"
expect "mixed: exit 0" [ "$rc" -eq 0 ]
expect "mixed: keeps a first-tag line" has mixed "- $P1: A new weather card."
expect "mixed: keeps a second-tag line" has mixed "- $P2: The second tag records what is live."
expect "mixed: keeps the later lines" has mixed "- $P2: The seal vectors gained a case."
expect "mixed: drops a dev line" lacks mixed "- dev: A CI job"
expect "mixed: drops the continuation of a dev line" lacks mixed "It runs on every pull request."
expect "mixed: keeps the Added heading" has mixed "### Added"
expect "mixed: keeps the Fixed heading" has mixed "### Fixed"
expect "mixed: stops at the next version" lacks mixed "Old entry without a tag."
expect "mixed: no dev tag anywhere" lacks mixed "dev:"
expect "mixed: stderr empty" empty mixed.err

# 2. a heading whose entries are all dev goes away
expect "all-dev heading: dropped" lacks mixed "### Changed"
expect "all-dev heading: its lines dropped" lacks mixed "The rules moved"

# 3. clean edges and no blank-line run
expect "mixed: no double blank line" no_double_blank mixed
expect "mixed: starts with a heading" first_line_is mixed "### Added"
expect "mixed: no blank last line" last_line_not_blank mixed

# 4. only dev entries: refused
cat >"$T/onlydev.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- dev: A CI job for the shell tests.

### Changed

- dev: The rules moved to a new file.

## [0.2.0] - 2026-10-29

- Old.
EOF
run onlydev Unreleased "$T/onlydev.md"
expect "only dev: exit 1" [ "$rc" -eq 1 ]
expect "only dev: says nothing is left for a user" has onlydev.err "no entry for a user"
expect "only dev: rule then Fix" pair onlydev
expect "only dev: prints no notes" empty onlydev

# 5. an empty section is refused the same way
cat >"$T/empty.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.2.0] - 2026-10-29

- Old.
EOF
run empty Unreleased "$T/empty.md"
expect "empty section: exit 1" [ "$rc" -eq 1 ]
expect "empty section: rule then Fix" pair empty

# 6. an untagged entry: refused, names the line, lists the tags
cat >"$T/untagged.md" <<EOF
# Changelog

## [Unreleased]

### Added

- $P1: A tagged line.
- A line with no tag at all.
- dev: Another tagged line.
EOF
run untagged Unreleased "$T/untagged.md"
expect "untagged: exit 1" [ "$rc" -eq 1 ]
expect "untagged: names the line" has untagged.err "A line with no tag at all."
expect "untagged: lists the tags" has untagged.err "(${TAGS//,/, })"
expect "untagged: exactly the two-line refusal" pair untagged
expect "untagged: the Fix line names the tags" bash -c 'awk "NR == 2" "$1" | grep -Fq -- "$2"' _ "$T/untagged.err" "${TAGS//,/: }:"
expect "untagged: prints no notes" empty untagged

# 7. a wrong tag, a lookalike tag and a missing space are untagged
printf '## [Unreleased]\n\n- zz9: A tag that is not in the list.\n' >"$T/wrongtag.md"
run wrongtag Unreleased "$T/wrongtag.md"
expect "wrong tag: exit 1" [ "$rc" -eq 1 ]
printf '## [Unreleased]\n\n- %sx: A lookalike of a real tag.\n' "$P1" >"$T/lookalike.md"
run lookalike Unreleased "$T/lookalike.md"
expect "lookalike tag: exit 1" [ "$rc" -eq 1 ]
printf '## [Unreleased]\n\n- %s:No space after the colon.\n' "$P1" >"$T/nospace.md"
run nospace Unreleased "$T/nospace.md"
expect "no space after the colon: exit 1" [ "$rc" -eq 1 ]
printf '## [Unreleased]\n\n- %s:\n' "$P1" >"$T/bare.md"
run bare Unreleased "$T/bare.md"
expect "a tag with nothing after the colon is accepted" [ "$rc" -eq 0 ]

# 8. every stamped tag is accepted; dev alone is not enough
oldifs="$IFS"
IFS=','
for t in $TAGS; do
    printf '## [Unreleased]\n\n- %s: One line.\n- %s: Another.\n' "$t" "$P1" >"$T/each.md"
    run each Unreleased "$T/each.md"
    expect "tag $t: accepted" [ "$rc" -eq 0 ]
done
IFS="$oldifs"

# 9. a version section, with and without the v
cat >"$T/ver.md" <<EOF
# Changelog

## [Unreleased]

- $P1: Still waiting.

## [0.3.0] - 2026-11-20

### Added

- $P1: Shipped in 0.3.0.
- dev: A tooling line in 0.3.0.

## [0.2.0] - 2026-10-29

- Old.
EOF
run ver 0.3.0 "$T/ver.md"
expect "version: exit 0" [ "$rc" -eq 0 ]
expect "version: has its own entry" has ver "- $P1: Shipped in 0.3.0."
expect "version: drops its dev line" lacks ver "A tooling line in 0.3.0."
expect "version: leaves the Unreleased entry out" lacks ver "Still waiting."
run verv v0.3.0 "$T/ver.md"
expect "v-prefixed version: exit 0" [ "$rc" -eq 0 ]
expect "v-prefixed version: same notes" cmp -s "$T/ver" "$T/verv"
run dotty 0x3y0 "$T/ver.md"
expect "a dot in the version is not a wildcard" [ "$rc" -eq 1 ]

# 10. a missing version and a missing file
run missing 9.9.9 "$T/ver.md"
expect "missing version: exit 1" [ "$rc" -eq 1 ]
expect "missing version: names it" has missing.err "no '## [9.9.9]' section"
expect "missing version: rule then Fix" pair missing
run nofile Unreleased "$T/does-not-exist.md"
expect "missing file: exit 1" [ "$rc" -eq 1 ]
expect "missing file: rule then Fix" pair nofile

# 11. usage
rc=0
bash "$SCRIPT" >"$T/noargs" 2>"$T/noargs.err" || rc=$?
expect "no arguments: exit 2" [ "$rc" -eq 2 ]
expect "no arguments: rule then Fix" pair noargs
rc=0
bash "$SCRIPT" a b c >"$T/threeargs" 2>"$T/threeargs.err" || rc=$?
expect "three arguments: exit 2" [ "$rc" -eq 2 ]
expect "three arguments: rule then Fix" pair threeargs
rc=0
bash "$SCRIPT" --help >"$T/help" 2>/dev/null || rc=$?
expect "--help: exit 0 and a usage line" bash -c '[ "$1" -eq 0 ] && grep -q "^Usage: " "$2"' _ "$rc" "$T/help"

# 12. CRLF line ends, and the default changelog path next to the script
sed 's/$/\r/' "$T/mixed.md" >"$T/crlf.md"
run crlf Unreleased "$T/crlf.md"
expect "CRLF changelog: exit 0" [ "$rc" -eq 0 ]
expect "CRLF changelog: keeps the first-tag line" has crlf "- $P1: A new weather card."
mkdir -p "$T/repo/scripts"
cp "$SCRIPT" "$T/repo/scripts/release-notes.sh"
cp "$T/mixed.md" "$T/repo/CHANGELOG.md"
rc=0
(cd "$T/repo" && bash scripts/release-notes.sh Unreleased) >"$T/default" 2>/dev/null || rc=$?
expect "default path: reads CHANGELOG.md at the repo root" [ "$rc" -eq 0 ]
expect "default path: same notes as the explicit path" cmp -s "$T/default" "$T/mixed"
rc=0
(cd "$T/repo/scripts" && bash release-notes.sh Unreleased) >"$T/default2" 2>/dev/null || rc=$?
expect "default path: also from inside scripts/" [ "$rc" -eq 0 ]

# 13. python3 and jq absent from PATH
mkdir -p "$T/nopy"
for tool in bash awk; do
    p="$(command -v "$tool")"
    ln -sf "$p" "$T/nopy/$tool"
done
expect "the stripped PATH holds no python3 and no jq" bash -c '! PATH="$1" command -v python3 && ! PATH="$1" command -v jq' _ "$T/nopy"
rc=0
PATH="$T/nopy" "$T/nopy/bash" "$SCRIPT" Unreleased "$T/mixed.md" >"$T/nopy.out" 2>"$T/nopy.err" || rc=$?
expect "no python3 on PATH: exit 0" [ "$rc" -eq 0 ]
expect "no python3 on PATH: same notes" cmp -s "$T/nopy.out" "$T/mixed"
rc=0
PATH="$T/nopy" "$T/nopy/bash" "$SCRIPT" Unreleased "$T/untagged.md" >"$T/nopy2.out" 2>"$T/nopy2.err" || rc=$?
expect "no python3 on PATH: the refusal still fires" bash -c '[ "$1" -eq 1 ] && grep -q "^Fix: " "$2"' _ "$rc" "$T/nopy2.err"

echo "failures: $fails"
[ "$fails" -eq 0 ]
