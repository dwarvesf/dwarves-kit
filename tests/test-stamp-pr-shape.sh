#!/usr/bin/env bash
# test-stamp-pr-shape.sh -- the pr-shape group of the team stamp: scripts/pr-shape.sh and its generated
# test. Stamps the group into temp repos with default and non-default values, checks the files are
# kit-free and clean, runs the generated test, and runs pr-shape against the real stamped rules docs
# (the parity convention of tests/test-stamp-rules.sh: every AGENTS.md heading has a link in
# docs/TEAM-WORKFLOW.md) and the real stamped negctl.sh block.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { # expect <label> <command...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-pr-shape.XXXXXX")" || exit 1
LEAK_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
have_shellcheck() { command -v shellcheck >/dev/null 2>&1; }
gi() { git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "${@:2}"; }

# 1. a stamp with non-default values
A="$(newrepo)"
RC=0
bash lib/stamp.sh --only pr-shape --default-branch master --tags app,lib --product-paths app/,pkg/ --board-file docs/BOARD.md "$A" >"$WORK/stamp-a.out" 2>&1 || RC=$?
expect "stamp of the pr-shape group exits 0" [ "$RC" -eq 0 ]
for f in scripts/pr-shape.sh scripts/test-pr-shape.sh; do
  expect "created $f" grep -qx "created: $f" "$WORK/stamp-a.out"
  expect "$f is executable" test -x "$A/$f"
  expect "$f is listed in the lock" grep -q "^file $f pr-shape sha256:" "$A/.claude/team-stamp.lock"
done
expect "the stamp writes exactly two files" bash -c '[ "$(grep -c "^created: " "$1")" -eq 2 ]' _ "$WORK/stamp-a.out"
expect "no {{KEY}} is left in a generated file" bash -c "! grep -rE '\{\{[A-Za-z_]+\}\}' '$A/scripts'"
bash lib/stamp.sh --only pr-shape "$A" >"$WORK/stamp-a2.out" 2>&1
expect "the second run prints only unchanged lines" bash -c '[ "$(grep -Evc "^(unchanged|using): " "$1")" -eq 0 ] && [ "$(grep -c "^unchanged: " "$1")" -eq 2 ]' _ "$WORK/stamp-a2.out"
expect "--check is clean" bash lib/stamp.sh --only pr-shape --check "$A"

# 2. stamped values; nothing typed in the script
S="$A/scripts/pr-shape.sh"
expect "default branch comes from the stamp" grep -qxF "DEFAULT_BRANCH='master'" "$S"
expect "tag list comes from the stamp" grep -qxF "TAGS_ERE='app|lib|dev'" "$S"
expect "product paths come from the stamp" grep -qxF "PRODUCT_ERE='^(app/|pkg/)'" "$S"
expect "board file comes from the stamp" grep -qxF "BOARD_FILE='docs/BOARD.md'" "$S"
expect "no literal main branch" bash -c "! grep -Eq 'origin/main|[^a-z]main[^a-z]' '$S'"
B="$(newrepo)"
bash lib/stamp.sh --only pr-shape --default-branch main "$B" >/dev/null 2>&1
expect "an empty board file stays empty in the script" grep -qxF "BOARD_FILE=''" "$B/scripts/pr-shape.sh"

# 3. the interface the twin check.sh and ci.yml call: four env values, nothing else, no token
for v in PR_TITLE PR_BODY PR_BODY_FILE BASE_SHA HEAD_SHA; do
  expect "the header documents $v" grep -q "^#   $v " "$S"
done
expect "no token and no gh call" bash -c "! grep -Eq 'GH_TOKEN|GITHUB_TOKEN|gh api|gh pr (view|diff)' '$S'"
expect "PR text never reaches eval" bash -c "! grep -Eq '(^|[^a-z_-])eval[ \t]' '$S'"
expect "no bash 4 feature" bash -c "! grep -Eq 'readarray|mapfile|grep -P|sed -r|declare -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)\\}' '$S' '$A/scripts/test-pr-shape.sh'"

# 4. every generated file: kit-free, no dash characters, no python3, no bare hex digest, shellcheck clean
for f in scripts/pr-shape.sh scripts/test-pr-shape.sh; do
  expect "$f names no kit path" bash -c "! grep -Eq '$LEAK_PATTERN' '$A/$f'"
  expect "$f has no em or en dash" bash -c "! LC_ALL=C grep -q -e '$(printf '\342\200\224')' -e '$(printf '\342\200\223')' '$A/$f'"
  expect "$f does not call python3 or jq" bash -c "! grep -Eq 'python3|(^|[^a-z])jq ' '$A/$f'"
  expect "$f holds no bare 40 or 64 digit hex run" bash -c "! grep -Eq '[0-9a-fA-F]{40}' '$A/$f'"
  if have_shellcheck; then expect "$f is shellcheck clean" shellcheck -S warning "$A/$f"; else ok "shellcheck not installed, $f skipped"; fi
done
expect "every Fix line casing: the script prints Fix: and no lowercase fix:" bash -c "! grep -q 'fix: ' '$S'"

