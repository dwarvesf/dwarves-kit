#!/usr/bin/env bash
# test-adopt.sh -- lib/adopt.sh: fresh adopt, idempotency, --check, no-clobber.
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

newrepo() { local d; d="$(mktemp -d)"; git -C "$d" init -q; echo "$d"; }

# 1. fresh adopt creates the 4 artifacts
T1="$(newrepo)"
bash lib/adopt.sh "$T1" >/dev/null
if [ -f "$T1/AGENTS.md" ] && [ -f "$T1/WORKFLOW.md" ] && [ -f "$T1/docs/verification/README.md" ] \
  && grep -q 'kit:adopt' "$T1/CLAUDE.md"; then
  ok "fresh adopt creates AGENTS.md + WORKFLOW pointer + CLAUDE pointer + proof marker"
else
  no "fresh adopt artifacts"
fi

# 2. idempotent re-run = clean git diff
git -C "$T1" add -A
git -C "$T1" -c user.email=t@t -c user.name=t commit -qm init
bash lib/adopt.sh "$T1" >/dev/null
if git -C "$T1" diff --quiet; then ok "re-run is a clean no-op (idempotent)"; else no "re-run dirtied the tree"; fi

# 3. --check: 0 on adopted, 1 on fresh
if bash lib/adopt.sh --check "$T1" >/dev/null; then ok "--check exits 0 on an adopted repo"; else no "--check should be 0 on adopted"; fi
T2="$(newrepo)"
if bash lib/adopt.sh --check "$T2" >/dev/null; then no "--check should be 1 on a fresh repo"; else ok "--check exits 1 on a fresh repo"; fi

# 4. no-clobber: a pre-existing AGENTS.md is never overwritten
T3="$(newrepo)"
printf 'SENTINEL-DO-NOT-CLOBBER\n' > "$T3/AGENTS.md"
bash lib/adopt.sh "$T3" >/dev/null
if grep -q SENTINEL-DO-NOT-CLOBBER "$T3/AGENTS.md"; then ok "existing AGENTS.md is not clobbered"; else no "AGENTS.md was clobbered"; fi

# 5. CLAUDE.md loader uses an @AGENTS.md import + paired markers
if grep -q '@AGENTS.md' "$T1/CLAUDE.md" && grep -q '<!-- /kit:adopt -->' "$T1/CLAUDE.md"; then
  ok "CLAUDE.md loader uses @AGENTS.md import + paired end marker"
else
  no "CLAUDE.md loader missing @-import or end marker"
fi

# 6. --dry-run writes nothing
T4="$(newrepo)"
bash lib/adopt.sh --dry-run "$T4" >/dev/null
if [ ! -f "$T4/AGENTS.md" ] && [ ! -f "$T4/CLAUDE.md" ]; then ok "--dry-run writes nothing"; else no "--dry-run wrote files"; fi

# 7. --refresh keeps exactly one managed block (idempotent replace)
bash lib/adopt.sh --refresh "$T1" >/dev/null
s=$(grep -c '<!-- kit:adopt -->' "$T1/CLAUDE.md"); e=$(grep -c '<!-- /kit:adopt -->' "$T1/CLAUDE.md")
if [ "$s" = 1 ] && [ "$e" = 1 ]; then ok "--refresh keeps a single managed block"; else no "--refresh duplicated the block (s=$s e=$e)"; fi

# 8. --refresh REFUSES to truncate a block whose END marker is gone (review CRITICAL #1: the awk
#    strip would otherwise drop everything from START to EOF and mv the truncated file).
T5="$(newrepo)"
bash lib/adopt.sh "$T5" >/dev/null
printf 'TAIL-SENTINEL-KEEP-ME\n' >> "$T5/CLAUDE.md"
grep -v '<!-- /kit:adopt -->' "$T5/CLAUDE.md" > "$T5/CLAUDE.noend" && mv "$T5/CLAUDE.noend" "$T5/CLAUDE.md"
cp "$T5/CLAUDE.md" "$T5/CLAUDE.before"
if bash lib/adopt.sh --refresh "$T5" >/dev/null 2>&1; then
  no "--refresh should FAIL on a block missing its END marker"
