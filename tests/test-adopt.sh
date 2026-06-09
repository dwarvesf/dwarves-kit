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

rm -rf "$T1" "$T2" "$T3" "$T4"
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
