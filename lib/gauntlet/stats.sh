#!/bin/bash
# gauntlet stats: read-only projection over the run-record corpus (SPEC-240).
# Scans docs/verification/gauntlet/ record dirs, parses QL-VERDICT markers +
# row-verdict tables + probe transcripts, prints one convergence table.
# --write drops a dated snapshot next to the records (refuses same-day
# overwrite without --force). Never writes inside a record dir.
set -uo pipefail

G="docs/verification/gauntlet"
WRITE=0 FORCE=0
for a in "$@"; do
  case "$a" in
    --write) WRITE=1 ;;
    --force) FORCE=1 ;;
    *) echo "usage: stats.sh [--write [--force]]" >&2; exit 2 ;;
  esac
done
[ -d "$G" ] || { echo "stats.sh: no $G here; run from the kit root" >&2; exit 1; }

# A QL-VERDICT line must match this in full (backtick wrapping allowed);
# anything else naming QL-VERDICT is a malformed marker and a loud error.
QL_OK='\[\[QL-VERDICT round=[0-9]+ clean=(true|false) findings=[0-9]+\]\]'

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# rounds_files <dir> -- the record files: ROUNDS.md + prefixed *-ROUNDS.md
rounds_files() {
  local d="$1" f
  for f in "$d/ROUNDS.md" "$d"/*-ROUNDS.md; do
    [ -f "$f" ] && echo "$f"
  done
}

# tokens_cost <dir> -- sum probe usage across the dir's transcripts, both
# formats: omp v3 (turn_end.usage) and claude stream-json (result event).
# Room contents (nested repos, kit copies) are pruned. Scoped per RUN, not
# per dir: a prefixed run (<p>-ROUNDS.md) owns only its <p>-round-* subtrees;
# the primary run owns the rest (its own round-* dirs and campaign row dirs
# never match '*-round-*'). Prints "tok cost" or nothing.
tokens_cost() {
  local d="$1" prefix="$2" files=()
  if [ -n "$prefix" ]; then
    while IFS= read -r line; do files+=("$line"); done < <(
      find "$d" \( -name kit-extract -o -name fixture-repo -o -name kit -o -name home \) -prune \
        -o -path "*/${prefix}-round-*" -name transcript.jsonl -print 2>/dev/null)
  else
    while IFS= read -r line; do files+=("$line"); done < <(
      find "$d" \( -name kit-extract -o -name fixture-repo -o -name kit -o -name home -o -name '*-round-*' \) -prune \
        -o -name transcript.jsonl -print 2>/dev/null)
  fi
  [ "${#files[@]}" -gt 0 ] || return 0
  jq -n '
    [inputs
     | if .type=="turn_end" and ((.usage // .message.usage)|type=="object") then
         ((.usage // .message.usage) | {t: ((.input//0)+(.output//0)), c: (.cost.total//0)})
       elif .type=="result" and ((.usage|type)=="object" or (.usage|type)=="null") then
         {t: (((.usage.input_tokens//0))+((.usage.output_tokens//0))), c: (.total_cost_usd//0)}
       else empty end]
    | if length==0 then empty else "\(map(.t)|add) \(map(.c)|add)" end
    | @text' -r "${files[@]}" 2>/dev/null
}

# probe_label <rounds-file> -- best-effort probe/model note for display.
probe_label() {
  local f="$1" p
  p=$(sed -n 's/^| *Probe *| *\(.*\) *|$/\1/p' "$f" | head -1)
  [ -n "$p" ] || p=$(sed -n 's/.*Probe: *\([^.;]*\).*/\1/p' "$f" | head -1)
  printf '%s' "${p:0:48}"
}

# Pass 1: malformed-marker sweep across the whole corpus (fail loud, AC-3).
bad=0
for d in "$G"/*/; do
  d="${d%/}"
  [ -L "$d" ] && continue
  while IFS= read -r f; do
    while IFS= read -r line; do
      # Full-line match after stripping backticks/whitespace: a line pairing a
      # valid marker with a corrupted one must still fail, so no substring pass.
      printf '%s' "$line" | sed 's/`//g; s/^ *//; s/ *$//' | grep -qxE "$QL_OK" \
        || { echo "stats.sh: malformed QL-VERDICT in $f: $line" >&2; bad=1; }
    done < <(grep -h 'QL-VERDICT' "$f")
  done < <(rounds_files "$d")
done
[ "$bad" -eq 0 ] || exit 1

# Pass 2: one summary row per run record.
for d in "$G"/*/; do
  d="${d%/}"
  [ -L "$d" ] && continue
  name="$(basename "$d")"
  while IFS= read -r f; do
    run="$name" prefix=""
    case "$f" in
      */ROUNDS.md) ;;
      *) prefix="$(basename "$f" -ROUNDS.md)"; run="$name/$prefix" ;;
    esac
    date_part="${name:0:10}"
    # QL-VERDICT projection: round-ordered findings trajectory + first clean round.
    traj="" clean_at="-" rounds=0
    while read -r rno cl fi; do
      rounds=$((rounds + 1))
      [ -n "$traj" ] && traj="${traj}->"
      traj="${traj}${fi}"
      [ "$cl" = "true" ] && [ "$clean_at" = "-" ] && clean_at="$rno"
    done < <(grep -h 'QL-VERDICT' "$f" \
             | sed -E 's/.*round=([0-9]+) clean=(true|false) findings=([0-9]+).*/\1 \2 \3/' \
             | sort -n)
    [ -n "$traj" ] || traj="-"
    # Campaign records: per-row verdict table (| J1 | ... GREEN ... |).
    rows_total=$(grep -cE '^\| *J[0-9]+ *\|' "$f" || true)
    if [ "${rows_total:-0}" -gt 0 ]; then
      rows_green=$(grep -E '^\| *J[0-9]+ *\|' "$f" | grep -c 'GREEN')
      rows="${rows_green}/${rows_total}"
    else
      rows="-"
    fi
    # Tokens/cost: scoped to this run's own transcripts (see tokens_cost).
    tok="-" cost="-"
    tc=$(tokens_cost "$d" "$prefix")
    if [ -n "$tc" ]; then
      tok="${tc%% *}"
      cost=$(printf '%.4f' "${tc#* }")
    fi
    probe=$(probe_label "$f")
    [ -n "$probe" ] || probe="-"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$run" "$date_part" "$rounds" "$traj" "$clean_at" "$rows" "$tok" "$cost" "$probe" >> "$TMP"
  done < <(rounds_files "$d")
done

[ -s "$TMP" ] || { echo "stats.sh: no run records found under $G" >&2; exit 1; }

render() {
  echo "# Gauntlet run-record stats ($(date +%F))"
  echo
  echo "| Run | Date | Rounds | Findings | Clean at | Rows GREEN | Probe tokens | Probe cost | Probe |"
  echo "|---|---|---|---|---|---|---|---|---|"
  sort "$TMP" | awk -F'\t' '{printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1,$2,$3,$4,$5,$6,$7,$8,$9}'
  # Same-card probe deltas: a record named <base>-nw pairs with <base>.
  local pairs
  pairs=$(awk -F'\t' '$1 ~ /-nw$/ {base=$1; sub(/-nw$/,"",base); print base"\t"$1}' "$TMP")
  [ -n "$pairs" ] || return 0
  echo
  echo "## Probe-model deltas (same card)"
  echo
  echo "| Card | Run | Rounds | Findings | Probe tokens | Probe cost | Probe |"
  echo "|---|---|---|---|---|---|---|"
  while IFS=$'\t' read -r base nw; do
    for r in "$base" "$nw"; do
      awk -F'\t' -v run="$r" -v card="$base" \
        '$1==run {printf "| %s | %s | %s | %s | %s | %s | %s |\n", card,$1,$3,$4,$7,$8,$9}' "$TMP"
    done
  done <<< "$pairs"
}

if [ "$WRITE" -eq 1 ]; then
  out="$G/$(date +%F)-stats.md"
  if [ -e "$out" ] && [ "$FORCE" -ne 1 ]; then
    echo "stats.sh: $out exists; pass --force to overwrite" >&2
    exit 1
  fi
  render > "$out"
  echo "wrote $out"
else
  render
fi
