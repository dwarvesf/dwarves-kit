#!/usr/bin/env bash
# harvest.sh -- PreCompact / SessionEnd hook, function-named port of ops-toolkit's
# cc-harvest (kit-foldin design note, was cc-harvest). Thin bash shim; the actual
# logic is the co-located harvest.py (stdlib-only, no deps to vendor). Modes (no
# args, --lab-log, --cleanup, --stop-trigger) are dispatched inside harvest.py;
# settings.json/hooks.json pass the mode as an argv flag. Always exits 0: a harvest
# never blocks a compaction/session-end/stop.
#
# Sweep gate: the AUTO modes -- no-arg, --lab-log, --stop-trigger -- exit 0
# without spawning harvest.py when either holds:
#   * HARVEST_SWEEP_CHILD=1 -- the process tree is the sweep's own extractor, which
#     must never re-fire the hook (recursion guard);
#   * the sweep is ACTIVE on this host (its <state>/sweep/installed marker exists AND
#     harvest.enable resolves true) AND harvest.hook_when_sweep_on is false -- so a
#     session is never staged or paid for twice while the sweep reads it.
# [harvest] keys resolve through kit_config_get_root only: a project
# .kit.toml rides inside an untrusted PR and can neither switch the sweep on nor
# keep the hook running. Explicit verbs (--cleanup, --sweep, --flush-list, ...) are
# never gated: they are operator actions, not hook fires.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_auto=1
for a in "$@"; do
  case "$a" in
    --lab-log|--stop-trigger) ;;
    *) _auto=0 ;;
  esac
done
if [ "$_auto" = 1 ]; then
  if [ "${HARVEST_SWEEP_CHILD:-}" = "1" ]; then
    exit 0
  fi
  _state="${HARVEST_STATE_DIR:-$HOME/.claude/dwarves-kit/state/harvest}"
  if [ -f "$_state/sweep/installed" ]; then
    # shellcheck source=../lib/config/kit-config.sh
    source "$HERE/../lib/config/kit-config.sh"
    _en="$(kit_config_get_root harvest.enable false | tr 'A-Z' 'a-z')"
    _hook="$(kit_config_get_root harvest.hook_when_sweep_on false | tr 'A-Z' 'a-z')"
    case "$_en" in
      true|1|yes|on)
        case "$_hook" in true|1|yes|on) ;; *) exit 0 ;; esac ;;
    esac
  fi
fi
python3 "$HERE/harvest.py" "$@" || true
exit 0
