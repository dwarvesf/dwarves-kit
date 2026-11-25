#!/usr/bin/env bash
# test-mega-tick.sh -- `mega tick`: record a merged sub-goal from gh truth (lib/mega/mega.sh cmd_tick).
#
# Fixtures: a LEDGER repo (holds docs/megagoals/m1/ROADMAP.md, on branch run/m1, default main) and a
# separate CODE repo (default develop), each with a bare origin and origin/HEAD set. A stub gh
# (GH_BIN) returns canned PR JSON keyed on the PR number and logs argv, cwd and GH_PROMPT_DISABLED.
# Attempt stores live in both repos' git dirs; ATTEMPT_REGISTRY_DIR is unset so the verb probes both.
# Every case starts from a fresh copy of the template. Case ids (C1..C52) follow the spec's test plan.
#
# Run: bash tests/test-mega-tick.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEGA="$KIT_DIR/lib/mega/mega.sh"
AS="$KIT_DIR/lib/goal/attempt-state.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got [$2], want [$3])"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1 (missing [$3] in [$2])" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-mega-tick.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
unset ATTEMPT_REGISTRY_DIR MEGAGOALS_ROOT CODE_ROOT REPO_ROOT MEGA_TICK_TEST MEGA_TICK_TEST_PAUSE_FILE ATTEMPT_STATE_BIN
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export MEGA_TICK_LOCK_WAIT_SECS=1
G() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------- gh stub
GHS="$TMP/bin/gh"; mkdir -p "$TMP/bin"
cat > "$GHS" <<'STUB'
#!/usr/bin/env bash
[ -t 0 ] && tty=yes || tty=no
printf 'argv=%s cwd=%s prompt=%s stdin_tty=%s\n' "$*" "$PWD" "${GH_PROMPT_DISABLED:-}" "$tty" >> "${GH_LOG:-/dev/null}"
[ "$1 $2" = "pr view" ] || exit 2
n="$3"; st=MERGED; base=develop; head=feat/x; oid=""; url="https://github.com/acme/code/pull/$n"
rep() { printf '%s' "$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1$1" | cut -c1-40; }
case "$n" in
  96) head=feat/vn-40-drag-by-labels; oid=0c471eb999dcbbcb51723e4ea22912d217e73fb8 ;;
  37) head=feat/13; oid=281992a3530ea05c37709663c04ea2514dec0654 ;;
  21) head=ci/release-pipeline; oid=$(rep 2) ;;
  57) oid=$(rep 5) ;;
  38|48|120|121|190) oid=$(rep 4) ;;
  102) st=OPEN; head=feat/vn-44-uat ;;
  103) head=feat/vn-44-uat ;;
  104) base=feat/stack; head=feat/vn-44-uat; oid=$(rep a) ;;
  105) echo "GraphQL: Could not resolve to a PullRequest with the number of 105. (repository.pullRequest)" >&2; exit 1 ;;
  106) st=OPEN; head=feat/vn-44-uat; oid=$(rep b) ;;
  107) echo "not json"; exit 0 ;;
  108) head=feat/someone-else; oid=$(rep c) ;;
  109) head=feat/vn-44-uat; oid=$(rep d); url="https://github.com/acme/code/pull/110" ;;
  111) head="feat/$(printf '%0300d' 0)"; oid=$(rep e) ;;
  *) echo "GraphQL: Could not resolve to a PullRequest with the number of $n." >&2; exit 1 ;;
esac
if [ -n "$oid" ]; then mc="{\"oid\":\"$oid\"}"; else mc=null; fi
printf '{"baseRefName":"%s","headRefName":"%s","mergeCommit":%s,"state":"%s","url":"%s"}\n' "$base" "$head" "$mc" "$st" "$url"
STUB
chmod +x "$GHS"

# ---------------------------------------------------------------- template
TPL="$TMP/tpl"; mkdir -p "$TPL"
G init -q --bare "$TPL/ledger.git"; G init -q --bare "$TPL/code.git"
G init -q "$TPL/ledger"
MD="$TPL/ledger/docs/megagoals/m1"; mkdir -p "$MD/goals"
cat > "$MD/ROADMAP.md" <<'EOF'
# Mega-goal: m1

## Sub-goals

Format on completion: `- [x] NN-slug, PR #N, merged <sha>`.

