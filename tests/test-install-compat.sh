#!/usr/bin/env bash
# test-install-compat.sh -- install.sh is plugin-aware: when the kit plugin is
# installed, it does a COMPAT-ONLY install (legacy path symlinks) and must NOT
# merge settings.json hooks or add flat commands (that would double-register).
set -euo pipefail
KIT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

# --- plugin present -> compat-only ---
# ID-463: the compat branch (install.sh's plugin-detected path) unconditionally
# writes a CLI shim to $HOME/.local/bin for every known module, regardless of
# --with. Without a sandboxed HOME that lands in the REAL ~/.local/bin, pointing
# at this test's own $TMP -- which the trap below deletes on exit, leaving a
# dangling shim. Incident: this clobbered 4 live shims on 2026-08-01. HOME_SB1/2
# give install.sh its own throwaway HOME so ~/.local/bin is never touched.
TMP="$(mktemp -d)"; HOME_SB1="$(mktemp -d)"; HOME_SB2="$(mktemp -d)"
trap 'rm -rf "$TMP" "${TMP2:-}" "$HOME_SB1" "$HOME_SB2"' EXIT
mkdir -p "$TMP/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
out="$(HOME="$HOME_SB1" CLAUDE_DIR="$TMP" bash "$KIT_DIR/install.sh" 2>&1)"

{ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'COMPAT-ONLY'; chk "took the compat branch" $?
[ -L "$TMP/dwarves-kit/lib" ];         chk "lib symlink created" $?
[ -L "$TMP/dwarves-kit/WORKFLOW.md" ]; chk "WORKFLOW.md symlink created" $?
[ -L "$TMP/dwarves-kit/docs/WORKFLOW.md" ]; chk "docs/WORKFLOW.md symlink created (SPEC-185 bulk)" $?
[ -L "$TMP/dwarves-kit/AGENTS.md" ];   chk "AGENTS.md symlink created" $?
# kit-config.sh reads the kit-root kit.toml and gate-ledger reads VERSION from
# ~/.claude/dwarves-kit by default, so the farm must carry both.
[ -L "$TMP/dwarves-kit/kit.toml" ];    chk "kit.toml symlink created" $?
[ -L "$TMP/dwarves-kit/VERSION" ];     chk "VERSION symlink created" $?
[ ! -e "$TMP/settings.json" ];         chk "settings.json NOT written (no double hooks)" $?
[ -e "$TMP/dwarves-kit/lib/classify/lane-classify.sh" ]; chk "compat lib resolves to a real script" $?

# --- compat branch retires a stale bare agent copy, keeps unowned ones ---
# A bare ~/.claude/agents/<name>.md that the cached plugin also ships is moved
# to agents.retired-<date>/, never rm'd; a user agent with a non-kit name and
# a kit-named copy the plugin does not ship yet both survive.
TMP3="$(mktemp -d)"; HOME_SB3="$(mktemp -d)"
trap 'rm -rf "$TMP" "${TMP2:-}" "$TMP3" "$HOME_SB1" "$HOME_SB2" "$HOME_SB3"' EXIT
mkdir -p "$TMP3/plugins/cache/dwarves-marketplace/kit/1.0.0/lib" "$TMP3/plugins/cache/dwarves-marketplace/kit/1.0.0/agents" "$TMP3/agents"
KIT_AGENT="$(ls "$KIT_DIR/agents/"*.md | head -1 | xargs basename)"
NOT_SHIPPED="$(ls "$KIT_DIR/agents/"*.md | sed -n 2p | xargs basename)"
cp "$KIT_DIR/agents/$KIT_AGENT" "$TMP3/plugins/cache/dwarves-marketplace/kit/1.0.0/agents/$KIT_AGENT"
echo "edited by the user" > "$TMP3/agents/$KIT_AGENT"
echo "kit name, not in the cached plugin yet" > "$TMP3/agents/$NOT_SHIPPED"
echo "user agent" > "$TMP3/agents/my-own-agent.md"
out3="$(HOME="$HOME_SB3" CLAUDE_DIR="$TMP3" bash "$KIT_DIR/install.sh" 2>&1)"
[ ! -e "$TMP3/agents/$KIT_AGENT" ];                       chk "stale bare agent copy removed from agents/" $?
[ "$(cat "$TMP3"/agents.retired-*/"$KIT_AGENT" 2>/dev/null)" = "edited by the user" ]; chk "stale copy retired with its content intact, not rm'd" $?
[ -f "$TMP3/agents/$NOT_SHIPPED" ];                       chk "kit-named copy the plugin does not ship survives" $?
[ -f "$TMP3/agents/my-own-agent.md" ];                    chk "user agent with a non-kit name survives" $?
{ trap '' PIPE; printf '%s' "$out3" 2>/dev/null || :; } | grep -q "Retired stale bare agent copy"; chk "install log announces the retire" $?

# --- KIT_FORCE_FULL bypasses compat even with the plugin present ---
TMP2="$(mktemp -d)"
mkdir -p "$TMP2/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
out2="$(HOME="$HOME_SB2" CLAUDE_DIR="$TMP2" KIT_FORCE_FULL=1 bash "$KIT_DIR/install.sh" 2>&1 || true)"
if { trap '' PIPE; printf '%s' "$out2" 2>/dev/null || :; } | grep -q 'COMPAT-ONLY'; then echo "FAIL KIT_FORCE_FULL still compat"; fail=1; else echo "ok   KIT_FORCE_FULL bypasses compat"; fi
# ... but never reopens the bare-agent duplicate: the plugin serves agents under
# kit:, so the full install with a plugin cached must not copy agents/ again.
[ -z "$(ls -A "$TMP2/agents" 2>/dev/null)" ]; chk "KIT_FORCE_FULL with plugin cached copies no bare agents" $?
{ trap '' PIPE; printf '%s' "$out2" 2>/dev/null || :; } | grep -q 'Agents served by the cached plugin'; chk "install log says agents come from the plugin" $?

# --- no plugin cached -> the full install still copies agents (negative control) ---
TMP4="$(mktemp -d)"; HOME_SB4="$(mktemp -d)"
trap 'rm -rf "$TMP" "${TMP2:-}" "${TMP3:-}" "$TMP4" "$HOME_SB1" "$HOME_SB2" "${HOME_SB3:-}" "$HOME_SB4"' EXIT
out4="$(HOME="$HOME_SB4" CLAUDE_DIR="$TMP4" bash "$KIT_DIR/install.sh" 2>&1 || true)"
KIT_AGENT_ANY="$(ls "$KIT_DIR/agents/"*.md | head -1 | xargs basename)"
[ -f "$TMP4/agents/$KIT_AGENT_ANY" ]; chk "no plugin cached: full install still copies agents" $?

# --- Tripwire (ID-463): the compat branch's CLI-shim write must never escape
# into the REAL $HOME, no matter what changes upstream in install.sh. $HOME is
# never reassigned in THIS script (only the install.sh subshells above got a
# sandboxed one), so it still names the operator's real home here.
REAL_BIN="$HOME/.local/bin"
LEAKED=""
if [ -d "$REAL_BIN" ]; then
  for f in "$REAL_BIN"/*; do
    [ -f "$f" ] || continue
    grep -q "dwarves-kit CLI shim" "$f" 2>/dev/null || continue
    grep -qE "exec \"($TMP|$TMP2)/" "$f" 2>/dev/null && LEAKED="$LEAKED $(basename "$f")"
  done
fi
[ -z "$LEAKED" ]; chk "tripwire: real ~/.local/bin shims never point into this test's \$TMPDIR (leaked:${LEAKED:- none})" $?

[ "$fail" -eq 0 ] && echo "PASS: install compat" || { echo "SOME TESTS FAILED"; exit 1; }
