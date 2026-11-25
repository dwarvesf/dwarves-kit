#!/usr/bin/env bash
# test-stamp-playbook.sh -- the "digest" group of the team stamp: the ship-pr skill and the team
# digest script with its generated test. Stamps only that group into temp repos and checks:
#   1. SKILL.md starts with --- on line 1, carries exactly the keys name and description (a
#      misspelled key must fail the check), grants no allowed-tools, and names only scripts from
#      the stamp's own set (that every named script exists in a full stamp is checked with the
#      cross-group suite);
#   2. the stamped default branch reaches the skill; no literal default branch name does;
#   3. the digest is portable (no python3, branches on uname -s) and its generated test passes with
#      a board file set and with none, and a second run changes nothing.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
unset STAMP_TEMPLATES
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }
expect_not() { local label="$1"; shift; if "$@"; then no "$label"; else ok "$label"; fi; }

ls "$ROOT"/templates/team-stamp/manifest.d/*-digest.tsv >/dev/null 2>&1 || { echo "NOT ok - no digest manifest" >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-playbook.XXXXXX")" || exit 1
STAMP="bash $ROOT/lib/stamp.sh --only digest"
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
LIT="ma""in"

# frontmatter_ok <SKILL.md>: line 1 is ---, a closing --- exists, the keys are exactly name and description
frontmatter_ok() {
  local f="$1" keys
  [ "$(sed -n 1p "$f")" = "---" ] || return 1
  awk 'NR>1 && /^---[ \t]*$/ {found=1; exit} END{exit !found}' "$f" || return 1
  keys="$(awk 'NR==1{next} /^---[ \t]*$/{exit} /^[A-Za-z][A-Za-z0-9_-]*:/ {sub(/:.*/, ""); print}' "$f" | LC_ALL=C sort | tr '\n' ' ')"
  [ "$keys" = "description name " ]
}

# 1. the skill
R="$(newrepo)"
$STAMP --default-branch master "$R" >"$WORK/stamp.out" 2>&1; RC=$?
expect "stamp the digest group exits 0" [ "$RC" -eq 0 ]
SK="$R/.claude/skills/ship-pr/SKILL.md"
expect "SKILL.md is written" [ -f "$SK" ]
expect "SKILL.md line 1 is --- and the keys are exactly name and description" frontmatter_ok "$SK"
expect "SKILL.md name is ship-pr" grep -q '^name: ship-pr$' "$SK"
expect "SKILL.md grants no allowed-tools" bash -c '! grep -qi "allowed-tools" "$1"' _ "$SK"
expect "SKILL.md description stays under the 1,536 character cap" bash -c '[ "$(grep "^description:" "$1" | wc -c)" -lt 1500 ]' _ "$SK"
cp "$SK" "$WORK/bad1.md"; sed -i.bak 's/^description:/descripton:/' "$WORK/bad1.md"
expect_not "a misspelled key fails the check" frontmatter_ok "$WORK/bad1.md"
printf '\n%s\n' "$(cat "$SK")" >"$WORK/bad2.md"
expect_not "a file that does not start with --- fails the check" frontmatter_ok "$WORK/bad2.md"
cp "$SK" "$WORK/bad3.md"; sed -i.bak 's/^name: ship-pr$/name: ship-pr\nallowed-tools: Bash/' "$WORK/bad3.md"
expect_not "an extra key fails the check" frontmatter_ok "$WORK/bad3.md"