- [x] 01-release-pipeline, PR #21, merged 06376c9 (human gate, merged by Han)
- [x] 07-axlive-press-ladder, PR #38, merged 1cbdac4 (G2 fix-forward PR #41, 8af731e; seam fix PR #72, 128b043)
- [x] 13-hintkit-labels, PR #37, merged 2819920
- [x] 21-app-shell-seams, PR #57, merged OPEN
- [ ] 40-drag-by-labels, prose, `auto`, PR #
- [ ] 44-uat-pack-release-gate, README, UAT plan ... held for Han. `gate`, PR #
- [~] 45-parked-thing, rehomed
- [ ] 46-dup-line, a
- [ ] 46-dup-line, b
- [x] 47-legacy (repo), prose, PR #190 merged cb64f15 (note)
- [x] 48-backslash, PR #48, merged abcdef1 (path C:\tmp\x and a \n literal)
- [ ] 49-open-other, prose, PR #
- [ ] 50-glob, prose, PR #
- [ ] 51-cites, see PR #96 for context, PR #
- [ ] 52-cites-other, see PR #37, PR #
EOF
chmod 644 "$MD/ROADMAP.md"
printf '# goal\n\n**Branch:** ci/release-pipeline (existing)\n' > "$MD/goals/01-release-pipeline.md"
printf '# goal\n\n**Branch:** `feat/13`\n' > "$MD/goals/13-hintkit-labels.md"
printf '# goal\n\n**Branch:** feat/x\r\n' > "$MD/goals/21-app-shell-seams.md"
printf '# goal\n\n**Branch:** feat/vn-40-drag-by-labels\n' > "$MD/goals/40-drag-by-labels.md"
printf '# goal\n\n**Branch:** feat/vn-44-uat\n' > "$MD/goals/44-uat-pack-release-gate.md"
printf '# goal\n\n**Branch:** feat/*\n' > "$MD/goals/50-glob.md"
G -C "$TPL/ledger" add -A; G -C "$TPL/ledger" commit -q -m base
G -C "$TPL/ledger" remote add origin "$TPL/ledger.git"; G -C "$TPL/ledger" push -q origin main 2>/dev/null
G -C "$TPL/ledger" remote set-head origin main; G -C "$TPL/ledger" checkout -q -b run/m1
G init -q -b develop "$TPL/code"; G -C "$TPL/code" commit -q --allow-empty -m base
G -C "$TPL/code" remote add origin "$TPL/code.git"; G -C "$TPL/code" push -q origin develop 2>/dev/null
G -C "$TPL/code" remote set-head origin develop

# ---------------------------------------------------------------- per-case helpers
fresh() {
  rm -rf "$TMP/w"; cp -R "$TPL" "$TMP/w"; WK="$TMP/w"
  MDIR="$WK/ledger/docs/megagoals/m1"; RM="$MDIR/ROADMAP.md"
  CS="$WK/code/.git/kit-attempts"; LS="$WK/ledger/.git/kit-attempts"; mkdir -p "$CS"
  : > "$WK/gh.log"
}
asc() { ATTEMPT_REGISTRY_DIR="$CS" bash "$AS" "$@" >/dev/null; }
asl() { ATTEMPT_REGISTRY_DIR="$LS" bash "$AS" "$@" >/dev/null; }
stores() { find "$CS" "$LS" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done; }
snap() { cp "$RM" "$WK/rm.orig" 2>/dev/null; SNAP="$(stores)"; }
tick() {
  OUT="$(cd "$WK/ledger" && GH_BIN="$GHS" GH_LOG="$WK/gh.log" bash "$MEGA" tick m1 "$@" \
    --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" 2>"$WK/err")"; RC=$?
  ERR="$(cat "$WK/err")"
}
unchanged() {
  if cmp -s "$RM" "$WK/rm.orig" && [ "$(stores)" = "$SNAP" ]; then ok "$1: ROADMAP and stores unchanged"
  else no "$1: something changed"; fi
}
refused() { # <label> <want-rc>
  eq "$1: exit $2" "$RC" "$2"; unchanged "$1"
}
difflines() { diff "$WK/rm.orig" "$RM" | grep -c '^[<>]'; }
status_of() { ATTEMPT_REGISTRY_DIR="$1" bash "$AS" status "$2" 2>&1 | head -2 | tr '\n' ' '; }

