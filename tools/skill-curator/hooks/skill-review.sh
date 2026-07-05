#!/usr/bin/env bash
# skill-review.sh: skill-curator's PreCompact/SessionEnd hook entry (its OWN entry, same events
# as cc-harvest, separate concern). It does the cheap part inline and hands the expensive reviewer
# to a DETACHED child, so it returns in well under 200 ms and never blocks the session. Exit 0
# always. The reviewer MODEL has no filesystem write (DEC-008); this hook only spawns it.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/../lib/common.sh"

# Reentrancy: if we are already inside a reviewer's `claude -p`, do nothing (a reviewer must never
# trigger a reviewer). --bare also strips hooks; this is belt-and-suspenders.
reviewing_sentinel_set && exit 0

# Master switch (config/env). Default on.
[ "$(cfg enabled true)" = "true" ] || exit 0

payload="$(cat 2>/dev/null)"
tp="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$tp" ] || exit 0

# Hand the payload to the detached child via a temp file (stdin does not survive a detached spawn).
mkdir -p "$CC_SI_STATE_DIR/state" 2>/dev/null || exit 0
pf="$CC_SI_STATE_DIR/state/payload-$$.json"
printf '%s' "$payload" > "$pf" 2>/dev/null || exit 0

# Detached: new session so it survives the hook returning; the child self-guards with the
# single-flight lock and removes its payload file. setsid if available, else nohup+disown.
if command -v setsid >/dev/null 2>&1; then
  setsid bash "$HERE/../lib/reviewer-spawn.sh" "$pf" >/dev/null 2>&1 < /dev/null &
else
  nohup bash "$HERE/../lib/reviewer-spawn.sh" "$pf" >/dev/null 2>&1 < /dev/null &
  disown 2>/dev/null || true
fi
exit 0
