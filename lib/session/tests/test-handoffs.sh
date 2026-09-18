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

echo "[9] liveness: a file with no cited row IDs is tagged UNCITED"
if [[ "$first" == *"UNCITED (no row IDs; read it)"* ]]; then
  ok "with-next.md tagged UNCITED: $first"
else
  no "expected UNCITED tag, got: $first"
fi

# --- liveness against a real board, read from origin (git fixture) --------
# Proves the liveness check reads _meta/BACKLOG.md as it stands on origin,
# not the (possibly stale/dirty) working tree: the scan repo's local
# BACKLOG.md below is deliberately the INVERSE of origin's, so a wrong
# implementation that reads the working copy flips DEAD and LIVE.

GBARE="$(mktemp -d)"
git init -q --bare "$GBARE/origin.git"

GWORK="$(mktemp -d)"
git init -q -b main "$GWORK"
mkdir -p "$GWORK/_meta"
cat > "$GWORK/_meta/BACKLOG.md" <<'EOF'
## Active queue

| ID | Title | Lane | Status |
|---|---|---|---|
| ID-100 | Retired thing | tiny | shipped |
| ID-200 | Still open thing | tiny | queued |
EOF
git -C "$GWORK" add -A
git -C "$GWORK" -c user.email=t@t -c user.name=t commit -q -m "seed board"
git -C "$GWORK" remote add origin "$GBARE/origin.git"
git -C "$GWORK" push -q origin main
git -C "$GBARE/origin.git" symbolic-ref HEAD refs/heads/main

GSCAN="$(mktemp -d)"
git clone -q "$GBARE/origin.git" "$GSCAN/repo"
GREPO="$GSCAN/repo"
mkdir -p "$GREPO/_meta/handoffs"

cat > "$GREPO/_meta/handoffs/dead-one.md" <<'EOF'
# Handoff: retired work

## Next
Nothing left, ID-100 shipped.
EOF

cat > "$GREPO/_meta/handoffs/live-one.md" <<'EOF'
# Handoff: still open

## Next
Finish ID-200.
EOF

cat > "$GREPO/_meta/handoffs/no-ids.md" <<'EOF'
# Handoff: no board rows

## Next
Just a reminder, nothing tracked.
EOF

# Dirty local copy: inverse of origin's statuses for the same two rows.
cat > "$GREPO/_meta/BACKLOG.md" <<'EOF'
## Active queue

| ID | Title | Lane | Status |
|---|---|---|---|
| ID-100 | Retired thing | tiny | queued |
| ID-200 | Still open thing | tiny | shipped |
EOF

touch -t "$(stamp_days_ago 3)" "$GREPO/_meta/handoffs/dead-one.md"
touch -t "$(stamp_days_ago 2)" "$GREPO/_meta/handoffs/live-one.md"
touch -t "$(stamp_days_ago 1)" "$GREPO/_meta/handoffs/no-ids.md"

gout="$(bash "$HO" list --repo "$GREPO")"

echo "[10] DEAD: all cited rows closed on origin (local copy says the opposite)"
dead_line="$(printf '%s\n' "$gout" | grep 'dead-one.md')"
if [[ "$dead_line" == *"DEAD (all 1 cited rows closed, delete it)"* ]]; then
  ok "dead-one.md verdict: $dead_line"
else
  no "expected DEAD verdict, got: $dead_line"
fi

echo "[11] LIVE: cited row open on origin (local copy says the opposite)"
live_line="$(printf '%s\n' "$gout" | grep 'live-one.md')"
if [[ "$live_line" == *"LIVE (1 open: ID-200)"* ]]; then
  ok "live-one.md verdict: $live_line"
else
  no "expected LIVE verdict, got: $live_line"
fi

echo "[12] UNCITED: no board IDs in the file"
uncited_line="$(printf '%s\n' "$gout" | grep 'no-ids.md')"
if [[ "$uncited_line" == *"UNCITED (no row IDs; read it)"* ]]; then
  ok "no-ids.md verdict: $uncited_line"
else
  no "expected UNCITED verdict, got: $uncited_line"
fi

echo "[13] local fallback: no origin, unresolved id stays open, tagged (local)"
LREPO="$(mktemp -d)"
mkdir -p "$LREPO/_meta/handoffs"
cat > "$LREPO/_meta/handoffs/local-fallback.md" <<'EOF'
# Handoff: no git origin here

## Next
Still need ID-999, and this repo has no git remote.
EOF
touch -t "$(stamp_days_ago 4)" "$LREPO/_meta/handoffs/local-fallback.md"
lout="$(bash "$HO" list --repo "$LREPO")"
if [[ "$lout" == *"LIVE (1 open: ID-999) (local)"* ]]; then
  ok "local fallback marker: $lout"
else
  no "expected local LIVE marker, got: $lout"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "smoke: all $pass passed"
  exit 0
else
  echo "smoke: $fail FAILED, $pass passed" >&2
  exit 1
fi
