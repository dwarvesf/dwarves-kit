#!/usr/bin/env bash
# backlog-stage.sh -- SessionEnd hook, function-named port of ops-toolkit's cc-backlog
# (kit-foldin design note, was cc-backlog). Thin bash shim; the actual logic is the
# co-located backlog-stage.py (stdlib-only, no deps to vendor). Always exits 0: a
# harvest never blocks a session end.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Opt-in, default off. A session ends with its follow-ups done or listed in its own report;
# staging candidates as a side effect filled a staging file nobody drained and fed a board
# that grew 13 to 25 rows a day. BACKLOG_STAGE_AUTO=1 restores all three passes below: the
# SessionEnd harvest, the SessionStart intake sweep, and the SessionStart count line.
case "${BACKLOG_STAGE_AUTO:-}" in 1|true|yes|on) ;; *) exit 0 ;; esac
# On the SessionStart surface pass, first sweep the consumer's declared deferred-link
# sources into the same staging funnel (intake-sweep is config-gated: no
# _meta/intake-sources.json means it is a silent no-op, and it self-throttles to daily),
# so the surfaced candidate count already includes them. One wiring point, one funnel.
case " $* " in *" --surface "*) python3 "$HERE/intake-sweep.py" || true ;; esac
python3 "$HERE/backlog-stage.py" "$@" || true
exit 0
