#!/usr/bin/env bash
# test-wrap-adopt-codes.sh -- the adopt verb's exit code branches on a row code, never on the
# row's words. Every scenario runs twice, once through the real kit and once through a copy
# whose row phrases are reworded (reword_adopt); the exit codes and the failure count must match.
# Also pins the `adopted; FAILED ...` row (a merged adoption whose tidy step failed) as a failure.
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh lib/wrap/wrap-ship.sh
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

CLAUDE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; export CLAUDE_DIR

adopt_clone() { # adopt_clone <name> -- a bare remote plus a clean unadopted clone on main
  local name="$1" work="$TMPD/aw-$1" bare="$TMPD/abare-$1" clone="$TMPD/aclone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/a.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$bare"
  git clone -q "$bare" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  printf '%s\n' "$clone"
}

adopt_apply() { # adopt_apply <clone> <bare> -- `$WRAP adopt --apply` with the gh stub wired for create/merge
  local c="$1" b="$2"
  GH_STUB_OPEN_HEAD_chore_kit_adopt="${GH_STUB_OPEN_HEAD_chore_kit_adopt:-[]}" \
  GH_STUB_CREATE_NUM="${GH_STUB_CREATE_NUM:-7}" \
  GH_STUB_LAND_REPO="$c/.claude/worktrees/kit-adopt" \
  GH_STUB_LAND_REMOTE="$b" \
  GH_STUB_LAND_BRANCH="chore/kit-adopt" \
  GH_STUB_LAND_DEF="main" \
  "$WRAP" adopt --apply "$c" 2>&1
}

printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPD/adopt-nothing.sh"; chmod +x "$TMPD/adopt-nothing.sh"
printf '#!/usr/bin/env bash\nbash "%s/lib/adopt.sh" "$1" || exit $?\nmkdir -p "$1/src"; echo x > "$1/src/x.sh"\n' "$KIT_DIR" \
  > "$TMPD/adopt-stray.sh"; chmod +x "$TMPD/adopt-stray.sh"

# run_scenarios <wrap bin> <tag> -- every row kind the reader sees. Sets SC_RCS (` name=rc` per
# scenario) and SC_OUT (every scenario's output).
SC_RCS=""; SC_OUT=""
rec() { SC_RCS="$SC_RCS $1=$2"; SC_OUT="$SC_OUT"$'\n'"$3"; }
run_scenarios() {
  local bin="$1" t="$2" c out rc zeros
  SC_RCS=""; SC_OUT=""

  c="$(adopt_clone "dry$t")"
  out="$("$bin" adopt "$c" 2>&1)"; rc=$?; rec dry "$rc" "$out"

  c="$(adopt_clone "skip$t")"
  bash "$KIT_DIR/lib/adopt.sh" "$c" >/dev/null 2>&1
  git -C "$c" add -A; git -C "$c" commit -qm adopt; git -C "$c" push -q origin main
  out="$("$bin" adopt "$c" 2>&1)"; rc=$?; rec skip "$rc" "$out"

  c="$(adopt_clone "ref$t")"; echo x > "$c/AGENTS.md"
  out="$("$bin" adopt "$c" 2>&1)"; rc=$?; rec refused "$rc" "$out"

  c="$(adopt_clone "gh$t")"
  out="$(GH_STUB_UNAUTH=1 "$bin" adopt "$c" 2>&1)"; rc=$?; rec ghnotok "$rc" "$out"

  c="$(adopt_clone "ok$t")"
  out="$(WRAP="$bin" adopt_apply "$c" "$TMPD/abare-ok$t")"; rc=$?; rec adopted "$rc" "$out"

  c="$(adopt_clone "nochg$t")"
  out="$(WRAP="$bin" WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-nothing.sh" \
    adopt_apply "$c" "$TMPD/abare-nochg$t")"; rc=$?; rec nochange "$rc" "$out"

  c="$(adopt_clone "stray$t")"
  out="$(WRAP="$bin" WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-stray.sh" \
    adopt_apply "$c" "$TMPD/abare-stray$t")"; rc=$?; rec failed "$rc" "$out"

  c="$(adopt_clone "pull$t")"
  echo local > "$c/local.txt"; git -C "$c" add -A; git -C "$c" commit -qm local
  out="$(WRAP="$bin" adopt_apply "$c" "$TMPD/abare-pull$t")"; rc=$?; rec mergednotadopted "$rc" "$out"

  # The bare origin refuses to delete a branch, so land merges, then prints FAILED delete.
  c="$(adopt_clone "tidy$t")"
  zeros="$(printf '%040d' 0)"; mkdir -p "$TMPD/abare-tidy$t/hooks"
  printf '#!/bin/sh\n[ "$3" = "%s" ] && { echo "no deletes" >&2; exit 1; }\nexit 0\n' "$zeros" \
    > "$TMPD/abare-tidy$t/hooks/update"
  chmod +x "$TMPD/abare-tidy$t/hooks/update"
  out="$(WRAP="$bin" adopt_apply "$c" "$TMPD/abare-tidy$t")"; rc=$?; rec adoptedfailed "$rc" "$out"
}

fail_count() { printf '%s\n' $1 | grep -vc '=0$'; }

echo "=== adopt codes: the real kit exits per row kind (1) ==="
run_scenarios "$WRAP" r
REAL_RCS="$SC_RCS"; REAL_OUT="$SC_OUT"
chk_has "1: dry run exits 0" "$REAL_RCS" " dry=0"
chk_has "1: skip exits 0" "$REAL_RCS" " skip=0"
chk_has "1: adopted exits 0" "$REAL_RCS" " adopted=0"
chk_has "1: refused exits 1" "$REAL_RCS" " refused=1"
chk_has "1: gh not ok exits 1" "$REAL_RCS" " ghnotok=1"
chk_has "1: failed exits 1" "$REAL_RCS" " failed=1"
chk_has "1: no change exits 1" "$REAL_RCS" " nochange=1"
chk_has "1: merged-not-adopted exits 1" "$REAL_RCS" " mergednotadopted=1"
chk_has "1: adopted-with-FAILED exits 1" "$REAL_RCS" " adoptedfailed=1"
chk_has "1: the FAILED row prints as it always did" "$REAL_OUT" "adopted; FAILED delete chore/kit-adopt on origin"
chk "1: six failures" "$([ "$(fail_count "$REAL_RCS")" -eq 6 ]; echo $?)"

echo "=== adopt codes: reworded row phrases keep every exit code (2) ==="
reword_adopt || exit 1
run_scenarios "$WRAP_ADOPT_REWORDED" w
chk "2: exit codes match the real kit" "$([ "$SC_RCS" = "$REAL_RCS" ]; echo $?)"
chk "2: failure count matches" "$([ "$(fail_count "$SC_RCS")" = "$(fail_count "$REAL_RCS")" ]; echo $?)"
chk_has "2: the reword took effect on a success row" "$SC_OUT" "landed"
chk_has "2: the reword took effect on a failure row" "$SC_OUT" "broke: adoption wrote src/x.sh"
chk_has "2: the reword took effect on a refusal row" "$SC_OUT" "declined: "
chk_has "2: the reword took effect on a dry-run row" "$SC_OUT" "dry run: would take"
chk_has "2: the reworded FAILED row still fails" "$SC_OUT" "landed; FAILED delete chore/kit-adopt on origin"
chk_no "2: no original success phrase survives" "$SC_OUT" "result: #7 adopted"
chk_no "2: no original failure phrase survives" "$SC_OUT" "result: - failed:"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-adopt-codes: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-adopt-codes: all $PASS passed"
