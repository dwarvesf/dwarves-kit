#!/usr/bin/env bash
# test-shared-lookups.sh -- the structural lint for the two shared lookups:
#   "which spec is active"   -> spec_active   (lib/spec/spec-active.sh)
#   "has this branch landed" -> branch_merged (lib/gate/branch-merged.sh)
# A caller that keeps or regains a private copy of either answer turns this suite red. The lint
# reads code only (hooks/, lib/, bin/; never tests, docs or data files, never the shared files
# themselves) and never a comment line. A hit passes only with a per-line marker that carries a
# reason: `spec-active-ok: <reason>` or `merged-ok: <reason>`. The marker list is PINNED below, so
# a new exemption needs an edit to this file, which is where a reviewer sees it.
# modules under test (the test-affected cache key greps this line):
# lib/spec/spec-active.sh lib/gate/branch-merged.sh
# Run: bash tests/test-shared-lookups.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars) 2>/dev/null
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-shared-lookups.XXXXXX")" || exit 1
trap 'rm -rf "$TMPD"' EXIT

PASS=0; FAIL=0
chk() { if [ "$2" -eq 0 ] 2>/dev/null; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }
eq() { if [ "$2" = "$3" ]; then chk "$1" 0; else echo "    want: $3"; echo "    got:  $2"; chk "$1" 1; fi; }

# ---------------------------------------------------------------------------- the patterns
# ACTIVE spec. A private way to enumerate or pick a spec:
#   ls/find ... docs/specs      a directory listing or walk of the spec tree
#   docs/specs/SPEC-*           a glob over spec files
#   spec_files() / spec_for_slug()   a redefinition of the shared resolver (the stale-install stubs)
#   */docs/specs/SPEC           a walk for co-located specs
# `ls`/`find` must be a word (not "ls-files", not "tools"); a find that only PRUNES docs/specs
# (`-path ".../docs/specs"`) is not a lookup and is skipped in scan().
PAT_ACTIVE='(^|[^[:alnum:]_-])(ls|find)[[:space:]][^#]*docs/specs|docs/specs/SPEC-\*|spec_files\(\)|spec_for_slug\(\)|\*/docs/specs/SPEC'
# MERGED check. A private meaning of "this branch has landed":
#   --state merged / mergedAt   a read of the merged-PR list or its merge time
#   git cherry / patch-id       patch equivalence against the default branch
#   --state all ... --head      the first PR gh lists for a head, any state
#   is-ancestor <x> origin/<d>  the merged direction (x reached the default branch); the up-to-date
#                               direction `is-ancestor origin/<d> HEAD` starts with origin/ and is not a hit
#   pr view ... state           a PR state read; a delete guarded on it would be a private merged check
PAT_MERGED='--state merged|mergedAt|git[^|]* cherry |patch-id|--state all[^|]*--head|--head[^|]*--state all|is-ancestor "?[^o" ][^ ]* "?(refs/remotes/)?origin/|pr view[^#]*state'

# scan <root> <ere> -- every code line under hooks/ lib/ bin/ of <root> that matches, as `file:line:text`.
# Skipped: tests, docs and data files, the shared files, comment-only lines, a find that prunes docs/specs.
scan() {
  ( cd "$1" && grep -rnIE -e "$2" hooks lib bin 2>/dev/null ) | awk -F: '
    $1 ~ /\/tests\// || $1 ~ /\.(md|html|tsv|json|py)$/ { next }
    $1 == "lib/gate/branch-merged.sh" || $1 == "lib/spec/spec-find.sh" || $1 == "lib/spec/spec-active.sh" { next }
    { rest = $0; sub(/^[^:]*:[0-9]+:/, "", rest)
      if (rest ~ /^[ \t]*#/) next
      if (rest ~ /-path "[^"]*docs\/specs"/) next
      print }'
}
# problems <root> -- unmarked hits, markers without a reason, markers on a line no pattern hits.
problems() {
  local root="$1" line kind
  for kind in active merged; do
    local pat marker
    if [ "$kind" = active ]; then pat="$PAT_ACTIVE"; marker='spec-active-ok:'; else pat="$PAT_MERGED"; marker='merged-ok:'; fi
    scan "$root" "$pat" | while IFS= read -r line; do
      case "$line" in
        *"$marker"*)
          # the reason is the text after the marker; it must hold a non-space character
          case "${line#*"$marker"}" in *[![:space:]]*) ;; *) echo "NO-REASON $kind ${line%%:*}:$(printf '%s' "$line" | cut -d: -f2)" ;; esac ;;
        *) echo "UNMARKED $kind ${line%%:*}:$(printf '%s' "$line" | cut -d: -f2)" ;;
      esac
    done
  done
  # a marker on a line that matches no pattern is a dead exemption
  for kind in spec-active-ok merged-ok; do
    ( cd "$root" && grep -rnIE -e "$kind:" hooks lib bin 2>/dev/null ) | awk -F: '$1 !~ /\/tests\// && $1 !~ /\.(md|html|tsv|json|py)$/ { print $1 ":" $2 }' | while IFS= read -r ref; do
      case "$kind" in
        spec-active-ok) scan "$root" "$PAT_ACTIVE" ;;
        merged-ok) scan "$root" "$PAT_MERGED" ;;
      esac | cut -d: -f1,2 | grep -qxF -- "$ref" || echo "DEAD-MARKER $kind $ref"
    done
  done
}
# marked <root> -- `kind file` for every marked hit, one line each, sorted.
marked() {
  scan "$1" "$PAT_ACTIVE" | grep -F 'spec-active-ok:' | cut -d: -f1 | sed 's/^/spec-active-ok /'
  scan "$1" "$PAT_MERGED" | grep -F 'merged-ok:' | cut -d: -f1 | sed 's/^/merged-ok /'
}

