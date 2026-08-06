#!/usr/bin/env bash
# lib/sync/deploy/macos/board-sync-cron tests (kit board ID-289). The
# install-script tests (test-sync-cron-install.sh) cover the install-time
# gate + render path; this covers the LAUNCHER itself: argv[1] required,
# the LIVE sync.mode re-check (skips cleanly once a repo un-opts-in),
# forwards to `bin/board sync --backlog-file <path>` unchanged, widens PATH,
# timestamped start/end log lines, the optional consumer env file, and the
# optional consumer bridge hook.
set -uo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$KIT_ROOT/lib/sync/deploy/macos/board-sync-cron"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 -- got: $3"; fi; }

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT

# stub bin/board (the launcher execs "$KIT/bin/board", resolved 4 dirs up
# from its own location -- exercise that path resolution for real by copying
# the launcher + the REAL kit-config.sh it now sources (for the live
# sync.mode re-check) into a throwaway kit-shaped tree with a fake bin/board).
FAKE_KIT="$d/fake-kit"
mkdir -p "$FAKE_KIT/lib/sync/deploy/macos" "$FAKE_KIT/lib/config" "$FAKE_KIT/bin"
cp "$LAUNCHER" "$FAKE_KIT/lib/sync/deploy/macos/board-sync-cron"
chmod +x "$FAKE_KIT/lib/sync/deploy/macos/board-sync-cron"
cp "$KIT_ROOT/lib/config/kit-config.sh" "$FAKE_KIT/lib/config/kit-config.sh"
BOARD_LOG="$d/board.log"
cat > "$FAKE_KIT/bin/board" <<STUB
#!/usr/bin/env bash
printf 'ARGV:%s\n' "\$*" > "$BOARD_LOG"
printf 'PATH:%s\n' "\$PATH" >> "$BOARD_LOG"
[ -n "\${CONSUMER_MARKER:-}" ] && printf 'CONSUMER_MARKER:%s\n' "\$CONSUMER_MARKER" >> "$BOARD_LOG"
exit 0
STUB
chmod +x "$FAKE_KIT/bin/board"

export HOME="$d/home"; mkdir -p "$HOME"
export KIT_CONFIG_ROOT="$d/kitroot"; mkdir -p "$KIT_CONFIG_ROOT"
printf '[sync]\nmode = "manual"\n' > "$KIT_CONFIG_ROOT/kit.toml"

mk_repo() {
  local dir="$1" mode="$2"
  mkdir -p "$dir/_meta"
  git -C "$dir" init -q
  touch "$dir/_meta/BACKLOG.md"
  if [ -n "$mode" ]; then
    printf '[sync]\napps = "reminders"\nmode = "%s"\n' "$mode" > "$dir/.kit.toml"
  fi
}

run() { bash "$FAKE_KIT/lib/sync/deploy/macos/board-sync-cron" "$1"; }

# --- missing argv[1] ---------------------------------------------------
out="$(bash "$FAKE_KIT/lib/sync/deploy/macos/board-sync-cron" 2>&1)"; rc=$?
check "missing backlog argv[1] fails cleanly (not an unbound-var crash trace)" \
  '[ "$rc" -ne 0 ] && [[ "$out" == *"missing backlog path"* ]]' "rc=$rc $out"

# --- live sync.mode re-check: mode=cron proceeds to bin/board -------------
mk_repo "$d/repoCron" cron
rm -f "$BOARD_LOG"
out="$(run "$d/repoCron/_meta/BACKLOG.md" 2>&1)"; rc=$?
check "mode=cron: resolves KIT via BASH_SOURCE (4 dirs up) and execs the fake bin/board" \
  '[ "$rc" -eq 0 ] && [ -f "$BOARD_LOG" ]' "rc=$rc"
check "mode=cron: forwards argv as: sync --backlog-file <path>" \
  '[[ "$(cat "$BOARD_LOG")" == *"ARGV:sync --backlog-file $d/repoCron/_meta/BACKLOG.md"* ]]' \
  "$(cat "$BOARD_LOG" 2>/dev/null)"
