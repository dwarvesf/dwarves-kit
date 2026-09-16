#!/usr/bin/env bash
# test-spec-next-pr-scan.sh -- spec-next mints against open PR heads, not only the local scan.
#
# Three parallel workers each got SPEC-289 from spec-next because it only scanned docs/specs/,
# local branches, and commit subjects: none of those surfaces show a number an OPEN PR is
# already holding. This proves the added `gh`-backed scan folds an open PR's docs/specs/
# listing into the max, degrades cleanly without `gh`, and is skippable for hermetic tests via
# SPEC_NEXT_NO_PR_SCAN=1.
#
# Run: bash tests/test-spec-next-pr-scan.sh
# Exit 0 = all pass. Exit 1 = failures.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SN="$KIT_DIR/lib/spec/spec-next.sh"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0; TOTAL=0
ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} $1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
expect() { if { trap '' PIPE; printf '%s' "$3" 2>/dev/null || :; } | grep -q "$2"; then ok "$1"; else bad "$1 (missing '$2' in: $3)"; fi; }

# A temp git repo whose only local spec is SPEC-0449 (local max, before the PR scan).
mk_repo() {
  local r; r="$(mktemp -d "${TMPDIR:-/tmp}/kit-spec-next-pr.XXXXXX")"
  git -C "$r" init -q; git -C "$r" config user.email t@t.t; git -C "$r" config user.name t
  mkdir -p "$r/docs/specs"; : > "$r/docs/specs/SPEC-0449-x.md"
  git -C "$r" add -A; git -C "$r" commit -qm init >/dev/null 2>&1
  printf '%s\n' "$r"
}

# A stub `gh` on PATH. $1 selects behavior: "ok" (one open PR holding SPEC-0450) or "fail"
# (auth fails, as if `gh` is present but not logged in).
mk_stub_gh() {
  local mode="$1" bin; bin="$(mktemp -d "${TMPDIR:-/tmp}/kit-stub-gh.XXXXXX")"
  cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
mode="$mode"
case "\$1 \$2" in
  "auth status")
    [ "\$mode" = "ok" ] && exit 0 || exit 1 ;;
esac
case "\$*" in
  *"repo view"*) echo "acme/widgets" ;;
  *"pr list"*)   echo "feat/pr-1" ;;
  *"contents/docs/specs"*) echo "SPEC-0450-x.md" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$bin/gh"
  printf '%s\n' "$bin"
}

# ============================================================
echo "=== T1: gh present + authed, one open PR holds SPEC-0450 -> next folds it in ==="
# ============================================================
R="$(mk_repo)"; STUB="$(mk_stub_gh ok)"
OUT="$(cd "$R" && PATH="$STUB:$PATH" bash "$SN" next 2>/dev/null)"
eq "T1 next is 451 (local max 449, PR head holds 450)" "$OUT" "451"

# ============================================================
echo "=== T2: gh present but NOT authenticated -> local-only fallback + stderr note ==="
# ============================================================
R="$(mk_repo)"; STUB="$(mk_stub_gh fail)"
OUT2="$(cd "$R" && PATH="$STUB:$PATH" bash "$SN" next 2>/dev/null)"
ERR2="$(cd "$R" && PATH="$STUB:$PATH" bash "$SN" next 2>&1 >/dev/null)"
eq "T2 next falls back to local max+1 (450)" "$OUT2" "450"
expect "T2 stderr carries the not-scanned note" "spec-next: open PR heads not scanned" "$ERR2"

# ============================================================
echo "=== T3: SPEC_NEXT_NO_PR_SCAN=1 skips the scan even with a working gh stub ==="
# ============================================================
R="$(mk_repo)"; STUB="$(mk_stub_gh ok)"
OUT3="$(cd "$R" && SPEC_NEXT_NO_PR_SCAN=1 PATH="$STUB:$PATH" bash "$SN" next 2>/dev/null)"
ERR3="$(cd "$R" && SPEC_NEXT_NO_PR_SCAN=1 PATH="$STUB:$PATH" bash "$SN" next 2>&1 >/dev/null)"
eq "T3 opt-out ignores the PR head (local max+1 = 450)" "$OUT3" "450"
expect "T3 stderr names the opt-out reason" "SPEC_NEXT_NO_PR_SCAN=1" "$ERR3"

# ============================================================
echo "=== T4: no gh on PATH at all -> local-only fallback + stderr note ==="
# ============================================================
R="$(mk_repo)"
# Strip PATH down to no `gh`: symlink only `git` (whatever binary it really resolves to,
# alias or not) into an isolated bin dir, then keep every OTHER dir from the real PATH
# EXCEPT any dir that itself holds a `gh` executable. A hardcoded /usr/bin:/bin fallback
# is not portable: on a GitHub-hosted ubuntu runner `gh` lives in /usr/bin right next to
# coreutils, so that fallback silently let `gh` back onto PATH and T4 ran the WRONG branch
# (mistaken for "not authenticated" instead of "not on PATH") on CI while passing locally,
# where gh happens to live in a Homebrew dir already excluded. Filtering by dir CONTENT
# (does this dir have a `gh` in it), not by a fixed dir LIST, is correct on both.
NOGH_BIN="$(mktemp -d "${TMPDIR:-/tmp}/kit-no-gh.XXXXXX")"
REAL_GIT="$(bash -c 'command -v git' 2>/dev/null)"
[ -n "$REAL_GIT" ] && ln -sf "$REAL_GIT" "$NOGH_BIN/git"
FILTERED=""
IFS=':' read -ra _path_dirs <<< "$PATH"
for _d in "${_path_dirs[@]}"; do
  [ -n "$_d" ] || continue
  [ -x "$_d/gh" ] && continue
  FILTERED="${FILTERED:+$FILTERED:}$_d"
done
NOGH_PATH="$NOGH_BIN:$FILTERED"
if PATH="$NOGH_PATH" command -v gh >/dev/null 2>&1; then
  bad "T4 setup: gh is still reachable on the built PATH (test would run the wrong branch)"
else
  ok "T4 setup: gh is provably absent from the built PATH"
fi
OUT4="$(cd "$R" && PATH="$NOGH_PATH" bash "$SN" next 2>/dev/null)"
ERR4="$(cd "$R" && PATH="$NOGH_PATH" bash "$SN" next 2>&1 >/dev/null)"
eq "T4 next falls back to local max+1 (450) with no gh" "$OUT4" "450"
expect "T4 stderr says gh not on PATH" "gh not on PATH" "$ERR4"

# ============================================================
echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASS${NC} / $TOTAL"
if [ "$FAIL" -gt 0 ]; then echo -e "${RED}$FAIL assertions failed.${NC}"; exit 1; fi
echo -e "${GREEN}spec-next-pr-scan green.${NC}"
