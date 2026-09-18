#!/usr/bin/env bash
# test-megagoals.sh -- unit test for lib/goal/megagoals.sh, the kit:start
# mega-goal lister.
#
# Fixtures are built at run time under mktemp, not committed (same shape as
# lib/session/tests/test-handoffs.sh).
#
# Run: bash lib/goal/tests/test-megagoals.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"     # lib/goal
MG="${DIR}/megagoals.sh"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

# --- fixture: one repo, four mega-goals, both checklist shapes -------------
# open-list / done-list  use the plain "- [ ]" / "- [x]" bullet checklist
# open-table / done-table embed the same checkbox token inside a table's
# Status cell (the shape experiments/homelab-net-research/megagoals/* uses).

REPO="$(mktemp -d)"
mkdir -p "$REPO/_meta/megagoals/open-list" \
         "$REPO/_meta/megagoals/done-list" \
         "$REPO/_meta/megagoals/open-table" \
         "$REPO/_meta/megagoals/done-table"

cat > "$REPO/_meta/megagoals/open-list/ROADMAP.md" <<'EOF'
# Mega-goal: open-list

## Sub-goals

- [x] 01-first, shipped, `auto`, PR #1
- [ ] 02-second, still open, `auto`, PR #

## Imported history (never re-run)

- [x] pre-work, shipped (not a sub-goal, must not be counted)
EOF

cat > "$REPO/_meta/megagoals/done-list/ROADMAP.md" <<'EOF'
# Mega-goal: done-list

## Sub-goals

- [x] 01-first, shipped, `auto`, PR #1
- [x] 02-second, shipped, `auto`, PR #2
EOF

cat > "$REPO/_meta/megagoals/open-table/ROADMAP.md" <<'EOF'
# Mega-goal: open-table

## Sub-goals

| # | Sub-goal | Merge | Depends | Status |
|---|---|---|---|---|
| 01 | first thing | [auto] | - | - [x] shipped |
| 02 | second thing | [auto] | 01 | - [ ] queued |
| 03 | third thing | [gate] | 02 | - [ ] queued |

**Key decisions:** none.
EOF

cat > "$REPO/_meta/megagoals/done-table/ROADMAP.md" <<'EOF'
# Mega-goal: done-table

## Sub-goals

| # | Sub-goal | Merge | Depends | Status |
|---|---|---|---|---|
| 01 | first thing | [auto] | - | - [x] shipped |
| 02 | second thing | [auto] | 01 | - [x] shipped |
EOF

# HANDOFF + POINTER only on open-list, to check the yes/no and path/- columns.
cat > "$REPO/_meta/megagoals/open-list/HANDOFF.md" <<'EOF'
# HANDOFF
State: mid-wave.
EOF
cat > "$REPO/_meta/megagoals/open-list/POINTER_PROMPT.md" <<'EOF'
Execute the mega-goal at open-list/.
EOF

out="$(bash "$MG" list --repo "$REPO")"

echo "[1] open-list shown with correct done/total, excluding the Imported history checkbox"
line="$(printf '%s\n' "$out" | grep '^open-list ')"
if [[ "$line" == "open-list  1/2  HANDOFF:yes  POINTER:_meta/megagoals/open-list/POINTER_PROMPT.md" ]]; then
  ok "open-list line: $line"
else
  no "expected 1/2 with handoff+pointer, got: $line"
fi

echo "[2] done-list is hidden by default (fully done)"
if [[ "$out" != *"done-list "* ]]; then ok "done-list hidden"; else no "done-list leaked: $out"; fi

echo "[3] open-table counted from the table's Status cell, 1/3"
line="$(printf '%s\n' "$out" | grep '^open-table ')"
if [[ "$line" == "open-table  1/3  HANDOFF:no  POINTER:-" ]]; then
  ok "open-table line: $line"
else
  no "expected 1/3 no-handoff no-pointer, got: $line"
fi