elif cmp -s "$T5/CLAUDE.md" "$T5/CLAUDE.before" && grep -q TAIL-SENTINEL-KEEP-ME "$T5/CLAUDE.md"; then
  ok "--refresh refuses to truncate a block missing its END marker (file untouched)"
else
  no "--refresh mutated a file it should have refused (tail lost)"
fi

# 9. --refresh re-syncs a STALE block body (the actual purpose, not just idempotency) and keeps
#    the surrounding prose.
T6="$(newrepo)"
printf '# Repo\n\n<!-- kit:adopt -->\nSTALE-BODY\n<!-- /kit:adopt -->\n\n## Keep this tail\n' > "$T6/CLAUDE.md"
bash lib/adopt.sh --refresh "$T6" >/dev/null
if ! grep -q STALE-BODY "$T6/CLAUDE.md" && grep -q '@AGENTS.md' "$T6/CLAUDE.md" && grep -q 'Keep this tail' "$T6/CLAUDE.md"; then
  ok "--refresh replaces a stale block body and preserves surrounding content"
else
  no "--refresh did not re-sync the stale block or lost surrounding content"
fi

# 10. --refresh never overwrites AGENTS.md or the proof marker (documented invariant).
T7="$(newrepo)"
bash lib/adopt.sh "$T7" >/dev/null
printf 'AGENTS-SENTINEL\n' >> "$T7/AGENTS.md"
printf 'MARKER-SENTINEL\n' >> "$T7/docs/verification/README.md"
bash lib/adopt.sh --refresh "$T7" >/dev/null
if grep -q AGENTS-SENTINEL "$T7/AGENTS.md" && grep -q MARKER-SENTINEL "$T7/docs/verification/README.md"; then
  ok "--refresh preserves AGENTS.md + proof marker (never overwritten)"
else
  no "--refresh overwrote AGENTS.md or the proof marker"
fi

# 11. --dry-run on an already-adopted repo writes nothing (T1 was committed in test 2).
bash lib/adopt.sh --dry-run "$T1" >/dev/null
if git -C "$T1" diff --quiet; then ok "--dry-run on an adopted repo writes nothing"; else no "--dry-run dirtied an adopted repo"; fi

# ------------------------------------------------------------------------------------------
# SPEC-192 (goal 06, harness-ops): per-project .kit.toml override + adopt-time module wiring.
# The resolver (lib/config/kit-config.sh, goal 01) already merges <project>/.kit.toml over the
# kit-root default; these tests close the loop through adopt: a starter .kit.toml is seeded,
# and the currently-enabled hook-modules (board/session/advisor/cosmetic) are wired into
# <project>/.claude/settings.json at adopt time.
# ------------------------------------------------------------------------------------------
wired_hooks() { jq -r '[.hooks // {} | to_entries[]? | .value[]? | .hooks[]? | .command] | .[]' "$1" 2>/dev/null | grep -oE 'dwarves-kit/hooks/[A-Za-z0-9._-]+\.sh' | sed 's#dwarves-kit/hooks/##' | sort -u; }

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - SPEC-192 module-wiring tests need jq; not found on PATH"
else

# 12. Fresh adopt seeds a starter .kit.toml with a [modules] section naming every known module.
T8="$(newrepo)"
bash lib/adopt.sh "$T8" >/dev/null
if [ -f "$T8/.kit.toml" ] && grep -q '^\[modules\]' "$T8/.kit.toml" \
  && grep -qE '^board[[:space:]]*=' "$T8/.kit.toml" && grep -qE '^cosmetic[[:space:]]*=' "$T8/.kit.toml"; then
  ok "fresh adopt seeds a starter .kit.toml with a [modules] section"
else
  no "fresh adopt did not seed .kit.toml with the expected [modules] section"
fi

# 13. That same fresh adopt wires the kit-root-default-enabled modules' hooks into the
# project's settings.json (board/session/advisor default true; cosmetic defaults false).
W13="$(wired_hooks "$T8/.claude/settings.json")"
if { trap '' PIPE; printf '%s\n' "$W13" 2>/dev/null || :; } | grep -qx backlog-stage.sh && { trap '' PIPE; printf '%s\n' "$W13" 2>/dev/null || :; } | grep -qx context-hints.sh \
  && ! { trap '' PIPE; printf '%s\n' "$W13" 2>/dev/null || :; } | grep -qx auto-format.sh; then
  ok "fresh adopt wires kit-root-default-enabled modules' hooks (board/advisor in, cosmetic out)"
