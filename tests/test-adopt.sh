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

rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6" "$T7"
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
