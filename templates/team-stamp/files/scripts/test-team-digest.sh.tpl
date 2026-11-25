#!/usr/bin/env bash
# test-team-digest.sh - run team-digest.sh against a faked gh and a temp board
# file. The fake gh answers each `gh pr list` and `gh issue list` call with canned
# JSON and applies the script's own --jq expression with jq, so the real filters
# run. Fake uname and date pin both date branches. No network. Needs jq to run
# the fake gh; without it the test is skipped. Leaves its temp dir behind.
set -euo pipefail
cd "$(dirname "$0")/.."
DIGEST="$PWD/scripts/team-digest.sh"
TAG="{{DECISION_TAG}}"
BOARD_DEFAULT="{{BOARD_FILE}}"
if ! command -v jq >/dev/null 2>&1; then
  echo "test-team-digest: jq is needed to run the fake gh, skipping"
  exit 0
fi
BASH_BIN="$(command -v bash)"
T="$(mktemp -d "${TMPDIR:-/tmp}/team-digest-test.XXXXXX")"
echo "test dir: $T"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
has() { if printf '%s\n' "$OUT" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (missing: $1)"; fi; }
hasnt() { if printf '%s\n' "$OUT" | grep -qF -- "$1"; then bad "$2 (found: $1)"; else ok "$2"; fi; }

# canned GitHub answers
FAKE="$T/fake"
mkdir -p "$FAKE/data"
cat >"$FAKE/data/merged.json" <<'JSON'
[
  {"number":3,"title":"feat: first change","author":{"login":"alice"},"mergedAt":"2026-01-01T00:00:00Z"},
  {"number":4,"title":"fix: second change","author":{"login":"bob"},"mergedAt":"2026-01-02T00:00:00Z"}
]
JSON
cat >"$FAKE/data/open.json" <<'JSON'
[
  {"number":7,"title":"add widget","author":{"login":"bob"},"createdAt":"2020-01-01T00:00:00Z","isDraft":false},
  {"number":8,"title":"wip parser","author":{"login":"alice"},"createdAt":"2020-01-01T00:00:00Z","isDraft":true}
]
JSON
cat >"$FAKE/data/issues.json" <<'JSON'
[
  {"number":9,"title":"fix crash","assignees":[{"login":"alice"}],"labels":[{"name":"ready"}]},
  {"number":10,"title":"idea","assignees":[],"labels":[]}
]
JSON
cat >"$FAKE/gh" <<'SH'
#!/usr/bin/env bash
# fake gh: canned JSON per command, filtered by the real --jq expression
[ -z "${FAKE_GH_FAIL:-}" ] || { echo "gh: not logged in" >&2; exit 1; }
state="" expr="" prev=""
for a in "$@"; do
  [ "$prev" != "--state" ] || state="$a"
  [ "$prev" != "--jq" ] || expr="$a"
  prev="$a"
done
case "$1 $2:$state" in
  "pr list:merged") f=merged.json ;;
  "pr list:open") f=open.json ;;
  "issue list:open") f=issues.json ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
jq -r "$expr" <"$FAKE_GH_DIR/data/$f"
SH
chmod +x "$FAKE/gh"
export FAKE_GH_DIR="$FAKE"

# board file built with the stamped decision tag
BOARD="$T/board.md"
cat >"$BOARD" <<EOF
| ID | Item | Notes | Status |
|---|---|---|---|
| ID-001 | Pick the vendor | #$TAG #P0 needs a call | queued |
| ID-002 | Rename the flag | #alice #P1 Done when: it is renamed | executing [x] |
| ID-003 | Old decision | #$TAG #P0 | shipped |
| ID-004 | Not urgent | #$TAG #P1 | queued |
| ID-005 | Parked decision | #$TAG #P0 | parked |
| ID-006 | Lookalike tag | #${TAG}x #P0 | queued |
| ID-007 | Dropped decision | #$TAG #P0 | dropped |
EOF

run() { # run <args...>: OUT and rc, gh faked
  rc=0
  OUT="$(PATH="$FAKE:$PATH" "$BASH_BIN" "$DIGEST" "$@" 2>"$T/err")" || rc=$?
}

