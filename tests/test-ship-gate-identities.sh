#!/usr/bin/env bash
# test-ship-gate-identities.sh -- ship-gate refuses a push whose commits carry a fixture git
# identity (x@x, t@t.dev) as author, committer or Co-authored-by; real, noreply and bot addresses pass.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
LOGDIR="$(mktemp -d)"
REAL=tieubao@users.noreply.github.com

mkrepo() { # $1=dir; a fresh bare origin per repo
  local ORIGIN; ORIGIN="$(mktemp -d)"; git init -q --bare -b master "$ORIGIN" 2>/dev/null
  git clone -q "$ORIGIN" "$1" 2>/dev/null
  git -C "$1" symbolic-ref HEAD refs/heads/master
  git -C "$1" config user.email "$REAL"; git -C "$1" config user.name "Han Ngo"
  echo base > "$1/f"; git -C "$1" add -A; git -C "$1" commit -qm "chore: init"
  git -C "$1" push -q origin master 2>/dev/null
  git -C "$1" remote set-head origin master 2>/dev/null
}
gate() { # $1=repo -> echoes exit code
  ( cd "$1" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1; echo $? )
}
case_commit() { # $1=name $2=expected exit $3=author-email $4=trailer-line(optional) $5=committer-email(optional)
  local d; d="$(mktemp -d)/r"; mkrepo "$d"; git -C "$d" switch -qc "fix/change"
  echo "$1" > "$d/g"; git -C "$d" add -A
  GIT_AUTHOR_EMAIL="$3" GIT_AUTHOR_NAME=han GIT_COMMITTER_EMAIL="${5:-$REAL}" \
    git -C "$d" commit -q -m "fix: change" -m "${4:-body}"
  [ "$(gate "$d")" = "$2" ] && ok "$1" || no "$1 (want exit $2)"
}

case_commit "author x@x blocked"                  2 "x@x"
case_commit "author t@t.dev blocked"              2 "t@t.dev"
case_commit "author foo@example.com blocked"      2 "foo@example.com"
case_commit "committer x@x blocked"               2 "$REAL" "" "x@x"
case_commit "co-author t@t.dev blocked"           2 "$REAL" "Co-authored-by: tester <t@t.dev>"
case_commit "noreply author + devin bot co-author ok" 0 "$REAL" "Co-authored-by: devin-ai-integration[bot] <158243242+devin-ai-integration[bot]@users.noreply.github.com>"
case_commit "real address ok"                     0 "han@d.foundation"

echo "pass=$PASS fail=$FAIL"; [ "$FAIL" = 0 ]