else
  no "fresh adopt wired the wrong hook set: [$W13]"
fi

# 14. --with on a FRESH repo seeds the named modules true and wires their hooks even when the
# kit-root default is false (cosmetic defaults false; --with cosmetic turns it on for THIS repo).
T9="$(newrepo)"
bash lib/adopt.sh --with cosmetic "$T9" >/dev/null
if grep -qx 'cosmetic = true' "$T9/.kit.toml" \
  && { trap '' PIPE; printf '%s\n' "$(wired_hooks "$T9/.claude/settings.json")" 2>/dev/null || :; } | grep -qx auto-format.sh; then
  ok "--with cosmetic on a fresh repo seeds cosmetic=true and wires its hook"
else
  no "--with cosmetic did not seed/wire cosmetic for a fresh repo"
fi

# 15. THE Done= proof: a project .kit.toml [modules] board=false results in that project NOT
# wiring the board hook (backlog-stage.sh), verified via its settings.json.
T10="$(newrepo)"
bash lib/adopt.sh "$T10" >/dev/null
W15_BEFORE="$(wired_hooks "$T10/.claude/settings.json")"
{ trap '' PIPE; printf '%s\n' "$W15_BEFORE" 2>/dev/null || :; } | grep -qx backlog-stage.sh \
  && ok "precondition: board's hook is wired before the override (kit-root default board=true)" \
  || no "precondition failed: board's hook was never wired to begin with"
sed -i.bak 's/^board = true$/board = false/' "$T10/.kit.toml" && rm -f "$T10/.kit.toml.bak"
grep -qx 'board = false' "$T10/.kit.toml" || no "test setup: could not flip board=false in $T10/.kit.toml"
bash lib/adopt.sh --refresh "$T10" >/dev/null
W15_AFTER="$(wired_hooks "$T10/.claude/settings.json")"
if ! { trap '' PIPE; printf '%s\n' "$W15_AFTER" 2>/dev/null || :; } | grep -qx backlog-stage.sh; then
  ok "DONE=: project .kit.toml [modules] board=false -> board's hook is NOT wired (settings.json)"
else
  no "DONE=: board=false in .kit.toml did not stop board's hook from being wired"
fi
# session's hook must be untouched by the board-only edit (surgical re-wiring, not a full reset).
if { trap '' PIPE; printf '%s\n' "$W15_AFTER" 2>/dev/null || :; } | grep -qx context-readiness.sh; then
  ok "re-wiring after a board=false edit leaves the still-enabled session module's hooks wired"
else
  no "re-wiring after a board=false edit dropped an unrelated still-enabled module's hooks"
fi

# 16. THE Done= proof, second clause: a [ledger] override in the project .kit.toml is honored
# by a command reading it (the resolver from goal 01, exercised end-to-end through a real
# adopted project directory rather than a synthetic fixture).
T11="$(newrepo)"
bash lib/adopt.sh "$T11" >/dev/null
printf '\n[ledger]\nlocation = "isolated"\n' >> "$T11/.kit.toml"
KIT_REPO_ROOT="$(pwd)"
LEDGER_VAL="$(KIT_CONFIG_ROOT="$KIT_REPO_ROOT" KIT_PROJECT_ROOT="$T11" bash -c "source '$KIT_REPO_ROOT/lib/config/kit-config.sh'; kit_config_get ledger.location")"
if [ "$LEDGER_VAL" = "isolated" ]; then
  ok "DONE=: a [ledger] override in the project .kit.toml is honored by the resolver"
else
  no "DONE=: [ledger] override was not honored (got [$LEDGER_VAL], want isolated)"
fi

# 17. --with is ignored (never clobbers) once <project>/.kit.toml already exists.
bash lib/adopt.sh --with cosmetic "$T11" >/dev/null 2>&1
if ! grep -qx 'cosmetic = true' "$T11/.kit.toml"; then
  ok "--with is ignored once .kit.toml already exists (never overwritten)"
else
  no "--with clobbered an existing .kit.toml"
