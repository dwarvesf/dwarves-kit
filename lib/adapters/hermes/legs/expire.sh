#!/bin/bash
# expiry leg: archive the bot-made cards that outlived their rule's limit. `board sweep` runs it after
# the per-repo syncs as `"$BASH" <this script>` (lib/adapters/README.md, legs). Same store and PATH rules
# as the mirror leg, but it reads no BACKLOG and writes no snapshot, so it needs none of the origin
# plumbing and runs even on a tick where the mirror was skipped. It is on only when both
# --expire-kinds-file and --mirror-hermes-home are given; otherwise it exits 0 and prints nothing.
# Observational: it prints its own `expire rc=<n>` line and exits 0 whatever `board mirror-cleanup`
# returned, so a failure logs and never flips the sweep's exit code.
set -u

BOARD_CMD="$SWEEP_BOARD_CMD"
DRY_RUN="$SWEEP_DRY_RUN"
MIRROR_HERMES_HOME="${MIRROR_HERMES_HOME:-}"
EXPIRE_KINDS="${EXPIRE_KINDS_FILE:-}"

if [ -n "$EXPIRE_KINDS" ] && [ -n "$MIRROR_HERMES_HOME" ]; then
  if command -v hermes >/dev/null 2>&1; then
    expire_flags=()
    [ "$DRY_RUN" -eq 0 ] && expire_flags+=(--apply)
    eout="$(HERMES_HOME="$MIRROR_HERMES_HOME" "$BOARD_CMD" mirror-cleanup --expire-only --hermes-home "$MIRROR_HERMES_HOME" --kinds-file "$EXPIRE_KINDS" ${expire_flags[@]+"${expire_flags[@]}"} 2>&1)"; erc=$?
    echo "  expire rc=$erc (home=$MIRROR_HERMES_HOME)"
    printf '%s\n' "$eout" | sed 's/^/    /'
  else
    echo "  expire skipped: hermes CLI not on PATH"
  fi
fi
exit 0
