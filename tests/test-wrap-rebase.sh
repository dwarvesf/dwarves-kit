#!/usr/bin/env bash
# test-wrap-rebase.sh -- the rebase cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ------------------------------------------------------- rebase
# `wrap rebase <worktree>`: a worktree branch onto origin/<default>. Each case builds its own
# origin (a plain repo on main, so origin moves without a push), a main clone, and a feature
# worktree. The generator is a stub at the kit's own
# path: FEATURES.md is the sorted listing of specs/, so a regeneration is deterministic. Env
# knobs make it fail (RB_GEN_FAIL), do nothing (RB_GEN_NOOP), or also rewrite a README count
# (RB_GEN_README) or a non-ASCII tracked path (RB_GEN_UTF8). A grep over git output reads it through process substitution: under
# pipefail, `git log | grep -q` reports the SIGPIPE, never the match.
echo
echo "=== rebase: a worktree branch onto origin/<default>, only the safe conflicts resolved ==="
rb_build() { # rb_build <name> [--no-generator] -- sets RBO (origin), RBC (main clone), RBW (worktree)
  local name="$1" work="$TMPD/rbw-src-$1"
  mkdir -p "$work/lib/registry" "$work/specs" "$work/docs" "$work/_meta"
  git -C "$work" init -q; gitc "$work"; git -C "$work" symbolic-ref HEAD refs/heads/main
  cat > "$work/lib/registry/feature-registry.sh" <<'GEN'
#!/usr/bin/env bash
root="$(cd "$(dirname "$0")/../.." && pwd)"
[ -n "${RB_GEN_FAIL:-}" ] && exit 3
[ -n "${RB_GEN_NOOP:-}" ] && exit 0
ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"
[ -n "${RB_GEN_UTF8:-}" ] && echo changed > "$root/docs/café.md"
[ -n "${RB_GEN_README:-}" ] && printf 'count: %s\n' "$(ls "$root/specs" | wc -l | tr -d ' ')" > "$root/README.md"
exit 0
GEN
  [ "${2:-}" = "--no-generator" ] && rm -rf "$work/lib"
  echo a > "$work/specs/a.md"
  echo a.md > "$work/docs/FEATURES.md"
  printf '# Changelog\n\n## [Unreleased]\n\n- one\n- two\n' > "$work/docs/CHANGELOG.md"
  printf 'line\n' > "$work/other.md"
  printf 'count: 1\n' > "$work/README.md"
  echo base > "$work/docs/café.md"
  printf '| ID | Status |\n' > "$work/_meta/BACKLOG.md"
  printf '_meta/BACKLOG.md merge=union\n' > "$work/.gitattributes"
  git -C "$work" add -A; git -C "$work" commit -qm base
  RBO="$work"
  RBC="$TMPD/rbc-$name"; git clone -q "$work" "$RBC"; gitc "$RBC"
  RBW="$TMPD_P/rbwt-$name"
  git -C "$RBC" worktree add -q -b feat/rb "$RBW" origin/main >/dev/null 2>&1
}
rb_gen() { ( cd "$1" && bash lib/registry/feature-registry.sh generate ); }
rb_origin() { git -C "$RBO" add -A; git -C "$RBO" commit -qm "$1"; } # origin moves on main
rb_branch() { git -C "$RBW" add -A; git -C "$RBW" commit -qm "$1"; }
rb_run() { "$WRAP" rebase "$RBW" 2>&1; }
rb_tip() { git -C "$RBW" rev-parse HEAD; }
rb_rebasing() { local gd; gd="$(git -C "$RBW" rev-parse --path-format=absolute --git-dir)"; [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; }

echo "--- nothing to rebase"
rb_build none; echo b > "$RBW/b.txt"; rb_branch "feat: b"; old="$(rb_tip)"
out="$(rb_run)"; rc=$?
chk "rebase: already on origin exits 0" "$rc"
chk_has "rebase: says nothing to rebase" "$out" "nothing to rebase: feat/rb already contains origin/main"
chk "rebase: nothing to rebase leaves HEAD" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- clean rebase, disjoint changes, no regen commit when FEATURES is fresh"
rb_build clean; echo o > "$RBO/o.txt"; rb_origin "feat: o"; echo b > "$RBW/b.txt"; rb_branch "feat: b"
out="$(rb_run)"; rc=$?
chk "rebase: clean rebase exits 0" "$rc"
chk_has "rebase: clean rebase reports 0 stops" "$out" "0 stop(s) resolved"
chk "rebase: origin/main is an ancestor after" "$(git -C "$RBW" merge-base --is-ancestor origin/main HEAD; echo $?)"
chk "rebase: no regen commit when FEATURES is fresh" "$([ "$(git -C "$RBW" log -1 --format=%s)" = "feat: b" ]; echo $?)"
chk_has "rebase: says it did not push" "$out" "not pushed"

echo "--- a union-declared file both sides appended to: git keeps both, no stop"
rb_build union; echo '| O-1 | open |' >> "$RBO/_meta/BACKLOG.md"; rb_origin "board: o"
echo '| B-1 | open |' >> "$RBW/_meta/BACKLOG.md"; rb_branch "board: b"
out="$(rb_run)"; rc=$?
chk "rebase: union file exits 0" "$rc"
chk_has "rebase: union keeps origin's row" "$(cat "$RBW/_meta/BACKLOG.md")" "O-1"
chk_has "rebase: union keeps the branch's row" "$(cat "$RBW/_meta/BACKLOG.md")" "B-1"
chk_has "rebase: union needs no stop" "$out" "0 stop(s) resolved"

echo "--- CHANGELOG: both sides only added bullets, both kept"
rb_build clpure
printf '# Changelog\n\n## [Unreleased]\n\n- o-new\n- one\n- two\n' > "$RBO/docs/CHANGELOG.md"; rb_origin "docs: o"
printf '# Changelog\n\n## [Unreleased]\n\n- b-new\n- one\n- two\n' > "$RBW/docs/CHANGELOG.md"; rb_branch "docs: b"
out="$(rb_run)"; rc=$?
cl="$(cat "$RBW/docs/CHANGELOG.md")"
chk "rebase: pure-addition CHANGELOG exits 0" "$rc"
chk_has "rebase: CHANGELOG keeps origin's bullet" "$cl" "- o-new"
chk_has "rebase: CHANGELOG keeps the branch's bullet" "$cl" "- b-new"
chk "rebase: CHANGELOG keeps every base line once" "$([ "$(grep -c '^- one$' "$RBW/docs/CHANGELOG.md")" -eq 1 ] && [ "$(grep -c '^- two$' "$RBW/docs/CHANGELOG.md")" -eq 1 ]; echo $?)"
chk_has "rebase: CHANGELOG counted as one stop" "$out" "1 stop(s) resolved"
chk_no "rebase: CHANGELOG carries no marker" "$cl" "<<<<<<<"

echo "--- CHANGELOG: a reworded bullet refuses"
rb_build clword
printf '# Changelog\n\n## [Unreleased]\n\n- o-new\n- one reworded\n- two\n' > "$RBO/docs/CHANGELOG.md"; rb_origin "docs: reword"
printf '# Changelog\n\n## [Unreleased]\n\n- b-new\n- one\n- two\n' > "$RBW/docs/CHANGELOG.md"; rb_branch "docs: b"; old="$(rb_tip)"
out="$(rb_run)"; rc=$?
chk "rebase: reworded CHANGELOG exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: reworded CHANGELOG refused by name" "$out" "REFUSED feat/rb: conflict in docs/CHANGELOG.md"
chk "rebase: reworded CHANGELOG restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"
chk "rebase: reworded CHANGELOG leaves no rebase in progress" "$(rb_rebasing && echo 1 || echo 0)"

echo "--- generated FEATURES conflict: regenerated at the stop"
rb_build gen; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"
out="$(rb_run)"; rc=$?
chk "rebase: generated stop exits 0" "$rc"
chk_has "rebase: generated stop counted" "$out" "1 stop(s) resolved"
chk "rebase: FEATURES equals a fresh generate" "$([ "$(cat "$RBW/docs/FEATURES.md")" = "$(printf 'a.md\nb.md\no.md')" ]; echo $?)"
chk "rebase: no marker in any rebased commit" "$(grep -qE '^\+(<{7}|>{7})' < <(git -C "$RBW" log -p origin/main..HEAD) && echo 1 || echo 0)"
chk "rebase: no merge commit on the branch" "$([ -z "$(git -C "$RBW" rev-list --min-parents=2 origin/main..HEAD)" ]; echo $?)"
chk "rebase: one pick and no regen commit (committed only after the rebase)" "$([ "$(git -C "$RBW" rev-list --count origin/main..HEAD)" -eq 1 ]; echo $?)"
chk "rebase: worktree clean after" "$([ -z "$(git -C "$RBW" status --porcelain)" ]; echo $?)"

echo "--- the generator's side effect on a tracked README is staged by name"
rb_build side; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"
out="$(RB_GEN_README=1 rb_run)"; rc=$?
chk "rebase: side-effect stop exits 0" "$rc"
chk "rebase: README count landed in the pick" "$([ "$(git -C "$RBW" show HEAD:README.md)" = "count: 3" ]; echo $?)"
chk "rebase: worktree clean after the side effect" "$([ -z "$(git -C "$RBW" status --porcelain)" ]; echo $?)"

echo "--- a pick left empty by the regeneration is dropped"
rb_build empty; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"
echo extra >> "$RBW/docs/FEATURES.md"; rb_branch "chore: hand-edit features"
out="$(rb_run)"; rc=$?
chk "rebase: empty-pick run exits 0" "$rc"
chk "rebase: the empty pick is gone" "$(grep -q 'hand-edit' < <(git -C "$RBW" log --format=%s origin/main..HEAD) && echo 1 || echo 0)"
chk "rebase: one pick survives" "$([ "$(git -C "$RBW" rev-list --count origin/main..HEAD)" -eq 1 ]; echo $?)"

echo "--- final regeneration records a FEATURES left stale by origin"
rb_build final; echo o > "$RBO/specs/o.md"; rb_origin "feat: o without regen"
echo b > "$RBW/b.txt"; rb_branch "feat: b"
out="$(rb_run)"; rc=$?
chk "rebase: final-regen run exits 0" "$rc"
chk "rebase: last commit is the regen" "$([ "$(git -C "$RBW" log -1 --format=%s)" = "chore(registry): regenerate FEATURES.md after rebase" ]; echo $?)"
chk "rebase: the regen commit holds a fresh FEATURES" "$([ "$(git -C "$RBW" show HEAD:docs/FEATURES.md)" = "$(printf 'a.md\no.md')" ]; echo $?)"

echo "--- a hand-written conflict refuses and restores the old tip"
rb_build refuse; echo o-line > "$RBO/other.md"; rb_origin "o"; echo b-line > "$RBW/other.md"; rb_branch "b"; old="$(rb_tip)"
out="$(rb_run)"; rc=$?
chk "rebase: refused conflict exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: refused conflict named" "$out" "REFUSED feat/rb: conflict in other.md"
chk "rebase: refused conflict restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"
chk "rebase: refused conflict leaves no rebase in progress" "$(rb_rebasing && echo 1 || echo 0)"

echo "--- a mixed stop names only the unhandled path"
rb_build mixed; echo o-line > "$RBO/other.md"; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "o"
echo b-line > "$RBW/other.md"; echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "b"; old="$(rb_tip)"
out="$(rb_run)"; rc=$?
chk "rebase: mixed stop exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: mixed stop names other.md" "$out" "REFUSED feat/rb: conflict in other.md"
chk_no "rebase: mixed stop does not name FEATURES" "$out" "FEATURES.md"
chk "rebase: mixed stop restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- leftover markers: a no-op generator never reaches a commit"
rb_build markers; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"; old="$(rb_tip)"
out="$(RB_GEN_NOOP=1 rb_run)"; rc=$?
chk "rebase: leftover markers exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: leftover markers named" "$out" "MARKERS feat/rb: docs/FEATURES.md"
chk "rebase: leftover markers restore the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"
chk "rebase: no marker in any reachable commit" "$(grep -qE '^\+(<{7}|>{7})' < <(git -C "$RBW" log -p --all) && echo 1 || echo 0)"
chk "rebase: leftover markers leave no rebase in progress" "$(rb_rebasing && echo 1 || echo 0)"

echo "--- a failing generator aborts"
rb_build genfail; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"; old="$(rb_tip)"
out="$(RB_GEN_FAIL=1 rb_run)"; rc=$?
chk "rebase: generator failure exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: generator failure named" "$out" "GENERATOR FAILED feat/rb"
chk_no "rebase: a mid-rebase generator failure is not an after-rebase one" "$out" "AFTER REBASE"
chk "rebase: generator failure restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- no generator in the repo: FEATURES is an ordinary file"
rb_build nogen --no-generator
printf 'a.md\no.md\n' > "$RBO/docs/FEATURES.md"; rb_origin "o"; printf 'a.md\nb.md\n' > "$RBW/docs/FEATURES.md"; rb_branch "b"
out="$(rb_run)"; rc=$?
chk "rebase: no generator exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: no generator refuses FEATURES by name" "$out" "REFUSED feat/rb: conflict in docs/FEATURES.md"

echo "--- a delete conflict on a union-declared file refuses with the union note"
rb_build uniondel; git -C "$RBO" rm -q _meta/BACKLOG.md; rb_origin "drop board"
echo '| B-1 | open |' >> "$RBW/_meta/BACKLOG.md"; rb_branch "board: b"
out="$(rb_run)"; rc=$?
chk "rebase: union delete conflict exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: union delete conflict carries the note" "$out" "_meta/BACKLOG.md (merge=union, delete/rename conflict)"

echo "--- the stop bound aborts"
rb_build bound; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"; old="$(rb_tip)"
out="$(WRAP_REBASE_MAX_STOPS=0 rb_run)"; rc=$?
chk "rebase: stop bound exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: stop bound named" "$out" "STOP BOUND feat/rb"
chk "rebase: stop bound restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- a failed abort says so"
rb_build abortfail; echo o-line > "$RBO/other.md"; rb_origin "o"; echo b-line > "$RBW/other.md"; rb_branch "b"
mkdir -p "$TMPD/rbgit"
printf '#!/bin/bash\ncase " $* " in *" rebase --abort "*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v git)" > "$TMPD/rbgit/git"
chmod +x "$TMPD/rbgit/git"
out="$(PATH="$TMPD/rbgit:$PATH" "$WRAP" rebase "$RBW" 2>&1)"; rc=$?
chk "rebase: failed abort exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: failed abort named" "$out" "ABORT FAILED feat/rb: run git rebase --abort in $RBW"
git -C "$RBW" rebase --abort >/dev/null 2>&1

echo "--- preflight refusals"
rb_build pre; echo o > "$RBO/o.txt"; rb_origin "o"; echo b > "$RBW/b.txt"; rb_branch "b"; old="$(rb_tip)"
out="$("$WRAP" rebase "$RBC" 2>&1)"; rc=$?
chk "rebase: main checkout exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: main checkout named" "$out" "is the main checkout"
git -C "$RBC" worktree add -q -b master "$TMPD_P/rbwt-pre-master" origin/main >/dev/null 2>&1
out="$("$WRAP" rebase "$TMPD_P/rbwt-pre-master" 2>&1)"; rc=$?
chk "rebase: a protected branch name exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: protected branch named" "$out" "default or a protected branch name"
git -C "$RBC" worktree add -q --detach "$TMPD_P/rbwt-pre-det" origin/main >/dev/null 2>&1
out="$("$WRAP" rebase "$TMPD_P/rbwt-pre-det" 2>&1)"; rc=$?
chk "rebase: detached HEAD exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: detached HEAD named" "$out" "detached HEAD"
echo dirt >> "$RBW/b.txt"
out="$(rb_run)"; rc=$?
chk "rebase: dirty tracked file exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: dirty tracked file named" "$out" "tracked changes"
git -C "$RBW" checkout -q -- b.txt
gd="$(git -C "$RBW" rev-parse --path-format=absolute --git-dir)"
: > "$gd/index.lock"; touch -t 202001010000 "$gd/index.lock"
out="$(rb_run)"; rc=$?
chk "rebase: held index.lock exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: held index.lock named" "$out" "index.lock held by another writer"
rm -f "$gd/index.lock"
git -C "$RBC" remote set-url origin "$TMPD/no-such-origin"
out="$(rb_run)"; rc=$?
chk "rebase: fetch failure exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: fetch failure named" "$out" "fetch origin main failed"
git -C "$RBC" remote set-url origin "$RBO"
echo x-line > "$RBO/other.md"; rb_origin "x"; echo y-line > "$RBW/other.md"; rb_branch "y"; old="$(rb_tip)"
git -C "$RBW" fetch -q origin 2>/dev/null
GIT_EDITOR=true git -C "$RBW" rebase origin/main >/dev/null 2>&1
out="$(rb_run)"; rc=$?
chk "rebase: a rebase already in progress exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: in-progress operation named" "$out" "already in progress"
git -C "$RBW" rebase --abort >/dev/null 2>&1
chk "rebase: preflight refusals leave HEAD" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- CHANGELOG: both sides added the same line refuses"
rb_build cldup
printf '# Changelog\n\n## [Unreleased]\n\n- a\n- shared\n- one\n- two\n' > "$RBO/docs/CHANGELOG.md"; rb_origin "docs: o"
printf '# Changelog\n\n## [Unreleased]\n\n- shared\n- c\n- one\n- two\n' > "$RBW/docs/CHANGELOG.md"; rb_branch "docs: b"; old="$(rb_tip)"
out="$(rb_run)"; rc=$?
chk "rebase: a line both sides added exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: a line both sides added refused by name" "$out" "REFUSED feat/rb: conflict in docs/CHANGELOG.md"
chk "rebase: a line both sides added restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- a recorded rerere resolution never resolves a stop (rerere pinned off)"
rb_build rerere; git -C "$RBC" config rerere.enabled true; git -C "$RBC" config rerere.autoupdate true
echo o-line > "$RBO/other.md"; rb_origin "o"; echo b-line > "$RBW/other.md"; rb_branch "b"; old="$(rb_tip)"
git -C "$RBW" fetch -q origin 2>/dev/null
GIT_EDITOR=true git -C "$RBW" rebase origin/main >/dev/null 2>&1
echo resolved-line > "$RBW/other.md"; git -C "$RBW" rerere >/dev/null 2>&1; git -C "$RBW" rebase --abort >/dev/null 2>&1
chk "rebase: the rerere fixture recorded a resolution" "$(ls "$(git -C "$RBC" rev-parse --path-format=absolute --git-common-dir)"/rr-cache/*/postimage >/dev/null 2>&1; echo $?)"
out="$(rb_run)"; rc=$?
chk "rebase: a recorded resolution still exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: a recorded resolution is still refused by name" "$out" "REFUSED feat/rb: conflict in other.md"
chk "rebase: a recorded resolution restores the old tip" "$([ "$(rb_tip)" = "$old" ]; echo $?)"

echo "--- a stacked branch ref never moves (updateRefs pinned off)"
rb_build stack; git -C "$RBC" config rebase.updateRefs true
echo o > "$RBO/o.txt"; rb_origin "o"
echo b1 > "$RBW/b1.txt"; rb_branch "b1"; git -C "$RBW" branch feat/rb-lower; lower="$(git -C "$RBW" rev-parse feat/rb-lower)"
echo b2 > "$RBW/b2.txt"; rb_branch "b2"
out="$(rb_run)"; rc=$?
chk "rebase: stacked branch run exits 0" "$rc"
chk "rebase: the stacked branch ref did not move" "$([ "$(git -C "$RBW" rev-parse feat/rb-lower)" = "$lower" ]; echo $?)"

echo "--- a non-ASCII path the generator changes is staged as itself"
rb_build utf8; echo o > "$RBO/specs/o.md"; rb_gen "$RBO"; rb_origin "feat: o"
echo b > "$RBW/specs/b.md"; rb_gen "$RBW"; rb_branch "feat: b"
out="$(RB_GEN_UTF8=1 rb_run)"; rc=$?
chk "rebase: non-ASCII side effect exits 0" "$rc"
chk "rebase: the non-ASCII path landed in the pick" "$([ "$(git -C "$RBW" show 'HEAD:docs/café.md')" = "changed" ]; echo $?)"
chk "rebase: worktree clean after the non-ASCII side effect" "$([ -z "$(git -C "$RBW" status --porcelain)" ]; echo $?)"

echo "--- a failing final regeneration says the branch is already rebased"
rb_build finalfail; echo o > "$RBO/o.txt"; rb_origin "o"; echo b > "$RBW/b.txt"; rb_branch "b"
out="$(RB_GEN_FAIL=1 rb_run)"; rc=$?
chk "rebase: final-pass failure exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "rebase: final-pass failure carries its own prefix" "$out" "AFTER REBASE GENERATOR FAILED feat/rb"
chk "rebase: final-pass failure leaves the branch rebased" "$(git -C "$RBW" merge-base --is-ancestor origin/main HEAD; echo $?)"

echo "--- /kit:wrap step 10 runs the verb before the push and re-verifies"
step2="$(sed -n '/^\*\*Land, one repo at a time/,$p' "$KIT_DIR/commands/wrap.md" | grep -m1 '^2\. ')"
chk_has "step 10 landing step 2 runs wrap rebase first" "$step2" '2. Run `bin/wrap rebase <wt>` first'
chk_has "step 10 re-runs the verification after a rebase" "$step2" "re-run the worker's verification command"
chk_no "step 10 drops the moved-past condition" "$(cat "$KIT_DIR/commands/wrap.md")" 'when `origin/<default>` moved past it'

echo "--- usage"
out="$("$WRAP" rebase 2>&1)"; rc=$?
chk "rebase: no argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" rebase "$RBW" "$RBW" 2>&1)"; rc=$?
chk "rebase: two arguments exit 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" rebase --bogus "$RBW" 2>&1)"; rc=$?
chk "rebase: unknown flag exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
mkdir -p "$TMPD/rb-notrepo"
out="$("$WRAP" rebase "$TMPD/rb-notrepo" 2>&1)"; rc=$?
chk "rebase: not a repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "bin/wrap header names rebase" "$(sed -n '1,25p' "$KIT_DIR/bin/wrap")" "wrap rebase <worktree>"

echo "=== rebase: flags packed into one positional are refused ==="
out="$("$WRAP" rebase " --x" 2>&1)"; rc=$?
chk "packed arg to rebase exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "packed arg to rebase names the packed-flags refusal" "$out" "wrap.sh rebase: argument '"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-rebase: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-rebase: all $PASS passed"