# 5. the generated test passes with the non-default values, with the defaults, and with a board file set
T1="$WORK/test-a.out"
RC=0
bash "$A/scripts/test-pr-shape.sh" >"$T1" 2>&1 || RC=$?
expect "the generated test passes with non-default values" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$T1" | sed 's/^/    /'
expect "the generated test ran its attacker-text cases" grep -q 'running every Fix line creates no PWNED' "$T1"
expect "the generated test skips the negctl case when negctl.sh is absent" grep -q '^skipped: the negctl case' "$T1"
RC=0
bash "$B/scripts/test-pr-shape.sh" >"$WORK/test-b.out" 2>&1 || RC=$?
expect "the generated test passes with the default values (no board file)" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/test-b.out" | sed 's/^/    /'

# 6. with the merge group stamped too, the generated test runs the negctl case
C="$(newrepo)"
bash lib/stamp.sh --only pr-shape,merge --default-branch main --owner testowner --tags web,api --product-paths src/ "$C" >/dev/null 2>&1
RC=0
bash "$C/scripts/test-pr-shape.sh" >"$WORK/test-c.out" 2>&1 || RC=$?
expect "the generated test passes beside negctl.sh and a different tag list" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/test-c.out" | sed 's/^/    /'
expect "the negctl block is accepted by the proof check" grep -q 'PASS  the block negctl.sh prints is accepted as a proof' "$WORK/test-c.out"

# 7. the real stamped docs: the parity convention of the rules group, through a real PR
D="$(newrepo)"
bash lib/stamp.sh --only rules,pr-shape --default-branch main --tags app,dev "$D" >/dev/null 2>&1
gi "$D" symbolic-ref HEAD refs/heads/main
gi "$D" add -A
gi "$D" commit -q -m base
BASE="$(gi "$D" rev-parse HEAD)"
runps() { # runps <name> <body>: pr-shape on the repo $D from $BASE to HEAD
  RC=0
  (cd "$D" && env -u CI PR_TITLE="docs: change the rules" PR_BODY="$2" BASE_SHA="$BASE" HEAD_SHA="$(git rev-parse HEAD)" bash scripts/pr-shape.sh) >"$WORK/$1.out" 2>"$WORK/$1.err" || RC=$?
}
printf '\nOne more rule line.\n' >>"$D/AGENTS.md"
gi "$D" commit -q -am "agents only"
runps real-a ""
expect "stamped AGENTS.md changed alone: fails" [ "$RC" -eq 1 ]
expect "stamped AGENTS.md changed alone: the pair names parity" grep -q '^pr-shape: AGENTS.md changed and docs/TEAM-WORKFLOW.md did not' "$WORK/real-a.err"
runps real-b "no-rule-mirror: the extra line needs no mirror"
expect "stamped AGENTS.md alone with no-rule-mirror: passes" [ "$RC" -eq 0 ]
printf '\nOne more rule line, mirrored.\n' >>"$D/docs/TEAM-WORKFLOW.md"
gi "$D" commit -q -am "workflow too"
runps real-c ""
expect "both stamped docs changed, every heading still linked: passes" [ "$RC" -eq 0 ]
printf '\n### A brand new rule heading\n\nText.\n' >>"$D/AGENTS.md"
printf '\nMirror text without the heading link.\n' >>"$D/docs/TEAM-WORKFLOW.md"
gi "$D" commit -q -am "new heading, no link"
runps real-d ""
expect "a new stamped heading with no link in the workflow doc: fails" [ "$RC" -eq 1 ]
expect "a new stamped heading: the pair names the anchor" grep -q 'anchors: a-brand-new-rule-heading' "$WORK/real-d.err"

# 8. the proof guide's own block shape, filled in, is accepted
E="$(newrepo)"
bash lib/stamp.sh --only rules,pr-shape --default-branch main "$E" >/dev/null 2>&1
gi "$E" symbolic-ref HEAD refs/heads/main
gi "$E" add -A
gi "$E" commit -q -m base
BASE_E="$(gi "$E" rev-parse HEAD)"
printf '#!/usr/bin/env bash\necho new\n' >"$E/scripts/new.sh"
cat >"$E/docs/verification/new.md" <<'EOF'
# Verification: a script

Command: bash scripts/new.sh
Output:
new
Exit: 0
Verdict: PASS

## Negative control

NEGATIVE CONTROL: removed the echo
Command: bash scripts/test-new.sh
Output:
FAIL  new
Exit: 1
Verdict: RED, as expected
EOF
gi "$E" add -A
gi "$E" commit -q -m change
RC=0
(cd "$E" && env -u CI PR_TITLE="feat(scripts): add a script" PR_BODY="Closes #3" BASE_SHA="$BASE_E" HEAD_SHA="$(git rev-parse HEAD)" bash scripts/pr-shape.sh) >"$WORK/guide.out" 2>"$WORK/guide.err" || RC=$?
expect "a proof written in the proof guide's shape: passes" [ "$RC" -eq 0 ]

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
