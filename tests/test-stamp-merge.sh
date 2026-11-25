#!/usr/bin/env bash
# test-stamp-merge.sh -- the merge group of the team stamp: scripts/pr-merge.sh, scripts/negctl.sh and
# their generated tests. Stamps the group into temp repos with two value sets, runs the generated tests,
# checks the files are kit-free and clean, and compares the kit's lib/gate/negctl.sh with the stamped
# scripts/negctl.sh on one tiny fixture repo (the five labelled parts of the block, by shape).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { # expect <label> <command...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-merge.XXXXXX")" || exit 1
LEAK_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
have_shellcheck() { command -v shellcheck >/dev/null 2>&1; }

# 1. a stamp with non-default values
A="$(newrepo)"
RC=0
bash lib/stamp.sh --only merge --default-branch master --owner testowner --door-paths 'docs/legal/*,protocol/*' --door-approver reviewer "$A" >"$WORK/stamp-a.out" 2>&1 || RC=$?
expect "stamp of the merge group exits 0" [ "$RC" -eq 0 ]
expect "the stamp writes exactly four files" bash -c '[ "$(grep -c "^created: " "$1")" -eq 4 ]' _ "$WORK/stamp-a.out"
for f in scripts/pr-merge.sh scripts/test-pr-merge.sh scripts/negctl.sh scripts/test-negctl.sh; do
  expect "created $f" grep -qx "created: $f" "$WORK/stamp-a.out"
  expect "$f is executable" test -x "$A/$f"
  expect "$f is listed in the lock" grep -q "^file $f merge sha256:" "$A/.claude/team-stamp.lock"
done
expect "no {{KEY}} is left in a generated file" bash -c "! grep -rE '\{\{[A-Za-z_]+\}\}' '$A/scripts'"
bash lib/stamp.sh --only merge "$A" >"$WORK/stamp-a2.out" 2>&1
expect "the second run prints only unchanged lines" bash -c '[ "$(grep -Evc "^(unchanged|using): " "$1")" -eq 0 ] && [ "$(grep -c "^unchanged: " "$1")" -eq 4 ]' _ "$WORK/stamp-a2.out"
expect "--check is clean" bash lib/stamp.sh --only merge --check "$A"

# 2. stamped values and the dropped behaviors
P="$A/scripts/pr-merge.sh"
expect "default branch comes from the stamp" grep -qxF 'DEFAULT_BRANCH="master"' "$P"
expect "door approver comes from the stamp" grep -qxF 'APPROVER="reviewer"' "$P"
expect "door list comes from the stamp" grep -qxF 'DOORS=("docs/legal/*" "protocol/*")' "$P"
expect "no literal main in the guard" bash -c "! grep -Eq 'origin/main|[^a-z]main[^a-z]' '$P'"
expect "no CI-path flag" bash -c "! grep -q 'allow-ci-change' '$P'"
expect "the header says the self-copy check stops an honest out-of-date copy, not a hostile one" bash -c "grep -q 'It does NOT stop a hostile copy' '$P' && grep -q 'nobody runs a pull request' '$P'"
expect "the guard reads the files from the REST list, paginated, with previous names, and caps at 3000" bash -c "grep -q 'pulls/\$number/files' '$P' && grep -q 'previous_filename' '$P' && grep -q 'MAX_FILES=3000' '$P' && ! grep -q '100 or more' '$P'"
expect "the guard takes only this PR's runs of the stamped workflow file" bash -c "grep -q 'actions/runs?head_sha=' '$P' && grep -q 'pull_requests' '$P' && grep -q 'CI_FILE=' '$P'"
expect "the guard reads the timeline for base changes and refuses a base that is not the default branch" bash -c "grep -q 'base_ref_changed' '$P' && grep -q 'baseRefName' '$P'"
expect "the door patterns are lower case and the path is lowered before the match" bash -c "grep -q 'lp=\"\$(lower' '$P' && ! grep -E '^BASE_DOORS=' '$P' | grep -q '[A-Z]'"
expect "the default doors cover .github, scripts, .claude, OWNERS, AGENTS and CLAUDE at any depth, .mcp.json, the workflow doc and .kit.toml" bash -c "grep -E '^BASE_DOORS=' '$P' | grep -q '\.github/\*' && grep -E '^BASE_DOORS=' '$P' | grep -q '\*/agents.md' && grep -E '^BASE_DOORS=' '$P' | grep -q '\*/claude.md' && grep -E '^BASE_DOORS=' '$P' | grep -q '\.mcp.json'"
expect "no stale-rules refusal" bash -c "! grep -Eiq 'stale|older than the last change|RULE_PATHS' '$P'"
expect "no kit merge-head variable" bash -c "! grep -q 'KIT_' '$P'"
expect "no --all or --refresh mode" bash -c "! grep -Eq -- '--all|--refresh' '$P'"
expect "an empty array expansion is guarded under set -u" grep -q 'DOORS\[@\]+' "$P"
expect "the guard cleans gh text before it is printed" grep -q '^clean() ' "$P"
expect "the guard puts only a safe value into a Fix line" grep -q '^is_safe() ' "$P"
for f in scripts/pr-merge.sh scripts/negctl.sh; do
  expect "$f never uses eval" bash -c "! grep -Eq '(^|[^a-z_])eval[[:space:]]' '$A/$f'"
