#!/usr/bin/env bash
# lens-eval.sh -- treatment-vs-control eval for a prompt-only lens (a command or agent
# whose behavior is reviewer text, not code).
#
# Treatment is the working-tree text of <command-file>; control is the same path at
# <base-ref>. Each case's fixture spec runs through headless `claude -p` under each arm the
# case's signals name, N samples per arm. A sample hits a signal when one finding block
# (a list item, table row, or paragraph plus its indented lines, outside any Passed section)
# matches `pattern` (and `reviewer`). An arm hits when a majority of its samples hit. A
# `control: fewer` expectation passes when control has fewer hits than treatment. Prints a
# markdown table, the saved-samples dir, the cost, and one verdict line.
#
# Usage: lens-eval.sh <command-file> <base-ref> <cases.json> [--samples N] [--model M] [--live]
#   --samples N  samples per arm, 1 or odd (default 1)    --model M  claude model (default sonnet)
#   --live       spend the model calls; without it, print the plan and exit 3
# Exit: 0 PASS, 1 FAIL, 2 ERROR (a failed sample stops the run; nothing scored), 3 NOT RUN, 64 usage.
# Case file shape and the sustainability-lens example: lib/bench/README.md "lens-eval".
set -u

usage() { echo "usage: lens-eval.sh <command-file> <base-ref> <cases.json> [--samples N] [--model M] [--live]" >&2; exit 64; }
die() { echo "lens-eval: $*" >&2; usage; }

samples=1 model=sonnet live=0 pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --samples) [ $# -ge 2 ] || usage; samples="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --live) live=1; shift ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown flag: $1" ;;   # also refuses an option-shaped base ref before git sees it
    *) pos+=("$1"); shift ;;
  esac