# the commands the skill tells an agent to run, from the stamp's own set of scripts
cmds="$(grep -oE 'bash scripts/[A-Za-z0-9._-]+\.sh' "$SK" | sed 's/^bash //' | LC_ALL=C sort -u)"
expect "SKILL.md names at least one script" [ -n "$cmds" ]
known="scripts/check.sh scripts/check-owners.sh scripts/pr-merge.sh scripts/negctl.sh scripts/issues-from-rows.sh scripts/release-notes.sh scripts/team-digest.sh scripts/pr-shape.sh scripts/agent-lessons.sh"
unknown=""
for c in $cmds; do case " $known " in *" $c "*) ;; *) unknown="$unknown $c" ;; esac; done
expect "every script the skill names is in the stamp's set (unknown:${unknown:- none})" [ -z "$unknown" ]
expect "the skill walks claim, branch, proof, check, PR, merge" bash -c '
  for p in "gh issue edit" "git worktree add" "scripts/negctl.sh" "scripts/check.sh" "gh pr create" "scripts/pr-merge.sh --wait"; do
    grep -qF -- "$p" "$1" || { echo "missing: $p" >&2; exit 1; }
  done' _ "$SK"
expect "the stamped default branch reaches the skill" grep -q 'origin/master' "$SK"
expect "the skill names no literal $LIT branch" bash -c '! grep -qw "$1" "$2"' _ "$LIT" "$SK"
expect "the skill never suggests a bare gh pr merge" bash -c '! grep -E "^[[:space:]]*gh pr merge" "$1"' _ "$SK"
expect "no unresolved {{KEY}} in a generated file" bash -c '! grep -q "{{" "$1" "$2" "$3"' _ "$SK" "$R/scripts/team-digest.sh" "$R/scripts/test-team-digest.sh"

# 2. the digest script
DG="$R/scripts/team-digest.sh"
expect "digest and its test are written and executable" bash -c '[ -x "$1" ] && [ -x "$2" ]' _ "$DG" "$R/scripts/test-team-digest.sh"
expect "the digest has no python3" bash -c '! grep -q python3 "$1" "$2"' _ "$DG" "$R/scripts/test-team-digest.sh"
expect "the digest branches on uname -s for date" bash -c 'grep -q "uname -s" "$1" && grep -q "date -u -v" "$1" && grep -q "date -u -d" "$1"' _ "$DG"
expect "the digest reads the decision tag from the stamped value" grep -q '^decision_tag="decision"$' "$DG"
expect "bash -n accepts the digest" bash -n "$DG"
bash "$R/scripts/test-team-digest.sh" >"$WORK/dt1.out" 2>&1; RC=$?
expect "the generated digest test passes (default values, no board file)" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/dt1.out" | sed 's/^/    /'
expect "no board file stamped: the board value is empty" grep -q '^board_default=""$' "$DG"

# 3. non-default values: a board file, another decision tag
R2="$(newrepo)"
$STAMP --default-branch trunk --board-file docs/plan/BOARD.md --decision-tag needs-call "$R2" >/dev/null 2>&1; RC=$?
expect "stamp with a board file and a decision tag exits 0" [ "$RC" -eq 0 ]
expect "the board file and the tag reach the digest" bash -c 'grep -q "^board_default=\"docs/plan/BOARD.md\"$" "$1" && grep -q "^decision_tag=\"needs-call\"$" "$1"' _ "$R2/scripts/team-digest.sh"
bash "$R2/scripts/test-team-digest.sh" >"$WORK/dt2.out" 2>&1; RC=$?
expect "the generated digest test passes (board file, custom tag)" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/dt2.out" | sed 's/^/    /'
expect "the default board file is read from the repo root by the real script" bash -c '
  grep -q "default board file: exit 0" "$1" && grep -q "the default board file is read from the repo root" "$1"' _ "$WORK/dt2.out"

# 4. idempotence
OUT2="$($STAMP --default-branch trunk --board-file docs/plan/BOARD.md --decision-tag needs-call "$R2" 2>&1)"
expect "a second run prints only unchanged" bash -c '! printf "%s\n" "$1" | grep -Ev "^(unchanged|using): " | grep -q .' _ "$OUT2"

# 5. shell-clean
if command -v shellcheck >/dev/null 2>&1; then
  expect "shellcheck -S warning on the digest and its test" shellcheck -S warning "$R/scripts/team-digest.sh" "$R/scripts/test-team-digest.sh"
else
  echo "skip - shellcheck is not installed"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
