#!/usr/bin/env bash
# test-ship-gate-spec-pick.sh -- the spec pick in hooks/ship-gate.sh, run on its own. The hunk that
# resolves SPEC for the slug is cut out of the real hook (from `SPEC=""` to the line before the
# build-ran advisory) and run against three plugin roots: a full install, one that has spec-find.sh
# but no spec-active.sh (a partial update), and one with neither (a stale install). Each must still
# pick the spec, in the order spec-active.sh, spec-find.sh, the root glob; and a repo path that holds
# a TAB must survive the pick.
# modules under test (the test-affected cache key greps this line):
# hooks/ship-gate.sh lib/spec/spec-active.sh lib/spec/spec-find.sh
# Run: bash tests/test-ship-gate-spec-pick.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars) 2>/dev/null
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-spec-pick.XXXXXX")" || exit 1
TMPD="$(cd "$TMPD" && pwd -P)"
trap 'rm -rf "$TMPD"' EXIT
export HOME="$TMPD/home"; mkdir -p "$HOME"

PASS=0; FAIL=0
chk() { if [ "$2" -eq 0 ] 2>/dev/null; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }
eq() { if [ "$2" = "$3" ]; then chk "$1" 0; else echo "    want: $3"; echo "    got:  $2"; chk "$1" 1; fi; }

# The hunk, cut from the hook between its anchors.
HUNK="$TMPD/hunk.sh"
awk '/^SPEC=""$/ && !on { on = 1 } /^# Build-ran advisory/ { on = 0 } on' "$KIT_DIR/hooks/ship-gate.sh" > "$HUNK"
chk "the hook hunk was found" "$([ "$(wc -l < "$HUNK")" -ge 4 ]; echo $?)"

# plugin roots
mkroot() { # mkroot <name> <files...>
  local d="$TMPD/plugin-$1" f; shift; mkdir -p "$d/lib/spec"
  for f in "$@"; do cp "$KIT_DIR/lib/spec/$f" "$d/lib/spec/$f"; done
  printf '%s\n' "$d"
}
FULL="$(mkroot full spec-find.sh spec-active.sh spec-status.sh states.tsv)"
PART="$(mkroot partial spec-find.sh)"
NONE="$(mkroot none)"

# repos
mkrepo() { # mkrepo <dir> -- a root spec for slug foo and a co-located one for slug delta
  mkdir -p "$1/docs/specs" "$1/tools/x/docs/specs"
  printf '# foo\nStatus: DRAFT\n' > "$1/docs/specs/SPEC-001-foo.md"
  printf '# delta\nStatus: DRAFT\n' > "$1/tools/x/docs/specs/SPEC-005-delta.md"
}
R="$TMPD/repo"; mkrepo "$R"
RT="$TMPD/repo$(printf '\t')tab"; mkrepo "$RT"

pick() { # pick <plugin root> <repo> <slug> -- what the hook hunk leaves in SPEC
  bash -c 'ROOT="$2"; SLUG="$3"; export CLAUDE_PLUGIN_ROOT="$1"; . "$4"; printf "%s" "$SPEC"' _ "$1" "$2" "$3" "$HUNK" 2>/dev/null
}

echo "=== a full install: spec-active.sh answers ==="
eq "root spec"                  "$(pick "$FULL" "$R" foo)"   "$R/docs/specs/SPEC-001-foo.md"
eq "co-located spec"            "$(pick "$FULL" "$R" delta)" "$R/tools/x/docs/specs/SPEC-005-delta.md"
eq "no spec for the slug"       "$(pick "$FULL" "$R" nope)"  ""
eq "a root path holding a TAB survives the pick" "$(pick "$FULL" "$RT" foo)" "$RT/docs/specs/SPEC-001-foo.md"

echo "=== a partial install: spec-find.sh without spec-active.sh ==="
eq "root spec"                  "$(pick "$PART" "$R" foo)"   "$R/docs/specs/SPEC-001-foo.md"
eq "co-located spec is still found (the pick master makes)" "$(pick "$PART" "$R" delta)" "$R/tools/x/docs/specs/SPEC-005-delta.md"
eq "a root path holding a TAB survives the pick" "$(pick "$PART" "$RT" foo)" "$RT/docs/specs/SPEC-001-foo.md"

echo "=== a stale install: neither file, the root glob ==="
eq "root spec"                  "$(pick "$NONE" "$R" foo)"   "$R/docs/specs/SPEC-001-foo.md"
eq "no spec for the slug"       "$(pick "$NONE" "$R" nope)"  ""

echo
if [ "$FAIL" -gt 0 ]; then echo "test-ship-gate-spec-pick: $PASS passed, $FAIL FAILED"; exit 1; fi
echo "test-ship-gate-spec-pick: all $PASS passed"
