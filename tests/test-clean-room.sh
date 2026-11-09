#!/usr/bin/env bash
# test-clean-room.sh -- a stranger can install the kit and use it with none of the maintainer's setup.
#
# One end-to-end run in a sandbox: a fresh HOME (no ~/.config/dwarves-kit, no ~/.claude), a PATH
# of system tools plus bash, jq and git (no op, no direnv, no gh login), and a fresh git repo as
# the project. Every kit command runs under `env -i`, so nothing leaks in from the host shell.
#
# Sequence: install.sh (bash path) -> onboard-detect -> adopt (check, dry-run, real, re-run) ->
# a normal-lane run through gate-ledger and the ship-gate hook -> `config seams`.
#
# Asserts: every command exits as documented; writes land only in the allowed dirs
# (assert_writes_land_only_in, the one place to tighten); no output or generated config names the
# host (assert_no_host_leak).
#
# Not covered: the plugin install path. It needs a running Claude Code to load .claude-plugin/,
# so no shell test can reach it. /kit:onboard and /kit:adopt are model-driven; this drives the
# scripts they call (lib/onboard-detect.sh, lib/adopt.sh).
#
# Run: bash tests/test-clean-room.sh
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REAL_HOME="${HOME:-}"
REAL_USER="$(id -un 2>/dev/null || true)"

# Fence this process too: a helper that reads the resolver here must not see the host operator file.
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-clean-room-no-operator.$$"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }
# has/lacks test a string with a fixed-string match. Piping into grep -q can SIGPIPE the writer, so
# the match runs on a here-string.
has()   { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing '$3')"; fi; }
lacks() { if grep -qF -- "$3" <<<"$2"; then bad "$1 (found '$3')"; else ok "$1"; fi; }

# --- sandbox ---------------------------------------------------------------------------------
# The sandbox goes under /tmp when TMPDIR sits inside the real home, so the leak scan cannot trip
# on the sandbox path itself.
BASE_TMP="${TMPDIR:-/tmp}"
case "$BASE_TMP" in "$REAL_HOME"|"$REAL_HOME"/*) BASE_TMP=/tmp ;; esac
SANDBOX="$(mktemp -d "$BASE_TMP/kit-clean-room.XXXXXX")" || exit 1
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
cleanup() { if [ "$FAIL" -eq 0 ]; then rm -rf "$SANDBOX"; else echo "sandbox kept: $SANDBOX"; fi; }
trap cleanup EXIT

TOKEN="cr$$x${RANDOM}"                       # unique per run: how a stray write is recognised
HOME_DIR="$SANDBOX/home"
REPO="$SANDBOX/repo"
REMOTE="$SANDBOX/remote.git"
TMP_DIR="$SANDBOX/tmp"
BIN_DIR="$SANDBOX/bin"
NO_OPERATOR="$SANDBOX/no-operator-config"    # never created
OUT_LOG="$SANDBOX/all-output.log"            # every command's output, scanned for host names
mkdir -p "$HOME_DIR" "$REPO" "$TMP_DIR" "$BIN_DIR"
: > "$OUT_LOG"
MARKER="$SANDBOX/.start-marker"; : > "$MARKER"

# bash, jq and git are the only non-system tools the kit needs. The test's own bash is linked so a
# macOS runner with Homebrew bash 4+ first on PATH keeps it.
for t in jq git; do
  src="$(command -v "$t" 2>/dev/null)" || { echo "SKIP: $t not on PATH"; exit 0; }
  ln -s "$src" "$BIN_DIR/$t"
done
ln -s "$BASH" "$BIN_DIR/bash"
PATH_CR="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin"

# cr: run a command in the clean room. Nothing from the host shell survives `env -i`.
cr() { env -i HOME="$HOME_DIR" PATH="$PATH_CR" TMPDIR="$TMP_DIR" KIT_CONFIG_OPERATOR="$NO_OPERATOR" "$@"; }
# run: cr in the repo, output and status kept in OUT and RC, output appended to the leak log.
OUT=""; RC=0
run() { OUT="$(cd "$REPO" && cr "$@" 2>&1)"; RC=$?; printf '%s\n' "$OUT" >> "$OUT_LOG"; }

# --- the two assertions the lead can tighten --------------------------------------------------

# Dirs a clean-room run may write into. Under the fake HOME that is only what the install owns
# (~/.claude, the ~/.local/bin shims) and the kit's data dirs (XDG state, XDG cache and the
# operator config dir, as lib/config/data-path.sh resolves them). A kit feature that writes
# anywhere else in HOME, or a stranger's legacy ~/.claude/dwarves-kit/state, fails the run.
ALLOWED_WRITE_DIRS=("$HOME_DIR/.claude" "$HOME_DIR/.local/bin" "$HOME_DIR/.local/state/dwarves-kit"
                    "$HOME_DIR/.cache/dwarves-kit" "$HOME_DIR/.config/dwarves-kit"
                    "$REPO" "$REMOTE" "$TMP_DIR" "$BIN_DIR")
# The harness's own bookkeeping files in the sandbox root.
HARNESS_PATHS=("$OUT_LOG" "$MARKER")

# Kit-owned dirs under the real HOME that a clean-room run must never touch.
real_home_canaries() {
  [ -n "$REAL_HOME" ] && [ "$REAL_HOME" != "/" ] || return 0
  local d
  for d in "$REAL_HOME/.config/dwarves-kit" "$REAL_HOME/.local/state/dwarves-kit" \
           "$REAL_HOME/.local/bin" "$REAL_HOME/.claude/dwarves-kit/logs" \
           "$REAL_HOME/.claude/commands" "$REAL_HOME/.claude/agents" \
           "$REAL_HOME/.claude/skills" "$REAL_HOME/.claude/output-styles"; do
    [ -e "$d" ] && printf '%s\n' "$d"
  done
}

# The install-owned dirs, where a name appearing or vanishing means the install touched the real
# HOME. Logs and state churn under a live session, so they get the token rule only.
real_home_install_dirs() {
  local d
  while IFS= read -r d; do
    case "$d" in */.local/state/*|*/dwarves-kit/logs) ;; *) printf '%s\n' "$d" ;; esac
  done < <(real_home_canaries)
}