# ================================================================ TASK-003: audit, branch, line
echo "== happy path, incidents, idempotence =="
fresh; asc dispatch 40-drag-by-labels w1; snap
tick 40-drag-by-labels --pr 96
eq "C1 exit 0" "$RC" 0
has "C1 AUDIT line" "$OUT" "AUDIT acme/code PR #96 MERGED base=develop head=feat/vn-40-drag-by-labels merge=0c471eb999dcbbcb51723e4ea22912d217e73fb8"
has "C1 BRANCH ok" "$OUT" "BRANCH ok feat/vn-40-drag-by-labels"
has "C1 TICKED" "$OUT" "TICKED 40-drag-by-labels: - [x] 40-drag-by-labels, PR #96, merged 0c471eb"
eq "C1 line written" "$(grep -c -x -F -- '- [x] 40-drag-by-labels, PR #96, merged 0c471eb' "$RM")" 1
eq "C1 one-line diff" "$(difflines)" 2
has "C1 attempt committed" "$(status_of "$CS" 40-drag-by-labels)" "state=done winner=a1 ref=PR#96@0c471eb"
eq "C1 mode kept" "$(stat -f %Lp "$RM" 2>/dev/null || stat -c %a "$RM")" 644
[ ! -e "$MDIR/.orchestrate/flip.lock" ] && [ -d "$MDIR/.orchestrate" ] && ok "C1 lock released, .orchestrate kept" || no "C1 lock state"
eq "C47 one gh call" "$(wc -l < "$WK/gh.log" | tr -d ' ')" 1
has "C47 gh argv" "$(cat "$WK/gh.log")" "argv=pr view 96 --json state,mergeCommit,baseRefName,headRefName,url cwd=$WK/code prompt=1 stdin_tty=no"
cp "$RM" "$WK/rm.after1"
tick 40-drag-by-labels --pr 96
eq "C4 rerun exit 0" "$RC" 0
has "C4 UNCHANGED" "$OUT" "UNCHANGED 40-drag-by-labels"
has "C4 NOOP" "$OUT" "NOOP 40-drag-by-labels already committed"
cmp -s "$RM" "$WK/rm.after1" && ok "C4 bytes identical" || no "C4 bytes changed"

fresh; snap; tick 13-hintkit-labels --pr 37 --keep-note
refused "C2 --keep-note with no annotation" 3
tick 13-hintkit-labels --pr 37
eq "C2 exit 0" "$RC" 0
eq "C2 wrong sha repaired" "$(grep -c -x -F -- '- [x] 13-hintkit-labels, PR #37, merged 281992a' "$RM")" 1
has "C2 backticked branch line" "$OUT" "BRANCH ok feat/13"
has "C33 ATTEMPT none names the store" "$OUT" "ATTEMPT none 13-hintkit-labels (no 13-hintkit-labels.task in $CS"

fresh; snap; tick 21-app-shell-seams --pr 57
eq "C3 exit 0" "$RC" 0
eq "C3 merged OPEN repaired" "$(grep -c -x -F -- '- [x] 21-app-shell-seams, PR #57, merged 5555555' "$RM")" 1
has "C3 CR-ended branch line" "$OUT" "BRANCH ok feat/x"

echo "== gh audit refusals =="
for c in "C5 102" "C6 103" "C7 104" "C8 105" "C9 107" "C10 106" "C11a 109" "C11b 111"; do
  set -- $c; fresh; snap; tick 44-uat-pack-release-gate --pr "$2"; refused "$1 PR $2" 1
done
fresh; snap; tick 44-uat-pack-release-gate --pr 105; has "C8 gh stderr in message" "$ERR" "GraphQL: Could not resolve"
fresh; snap; tick 44-uat-pack-release-gate --pr 103; has "C6 retry hint" "$ERR" "retry shortly"
fresh; snap
OUT="$(cd "$WK/ledger" && GH_BIN="$TMP/nope/gh" bash "$MEGA" tick m1 44-uat-pack-release-gate --pr 96 --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" 2>"$WK/err")"; RC=$?; ERR="$(cat "$WK/err")"
refused "C12a gh missing" 1
NJ="$TMP/nojq"; mkdir -p "$NJ"
for t in bash git env dirname tr wc cut sed awk head cat mktemp rm; do ln -sf "$(command -v "$t")" "$NJ/$t"; done
OUT="$(cd "$WK/ledger" && PATH="$NJ" GH_BIN="$GHS" bash "$MEGA" tick m1 44-uat-pack-release-gate --pr 96 --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" 2>"$WK/err")"; RC=$?; ERR="$(cat "$WK/err")"
refused "C12b jq missing" 1; has "C12b names jq" "$ERR" "jq"
fresh; G -C "$WK/code" update-ref -d refs/remotes/origin/HEAD; G -C "$WK/code" update-ref -d refs/remotes/origin/develop; snap
tick 40-drag-by-labels --pr 96
refused "C13 no code-root default" 1; has "C13 names the fix" "$ERR" "remote set-head origin -a"

