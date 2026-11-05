#!/usr/bin/env bash
# test-update-check-notice.sh -- hooks/kit-update-notice.sh (SessionStart, startup only).
#
# Hermetic: no network. HOME, the plugin root, the state dir and the "remote" VERSION all live in
# one mktemp dir; the fetch URL is a file:// URL (KIT_UPDATE_CHECK_URL).
#   T1  newer -> one systemMessage naming both versions and the update command
#   T2  equal, older, patch/minor/major compare -> silent
#   T3  fetch fails, garbage remote, garbage installed VERSION -> silent, exit 0
#   T4  cache younger than 24h -> no fetch (the URL is dead); stale cache -> fetch
#   T5  KIT_UPDATE_CHECK=0 and the module toggle (through anchor-root.sh) -> silent
#   T6  wiring: hooks.json and settings.json run it on SessionStart, matcher startup, timeout 5
#
# Run: bash tests/test-update-check-notice.sh
set -u
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$KIT_DIR/hooks/kit-update-notice.sh"

T="$(mktemp -d "${TMPDIR:-/tmp}/kit-update-notice.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
PLUGIN="$T/plugin"; mkdir -p "$PLUGIN"
STATE="$T/state"
REMOTE="$T/remote-VERSION"
export CLAUDE_PLUGIN_ROOT="$PLUGIN"
export KIT_UPDATE_STATE_DIR="$STATE"
export KIT_UPDATE_CHECK_URL="file://$REMOTE"
unset KIT_UPDATE_CHECK

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

# scenario <installed> <remote>: fresh state, then run the hook; sets OUT and RC.
scenario() {
  rm -rf "$STATE"
  printf '%s\n' "$1" > "$PLUGIN/VERSION"
  printf '%s\n' "$2" > "$REMOTE"
  OUT="$(bash "$HOOK" < /dev/null 2>"$T/err")"; RC=$?
}
silent() { [ -z "$OUT" ] && [ "$RC" -eq 0 ] && [ ! -s "$T/err" ]; }

echo "== T1 a newer release prints one notice =="
scenario 2.3.0 2.4.0
check "exit 0" "$RC"
check "stdout is valid JSON with a systemMessage" "$(printf '%s' "$OUT" | jq -e '.systemMessage | type == "string"' >/dev/null 2>&1; echo $?)"
MSG="$(printf '%s' "$OUT" | jq -r '.systemMessage' 2>/dev/null)"
check "names latest and installed" "$([ "${MSG%% Run:*}" = "dwarves-kit 2.4.0 is available (installed: 2.3.0)." ]; echo $?)"
check "carries the plugin update command" "$(printf '%s' "$MSG" | grep -qF 'claude plugin marketplace update dwarves-marketplace && claude plugin update kit@dwarves-marketplace'; echo $?)"
check "one JSON object, one line" "$([ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]; echo $?)"
check "the cache was written with the latest" "$([ "$(jq -r .latest "$STATE/cache.json" 2>/dev/null)" = 2.4.0 ]; echo $?)"

echo "== T2 semver compare =="
for pair in "2.3.0 2.3.0" "2.4.0 2.3.0" "2.3.1 2.3.0" "3.0.0 2.99.99" "2.10.0 2.9.9"; do
  set -- $pair; scenario "$1" "$2"
  check "installed $1, latest $2: silent" "$(silent; echo $?)"
done
for pair in "2.3.0 2.3.1" "2.3.9 2.4.0" "2.9.9 2.10.0" "2.99.99 3.0.0"; do
  set -- $pair; scenario "$1" "$2"
  check "installed $1, latest $2: notice" "$([ -n "$OUT" ] && printf '%s' "$OUT" | grep -q "dwarves-kit $2 is available (installed: $1)"; echo $?)"
done

echo "== T3 failures stay silent =="
rm -rf "$STATE"; printf '2.3.0\n' > "$PLUGIN/VERSION"; rm -f "$REMOTE"
OUT="$(bash "$HOOK" < /dev/null 2>"$T/err")"; RC=$?
check "remote file missing: silent, exit 0" "$(silent; echo $?)"
scenario 2.3.0 "<html>404 not found</html>"
check "garbage remote VERSION: silent" "$(silent; echo $?)"
scenario 2.3.0 "2.4"
check "two-part remote VERSION: silent" "$(silent; echo $?)"
scenario "dev-build" 9.9.9
check "garbage installed VERSION: silent" "$(silent; echo $?)"
rm -rf "$STATE"; rm -f "$PLUGIN/VERSION"; printf '9.9.9\n' > "$REMOTE"
OUT="$(bash "$HOOK" < /dev/null 2>"$T/err")"; RC=$?
check "no installed VERSION file: silent" "$(silent; echo $?)"
scenario 2.3.0 2.4.0
OUT="$(KIT_UPDATE_CHECK_URL="http://127.0.0.1:9/VERSION" KIT_UPDATE_STATE_DIR="$T/state2" bash "$HOOK" < /dev/null 2>"$T/err")"; RC=$?
check "connection refused: silent, exit 0" "$(silent; echo $?)"
OUT="$(PATH="/nonexistent" /bin/bash "$HOOK" < /dev/null 2>"$T/err")"; RC=$?
check "no curl and no jq on PATH: silent, exit 0" "$(silent; echo $?)"