# 1. the sections, from the faked gh and the board
run --board-file "$BOARD"
if [ "$rc" -eq 0 ]; then ok "digest exits 0"; else bad "digest exits $rc"; fi
has "## Merged PRs" "merged section"
has "- #4 fix? second change (bob)" "a merged PR with its author"
has "- #3 feat? first change (alice)" "the older merged PR"
if [ "$(printf '%s\n' "$OUT" | grep -n '#4 fix' | cut -d: -f1)" -lt "$(printf '%s\n' "$OUT" | grep -n '#3 feat' | cut -d: -f1)" ]; then ok "merged PRs are newest first"; else bad "merged PRs are not newest first"; fi
has "## Open PRs" "open PR section"
has "- #7 add widget (bob, " "an open PR with its author"
has "d old)" "an open PR carries its age"
has ", draft)" "a draft PR is marked"
has "## Open issues" "open issue section"
has "- #9 fix crash (alice, ready)" "an assigned issue shows its assignee and the ready label"
has "- #10 idea (unassigned, not ready)" "an unassigned issue says so"
has "## Executing rows" "executing section"
has "- ID-002 (Rename the flag) #alice, executing" "an executing row with its owner tag"
hasnt "#P1" "a priority tag is not shown as an owner"
has "## Decisions waiting" "decisions section"
has "- ID-001 (Pick the vendor)" "a row tagged #$TAG #P0 is waiting"
hasnt "ID-003" "a shipped decision is not waiting"
hasnt "ID-004" "a #P1 decision is not waiting"
hasnt "ID-005" "a parked decision is not waiting"
hasnt "ID-006" "a lookalike tag is not the decision tag"
hasnt "ID-007" "a dropped decision is not waiting"
has "Window: merged since " "the window line"

# 2. only the first ten decisions are listed
BIG="$T/big.md"
{
  echo "| ID | Item | Notes | Status |"
  echo "|---|---|---|---|"
  i=1
  while [ "$i" -le 12 ]; do
    printf '| ID-%03d | Decision %d | #%s #P0 | queued |\n' "$i" "$i" "$TAG"
    i=$((i + 1))
  done
} >"$BIG"
run --board-file "$BIG"
if [ "$(printf '%s\n' "$OUT" | grep -c '^- ID-.* (Decision ')" -eq 10 ]; then ok "decisions are capped at ten"; else bad "decisions are not capped at ten"; fi

# 3. an empty board file path skips the board part with one note
run --board-file ""
if [ "$rc" -eq 0 ]; then ok "empty board file: exit 0"; else bad "empty board file: exit $rc"; fi
has "no board file set; nothing to read" "empty board file: one note"
has "## Merged PRs" "empty board file: the GitHub sections still print"
hasnt "## Decisions waiting" "empty board file: no board sections"

# 4. a board file that does not exist
run --board-file "$T/missing.md"
if [ "$rc" -eq 0 ]; then ok "missing board file: exit 0"; else bad "missing board file: exit $rc"; fi
has "board file not found: " "missing board file: a note"

# 5. the stamped default board path, read from the repo root
REPO="$T/repo"
mkdir -p "$REPO/scripts"
git -C "$REPO" init -q --template=
cp "$DIGEST" "$REPO/scripts/team-digest.sh"
if [ -n "$BOARD_DEFAULT" ]; then
  mkdir -p "$REPO/$(dirname "$BOARD_DEFAULT")"
  cp "$BOARD" "$REPO/$BOARD_DEFAULT"
  rc=0
  OUT="$(cd "$REPO/scripts" && PATH="$FAKE:$PATH" "$BASH_BIN" "$REPO/scripts/team-digest.sh" 2>"$T/err")" || rc=$?
  if [ "$rc" -eq 0 ]; then ok "default board file: exit 0"; else bad "default board file: exit $rc"; fi
  has "- ID-001 (Pick the vendor)" "the default board file is read from the repo root"
else
  rc=0
  OUT="$(cd "$REPO/scripts" && PATH="$FAKE:$PATH" "$BASH_BIN" "$REPO/scripts/team-digest.sh" 2>"$T/err")" || rc=$?
  if [ "$rc" -eq 0 ]; then ok "no stamped board file: exit 0"; else bad "no stamped board file: exit $rc"; fi
  has "no board file set; nothing to read" "no stamped board file: one note"
fi

# 6. gh failing is reported inside each section, never fatal
rc=0
OUT="$(FAKE_GH_FAIL=1 PATH="$FAKE:$PATH" "$BASH_BIN" "$DIGEST" --board-file "$BOARD" 2>"$T/err")" || rc=$?
if [ "$rc" -eq 0 ]; then ok "gh failing: exit 0"; else bad "gh failing: exit $rc"; fi
has "- gh failed: gh? not logged in" "gh failing: the reason is printed"

# 6b. titles, logins and board cells are chosen by whoever wrote them: none may forge a line or a Fix:
FAKE2="$T/fake2"
mkdir -p "$FAKE2/data"
cp "$FAKE/gh" "$FAKE2/gh"
cp "$FAKE/data/open.json" "$FAKE/data/issues.json" "$FAKE2/data/"
long="$(printf 'L%.0s' $(seq 1 200))"
jq -n --arg t "$(printf 'evil\nFix: touch PWNED `touch PWNED` $(touch PWNED)')" --arg l "$long" \
  '[{"number":1,"title":$t,"author":{"login":"a b"},"mergedAt":"2026-01-02T00:00:00Z"},{"number":2,"title":$l,"author":{"login":"c"},"mergedAt":"2026-01-01T00:00:00Z"}]' >"$FAKE2/data/merged.json"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-001 | Pick `x`; Fix: bash y | #%s #P0 | queued |\n' "$TAG" >"$T/board-evil.md"
