#!/usr/bin/env bash
# test-stamp-owners.sh -- the owners group of the team stamp: scripts/check-owners.sh, its generated
# test, and the OWNERS.md seed, stamped into scratch repos and exercised there.
# The cross-group case (the seed of a FULL stamp passes the check) lives in the integration suite;
# here the seed is trimmed to the files this group wrote, then the check is run on it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-owners.XXXXXX")" || exit 1
KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
EM="$(printf '\342\200\224')"; EN="$(printf '\342\200\223')"
TPL=templates/team-stamp
CHK="$TPL/files/scripts/check-owners.sh"
TST="$TPL/files/scripts/test-check-owners.sh"

newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
two_lines() { # two_lines <file>: exactly one refusal pair, rule then Fix
  [ "$(wc -l <"$1" | tr -d ' ')" -eq 2 ] && sed -n 1p "$1" | grep -q '^check-owners: ' && sed -n 2p "$1" | grep -q '^Fix: '
}

# 1. manifest rows
M="$TPL/manifest.d/40-owners.tsv"
expect "manifest exists" [ -f "$M" ]
expect "manifest: every row has five tab-separated columns" bash -c "grep -v '^#' '$M' | grep -v '^\$' | awk -F'\t' 'NF != 5 { exit 1 }'"
expect "manifest: the OWNERS.md row is a hook row on the engine's owners seed" bash -c "grep -v '^#' '$M' | awk -F'\t' '\$1 == \"hook\" && \$2 == \"lib/stamp/owners-seed.sh\" && \$3 == \"OWNERS.md\" { f = 1 } END { exit !f }'"
expect "manifest: the check and its test are copy rows" bash -c "grep -v '^#' '$M' | awk -F'\t' '\$1 == \"copy\" && \$3 == \"scripts/check-owners.sh\" { a = 1 } \$1 == \"copy\" && \$3 == \"scripts/test-check-owners.sh\" { b = 1 } END { exit !(a && b) }'"

# 2. stamp the group
R1="$(newrepo)"
bash lib/stamp.sh --only owners --default-branch main --owner testowner "$R1" >"$WORK/s1.out" 2>&1
expect "stamp the owners group" [ $? -eq 0 ]
for f in scripts/check-owners.sh scripts/test-check-owners.sh OWNERS.md; do
  expect "created: $f" [ -f "$R1/$f" ]
done
expect "check-owners.sh is executable" [ -x "$R1/scripts/check-owners.sh" ]
expect "test-check-owners.sh is executable" [ -x "$R1/scripts/test-check-owners.sh" ]
expect "the check and its test are byte-identical to the templates (agnostic, no value)" bash -c "cmp -s '$CHK' '$R1/scripts/check-owners.sh' && cmp -s '$TST' '$R1/scripts/test-check-owners.sh'"

# 3. the seed
expect "seed: a row for the check, owned by the stamped owner" grep -q '^| `scripts/check-owners.sh` | .* | @testowner | |$' "$R1/OWNERS.md"
expect "seed: a row for the check's test" grep -q '^| `scripts/test-check-owners.sh` | Test for scripts/check-owners.sh | @testowner | |$' "$R1/OWNERS.md"
expect "seed: the table header names Path, Owner and Sponsor" grep -q '^| Path | What it does | Owner | Sponsor |$' "$R1/OWNERS.md"

# 4. idempotent, never drift-checked after the repo edits OWNERS.md
bash lib/stamp.sh --only owners --default-branch main --owner testowner "$R1" >"$WORK/s2.out" 2>&1
expect "second run prints only unchanged" bash -c "[ -s '$WORK/s2.out' ] && ! grep -Ev '^(unchanged|using): ' '$WORK/s2.out'"
printf '| `scripts/extra.sh` | Added by the repo | @someone | |\n' >>"$R1/OWNERS.md"
bash lib/stamp.sh --only owners --check "$R1" >"$WORK/c1.out" 2>&1
expect "--check stays clean after the repo edits OWNERS.md" [ $? -eq 0 ]

