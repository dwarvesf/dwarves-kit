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

echo "=== head-mode-config-at-tip (negative control) ==="
# X: an old main commit with lane_gates off, a current tip with it on; the PR head branches from the old one
X="$T/cfgrepo"; git init -q -b main "$X"
printf '[gate]\nlane_gates = false\n' > "$X/.kit.toml"; printf 'hello\n' > "$X/README.md"
git -C "$X" add -A; git -C "$X" commit -qm old; XOLD="$(git -C "$X" rev-parse HEAD)"
printf '[gate]\nlane_gates = true\n' > "$X/.kit.toml"; git -C "$X" commit -qam tip; XTIP="$(git -C "$X" rev-parse HEAD)"
git -C "$X" switch -q -c pr-old "$XOLD"; mkdir -p "$X/src/auth"; echo 'export const y = 1' > "$X/src/auth/login.ts"
git -C "$X" add -A; git -C "$X" commit -qm pr; XH="$(git -C "$X" rev-parse HEAD)"
git -C "$X" switch -q --detach "$XOLD"   # the orchestrator checkout is stale too
R="$(gate_run "$X" rid normal --head "$XH" --base-tip "$XTIP")"
{ [ "${R%%|*}" = 1 ] && has 'hard path (auth: src/auth/login.ts' "$R"; } && ok "head-mode-config-at-tip: a head cut from a lane_gates=false commit is gated by the tip's config" || no "head-mode-config-at-tip: got $R"
R="$(gate_run "$X" rid normal --head "$XH" --base-tip "$XOLD")"
[ "${R%%|*}" = 0 ] && ok "head-mode-config-at-tip: control, the tip itself having lane_gates off passes" || no "head-mode-config-at-tip control: got $R"

echo "=== head-mode-extras-at-tip ==="
Z="$T/extrarepo"; git init -q -b main "$Z"
printf '[gate]\nlane_gates = true\n' > "$Z/.kit.toml"; printf 'hello\n' > "$Z/README.md"
git -C "$Z" add -A; git -C "$Z" commit -qm old; ZOLD="$(git -C "$Z" rev-parse HEAD)"
printf '[gate]\nlane_gates = true\n[lanes]\nextra_hard_paths = "^payments/"\n' > "$Z/.kit.toml"; git -C "$Z" commit -qam tip; ZTIP="$(git -C "$Z" rev-parse HEAD)"
git -C "$Z" switch -q -c pr-old "$ZOLD"; mkdir -p "$Z/payments"; echo 'x' > "$Z/payments/x.ts"
git -C "$Z" add -A; git -C "$Z" commit -qm pr; ZH="$(git -C "$Z" rev-parse HEAD)"
git -C "$Z" switch -q --detach "$ZOLD"
R="$(gate_run "$Z" rid normal --head "$ZH" --base-tip "$ZTIP")"
{ [ "${R%%|*}" = 1 ] && has 'hard path (extra: payments/x.ts' "$R"; } && ok "head-mode-extras-at-tip: an extra_hard_paths entry committed at the tip applies to a stale head and checkout" || no "head-mode-extras-at-tip: got $R"

echo "=== head-mode-base-is-head (negative control) ==="
T2="$(commit_on tip2 main README.md 'moved on')"
R="$(gate_run "$W" rid normal --head "$MAIN" --base-tip "$MAIN")"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED: mega gate: merge base equals head' "$R"; } && ok "head-mode-base-is-head: head equal to the tip is refused" || no "head-mode-base-is-head same: got $R"
R="$(gate_run "$W" rid normal --head "$MAIN" --base-tip "$T2")"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED: mega gate: merge base equals head' "$R"; } && ok "head-mode-base-is-head: a head already inside the tip is refused" || no "head-mode-base-is-head ancestor: got $R"
R="$(gate_run "$W" rid normal --head "$T2" --base-tip "$MAIN")"
[ "${R%%|*}" = 0 ] && ok "head-mode-base-is-head: a head ahead of the tip still passes" || no "head-mode-base-is-head ahead: got $R"

