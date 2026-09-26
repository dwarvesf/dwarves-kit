#!/usr/bin/env bash
# lens-eval.sh -- treatment-vs-control eval for a prompt-only lens (a command or agent
# whose behavior is reviewer text, not code).
#
# Treatment is the working-tree text of <command-file>; control is the same path at
# <base-ref>. Each case's fixture spec runs through headless `claude -p` under each arm the
# case's signals name, N samples per arm. A sample hits a signal when one finding block
# (a list item or paragraph plus its indented lines) matches `pattern` (and `reviewer`). An arm hits when a strict majority of its
# samples hit; a tie is a miss. Prints a markdown table, the saved-samples dir, the cost,
# and one verdict line.
#
# Usage: lens-eval.sh <command-file> <base-ref> <cases.json> [--samples N] [--model M] [--live]
#   --samples N  samples per arm (default 1)    --model M  claude model (default sonnet)
#   --live       spend the model calls; without it, print the plan and exit 3
# Exit: 0 PASS, 1 FAIL, 2 ERROR (a failed sample; nothing scored), 3 NOT RUN, 64 usage.
# Case file shape and the SPEC-314 example: lib/bench/README.md "lens-eval".
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
[ -f "$cmd" ] || die "no command file: $cmd"
control="$(cd "$(dirname "$cmd")" && git show "$base:./$(basename "$cmd")" 2>/dev/null)" || die "$cmd not found at $base"
treatment="$(cat "$cmd")"

jq -e 'def arm: . == null or . == "hit" or . == "miss";
  (.cases | type == "array" and length > 0) and all(.cases[];
    (.name | type == "string" and test("^[A-Za-z0-9._-]+$")) and (.fixture | type == "string")
    and (.signals | type == "array" and length > 0) and all(.signals[];
      (.name | type == "string") and (.pattern | type == "string")
      and ((.reviewer // "") | type == "string")
      and (.treatment | arm) and (.control | arm) and (.treatment != null or .control != null)))' \
  "$cases" >/dev/null 2>&1 || die "bad case file: $cases"
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

tmp="${TMPDIR:-/tmp}"; out="$(mktemp -d "${tmp%/}/lens-eval.XXXXXX")"
header='Run the command below once, non-interactively, against the spec below. Do not ask questions or pause between reviewers. Run no tools, write no files, and skip any gate-ledger or Status step. Print only the final report. Tag every finding with the reviewer that raised it, as "Reviewer N".'
failed=0 cost=0 t0=$SECONDS

# ponytail: sequential calls with no per-call timeout; add `&`+`wait` or a timeout when N grows past 3.
for ((c = 0; c < ncases; c++)); do
  name="$(jq -r ".cases[$c].name" "$cases")"
  fixture="$(cat "$dir/$(jq -r ".cases[$c].fixture" "$cases")")"
  for arm in $(arms "$c"); do
    if [ "$arm" = treatment ]; then text="$treatment"; else text="$control"; fi
    for ((i = 1; i <= samples; i++)); do
      echo "lens-eval: $name $arm $i/$samples" >&2
      envelope="$(printf '%s\n\n=== COMMAND ===\n%s\n\n=== SPEC ===\n%s\n' "$header" "$text" "$fixture" \
        | (cd "$out" && claude -p --safe-mode --no-session-persistence --tools "" \
             --model "$model" --output-format json 2>>"$out/claude-stderr.log"))" || envelope=""
      # An is_error envelope carries an error message as .result; it is a failed sample, never a miss.
      result="$(jq -r 'if .is_error == true then "" else .result // "" end' <<<"$envelope" 2>/dev/null)"
      printf '%s\n' "$result" >"$out/$name.$arm.$i.md"
      [ -n "${result//[[:space:]]/}" ] || failed=$((failed + 1))
      one="$(jq -r '.total_cost_usd // 0' <<<"$envelope" 2>/dev/null)"
      cost="$(awk -v a="$cost" -v b="${one:-0}" 'BEGIN { print a + b }')"
    done
  done
done

summary() { echo; echo "samples: $out"; echo "cost: \$$cost over $calls calls, $((SECONDS - t0))s"; }
if [ "$failed" -gt 0 ]; then
  summary; echo "verdict: ERROR ($failed failed samples, see $out)"; exit 2
fi

# blocks <file>: one line per finding. Models tag a finding on its first line and put the
# detail on indented lines under it, so a block is a top-level list item, a heading, or a
# paragraph start, joined with its continuation lines.
blocks() {
  awk '/^[[:space:]]*$/ { blank = 1; next }
       /^([0-9]+[.)]|[-*+]) |^#/ || (blank && /^[^[:space:]]/) { if (b != "") print b; b = $0; blank = 0; next }
       { b = b " " $0; blank = 0 }
       END { if (b != "") print b }' "$1"
}

# hits <case> <arm> <reviewer-regex> <pattern>: how many samples have one block matching both.
hits() {
  local n=0 i
  for ((i = 1; i <= samples; i++)); do
    blocks "$out/$1.$2.$i.md" | grep -iE -- "${3:-.}" | grep -qiE -- "$4" && n=$((n + 1))
  done
  echo "$n"
}

echo "| case | signal | treatment | control | result |"
echo "|---|---|---|---|---|"
total=0 nbad=0 bad=""
US=$'\x1f'   # unit separator: patterns may hold tabs or backslashes, which @tsv would mangle
while IFS="$US" read -r cname sname reviewer pattern want_t want_c; do
  ok=1 cells=""
  for pair in "treatment:$want_t" "control:$want_c"; do
    arm="${pair%%:*}" want="${pair#*:}"
    if [ "$want" = "-" ]; then cells="$cells | -"; continue; fi
    h="$(hits "$cname" "$arm" "$reviewer" "$pattern")"
    if [ $((h * 2)) -gt "$samples" ]; then got=hit; else got=miss; fi
    [ "$got" = "$want" ] || ok=0
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
