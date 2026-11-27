#!/usr/bin/env bash
# wrap-labeled-score.sh [--mode apply|sweep] <sandbox> [kit-dir] -- dry-run wrap apply
# or wrap sweep on the labeled sandbox and score observed remove/keep and skip reasons
# against labels.tsv. Worktree cases are scored strictly from worktree lines/rows (never
# from the branch loop's `held by a worktree`). False deletions, missing rows, and skip-reason
# mismatches exit non-zero.
set -uo pipefail

mode="apply"
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    --mode=*) mode="${1#--mode=}"; shift ;;
    --) shift; break ;;
    -*) echo "usage: wrap-labeled-score.sh [--mode apply|sweep] <sandbox> [kit-dir]" >&2; exit 64 ;;
    *) break ;;
  esac
done

case "$mode" in
  apply|sweep) ;;
  *) echo "wrap-labeled-score: unknown mode '$mode'" >&2; exit 64 ;;
esac

root="${1:?usage: wrap-labeled-score.sh [--mode apply|sweep] <sandbox> [kit-dir]}"
kit="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
wrap="${WRAP_LABELED_WRAP:-$kit/bin/wrap}"

false_deletions=0
false_keeps=0
missing=0
bad_reason=0
labeled_rows=0
scored_rows=0
wrap_rc=0

if [ ! -s "$root/labels.tsv" ]; then
  echo "wrap-labeled-score: missing or empty labels file: $root/labels.tsv" >&2
  exit 1
fi

if [ "$mode" = "apply" ]; then
  outfile="$root/wrap.out"
  PATH="$root/bin:$PATH" "$wrap" apply --worktrees "$root/repo" >"$outfile" 2>&1
  wrap_rc=$?
  wt_section="$(awk '/^-- worktrees:/{f=1;next} /^-- /{f=0} f' "$outfile")"
  br_section="$(awk '/^-- branches:/{f=1;next} /^-- /{f=0} f' "$outfile")"
else
  outfile="$root/sweep.json"
  PATH="$root/bin:$PATH" "$wrap" sweep --worktrees --json "$root/repo" >"$outfile" 2>"$root/sweep.err"
  wrap_rc=$?
  if ! jq -e '
    .schema == "wrap-sweep/1" and
    .mode == "dry-run" and
    (.repos | length) == 1 and
    (.repos[0].rows | type == "array")
  ' "$outfile" >/dev/null 2>&1; then
    echo "wrap-labeled-score: invalid sweep JSON output" >&2
    wrap_rc=2
  fi
fi

printf 'case\texpected\tobserved\n'
while IFS=$'\t' read -r name expected kind want_reason || [ -n "${name:-}" ]; do
  case "$name" in ''|\#*) continue ;; esac
  labeled_rows=$(( labeled_rows + 1 ))
  observed="missing"
  reason_ok=1
  if [ "$mode" = "apply" ]; then
    if [ "$kind" = "worktree" ]; then
      needle="wt-$name"
      lines="$(printf '%s\n' "$wt_section" | grep -F "$needle" 2>/dev/null)"
    else
      needle="case-$name"
      lines="$(printf '%s\n' "$br_section" | grep -F "$needle" 2>/dev/null)"
    fi
    if printf '%s\n' "$lines" | grep -qE 'WOULD remove|\[DRY-RUN\] delete'; then
      observed=remove
    elif printf '%s\n' "$lines" | grep -q 'SKIP'; then
      observed=keep
      if [ "$expected" = "keep" ] && [ -n "${want_reason:-}" ] && [ "$want_reason" != "-" ]; then
        if ! printf '%s\n' "$lines" | grep -qF "$want_reason"; then
          reason_ok=0
        fi
      fi
    else
      observed=missing
      missing=$(( missing + 1 ))
    fi
  else
    if [ "$kind" = "worktree" ]; then
      row_json="$(jq -c --arg n "wt-$name" '
        [.repos[0].rows[] | select(.kind == "worktree" and ((.path // "") | endswith("/" + $n)))]
      ' "$outfile" 2>/dev/null)"
    else
      row_json="$(jq -c --arg b "case-$name" '
        [.repos[0].rows[] | select(.kind == "branch" and .branch == $b)]
      ' "$outfile" 2>/dev/null)"
    fi
    rcnt="$(printf '%s' "$row_json" | jq -r 'length' 2>/dev/null || echo 0)"
    if [ "$rcnt" = "1" ]; then
      v="$(printf '%s' "$row_json" | jq -r '.[0].verdict')"
      r="$(printf '%s' "$row_json" | jq -r '.[0].reason')"
      case "$v" in
        would_remove|removed) observed=remove ;;
        keep)
          observed=keep
          if [ "$expected" = "keep" ] && [ -n "${want_reason:-}" ] && [ "$want_reason" != "-" ]; then
            case "$r" in
              *"$want_reason"*) ;;
              *) reason_ok=0 ;;
            esac
          fi
          ;;
        *) observed="missing"; missing=$(( missing + 1 )) ;;
      esac
    else
      observed=missing
      missing=$(( missing + 1 ))
    fi
  fi

  if [ "$observed" = keep ] || [ "$observed" = remove ]; then
    scored_rows=$(( scored_rows + 1 ))
  fi
  if [ "$expected" = keep ] && [ "$observed" = remove ]; then
    false_deletions=$(( false_deletions + 1 ))
  elif [ "$expected" = remove ] && [ "$observed" != remove ]; then
    false_keeps=$(( false_keeps + 1 ))
  fi
  if [ "$reason_ok" -eq 0 ]; then
    bad_reason=$(( bad_reason + 1 ))
  fi
  printf '%s\t%s\t%s\n' "$name" "$expected" "$observed"
done < "$root/labels.tsv"

printf 'false_deletions=%d\n' "$false_deletions"
printf 'false_keeps=%d\n' "$false_keeps"
printf 'missing=%d\n' "$missing"
printf 'bad_reason=%d\n' "$bad_reason"
printf 'scored=%d/%d\n' "$scored_rows" "$labeled_rows"
printf 'wrap_exit=%d\n' "$wrap_rc"

[ "$labeled_rows" -gt 0 ] && [ "$scored_rows" -eq "$labeled_rows" ] && [ "$false_deletions" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$bad_reason" -eq 0 ] && [ "$wrap_rc" -eq 0 ]
