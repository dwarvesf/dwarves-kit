#!/usr/bin/env bash
# test-install-lib-copy.sh -- install.sh copies lib/ without gitignored build output.
# A dev checkout carries lib/prose-rag/rust/target (419M of cargo output from the retired
# crate), lib/stats/.venv (a non-relocatable venv that `uv run --project` rebuilds) and
# __pycache__ dirs. `cp -R` shipped all of it into every pinned install: 485M instead of 7M.
# The stand-in checkout below plants one of each next to a tracked file, installs it, and
# checks that the tracked files land and the build output does not.
set -euo pipefail
KIT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

DEST="$(mktemp -d)"; HOME_SB="$(mktemp -d)"; FAKE_KIT="$(mktemp -d)"; INSTALL_LOG="$(mktemp)"
trap 'rm -rf "$DEST" "$HOME_SB" "$FAKE_KIT" "$INSTALL_LOG"' EXIT

mkdir -p "$FAKE_KIT/hooks" "$FAKE_KIT/commands" "$FAKE_KIT/agents" "$FAKE_KIT/skills/demo" "$FAKE_KIT/bin" "$FAKE_KIT/docs/impl-playbook" \
  "$FAKE_KIT/lib/mod/sub" "$FAKE_KIT/lib/mod/.venv/bin" "$FAKE_KIT/lib/mod/__pycache__" \
  "$FAKE_KIT/lib/mod/rust/target/release" "$FAKE_KIT/lib/mod/bin"
echo 'tracked'      > "$FAKE_KIT/lib/mod/keep.sh"
echo 'tracked deep' > "$FAKE_KIT/lib/mod/sub/deep.sh"
echo 'tracked bin'  > "$FAKE_KIT/lib/mod/bin/tool"
echo 'venv'         > "$FAKE_KIT/lib/mod/.venv/bin/python"
echo 'bytecode'     > "$FAKE_KIT/lib/mod/__pycache__/keep.cpython-312.pyc"
echo 'cargo output' > "$FAKE_KIT/lib/mod/rust/target/release/engine"
echo 'built binary' > "$FAKE_KIT/lib/mod/bin/engine-rs"
echo 'hook'         > "$FAKE_KIT/hooks/marker.sh"
echo 'playbook'     > "$FAKE_KIT/docs/impl-playbook/marker.md"
echo 'contract'     > "$FAKE_KIT/AGENTS.md"
echo 'contract'     > "$FAKE_KIT/WORKFLOW.md"
echo 'contract'     > "$FAKE_KIT/docs/WORKFLOW.md"
echo '{"hooks":{}}'  > "$FAKE_KIT/settings.json"
echo 'command'      > "$FAKE_KIT/commands/demo.md"
echo 'agent'        > "$FAKE_KIT/agents/demo.md"
echo 'skill'        > "$FAKE_KIT/skills/demo/SKILL.md"
cp "$KIT_DIR/install.sh" "$FAKE_KIT/install.sh"

if ! HOME="$HOME_SB" CLAUDE_DIR="$DEST" bash "$FAKE_KIT/install.sh" >"$INSTALL_LOG" 2>&1; then
  echo "FAIL install.sh exited non-zero; last lines of its log:"
  tail -n 20 "$INSTALL_LOG"
  fail=1
fi
LIB="$DEST/dwarves-kit/lib/mod"

chk "tracked lib files are copied" "$([ -f "$LIB/keep.sh" ] && [ -f "$LIB/sub/deep.sh" ] && [ -f "$LIB/bin/tool" ]; echo $?)"
chk "a .venv is not copied" "$([ ! -e "$LIB/.venv" ]; echo $?)"
chk "a __pycache__ is not copied" "$([ ! -e "$LIB/__pycache__" ]; echo $?)"
chk "rust/target cargo output is not copied" "$([ ! -e "$LIB/rust/target" ]; echo $?)"
chk "a bin/*-rs built binary is not copied" "$([ ! -e "$LIB/bin/engine-rs" ]; echo $?)"

[ "$fail" -eq 0 ] && echo "PASS: install lib copy skips build output" || { echo "SOME TESTS FAILED"; exit 1; }
