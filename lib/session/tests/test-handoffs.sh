#!/usr/bin/env bash
# test-handoffs.sh -- unit test for lib/session/handoffs.sh, the kit:start
# open-handoffs lister.
#
# Fixtures are built at run time under mktemp, not committed: a fixture
# under `.claude/handoffs/` cannot be committed at all (repo-wide
# `**/.claude/` gitignore), and file mtime (which the age computation reads)
# is never preserved through a git checkout anyway, so a static fixture
# could not give a deterministic age either way.
#
# Run: bash lib/session/tests/test-handoffs.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"     # lib/session
HO="${DIR}/handoffs.sh"

# BSD `date -v` (macOS) vs GNU `date -d` (Linux), same fallback shape used
# elsewhere in this repo for cross-platform date/stat handling.
stamp_days_ago() { # <N>
  if date -v-1d +%Y%m%d%H%M >/dev/null 2>&1; then
    date -v-"$1"d +%Y%m%d%H%M
  else
    date -d "$1 days ago" +%Y%m%d%H%M
  fi
}

REPO="$(mktemp -d)"
mkdir -p "$REPO/_meta/handoffs/done" "$REPO/.claude/handoffs"

cat > "$REPO/_meta/handoffs/with-next.md" <<'EOF'
# Handoff: migration cutover

## Context
Started the cutover, paused before the DNS swap.

## Next
Flip the DNS record and verify the health check before EOD.

## Notes
Rollback plan is in the runbook.
EOF

cat > "$REPO/.claude/handoffs/no-next.md" <<'EOF'
# Handoff: quick note

## Summary
Just parked a link for later, nothing pending.
EOF

cat > "$REPO/_meta/handoffs/done/decoy.md" <<'EOF'
# Handoff: already consumed

## Next
This must never show up: it is archived under done/.
EOF

touch -t "$(stamp_days_ago 10)" "$REPO/_meta/handoffs/with-next.md"
touch -t "$(stamp_days_ago 2)"  "$REPO/.claude/handoffs/no-next.md"
touch -t "$(stamp_days_ago 1)"  "$REPO/_meta/handoffs/done/decoy.md"

EMPTY="$(mktemp -d)"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] golden path: 2 lines + count, oldest (with-next.md) first"
out="$(bash "$HO" list --repo "$REPO")"
n=$(printf '%s\n' "$out" | grep -c .)
if [[ "$n" -eq 3 ]]; then ok "3 lines (2 handoffs + count)"; else no "expected 3 lines, got $n: $out"; fi

first="$(printf '%s\n' "$out" | sed -n 1p)"
if [[ "$first" == *"with-next.md"* && "$first" =~ ^[0-9]+d ]]; then ok "oldest first: $first"; else no "expected with-next.md first, got: $first"; fi

echo "[2] excerpt: first Next line, truncated"
if [[ "$first" == *"next: Flip the DNS record and verify the health check before EOD."* ]]; then
  ok "excerpt matches the Next line"
else
  no "excerpt wrong: $first"
fi

echo "[3] no-Next fallback"
second="$(printf '%s\n' "$out" | sed -n 2p)"
if [[ "$second" == *"no-next.md"*"(no Next section)"* ]]; then ok "fallback excerpt: $second"; else no "expected fallback, got: $second"; fi

echo "[4] count line"
last="$(printf '%s\n' "$out" | tail -1)"
if [[ "$last" == "2 open handoffs" ]]; then ok "count: $last"; else no "expected '2 open handoffs', got: $last"; fi

echo "[5] done/ decoy is absent"
if [[ "$out" != *"decoy.md"* ]]; then ok "decoy excluded"; else no "decoy leaked into output: $out"; fi

echo "[6] --days filters out the newer handoff"
dout="$(bash "$HO" list --repo "$REPO" --days 5)"
dn=$(printf '%s\n' "$dout" | grep -c .)
if [[ "$dn" -eq 2 && "$dout" == *"with-next.md"* && "$dout" != *"no-next.md"* ]]; then
  ok "days filter narrows to the stale one: $dout"
else
  no "days filter wrong: $dout"
fi

echo "[7] NC empty repo: honest 'no handoffs', exit 0"
eout="$(bash "$HO" list --repo "$EMPTY")"
erc=$?
if [[ "$eout" == "no handoffs" && $erc -eq 0 ]]; then ok "no handoffs, exit 0"; else no "expected 'no handoffs'/exit 0, got: $eout (rc=$erc)"; fi

echo "[8] NC unknown subcommand: usage error, exit 64"
set +e
uerr="$(bash "$HO" bogus 2>&1)"
urc=$?
set -e 2>/dev/null || true
if [[ $urc -eq 64 ]]; then ok "exit 64 on unknown subcommand"; else no "expected exit 64, got rc=$urc: $uerr"; fi

echo
if [[ $fail -eq 0 ]]; then
  echo "smoke: all $pass passed"
  exit 0
else
  echo "smoke: $fail FAILED, $pass passed" >&2
  exit 1
fi
