#!/usr/bin/env bash
# test-mktemp-template-guard.sh -- no bare `mktemp` in the kit's scripts and tests.
#
# macOS `mktemp` with no template, and `mktemp -t name`, build the path from the per-user
# /var/folders dir and ignore $TMPDIR. Inside a sandbox that denies /var/folders (the
# incident-fix host lane runs the suite under Seatbelt with $TMPDIR as the only writable
# scratch dir) the call fails and the substitution comes back EMPTY. A suite then ran its
# fixture setup in the current directory: 158 suites went red, and a leaked fixture landed
# in a real clone. The fix is one rule: every mktemp names an explicit template,
#   mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX"
# and a test that cds into or builds a repo from the result stops when it is empty.
#
# Rules, checked over tracked files under tests/, lib/, bin/, hooks/, deploy/ and the
# top-level scripts (docs, markdown, json and html are skipped; comment lines are skipped):
#   R1  no `mktemp` / `mktemp -d` / `mktemp -u` without a template, and no `mktemp -t`.
#   R2  tests: `cd "$(mktemp ...)"` is forbidden (cd to an empty string succeeds in place).
#   R3  tests: `VAR=$(mktemp ...)` carries `|| exit 1`, `|| return 1` or `|| VAR=""` (a caller that then tests it) on the same line.
# A line that must break R3 on purpose carries `# mktemp-ok: <reason>`.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
pass() { echo "  PASS $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $1" >&2; FAIL=$((FAIL+1)); }

# Word start: not preceded by a letter, digit, underscore or hyphen (so `test-mktemp` and
# prose such as `for t in ... mktemp readlink` do not count; a following word is not a call).
LEAD='(^|[^[:alnum:]_.-])'
BARE_RE="${LEAD}mktemp( +-[du])?( +2>[^ ]+)? *(\\)|\`|;|\\||&|\\}|\$| #)"
TFLAG_RE="${LEAD}mktemp( +-d)? +-t( |\$)"
CD_RE="cd +\"?\\\$\\(mktemp"
ASSIGN_RE="[A-Za-z_][A-Za-z_0-9]*=\"?\\\$\\(mktemp"

# scan <root> <list-file>: print "file:line: text" for each violation.
scan() {
  local root="$1" list="$2" f in_test n line
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    in_test=0
    case "$f" in tests/*|*/tests/*) in_test=1 ;; esac
    grep -nE 'mktemp' "$root/$f" 2>/dev/null | while IFS= read -r hit; do
      n="${hit%%:*}"; line="${hit#*:}"
      case "$line" in *[![:space:]]*) ;; *) continue ;; esac
      line="${line#"${line%%[![:space:]]*}"}"
      case "$line" in '#'*) continue ;; esac
      if printf '%s\n' "$line" | grep -qE "$BARE_RE" || printf '%s\n' "$line" | grep -qE "$TFLAG_RE"; then
        echo "R1 $f:$n: $line"; continue
      fi
      [ "$in_test" = 1 ] || continue
      case "$line" in *'mktemp-ok:'*) continue ;; esac
      if printf '%s\n' "$line" | grep -qE "$CD_RE"; then
        echo "R2 $f:$n: $line"; continue
      fi
      if printf '%s\n' "$line" | grep -qE "$ASSIGN_RE" && ! printf '%s\n' "$line" | grep -qE '\|\| *(exit|return|die|[A-Za-z_]+=)'; then
        echo "R3 $f:$n: $line"
      fi
    done
  done < "$list"
}

tracked_list() {
  git -C "$KIT_DIR" ls-files -z | tr '\0' '\n' \
    | grep -vE '^(docs|examples)/|\.(md|json|jsonl|html)$' \
    | grep -vE '^tests/test-mktemp-template-guard\.sh$' \
    | grep -E '^(tests|lib|bin|hooks|deploy)/|^[^/]+\.sh$'
}

echo "=== G1: the live tree has no bare mktemp and no unguarded test use ==="
LIST="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
FX="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$LIST" "$FX"' EXIT
tracked_list > "$LIST"
[ -s "$LIST" ] && pass "scanned $(wc -l < "$LIST" | tr -d ' ') files" || fail "no files to scan"
OUT="$(scan "$KIT_DIR" "$LIST")"
if [ -z "$OUT" ]; then pass "no violations"; else fail "violations:"; printf '%s\n' "$OUT" >&2; fi

echo "=== G2: negative control, each rule fires on a planted line ==="
mkdir -p "$FX/tests"
{
  echo 'd=$(mktemp -d)'
  echo 'f=$(mktemp)'
  echo 'g=$(mktemp -t name.XXXXXX)'
  echo 'h=$(mktemp -d -t name.XXXXXX)'
  echo 'u=$(mktemp -u)'
  echo 'x=$(mktemp 2>/dev/null)'
} > "$FX/lib-bad.sh"
{
  echo 'cd "$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")"'
  echo 'd="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")"'
} > "$FX/tests/test-bad.sh"
printf 'lib-bad.sh\ntests/test-bad.sh\n' > "$FX/list"
PLANT="$(scan "$FX" "$FX/list")"
for want in 'R1 lib-bad.sh:1:' 'R1 lib-bad.sh:2:' 'R1 lib-bad.sh:3:' 'R1 lib-bad.sh:4:' 'R1 lib-bad.sh:5:' 'R1 lib-bad.sh:6:' 'R2 tests/test-bad.sh:1:' 'R3 tests/test-bad.sh:2:'; do
  if printf '%s\n' "$PLANT" | grep -qF "$want"; then pass "caught ${want% *} ${want#* }"; else fail "missed $want"; fi
done

echo "=== G3: the accepted forms stay clean ==="
{
  echo 'd="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1'
  echo 'f="$(mktemp "$dir/x.XXXXXX" 2>/dev/null)" || f=""'
  echo '# mktemp -d in a comment is fine'
  echo 'for t in bash mktemp readlink; do :; done'
  echo 'echo "uses mktemp for scratch"'
  echo 'cd "$d"; x=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")   # mktemp-ok: probes the failure path'
} > "$FX/tests/test-good.sh"
printf 'tests/test-good.sh\n' > "$FX/list"
GOOD="$(scan "$FX" "$FX/list")"
if [ -z "$GOOD" ]; then pass "accepted forms produce no violation"; else fail "false positive:"; printf '%s\n' "$GOOD" >&2; fi

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