echo "== branch check =="
fresh; snap; tick 44-uat-pack-release-gate --pr 108; refused "C14 goal branch differs from head" 3
fresh; snap; tick 44-uat-pack-release-gate --pr 108 --branch-override "branch renamed after review"
eq "C48 override exit 0" "$RC" 0
has "C48 AUDIT carries reason" "$OUT" 'branch-override=branch\ renamed\ after\ review'
has "C48 BRANCH override" "$OUT" "BRANCH override feat/vn-44-uat != feat/someone-else"
has "C48 reason on stderr" "$ERR" "branch renamed after review"
fresh; snap; tick 50-glob --pr 121; refused "C49 glob branch is a literal" 3
fresh; snap; tick 01-release-pipeline --pr 21 --note "merged by Han"
eq "C21 exit 0" "$RC" 0
has "C21 suffixed branch line" "$OUT" "BRANCH ok ci/release-pipeline"
eq "C21 note" "$(grep -c -x -F -- '- [x] 01-release-pipeline, PR #21, merged 2222222 (merged by Han)' "$RM")" 1

echo "== line refusals =="
fresh; snap; tick 49-open-other --pr 57; refused "C15 another done line names the PR" 3
fresh; snap; tick 99-missing --pr 120; refused "C16a no line" 3
fresh; snap; tick 13-hintkit --pr 120; refused "C16b prefix id" 3
fresh; snap; tick 13-hintkit-labels --pr 96 --branch-override "test the PR compare"; refused "C17 ticked with another PR" 3
fresh; snap; tick 45-parked-thing --pr 120; refused "C18a parked" 3
fresh; snap; tick 46-dup-line --pr 120; refused "C18b duplicate" 3
fresh; snap; tick 47-legacy --pr 190; refused "C19 legacy shape" 3
fresh; snap; tick 07-axlive-press-ladder --pr 38; refused "C20 annotation needs a flag" 3
tick 07-axlive-press-ladder --pr 38 --keep-note
eq "C20 keep-note exit 0" "$RC" 0
eq "C20 annotation kept" "$(grep -c -x -F -- '- [x] 07-axlive-press-ladder, PR #38, merged 4444444 (G2 fix-forward PR #41, 8af731e; seam fix PR #72, 128b043)' "$RM")" 1
fresh; snap; tick 40-drag-by-labels --pr 96 --note 'x\n- [x] 99-other, PR #1, merged abc1234'
eq "C22 exit 0" "$RC" 0
eq "C22 literal backslash-n kept on one line" "$(grep -c -x -F -- '- [x] 40-drag-by-labels, PR #96, merged 0c471eb (x\n- [x] 99-other, PR #1, merged abc1234)' "$RM")" 1
eq "C22 no forged line" "$(grep -c '^- \[x\] 99-other' "$RM")" 0
eq "C22 one-line diff" "$(difflines)" 2
fresh; snap; tick 48-backslash --pr 48 --keep-note
eq "C23 exit 0" "$RC" 0
eq "C23 backslash annotation byte-exact" "$(grep -c -x -F -- '- [x] 48-backslash, PR #48, merged 4444444 (path C:\tmp\x and a \n literal)' "$RM")" 1
eq "C23 one-line diff" "$(difflines)" 2
fresh; snap; tick 40-drag-by-labels --pr 96 --note "$(printf 'a\nb')"; refused "C24a note with a newline" 3
fresh; snap; tick 40-drag-by-labels --pr 96 --note "$(printf 'a\tb')"; refused "C24b note with a tab" 3
fresh; snap; tick 40-drag-by-labels --pr 96 --note "$(printf 'a\177b')"; refused "C24c note with 0x7f" 3
fresh; awk '{ if (index($0, "48-backslash")) sub(/path/, "pa\tth"); print }' "$RM" > "$WK/x" && cat "$WK/x" > "$RM"; snap
tick 48-backslash --pr 48 --keep-note; refused "C24d kept annotation with a tab" 3
fresh; awk '{ printf "%s\r\n", $0 }' "$RM" > "$WK/x" && cat "$WK/x" > "$RM"; snap
tick 40-drag-by-labels --pr 96; refused "C25 CRLF line" 3
fresh; snap; tick 40-drag-by-labels --pr 96 --note "$(printf '%0201d' 0)"; refused "C50a note over 200 bytes" 3
fresh; snap; tick 44-uat-pack-release-gate --pr 108 --branch-override "$(printf 'a\tb')"; refused "C50b override reason with a tab" 3
fresh; snap; tick 52-cites-other --pr 120
eq "C52 open line citing another PR ticks" "$RC" 0
eq "C52 line" "$(grep -c -x -F -- '- [x] 52-cites-other, PR #120, merged 4444444' "$RM")" 1
fresh; snap; tick 51-cites --pr 120; eq "C1b open line citing PR #96 in prose does not block" "$RC" 0

