#!/usr/bin/env bash
# The mega reconcile labels (OK CLAIM-UNVERIFIED ...) are declared once, in lib/mega/labels.tsv. `mega.sh status`
# prints them, `mega.sh labels` lists them, and lib/mega/mega-review.py builds its status-line parser from them.
# This suite proves the printed output is unchanged, and that a label added to the table reaches both readers
# with no second edit.
#
# Run: bash tests/test-mega-labels.sh   (exit 0 = all green)
set -uo pipefail
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1: got '$2' want '$3'"; FAIL=$((FAIL+1)); fi; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

echo "== the table and the verb =="
eq "labels.tsv exists" "$([ -f "$KIT_DIR/lib/mega/labels.tsv" ] && echo yes || echo no)" "yes"
eq "mega.sh labels lists the status labels, in order, one per line" \
  "$(bash "$KIT_DIR/lib/mega/mega.sh" labels | paste -sd ' ' -)" \
  "OK CLAIM-UNVERIFIED MERGED-UNCHECKED STALLED WIP PENDING INFO"

echo "== output unchanged: mega.sh status prints every label =="
RM="$TMP/m/fx"; mkdir -p "$RM"
cat > "$RM/ROADMAP.md" <<'RMEOF'
## Sub-goals
- [ ] SG-01 pending , auto
- [x] SG-02 claimed , auto , PR #2
- [~] SG-03 parked , auto
RMEOF
printf '#!/bin/bash\nexit 1\n' > "$TMP/stub"; chmod +x "$TMP/stub"
st="$(GH_BIN="$TMP/stub" GIT_BIN="$TMP/stub" bash "$KIT_DIR/lib/mega/mega.sh" status fx --megagoals-root "$TMP/m" --code-root "$TMP" 2>&1 | awk '$2 ~ /^SG-/ { print $2 "=" $3 }' | paste -sd ' ' -)"
eq "status labels" "$st" "SG-01=PENDING SG-02=CLAIM-UNVERIFIED SG-03=INFO"

echo "== a label added to the table reaches both readers =="
CP="$TMP/kit"; mkdir -p "$CP/lib"; cp -R "$KIT_DIR/lib/mega" "$CP/lib/mega"; ln -s "$KIT_DIR/lib/gate" "$CP/lib/gate"; ln -s "$KIT_DIR/lib/reflect" "$CP/lib/reflect"
printf 'fresh\tFRESHLABEL\tstatus\n' >> "$CP/lib/mega/labels.tsv"
eq "bash reader sees the new label" "$(bash "$CP/lib/mega/mega.sh" labels | tail -1)" "FRESHLABEL"
py="$(python3 - "$CP" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("mr", sys.argv[1] + "/lib/mega/mega-review.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
hit = m._STATUS_LINE_RE.match("  ~ SG-01      FRESHLABEL (note)")
print(hit.group("label") if hit else "none")
PY
)"
eq "python reader parses the new label" "$py" "FRESHLABEL"
py="$(python3 - "$KIT_DIR" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("mr", sys.argv[1] + "/lib/mega/mega-review.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print("hit" if m._STATUS_LINE_RE.match("  ~ SG-01      FRESHLABEL") else "none")
PY
)"
eq "the real table is untouched by the copy" "$py" "none"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
