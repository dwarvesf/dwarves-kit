#!/usr/bin/env bash
# test-adopt.sh -- lib/adopt.sh: fresh adopt, idempotency, --check, no-clobber.
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

newrepo() { local d; d="$(mktemp -d)"; git -C "$d" init -q; echo "$d"; }

# The operator kit.toml is fenced off for the whole suite: a real operator may have
# adopt.single_source or output.style turned on, and every case below asserts the kit-root
# default. Cases that need their own operator file re-export the variable and restore this one.
NO_OPERATOR="$(mktemp -d)"; export KIT_CONFIG_OPERATOR="$NO_OPERATOR"

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

# 4. no-clobber: a pre-existing repo-authored AGENTS.md is never overwritten
T3="$(newrepo)"
printf 'SENTINEL-DO-NOT-CLOBBER\n' > "$T3/AGENTS.md"
bash lib/adopt.sh "$T3" >/dev/null
if grep -q SENTINEL-DO-NOT-CLOBBER "$T3/AGENTS.md"; then ok "existing repo-authored AGENTS.md is not clobbered"; else no "AGENTS.md was clobbered"; fi

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

# 10. --refresh never overwrites an edited AGENTS.md or the proof marker (documented invariant).
T7="$(newrepo)"
bash lib/adopt.sh "$T7" >/dev/null
printf 'AGENTS-SENTINEL\n' >> "$T7/AGENTS.md"
printf 'MARKER-SENTINEL\n' >> "$T7/docs/verification/README.md"
bash lib/adopt.sh --refresh "$T7" >/dev/null
if grep -q AGENTS-SENTINEL "$T7/AGENTS.md" && grep -q MARKER-SENTINEL "$T7/docs/verification/README.md"; then
  ok "--refresh preserves an edited AGENTS.md + proof marker (never overwritten)"
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

# 15b. Migrating a pre-anchor settings.json (same hooks, no anchor-root.sh prefix) is a real
# rewrite, so adopt reports "updated", never "already adopted, no-op". A second run is the no-op.
T10B="$(newrepo)"
bash lib/adopt.sh "$T10B" >/dev/null
sed -i.bak 's#\$HOME/\.claude/dwarves-kit/hooks/anchor-root\.sh ##' "$T10B/.claude/settings.json" && rm -f "$T10B/.claude/settings.json.bak"
grep -q 'anchor-root' "$T10B/.claude/settings.json" && no "test setup: could not strip the anchor prefix in $T10B"
OUT15B="$(bash lib/adopt.sh "$T10B" 2>&1 | tail -1)"
if grep -q 'anchor-root' "$T10B/.claude/settings.json" && printf '%s\n' "$OUT15B" | grep -q '(updated)$'; then
  ok "unwrapped -> wrapped hook migration re-adds the anchor and reports updated"
else
  no "unwrapped -> wrapped hook migration misreported: [$OUT15B]"
fi
if bash lib/adopt.sh "$T10B" 2>&1 | tail -1 | grep -q 'already adopted, no-op'; then
  ok "a re-run after the anchor migration is a no-op"
else
  no "a re-run after the anchor migration was not a no-op"
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
rm -rf "$T12" "$KIT_CONFIG_OPERATOR"; export KIT_CONFIG_OPERATOR="$NO_OPERATOR"

# --- --single-source: one repo, one agent guide (CLAUDE.md folds into AGENTS.md) ---

# 19. CLAUDE.md only -> git mv to AGENTS.md, CLAUDE.md becomes a one-line @AGENTS.md pointer,
# AGENTS.md is the pointer plus the folded notes (the pointer replaces the block), content kept.
T13="$(newrepo)"
printf '# Repo\n\nORIGINAL-CLAUDE-CONTENT\n' > "$T13/CLAUDE.md"
bash lib/adopt.sh --single-source "$T13" >/dev/null
if [ "$(cat "$T13/CLAUDE.md")" = "@AGENTS.md" ] && grep -q ORIGINAL-CLAUDE-CONTENT "$T13/AGENTS.md" \
  && head -n 1 "$T13/AGENTS.md" | grep -qF 'kit:agents-pointer' && ! grep -q '^@AGENTS.md$' "$T13/AGENTS.md"; then
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