check "mode=cron: widens PATH with ~/.local/bin and /opt/homebrew/bin" \
  '[[ "$(cat "$BOARD_LOG")" == *"$HOME/.local/bin"* && "$(cat "$BOARD_LOG")" == *"/opt/homebrew/bin"* ]]' \
  "$(cat "$BOARD_LOG" 2>/dev/null)"
check "mode=cron: prints a timestamped start line" \
  '[[ "$out" == *"board-sync-cron: start backlog=$d/repoCron/_meta/BACKLOG.md"* ]]' "$out"
check "mode=cron: prints a timestamped end line with rc" \
  '[[ "$out" == *"board-sync-cron: end rc=0"* ]]' "$out"

# --- live sync.mode re-check: mode=manual (or unset) skips cleanly --------
mk_repo "$d/repoManual" manual
rm -f "$BOARD_LOG"
out="$(run "$d/repoManual/_meta/BACKLOG.md" 2>&1)"; rc=$?
check "mode=manual: skips cleanly, exit 0" '[ "$rc" -eq 0 ]' "rc=$rc"
check "mode=manual: does NOT invoke bin/board" '[ ! -f "$BOARD_LOG" ]' "$(cat "$BOARD_LOG" 2>/dev/null)"
check "mode=manual: says why it skipped" '[[ "$out" == *"no longer cron"* ]]' "$out"

mk_repo "$d/repoUnset" ""
rm -f "$BOARD_LOG"
out="$(run "$d/repoUnset/_meta/BACKLOG.md" 2>&1)"; rc=$?
check "no .kit.toml (default manual): skips cleanly, exit 0, no board call" \
  '[ "$rc" -eq 0 ] && [ ! -f "$BOARD_LOG" ]' "rc=$rc $(cat "$BOARD_LOG" 2>/dev/null)"

# --- sources the optional consumer env file -----------------------------
mkdir -p "$HOME/.config/board-sync-cron"
printf 'export CONSUMER_MARKER=from-consumer-env\n' > "$HOME/.config/board-sync-cron/env"
rm -f "$BOARD_LOG"
run "$d/repoCron/_meta/BACKLOG.md" >/dev/null 2>&1
check "sources ~/.config/board-sync-cron/env when present" \
  '[[ "$(cat "$BOARD_LOG" 2>/dev/null)" == *"CONSUMER_MARKER:from-consumer-env"* ]]' \
  "$(cat "$BOARD_LOG" 2>/dev/null)"
rm -f "$HOME/.config/board-sync-cron/env"

# --- no consumer env file: silent no-op, not an error ---------------------
rm -f "$BOARD_LOG"
out="$(run "$d/repoCron/_meta/BACKLOG.md" 2>&1)"; rc=$?
check "absent consumer env file is a silent no-op (exit 0, no error text)" \
  '[ "$rc" -eq 0 ] && [[ "$out" != *"No such file"* ]]' "rc=$rc $out"

# --- optional consumer bridge hook: called with rc + backlog path ---------
mkdir -p "$HOME/.config/board-sync-cron"
BRIDGE_LOG="$d/bridge.log"
cat > "$HOME/.config/board-sync-cron/bridge" <<STUB
#!/usr/bin/env bash
printf 'BRIDGE_ARGV:%s\n' "\$*" > "$BRIDGE_LOG"
STUB
chmod +x "$HOME/.config/board-sync-cron/bridge"
run "$d/repoCron/_meta/BACKLOG.md" >/dev/null 2>&1
check "executable bridge hook is invoked with rc + backlog path" \
  '[[ "$(cat "$BRIDGE_LOG" 2>/dev/null)" == "BRIDGE_ARGV:0 $d/repoCron/_meta/BACKLOG.md" ]]' \
  "$(cat "$BRIDGE_LOG" 2>/dev/null)"
rm -f "$HOME/.config/board-sync-cron/bridge" "$BRIDGE_LOG"

# --- no bridge hook: silent no-op ------------------------------------------
out="$(run "$d/repoCron/_meta/BACKLOG.md" 2>&1)"; rc=$?
check "absent bridge hook is a silent no-op (exit 0)" '[ "$rc" -eq 0 ]' "rc=$rc $out"

printf '=== %d/%d passed ===\n' "$PASS" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