# 5. the generated test passes in the stamped repo
(cd "$R1" && bash scripts/test-check-owners.sh) >"$WORK/t1.out" 2>&1
expect "the generated test passes in the stamped repo" [ $? -eq 0 ]
expect "the generated test ran cases" bash -c "[ \"\$(grep -c '^PASS' '$WORK/t1.out')\" -ge 20 ]"

# 6. the seed, trimmed to this group's files, passes the check; a pre-existing script then refuses
R2="$(newrepo)"
bash lib/stamp.sh --only owners --default-branch main --owner testowner "$R2" >/dev/null 2>&1
# rows of other groups name files that this partial stamp did not write: drop them, keep the rest
(cd "$R2" && awk -F'|' '/^\| `/ { p = $2; gsub(/[ `]/, "", p); if (system("test -e " p) != 0) next } { print }' OWNERS.md >OWNERS.trim && mv OWNERS.trim OWNERS.md)
git -C "$R2" add -A 2>/dev/null
(cd "$R2" && bash scripts/check-owners.sh) >"$WORK/k1.out" 2>"$WORK/k1.err"
expect "the seed, trimmed to the group's files, passes the check" [ $? -eq 0 ]
expect "the check reports its count" grep -q '^check-owners: 2 paths, all owned$' "$WORK/k1.out"
printf '#!/usr/bin/env bash\n' >"$R2/scripts/legacy.sh"
git -C "$R2" add -A 2>/dev/null
(cd "$R2" && bash scripts/check-owners.sh) >"$WORK/k2.out" 2>"$WORK/k2.err"
expect "a repo's own script with no row refuses" [ $? -eq 1 ]
expect "the refusal is the two-line form and says no owner yet" two_lines "$WORK/k2.err"
expect "the refusal names the script" grep -q 'no owner yet for scripts/legacy.sh' "$WORK/k2.err"
mkdir -p "$R2/.github/workflows"
printf 'name: x\n' >"$R2/.github/workflows/x.yml"
git -C "$R2" add -A 2>/dev/null
(cd "$R2" && bash scripts/check-owners.sh) >"$WORK/k3.out" 2>"$WORK/k3.err"
expect "a workflow of any repo is covered" grep -q 'no owner yet for .github/workflows/x.yml' "$WORK/k3.err"

# 7. non-default values change nothing in the script bytes
R3="$(newrepo)"
bash lib/stamp.sh --only owners --default-branch master --owner other --tags app,lib --product-paths app/,pkg/ "$R3" >/dev/null 2>&1
expect "stamped with other values: same script bytes" cmp -s "$R1/scripts/check-owners.sh" "$R3/scripts/check-owners.sh"
expect "stamped with other values: the seed uses the other owner" grep -q '@other | |$' "$R3/OWNERS.md"

# 8. no stamp for a missing owner (the seed needs one)
R4="$(newrepo)"
bash lib/stamp.sh --only owners --default-branch main "$R4" >"$WORK/o.out" 2>&1
expect "no --owner: refused" [ $? -ne 0 ]
expect "no --owner: the refusal is two lines with a Fix line" bash -c "[ \"\$(wc -l <'$WORK/o.out' | tr -d ' ')\" -eq 2 ] && sed -n 2p '$WORK/o.out' | grep -q '^Fix: '"

# 9. portability and scope of the template text
for f in "$CHK" "$TST"; do
  expect "$f: no python3, no jq, no GNU-only flag" bash -c "! grep -Eq 'python3|(^|[^A-Za-z])jq |grep -P|sed -r|readarray|mapfile|declare -A' '$f'"
  expect "$f: no kit path and no home path" bash -c "! grep -Eq '$KIT_PATTERN' '$f'"
  expect "$f: no em or en dash" bash -c "! grep -q -e '$EM' -e '$EN' '$f'"
  expect "$f: no bare 40 or 64 hex run" bash -c "! grep -Eq '[0-9a-f]{40}' '$f'"
  expect "$f: bash -n" bash -n "$f"
done
if command -v shellcheck >/dev/null 2>&1; then
  expect "shellcheck -S warning on the check and its test" shellcheck -S warning "$CHK" "$TST"
else
  echo "note: shellcheck not installed, skipped"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
