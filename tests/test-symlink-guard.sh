#!/usr/bin/env bash
# test-symlink-guard.sh -- kit code that touches a fixed repo-relative path refuses a symlink there.
# A repo can track CLAUDE.md, .claude/backups or _meta as a link to an operator file; the kit must
# neither read through it nor write through it. Covers lib/config/safe-path.sh and its callers:
# lib/adopt.sh, hooks/pre-compact-backup.sh, hooks/harvest.sh, lib/reflect/staging-format.py.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
chk() { if [ "$2" = 0 ]; then ok "$1"; else no "$1"; fi; }

W="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
W="$(cd "$W" && pwd -P)"
export KIT_CONFIG_OPERATOR="$W/no-operator" CLAUDE_DIR="$W/no-claude" KIT_LEDGER_DIR="$W/ledger"
mkdir -p "$W/no-operator" "$W/no-claude" "$W/ledger"
newrepo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" config user.email t@t && git -C "$1" config user.name t; }

# --- the guard function ------------------------------------------------------
# shellcheck source=lib/config/safe-path.sh
. "$KIT_DIR/lib/config/safe-path.sh"
R="$W/guard"; mkdir -p "$R/real" "$W/outside"
ln -s "$W/outside" "$R/linkdir"
ln -s "$W/outside/f" "$R/linkfile"
kit_refuse_symlink_path "$R" "$R/real/new.md" 2>/dev/null; chk "guard: a clean path that does not exist yet passes" $?
kit_refuse_symlink_path "$R" "$R/linkfile" 2>/dev/null; chk "guard: a symlink leaf is refused" $((! $? ))
kit_refuse_symlink_path "$R" "$R/linkdir/x.md" 2>/dev/null; chk "guard: a path under a symlinked directory is refused" $((! $? ))
kit_refuse_symlink_path "$R" "$W/outside/x.md" 2>/dev/null; chk "guard: a path outside the root is refused" $((! $? ))
kit_refuse_symlink_path "$R" "$R/real/../x.md" 2>/dev/null; chk "guard: a dot-dot segment is refused" $((! $? ))
kit_refuse_symlink_path "$R/" "$R/real/ok.md" 2>/dev/null; chk "guard: a root with a trailing slash still works" $?

# --- adopt: a tracked CLAUDE.md that links to an operator file ---------------
echo "operator-secret-text" > "$W/outside/operator-file"
A="$W/adopt-claude"; newrepo "$A"
ln -s "$W/outside/operator-file" "$A/CLAUDE.md"
bash "$KIT_DIR/lib/adopt.sh" "$A" >/dev/null 2>&1; rc=$?
chk "adopt: refuses a symlinked CLAUDE.md (non-zero exit)" $([ "$rc" -ne 0 ]; echo $?)
chk "adopt: CLAUDE.md is still the same symlink" $([ -L "$A/CLAUDE.md" ]; echo $?)
chk "adopt: the linked file is unchanged" $([ "$(cat "$W/outside/operator-file")" = "operator-secret-text" ]; echo $?)
chk "adopt: nothing else was written" $([ ! -e "$A/AGENTS.md" ] && [ ! -e "$A/docs" ]; echo $?)

A2="$W/adopt-dir"; newrepo "$A2"
ln -s "$W/outside" "$A2/.claude"
bash "$KIT_DIR/lib/adopt.sh" "$A2" >/dev/null 2>&1; rc=$?
chk "adopt: refuses a symlinked .claude directory" $([ "$rc" -ne 0 ]; echo $?)
chk "adopt: nothing landed in the linked directory" $([ -z "$(ls "$W/outside" | grep -v operator-file)" ]; echo $?)

A3="$W/adopt-clean"; newrepo "$A3"
bash "$KIT_DIR/lib/adopt.sh" "$A3" >/dev/null 2>&1; rc=$?
chk "adopt: a clean repo still adopts" $([ "$rc" -eq 0 ] && [ -f "$A3/AGENTS.md" ]; echo $?)

# --- pre-compact-backup: .claude/backups links outside the project -----------
P="$W/pcb-link"; newrepo "$P"; mkdir -p "$P/.claude" "$W/backups-out"
ln -s "$W/backups-out" "$P/.claude/backups"
( cd "$P" && echo '{"session_id":"s"}' | bash "$KIT_DIR/hooks/pre-compact-backup.sh" >/dev/null 2>&1 ); rc=$?
chk "pre-compact-backup: exits 0 when the backup dir is a symlink" $rc
chk "pre-compact-backup: nothing is written through the link" $([ -z "$(ls "$W/backups-out")" ]; echo $?)
P2="$W/pcb-clean"; newrepo "$P2"
( cd "$P2" && echo '{"session_id":"s"}' | bash "$KIT_DIR/hooks/pre-compact-backup.sh" >/dev/null 2>&1 )
chk "pre-compact-backup: a clean repo still gets its backup" $([ -n "$(ls "$P2"/.claude/backups/*-backup-*.md 2>/dev/null)" ]; echo $?)

# --- harvest: _meta links outside the project --------------------------------
cat > "$W/ext.sh" <<'EXT'
#!/bin/sh
cat >/dev/null
printf '%s' '[{"item":"Guard The Link","kind":"decision","home":"til","why":"w"}]'
EXT
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"We decided to guard links."}]}}' > "$W/t.jsonl"
harvest_run() { # <repo>
  ( cd "$1" && printf '{"transcript_path":"%s","session_id":"s1"}' "$W/t.jsonl" \
    | REPO_ROOT="$1" HARVEST_STATE_DIR="$W/hv" HARVEST_SYNC=1 HARVEST_MIN_INTERVAL=0 \
      HARVEST_EXTRACTOR="bash $W/ext.sh" bash "$KIT_DIR/hooks/harvest.sh" >/dev/null 2>&1 )
}
H="$W/hv-link"; newrepo "$H"; mkdir -p "$W/meta-out"
ln -s "$W/meta-out" "$H/_meta"
harvest_run "$H"
chk "harvest: nothing is staged through a symlinked _meta" $([ -z "$(ls "$W/meta-out")" ]; echo $?)
H2="$W/hv-clean"; newrepo "$H2"
harvest_run "$H2"
chk "harvest: a clean repo still stages its ledger" $([ -s "$H2/_meta/learned-ledger.md" ]; echo $?)

# --- staging-format.py append: a symlinked staging file ----------------------
echo "keep" > "$W/outside/staging-target"
ln -s "$W/outside/staging-target" "$W/staging.md"
printf 'block\n' | python3 "$KIT_DIR/lib/reflect/staging-format.py" append "$W/staging.md" >/dev/null 2>&1; rc=$?
chk "staging append: refuses a symlinked staging file (non-zero exit)" $([ "$rc" -ne 0 ]; echo $?)
chk "staging append: the linked file is unchanged" $([ "$(cat "$W/outside/staging-target")" = "keep" ]; echo $?)
printf 'block\n' | python3 "$KIT_DIR/lib/reflect/staging-format.py" append "$W/plain.md" >/dev/null 2>&1
chk "staging append: a plain file still appends" $([ -s "$W/plain.md" ]; echo $?)

mv -f "$W" "$W.discard" 2>/dev/null
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