done

# 3. every generated file: kit-free, no dash characters, no python3, no bare hex digest, shellcheck clean
for f in scripts/pr-merge.sh scripts/test-pr-merge.sh scripts/negctl.sh scripts/test-negctl.sh; do
  expect "$f names no kit path" bash -c "! grep -Eq '$LEAK_PATTERN' '$A/$f'"
  expect "$f has no em or en dash" bash -c "! LC_ALL=C grep -q -e '$(printf '\342\200\224')' -e '$(printf '\342\200\223')' '$A/$f'"
  expect "$f does not call python3" bash -c "! grep -q 'python3' '$A/$f'"
  expect "$f holds no bare 40 or 64 digit hex run" bash -c "! grep -Eq '[0-9a-fA-F]{40}' '$A/$f'"
  expect "$f uses no GNU-only or bash 4 feature" bash -c "! grep -Eq 'readarray|mapfile|grep -P|sed -r|declare -A' '$A/$f'"
  if have_shellcheck; then expect "$f is shellcheck clean" shellcheck -S warning "$A/$f"; else ok "shellcheck not installed, $f skipped"; fi
done
expect "the stamped negctl names no kit script" bash -c "! grep -q 'gate/negctl' '$A/scripts/negctl.sh'"

# 4. the generated tests pass, with non-default values and with the default empty door list
run_generated() { # run_generated <label> <repo> <test script>
  local out rc=0
  out="$(cd "$2" && bash "$3" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'failures: 0'; then ok "$1"; else no "$1"; printf '%s\n' "$out" | grep -v '^PASS' | tail -n 15 | sed 's/^/    /'; fi
}
run_generated "generated test-pr-merge.sh passes (master, door list, approver)" "$A" scripts/test-pr-merge.sh
run_generated "generated test-negctl.sh passes" "$A" scripts/test-negctl.sh

B="$(newrepo)"
bash lib/stamp.sh --only merge --default-branch develop --owner testowner "$B" >/dev/null 2>&1
expect "a default stamp holds an empty door list" grep -qxF 'DOORS=()' "$B/scripts/pr-merge.sh"
expect "a default stamp holds an empty approver" grep -qxF 'APPROVER=""' "$B/scripts/pr-merge.sh"
expect "a default stamp names its own branch" grep -qxF 'DEFAULT_BRANCH="develop"' "$B/scripts/pr-merge.sh"
expect "a default stamp is shellcheck clean or shellcheck is absent" bash -c "! command -v shellcheck >/dev/null 2>&1 || shellcheck -S warning '$B/scripts/pr-merge.sh'"
run_generated "generated test-pr-merge.sh passes (develop, no door list)" "$B" scripts/test-pr-merge.sh

# 5. the stamped negctl against the kit's, on one tiny fixture repo
mkfixture() { # mkfixture <name>: a committed repo whose test is "a.txt still says good"
  local d="$WORK/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q 2>/dev/null && git config user.name t && git config user.email t@example.invalid && git config commit.gpgsign false
    printf 'good\n' > a.txt
    printf '%s\n' 'echo "checking a.txt"' 'grep -q good a.txt || { echo "FAIL a.txt lost good"; exit 1; }' 'echo "ok a.txt"' > test.sh
    git add a.txt test.sh && git commit -q -m init )
  echo "$d"
}
K="$(mkfixture kit)"; G="$(mkfixture gen)"
MUT="printf 'bad\n' > a.txt"
( cd "$K" && bash "$ROOT/lib/gate/negctl.sh" "$K" "bash test.sh" "$MUT" ) > "$WORK/kit.out" 2> "$WORK/kit.err"; KRC=$?
( cd "$G" && bash "$A/scripts/negctl.sh" "bash test.sh" "$MUT" ) > "$WORK/gen.out" 2> "$WORK/gen.err"; GRC=$?
expect "the kit negctl goes green, red, green on the fixture" [ "$KRC" -eq 0 ]
expect "the stamped negctl goes green, red, green on the fixture" [ "$GRC" -eq 0 ]

