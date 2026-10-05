#!/usr/bin/env bash
# board-sweep-post.sh: hand one cluster's digest payload to the operator's
# poster command, then record the outcome in the digest state.
#
# The kit owns WHAT to post (board-digest.sh) and WHEN a post counts as
# delivered; the operator owns HOW (which chat service, which credentials).
# The poster contract:
#   - an executable, given by --poster
#   - stdin: the payload JSON that `board-digest.sh --emit` prints
#   - exit 0 means delivered; any other exit means not delivered
#   - stderr: on failure, the reason in plain text (it is redacted, stored in
#     the digest state, and shown on the next successful post for the same
#     cluster). stdout is ignored.
#
# Never touches the sweep's exit code: every failure path is a
# `digest: ... ERROR(...)` stderr line and exit 0. Only a usage error exits
# non-zero.
#
# On a failed post the reason can carry upstream error text (webhook URLs,
# token-shaped strings) and used to ride argv, which macOS exposes to every
# local user. It is redacted, stripped of non-printables (a byte-truncated
# UTF-8 tail breaks jq), and handed to the digest through a 0600 file.
#
# Usage: board-sweep-post.sh --cluster <name> --registry F --poster CMD
#          [--state-file F] [--cluster-map M] [--crit-prefix P] [--field-cap N]
#          [--dry-run]
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
DIGEST="$SELF_DIR/board-digest.sh"

CLUSTER=""
POSTER=""
DRY_RUN=0
REGISTRY=""
STATE_FILE="${HOME}/.cache/backlog-sync/digest-state.json"
digest_flags=()

while [ $# -gt 0 ]; do case "$1" in
  --cluster) CLUSTER="$2"; shift 2;;
  --poster) POSTER="$2"; shift 2;;
  --registry) REGISTRY="$2"; shift 2;;
  --state-file) STATE_FILE="$2"; shift 2;;
  --cluster-map|--crit-prefix|--field-cap) digest_flags+=("$1" "$2"); shift 2;;
  --dry-run) DRY_RUN=1; shift;;
  *) echo "unknown arg: $1" >&2; exit 64;;
esac; done

[ -n "$CLUSTER" ] || { echo "need --cluster <name>" >&2; exit 64; }
[ -n "$REGISTRY" ] || { echo "need --registry <file>" >&2; exit 64; }
[ "$DRY_RUN" -eq 1 ] || [ -n "$POSTER" ] || { echo "need --poster <command>" >&2; exit 64; }
command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }

log() { echo "digest: $*" >&2; }
reason=""
fail() { log "ERROR($1) $CLUSTER"; reason="${reason:+$reason; }$1"; }

common=(--registry "$REGISTRY" --state-file "$STATE_FILE" ${digest_flags[@]+"${digest_flags[@]}"})

payload="$(bash "$DIGEST" --emit --cluster "$CLUSTER" "${common[@]}")"
digest_rc=$?
[ "$digest_rc" -eq 0 ] || { log "ERROR(digest --emit exited $digest_rc) $CLUSTER"; exit 0; }

[ -n "$payload" ] || exit 0  # nothing to post; the digest already logged skipped(no-change)

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$payload"
  log "$CLUSTER dry-run (not posted)"
  exit 0
fi

posted=0
if [ ! -x "$POSTER" ]; then
  fail "poster not executable: $POSTER"
else
  poster_err="$(mktemp)"
  if printf '%s' "$payload" | "$POSTER" >/dev/null 2>"$poster_err"; then
    posted=1
  else
    poster_rc=$?
    detail="$(tail -c 400 "$poster_err" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    fail "${detail:-poster exit $poster_rc}"
  fi
  rm -f "$poster_err"
fi

if [ "$posted" -eq 1 ]; then
  bash "$DIGEST" --mark-posted --cluster "$CLUSTER" "${common[@]}"
  log "$CLUSTER posted"
else
  reason_safe="$(printf '%s' "$reason" | LC_ALL=C tr -c '[:print:]' ' ' \
    | sed -E 's#https://discord(app)?\.com/api/webhooks/[^ ]+#[webhook-redacted]#g; s#[A-Za-z0-9_-]{24,}#[redacted]#g')"
  rfile="$(mktemp)"; chmod 600 "$rfile"
  printf '%s' "$reason_safe" > "$rfile"
  bash "$DIGEST" --mark-failed --cluster "$CLUSTER" --reason-file "$rfile" "${common[@]}"
  rm -f "$rfile"
fi

exit 0