# Names under the canaries, sorted: the before/after snapshot.
real_home_snapshot() {
  local d
  while IFS= read -r d; do find "$d" 2>/dev/null; done < <(real_home_install_dirs) | LC_ALL=C sort
}

# real_home_stray: files in the canaries newer than the start marker that carry this run's token,
# by name or by content. A live session may write there too, but never with our token.
real_home_stray() {
  local d
  while IFS= read -r d; do
    find "$d" -name "*$TOKEN*" 2>/dev/null
    find "$d" -type f -newer "$MARKER" -exec grep -lF -- "$TOKEN" {} + 2>/dev/null
  done < <(real_home_canaries)
}

# outside_allowed <root> <allowed>...: every path under <root> that is neither inside an allowed
# dir nor an ancestor of one.
outside_allowed() {
  local root="$1"; shift
  local list; list="$(mktemp "${TMPDIR:-/tmp}/kit-allowed.XXXXXX")" || return 1
  printf '%s\n' "$@" > "$list"
  find "$root" -mindepth 1 2>/dev/null | awk -v listf="$list" '
    BEGIN { while ((getline a < listf) > 0) if (a != "") allowed[++n] = a }
    { p = $0; ok = 0
      for (i = 1; i <= n; i++) {
        a = allowed[i]
        if (p == a || index(p, a "/") == 1 || index(a, p "/") == 1) { ok = 1; break }
      }
      if (!ok) print p }'
  rm -f "$list"
}

# assert_writes_land_only_in <label> <root> <before-snapshot> <allowed>...
# Three rules: nothing under <root> outside the allowed dirs; the real-HOME canary names equal the
# <before-snapshot>; no real-HOME file carries the run's token.
assert_writes_land_only_in() {
  local label="$1" root="$2" before="$3"; shift 3
  local stray; stray="$(outside_allowed "$root" "$@")"
  eq "$label: nothing written under the sandbox outside the allowed dirs" "$stray" ""
  eq "$label: kit-owned dirs in the real HOME have the same names as before" "$(real_home_snapshot)" "$before"
  eq "$label: no file in the real HOME carries this run's token" "$(real_home_stray)" ""
}

# host_leak_hits: read text on stdin, drop the kit checkout path (the kit's own location, not host
# config), print any line that names the maintainer, their tooling or the real user's home.
host_leak_hits() {
  # op:// counts only as a real ref (a vault name follows); the shipped docs show op://<vault>/... placeholders.
  # Built from halves so this file is not its own hit for lib/gate/boundary-lint.sh.
  local pats=("tieu""bao" "han""-ws" "ops""-toolkit")
  [ -n "$REAL_USER" ] && pats+=("/Users/$REAL_USER" "/home/$REAL_USER")
  [ "${#REAL_HOME}" -ge 6 ] && pats+=("$REAL_HOME")
  local text; text="$(awk -v k="$KIT_DIR" '{ while ((i = index($0, k)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(k)); print }')"
  local p
  for p in "${pats[@]}"; do grep -nF -- "$p" <<<"$text" | sed "s|^|[$p] |"; done
  grep -nE 'op://[A-Za-z0-9]' <<<"$text" | sed 's|^|[op://] |'
  return 0
}