fi

# 18. Idempotent re-run after a config edit: re-running adopt again with NO further edits is a
# clean no-op on the module wiring (settled state is stable, not re-churned every run).
git -C "$T10" init -q >/dev/null 2>&1 || true
git -C "$T10" add -A && git -C "$T10" -c user.email=t@t -c user.name=t commit -qm settle >/dev/null
bash lib/adopt.sh --refresh "$T10" >/dev/null
if git -C "$T10" diff --quiet; then
  ok "re-running adopt --refresh with an unchanged .kit.toml is a clean no-op on module wiring"
else
  no "re-running adopt --refresh churned settings.json with no .kit.toml change"
fi

rm -rf "$T8" "$T9" "$T10" "$T11"
fi

# --- SPEC-252: [output] style -> project output-styles/ + settings.json outputStyle ---
# The operator kit.toml is fenced off (a real operator may set output.style); only the
# kit-root default ("") and the project .kit.toml speak here.
export KIT_CONFIG_OPERATOR="$(mktemp -d)"
T12="$(newrepo)"
bash lib/adopt.sh "$T12" >/dev/null
if [ ! -f "$T12/.claude/output-styles/adhd.md" ] \
  && { [ ! -f "$T12/.claude/settings.json" ] || [ "$(jq -r '.outputStyle // ""' "$T12/.claude/settings.json")" = "" ]; }; then
  ok "kit-root default style=\"\" leaves the project's outputStyle and output-styles/ untouched"
else
  no "empty output.style still wrote a style into the project"
fi
printf '\n[output]\nstyle = "adhd"\n' >> "$T12/.kit.toml"
bash lib/adopt.sh --refresh "$T12" >/dev/null
if [ -f "$T12/.claude/output-styles/adhd.md" ] && cmp -s output-styles/adhd.md "$T12/.claude/output-styles/adhd.md" \
  && [ "$(jq -r '.outputStyle' "$T12/.claude/settings.json")" = "adhd" ]; then
  ok "project .kit.toml [output] style=adhd copies the kit style in and sets outputStyle"
else
  no "output.style=adhd did not wire the style file + settings key"
fi
git -C "$T12" add -A
git -C "$T12" -c user.email=t@t -c user.name=t commit -qm styled
bash lib/adopt.sh --refresh "$T12" >/dev/null
if git -C "$T12" diff --quiet; then
  ok "re-running adopt --refresh with an unchanged output.style is a clean no-op"
else
  no "re-running adopt --refresh churned the style file or settings.json"
fi
# Negative control (name the kit does not ship): the key is set, nothing is copied.
sed -i.bak 's/^style = "adhd"/style = "Explanatory"/' "$T12/.kit.toml" && rm -f "$T12/.kit.toml.bak"
bash lib/adopt.sh --refresh "$T12" >/dev/null
if [ "$(jq -r '.outputStyle' "$T12/.claude/settings.json")" = "Explanatory" ] \
  && [ ! -f "$T12/.claude/output-styles/Explanatory.md" ]; then
  ok "a style the kit does not ship sets the key only (nothing copied)"
else
  no "non-kit style name mishandled"
fi
# A name with a path component is refused: nothing copied, the key left as it was.
sed -i.bak 's#^style = "Explanatory"#style = "../../etc/passwd"#' "$T12/.kit.toml" && rm -f "$T12/.kit.toml.bak"
bash lib/adopt.sh --refresh "$T12" >/dev/null 2>&1
if [ "$(jq -r '.outputStyle' "$T12/.claude/settings.json")" = "Explanatory" ] \
  && [ ! -e "$T12/.claude/output-styles/../../etc/passwd" ] && [ ! -e "$T12/etc/passwd" ]; then
  ok "output.style with a path component is refused (key unchanged, nothing written)"
else
  no "path-shaped output.style was not refused"
fi
# Hook wiring survives the style write (the merge is targeted, never a file rewrite).
if jq -e '.hooks | length > 0' "$T12/.claude/settings.json" >/dev/null 2>&1; then
  ok "setting outputStyle preserves the hook-module wiring in settings.json"
else
  no "outputStyle write dropped the hooks block"
