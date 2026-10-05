#!/usr/bin/env bash
# test-board-sweep.sh -- the loop of `board sweep` (lib/sync/sweep/board-sweep):
# per-repo sync, enrolment-style preflight, publish gate, token handoff, the
# digest and poster wiring, the on-clean hook, and --dry-run.
#
# The board command, the poster and every hook are stubs, and HOME is a scratch
# dir: no real board, no spoke, no network, no credential.
#
#   AC1  every registry repo syncs in order, from its own root, with --backlog-file
#   AC2  an empty extra-arg list is safe on Apple bash 3.2 (the sweep runs as #!/bin/bash)
#   AC3  --repo-arg adds argv to ONE repo's sync; --extra-board sweeps one more board
#   AC4  a repo with no [sync] block is a skip, a missing board is a skip, a failed sync flips rc
#   AC5  --preflight runs once with the registry; nonzero holds the on-clean hook
#   AC6  --on-clean runs only on a clean sweep, never on a dirty one or a dry run
#   AC7  the token reaches ONLY the --sync-token-repo sync and the publish leg
#   AC8  publish runs only after a sync that wrote the board; rc 3 flips the sweep rc
#   AC9  --poster wires digest -> post -> mark: one payload per cluster, change-only
#   AC10 --dry-run plans: sync --dry-run, no publish, no real state write, no post
#   AC11 --name labels the start/end lines
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="$HERE/../lib/sync/sweep/board-sweep"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
mkdir -p "$WORK/out"

for r in alpha beta gamma; do
  mkdir -p "$WORK/r-$r/_meta"
  printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | row | | queued |\n' > "$WORK/r-$r/_meta/BACKLOG.md"
done
cat > "$WORK/boards.txt" <<EOF
# a comment, then three boards on two rails
alpha  $WORK/r-alpha/_meta/BACKLOG.md  on rail=crew
beta   $WORK/r-beta/_meta/BACKLOG.md   rail=pers
gamma  $WORK/r-gamma/_meta/BACKLOG.md  rail=crew
EOF

# the stub board: logs argv + the credential-bearing env the leg saw; `sync`
# replays out/<repo-dir-name>.out with out/<..>.rc, `publish` honours FAKE_PUBLISH_RC
cat > "$WORK/board" <<'EOF'
#!/usr/bin/env bash
repo="$(basename "$PWD")"
# publish runs from the sweep's own cwd, so the repo is named by its --backlog-file
[ "$1" = "publish" ] && repo="$(basename "$(dirname "$(dirname "$3")")")"
{
  echo "board called [$repo]: $*"
  echo "  env [$repo/$1] GH_TOKEN=${GH_TOKEN:-UNSET} GIT_ASKPASS=$(basename "${GIT_ASKPASS:-UNSET}") GIT_TOKEN=${BOARD_SYNC_GIT_TOKEN:-UNSET} SWEEP_TOKEN=${BOARD_SWEEP_TOKEN:-UNSET} PROMPT=${GIT_TERMINAL_PROMPT:-UNSET}"
} >> "$FAKE_CALL_LOG"
case "$1" in
  sync)
    cat "$FAKE_OUT/$repo.out" 2>/dev/null
    exit "$(cat "$FAKE_OUT/$repo.rc" 2>/dev/null || echo 0)" ;;
  publish) echo "publish stub"; exit "${FAKE_PUBLISH_RC:-0}" ;;
  mirror) exit 0 ;;