# 22. Neither exists -> AGENTS.md is the pointer alone, CLAUDE.md the one-line import, exit 0.
T15="$(newrepo)"
if bash lib/adopt.sh --single-source "$T15" >/dev/null 2>&1 && cmp -s "$T15/AGENTS.md" lib/adopt/AGENTS.pointer.md \
  && [ "$(cat "$T15/CLAUDE.md")" = "@AGENTS.md" ]; then
  ok "--single-source with neither file writes the pointer plus a one-line CLAUDE.md import"
else
  no "--single-source with neither file"
fi

# 23. --single-source already in single-source shape (both exist, CLAUDE.md is exactly
# @AGENTS.md) is a no-op even on a repo that never went through case 1.
T16="$(newrepo)"
bash lib/adopt.sh "$T16" >/dev/null   # normal adopt: block lands in CLAUDE.md
printf '@AGENTS.md\n' > "$T16/CLAUDE.md"  # hand-fold it into single-source shape
OUT23="$(bash lib/adopt.sh --single-source "$T16" 2>&1)"
if [ "$(cat "$T16/CLAUDE.md")" = "@AGENTS.md" ] && head -n 1 "$T16/AGENTS.md" | grep -qF 'kit:agents-pointer' \
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
# The knob is set in a temp COPY of the kit tree (lib, kit.toml, AGENTS.md): the tracked kit.toml
# is never edited, so a concurrent run cannot see a flipped knob.
KT="$(mktemp -d)"; mkdir "$KT/lib"; cp lib/adopt.sh "$KT/lib/"; cp -R lib/adopt lib/config "$KT/lib/"
cp AGENTS.md "$KT/"; cp kit.toml "$KT/kit.toml.orig"
set_single_source_knob() {
  awk -v v="$1" '{ if ($0 ~ /^single_source = /) print "single_source = " v; else print }' "$KT/kit.toml.orig" > "$KT/kit.toml"
}

# 24. Knob true, no flag: adopt.sh folds CLAUDE.md into AGENTS.md as if --single-source
# had been passed, and names the knob in its one-line report.
set_single_source_knob true
T17="$(newrepo)"
printf '# Repo\n\nKNOB-TRUE-CONTENT\n' > "$T17/CLAUDE.md"
OUT24="$(bash "$KT/lib/adopt.sh" "$T17" 2>&1)"
if [ "$(cat "$T17/CLAUDE.md")" = "@AGENTS.md" ] && grep -q KNOB-TRUE-CONTENT "$T17/AGENTS.md" \
  && head -n 1 "$T17/AGENTS.md" | grep -qF 'kit:agents-pointer' \
  && echo "$OUT24" | grep -q 'single-source mode on (adopt.single_source knob)'; then
  ok "adopt.single_source=true with no flag folds CLAUDE.md into AGENTS.md and names the knob"
else
  no "adopt.single_source=true with no flag did not fold (or did not name the knob)"
fi

# 25. Knob true, --no-single-source: the flag overrides the knob back off; normal two-file
# adopt runs (block lands in CLAUDE.md, CLAUDE.md is not folded, AGENTS.md carries no block).
T18="$(newrepo)"
printf '# Repo\n\nKNOB-OVERRIDE-CONTENT\n' > "$T18/CLAUDE.md"
OUT25="$(bash "$KT/lib/adopt.sh" --no-single-source "$T18" 2>&1)"
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
OUT26="$(bash "$KT/lib/adopt.sh" --single-source "$T19" 2>&1)"
if [ "$(cat "$T19/CLAUDE.md")" = "@AGENTS.md" ] && grep -q KNOB-FALSE-FLAG-CONTENT "$T19/AGENTS.md" \
  && head -n 1 "$T19/AGENTS.md" | grep -qF 'kit:agents-pointer' \
  && echo "$OUT26" | grep -q 'single-source mode on (--single-source flag)'; then
  ok "adopt.single_source=false plus --single-source still folds (flag beats a false knob)"
else
  no "adopt.single_source=false plus --single-source did not fold"
fi


# ------------------------------------------------------------------------------------------
# SPEC-371: adopt writes a small pointer AGENTS.md. Decision by hash: absent -> pointer; equals
# the pointer -> silent; known old copy -> notice, swapped only by --refresh --swap-agents;
# anything else -> left alone with a drift line. Every case runs against temp repos.
# ------------------------------------------------------------------------------------------
POINTER="lib/adopt/AGENTS.pointer.md"
KNOWN="lib/adopt/agents-known.sha256"
sha_of() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1"; else sha256sum < "$1"; fi | cut -d' ' -f1; }
old_kit_copy() { git show "$(git log --format=%H -- AGENTS.md | tail -n 1):AGENTS.md"; }
dcount() { diff "$1" "$2" | grep -c '^[<>]'; }
seed_old() { local d; d="$(newrepo)"; old_kit_copy > "$d/AGENTS.md"; echo "$d"; }