assert_no_host_leak() { # <label> <file>...
  local label="$1"; shift
  local f hits
  for f in "$@"; do
    [ -f "$f" ] || continue
    hits="$(host_leak_hits < "$f")"
    eq "$label: no host name in ${f#"$SANDBOX"/}" "$hits" ""
  done
}

# --- self-test: the assertions catch what they claim to catch ---------------------------------
echo "== guards catch planted failures =="
: > "$SANDBOX/stray-entry"
eq "a stray entry in the sandbox root is seen" "$(outside_allowed "$SANDBOX" "${ALLOWED_WRITE_DIRS[@]}" "${HARNESS_PATHS[@]}" | grep -c 'stray-entry')" "1"
rm -f "$SANDBOX/stray-entry"
eq "with the stray gone the sandbox is clean" "$(outside_allowed "$SANDBOX" "${ALLOWED_WRITE_DIRS[@]}" "${HARNESS_PATHS[@]}")" ""
eq "an ancestor of an allowed dir is not a stray" "$(outside_allowed "$SANDBOX" "$HOME_DIR/.deep/inner" | grep -c "^$HOME_DIR\$")" "0"
eq "a tokened line is a host-leak hit only through its pattern" "$(printf 'Kit location: %s\nok line\n' "$KIT_DIR" | host_leak_hits)" ""
LEAK_WORD="ops""-toolkit"
eq "the maintainer's tooling repo name in an output line is a hit" "$(printf 'see %s/tools\n' "$LEAK_WORD" | host_leak_hits | grep -cF "$LEAK_WORD")" "1"
eq "an op:// ref in an output line is a hit" "$(printf 'key op://vault/item\n' | host_leak_hits | grep -c 'op://')" "1"
if [ -n "$REAL_USER" ]; then
  has "the real user's /Users path is a hit" "$(printf 'path /Users/%s/x\n' "$REAL_USER" | host_leak_hits)" "/Users/$REAL_USER"
fi

# --- preconditions: the room is really clean ---------------------------------------------------
echo "== preconditions =="
eq "no ~/.config/dwarves-kit in the fake HOME" "$([ -e "$HOME_DIR/.config/dwarves-kit" ] && echo present || echo absent)" "absent"
eq "no ~/.claude in the fake HOME" "$([ -e "$HOME_DIR/.claude" ] && echo present || echo absent)" "absent"
eq "op is not on the clean PATH" "$(cr sh -c 'command -v op' 2>/dev/null)" ""
eq "direnv is not on the clean PATH" "$(cr sh -c 'command -v direnv' 2>/dev/null)" ""
if cr sh -c 'command -v gh' >/dev/null 2>&1; then
  # Ubuntu runners ship gh in /usr/bin. It must hold no login: no token env, no ~/.config/gh.
  # gh writes its own device-id under XDG state on every run, so that dir is pinned into the allowed TMP_DIR:
  # the write-fence below is for the kit, not for a probe of someone else's CLI.
  chk "gh, if present, is not logged in" "$(cr env XDG_STATE_HOME="$TMP_DIR/gh-state" gh auth status >/dev/null 2>&1; [ $? -ne 0 ] && echo 0 || echo 1)"
else
  ok "gh is not on the clean PATH"
fi
eq "the clean env carries no secret-shaped variable" "$(cr env | grep -ciE 'token|secret|OP_|SA_TOKEN|API_KEY')" "0"

SNAP_BEFORE="$(real_home_snapshot)"

# --- install -----------------------------------------------------------------------------------
echo "== install.sh (bash path) =="
run git init -q -b trunk "$REPO"
chk "toy repo created" $RC
cr git -C "$REPO" config user.email stranger@users.noreply.github.com
cr git -C "$REPO" config user.name Stranger
printf '# toy\n' > "$REPO/README.md"
cr git -C "$REPO" add -A && cr git -C "$REPO" commit -qm "chore: init"