echo "=== merge: fetch the PR head and gate on it ==="
# stubs: pr number selects the answer; the real gh is never called
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\ncat "%s/head-$1"\n' "$T" > "$T/prhead"
printf '#!/usr/bin/env bash\ncat "%s/base-$1"\n' "$T" > "$T/prbase"
printf '#!/usr/bin/env bash\nprintf "false\\037\\037clear PR\\n"\n' > "$T/prinfo"
printf '#!/usr/bin/env bash\necho README.md\n' > "$T/prfiles"
chmod +x "$T/prhead" "$T/prbase" "$T/prinfo" "$T/prfiles"
GHLOG="$T/gh.log"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 0\n' "$GHLOG" > "$T/bin/gh"; chmod +x "$T/bin/gh"
# merge_run <pr> [base-stub] -> "<exit>|<output>"; head-<pr> and base-<pr> hold the stub answers
merge_run() {
  local out rc; : > "$GHLOG"
  out="$(cd "$W" && PATH="$T/bin:$PATH" MEGA_MERGE_ROOT="$W" MEGA_MERGE_GATE_LEDGER="$T/gl" MEGA_MERGE_PR_HEAD_CMD="$T/prhead" \
    MEGA_MERGE_PR_BASE_CMD="${2:-$T/prbase}" MEGA_MERGE_PR_INFO_CMD="$T/prinfo" MEGA_MERGE_PR_FILES_CMD="$T/prfiles" \
    bash "$MM" merge "$1" rid normal --execute 2>&1)"; rc=$?
  printf '%s|%s' "$rc" "$out"
}
merged() { grep -qF "pr merge $1" "$GHLOG"; }
norefs() { [ -z "$(git -C "$W" for-each-ref refs/kit)" ]; }

git -C "$W" push -q origin "$P:refs/pull/7/head" 2>/dev/null
echo "$P" > "$T/head-7"; echo main > "$T/base-7"
R="$(merge_run 7)"
{ [ "${R%%|*}" = 1 ] && has 'hard path (auth: src/auth/login.ts' "$R" && ! merged 7; } && ok "merge-floor-sees-pr-head: the PR head's auth change is refused from the main checkout" || no "merge-floor-sees-pr-head: got $R; gh: $(cat "$GHLOG")"
norefs && ok "merge-floor-sees-pr-head: the private refs are deleted after the gate" || no "merge-floor-sees-pr-head: left $(git -C "$W" for-each-ref refs/kit)"

echo "=== merge-fetch-mismatch (negative control) ==="
C="$(commit_on pr-clean main README.md 'hello again')"
git -C "$W" push -q -f origin "$C:refs/pull/7/head" 2>/dev/null
R="$(merge_run 7)"
{ [ "${R%%|*}" = 1 ] && has 'head moved after it was pinned' "$R" && ! merged 7; } && ok "merge-fetch-mismatch: another commit at refs/pull/7/head is refused" || no "merge-fetch-mismatch moved: got $R"
norefs && ok "merge-fetch-mismatch: the private refs are deleted on a mismatch" || no "merge-fetch-mismatch: left refs"
git -C "$W" remote set-url origin "$T/nonexistent.git"
R="$(merge_run 7)"
{ [ "${R%%|*}" = 1 ] && has 'cannot fetch PR #7' "$R" && ! merged 7; } && ok "merge-fetch-mismatch: an unreachable origin is refused" || no "merge-fetch-mismatch unreachable: got $R"
git -C "$W" remote set-url origin "$O"

echo "=== merge-fetch-timeout ==="
mkdir -p "$T/slowbin"; REALGIT="$(command -v git)"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = fetch ] && exec sleep 25; done\nexec "%s" "$@"\n' "$REALGIT" > "$T/slowbin/git"; chmod +x "$T/slowbin/git"
t0=$SECONDS
R="$(cd "$W" && PATH="$T/slowbin:$T/bin:$PATH" MEGA_MERGE_FETCH_TIMEOUT=1 MEGA_MERGE_ROOT="$W" MEGA_MERGE_GATE_LEDGER="$T/gl" MEGA_MERGE_PR_HEAD_CMD="$T/prhead" \
  MEGA_MERGE_PR_BASE_CMD="$T/prbase" MEGA_MERGE_PR_INFO_CMD="$T/prinfo" MEGA_MERGE_PR_FILES_CMD="$T/prfiles" bash "$MM" merge 7 rid normal --execute 2>&1)"; rc=$?
{ [ "$rc" = 1 ] && has 'cannot fetch PR #7' "$R" && [ $((SECONDS - t0)) -lt 15 ]; } && ok "merge-fetch-timeout: a hung fetch is killed and refused" || no "merge-fetch-timeout: rc=$rc after $((SECONDS - t0))s: $R"

