#!/usr/bin/env bash
# test-stamp-hook.sh -- the "hook" group of the team stamp: the command guard, its generated test,
# and the .claude/settings.json merge. Stamps only that group into temp repos and checks:
#   1. the guard blocks a bare merge with the PR number in the Fix line, a push to the default
#      branch and a commit on it, and allows the lookalikes (the generated test holds the rows);
#   2. the guard reads no python3, names no literal default branch, and fails open on bad input;
#   3. the settings merge adds one PreToolUse Bash entry and one SessionStart entry, keeps foreign
#      keys and foreign hook entries, adds nothing on a second run, and refuses invalid JSON.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
unset STAMP_TEMPLATES
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }

command -v jq >/dev/null 2>&1 || { echo "NOT ok - jq is needed for this suite" >&2; exit 1; }
ls "$ROOT"/templates/team-stamp/manifest.d/*-hook.tsv >/dev/null 2>&1 || { echo "NOT ok - no hook manifest" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-hook.XXXXXX")" || exit 1
STAMP="bash $ROOT/lib/stamp.sh --only hook"
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
guard_json() { jq -n --arg c "$2" --arg d "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
# lit: a word assembled at run time so this file holds no literal default branch name
LIT="ma""in"

# 1. stamp with a non-default branch
R="$(newrepo)"
$STAMP --default-branch master "$R" >/dev/null 2>&1; RC=$?
expect "stamp the hook group exits 0" [ "$RC" -eq 0 ]
expect "guard is written and executable" [ -x "$R/scripts/agent-guard.sh" ]
expect "guard test is written and executable" [ -x "$R/scripts/test-agent-guard.sh" ]
expect "settings.json is written" [ -f "$R/.claude/settings.json" ]
expect "the lock lists the guard and its test" bash -c 'grep -q "^file scripts/agent-guard.sh " "$1" && grep -q "^file scripts/test-agent-guard.sh " "$1"' _ "$R/.claude/team-stamp.lock"
expect "the guard carries the stamped default branch" grep -q '^default_branch="master"$' "$R/scripts/agent-guard.sh"
expect "the guard names no literal $LIT branch" bash -c '! grep -qw "$1" "$2"' _ "$LIT" "$R/scripts/agent-guard.sh"
expect "the guard test names no literal $LIT branch" bash -c '! grep -qw "$1" "$2"' _ "$LIT" "$R/scripts/test-agent-guard.sh"
expect "the guard has no python3" bash -c '! grep -q python3 "$1" "$2"' _ "$R/scripts/agent-guard.sh" "$R/scripts/test-agent-guard.sh"
expect "the guard lists what it does not catch" grep -q "What this guard does not catch" "$R/scripts/agent-guard.sh"
expect "no unresolved {{KEY}} in a generated file" bash -c '! grep -q "{{" "$1" "$2"' _ "$R/scripts/agent-guard.sh" "$R/scripts/test-agent-guard.sh"
expect "bash -n accepts the guard" bash -n "$R/scripts/agent-guard.sh"

# 2. the generated test passes (both with the stamped branch and with another one)
bash "$R/scripts/test-agent-guard.sh" >"$WORK/gt.out" 2>&1; RC=$?
expect "the generated guard test passes (master)" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/gt.out" | sed 's/^/    /'
R2="$(newrepo)"
$STAMP --default-branch trunk "$R2" >/dev/null 2>&1
bash "$R2/scripts/test-agent-guard.sh" >"$WORK/gt2.out" 2>&1; RC=$?
expect "the generated guard test passes (trunk)" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/gt2.out" | sed 's/^/    /'
expect "the generated test holds a row per known probe" bash -c '
  t="$1"; for p in "env -i git commit" "timeout 5 git push origin" "git push --all" "git push --mirror" "pulls/9/merge" "pr merge 7" "git checkout README.md; git commit"; do
    grep -qF -- "$p" "$t" || { echo "missing row: $p" >&2; exit 1; }
  done' _ "$R/scripts/test-agent-guard.sh"

# 3. the contract end to end: the stamped guard on real hook JSON
G="$R/scripts/agent-guard.sh"
git -C "$R" symbolic-ref HEAD refs/heads/master
git -C "$R" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init 2>/dev/null
guard_json "$R" 'gh pr merge 7 --squash' | bash "$G" >/dev/null 2>"$WORK/e1"; RC=$?
expect "bare gh pr merge 7 exits 2" [ "$RC" -eq 2 ]
expect "bare merge: two stderr lines" [ "$(wc -l <"$WORK/e1" | tr -d ' ')" = 2 ]
expect "bare merge: line 2 is the Fix line with the PR number" [ "$(sed -n 2p "$WORK/e1")" = "Fix: bash scripts/pr-merge.sh --wait 7" ]
guard_json "$R" 'git push origin master' | bash "$G" >/dev/null 2>"$WORK/e2"; RC=$?
expect "push to the default branch exits 2 with a Fix line" bash -c '[ "$1" -eq 2 ] && [ "$(sed -n 2p "$2" | cut -c1-5)" = "Fix: " ]' _ "$RC" "$WORK/e2"
guard_json "$R" 'git commit -m x' | bash "$G" >/dev/null 2>"$WORK/e3"; RC=$?
expect "a commit on the default branch exits 2" [ "$RC" -eq 2 ]
expect "commit fix is git switch -c" [ "$(sed -n 2p "$WORK/e3")" = "Fix: git switch -c <type>/<slug>" ]
guard_json "$R" 'bash scripts/pr-merge.sh --wait 5' | bash "$G" >/dev/null 2>"$WORK/e4"; RC=$?
expect "pr-merge.sh --wait 5 is allowed, silent" bash -c '[ "$1" -eq 0 ] && [ ! -s "$2" ]' _ "$RC" "$WORK/e4"
guard_json "$R" 'echo "gh pr merge"' | bash "$G" >/dev/null 2>&1; RC=$?
expect "echo \"gh pr merge\" is allowed" [ "$RC" -eq 0 ]
printf '{broken' | bash "$G" >/dev/null 2>&1; RC=$?
expect "broken stdin exits 0" [ "$RC" -eq 0 ]
printf '' | bash "$G" >/dev/null 2>&1; RC=$?
expect "empty stdin exits 0" [ "$RC" -eq 0 ]

# 4. settings: the two entries, through ${CLAUDE_PROJECT_DIR}
S="$R/.claude/settings.json"
expect "settings.json is valid JSON" jq -e . "$S" >/dev/null
expect "one PreToolUse Bash entry runs the guard" bash -c '[ "$(jq "[.hooks.PreToolUse[] | select(.matcher==\"Bash\") | .hooks[] | select(.command | test(\"agent-guard.sh\"))] | length" "$1")" = 1 ]' _ "$S"
expect "one SessionStart entry runs the lessons script" bash -c '[ "$(jq "[.hooks.SessionStart[].hooks[] | select(.command | test(\"agent-lessons.sh\"))] | length" "$1")" = 1 ]' _ "$S"
expect "both commands go through \${CLAUDE_PROJECT_DIR}" bash -c '[ "$(jq "[.. | .command? // empty | select(startswith(\"bash \\\"\${CLAUDE_PROJECT_DIR}/scripts/\"))] | length" "$1")" = 2 ]' _ "$S"
expect "the settings carry no absolute path" bash -c '! grep -Eq "(/Users/|/home/)" "$1"' _ "$S"

# 5. second run: nothing to add, nothing changes
before="$(cksum <"$S")"
OUT2="$($STAMP --default-branch master "$R" 2>&1)"; RC=$?
expect "a second run exits 0" [ "$RC" -eq 0 ]
expect "a second run leaves settings.json byte-identical" [ "$(cksum <"$S")" = "$before" ]
expect "a second run prints only unchanged" bash -c '! printf "%s\n" "$1" | grep -Ev "^(unchanged|using): " | grep -q .' _ "$OUT2"

# 6. foreign keys and a foreign hook entry survive, in the same Bash group
R3="$(newrepo)"
mkdir -p "$R3/.claude"
cat >"$R3/.claude/settings.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "foreign-check.sh" } ] },
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "foreign-edit.sh" } ] }
    ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "foreign-stop.sh" } ] } ]
  }
}
JSON
OUT3="$($STAMP --default-branch master "$R3" 2>&1)"; RC=$?
S3="$R3/.claude/settings.json"
expect "stamp over a settings.json with foreign entries exits 0" [ "$RC" -eq 0 ]
expect "the foreign top-level key is kept" bash -c '[ "$(jq -r ".permissions.allow[0]" "$1")" = "Bash(ls:*)" ]' _ "$S3"
expect "the foreign Stop hook is kept" bash -c '[ "$(jq -r ".hooks.Stop[0].hooks[0].command" "$1")" = "foreign-stop.sh" ]' _ "$S3"
expect "the foreign Edit entry is kept" bash -c '[ "$(jq -r "[.hooks.PreToolUse[] | select(.matcher==\"Edit\")] | length" "$1")" = 1 ]' _ "$S3"
expect "the foreign Bash hook is kept" bash -c '[ "$(jq -r "[.hooks.PreToolUse[] | select(.matcher==\"Bash\") | .hooks[] | select(.command==\"foreign-check.sh\")] | length" "$1")" = 1 ]' _ "$S3"
expect "the guard entry joins the same Bash group" bash -c '[ "$(jq "[.hooks.PreToolUse[] | select(.matcher==\"Bash\")] | length" "$1")" = 1 ] && [ "$(jq "[.hooks.PreToolUse[] | select(.matcher==\"Bash\") | .hooks[]] | length" "$1")" = 2 ]' _ "$S3"
expect "the report says merged" bash -c 'printf "%s\n" "$1" | grep -q "^merged: .claude/settings.json"' _ "$OUT3"
before3="$(jq -cS . "$S3")"
$STAMP --default-branch master "$R3" >/dev/null 2>&1
$STAMP --default-branch master "$R3" >/dev/null 2>&1
expect "two more runs add no duplicate entry" [ "$(jq -cS . "$S3")" = "$before3" ]
expect "--check is clean after the merge" bash -c "$STAMP --check --default-branch master \"$R3\" >/dev/null 2>&1"

# 7. invalid JSON is refused and nothing is written
R4="$(newrepo)"
mkdir -p "$R4/.claude"
printf '{ not json' >"$R4/.claude/settings.json"
OUT4="$($STAMP --default-branch master "$R4" 2>&1)"; RC=$?
expect "invalid settings.json: the run is refused" [ "$RC" -ne 0 ]
expect "invalid settings.json: left byte-identical" [ "$(cat "$R4/.claude/settings.json")" = "{ not json" ]
expect "invalid settings.json: no guard written" [ ! -e "$R4/scripts/agent-guard.sh" ]
expect "invalid settings.json: the refusal ends in a Fix line" bash -c 'printf "%s\n" "$1" | grep -q "^Fix: "' _ "$OUT4"

# 8. the generated files are shell-clean
if command -v shellcheck >/dev/null 2>&1; then
  expect "shellcheck -S warning on the guard and its test" shellcheck -S warning "$R/scripts/agent-guard.sh" "$R/scripts/test-agent-guard.sh"
else
  echo "skip - shellcheck is not installed"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
