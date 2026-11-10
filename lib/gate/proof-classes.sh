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
# A missing or empty table is FATAL, never an empty vocabulary: an empty stateful set would quietly
# turn every stateful change into a behavioral one.

PC_TSV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/proof-classes.tsv"

_pc_rows() { awk -F'\t' '!/^#/ && NF' "$PC_TSV"; }

pc_classes() { _pc_rows | awk -F'\t' '$1=="class" { print $3 "\t" $2 }' | sort -rn | cut -f2; }
pc_rank() { _pc_rows | awk -F'\t' -v n="$1" '$1=="class" && $2==n { print $3 }'; }
pc_is_class() { [ -n "$(pc_rank "$1")" ]; }
pc_emit() { pc_is_class "$1" || { echo "proof-classes: undeclared class '$1'" >&2; return 70; }; printf '%s\n' "$1"; }
pc_stateful_ere() { _pc_rows | awk -F'\t' '$1=="stateful" { printf "%s%s", sep, $2; sep="|" }'; }

if [ ! -r "$PC_TSV" ] || ! pc_is_class inert || ! pc_is_class behavioral || ! pc_is_class stateful || [ -z "$(pc_stateful_ere)" ]; then
  echo "FATAL: lib/gate/proof-classes.tsv missing, unreadable, or lacks a class or stateful word" >&2
  exit 1
fi