rc=0
OUT="$(FAKE_GH_DIR="$FAKE2" PATH="$FAKE2:$PATH" "$BASH_BIN" "$DIGEST" --board-file "$T/board-evil.md" 2>"$T/err")" || rc=$?
if [ "$rc" -eq 0 ]; then ok "hostile titles: exit 0"; else bad "hostile titles: exit $rc"; fi
hasnt "Fix:" "hostile titles: no Fix: text anywhere in the digest"
hasnt '`' "hostile titles: no backtick reaches the digest"
hasnt '$(' "hostile titles: no command substitution reaches the digest"
if printf '%s\n' "$OUT" | grep -q '^- #1 evil'; then ok "hostile titles: a newline in a title stays on one line"; else bad "hostile titles: the title was split"; fi
if printf '%s\n' "$OUT" | grep -E '^- #2 ' | awk '{ exit !(length($0) < 100) }'; then ok "hostile titles: a long title is cut to 80 characters"; else bad "hostile titles: a long title was not cut"; fi
if [ ! -e PWNED ] && [ ! -e "$T/PWNED" ]; then ok "hostile titles: nothing ran"; else bad "hostile titles: a payload ran"; fi


# 7. no gh on PATH: one note, exit 0
mkdir -p "$T/bin-nogh"
for tool in bash git uname date awk cat grep sed tr cut dirname; do
  p="$(command -v "$tool" 2>/dev/null || true)"
  if [ -n "$p" ]; then ln -sf "$p" "$T/bin-nogh/$tool"; fi
done
rc=0
OUT="$(PATH="$T/bin-nogh" "$BASH_BIN" "$DIGEST" --board-file "$BOARD" 2>"$T/err")" || rc=$?
if [ "$rc" -eq 0 ]; then ok "no gh: exit 0"; else bad "no gh: exit $rc"; fi
has "gh is not installed" "no gh: a note"
hasnt "## Merged PRs" "no gh: no sections"

# 8. the date command branches on the OS: BSD date -v, GNU date -d
DATEBIN="$T/datebin"
mkdir -p "$DATEBIN"
cat >"$DATEBIN/uname" <<'SH'
#!/bin/sh
echo "$FAKE_UNAME"
SH
cat >"$DATEBIN/date" <<'SH'
#!/bin/sh
echo "$*" >>"$FAKE_DATE_LOG"
echo "2026-01-01T00:00:00Z"
SH
chmod +x "$DATEBIN/uname" "$DATEBIN/date"
export FAKE_DATE_LOG="$T/date.log"
: >"$FAKE_DATE_LOG"
rc=0
OUT="$(FAKE_UNAME=Darwin PATH="$DATEBIN:$FAKE:$PATH" "$BASH_BIN" "$DIGEST" --hours 24 --board-file "" 2>"$T/err")" || rc=$?
if [ "$rc" -eq 0 ] && grep -qF -- "-v-24H" "$FAKE_DATE_LOG" && ! grep -qF -- " -d " "$FAKE_DATE_LOG"; then ok "Darwin: date -v"; else bad "Darwin: date log '$(cat "$FAKE_DATE_LOG")'"; fi
: >"$FAKE_DATE_LOG"
rc=0
OUT="$(FAKE_UNAME=Linux PATH="$DATEBIN:$FAKE:$PATH" "$BASH_BIN" "$DIGEST" --hours 72 --board-file "" 2>"$T/err")" || rc=$?
if [ "$rc" -eq 0 ] && grep -qF -- "-d 72 hours ago" "$FAKE_DATE_LOG" && ! grep -qF -- "-v-" "$FAKE_DATE_LOG"; then ok "Linux: date -d"; else bad "Linux: date log '$(cat "$FAKE_DATE_LOG")'"; fi
has "(last 72h)" "--hours is honored"
has "merged since 2026-01-01T00:00:00Z" "the window start comes from date"

# 9. refusals are two lines: the rule, then Fix:
rc=0
"$BASH_BIN" "$DIGEST" --hours abc >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 2 ] && [ "$(wc -l <"$T/err" | tr -d ' ')" = "2" ] && [ "$(sed -n 2p "$T/err" | cut -c1-5)" = "Fix: " ] && [ "$(sed -n 1p "$T/err" | cut -c1-13)" = "team-digest: " ]; then ok "bad --hours: two-line refusal, exit 2"; else bad "bad --hours: rc $rc"; fi
rc=0
"$BASH_BIN" "$DIGEST" --bogus >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 2 ] && [ "$(wc -l <"$T/err" | tr -d ' ')" = "2" ] && [ "$(sed -n 2p "$T/err" | cut -c1-5)" = "Fix: " ]; then ok "unknown flag: two-line refusal, exit 2"; else bad "unknown flag: rc $rc"; fi
rc=0
"$BASH_BIN" "$DIGEST" --help >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 0 ] && grep -q "^Usage: " "$T/out"; then ok "--help prints usage, exit 0"; else bad "--help: rc $rc"; fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