echo "=== merge-clean-pr-head ==="
git -C "$W" push -q -f origin "$C:refs/pull/9/head" 2>/dev/null
echo "$C" > "$T/head-9"; echo main > "$T/base-9"
R="$(merge_run 9)"
{ [ "${R%%|*}" = 0 ] && merged "9 --squash --delete-branch --match-head-commit $C" ; } && ok "merge-clean-pr-head: a README-only PR merges with the pinned head" || no "merge-clean-pr-head: got $R; gh: $(cat "$GHLOG")"
norefs && ok "merge-clean-pr-head: no private refs remain after a merge" || no "merge-clean-pr-head: left refs"

echo "=== merge-mega-base ==="
M="$(commit_on mega/x main db/migrations/0001.sql 'create table t;')"
git -C "$W" push -q origin "$M:refs/heads/mega/x" 2>/dev/null
Q="$(commit_on pr-wave mega/x README.md 'wave change')"
git -C "$W" push -q origin "$Q:refs/pull/8/head" 2>/dev/null
echo "$Q" > "$T/head-8"; echo mega/x > "$T/base-8"
R="$(merge_run 8)"
{ [ "${R%%|*}" = 0 ] && merged "8 --squash --delete-branch --match-head-commit $Q" && ! has 'hard path' "$R"; } && ok "merge-mega-base: a wave PR is diffed against its own base branch, not main" || no "merge-mega-base: got $R"
echo main > "$T/base-8"
R="$(merge_run 8)"
{ [ "${R%%|*}" = 1 ] && has 'hard path (migration' "$R"; } && ok "merge-mega-base: the same PR diffed against main hits the earlier wave's migration" || no "merge-mega-base against main: got $R"

echo "=== merge-base-read ==="
rm -f "$T/base-7"; echo "$P" > "$T/head-7"; git -C "$W" push -q -f origin "$P:refs/pull/7/head" 2>/dev/null
R="$(merge_run 7)"
{ [ "${R%%|*}" = 1 ] && has 'cannot fetch PR #7' "$R" && ! merged 7; } && ok "merge-base-read: an unreadable base branch is refused" || no "merge-base-read unreadable: got $R"
echo 'a..b' > "$T/base-7"
R="$(merge_run 7)"
{ [ "${R%%|*}" = 1 ] && has 'cannot fetch PR #7' "$R" && ! merged 7; } && ok "merge-base-read: a base name check-ref-format rejects is refused" || no "merge-base-read bad name: got $R"
echo nobranch > "$T/base-7"
R="$(merge_run 7)"
{ [ "${R%%|*}" = 1 ] && has 'cannot fetch PR #7' "$R" && ! merged 7; } && ok "merge-base-read: a base branch missing on origin is refused" || no "merge-base-read missing: got $R"

echo "=== merge-base-retarget ==="
printf '#!/usr/bin/env bash\nn=$(cat "%s/cnt" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "%s/cnt"\nif [ "$n" -ge 2 ]; then echo mega/x; else echo main; fi\n' "$T" "$T" > "$T/prbase-flip"
chmod +x "$T/prbase-flip"; rm -f "$T/cnt"
R="$(merge_run 9 "$T/prbase-flip")"
{ [ "${R%%|*}" = 1 ] && has 'base branch changed' "$R" && ! merged 9; } && ok "merge-base-retarget: a base that changed after the gate is refused" || no "merge-base-retarget: got $R"

