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
# Strip PATH down to no `gh`: a per-host directory-CONTENT filter (does this dir have a
# `gh` in it) is still wrong on Linux, because ubuntu runners ship `gh` in /usr/bin right
# beside `bash` itself, so dropping that whole directory left the fenced PATH with no
# `bash` to exec ("bash: command not found", CI-only, since /usr/bin/gh and /usr/bin/bash
# do not coexist that way on a Mac). Build the fence as a plain directory of symlinks
# instead: resolve each needed command via the RUNNING host's own `command -v` (so it is
# /bin/bash on macOS and /usr/bin/bash on Linux, whichever this box actually has) and
# symlink it in; `gh` is deliberately never one of the resolved names, so it cannot leak
# in by any path.
FENCE="$(mktemp -d "${TMPDIR:-/tmp}/kit-no-gh.XXXXXX")"
for _name in bash sh git sed grep sort uniq awk head tail cat mktemp ls dirname basename \
             tr cut wc env printf date mkdir mv rm rmdir sleep stat ln chmod; do
  _resolved="$(command -v "$_name" 2>/dev/null)"
  [ -n "$_resolved" ] && ln -sf "$_resolved" "$FENCE/$_name"
done
NOGH_PATH="$FENCE"
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