# T1 / AC-1 / AC-2: a fresh adopt writes a pointer at or under the cap that names the contract.
P1="$(newrepo)"; bash lib/adopt.sh "$P1" >/dev/null
if [ "$(wc -c < "$P1/AGENTS.md")" -le 1200 ] && grep -qF '~/.claude/dwarves-kit/AGENTS.md' "$P1/AGENTS.md" \
  && head -n 1 "$P1/AGENTS.md" | grep -qF 'kit:agents-pointer' && cmp -s "$P1/AGENTS.md" "$POINTER"; then
  ok "fresh adopt writes the pointer: at or under 1200 bytes, names the installed contract, has the marker"
else
  no "fresh adopt did not write a small pointer that names the contract"
fi

# T2 / AC-3: an edited AGENTS.md survives --refresh and --refresh --swap-agents byte for byte.
P2="$(newrepo)"; bash lib/adopt.sh "$P2" >/dev/null
printf 'LOCAL-EDIT-SENTINEL\n' >> "$P2/AGENTS.md"; cp "$P2/AGENTS.md" "$P2/AGENTS.before"
bash lib/adopt.sh --refresh "$P2" >/dev/null; c1=1; cmp -s "$P2/AGENTS.md" "$P2/AGENTS.before" && c1=0
bash lib/adopt.sh --refresh --swap-agents "$P2" >/dev/null; c2=1; cmp -s "$P2/AGENTS.md" "$P2/AGENTS.before" && c2=0
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && grep -q LOCAL-EDIT-SENTINEL "$P2/AGENTS.md"; then
  ok "edited AGENTS.md survives refresh and swap"
else
  no "edited AGENTS.md survives refresh and swap (c1=$c1 c2=$c2)"
fi

# T3 / AC-4: a repo-authored file survives all modes; the line gives its own line count, no diff count.
P3="$(newrepo)"; printf '# Trading\n\nOur own rules.\nSecond rule.\n' > "$P3/AGENTS.md"; cp "$P3/AGENTS.md" "$P3/AGENTS.before"
O3="$(bash lib/adopt.sh "$P3" 2>&1; bash lib/adopt.sh --refresh "$P3" 2>&1; bash lib/adopt.sh --refresh --swap-agents "$P3" 2>&1)"
if cmp -s "$P3/AGENTS.md" "$P3/AGENTS.before" && echo "$O3" | grep -qF 'AGENTS.md is not a kit file, 4 lines (left alone)' \
  && ! echo "$O3" | grep -q 'AGENTS.md differs'; then
  ok "not a kit file: left byte-identical, reports its own line count"
else
  no "not a kit file case (repo-authored AGENTS.md)"
fi

# T4 / AC-5: an unmodified old kit copy is swapped only by --refresh --swap-agents.
P4="$(seed_old)"; cp "$P4/AGENTS.md" "$P4/AGENTS.before"
O4a="$(bash lib/adopt.sh "$P4" 2>&1)"; a=1; cmp -s "$P4/AGENTS.md" "$P4/AGENTS.before" && a=0
O4b="$(bash lib/adopt.sh --refresh "$P4" 2>&1)"; b=1; cmp -s "$P4/AGENTS.md" "$P4/AGENTS.before" && b=0
bash lib/adopt.sh --refresh --swap-agents "$P4" >/dev/null; c=1; cmp -s "$P4/AGENTS.md" "$POINTER" && c=0
if [ "$a" -eq 0 ] && [ "$b" -eq 0 ] && [ "$c" -eq 0 ] \
  && echo "$O4a" | grep -qF 'old kit copy, run --refresh --swap-agents to replace' \
  && echo "$O4b" | grep -qF 'old kit copy, run --refresh --swap-agents to replace'; then
  ok "old copy swap needs flag"
else
  no "old copy swap needs flag (plain=$a refresh=$b swap=$c)"
fi

# T4b: a file equal to the current pointer is a silent no-op in every mode.
P4b="$(newrepo)"; bash lib/adopt.sh "$P4b" >/dev/null
O4c="$(bash lib/adopt.sh "$P4b" 2>&1; bash lib/adopt.sh --refresh "$P4b" 2>&1; bash lib/adopt.sh --refresh --swap-agents "$P4b" 2>&1)"
if cmp -s "$P4b/AGENTS.md" "$POINTER" && ! echo "$O4c" | grep -q 'AGENTS.md'; then
  ok "current pointer is a silent no-op"
