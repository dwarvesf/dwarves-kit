#!/usr/bin/env bash
# test-test-affected-replay.sh -- tests/lib/test-affected-replay.sh in a throwaway git repo: a
# correct selection replays with 0 MISS, a selection that drops a suite that runs the changed
# file reports MISS and exits 1, and the touched rule counts a run/source and not a bare mention.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
has() { grep -qF -- "$2" <<<"$1" && ok "$3" || bad "$3 (missing '$2' in: $1)"; }
hasnt() { grep -qF -- "$2" <<<"$1" && bad "$3 (unexpected '$2' in: $1)" || ok "$3"; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
R="$W/repo"; mkdir -p "$R/tests/lib" "$R/bin" "$R/lib/x"; cd "$R"
git init -q -b main . && git config user.email t@t && git config user.name t
cp "$KIT_DIR/tests/lib/test-affected-replay.sh" tests/lib/
cp "$KIT_DIR/bin/test-affected" bin/test-affected
echo 1.0.0 > VERSION
printf 'echo a\n' > lib/x/runner-thing.sh
printf 'echo m\n' > lib/x/mentioned-only.sh
printf '#!/bin/bash\nbash lib/x/runner-thing.sh\n'      > tests/test-runs.sh
printf '#!/bin/bash\ncd lib/x && bash runner-thing.sh\n' > tests/test-runs-base.sh
printf '#!/bin/bash\necho mentioned-only.sh\n'            > tests/test-mention.sh
git add -A && git commit -qm base
echo "# edit" >> lib/x/runner-thing.sh; echo "# edit" >> lib/x/mentioned-only.sh
git commit -qam "edit libs"
sha="$(git rev-parse HEAD)"
printf '7 %s\n' "$sha" > "$W/prs"
export TA_REPLAY_PRS_FILE="$W/prs" TMPDIR="$W"
RP="$R/tests/lib/test-affected-replay.sh"

echo "== a correct selection has no MISS =="
out="$(bash "$RP" --n 1 --ta "$R/bin/test-affected" 2>&1)"; rc=$?
has "$out" "1 PRs, picked 2, 0 MISS" "the path run and the basename run are selected, the bare mention is not"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc, want 0 ($out)"

echo "== a selection that omits a suite that runs the file is a MISS =="
printf '#!/bin/bash\necho "test-affected: 1 changed files against x"\necho "  tests/test-runs.sh  (references x)"\n' > "$W/stub"
out="$(bash "$RP" --n 1 --ta "$W/stub" 2>&1)"; rc=$?
has "$out" "MISS #7 tests/test-runs-base.sh" "the suite that runs the file by basename is reported"
hasnt "$out" "MISS #7 tests/test-mention.sh" "a bare mention is not required"
[ "$rc" = 1 ] && ok "exit 1 on a MISS" || bad "exit $rc, want 1"

echo "== --compare adds the before column =="
out="$(bash "$RP" --n 1 --ta "$R/bin/test-affected" --compare "$W/stub" 2>&1)"
has "$out" "picked 1 before," "the compare copy fills the before count"
has "$out" ", 0 MISS" "the copy under test still has no MISS"

echo "== usage =="
bash "$RP" --n 0 >/dev/null 2>&1; [ "$?" = 2 ] && ok "--n 0 exits 2" || bad "--n 0 did not exit 2"
bash "$RP" --bogus >/dev/null 2>&1; [ "$?" = 2 ] && ok "unknown flag exits 2" || bad "unknown flag did not exit 2"

echo "test-test-affected-replay: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
