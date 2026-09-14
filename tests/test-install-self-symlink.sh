#!/usr/bin/env bash
# test-install-self-symlink.sh -- on a dev machine ~/.claude/dwarves-kit is a
# symlink to the checkout, so the compat branch's link targets resolve to the
# same paths it is writing. Re-running install.sh there used to move hooks/ lib/
# bin/ aside and leave symlinks pointing at themselves, killing every hook with
# ELOOP. The guard in kit_symlink_hardened must leave the checkout untouched.
set -euo pipefail
KIT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

TMP="$(mktemp -d)"; HOME_SB="$(mktemp -d)"; FAKE_KIT="$(mktemp -d)"
trap 'rm -rf "$TMP" "$HOME_SB" "$FAKE_KIT"' EXIT

# A stand-in checkout with the dirs the compat branch links, then CLAUDE_DIR
# gets a dwarves-kit symlink pointing straight at it (the dev-machine layout).
# install.sh derives KIT_DIR from its OWN location, so the copy has to live in
# the stand-in checkout for the paths to collide the way they do on the Air.
mkdir -p "$FAKE_KIT/hooks" "$FAKE_KIT/lib" "$FAKE_KIT/bin" "$FAKE_KIT/docs/impl-playbook"
echo 'real hook' > "$FAKE_KIT/hooks/marker.sh"
echo 'real lib'  > "$FAKE_KIT/lib/marker.sh"
echo 'playbook'  > "$FAKE_KIT/docs/impl-playbook/marker.md"
cp "$KIT_DIR/install.sh" "$FAKE_KIT/install.sh"
mkdir -p "$TMP/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
ln -s "$FAKE_KIT" "$TMP/dwarves-kit"

out="$(HOME="$HOME_SB" CLAUDE_DIR="$TMP" bash "$FAKE_KIT/install.sh" 2>&1 || true)"

{ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q '\[skip\]'; chk "guard fired (reported a skip)" $?
[ -d "$FAKE_KIT/hooks" ] && [ ! -L "$FAKE_KIT/hooks" ]; chk "hooks/ still a real directory" $?
[ -d "$FAKE_KIT/lib" ] && [ ! -L "$FAKE_KIT/lib" ];     chk "lib/ still a real directory" $?
[ -f "$FAKE_KIT/hooks/marker.sh" ];                     chk "hook file still readable (no ELOOP)" $?
[ -z "$(ls -d "$FAKE_KIT"/*.pre-symlink.bak.* 2>/dev/null)" ]; chk "no dir moved aside to a .pre-symlink.bak" $?

[ "$fail" -eq 0 ] && echo "PASS: install self-symlink guard" || { echo "SOME TESTS FAILED"; exit 1; }
