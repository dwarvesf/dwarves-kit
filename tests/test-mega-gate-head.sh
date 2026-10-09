#!/usr/bin/env bash
# test-mega-gate-head.sh -- the mega-goal merge gate checks the PR head it merges.
# `mega-merge.sh gate <rid> <lane> --head <sha> [--base-tip <sha>]` runs the diff rules (hard-path
# floor, large-spec validate) on <sha>, not on the local HEAD; `merge` fetches refs/pull/<n>/head
# from origin, checks it equals the pinned head, and gates on it. Every case runs offline against
# temp repos under mktemp -d with a local bare origin, a ledger stub that passes only the normal
# lane's gates, and a fake gh on PATH.
# Run: bash tests/test-mega-gate-head.sh   (exit 0 = all green)
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
MM="$KIT/lib/goal/mega-merge.sh"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
T="$(mktemp -d)"
export DWARVES_KIT_LOG_DIR="$T/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
has() { { trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$1"; }

# ledger stub: the normal lane passes, any other lane (the floor asks for full) reports a gap
cat > "$T/gl" <<'SH'
#!/usr/bin/env bash
case "$1" in
  check) [ "$2" = normal ] && exit 0; echo "MISSING-GATE: build" >&2; exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$T/gl"

# world: a bare origin, a work checkout on main (origin/HEAD set), PR commits kept off main
O="$T/origin.git"; W="$T/work"
git init -q --bare -b main "$O"
git init -q -b main "$W"
printf 'hello\n' > "$W/README.md"; : > "$W/.keep"
git -C "$W" add -A; git -C "$W" commit -qm init
git -C "$W" remote add origin "$O"; git -C "$W" push -q -u origin main 2>/dev/null
git -C "$W" remote set-head origin main >/dev/null 2>&1
MAIN="$(git -C "$W" rev-parse main)"

# commit_on <branch> <from> <path> <content> -> prints the new commit; the checkout returns to main
commit_on() {
  git -C "$W" switch -q -c "$1" "$2"
  mkdir -p "$W/$(dirname "$3")"; printf '%s\n' "$4" > "$W/$3"
  git -C "$W" add -A; git -C "$W" commit -qm "$1"
  git -C "$W" rev-parse HEAD
  git -C "$W" switch -q main
}
P="$(commit_on pr-auth main src/auth/login.ts 'export const x = 1')"

# gate_run <root> <args...> -> prints "<exit>|<stderr>"; the gate runs from <root>'s cwd when it is a dir
gate_run() {
  local root="$1" err rc; shift
  err="$(cd "$W" && MEGA_MERGE_ROOT="$root" MEGA_MERGE_GATE_LEDGER="$T/gl" TMPDIR="$T/tmpd" bash "$MM" gate "$@" 2>&1 >/dev/null)"; rc=$?
  printf '%s|%s' "$rc" "$err"
}
mkdir -p "$T/tmpd"

echo "=== head-mode-floor-hits (negative control) ==="
R="$(gate_run "$W" rid normal --head "$P")"
{ [ "${R%%|*}" = 1 ] && has 'hard path (auth: src/auth/login.ts' "$R"; } && ok "head-mode-floor-hits: --head P from main refuses on the auth hard path" || no "head-mode-floor-hits: got $R"
R="$(gate_run "$W" rid normal)"
[ "${R%%|*}" = 0 ] && ok "head-mode-floor-hits: the same gate with no --head passes (local HEAD is main)" || no "head-mode no --head: got $R"

echo "=== head-mode-bad-sha (negative control) ==="
R="$(gate_run "$W" rid normal --head 1111111111111111111111111111111111111111)"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED: mega gate:' "$R"; } && ok "head-mode-bad-sha: 40 hex naming no object is refused" || no "head-mode-bad-sha unknown object: got $R"
R="$(gate_run "$W" rid normal --head abc)"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED: mega gate:' "$R"; } && ok "head-mode-bad-sha: a short value is refused" || no "head-mode-bad-sha short: got $R"
R="$(gate_run "$W" rid normal --head "$P" --base-tip abc)"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED: mega gate:' "$R"; } && ok "head-mode-bad-sha: a bad --base-tip is refused" || no "head-mode-bad-sha base-tip: got $R"
mkdir -p "$T/notrepo"
R="$(gate_run "$T/notrepo" rid normal --head "$P")"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED: mega gate:' "$R"; } && ok "head-mode-bad-sha: a root that is not a repo is refused, no bare ledger pass" || no "head-mode-bad-sha non-repo: got $R"

echo "=== head-mode-usage ==="
R="$(gate_run "$W" rid normal --base-tip "$MAIN")"
[ "${R%%|*}" = 64 ] && ok "head-mode-usage: --base-tip without --head is a usage error (64)" || no "head-mode-usage base-tip alone: got $R"
R="$(gate_run "$W" rid normal --head)"
[ "${R%%|*}" = 64 ] && ok "head-mode-usage: --head with no value is a usage error (64)" || no "head-mode-usage head no value: got $R"
R="$(gate_run "$W" rid normal --head "$P" --base-tip)"
[ "${R%%|*}" = 64 ] && ok "head-mode-usage: --base-tip with no value is a usage error (64)" || no "head-mode-usage base-tip no value: got $R"

echo "=== head-mode-no-base (negative control) ==="
N="$T/nobase"; git clone -q --no-checkout "$W" "$N" 2>/dev/null
git -C "$N" remote remove origin; git -C "$N" remote add origin "$O"
git -C "$N" fetch -q "$W" "$P" 2>/dev/null; git -C "$N" update-ref refs/heads/pr "$P"
U="$(git -C "$N" commit-tree -m unrelated "$(git -C "$N" hash-object -t tree /dev/null)")"
R="$(gate_run "$N" rid normal --head "$P")"
{ [ "${R%%|*}" = 1 ] && has 'no merge base' "$R"; } && ok "head-mode-no-base: no origin/HEAD, origin/main or origin/master refuses" || no "head-mode-no-base no ref: got $R"
R="$(gate_run "$N" rid normal --head "$P" --base-tip "$U")"
{ [ "${R%%|*}" = 1 ] && has 'no merge base' "$R"; } && ok "head-mode-no-base: an unrelated --base-tip refuses" || no "head-mode-no-base unrelated: got $R"

echo "=== head-mode-large-spec ==="
specs() { # <n> -> n task lines
  local i; printf '# Spec: x\nStatus: DRAFT\nLane: normal\n\n'; for i in $(seq 1 "$1"); do printf -- '- [ ] TASK-%s: x\n' "$i"; done
}
S1="$(commit_on pr-spec main docs/specs/SPEC-001-rid.md "$(specs 5)")"
R="$(gate_run "$W" rid normal --head "$S1")"
{ [ "${R%%|*}" = 1 ] && has 'is large' "$R" && has 'depth size docs/specs/SPEC-001-rid.md' "$R" && ! has "$T/tmpd" "$R"; } && ok "head-mode-large-spec: a large spec only in the head's tree is found; the message names the in-tree path" || no "head-mode-large-spec: got $R"
[ -z "$(ls -A "$T/tmpd")" ] && ok "head-mode-large-spec: no temp file is left behind" || no "head-mode-large-spec: left $(ls "$T/tmpd")"
R="$(gate_run "$W" my-rid normal --head "$(commit_on pr-spec-h main docs/specs/SPEC-002-my-rid.md "$(specs 5)")")"
{ [ "${R%%|*}" = 1 ] && has 'is large' "$R"; } && ok "head-mode-large-spec: a hyphenated slug matches the root glob" || no "head-mode-large-spec hyphenated: got $R"
R="$(gate_run "$W" co-rid normal --head "$(commit_on pr-spec-c main tools/x/docs/specs/SPEC-003-co-rid.md "$(specs 5)")")"
{ [ "${R%%|*}" = 1 ] && has 'is large' "$R"; } && ok "head-mode-large-spec: a co-located spec is found" || no "head-mode-large-spec co-located: got $R"
R="$(gate_run "$W" rid normal --head "$(commit_on pr-spec-s main docs/specs/SPEC-001-rid.md "$(specs 1)")")"
[ "${R%%|*}" = 0 ] && ok "head-mode-large-spec: a small spec passes" || no "head-mode-large-spec small: got $R"
R="$(gate_run "$W" rid normal --head "$(commit_on pr-spec-n main tools/x/docs/specs/SPEC-abc-rid.md "$(specs 5)")")"
[ "${R%%|*}" = 0 ] && ok "head-mode-large-spec: a co-located name with a non-numeric id is not a spec" || no "head-mode-large-spec non-numeric: got $R"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