esac
exit 0
EOF
chmod +x "$WORK/board"
cat > "$WORK/poster" <<'EOF'
#!/usr/bin/env bash
cat >> "$FAKE_POSTED"; echo >> "$FAKE_POSTED"
exit "${FAKE_POSTER_RC:-0}"
EOF
chmod +x "$WORK/poster"
cat > "$WORK/hook-clean" <<'EOF'
#!/usr/bin/env bash
echo "on-clean ran" >> "$FAKE_CALL_LOG"; echo "  heartbeat stub ok"
EOF
cat > "$WORK/hook-preflight" <<'EOF'
#!/usr/bin/env bash
echo "preflight argv: $*" >> "$FAKE_CALL_LOG"; echo "  preflight stub says $FAKE_PREFLIGHT_SAYS"
exit "${FAKE_PREFLIGHT_RC:-0}"
EOF
chmod +x "$WORK/hook-clean" "$WORK/hook-preflight"
export FAKE_CALL_LOG FAKE_OUT FAKE_POSTED FAKE_PUBLISH_RC FAKE_POSTER_RC FAKE_PREFLIGHT_RC FAKE_PREFLIGHT_SAYS
FAKE_OUT="$WORK/out"
STATE="$WORK/state.json"

run_sweep() {  # extra sweep args...
  HOME="$WORK" PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
    "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/board" --state-file "$STATE" "$@"
}
reset() { : > "$WORK/calls.log"; FAKE_CALL_LOG="$WORK/calls.log"; : > "$WORK/posted.log"; FAKE_POSTED="$WORK/posted.log"; rm -f "$WORK"/out/* "$STATE"; FAKE_PUBLISH_RC=0; FAKE_POSTER_RC=0; FAKE_PREFLIGHT_RC=0; }

echo "case clean (three repos sync in order, from their own roots):"
reset
out="$(run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || bad "exit $rc"
grep -q "board-sweep: start" <<<"$out" && grep -q "board-sweep: end rc=0" <<<"$out" && ok "start and end lines" || bad "no start/end: $out"
[ "$(grep '^board called' "$WORK/calls.log" | sed -E 's/^board called \[([a-z-]+)\].*/\1/' | paste -sd, -)" = "r-alpha,r-beta,r-gamma" ] \
  && ok "registry order, each from its own repo root" || bad "order wrong: $(grep '^board called' "$WORK/calls.log")"
grep -qF "board called [r-alpha]: sync --backlog-file $WORK/r-alpha/_meta/BACKLOG.md" "$WORK/calls.log" \
  && ok "sync gets --backlog-file and nothing else when no extras are set (bash 3.2 empty array)" || bad "sync argv wrong: $(grep 'sync' "$WORK/calls.log" | head -1)"
grep -q "  alpha rc=0" <<<"$out" && ok "per-repo rc line" || bad "no per-repo rc line"
[ ! -f "$STATE" ] && ok "no --poster: the digest leg never touches the state file" || bad "state file written without a poster"

echo "case repo-arg (extra argv for ONE repo's sync; a filter is two flags):"
reset
run_sweep --repo-arg alpha=--filter --repo-arg 'alpha=hermes:intake_skip_re=^filed-by: bot' >/dev/null 2>&1
grep -qF "board called [r-alpha]: sync --backlog-file $WORK/r-alpha/_meta/BACKLOG.md --filter hermes:intake_skip_re=^filed-by: bot" "$WORK/calls.log" \
  && ok "alpha's sync carries both extra argv items, in order" || bad "alpha argv: $(grep 'r-alpha\]: sync' "$WORK/calls.log")"
grep -qF "board called [r-beta]: sync --backlog-file $WORK/r-beta/_meta/BACKLOG.md" "$WORK/calls.log" && ! grep -q "r-beta\]: sync.*--filter" "$WORK/calls.log" \
  && ok "beta's sync is untouched" || bad "beta argv polluted: $(grep 'r-beta\]: sync' "$WORK/calls.log")"

echo "case extra-board (--extra-board sweeps one more BACKLOG.md after the registry):"
reset
mkdir -p "$WORK/x-extra/_meta"; printf '| AB-1 | r | | queued |\n' > "$WORK/x-extra/_meta/BACKLOG.md"
out="$(run_sweep --extra-board "$WORK/x-extra/_meta/BACKLOG.md" 2>&1)"
grep -q "  x-extra rc=0" <<<"$out" && ok "the extra board is swept under its repo directory name" || bad "extra board not swept: $out"
[ "$(grep '^board called' "$WORK/calls.log" | tail -1 | sed -E 's/^board called \[([a-z-]+)\].*/\1/')" = "x-extra" ] && ok "after the registry" || bad "extra board not last"

echo "case skips-and-failures (no [sync] block / no board = skip; a failed sync flips rc):"
reset
printf 'board sync: no [sync] apps configured in x/.kit.toml\n' > "$WORK/out/r-alpha.out"; echo 2 > "$WORK/out/r-alpha.rc"
echo 1 > "$WORK/out/r-gamma.rc"; printf 'boom\n' > "$WORK/out/r-gamma.out"
rm -rf "$WORK/r-beta"
out="$(run_sweep --on-clean "$WORK/hook-clean" 2>&1)"; rc=$?
grep -q "skip alpha (no \[sync\] block)" <<<"$out" && ok "no [sync] block is a skip" || bad "no skip line for alpha: $out"
grep -q "skip beta (no board at" <<<"$out" && ok "a missing board is a skip" || bad "no skip line for beta"
grep -q "  gamma rc=1" <<<"$out" && ok "the failure is logged with its rc" || bad "no gamma rc=1"
[ "$rc" -eq 1 ] && ok "a failed sync makes the sweep exit 1" || bad "sweep exit $rc (want 1)"
grep -q "on-clean ran" "$WORK/calls.log" && bad "on-clean ran after a failed sync" || ok "on-clean held after a failed sync"
mkdir -p "$WORK/r-beta/_meta"; printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| AB-1 | row | | queued |\n' > "$WORK/r-beta/_meta/BACKLOG.md"

echo "case hooks (preflight runs once with the registry; on-clean only after a clean sweep):"
reset
FAKE_PREFLIGHT_SAYS="all enrolled"
out="$(run_sweep --preflight "$WORK/hook-preflight" --on-clean "$WORK/hook-clean" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "clean preflight, clean sweep: exit 0" || bad "exit $rc"
[ "$(grep -c '^preflight argv' "$WORK/calls.log")" -eq 1 ] && ok "preflight ran exactly once" || bad "preflight ran $(grep -c '^preflight argv' "$WORK/calls.log") times"
grep -qF "preflight argv: $WORK/boards.txt" "$WORK/calls.log" && ok "preflight got the registry path" || bad "preflight argv: $(grep '^preflight' "$WORK/calls.log")"
grep -q "preflight stub says all enrolled" <<<"$out" && ok "preflight output reaches the sweep log" || bad "preflight output lost"
grep -q "on-clean ran" "$WORK/calls.log" && grep -q "heartbeat stub ok" <<<"$out" && ok "on-clean ran and its output is logged" || bad "on-clean did not run"
reset
FAKE_PREFLIGHT_RC=1; FAKE_PREFLIGHT_SAYS="beta is not enrolled"
out="$(run_sweep --preflight "$WORK/hook-preflight" --on-clean "$WORK/hook-clean" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "a failing preflight makes the sweep exit 1" || bad "exit $rc (want 1)"
grep -q "on-clean ran" "$WORK/calls.log" && bad "on-clean ran after a failing preflight" || ok "on-clean held (the missed heartbeat is the alert)"
[ "$(grep -c '^board called.*sync' "$WORK/calls.log")" -eq 3 ] && ok "the sweep itself still ran every repo" || bad "sweep stopped after preflight"

echo "case token (the credential reaches ONLY the named sync and the publish leg):"
reset
printf '  ✓ board     AB-1 -> shipped\n' > "$WORK/out/r-alpha.out"
printf '  ✓ board     AB-1 -> shipped\n' > "$WORK/out/r-beta.out"
BOARD_SWEEP_TOKEN="tok-123" run_sweep --sync-token-repo beta >/dev/null 2>&1
grep -qF "env [r-beta/sync] GH_TOKEN=tok-123" "$WORK/calls.log" && ok "the named repo's sync sees GH_TOKEN" || bad "beta sync env: $(grep 'r-beta/sync' "$WORK/calls.log")"
grep -qF "env [r-alpha/sync] GH_TOKEN=UNSET" "$WORK/calls.log" && grep -qF "env [r-gamma/sync] GH_TOKEN=UNSET" "$WORK/calls.log" \
  && ok "no other sync sees it" || bad "token leaked to another sync"
grep -q "SWEEP_TOKEN=tok-123" "$WORK/calls.log" && bad "BOARD_SWEEP_TOKEN itself reached a child" || ok "BOARD_SWEEP_TOKEN is dropped from every child's environment"
grep -qF "env [r-alpha/publish] GH_TOKEN=UNSET GIT_ASKPASS=board-git-askpass GIT_TOKEN=tok-123 SWEEP_TOKEN=UNSET PROMPT=0" "$WORK/calls.log" \
  && ok "publish gets the askpass helper, the git token, and no prompt - never GH_TOKEN" || bad "publish env: $(grep 'r-alpha/publish' "$WORK/calls.log")"
reset
printf '  ✓ board     AB-1 -> shipped\n' > "$WORK/out/r-alpha.out"
run_sweep >/dev/null 2>&1
grep -qF "env [r-alpha/publish] GH_TOKEN=UNSET GIT_ASKPASS=UNSET GIT_TOKEN=UNSET" "$WORK/calls.log" \
  && ok "no token: publish runs with the ambient git auth only" || bad "publish env without a token: $(grep 'r-alpha/publish' "$WORK/calls.log")"
GIT_ASKPASS_OUT="$("$HERE/../lib/sync/sweep/board-git-askpass" 'Username for https://github.com' && BOARD_SYNC_GIT_TOKEN=tok-9 "$HERE/../lib/sync/sweep/board-git-askpass" 'Password for x')"
[ "$GIT_ASKPASS_OUT" = "$(printf 'x-access-token\ntok-9')" ] && ok "the askpass helper answers username then token" || bad "askpass said: $GIT_ASKPASS_OUT"

echo "case publish-gate (publish only after a sync that wrote the board; rc 3 flips the sweep):"
reset
printf '  · note      nothing happened\n' > "$WORK/out/r-alpha.out"
printf '  + board     AB-2 (queued) <- '"'"'adopted row'"'"'\n' > "$WORK/out/r-beta.out"
out="$(run_sweep 2>&1)"
grep -q "board called \[r-alpha\]: publish" "$WORK/calls.log" && bad "publish ran for a no-write sync" || ok "a no-write sync never publishes"
grep -q "board called \[r-beta\]: publish --backlog-file $WORK/r-beta/_meta/BACKLOG.md" "$WORK/calls.log" && ok "a '+ board' write publishes that repo" || bad "no publish for beta"
FAKE_PUBLISH_RC=3
out="$(run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "publish rc 3 (committed, not on the remote) flips the sweep rc" || bad "sweep exit $rc (want 1)"

echo "case poster (digest -> one payload per cluster -> mark posted; change-only):"
reset
printf '  + spoke     AB-7 · from alpha\n' > "$WORK/out/r-alpha.out"
printf '  + spoke     AB-8 · from gamma\n' > "$WORK/out/r-gamma.out"
out="$(run_sweep --poster "$WORK/poster" --cluster-map "team=crew,solo=pers" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || bad "exit $rc"
[ "$(grep -c '"cluster"' "$WORK/posted.log")" -eq 1 ] && ok "one cluster had changes, one payload posted" || bad "posted: $(cat "$WORK/posted.log")"
[ "$(jq -r '.cluster' "$WORK/posted.log" | head -1)" = "team" ] && ok "alpha and gamma merged into the one team payload" || bad "cluster wrong"
jq -e '.fields[] | select(.name=="alpha")' "$WORK/posted.log" >/dev/null && jq -e '.fields[] | select(.name=="gamma")' "$WORK/posted.log" >/dev/null \
  && ok "a subsection per repo" || bad "repo subsections missing"
grep -q "digest: team posted" <<<"$out" && ok "posted logged" || bad "no posted line"
grep -q "skipped(no-change) solo" <<<"$out" && ok "the quiet cluster says so" || bad "no skipped(no-change) for solo"
[ "$(jq -c '.alpha.unsent' "$STATE")" = "[]" ] && ok "state: nothing left unsent" || bad "unsent not cleared"
: > "$WORK/posted.log"
rm -f "$WORK"/out/*
out="$(run_sweep --poster "$WORK/poster" --cluster-map "team=crew,solo=pers" 2>&1)"
[ ! -s "$WORK/posted.log" ] && ok "next tick with no changes posts nothing (change-only)" || bad "re-posted: $(cat "$WORK/posted.log")"
reset
printf '  + spoke     AB-9 · from alpha\n' > "$WORK/out/r-alpha.out"
FAKE_POSTER_RC=1
out="$(run_sweep --poster "$WORK/poster" --cluster-map "team=crew,solo=pers" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a failed post never flips the sweep rc (the digest is observational)" || bad "post failure flipped rc: $rc"
[ "$(jq '.alpha.unsent | length' "$STATE")" -eq 1 ] && ok "and the change is carried to the next tick" || bad "change not carried"

echo "case dry-run (plan only: no publish, no real state write, no post, no on-clean):"
reset
printf '  + spoke     AB-3 · planned\n  ✓ board     AB-1 -> shipped\n' > "$WORK/out/r-alpha.out"
printf '{"alpha":{"ids":["AB-OLD"],"pending":{"created":[],"adopted":[],"moves":[],"others":[],"flapping_ids":[]},"unsent":[]}}' > "$STATE"
before="$(cksum < "$STATE")"
out="$(BOARD_SWEEP_TOKEN=tok run_sweep --dry-run --poster "$WORK/poster" --cluster-map "team=crew,solo=pers" --on-clean "$WORK/hook-clean" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || bad "exit $rc"
grep -qF "board called [r-alpha]: sync --backlog-file $WORK/r-alpha/_meta/BACKLOG.md --dry-run" "$WORK/calls.log" && ok "sync runs with --dry-run" || bad "no --dry-run on sync: $(grep 'r-alpha\]: sync' "$WORK/calls.log")"
grep -q "board called \[r-alpha\]: publish" "$WORK/calls.log" && bad "publish ran in a dry run" || ok "publish never runs"
grep -q "board publish: skipped (dry-run)" <<<"$out" && ok "the skip is said out loud" || bad "no dry-run publish line"
[ ! -s "$WORK/posted.log" ] && ok "the poster is never invoked" || bad "poster ran in a dry run"
grep -q '"cluster":"team"' <<<"$out" && ok "the payload is printed instead" || bad "no payload in the log: $out"
[ "$(cksum < "$STATE")" = "$before" ] && ok "the real digest state is byte-identical (flap tracking untouched)" || bad "dry run wrote the real state"
grep -q "on-clean ran" "$WORK/calls.log" && bad "on-clean ran in a dry run" || ok "no on-clean"

echo "case name (--name labels the start and end lines):"
reset
out="$(run_sweep --name nightly 2>&1)"
grep -q "nightly: start" <<<"$out" && grep -q "nightly: end rc=0" <<<"$out" && ok "custom label" || bad "label not applied: $out"

echo "case usage (bad invocations):"
HOME="$WORK" "$SWEEP" >/dev/null 2>&1; [ $? -eq 64 ] && ok "no --registry -> 64" || bad "no --registry did not exit 64"
HOME="$WORK" "$SWEEP" --registry "$WORK/none.txt" >/dev/null 2>&1; [ $? -eq 2 ] && ok "missing registry file -> 2" || bad "missing registry did not exit 2"
HOME="$WORK" "$SWEEP" --registry "$WORK/boards.txt" --bogus >/dev/null 2>&1; [ $? -eq 64 ] && ok "unknown flag -> 64" || bad "unknown flag did not exit 64"
"$SWEEP" --help 2>&1 | grep -q "Usage: board sweep" && ok "--help prints the usage" || bad "no usage text"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
