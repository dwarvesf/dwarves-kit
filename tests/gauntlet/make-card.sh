#!/bin/bash
# make-card.sh -- render a frozen seed card from a scenario-matrix row
# (SPEC-227 P3). The matrix (scenarios.md) is the durable artifact; a card is
# its projection, materialized at run time and frozen into the run record.
#
# Usage:
#   make-card.sh <ROW>              # print the card to stdout
#   make-card.sh <ROW> --out <dir>  # write CARD.md into <dir> instead
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: make-card.sh <ROW> [--out <dir>]" >&2
  echo "  ROW one of: J1 J2 J3 J4 J5 J6 J7 J8 J9 J10 J11" >&2
  exit 64
}

ROW="${1:-}"
[ -n "${ROW}" ] || usage
shift || true

OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="${2:?--out needs a directory}"; shift 2 ;;
    *) usage ;;
  esac
done

# J1/J2 share the doorway card; J3+ each have their own file. One case arm
# per row keeps the mapping explicit and greppable rather than a naming
# convention that could silently drift (SPEC-227 P3).
case "${ROW}" in
  J1|J2)  CARD_FILE="${SCRIPT_DIR}/seed-card-user.md" ;;
  J3)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J3.md" ;;
  J4)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J4.md" ;;
  J5)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J5.md" ;;
  J6)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J6.md" ;;
  J7)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J7.md" ;;
  J8)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J8.md" ;;
  J9)     CARD_FILE="${SCRIPT_DIR}/seed-card-user-J9.md" ;;
  J10)    CARD_FILE="${SCRIPT_DIR}/seed-card-user-J10.md" ;;
  J11)    CARD_FILE="${SCRIPT_DIR}/seed-card-user-J11.md" ;;
  *) echo "make-card: unknown row '${ROW}'" >&2; usage ;;
esac

[ -f "${CARD_FILE}" ] || { echo "make-card: card file missing for ${ROW}: ${CARD_FILE}" >&2; exit 1; }

if [ -n "${OUT_DIR}" ]; then
  mkdir -p "${OUT_DIR}"
  cp "${CARD_FILE}" "${OUT_DIR}/CARD.md"
  echo "make-card: wrote ${OUT_DIR}/CARD.md (row ${ROW})" >&2
else
  cat "${CARD_FILE}"
fi