echo "[4] done-table is hidden by default (fully done)"
if [[ "$out" != *"done-table "* ]]; then ok "done-table hidden"; else no "done-table leaked: $out"; fi

echo "[5] count line: 2 mega-goals shown by default"
if [[ "$out" == *$'\n'"2 mega-goals" ]]; then ok "count line: $(tail -1 <<<"$out")"; else no "expected '2 mega-goals' last line, got: $out"; fi

echo "[6] --all reveals the fully-done ones too, 4 total"
aout="$(bash "$MG" list --repo "$REPO" --all)"
if [[ "$aout" == *"done-list  2/2"* && "$aout" == *"done-table  2/2"* && "$aout" == *$'\n'"4 mega-goals" ]]; then
  ok "--all shows all 4"
else
  no "--all output wrong: $aout"
fi

# --- cap test: 7 open mega-goals, default limit 5 --------------------------

CAPREPO="$(mktemp -d)"
for i in 1 2 3 4 5 6 7; do
  d="$CAPREPO/_meta/megagoals/cap-$i"
  mkdir -p "$d"
  cat > "$d/ROADMAP.md" <<EOF
# Mega-goal: cap-$i

## Sub-goals

- [ ] 01-only, still open
EOF
done

echo "[7] cap: 7 open mega-goals collapse to 5 lines + '+2 more'"
cout="$(bash "$MG" list --repo "$CAPREPO")"
shown=$(printf '%s\n' "$cout" | grep -c '^cap-')
if [[ "$shown" -eq 5 ]]; then ok "5 shown"; else no "expected 5 shown lines, got $shown: $cout"; fi
if [[ "$cout" == *$'\n'"+2 more"$'\n'"7 mega-goals" ]]; then
  ok "collapse + count tail correct"
else
  no "expected '+2 more' then '7 mega-goals', got: $cout"
fi

echo "[8] --limit overrides the default"
lout="$(bash "$MG" list --repo "$CAPREPO" --limit 2)"
shown2=$(printf '%s\n' "$lout" | grep -c '^cap-')
if [[ "$shown2" -eq 2 && "$lout" == *"+5 more"* ]]; then ok "--limit 2: $shown2 shown, +5 more"; else no "wrong --limit output: $lout"; fi

# --- other three known shapes discovered ------------------------------------

SHAPEREPO="$(mktemp -d)"
mkdir -p "$SHAPEREPO/experiments/exp1/megagoals/e1" \
         "$SHAPEREPO/tools/tool1/docs/megagoals/t1" \
         "$SHAPEREPO/docs/megagoals/d1"
for d in "$SHAPEREPO/experiments/exp1/megagoals/e1" \
         "$SHAPEREPO/tools/tool1/docs/megagoals/t1" \
         "$SHAPEREPO/docs/megagoals/d1"; do
  cat > "$d/ROADMAP.md" <<'EOF'
## Sub-goals

- [ ] 01-only, still open
EOF
done

echo "[9] the other three mega-goal shapes are all discovered"
sout="$(bash "$MG" list --repo "$SHAPEREPO")"
if [[ "$sout" == *"e1  0/1"* && "$sout" == *"t1  0/1"* && "$sout" == *"d1  0/1"* ]]; then
  ok "experiments/, tools/*/docs/, docs/ shapes all found"
else
  no "expected all three shapes found, got: $sout"
fi

# --- negative controls -------------------------------------------------------

EMPTY="$(mktemp -d)"
echo "[10] NC empty repo: honest 'no mega-goals', exit 0"
eout="$(bash "$MG" list --repo "$EMPTY")"
erc=$?
if [[ "$eout" == "no mega-goals" && $erc -eq 0 ]]; then ok "no mega-goals, exit 0"; else no "expected 'no mega-goals'/exit 0, got: $eout (rc=$erc)"; fi

echo "[11] NC unknown subcommand: usage error, exit 64"
set +e
uerr="$(bash "$MG" bogus 2>&1)"
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