fi
rm -rf "$T12" "$KIT_CONFIG_OPERATOR"; unset KIT_CONFIG_OPERATOR

# --- --single-source: one repo, one agent guide (CLAUDE.md folds into AGENTS.md) ---

# 19. CLAUDE.md only -> git mv to AGENTS.md, CLAUDE.md becomes a one-line @AGENTS.md pointer,
# the operate-contract block lands in AGENTS.md (not the one-liner), original content kept.
T13="$(newrepo)"
printf '# Repo\n\nORIGINAL-CLAUDE-CONTENT\n' > "$T13/CLAUDE.md"
bash lib/adopt.sh --single-source "$T13" >/dev/null
if [ "$(cat "$T13/CLAUDE.md")" = "@AGENTS.md" ] && grep -q ORIGINAL-CLAUDE-CONTENT "$T13/AGENTS.md" \
  && grep -qxF '<!-- kit:adopt -->' "$T13/AGENTS.md" && ! grep -q '^@AGENTS.md$' "$T13/AGENTS.md"; then
  ok "--single-source folds an existing CLAUDE.md into AGENTS.md and leaves a one-line pointer"
else
  no "--single-source did not fold CLAUDE.md into AGENTS.md correctly"
fi

# 20. Idempotent rerun: a second --single-source pass is a clean no-op.
cp "$T13/AGENTS.md" "$T13/AGENTS.before"
cp "$T13/CLAUDE.md" "$T13/CLAUDE.before"
OUT20="$(bash lib/adopt.sh --single-source "$T13" 2>&1)"
if cmp -s "$T13/AGENTS.md" "$T13/AGENTS.before" && cmp -s "$T13/CLAUDE.md" "$T13/CLAUDE.before" \
  && echo "$OUT20" | grep -q 'already single-source'; then
  ok "--single-source rerun is a clean idempotent no-op and reports already single-source"
else
  no "--single-source rerun changed files or did not report already single-source"
fi
rm -f "$T13/AGENTS.before" "$T13/CLAUDE.before"

# 21. Both exist and differ -> refuse, exit 1, write nothing.
T14="$(newrepo)"
printf 'AGENTS-CONTENT\n' > "$T14/AGENTS.md"
printf 'CLAUDE-CONTENT-NOT-A-POINTER\n' > "$T14/CLAUDE.md"
if bash lib/adopt.sh --single-source "$T14" >/dev/null 2>/tmp/single-source-t14.err; then
  no "--single-source should refuse when AGENTS.md and CLAUDE.md both exist and differ"
elif grep -q AGENTS-CONTENT "$T14/AGENTS.md" && grep -q CLAUDE-CONTENT-NOT-A-POINTER "$T14/CLAUDE.md" \
  && grep -q 'AGENTS.md' /tmp/single-source-t14.err && grep -q 'CLAUDE.md' /tmp/single-source-t14.err; then
  ok "--single-source refuses (exit 1, writes nothing) when both files exist and differ, naming both"
else
  no "--single-source did not refuse cleanly on a real conflict"
fi
rm -f /tmp/single-source-t14.err

# 22. Neither exists -> refuse, exit 1.
T15="$(newrepo)"
if bash lib/adopt.sh --single-source "$T15" >/dev/null 2>&1; then
  no "--single-source should refuse when neither AGENTS.md nor CLAUDE.md exists"
else
  ok "--single-source refuses (exit 1) when neither AGENTS.md nor CLAUDE.md exists"
fi

# 23. --single-source already in single-source shape (both exist, CLAUDE.md is exactly
# @AGENTS.md) is a no-op even on a repo that never went through case 1.
T16="$(newrepo)"
bash lib/adopt.sh "$T16" >/dev/null   # normal adopt: block lands in CLAUDE.md
printf '@AGENTS.md\n' > "$T16/CLAUDE.md"  # hand-fold it into single-source shape
OUT23="$(bash lib/adopt.sh --single-source "$T16" 2>&1)"
if [ "$(cat "$T16/CLAUDE.md")" = "@AGENTS.md" ] && grep -qxF '<!-- kit:adopt -->' "$T16/AGENTS.md" \
  && echo "$OUT23" | grep -q 'already single-source'; then
  ok "--single-source recognizes an already-single-source repo and reports it"
