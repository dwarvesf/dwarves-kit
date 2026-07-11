#!/usr/bin/env bash
# cc-worktree-provision smoke. Builds fixture "main repo" + "worktree" dirs (no real
# git needed: --source overrides the git-derived root) and checks the provision plan,
# real symlink creation, idempotency, no-op, and payload safety. Stdlib only (python3).
#
# Run: bash tests/smoke.sh   Pass: "smoke: all N passed", exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/bin/cc-worktree-provision"
run(){ python3 "$BIN" "$@"; }   # env-var cases use `env VAR=val python3` directly (unambiguous)

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# fixture A: a source repo with gitignored env + a python manifest, and an empty worktree
SRC="$TMP/main"; WT="$TMP/wt"
mkdir -p "$SRC" "$WT"
printf 'export FOO=bar\n' > "$SRC/.envrc"
printf 'use flake\n' > "$SRC/.env"
printf '[project]\nname="x"\n' > "$WT/pyproject.toml"
# fixture B: nothing to provision
SRC2="$TMP/main2"; WT2="$TMP/wt2"; mkdir -p "$SRC2" "$WT2"
# fixture C: a node worktree
WT3="$TMP/wt3"; mkdir -p "$WT3"; printf '{}\n' > "$WT3/package.json"
# fixtures D/E/F: go / rust / ruby worktrees
WT5="$TMP/wt5"; mkdir -p "$WT5"; printf 'module x\n' > "$WT5/go.mod"
WT6="$TMP/wt6"; mkdir -p "$WT6"; printf '[package]\nname="x"\n' > "$WT6/Cargo.toml"
WT7="$TMP/wt7"; mkdir -p "$WT7"; printf "source 'https://rubygems.org'\n" > "$WT7/Gemfile"
# fixture G: a go worktree used to exercise a REAL (stubbed) install run + verbose toggle.
# A fake `go` on PATH echoes a marker so no real toolchain is needed.
WT8="$TMP/wt8"; mkdir -p "$WT8"; printf 'module x\n' > "$WT8/go.mod"
STUB="$TMP/stub"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash\necho "STUB-INSTALL-RAN $*"\n' > "$STUB/go"
chmod +x "$STUB/go"

pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] dry-run plan: symlinks .envrc/.env + detects uv sync"
out="$(run --base "$WT" --source "$SRC" --dry-run 2>&1)"
if grep -q 'symlink .*/wt/.envrc -> .*/main/.envrc' <<<"$out" && grep -q 'symlink .*/wt/.env ' <<<"$out" && grep -q 'install: uv sync' <<<"$out"; then ok "plan correct"; else no "plan: $out"; fi

echo "[2] no-op when nothing to provision (negative control)"
out="$(run --base "$WT2" --source "$SRC2" --dry-run 2>&1)"
if grep -q 'no-op: nothing to provision' <<<"$out"; then ok "no-op clean"; else no "expected no-op: $out"; fi

echo "[3] real symlink created (install skipped via env)"
env CC_WT_PROVISION_NO_INSTALL=1 python3 "$BIN" --base "$WT" --source "$SRC" >/dev/null 2>&1
if [[ -L "$WT/.envrc" && "$(readlink "$WT/.envrc")" == "$SRC/.envrc" ]]; then ok ".envrc symlinked to source"; else no "symlink wrong: $(ls -la "$WT/.envrc" 2>&1)"; fi

echo "[4] idempotent: re-run does not error or double-link"
set +e; env CC_WT_PROVISION_NO_INSTALL=1 python3 "$BIN" --base "$WT" --source "$SRC" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 && -L "$WT/.envrc" ]]; then ok "re-run safe"; else no "rc=$rc"; fi

echo "[5] manifest detection: package.json -> pnpm install"
out="$(run --base "$WT3" --source "$SRC2" --dry-run 2>&1)"
if grep -q 'install: pnpm install' <<<"$out"; then ok "pnpm detected"; else no "node plan: $out"; fi

echo "[6] junk stdin payload -> exit 0, no action"
set +e; echo 'notjson' | run >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]]; then ok "junk safe"; else no "rc=$rc"; fi

echo "[7] payload with no base_path -> exit 0 (no-op)"
set +e; echo '{}' | run >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 0 ]]; then ok "missing base_path safe"; else no "rc=$rc"; fi

echo "[8] payload base_path drives provisioning (real WorktreeCreate event shape)"
WT4="$TMP/wt4"; mkdir -p "$WT4"
out="$(printf '{"base_path":"%s"}' "$WT4" | env CC_WT_PROVISION_ENV=.envrc python3 "$BIN" --source "$SRC" --dry-run 2>&1)"
if grep -q "symlink $WT4/.envrc -> $SRC/.envrc" <<<"$out"; then ok "stdin base_path honored"; else no "payload path: $out"; fi

echo "[9] manifest detection: go.mod -> go mod download"
out="$(run --base "$WT5" --source "$SRC2" --dry-run 2>&1)"
if grep -q 'install: go mod download' <<<"$out"; then ok "go detected"; else no "go plan: $out"; fi

echo "[10] manifest detection: Cargo.toml -> cargo fetch"
out="$(run --base "$WT6" --source "$SRC2" --dry-run 2>&1)"
if grep -q 'install: cargo fetch' <<<"$out"; then ok "rust detected"; else no "rust plan: $out"; fi

echo "[11] manifest detection: Gemfile -> bundle install"
out="$(run --base "$WT7" --source "$SRC2" --dry-run 2>&1)"
if grep -q 'install: bundle install' <<<"$out"; then ok "ruby detected"; else no "ruby plan: $out"; fi

echo "[12] verbose dry-run labels the install line"
out="$(env CC_WT_PROVISION_VERBOSE=1 python3 "$BIN" --base "$WT5" --source "$SRC2" --dry-run 2>&1)"
if grep -q 'install (verbose): go mod download' <<<"$out"; then ok "verbose label shown"; else no "verbose label: $out"; fi

echo "[13] verbose ON streams the install command + (stubbed) output"
out="$(PATH="$STUB:$PATH" env CC_WT_PROVISION_VERBOSE=1 python3 "$BIN" --base "$WT8" --source "$SRC2" 2>&1)"
if grep -q 'running go mod download' <<<"$out" && grep -q 'STUB-INSTALL-RAN' <<<"$out"; then ok "verbose streams cmd+output"; else no "verbose run: $out"; fi

echo "[14] verbose OFF is silent (no command echo, no install stdout)"
out="$(PATH="$STUB:$PATH" python3 "$BIN" --base "$WT8" --source "$SRC2" 2>&1)"
if ! grep -q 'running go mod download' <<<"$out" && ! grep -q 'STUB-INSTALL-RAN' <<<"$out"; then ok "silent by default"; else no "expected silence: $out"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
