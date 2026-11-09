#!/usr/bin/env bash
# always: KIT_BOARDS_REGISTRY is honored by every boards-registry reader
# test-board-registry-env.sh -- one setting names the boards registry.
#
# The registry precedence is `--registry` flag > $KIT_BOARDS_REGISTRY > <repo-root>/_meta/boards.txt.
# runs-dashboard.py and mega.sh already honored it; board.sh (all, queue, mirror, status, writeback),
# board-mirror-cleanup.py and reflect/propose.py read only the repo default.
#
#   R1  board all: with the env unset, the repo default registry is read
#   R2  board all: the env wins over the repo default
#   R3  board all: --registry wins over the env
#   R4  board queue: the env wins over the repo default
#   R5  board-mirror-cleanup.py: the env is the --registry default
#   R6  reflect/propose.py: the env is the dedup cockpit default, LEARN_PROPOSE_COCKPIT still beats it
#
# Run: bash tests/test-board-registry-env.sh   (exit 0 = all green)
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARD="$KIT_DIR/lib/board/board.sh"
CLEANUP="$KIT_DIR/lib/board/board-mirror-cleanup.py"
PROPOSE="$KIT_DIR/lib/reflect/propose.py"

PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got [$2] want [$3])"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/dk-board-registry-env.XXXXXX")" || exit 1
T="$(cd "$T" && pwd -P)"   # drop the double slash and symlinks so path assertions compare like for like
trap 'rm -rf "$T"' EXIT

mkboard() { # mkboard <dir> <id-prefix>
  mkdir -p "$1/_meta"
  git init -q "$1"; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  cat > "$1/_meta/BACKLOG.md" <<BOARD
# Backlog
## Active queue
| ID | Title | Source | Target | Lane | Status |
|----|-------|--------|--------|------|--------|
| $2-001 | Row of $2 | test | TBD | tiny | queued |
BOARD
}

mkboard "$T/home-repo" HOME
mkboard "$T/other-repo" OTHER
mkboard "$T/flag-repo" FLAG
printf 'homeboard  %s/home-repo/_meta/BACKLOG.md\n' "$T" > "$T/home-repo/_meta/boards.txt"
printf 'otherboard  %s/other-repo/_meta/BACKLOG.md\n' "$T" > "$T/env-boards.txt"
printf 'flagboard  %s/flag-repo/_meta/BACKLOG.md\n' "$T" > "$T/flag-boards.txt"

run_board() { (cd "$T/home-repo" && env -u KIT_BOARDS_REGISTRY "$@"); }

echo "=== R1: env unset -> repo default registry ==="
out="$(run_board bash "$BOARD" all 2>&1)"
echo "$out" | grep -q 'HOME-001' && echo "$out" | grep -q 'OTHER-001' && bad "R1 read both" || ok "R1 does not read the env registry"
echo "$out" | grep -q 'HOME-001' && ok "R1 lists the default registry board" || bad "R1 lists the default registry board"

echo "=== R2: KIT_BOARDS_REGISTRY beats the repo default ==="
out="$(cd "$T/home-repo" && KIT_BOARDS_REGISTRY="$T/env-boards.txt" bash "$BOARD" all 2>&1)"
echo "$out" | grep -q 'OTHER-001' && ok "R2 lists the env registry board" || bad "R2 lists the env registry board"
echo "$out" | grep -q 'HOME-001' && bad "R2 still read the repo default" || ok "R2 ignores the repo default"

echo "=== R3: --registry beats the env ==="
out="$(cd "$T/home-repo" && KIT_BOARDS_REGISTRY="$T/env-boards.txt" bash "$BOARD" all --registry "$T/flag-boards.txt" 2>&1)"
echo "$out" | grep -q 'FLAG-001' && ok "R3 lists the flag registry board" || bad "R3 lists the flag registry board"
echo "$out" | grep -q 'OTHER-001' && bad "R3 still read the env registry" || ok "R3 ignores the env registry"

echo "=== R4: board queue honors the env ==="
out="$(cd "$T/home-repo" && KIT_BOARDS_REGISTRY="$T/nope/boards.txt" bash "$BOARD" queue 2>&1)"; rc=$?
check "R4 queue exits 1 on a missing env registry" "$rc" "1"
echo "$out" | grep -qF "$T/nope/boards.txt" && ok "R4 names the env registry path" || bad "R4 names the env registry path: $out"

echo "=== R5: board-mirror-cleanup.py --registry default ==="
out="$(cd "$T/home-repo" && KIT_BOARDS_REGISTRY="$T/nope/boards.txt" HERMES_HOME="$T/hermes" python3 "$CLEANUP" 2>&1)"
echo "$out" | grep -qF "$T/nope/boards.txt" && ok "R5 reads the env registry" || bad "R5 reads the env registry: $out"
# With a readable registry the script goes on to call `hermes kanban`. A runner has no hermes, so a stub
# that lists no boards stands in; the run then reaches the header line that names the registry.
mkdir -p "$T/stub-bin"
printf '#!/bin/sh\necho "[]"\n' > "$T/stub-bin/hermes"; chmod +x "$T/stub-bin/hermes"
out="$(cd "$T/home-repo" && env -u KIT_BOARDS_REGISTRY HERMES_HOME="$T/hermes" PATH="$T/stub-bin:$PATH" python3 "$CLEANUP" 2>&1)"
echo "$out" | grep -qF "registry=$T/home-repo/_meta/boards.txt" && ok "R5 falls back to the repo default" || bad "R5 falls back to the repo default: $out"

echo "=== R6: reflect/propose.py cockpit source ==="
cockpit() {
  (cd "$T/home-repo" && REPO_ROOT="$T/home-repo" python3 - "$PROPOSE" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("propose", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print([p for k, p in m._dedup_sources("", "") if k == "cockpit"][0])
PY
  )
}
check "R6 env beats the repo default" "$(KIT_BOARDS_REGISTRY="$T/env-boards.txt" cockpit)" "$T/env-boards.txt"
check "R6 LEARN_PROPOSE_COCKPIT still beats the env" \
  "$(LEARN_PROPOSE_COCKPIT="$T/flag-boards.txt" KIT_BOARDS_REGISTRY="$T/env-boards.txt" cockpit)" "$T/flag-boards.txt"
check "R6 repo default when neither is set" "$(unset KIT_BOARDS_REGISTRY; cockpit)" "$T/home-repo/_meta/boards.txt"

echo
if [ "$FAIL" -eq 0 ]; then echo "test-board-registry-env: all $PASS passed"; else echo "test-board-registry-env: $FAIL FAILED, $PASS passed"; exit 1; fi
