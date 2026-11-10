#!/usr/bin/env bash
# proof-classes.sh -- reader for lib/gate/proof-classes.tsv, the one declaration of the proof class names,
# their rank, and the stateful words the diff classifier (proof-ledger.sh) and the task-text classifier
# (proof-gate.sh) share. Source it; it defines pc_* functions and checks the table once.
#
#   pc_classes             class names, highest rank first
#   pc_rank <name>         the rank of a class (nothing for an undeclared name)
#   pc_is_class <name>     exit 0 when <name> is a declared class
#   pc_emit <name>         print <name> when declared, else exit 70 (a classifier never prints an undeclared class)
#   pc_stateful_ere        the shared stateful words joined into one ERE
#
# A table that cannot be trusted is FATAL at load, never an empty or partial vocabulary: a missing, empty,
# malformed (not 3 tab fields, bad ERE, bad rank) table would quietly turn every stateful change into a
# behavioral one.

PC_TSV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/proof-classes.tsv"

_pc_rows() { awk -F'\t' '!/^#/ && !/^[[:space:]]*$/' "$PC_TSV"; }

pc_classes() { _pc_rows | awk -F'\t' '$1=="class" { print $3 "\t" $2 }' | sort -rn | cut -f2; }
pc_rank() { _pc_rows | awk -F'\t' -v n="$1" '$1=="class" && $2==n { print $3 }'; }
pc_is_class() { [ -n "$(pc_rank "$1")" ]; }
pc_emit() { pc_is_class "$1" || { echo "proof-classes: undeclared class '$1'" >&2; return 70; }; printf '%s\n' "$1"; }
pc_stateful_ere() { _pc_rows | awk -F'\t' '$1=="stateful" { printf "%s%s", sep, $2; sep="|" }'; }

# _pc_ere_ok <ERE>: exit 0 when grep -E accepts it. A bad ERE makes grep exit 2, which `if grep -q` reads
# as "no match", so one malformed row would quietly drop every input to behavioral.
_pc_ere_ok() { printf x | grep -E -e "$1" >/dev/null 2>&1; [ $? -ne 2 ]; }

# _pc_problem: print why the table cannot be trusted (nothing when it can).
_pc_problem() {
  [ -r "$PC_TSV" ] || { echo "missing or unreadable"; return; }
  local bad
  bad="$(_pc_rows | awk -F'\t' '
    NF != 3 { print "row without exactly 3 tab-separated fields: " $0; next }
    $2 == "" { print "empty value: " $0; next }
    $1 == "class" { if ($3 !~ /^[0-9]+$/) print "class rank is not an integer: " $0; else if (seen[$3]++) print "class rank declared twice: " $0; next }
    $1 == "stateful" { next }
    { print "unknown kind: " $0 }' | head -1)"
  [ -z "$bad" ] || { echo "$bad"; return; }
  pc_is_class inert && pc_is_class behavioral && pc_is_class stateful || { echo "lacks a class"; return; }
  local pat
  while IFS= read -r pat; do
    _pc_ere_ok "$pat" || { echo "invalid ERE: $pat"; return; }
  done < <(_pc_rows | awk -F'\t' '$1=="stateful" { print $2 }')
  [ -n "$(pc_stateful_ere)" ] || { echo "no stateful word"; return; }
  _pc_ere_ok "$(pc_stateful_ere)" || echo "joined stateful ERE is invalid"
}

PC_PROBLEM="$(_pc_problem)"
if [ -n "$PC_PROBLEM" ]; then
  echo "FATAL: lib/gate/proof-classes.tsv: $PC_PROBLEM" >&2
  exit 1
fi