# ---------------------------------------------------------------------------- the pinned markers
# `kind file count`. A new marker, or a marker that moves to another file, is an edit here.
PINNED="merged-ok lib/config/merge-command.sh 1
merged-ok lib/mega/mega.sh 1
merged-ok lib/queue/orchestrate.sh 1
merged-ok lib/wrap/wrap-apply.sh 3
merged-ok lib/wrap/wrap-carry.sh 3
merged-ok lib/wrap/wrap-land.sh 1
merged-ok lib/wrap/wrap-merge.sh 6
spec-active-ok hooks/ship-gate.sh 1
spec-active-ok lib/gate/gate-ledger.sh 2
spec-active-ok lib/gate/proof-ledger.sh 2
spec-active-ok lib/pitch.sh 2
spec-active-ok lib/registry/feature-registry.sh 1
spec-active-ok lib/spec/spec-next.sh 3"

echo "=== the repository: no private copy, only the pinned markers ==="
P="$(problems "$KIT_DIR")"
eq "no unmarked hit, no marker without a reason, no dead marker" "$P" ""
GOT="$(marked "$KIT_DIR" | sort | uniq -c | awk '{ print $2 " " $3 " " $1 }')"
eq "the marked hits are exactly the pinned list" "$GOT" "$PINNED"

echo "=== each migrated caller names the shared function ==="
named() { grep -qE "$2" "$KIT_DIR/$1" 2>/dev/null; echo $?; }
for f in hooks/ship-gate.sh hooks/pre-compact-backup.sh hooks/post-compact-reinject.sh hooks/context-readiness.sh hooks/spec-drift-guard.sh; do
  chk "$f calls spec_active" "$(named "$f" 'spec_active|spec-active\.sh')"
done
chk "lib/spec/spec-index.sh lists through spec_files" "$(named lib/spec/spec-index.sh 'spec_files')"
for f in lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-land.sh lib/wrap/wrap-adopt.sh lib/wrap/wrap-carry.sh lib/goal/wt.sh; do
  chk "$f calls branch_merged" "$(named "$f" 'branch_merged')"
done

echo "=== the lint itself: a fixture tree holds one bad line per pattern ==="
FX="$TMPD/fx"; mkdir -p "$FX/hooks" "$FX/lib/gate" "$FX/lib/spec" "$FX/lib/x/tests" "$FX/bin"
cat > "$FX/hooks/bad-spec.sh" <<'EOF'
SPEC=$(ls docs/specs/SPEC-*.md | tail -1)
SPEC2=$(find . -path '*/docs/specs/SPEC-*.md' | head -1)
spec_for_slug() { echo private; }
EOF
cat > "$FX/lib/bad-merged.sh" <<'EOF'
st=$(gh pr view "$n" --json state -q .state)
gh pr list --state merged --json mergedAt
git cherry origin/main "$b"
git diff a b | git patch-id --stable
gh pr list --state all --head "$b" --json state
git merge-base --is-ancestor "$tip" "origin/main"
EOF
cat > "$FX/lib/clean.sh" <<'EOF'
# gh pr view "$n" --json state in a comment is not a hit
git ls-files 'docs/specs/*.md'
git merge-base --is-ancestor origin/main HEAD
find "$root/docs" -path "$root/docs/specs" -prune -o -print
EOF
echo 'ls docs/specs/SPEC-*.md' > "$FX/lib/x/tests/t.sh"        # a test file: ignored
echo 'ls docs/specs/SPEC-*.md' > "$FX/lib/spec/spec-active.sh" # the shared file: ignored
echo 'gh pr view 1 --json state # merged-ok: the PR this script just merged' > "$FX/lib/ok-marker.sh"
echo 'gh pr view 1 --json state # merged-ok:' > "$FX/lib/no-reason.sh"
echo 'x=1 # merged-ok: nothing here matches a pattern' > "$FX/lib/dead.sh"
FP="$(problems "$FX" | sort)"
WANT="DEAD-MARKER merged-ok lib/dead.sh:1
NO-REASON merged lib/no-reason.sh:1
UNMARKED active hooks/bad-spec.sh:1
UNMARKED active hooks/bad-spec.sh:2
UNMARKED active hooks/bad-spec.sh:3
UNMARKED merged lib/bad-merged.sh:1
UNMARKED merged lib/bad-merged.sh:2
UNMARKED merged lib/bad-merged.sh:3
UNMARKED merged lib/bad-merged.sh:4
UNMARKED merged lib/bad-merged.sh:5
UNMARKED merged lib/bad-merged.sh:6"
eq "every bad pattern, an empty reason and a dead marker are named; comments, tests, the shared file, ls-files, up-to-date and prune are not" "$FP" "$(printf '%s\n' "$WANT" | sort)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-shared-lookups: $PASS passed, $FAIL FAILED"; exit 1; fi
echo "test-shared-lookups: all $PASS passed"
