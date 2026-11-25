#!/usr/bin/env bash
# test-stamp-refusals.sh -- every refusal of every generated script, once, on a full stamp.
# For each: it exits 1 (2 for the hook), every "Fix:" line is directly preceded by a
# "<tool>: <rule>" line, the last two stderr lines are that pair, hostile input (a quote,
# $(touch ...) and a newline followed by a fake Fix: line) never reaches the output raw, and every
# printed Fix: line, run through bash -c in a copy of the repo, creates nothing.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-refusals.XXXXXX")" || exit 1
command -v jq >/dev/null 2>&1 || { echo "ok - jq not found, skipping"; exit 0; }

# hostile text: a single quote, a command substitution, a backtick, and a newline plus a forged Fix line
EVIL="x'\$(touch EVILMARK)\`touch EVILMARK\`"
EVIL_NL="$(printf 'a\nFix: touch EVILMARK')"
no_mark() { [ -z "$(find "$WORK" -name EVILMARK 2>/dev/null)" ]; }
SEEN_FIXES=" "

# ---- the stamped repo, committed once; every case works in a fresh copy ----
R0="$WORK/base"; mkdir -p "$R0"; git -C "$R0" init -q -b master 2>/dev/null
git -C "$R0" config user.name tester; git -C "$R0" config user.email tester@example.invalid
bash lib/stamp.sh --default-branch master --owner testowner --tags app,lib --product-paths app/,pkg/ \
  --door-paths 'docs/legal/*' --door-approver reviewer --board-file docs/BOARD.md "$R0" >/dev/null 2>&1
git -C "$R0" add -A >/dev/null 2>&1; git -C "$R0" commit -q -m "chore: stamp"
git -C "$R0" update-ref refs/remotes/origin/master HEAD
ntargets="$(awk '$1=="file"' "$R0/.claude/team-stamp.lock" | wc -l | tr -d ' ')"
expect "the stamped repo has files to work with ($ntargets)" [ "$ntargets" -gt 20 ]

# a fake gh that serves $FAKE/case.json through the script's own --jq expression
FAKE="$WORK/fake"; mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/gh" <<EOF
#!/bin/bash
if [ "\$1 \$2" = "pr view" ]; then
  expr=""; while [ \$# -gt 0 ]; do [ "\$1" = "--jq" ] && expr="\$2"; shift; done
  jq -r "\$expr" "$FAKE/case.json"
elif [ "\$1 \$2" = "pr merge" ]; then exit 0
else exit 1; fi
EOF
chmod +x "$FAKE/bin/gh"
mkcase() { # mkcase <isDraft> <mergeable> <checks-json> <files-json> <reviews-json>
  printf '{"isDraft":%s,"mergeable":"%s","author":{"login":"author"},"statusCheckRollup":[%s],"files":[%s],"reviews":[%s],"headRefOid":"head1","headRefName":"feature/x"}\n' "$1" "$2" "$3" "$4" "$5" > "$FAKE/case.json"
}
GOODCK='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}'

fresh() { local d; d="$(mktemp -d "$WORK/c.XXXXXX")"; cp -R "$R0/." "$d/"; echo "$d"; }

# refusal <label> <tool> <expected-exit> <dir> <command...>   (stdin from $STDIN_FILE when set)
refusal() {
  local label="$1" tool="$2" want="$3" dir="$4" rc err n prev line fix fx; shift 4
  err="$(cd "$dir" && PATH="$FAKE/bin:$PATH" "$@" 2>&1 >/dev/null < "${STDIN_FILE:-/dev/null}")"; rc=$?
  expect "$label: exit $want" bash -c 'case " $2 " in *" $1 "*) exit 0;; *) exit 1;; esac' _ "$rc" "$want"
  expect "$label: the last two stderr lines are '$tool: <rule>' then 'Fix: ...'" bash -c '
    l1="$(printf "%s\n" "$1" | tail -n 2 | sed -n 1p)"; l2="$(printf "%s\n" "$1" | tail -n 2 | sed -n 2p)"
    [ "${l1#"$2: "}" != "$l1" ] && [ "${l2#Fix: }" != "$l2" ] && [ -n "${l2#Fix: }" ]' _ "$err" "$tool"
  # every Fix: line is preceded by a rule line, so a forged one cannot stand alone
  bad=0; prev=""
  while IFS= read -r line; do
    case "$line" in "Fix: "*) case "$prev" in "$tool: "*|"${ALSO:-__none__}: "*) ;; *) bad=1;; esac;; esac
    prev="$line"
  done <<EOF2