else
  no "current pointer printed something about AGENTS.md or changed"
fi

# T4c / AC-4: drift is counted against the MATCHED template.
P5="$(newrepo)"; bash lib/adopt.sh "$P5" >/dev/null; printf 'EDIT-ONE\nEDIT-TWO\n' >> "$P5/AGENTS.md"
n5="$(dcount "$POINTER" "$P5/AGENTS.md")"
O5="$(bash lib/adopt.sh --refresh "$P5" 2>&1)"
if [ "$n5" = 2 ] && echo "$O5" | grep -qF "AGENTS.md differs from the pointer by 2 lines (left alone)"; then
  ok "drift vs pointer"
else
  no "drift vs pointer (expected 2, count=$n5)"
fi
P6="$(seed_old)"; printf 'EDIT-ONE\n' >> "$P6/AGENTS.md"; cp "$P6/AGENTS.md" "$P6/AGENTS.before"
n6="$(dcount AGENTS.md "$P6/AGENTS.md")"
O6="$(bash lib/adopt.sh --refresh --swap-agents "$P6" 2>&1)"
if echo "$O6" | grep -qF "AGENTS.md differs from the old kit contract by $n6 lines (left alone)" && cmp -s "$P6/AGENTS.md" "$P6/AGENTS.before"; then
  ok "drift vs old contract"
else
  no "drift vs old contract (expected $n6)"
fi

# T5 / AC-5: every committed AGENTS.md version is in the known list. A shallow clone cannot say.
if [ "$(git rev-parse --is-shallow-repository)" != "false" ]; then
  echo "SKIP: shallow clone, history incomplete (known list complete against git log)"
else
  miss=0
  for c in $(git log --format=%H -- AGENTS.md); do
    git cat-file -e "$c:AGENTS.md" 2>/dev/null || continue
    h="$(git show "$c:AGENTS.md" | { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; } | cut -d' ' -f1)"
    grep -q "^$h " "$KNOWN" || { miss=$((miss + 1)); echo "  missing from list: $c"; }
  done
  [ "$miss" -eq 0 ] && ok "known list complete against git log" || no "known list complete against git log ($miss missing; run lib/adopt/known-hashes.sh)"
fi

# T5b / AC-9: known-hashes.sh refuses in a shallow clone and leaves the list unchanged. The
# synthetic repo also proves the script works in a full clone, so the refusal is not a broken setup.
KS="$(mktemp -d)"; mkdir -p "$KS/lib/adopt"; cp lib/adopt/known-hashes.sh "$KS/lib/adopt/"
printf 'KEEP\n' > "$KS/lib/adopt/agents-known.sha256"
git -C "$KS" init -q; printf 'one\n' > "$KS/AGENTS.md"; git -C "$KS" add -A
git -C "$KS" -c user.email=t@t -c user.name=t commit -qm one
printf 'two\n' >> "$KS/AGENTS.md"; git -C "$KS" -c user.email=t@t -c user.name=t commit -qam two
KC="$(mktemp -d)/clone"; git clone -q --depth 1 "file://$KS" "$KC" 2>/dev/null
E5="$(bash "$KC/lib/adopt/known-hashes.sh" 2>&1)"; r5=$?
KFULL="$(bash "$KS/lib/adopt/known-hashes.sh" 2>&1)"; rf=$?
if [ "$r5" -ne 0 ] && echo "$E5" | grep -qi 'shallow' && [ "$(cat "$KC/lib/adopt/agents-known.sha256")" = "KEEP" ] \
  && [ "$rf" -eq 0 ] && [ "$(grep -c '^[0-9a-f]\{64\} agents:' "$KS/lib/adopt/agents-known.sha256")" -eq 2 ]; then
  ok "known-hashes refuses shallow"
else
  no "known-hashes refuses shallow (rc=$r5 full-rc=$rf)"
fi

# T6b / AC-11: --swap-agents alone is refused, exit non-zero, nothing written.
P7="$(seed_old)"; cp "$P7/AGENTS.md" "$P7/AGENTS.before"
E7="$(bash lib/adopt.sh --swap-agents "$P7" 2>&1)"; r7=$?
if [ "$r7" -ne 0 ] && echo "$E7" | grep -qF -- '--refresh' && cmp -s "$P7/AGENTS.md" "$P7/AGENTS.before" && [ ! -f "$P7/CLAUDE.md" ]; then
  ok "swap-agents alone refused"