run bash "$KIT_DIR/install.sh"
eq "install.sh exits 0" "$RC" "0"
has "install announces the kit location" "$OUT" "dwarves-kit installer"
KIT="$HOME_DIR/.claude/dwarves-kit"
chk "installed engine has bin/config" "$([ -x "$KIT/bin/config" ] || [ -f "$KIT/bin/config" ]; echo $?)"
chk "installed engine has hooks/ship-gate.sh" "$([ -f "$KIT/hooks/ship-gate.sh" ]; echo $?)"
chk "installed kit.toml written" "$([ -f "$KIT/kit.toml" ]; echo $?)"
chk "settings.json registers hooks" "$(jq -e '.hooks | length > 0' "$HOME_DIR/.claude/settings.json" >/dev/null 2>&1; echo $?)"
eq "settings.json hook commands point at the fake HOME copy, never at the checkout" \
  "$(jq -r '[.hooks[][].hooks[].command] | .[]' "$HOME_DIR/.claude/settings.json" | grep -cF -- "$KIT_DIR/")" "0"
# The commands carry a literal $HOME, so they resolve to the fake HOME at run time.
eq "settings.json hook commands all run the copy under \$HOME/.claude/dwarves-kit/hooks" \
  "$(jq -r '[.hooks[][].hooks[].command] | .[]' "$HOME_DIR/.claude/settings.json" | grep -c 'hooks/')" \
  "$(jq -r '[.hooks[][].hooks[].command] | .[]' "$HOME_DIR/.claude/settings.json" | grep -cF -- '$HOME/.claude/dwarves-kit/hooks/')"
run bash "$KIT/lib/onboard-detect.sh" explain
eq "onboard-detect exits 0" "$RC" "0"
has "onboard-detect reports the bash install" "$OUT" "bash"

# --- adopt -------------------------------------------------------------------------------------
echo "== adopt (the scriptable half of /kit:onboard and /kit:adopt) =="
run bash "$KIT/lib/adopt.sh" --check "$REPO"
eq "adopt --check on a fresh repo exits 1 (not adopted)" "$RC" "1"
run bash "$KIT/lib/adopt.sh" --dry-run "$REPO"
eq "adopt --dry-run exits 0" "$RC" "0"
eq "adopt --dry-run writes nothing" "$(cr git -C "$REPO" status --porcelain | grep -vc '^?? .claude/$')" "0"
run bash "$KIT/lib/adopt.sh" --with board "$REPO"
eq "adopt exits 0" "$RC" "0"
for f in AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md; do
  chk "adopt wrote $f" "$([ -f "$REPO/$f" ]; echo $?)"
done
run bash "$KIT/lib/adopt.sh" --check "$REPO"
eq "adopt --check after adopting exits 0" "$RC" "0"
cr git -C "$REPO" add -A && cr git -C "$REPO" commit -qm "chore: adopt the kit"
run bash "$KIT/lib/adopt.sh" --with board "$REPO"
eq "a second adopt exits 0" "$RC" "0"
eq "a second adopt changes nothing (idempotent)" "$(cr git -C "$REPO" status --porcelain)" ""

# The ship-gate reads [gate] at the merge base with origin's default branch, so the adoption has
# to be on it. A local remote-tracking ref stands in for a push; nothing is pushed anywhere.
cr git init -q --bare -b trunk "$REMOTE"
cr git -C "$REPO" remote add origin "$REMOTE"
cr git -C "$REPO" update-ref refs/remotes/origin/trunk HEAD
cr git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk

# --- a gate cycle through the shell entry points -----------------------------------------------
echo "== gate cycle: gate-ledger and the ship-gate hook =="
BRANCH="feat/cr-$TOKEN"
RID="cr-$TOKEN"
LEDGER="$KIT/lib/gate/gate-ledger.sh"
cr git -C "$REPO" checkout -qb "$BRANCH"
mkdir -p "$REPO/docs/specs"
printf '# Spec: toy\nStatus: DRAFT\nLane: normal\n\n- [ ] TASK-1: toy\n' > "$REPO/docs/specs/SPEC-001-$RID.md"
printf 'toy\n' > "$REPO/toy.txt"
cr git -C "$REPO" add -A && cr git -C "$REPO" commit -qm "feat: add a toy"

run bash "$LEDGER" rid
eq "gate-ledger rid is the branch slug" "$OUT" "$RID"
run bash "$LEDGER" start "$RID" normal normal spec-feature
eq "gate-ledger start exits 0" "$RC" "0"
run bash "$LEDGER" check normal "$RID"
eq "gate-ledger check exits 1 while required gates are missing" "$RC" "1"
has "...and names the missing gate" "$OUT" "MISSING-GATE: build"

