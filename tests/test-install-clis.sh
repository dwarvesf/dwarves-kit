#!/usr/bin/env bash
# install.sh CLI shims (step 5b + kit_write_cli_shim): enabled modules expose their
# CLIs on ~/.local/bin as exec-shim FILES targeting the stable bin/ entrypoints
# (SPEC-184); a non-enabled module's CLI is absent; a user-owned (non-kit) file at
# the shim path is never clobbered; a stale symlink (the ops-toolkit cc-elevation
# shape this feature replaces) IS replaced. Hermetic: installs into mktemp HOMEs.
set -euo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass=0; fail=0
assert_true(){ if [ "$2" = "0" ]; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1" >&2; fail=$((fail+1)); fi; }

echo "== --with session,worktree exposes the CLIs as kit-managed shim files =="
H1="$(mktemp -d)"
HOME="$H1" bash "$KIT_DIR/install.sh" --with session,worktree >/tmp/kitcli-h1.log 2>&1
for cli in cc-intel cc-observe cc-semantic cc-recall cc-vps-report worktree-provision; do
  assert_true "$cli shim exists + executable" "$([ -x "$H1/.local/bin/$cli" ]; echo $?)"
  assert_true "$cli is a shim file (not symlink), kit-marked" \
    "$([ ! -L "$H1/.local/bin/$cli" ] && grep -q 'dwarves-kit CLI shim' "$H1/.local/bin/$cli"; echo $?)"
done
assert_true "shim targets the stable bin/ entrypoint" \
  "$(grep -q "$H1/.claude/dwarves-kit/bin/cc-intel" "$H1/.local/bin/cc-intel"; echo $?)"

echo "== the shim chain actually runs (shim -> bin/ -> lib/) =="
out="$(HOME="$H1" "$H1/.local/bin/cc-intel" --help 2>&1 || true)"
assert_true "cc-intel --help runs through the chain" "$(grep -q 'usage: cc-intel' <<<"$out"; echo $?)"
out="$(HOME="$H1" "$H1/.local/bin/worktree-provision" --base /nonexistent --dry-run 2>&1; echo "rc=$?")"
assert_true "worktree-provision exits 0 through the chain" "$(grep -q 'rc=0' <<<"$out"; echo $?)"

echo "== NC: spine-only install exposes no CLIs =="
H2="$(mktemp -d)"
HOME="$H2" bash "$KIT_DIR/install.sh" --prune >/tmp/kitcli-h2.log 2>&1
assert_true "no cc-intel shim without the session module" "$([ ! -e "$H2/.local/bin/cc-intel" ]; echo $?)"
assert_true "no worktree-provision shim without the worktree module" "$([ ! -e "$H2/.local/bin/worktree-provision" ]; echo $?)"

echo "== NC: a user-owned file at the shim path is never clobbered =="
H3="$(mktemp -d)"
mkdir -p "$H3/.local/bin"
printf '#!/bin/sh\necho user-owned\n' > "$H3/.local/bin/cc-intel"
chmod +x "$H3/.local/bin/cc-intel"
HOME="$H3" bash "$KIT_DIR/install.sh" --with session >/tmp/kitcli-h3.log 2>&1
assert_true "user-owned cc-intel untouched" "$(grep -q 'user-owned' "$H3/.local/bin/cc-intel"; echo $?)"
assert_true "install warned about the skip" "$(grep -q 'not kit-managed; left untouched' /tmp/kitcli-h3.log; echo $?)"

echo "== a stale symlink at the shim path IS replaced (the cc-elevation shape) =="
H4="$(mktemp -d)"
mkdir -p "$H4/.local/bin"
ln -s /nonexistent/old-snapshot/cc-intel "$H4/.local/bin/cc-intel"
HOME="$H4" bash "$KIT_DIR/install.sh" --with session >/tmp/kitcli-h4.log 2>&1
assert_true "stale symlink replaced by a kit shim" \
  "$([ ! -L "$H4/.local/bin/cc-intel" ] && grep -q 'dwarves-kit CLI shim' "$H4/.local/bin/cc-intel"; echo $?)"

echo
if [ $fail -gt 0 ]; then echo "test-install-clis: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-install-clis: all $pass passed"