echo "== T4 the 24h throttle =="
scenario 2.3.0 2.4.0   # primes the cache with latest 2.4.0
printf '9.9.9\n' > "$REMOTE"
OUT="$(KIT_UPDATE_CHECK_URL="http://127.0.0.1:9/VERSION" bash "$HOOK" < /dev/null 2>/dev/null)"
check "fresh cache + dead URL: still announces the cached 2.4.0 (no fetch needed)" "$(printf '%s' "$OUT" | grep -q 'dwarves-kit 2.4.0 is available'; echo $?)"
OUT="$(bash "$HOOK" < /dev/null 2>/dev/null)"
check "fresh cache + live URL with 9.9.9: still 2.4.0, so the remote was not read" "$(printf '%s' "$OUT" | grep -q 'dwarves-kit 2.4.0 is available'; echo $?)"
jq -n --argjson t "$(( $(date +%s) - 86500 ))" '{checked_at: $t, latest: "2.4.0"}' > "$STATE/cache.json"
OUT="$(bash "$HOOK" < /dev/null 2>/dev/null)"
check "cache older than 24h: fetches again and sees 9.9.9" "$(printf '%s' "$OUT" | grep -q 'dwarves-kit 9.9.9 is available'; echo $?)"
check "the cache stamp was refreshed" "$([ "$(( $(date +%s) - $(jq -r .checked_at "$STATE/cache.json") ))" -lt 60 ]; echo $?)"
jq -n --argjson t "$(( $(date +%s) - 86500 ))" '{checked_at: $t, latest: "2.4.0"}' > "$STATE/cache.json"
OUT="$(KIT_UPDATE_CHECK_URL="http://127.0.0.1:9/VERSION" bash "$HOOK" < /dev/null 2>/dev/null)"
check "stale cache + failed fetch: keeps the cached latest" "$(printf '%s' "$OUT" | grep -q 'dwarves-kit 2.4.0 is available'; echo $?)"
check "a failed fetch is recorded, so an offline start does not retry each time" "$([ "$(( $(date +%s) - $(jq -r .checked_at "$STATE/cache.json") ))" -lt 60 ]; echo $?)"
printf '2.4.0\n' > "$PLUGIN/VERSION"
OUT="$(bash "$HOOK" < /dev/null 2>/dev/null)"
check "after updating, the cached latest equals installed: silent" "$([ -z "$OUT" ]; echo $?)"

echo "== T5 opt-outs =="
scenario 2.3.0 2.4.0
rm -rf "$STATE"
OUT="$(KIT_UPDATE_CHECK=0 bash "$HOOK" < /dev/null 2>"$T/err")"; RC=$?
check "KIT_UPDATE_CHECK=0: silent" "$(silent; echo $?)"
check "KIT_UPDATE_CHECK=0 never wrote a cache" "$([ ! -e "$STATE/cache.json" ]; echo $?)"
# the module toggle is enforced by anchor-root.sh, like every non-spine hook
PROJ="$T/proj"; mkdir -p "$PROJ"
OUT="$(cd "$PROJ" && KIT_PROJECT_ROOT="$PROJ" bash "$KIT_DIR/hooks/anchor-root.sh" "$HOOK" < /dev/null 2>/dev/null)"
check "through anchor-root with the module on by default: notice" "$(printf '%s' "$OUT" | grep -q 'dwarves-kit 2.4.0 is available'; echo $?)"
printf '[modules]\nupdate_check = false\n' > "$PROJ/.kit.toml"
rm -rf "$STATE"
OUT="$(cd "$PROJ" && KIT_PROJECT_ROOT="$PROJ" bash "$KIT_DIR/hooks/anchor-root.sh" "$HOOK" < /dev/null 2>/dev/null)"
check "through anchor-root with modules.update_check = false: silent" "$([ -z "$OUT" ]; echo $?)"
check "module off never wrote a cache" "$([ ! -e "$STATE/cache.json" ]; echo $?)"

echo "== T6 wiring =="
for f in hooks/hooks.json settings.json; do
  got="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | contains("kit-update-notice.sh")) | "\(.matcher)|\(.hooks[0].timeout)"' "$KIT_DIR/$f" 2>/dev/null)"
  check "$f: one SessionStart entry, matcher startup, timeout 5 (got: ${got:-none})" "$([ "$got" = "startup|5" ]; echo $?)"
done
check "the hook and this test have no em or en dash" "$(! LC_ALL=C grep -q $'\xe2\x80[\x93\x94]' "$HOOK" "$0"; echo $?)"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