ship_gate() { # run the installed hook with a PreToolUse payload for a branch push
  local payload
  payload="$(jq -nc --arg cwd "$REPO" --arg cmd "git push -u origin $BRANCH" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')"
  OUT="$(cd "$REPO" && printf '%s' "$payload" | cr bash "$KIT/hooks/ship-gate.sh" 2>&1)"; RC=$?
  printf '%s\n' "$OUT" >> "$OUT_LOG"
}
ship_gate
eq "ship-gate blocks the push (exit 2) while gates are missing" "$RC" "2"
has "...and says which lane" "$OUT" "'normal' lane"

for phase in spec build review; do run bash "$LEDGER" record "$RID" "$phase" ran; done
run bash "$LEDGER" record "$RID" ship ran
eq "gate-ledger record exits 0" "$RC" "0"
run bash "$LEDGER" check normal "$RID"
eq "gate-ledger check exits 0 once the gates ran" "$RC" "0"
ship_gate
eq "ship-gate lets the push through (exit 0) once the gates ran" "$RC" "0"
run bash "$LEDGER" show "$RID"
has "gate-ledger show lists the run" "$OUT" "START"

# --- config seams -------------------------------------------------------------------------------
echo "== bin/config seams =="
run bash "$KIT/bin/config" seams
eq "config seams exits 0" "$RC" "0"
SEAM_ROWS="$(printf '%s\n' "$OUT" | tail -n +2 | grep -c .)"
SEAM_OK="$(printf '%s\n' "$OUT" | tail -n +2 | grep -cE '[[:space:]]{2,}(default|absent)[[:space:]]{2,}')"
chk "seams lists rows ($SEAM_ROWS)" "$([ "$SEAM_ROWS" -ge 5 ]; echo $?)"
eq "every seam is default or absent" "$SEAM_OK" "$SEAM_ROWS"
lacks "no seam is unresolved" "$OUT" "unresolved"
lacks "no seam is filled" "$OUT" " filled "
run bash "$KIT/bin/config" seams --check
eq "config seams --check exits 0" "$RC" "0"
run bash "$KIT/bin/config" get modules.board
eq "config get modules.board exits 0" "$RC" "0"
eq "...and reads the fresh install default" "$OUT" "true"
run bash "$KIT/bin/config" list
eq "config list exits 0" "$RC" "0"

# --- runtime data lands in the data dirs, never in the old ~/.claude paths ------------------------
echo "== a stranger's runtime data: XDG dirs only =="
run bash "$KIT/bin/config" data path state harvest
eq "state resolves under the fake HOME's XDG state dir" "$OUT" "$HOME_DIR/.local/state/dwarves-kit/harvest"
run bash "$KIT/bin/config" data path cache context-hints
eq "cache resolves under the fake HOME's XDG cache dir" "$OUT" "$HOME_DIR/.cache/dwarves-kit/context-hints"
run bash "$KIT/bin/config" data
lacks "config data shows no legacy path for a stranger" "$OUT" " legacy "
printf '%s' '{"prompt":"hello","session_id":"cr-ctx"}' | cr bash "$KIT/hooks/context-hints.sh" >/dev/null 2>&1
eq "a hook writes its state under the XDG cache dir" "$([ -f "$HOME_DIR/.cache/dwarves-kit/context-hints/cr-ctx.json" ] && echo yes || echo no)" "yes"
eq "...and nothing appears under the old ~/.claude/dwarves-kit/state" "$([ -e "$HOME_DIR/.claude/dwarves-kit/state" ] && echo present || echo absent)" "absent"

# --- the sandbox rules --------------------------------------------------------------------------
echo "== writes stay in the sandbox; nothing names the host =="
assert_writes_land_only_in "after the full run" "$SANDBOX" "$SNAP_BEFORE" "${ALLOWED_WRITE_DIRS[@]}" "${HARNESS_PATHS[@]}"
eq "no operator config appeared in the fake HOME" "$([ -e "$HOME_DIR/.config/dwarves-kit" ] && echo present || echo absent)" "absent"

# The whole shipped kit.toml is scanned, comments included: every install copies it to a stranger.
assert_no_host_leak "generated files" \
  "$HOME_DIR/.claude/settings.json" "$KIT/kit.toml" "$KIT/INSTALL-STAMP" \
  "$REPO/.kit.toml" "$REPO/AGENTS.md" "$REPO/CLAUDE.md" "$REPO/WORKFLOW.md" "$REPO/docs/verification/README.md"
assert_no_host_leak "ledger" $(find "$HOME_DIR/.local/state" -type f -name '*.log' 2>/dev/null | head -20)
eq "no command output names the host" "$(host_leak_hits < "$OUT_LOG")" ""

echo
echo "clean-room: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