else
  no "swap-agents alone refused (rc=$r7)"
fi

# T6c / AC-11: --dry-run --refresh --swap-agents plans the swap and writes nothing.
O8="$(bash lib/adopt.sh --dry-run --refresh --swap-agents "$P7" 2>&1)"
if echo "$O8" | grep -qF 'would swap AGENTS.md' && cmp -s "$P7/AGENTS.md" "$P7/AGENTS.before" && [ ! -f "$P7/CLAUDE.md" ]; then
  ok "dry-run swap plans only"
else
  no "dry-run swap plans only"
fi

# T7: --single-source never swaps or reports on an AGENTS.md that already exists, even a known old
# copy under --swap-agents (its text stays a byte-identical prefix; only the existing operate-contract
# block is appended); a CLAUDE.md-only repo gets the pointer plus its folded notes.
P9="$(newrepo)"; printf '# Repo\n\nSINGLE-SOURCE-CONTENT\n' > "$P9/CLAUDE.md"
O9="$(bash lib/adopt.sh --single-source "$P9" 2>&1)"; r9=$?
P10="$(newrepo)"; old_kit_copy > "$P10/AGENTS.md"; printf '@AGENTS.md\n' > "$P10/CLAUDE.md"; cp "$P10/AGENTS.md" "$P10/AGENTS.before"
O10="$(bash lib/adopt.sh --single-source --refresh --swap-agents "$P10" 2>&1)"; r10=$?
if ! echo "$O10" | grep -qE 'old kit copy|swapped|differs|not a kit file' && ! echo "$O9" | grep -q 'AGENTS.md:' \
  && head -c "$(wc -c < "$P10/AGENTS.before")" "$P10/AGENTS.md" | cmp -s - "$P10/AGENTS.before" && ! grep -q 'kit:agents-pointer' "$P10/AGENTS.md" \
  && head -n 1 "$P9/AGENTS.md" | grep -qF 'kit:agents-pointer' && grep -q SINGLE-SOURCE-CONTENT "$P9/AGENTS.md" \
  && [ "$r9" -eq 0 ] && [ "$r10" -eq 0 ]; then
  ok "--single-source leaves an existing AGENTS.md alone (no notice, no swap) and folds CLAUDE.md under the pointer"
else
  no "--single-source AGENTS.md handling (rc=$r9/$r10)"
fi

# Operator config with single_source = true: AC-1 and AC-2 still pass (pointer only, no block).
OPD="$(mktemp -d)"; printf '[adopt]\nsingle_source = true\n' > "$OPD/kit.toml"
P11="$(newrepo)"; KIT_CONFIG_OPERATOR="$OPD" bash lib/adopt.sh "$P11" >/dev/null 2>&1; r12=$?
if [ "$r12" -eq 0 ] && [ "$(wc -c < "$P11/AGENTS.md")" -le 1200 ] && grep -qF '~/.claude/dwarves-kit/AGENTS.md' "$P11/AGENTS.md" \
  && head -n 1 "$P11/AGENTS.md" | grep -qF 'kit:agents-pointer' && [ "$(cat "$P11/CLAUDE.md")" = "@AGENTS.md" ] \
  && KIT_CONFIG_OPERATOR="$OPD" bash lib/adopt.sh --check "$P11" >/dev/null; then
  ok "operator single_source=true: fresh adopt succeeds, pointer under the cap, CLAUDE.md one-line import"
else
  no "operator single_source=true fresh adopt (rc=$r12)"
fi

# Missing pointer template: exit 1, an existing AGENTS.md stays byte-identical, nothing is reported swapped.
MT="$(mktemp -d)"; mkdir "$MT/lib"; cp lib/adopt.sh "$MT/lib/"; cp -R lib/adopt lib/config "$MT/lib/"; rm -f "$MT/lib/adopt/AGENTS.pointer.md"
P12="$(seed_old)"; cp "$P12/AGENTS.md" "$P12/AGENTS.before"
E12="$(bash "$MT/lib/adopt.sh" --refresh --swap-agents "$P12" 2>&1)"; r13=$?
P13="$(newrepo)"; E13="$(bash "$MT/lib/adopt.sh" "$P13" 2>&1)"; r14=$?
if [ "$r13" -eq 1 ] && [ "$r14" -eq 1 ] && cmp -s "$P12/AGENTS.md" "$P12/AGENTS.before" && [ ! -e "$P13/AGENTS.md" ] \
  && ! echo "$E12" | grep -q swapped && echo "$E12" | grep -q 'template missing'; then
  ok "missing pointer template: exit 1, AGENTS.md untouched, nothing reported swapped"
