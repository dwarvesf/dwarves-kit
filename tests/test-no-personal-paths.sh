#!/usr/bin/env bash
# test-no-personal-paths.sh -- the kit ships no operator-specific path or hostname,
# and adopt renders none into a consumer repo.
#
# Two halves:
#   1. RENDER: adopt into a throwaway repo, assert no `/Users/` string lands in any
#      file adopt wrote. lib/adopt.sh resolves KIT_ROOT to this machine's absolute
#      install path, so a template that interpolates it bakes the operator's home
#      into another repo's committed docs. KIT_REF is the portable form.
#   2. TREE: no operator path or hostname anywhere in the checkout. The kit is a
#      public repo, so a personal path is both a leak and a broken instruction for
#      every other reader.
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

# ---------------------------------------------------------------- 1. RENDER
# Pin KIT_ROOT to a sentinel instead of trusting this machine's own install path:
# the assertion then holds wherever the suite runs, and a template that interpolates
# KIT_ROOT shows up as the sentinel rather than as a home that happens to look benign.
SENTINEL="/opt/kit-root-sentinel"
T="$(mktemp -d)"; git -C "$T" init -q
CLAUDE_PLUGIN_ROOT="$SENTINEL" bash lib/adopt.sh "$T" >/dev/null 2>&1
RENDERED="$(grep -rl -e "$SENTINEL" -e '/Users/' "$T" --exclude-dir=.git 2>/dev/null)"
if [ -z "$RENDERED" ]; then
  ok "adopt renders no render-time install path into the consumer repo"
else
  no "adopt baked the install path into: $(echo "$RENDERED" | tr '\n' ' ')"
fi

# The rendered kit references must still be resolvable, not merely home-free: a
# consumer shell expands ~ / $HOME itself, so both forms are portable and either
# one satisfies this check.
if grep -rq 'dwarves-kit' "$T/CLAUDE.md" "$T/docs/verification/README.md" 2>/dev/null; then
  ok "rendered files still point at the kit (portable ~ or \$HOME form)"
else
  no "rendered files lost their kit reference"
fi

# --------------------------------------------------------------- 2. TREE
# These three files quote the patterns as data: two leak-guard tests and this guard's
# own proof, whose negative-control transcript has to show the string it caught. Skip
# them by name; matching the pattern is their job, not a leak.
SELF="tests/test-no-personal-paths.sh"
GUARD="tests/test-kit-foldin-hooks.sh"
PROOF="docs/verification/no-personal-paths.md"

OWNER="tieu""bao"   # split so this file is not itself a hit in a plain tree grep

# Enumerate via `git ls-files`, not a recursive walk: it is exactly the set that
# ships. A walk both misses force-tracked files that .gitignore also names (kit.toml
# is one, which is why ripgrep skipped a real leak there) and drags in local build
# noise like __pycache__. -I skips binaries so a stale .pyc cannot fail the run.
LEAKS="$(git ls-files -z \
  | xargs -0 grep -IHn -F -e "/Users/$OWNER" -e "workspace/$OWNER" -e "Hans-Air" \
      -e "mini-$OWNER" 2>/dev/null \
  | grep -v -e "^$SELF:" -e "^$GUARD:" -e "^$PROOF:")"
if [ -z "$LEAKS" ]; then
  ok "no operator path or hostname anywhere in the tree"
else
  no "operator path/hostname still present:"
  echo "$LEAKS" | head -20
fi

echo ""
echo "Passed: $PASS / $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || { echo "$FAIL test(s) failed."; exit 1; }
echo "All no-personal-paths tests passed."