done
[ ${#pos[@]} -eq 3 ] || usage
cmd="${pos[0]}" base="${pos[1]}" cases="${pos[2]}"
case "$samples" in ''|*[!0-9]*|0*) die "--samples must be a positive integer" ;; esac
# An even N allows a tie, which has no majority either way.
[ $((samples % 2)) -eq 1 ] || die "--samples must be odd"
[ -f "$cmd" ] || die "no command file: $cmd"
cdir="$(cd "$(dirname "$cmd")" && pwd)"
git -C "$cdir" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $cdir"
basesha="$(git -C "$cdir" rev-parse --verify -q "$base^{commit}")" || die "bad ref: $base"
control="$(git -C "$cdir" show "$basesha:./$(basename "$cmd")" 2>/dev/null)" || die "$cmd not at $base"
treatment="$(cat "$cmd")"
[ "$control" != "$treatment" ] || die "control and treatment text are identical at $base; nothing to compare"

jq -e 'def arm: . == null or . == "hit" or . == "miss";
  (.cases | type == "array" and length > 0) and all(.cases[];
    (.name | type == "string" and test("^[A-Za-z0-9._-]+$"))
    and (.fixture | type == "string" and (test("^/|(^|/)\\.\\.(/|$)") | not))
    and (.signals | type == "array" and length > 0) and all(.signals[];
      (.name | type == "string" and test("^[A-Za-z0-9._-]+$")) and (.pattern | type == "string")
      and ((.reviewer // "") | type == "string")
      and (.treatment | arm) and ((.control | arm) or (.control == "fewer" and .treatment == "hit"))
      and (.treatment != null or .control != null))
    and ([.signals[].name] | length == (unique | length)))
  and ([.cases[].name] | length == (unique | length))' \
  "$cases" >/dev/null 2>&1 || die "bad case file: $cases"
# A bad regex would make grep exit 2, which scores as a miss and lets a `miss` pass.
while IFS= read -r re; do
  grep -qE -- "$re" /dev/null 2>/dev/null; [ $? -le 1 ] || die "bad regex in $cases: $re"
done < <(jq -r '.cases[].signals[] | .pattern, (.reviewer // empty)' "$cases")
dir="$(cd "$(dirname "$cases")" && pwd)"
ncases="$(jq '.cases | length' "$cases")"

# arms <case-index>: the arms some signal of the case names, one per line.
arms() { jq -r --argjson c "$1" '.cases[$c].signals as $s | ("treatment", "control") as $a
  | select(any($s[]; .[$a] != null)) | $a' "$cases"; }

calls=0
for ((c = 0; c < ncases; c++)); do
  f="$dir/$(jq -r ".cases[$c].fixture" "$cases")"
  [ -f "$f" ] || die "no fixture: $f"
  calls=$((calls + $(arms "$c" | wc -l) * samples))
done
if [ "$live" -eq 0 ]; then
  echo "plan: $ncases cases, $samples samples per arm = $calls model calls ($model)"
  echo "verdict: NOT RUN (dry run, 0 model calls; add --live to spend them)"
  exit 3
fi
command -v claude >/dev/null 2>&1 || { echo "verdict: ERROR (claude not on PATH)"; exit 2; }

tmp="${TMPDIR:-/tmp}"; out="$(mktemp -d "${tmp%/}/lens-eval.XXXXXX")"
header='Run the command below once, non-interactively, against the spec below. Do not ask questions or pause between reviewers. Run no tools, write no files, and skip any gate-ledger or Status step. Print only the final report. Tag every finding with the reviewer that raised it, as "Reviewer N".'
made=0 cost=0 t0=$SECONDS
sha12() { printf '%s\n' "$1" | shasum -a 256 | cut -c1-12; }
summary() {
  echo; echo "samples: $out"
  echo "base: $base $basesha"
  echo "text sha256: treatment $(sha12 "$treatment") control $(sha12 "$control")"
  echo "cost: \$$cost over $made calls, $((SECONDS - t0))s"
}

# ponytail: sequential calls with no per-call timeout; add `&`+`wait` or a timeout when N grows past 3.
for ((c = 0; c < ncases; c++)); do
  name="$(jq -r ".cases[$c].name" "$cases")"
  fixture="$(cat "$dir/$(jq -r ".cases[$c].fixture" "$cases")")"
  for arm in $(arms "$c"); do
    if [ "$arm" = treatment ]; then text="$treatment"; else text="$control"; fi
    for ((i = 1; i <= samples; i++)); do
      echo "lens-eval: $name $arm $i/$samples" >&2
      envelope="$(printf '%s\n\n=== COMMAND ===\n%s\n\n=== SPEC ===\n%s\n' "$header" "$text" "$fixture" \
        | (cd "$out" && claude -p --safe-mode --no-session-persistence --tools "" --max-budget-usd 1 \
             --model "$model" --output-format json 2>>"$out/claude-stderr.log"))" || envelope=""
      made=$((made + 1))
      # An is_error envelope carries an error message as .result; it is a failed sample, never a miss.
      result="$(jq -r 'if .is_error == true then "" else .result // "" end' <<<"$envelope" 2>/dev/null)"
      printf '%s\n' "$result" >"$out/$name.$arm.$i.md"
      one="$(jq -r '.total_cost_usd // 0' <<<"$envelope" 2>/dev/null)"
      cost="$(awk -v a="$cost" -v b="${one:-0}" 'BEGIN { print a + b }')"
      # Stop on the first failure: the rest would spend money on a run that cannot be scored.
      if [ -z "${result//[[:space:]]/}" ]; then
        summary; echo "verdict: ERROR (failed sample $name.$arm.$i, see $out)"; exit 2
      fi
    done
  done
done

US=$'\x1f'   # unit separator: patterns may hold tabs or backslashes, which @tsv would mangle
# blocks <file>: one line per finding, "<reviewer heading><US><block>". Models tag a finding
# on its first line and put the detail on indented lines under it, so a block is a top-level
# list item, a heading, or a paragraph start, joined with its continuation lines. A table
# row is always its own block. A Passed section holds pass lines, never findings, so it is
# dropped up to the next heading. A `Reviewer N` heading credits the blocks under it, until
# a heading at the same or a higher level.
blocks() {
  awk 'function flush() { if (b != "") print bctx "\037" b; b = "" }
       BEGIN { rlev = 99 }
       /^#/ { flush(); match($0, /^#+/)
              if (RLENGTH <= rlev) { ctx = ""; rlev = 99 }
              if (tolower($0) ~ /^#+ *reviewer [0-9]/) { ctx = $0; rlev = RLENGTH }
              skip = tolower($0) ~ /^#+ *passed/ }
       skip { next }
       /^[[:space:]]*$/ { blank = 1; next }
       /^\|/ { flush(); print ctx "\037" $0; blank = 0; next }
       /^([0-9]+[.)]|[-*+]) |^#/ || (blank && /^[^[:space:]]/) { flush(); b = $0; bctx = ctx; blank = 0; next }
       { if (b == "") { b = $0; bctx = ctx } else b = b " " $0; blank = 0 }
       END { flush() }' "$1"
}

# hits <case> <arm> <reviewer-regex> <pattern>: how many samples have one block matching both.
# The reviewer regex sees the carried heading too; the pattern sees the block alone.
hits() {
  local n=0 i
  for ((i = 1; i <= samples; i++)); do
    blocks "$out/$1.$2.$i.md" | grep -iE -- "${3:-.}" | cut -d "$US" -f2- | grep -qiE -- "$4" && n=$((n + 1))
  done
  echo "$n"
}

echo "| case | signal | treatment | control | result |"
echo "|---|---|---|---|---|"
total=0 nbad=0 bad=""
while IFS="$US" read -r cname sname reviewer pattern want_t want_c; do
  ok=1 cells="" ht=0
  for pair in "treatment:$want_t" "control:$want_c"; do
    arm="${pair%%:*}" want="${pair#*:}"
    if [ "$want" = "-" ]; then cells="$cells | -"; continue; fi
    h="$(hits "$cname" "$arm" "$reviewer" "$pattern")"
    if [ "$want" = fewer ]; then
      # A planted gap: the old text may notice it too, so only the gap between arms counts.
      [ "$h" -lt "$ht" ] || ok=0
    else
      if [ $((h * 2)) -gt "$samples" ]; then got=hit; else got=miss; fi
      [ "$got" = "$want" ] || ok=0
    fi
    [ "$arm" = treatment ] && ht=$h
    cells="$cells | $h/$samples want $want"
  done
  total=$((total + 1))
  if [ "$ok" -eq 1 ]; then res=PASS; else res=FAIL; nbad=$((nbad + 1)); bad="$bad${bad:+, }$sname"; fi
  echo "| $cname | $sname$cells | $res |"
done < <(jq -r --arg us "$US" '.cases[] | .name as $c | .signals[]
  | [$c, .name, (.reviewer // ""), .pattern, (.treatment // "-"), (.control // "-")] | join($us)' "$cases")

summary
if [ "$nbad" -gt 0 ]; then echo "verdict: FAIL ($nbad/$total signals failed: $bad)"; exit 1; fi
echo "verdict: PASS ($total/$total signals)"