echo "=== merge-fetch-override ==="
# MEGA_MERGE_PR_FETCH_CMD replaces the fetch and the comparison; merge still validates what it prints
override_run() { # <stub-body> -> "<exit>|<output>"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/prfetch"; chmod +x "$T/prfetch"; : > "$GHLOG"; echo main > "$T/base-9"
  local out rc
  out="$(cd "$W" && PATH="$T/bin:$PATH" MEGA_MERGE_PR_FETCH_CMD="$T/prfetch" MEGA_MERGE_ROOT="$W" MEGA_MERGE_GATE_LEDGER="$T/gl" MEGA_MERGE_PR_HEAD_CMD="$T/prhead" \
    MEGA_MERGE_PR_BASE_CMD="$T/prbase" MEGA_MERGE_PR_INFO_CMD="$T/prinfo" MEGA_MERGE_PR_FILES_CMD="$T/prfiles" bash "$MM" merge 9 rid normal --execute 2>&1)"; rc=$?
  printf '%s|%s' "$rc" "$out"
}
R="$(override_run "echo $MAIN")"
{ [ "${R%%|*}" = 0 ] && merged 9; } && ok "merge-fetch-override: a stub printing a real base tip merges" || no "merge-fetch-override good: got $R"
R="$(override_run 'echo not-a-sha')"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED' "$R" && ! merged 9; } && ok "merge-fetch-override: a printed tip that is not 40 hex is refused" || no "merge-fetch-override garbage: got $R"
R="$(override_run 'echo 2222222222222222222222222222222222222222')"
{ [ "${R%%|*}" = 1 ] && has 'BLOCKED' "$R" && ! merged 9; } && ok "merge-fetch-override: a printed tip that is not a commit is refused" || no "merge-fetch-override missing: got $R"
R="$(override_run 'exit 1')"
{ [ "${R%%|*}" = 1 ] && has 'cannot fetch PR #9' "$R" && ! merged 9; } && ok "merge-fetch-override: a failing stub is refused" || no "merge-fetch-override fail: got $R"

echo "=== docs-match ==="
for v in MEGA_MERGE_PR_BASE_CMD MEGA_MERGE_PR_FETCH_CMD MEGA_MERGE_FETCH_TIMEOUT; do
  grep -qE "^\| $v \|" "$KIT/lib/config/module-registry.md" && ok "docs-match: module-registry.md has a row for $v" || no "docs-match: no registry row for $v"
done
grep -E '^\| MEGA_MERGE_PR_(BASE|FETCH)_CMD \|' "$KIT/lib/config/module-registry.md" | grep -q 'Test-only' && ok "docs-match: the base and fetch overrides are marked test-only" || no "docs-match: registry rows not marked test-only"
grep -q 'MEGA_MERGE_PR_FETCH_CMD' "$KIT/docs/CHANGELOG.md" && grep -q 'refs/pull/<n>/head' "$KIT/docs/CHANGELOG.md" && ok "docs-match: CHANGELOG names the PR-head gate and the new knob" || no "docs-match: CHANGELOG line missing"
SEC14="$(sed -n 14p "$KIT/SECURITY.md")"
{ ! has 'read the orchestrator checkout' "$SEC14" && ! has 'local `HEAD`' "$SEC14" && has 'PR head' "$SEC14" && has 'base branch' "$SEC14"; } && ok "docs-match: SECURITY.md line 14 says the gate checks the PR head against its base branch" || no "docs-match: SECURITY.md line 14 still describes the local HEAD"
{ grep -q 'PR-chosen spec' "$KIT/SECURITY.md" && grep -q 'classifier' "$KIT/SECURITY.md"; } && ok "docs-match: SECURITY.md names the PR-chosen spec and the silent passes" || no "docs-match: SECURITY.md residuals missing"
grep -q 'refs/pull/<n>/head' "$KIT/commands/mega.md" && ok "docs-match: commands/mega.md says what the gate reads" || no "docs-match: commands/mega.md not updated"
! grep -q 'read the local checkout, not' "$MM" && ok "docs-match: the head-pin comment in merge() no longer says the gate reads the local checkout" || no "docs-match: stale head-pin comment"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
