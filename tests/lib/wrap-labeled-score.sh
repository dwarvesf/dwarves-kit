#!/usr/bin/env bash
# wrap-labeled-score.sh <sandbox> [kit-dir] -- dry-run wrap apply on the labeled
# sandbox and score observed remove/keep against labels.tsv. The raw wrap output is
# kept at <sandbox>/wrap.out. False deletions and missing rows exit non-zero; false
# keeps are printed as the baseline this fixture exists to measure.
set -uo pipefail

root="${1:?usage: wrap-labeled-score.sh <sandbox> [kit-dir]}"
kit="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
wrap="${WRAP_LABELED_WRAP:-$kit/bin/wrap}"
outfile="$root/wrap.out"

PATH="$root/bin:$PATH" "$wrap" apply --worktrees "$root/repo" >"$outfile" 2>&1
wrap_rc=$?

false_deletions=0
false_keeps=0
missing=0
printf 'case\texpected\tobserved\n'
while IFS=$'\t' read -r name expected; do
  case "$name" in ''|\#*) continue ;; esac
  case "$name" in
    detached-head|protected-*) needle="wt-$name" ;;
    *) needle="case-$name" ;;
  esac
  lines="$(grep -F "$needle" "$outfile" 2>/dev/null)"
  if printf '%s\n' "$lines" | grep -qE 'WOULD remove|\[DRY-RUN\] delete'; then
    observed=remove
  elif printf '%s\n' "$lines" | grep -q 'SKIP'; then
    observed=keep
  else
    observed=missing
    missing=$(( missing + 1 ))
  fi
  if [ "$expected" = keep ] && [ "$observed" = remove ]; then
    false_deletions=$(( false_deletions + 1 ))
  elif [ "$expected" = remove ] && [ "$observed" != remove ]; then
    false_keeps=$(( false_keeps + 1 ))
  fi
  printf '%s\t%s\t%s\n' "$name" "$expected" "$observed"
done < "$root/labels.tsv"

printf 'false_deletions=%d\n' "$false_deletions"
printf 'false_keeps=%d\n' "$false_keeps"
printf 'missing=%d\n' "$missing"
printf 'wrap_exit=%d\n' "$wrap_rc"

[ "$false_deletions" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$wrap_rc" -eq 0 ]