# the five labelled parts
labels() { # labels <block file>: the labels the block carries, sorted, one per line
  awk '
    function see(l) { seen[l] = 1 }
    tolower($0) ~ /negative control/ { see("NEGATIVE CONTROL") }
    /^Command: / { see("Command:") }
    /^Exit: [0-9]+/ { see("Exit:") }
    /^Output:/ { see("Output:") }
    /^Verdict: / { see("Verdict:") }
    END { for (l in seen) print l }' "$1" | LC_ALL=C sort
}
labels "$WORK/kit.out" > "$WORK/kit.labels"; labels "$WORK/gen.out" > "$WORK/gen.labels"
expect "both blocks carry the same five labelled parts" bash -c 'cmp -s "$1" "$2" && [ "$(wc -l < "$1")" -eq 5 ]' _ "$WORK/kit.labels" "$WORK/gen.labels"
red_exit() { awk '/^Exit: [0-9]+ \(under mutation/ { print $2; exit } /^Exit: [0-9]+$/ { print $2; exit }' "$1"; }
expect "both blocks report the same red exit code" bash -c '[ -n "$1" ] && [ "$1" = "$2" ]' _ "$(red_exit "$WORK/kit.out")" "$(red_exit "$WORK/gen.out")"
expect "both blocks name the same test command" bash -c '[ "$(grep -m1 "^Command: " "$1")" = "$(grep -m1 "^Command: " "$2")" ]' _ "$WORK/kit.out" "$WORK/gen.out"
expect "both Output slots hold the failing assertion line" bash -c 'grep -q "FAIL a.txt lost good" "$1" && grep -q "FAIL a.txt lost good" "$2"' _ "$WORK/kit.out" "$WORK/gen.out"
expect "both blocks end on a Verdict line" bash -c '[ "$(grep "^Verdict: " "$1" | tail -n 1 | cut -c1-9)" = "Verdict: " ] && [ "$(grep "^Verdict: " "$2" | tail -n 1 | cut -c1-9)" = "Verdict: " ]' _ "$WORK/kit.out" "$WORK/gen.out"
expect "the stamped verdict is RED, as expected" grep -qx 'Verdict: RED, as expected' "$WORK/gen.out"
# what a pull request check reads in a proof file
proof_ok() {
  grep -Eq '^[[:space:]]*Exit:' "$1" &&
    awk '{ if (prev && $0 != "") f = 1; prev = ($0 ~ /^[[:space:]]*Output:/) } END { exit !f }' "$1" &&
    grep -Eq '^[[:space:]]*Verdict: RED' "$1" && grep -Eiq 'negative control' "$1"
}
expect "the stamped block holds what a pull request proof check reads" proof_ok "$WORK/gen.out"
expect "both trees are clean and restored after the run" bash -c '[ -z "$(git -C "$1" status --porcelain)" ] && [ -z "$(git -C "$2" status --porcelain)" ] && [ "$(cat "$1/a.txt")" = good ] && [ "$(cat "$2/a.txt")" = good ]' _ "$K" "$G"

# both refuse a dirty tree before running anything, and a red that is only a syntax error
printf 'edited\n' > "$K/a.txt"; printf 'edited\n' > "$G/a.txt"
( cd "$K" && bash "$ROOT/lib/gate/negctl.sh" "$K" "touch ran-here; bash test.sh" "$MUT" ) > "$WORK/kit-dirty.out" 2>&1; KD=$?
( cd "$G" && bash "$A/scripts/negctl.sh" "touch ran-here; bash test.sh" "$MUT" ) > "$WORK/gen-dirty.out" 2> "$WORK/gen-dirty.err"; GD=$?
expect "both refuse a dirty tree with exit 2" bash -c '[ "$1" -eq 2 ] && [ "$2" -eq 2 ]' _ "$KD" "$GD"
expect "both name REFUSED" bash -c 'grep -q REFUSED "$1" && grep -q REFUSED "$2"' _ "$WORK/kit-dirty.out" "$WORK/gen-dirty.err"
expect "neither ran the test or the mutation" bash -c '[ ! -e "$1/ran-here" ] && [ ! -e "$2/ran-here" ] && [ "$(cat "$1/a.txt")" = edited ] && [ "$(cat "$2/a.txt")" = edited ]' _ "$K" "$G"
expect "the stamped refusal is two lines: rule, then Fix:" bash -c '[ "$(wc -l < "$1")" -eq 2 ] && [ "$(sed -n 2p "$1" | cut -c1-5)" = "Fix: " ]' _ "$WORK/gen-dirty.err"
git -C "$K" checkout -q -- a.txt; git -C "$G" checkout -q -- a.txt

SYNTAX="printf 'if then\\n' > test.sh"
( cd "$K" && bash "$ROOT/lib/gate/negctl.sh" "$K" "bash test.sh" "$SYNTAX" ) > "$WORK/kit-syn.out" 2>&1; KS=$?
( cd "$G" && bash "$A/scripts/negctl.sh" "bash test.sh" "$SYNTAX" ) > "$WORK/gen-syn.out" 2> "$WORK/gen-syn.err"; GS=$?
expect "both refuse a red that is only a syntax error (exit 1)" bash -c '[ "$1" -eq 1 ] && [ "$2" -eq 1 ]' _ "$KS" "$GS"
expect "neither records it as RED" bash -c '! grep -q "Verdict: RED" "$1" && ! grep -q "Verdict: RED" "$2"' _ "$WORK/kit-syn.out" "$WORK/gen-syn.out"
expect "both restored the test file" bash -c 'grep -q "lost good" "$1/test.sh" && grep -q "lost good" "$2/test.sh"' _ "$K" "$G"
expect "the stamped syntax refusal ends with a Fix: line" bash -c 'tail -n 1 "$1" | grep -q "^Fix: "' _ "$WORK/gen-syn.err"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