$err
EOF2
  expect "$label: every Fix: line follows a '$tool: ' line" [ "$bad" -eq 0 ]
  expect "$label: the hostile text is not in the output raw" bash -c '! printf "%s" "$1" | grep -qF "$(printf "%s" "$2")"' _ "$err" '$(touch'
  # run every printed Fix: line in a copy: nothing must be created
  n=0
  while IFS= read -r fix; do
    n=$((n + 1))
    case "$SEEN_FIXES" in *"|$fix|"*) continue;; esac   # each distinct line runs once
    SEEN_FIXES="$SEEN_FIXES|$fix| "
    fx="$(mktemp -d "$WORK/fx.XXXXXX")"; cp -R "$dir/." "$fx/"
    { ( cd "$fx" && PATH="$FAKE/bin:$PATH" perl -e 'alarm 10; exec @ARGV' bash -c "${fix#Fix: }" ) >/dev/null 2>&1 < /dev/null; } 2>/dev/null
  done <<EOF3
$(printf '%s\n' "$err" | grep '^Fix: ')
EOF3
  expect "$label: its $n Fix: line(s) ran through bash -c and created nothing" no_mark
}

json() { jq -nc --arg c "$1" --arg d "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}'; }

# ---- agent-guard (exit 2) ----
D="$(fresh)"
for c in "gh pr merge 7 --squash" "gh pr merge $EVIL" "git push origin master" "git push origin HEAD:master" "git commit -m x"; do
  STDIN_FILE="$WORK/in.json"; json "$c" "$D" > "$STDIN_FILE"
  refusal "guard: $(printf '%s' "$c" | cut -c1-30)" agent-guard 2 "$D" bash scripts/agent-guard.sh
done
unset STDIN_FILE

# ---- check-owners ----
D="$(fresh)"; printf '#!/usr/bin/env bash\n' > "$D/scripts/new-thing.sh"; git -C "$D" add scripts/new-thing.sh
refusal "owners: a script with no row" check-owners 1 "$D" bash scripts/check-owners.sh
D="$(fresh)"; hostile="scripts/x'\$(touch EVILMARK).sh"; printf '#!/usr/bin/env bash\n' > "$D/$hostile"; git -C "$D" add -f -- "$hostile"
refusal "owners: a hostile file name" check-owners 1 "$D" bash scripts/check-owners.sh
D="$(fresh)"; sed -i.bak 's/^| `scripts\/negctl.sh` | \(.*\) | @testowner |/| `scripts\/negctl.sh` | \1 |  |/' "$D/OWNERS.md"; git -C "$D" add -A >/dev/null 2>&1
refusal "owners: an empty owner" check-owners 1 "$D" bash scripts/check-owners.sh
D="$(fresh)"; printf '| `scripts/gone.sh` | gone | @testowner | |\n' >> "$D/OWNERS.md"
refusal "owners: a row for a missing path" check-owners 1 "$D" bash scripts/check-owners.sh

# ---- release-notes ----
D="$(fresh)"
refusal "release-notes: no section" release-notes 2 "$D" bash scripts/release-notes.sh
refusal "release-notes: a missing section" release-notes 1 "$D" bash scripts/release-notes.sh 9.9.9
printf '\n- app: fine\n- an untagged line\n' >> "$D/CHANGELOG.md"
refusal "release-notes: an untagged entry" release-notes 1 "$D" bash scripts/release-notes.sh Unreleased
D="$(fresh)"; printf '\n- %s\n' "$EVIL" >> "$D/CHANGELOG.md"
refusal "release-notes: a hostile entry" release-notes 1 "$D" bash scripts/release-notes.sh Unreleased
refusal "release-notes: a hostile section name" release-notes "1 2" "$D" bash scripts/release-notes.sh "$EVIL"

# ---- negctl ----
D="$(fresh)"
refusal "negctl: no arguments" negctl 64 "$D" bash scripts/negctl.sh
printf 'dirt\n' >> "$D/CHANGELOG.md"
refusal "negctl: a tracked file with uncommitted changes" negctl 2 "$D" bash scripts/negctl.sh "true" "true"
D="$(fresh)"
refusal "negctl: a test that is already red" negctl 1 "$D" bash scripts/negctl.sh "false" "echo x >> CHANGELOG.md"

# ---- pr-shape (exit 1) and check.sh ----
D="$(fresh)"; git -C "$D" checkout -q -b feat/x; mkdir -p "$D/app"; printf '#!/usr/bin/env bash\necho hi\n' > "$D/app/x.sh"; git -C "$D" add app; git -C "$D" commit -q -m "feat(app): x"
shape() { # shape <label> <title> <body>
  refusal "$1" pr-shape 1 "$D" env PR_TITLE="$2" PR_BODY="$3" BASE_SHA=origin/master HEAD_SHA=HEAD bash scripts/pr-shape.sh
}
shape "pr-shape: a bad title" "not conventional" "Closes #1"
shape "pr-shape: no proof, no board link, no changelog" "feat(app): x" ""
shape "pr-shape: a hostile title" "feat(app): $EVIL" "Closes #1"
shape "pr-shape: a hostile title with a forged Fix line" "feat(app): $EVIL_NL" "Closes #1"
shape "pr-shape: a hostile body" "feat(app): x" "$EVIL_NL"
D2="$(fresh)"; git -C "$D2" checkout -q -b docs/p; printf '\nedit\n' >> "$D2/AGENTS.md"; git -C "$D2" commit -q -am "docs: edit rules"
refusal "pr-shape: AGENTS.md changed alone" pr-shape 1 "$D2" env PR_TITLE="docs: edit rules" PR_BODY="" BASE_SHA=origin/master HEAD_SHA=HEAD bash scripts/pr-shape.sh
ALSO=pr-shape   # check.sh forwards the checks' own refusals before its own pair
refusal "check.sh: a bad title" check 1 "$D" bash scripts/check.sh --title "not conventional" --body "Closes #1"
refusal "check.sh: a hostile title" check 1 "$D" bash scripts/check.sh --title "feat(app): $EVIL_NL" --body "$EVIL"
refusal "check.sh: a usage error" check 2 "$D" bash scripts/check.sh --bogus
unset ALSO

# ---- pr-merge (fake gh) ----
D="$(fresh)"
mkcase true MERGEABLE "$GOODCK" '{"path":"app/x.sh"}' ''
refusal "pr-merge: a draft" pr-merge 1 "$D" bash scripts/pr-merge.sh 7
mkcase false MERGEABLE '{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"b'"'"'$(touch EVILMARK)","status":"COMPLETED","conclusion":"FAILURE"}' '{"path":"app/x.sh"}' ''
refusal "pr-merge: a red check with a hostile name" pr-merge 1 "$D" bash scripts/pr-merge.sh 7
mkcase false CONFLICTING "$GOODCK" '{"path":"app/x.sh"}' ''
refusal "pr-merge: a conflict" pr-merge 1 "$D" bash scripts/pr-merge.sh 7
mkcase false MERGEABLE "$GOODCK" '{"path":"docs/legal/terms.md"}' ''
refusal "pr-merge: a door path with no second person" pr-merge 1 "$D" bash scripts/pr-merge.sh 7
mkcase false MERGEABLE "$GOODCK" '{"path":"docs/legal/terms.md"}' '{"author":{"login":"author"},"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z"}'
refusal "pr-merge: the author as the second person" pr-merge 1 "$D" bash scripts/pr-merge.sh 7
mkcase false MERGEABLE "$GOODCK" '{"path":"app/x.sh"}' ''
refusal "pr-merge: a bad PR number" pr-merge 2 "$D" bash scripts/pr-merge.sh "$EVIL"

# ---- issues-from-rows, team-digest ----
D="$(fresh)"
refusal "issues-from-rows: an unknown flag" issues-from-rows 2 "$D" bash scripts/issues-from-rows.sh --bogus
refusal "team-digest: a bad --hours" team-digest 2 "$D" bash scripts/team-digest.sh --hours "$EVIL"

expect "no hostile payload ran anywhere: no marker file exists" no_mark

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