else
  no "missing pointer template (rc=$r13/$r14)"
fi

# Adopting the kit's own tree is refused (source and installed paths).
KO="$(bash lib/adopt.sh . 2>&1)"; r15=$?
if [ "$r15" -eq 1 ] && echo "$KO" | grep -q "own tree" && git diff --quiet -- AGENTS.md; then
  ok "adopt refuses the kit's own tree"
else
  no "adopt refuses the kit's own tree (rc=$r15)"
fi

# CRLF and BOM old copies: not a known hash, so left alone, and the drift line still names the old contract.
P14="$(newrepo)"; old_kit_copy | sed 's/$/\r/' > "$P14/AGENTS.md"; cp "$P14/AGENTS.md" "$P14/AGENTS.before"
P15="$(newrepo)"; { printf '\357\273\277'; old_kit_copy; } > "$P15/AGENTS.md"; cp "$P15/AGENTS.md" "$P15/AGENTS.before"
O14="$(bash lib/adopt.sh --refresh --swap-agents "$P14" 2>&1)"; O15="$(bash lib/adopt.sh --refresh --swap-agents "$P15" 2>&1)"
if cmp -s "$P14/AGENTS.md" "$P14/AGENTS.before" && cmp -s "$P15/AGENTS.md" "$P15/AGENTS.before" \
  && echo "$O14" | grep -q 'differs from the old kit contract' && echo "$O15" | grep -q 'differs from the old kit contract'; then
  ok "CRLF and BOM old copies are left alone with the old-contract drift line"
else
  no "CRLF/BOM old copies"; echo "$O14"; echo "$O15"
fi

# T8 / AC-10: no source AGENTS.md anywhere still adopts and writes the pointer.
NS="$(mktemp -d)"; mkdir -p "$NS/lib"; cp lib/adopt.sh "$NS/lib/"; cp -R lib/adopt lib/config "$NS/lib/"
NSTARGET="$(newrepo)"; NSEMPTY="$(mktemp -d)"
CLAUDE_PLUGIN_ROOT="$NSEMPTY" bash "$NS/lib/adopt.sh" "$NSTARGET" >/dev/null 2>&1; r11=$?
if [ "$r11" -eq 0 ] && cmp -s "$NSTARGET/AGENTS.md" "$POINTER"; then ok "no source contract"; else no "no source contract (rc=$r11)"; fi

# T9: the cost script reads both transcript shapes.
J2="docs/verification/gauntlet/2026-09-01-onboarding-campaign/J2/transcript.jsonl"
OJ="$(bash lib/adopt/onboarding-cost.sh "$J2" 2>&1)"
CCU='"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":1}'
CCY="$(mktemp)"; CCN="$(mktemp)"
printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"id\":\"m1\",$CCU,\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"/h/.claude/dwarves-kit/AGENTS.md\"}}]}}" \
  "{\"type\":\"assistant\",\"message\":{\"id\":\"m1\",$CCU,\"content\":[{\"type\":\"text\",\"text\":\"x\"}]}}" > "$CCY"
printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"id\":\"m1\",$CCU,\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"/h/src/main.js\"}}]}}" > "$CCN"
OY="$(bash lib/adopt/onboarding-cost.sh "$CCY" 2>&1)"; ON="$(bash lib/adopt/onboarding-cost.sh "$CCN" 2>&1)"
if echo "$OJ" | grep -qx 'turns 47' && echo "$OJ" | grep -qx 'tokens 2971254' && echo "$OJ" | grep -qx 'contract read: yes' \
  && echo "$OY" | grep -qx 'contract read: yes' && echo "$OY" | grep -qx 'turns 1' && echo "$OY" | grep -qx 'tokens 116' \
  && echo "$ON" | grep -qx 'contract read: no'; then
  ok "onboarding-cost reads the omp and Claude Code transcript shapes"
else
  no "onboarding-cost transcript shapes"; echo "$OJ"; echo "$OY"; echo "$ON"
fi
rm -f "$CCY" "$CCN"

rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6" "$T7" "$T13" "$T14" "$T15" "$T16" "$T17" "$T18" "$T19"
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