else
  no "--single-source mishandled an already-single-source repo"
fi

# --- adopt.single_source knob (root-only): flag beats the knob either direction ---
#
# adopt.sh resolves its OWN kit-root kit.toml as "the dev checkout first" (SRC_ROOT/kit.toml,
# same lookup as src_agents), ahead of KIT_CONFIG_ROOT -- so exercising the knob means
# editing this checkout's own kit.toml for the duration of the test, restored after (trap
# covers a mid-test failure too).
KIT_TOML_LIVE="kit.toml"
KIT_TOML_BAK="$(mktemp)"
cp "$KIT_TOML_LIVE" "$KIT_TOML_BAK"
trap 'cp "$KIT_TOML_BAK" "$KIT_TOML_LIVE"; rm -f "$KIT_TOML_BAK"' EXIT

set_single_source_knob() {
  awk -v v="$1" '{ if ($0 ~ /^single_source = /) print "single_source = " v; else print }' "$KIT_TOML_BAK" > "$KIT_TOML_LIVE"
}

# 24. Knob true, no flag: adopt.sh folds CLAUDE.md into AGENTS.md as if --single-source
# had been passed, and names the knob in its one-line report.
set_single_source_knob true
T17="$(newrepo)"
printf '# Repo\n\nKNOB-TRUE-CONTENT\n' > "$T17/CLAUDE.md"
OUT24="$(bash lib/adopt.sh "$T17" 2>&1)"
if [ "$(cat "$T17/CLAUDE.md")" = "@AGENTS.md" ] && grep -q KNOB-TRUE-CONTENT "$T17/AGENTS.md" \
  && grep -qxF '<!-- kit:adopt -->' "$T17/AGENTS.md" \
  && echo "$OUT24" | grep -q 'single-source mode on (adopt.single_source knob)'; then
  ok "adopt.single_source=true with no flag folds CLAUDE.md into AGENTS.md and names the knob"
else
  no "adopt.single_source=true with no flag did not fold (or did not name the knob)"
fi

# 25. Knob true, --no-single-source: the flag overrides the knob back off; normal two-file
# adopt runs (block lands in CLAUDE.md, CLAUDE.md is not folded, AGENTS.md carries no block).
T18="$(newrepo)"
printf '# Repo\n\nKNOB-OVERRIDE-CONTENT\n' > "$T18/CLAUDE.md"
OUT25="$(bash lib/adopt.sh --no-single-source "$T18" 2>&1)"
agents_untouched=1
grep -qxF '<!-- kit:adopt -->' "$T18/AGENTS.md" 2>/dev/null && agents_untouched=0
if grep -q KNOB-OVERRIDE-CONTENT "$T18/CLAUDE.md" && grep -qxF '<!-- kit:adopt -->' "$T18/CLAUDE.md" \
  && [ "$agents_untouched" -eq 1 ] && ! echo "$OUT25" | grep -q 'single-source mode on'; then
  ok "--no-single-source overrides a true knob back off (normal two-file adopt runs)"
else
  no "--no-single-source did not override the true knob"
fi

# 26. Knob false, --single-source: unchanged existing behaviour (the flag still folds).
set_single_source_knob false
T19="$(newrepo)"
printf '# Repo\n\nKNOB-FALSE-FLAG-CONTENT\n' > "$T19/CLAUDE.md"
OUT26="$(bash lib/adopt.sh --single-source "$T19" 2>&1)"
if [ "$(cat "$T19/CLAUDE.md")" = "@AGENTS.md" ] && grep -q KNOB-FALSE-FLAG-CONTENT "$T19/AGENTS.md" \
  && grep -qxF '<!-- kit:adopt -->' "$T19/AGENTS.md" \
  && echo "$OUT26" | grep -q 'single-source mode on (--single-source flag)'; then
  ok "adopt.single_source=false plus --single-source still folds (flag beats a false knob)"
else
  no "adopt.single_source=false plus --single-source did not fold"
fi

cp "$KIT_TOML_BAK" "$KIT_TOML_LIVE"; rm -f "$KIT_TOML_BAK"
trap - EXIT

rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6" "$T7" "$T13" "$T14" "$T15" "$T16" "$T17" "$T18" "$T19"
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