echo "== C51: the line changes between the read and the write =="
fresh; snap; PF="$WK/pause"; : > "$PF"
( cd "$WK/ledger" && MEGA_TICK_TEST=1 MEGA_TICK_TEST_PAUSE_FILE="$PF" GH_BIN="$GHS" bash "$MEGA" tick m1 40-drag-by-labels --pr 96 \
    --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" >"$WK/bg.out" 2>"$WK/bg.err"; echo $? > "$WK/bg.rc" ) &
BG=$!
i=0; while [ ! -s "$MDIR/.orchestrate/flip.lock/pid" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.5
awk '{ if (index($0, "40-drag-by-labels, prose")) sub(/prose/, "edited by someone"); print }' "$RM" > "$WK/x" && cat "$WK/x" > "$RM"
rm -f "$PF"; wait "$BG"
eq "C51 exit 8" "$(cat "$WK/bg.rc")" 8
eq "C51 other writer's edit kept" "$(grep -c 'edited by someone' "$RM")" 1
eq "C51 no temp left" "$(find "$MDIR" -maxdepth 1 -name '.roadmap.tick.*' | wc -l | tr -d ' ')" 0

# ================================================================ TASK-004: ledger, attempt, lock, write
echo "== ledger checkout =="
fresh; G -C "$WK/ledger" checkout -q main; snap; tick 40-drag-by-labels --pr 96; refused "C26 on the default branch" 4
fresh; G -C "$WK/ledger" checkout -q --detach; snap; tick 40-drag-by-labels --pr 96; refused "C27 detached HEAD" 4
fresh; G -C "$WK/ledger" update-ref -d refs/remotes/origin/HEAD; G -C "$WK/ledger" update-ref -d refs/remotes/origin/main; snap
tick 40-drag-by-labels --pr 96; refused "C28 no ledger default" 4; has "C28 names the fix" "$ERR" "remote set-head origin -a"
fresh; mv "$RM" "$MDIR/ROADMAP.real"; ln -s ROADMAP.real "$RM"; cp "$MDIR/ROADMAP.real" "$WK/rm.orig"; SNAP="$(stores)"
tick 40-drag-by-labels --pr 96
eq "C29 symlinked ROADMAP exit 8" "$RC" 8
[ -L "$RM" ] && cmp -s "$MDIR/ROADMAP.real" "$WK/rm.orig" && ok "C29 link and target unchanged" || no "C29 changed"

echo "== attempt store =="
fresh; asl dispatch 40-drag-by-labels w1; snap; tick 40-drag-by-labels --pr 96
eq "C30 record in the ledger store: exit 0" "$RC" 0
has "C30 ledger record done" "$(status_of "$LS" 40-drag-by-labels)" "state=done"
eq "C30 code store untouched" "$(find "$CS" -type f | wc -l | tr -d ' ')" 0
fresh; asl dispatch 40-drag-by-labels w1; asc dispatch 40-drag-by-labels w2; snap; tick 40-drag-by-labels --pr 96
refused "C31 record in both stores" 5
fresh; printf '#!/usr/bin/env bash\n[ "$1" = dir ] && exit 3\nexec bash %q "$@"\n' "$AS" > "$WK/as-nodir"; snap
OUT="$(cd "$WK/ledger" && ATTEMPT_STATE_BIN="$WK/as-nodir" GH_BIN="$GHS" bash "$MEGA" tick m1 40-drag-by-labels --pr 96 --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" 2>"$WK/err")"; RC=$?
refused "C32 store does not resolve" 5
fresh; rmdir "$CS"; snap; tick 40-drag-by-labels --pr 96
refused "C34a no store dir anywhere" 5; has "C34a hint" "$ERR" "--no-attempt"
tick 40-drag-by-labels --pr 96 --no-attempt
eq "C34b --no-attempt exit 0" "$RC" 0; has "C34b skipped line" "$OUT" "ATTEMPT skipped 40-drag-by-labels (--no-attempt)"
fresh; asc dispatch 40-drag-by-labels w1; snap; tick 40-drag-by-labels --pr 96 --no-attempt; refused "C35 --no-attempt with a record" 5
fresh; snap; tick 40-drag-by-labels --pr 96 --attempt a1; refused "C35b --attempt with no record" 5
lost_then_live() {
  asc dispatch 40-drag-by-labels w1
  ATTEMPT_NOW=1000 asc mark-disconnected 40-drag-by-labels --grace 0
  ATTEMPT_NOW=2000 asc lose-attempt 40-drag-by-labels
}
fresh; lost_then_live; asc dispatch 40-drag-by-labels w2; snap
tick 40-drag-by-labels --pr 96 --attempt a1; refused "C36a lost attempt named" 5
tick 40-drag-by-labels --pr 96 --attempt a; refused "C36b --attempt prefix of a field" 5
tick 40-drag-by-labels --pr 96
eq "C36c live a2 resolves" "$RC" 0; has "C36c a2 committed" "$(status_of "$CS" 40-drag-by-labels)" "winner=a2"
fresh; lost_then_live; snap; tick 40-drag-by-labels --pr 96; refused "C37a queued, no live attempt" 5
fresh; asc dispatch 40-drag-by-labels w1; asc commit-result 40-drag-by-labels a1 "PR#96@0c471eb"; snap
tick 40-drag-by-labels --pr 96 --attempt a9; refused "C37b done task, non-winner named" 5
fresh; asc dispatch 40-drag-by-labels w1; asc commit-result 40-drag-by-labels a1 "PR#96@1111111"; snap
tick 40-drag-by-labels --pr 96
eq "C38 exit 0" "$RC" 0
has "C38 ref mismatch on stderr" "$ERR" "ATTEMPT ref-mismatch 40-drag-by-labels recorded=PR#96@1111111 now=PR#96@0c471eb"

echo "== lock =="
fresh; mkdir -p "$MDIR/.orchestrate/flip.lock"; sleep 30 & SPID=$!; echo "$SPID" > "$MDIR/.orchestrate/flip.lock/pid"; snap
t0=$(date +%s); MEGA_TICK_LOCK_WAIT_SECS=0.4 tick 40-drag-by-labels --pr 96; t1=$(date +%s)
kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
refused "C39 live holder" 7; has "C39 names the pid" "$ERR" "live pid $SPID"
[ $((t1 - t0)) -le 5 ] && ok "C39 bounded wait ($((t1 - t0))s)" || no "C39 waited $((t1 - t0))s"
fresh; mkdir -p "$MDIR/.orchestrate/flip.lock"; sh -c 'exit 0' & DPID=$!; wait "$DPID"; echo "$DPID" > "$MDIR/.orchestrate/flip.lock/pid"; snap
tick 40-drag-by-labels --pr 96
eq "C40 dead holder reclaimed: exit 0" "$RC" 0
[ ! -e "$MDIR/.orchestrate/flip.lock" ] && ok "C40 lock released after" || no "C40 lock left"
fresh; mkdir -p "$MDIR/.orchestrate/flip.lock"; snap
MEGA_TICK_LOCK_WAIT_SECS=0 tick 40-drag-by-labels --pr 96; refused "C41 no pid file" 7; has "C41 rmdir hint" "$ERR" "rmdir"
fresh; : > "$MDIR/.orchestrate"; snap; tick 40-drag-by-labels --pr 96; refused "C42 .orchestrate is a file" 8

echo "== C43: the held lock reads fresh to the driver; the pause seam is test-only =="
fresh; snap; PF="$WK/pause"; : > "$PF"
( cd "$WK/ledger" && exec env MEGA_TICK_TEST=1 MEGA_TICK_TEST_PAUSE_FILE="$PF" GH_BIN="$GHS" bash "$MEGA" tick m1 40-drag-by-labels --pr 96 \
    --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" >/dev/null 2>&1 ) &
BG=$!
i=0; while [ ! -s "$MDIR/.orchestrate/flip.lock/pid" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
stale="$(FLIP_LOCK_STALE_SECS=0 TIER4_CLOSE=0 bash -c 'source "$1/lib/queue/orchestrate.sh" >/dev/null 2>&1; _lock_stale "$2"; echo $?' _ "$KIT_DIR" "$MDIR/.orchestrate/flip.lock")"
eq "C43 driver reads the held lock as fresh" "$stale" 1
eq "C43 pid file holds the verb's pid" "$(cat "$MDIR/.orchestrate/flip.lock/pid" 2>/dev/null)" "$BG"
rm -f "$PF"; wait "$BG"
fresh; snap; PF="$WK/pause"; : > "$PF"; t0=$(date +%s)
MEGA_TICK_TEST_PAUSE_FILE="$PF" tick 40-drag-by-labels --pr 96; t1=$(date +%s)
eq "C43b no pause without MEGA_TICK_TEST" "$RC" 0; [ $((t1 - t0)) -le 10 ] && ok "C43b fast" || no "C43b paused"

echo "== write path and commit failure =="
fresh; printf '#!/usr/bin/env bash\n[ "$1" = commit-result ] && exit 1\nexec bash %q "$@"\n' "$AS" > "$WK/as-nocommit"; asc dispatch 40-drag-by-labels w1; snap
OUT="$(cd "$WK/ledger" && ATTEMPT_STATE_BIN="$WK/as-nocommit" GH_BIN="$GHS" bash "$MEGA" tick m1 40-drag-by-labels --pr 96 --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" 2>"$WK/err")"; RC=$?; ERR="$(cat "$WK/err")"
eq "C44 exit 6" "$RC" 6
eq "C44 ROADMAP written" "$(grep -c -x -F -- '- [x] 40-drag-by-labels, PR #96, merged 0c471eb' "$RM")" 1
has "C44 settle command" "$ERR" "commit-result 40-drag-by-labels a1 PR#96@0c471eb"
tick 40-drag-by-labels --pr 96
eq "C44 re-run converges" "$RC" 0; has "C44 re-run UNCHANGED" "$OUT" "UNCHANGED"; has "C44 committed now" "$(status_of "$CS" 40-drag-by-labels)" "state=done"
fresh; mkdir -p "$WK/badbin"; printf '#!/bin/sh\nexit 1\n' > "$WK/badbin/chmod"; chmod +x "$WK/badbin/chmod"; snap
OUT="$(cd "$WK/ledger" && PATH="$WK/badbin:$PATH" GH_BIN="$GHS" bash "$MEGA" tick m1 40-drag-by-labels --pr 96 --megagoals-root "$WK/ledger/docs/megagoals" --code-root "$WK/code" 2>"$WK/err")"; RC=$?
refused "C45 chmod fails" 8
eq "C45 no temp left" "$(find "$MDIR" -maxdepth 1 -name '.roadmap.tick.*' | wc -l | tr -d ' ')" 0

echo "== usage =="
fresh; snap
for a in "SG-01 --pr 96" "40-drag-by-labels --pr 96 --note x --keep-note" "40-drag-by-labels --pr 96 --attempt a1 --no-attempt" \
         "40-drag-by-labels" "40-drag-by-labels --pr 096" "40-drag-by-labels --pr 1234567890" "40-drag-by-labels --pr 9a"; do
  tick $a; eq "C46 usage: $a" "$RC" 64
done
for s in "../x" ".hidden"; do
  OUT="$(cd "$WK/ledger" && GH_BIN="$GHS" bash "$MEGA" tick "$s" 40-drag-by-labels --pr 96 2>/dev/null)"; RC=$?
  eq "C46 mega slug $s" "$RC" 64
done
unchanged "C46 all usage errors"

echo
echo "test-mega-tick: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
