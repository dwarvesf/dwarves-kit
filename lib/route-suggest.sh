#!/usr/bin/env bash
# route-suggest.sh -- data-driven model routing suggester (token-optim-v3 SG-06).
# Needs bash 4+ (mapfile); #!/usr/bin/env bash resolves Homebrew bash, not macOS stock 3.2.
#
# Reads the v2 SG-09 ablation ledger (the 12-column TSV the eval harness emits)
# and SUGGESTS the model tier for a given benchmark task: the cheapest model that
# PASSED at quality parity. It is a SUGGESTER, never an auto-router, and it
# ABSTAINS (does not overfit) when the data is too thin to compare , e.g. only
# one model was measured, which is exactly the state of the committed SG-09 proof
# run (haiku-only, n=1; the full multi-model matrix is gated on a human).
#
# Ledger schema (tab-delimited, no header), per v2 SG-09 record.py:
#   task arm pass total_tokens in out cache_read cache_create turns cost_usd models session_id
#    1    2   3      4         5  6   7        8            9    10      11        12
#
# Effort is NOT a column in SG-09's schema, so effort is always abstained on
# (honesty: we cannot suggest what was never measured).
#
# Usage:
#   route-suggest.sh <ledger.tsv> <task>
# Output (tab-delimited, parseable):
#   SUGGEST  model=<tier>  effort=abstain  basis=<measured comparison>
#   ABSTAIN  reason=<why>  effort=abstain
# Exit 0 on SUGGEST, 2 on ABSTAIN, 1 on usage/IO error.

set -u

LEDGER="${1:-}"
TASK="${2:-}"
if [ -z "$LEDGER" ] || [ -z "$TASK" ]; then
  echo "usage: route-suggest.sh <ledger.tsv> <task>" >&2
  exit 1
fi
if [ ! -f "$LEDGER" ]; then
  echo "ABSTAIN	reason=no-ledger: $LEDGER not found	effort=abstain"
  exit 2
fi

# tier <- short model name (haiku-4-5 -> haiku, sonnet-4-6 -> sonnet, opus-4-8 -> opus).
# The orchestrator routes `--model <tier>`, so we emit the bare tier.
tier_of() { case "$1" in haiku*) echo haiku;; sonnet*) echo sonnet;; opus*) echo opus;; *) echo "$1";; esac; }

# For each PASSING row of this task, emit "tier<TAB>total_tokens" (cheapest arm per tier
# is the min). A failed run is never a candidate (infinite-cost guard, SG-09's anti-cherry-pick rule).
mapfile -t PASSES < <(awk -F'\t' -v t="$TASK" '$1==t && $3=="pass" {print $11"\t"$4}' "$LEDGER")

if [ "${#PASSES[@]}" -eq 0 ]; then
  echo "ABSTAIN	reason=no-passing-data: no PASS rows for task '$TASK' in ledger	effort=abstain"
  exit 2
fi

# Reduce to cheapest total_tokens per tier. A short/malformed row (no numeric total_tokens) is
# skipped rather than crashing the `-lt` arithmetic (schema-drift / hand-edit robustness).
declare -A MIN
for row in "${PASSES[@]}"; do
  model="${row%%$'\t'*}"; tok="${row##*$'\t'}"
  case "$tok" in ''|*[!0-9]*) continue ;; esac   # non-numeric -> not a usable token count
  tier="$(tier_of "$model")"
  if [ -z "${MIN[$tier]:-}" ] || [ "$tok" -lt "${MIN[$tier]}" ]; then MIN[$tier]="$tok"; fi
done

NTIERS="${#MIN[@]}"
if [ "$NTIERS" -lt 2 ]; then
  only="$(printf '%s' "${!MIN[*]}")"
  echo "ABSTAIN	reason=thin-data: only '$only' measured at parity for '$TASK' (need >=2 models to compare); keep the human's choice / default per the Opus-spend heuristic	effort=abstain"
  exit 2
fi

# >=2 tiers passed: suggest the cheapest by measured total_tokens. Iterate tiers in a fixed sorted
# order + strict `-lt` so a tie resolves deterministically to the alphabetically-first tier (bash
# associative-array iteration order is otherwise unspecified).
best_tier=""; best_tok=""
basis=""
while IFS= read -r tier; do
  basis="${basis:+$basis, }$tier=${MIN[$tier]}tok"
  if [ -z "$best_tok" ] || [ "${MIN[$tier]}" -lt "$best_tok" ]; then best_tok="${MIN[$tier]}"; best_tier="$tier"; fi
done < <(printf '%s\n' "${!MIN[@]}" | sort)
echo "SUGGEST	model=$best_tier	effort=abstain	basis=cheapest-at-parity for '$TASK': $basis (all PASS)"
exit 0
