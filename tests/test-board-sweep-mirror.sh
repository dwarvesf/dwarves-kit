#!/usr/bin/env bash
# test-board-sweep-mirror.sh -- the mirror leg of `board sweep` (lib/adapters/hermes/legs/mirror.sh, run by lib/sync/sweep/board-sweep):
# the git->Hermes kanban bridge riding every sweep tick, fed from each repo's
# ORIGIN copy of the board rather than a stale-or-dirty checkout.
#
#   AC1  --mirror-hermes-home on + hermes on PATH -> `board mirror` runs with the
#        pinned HERMES_HOME and an explicit --repo-root/--registry/--snapshot
#   AC2  a mirror failure is logged and never flips the sweep's exit code
#   AC3  no hermes CLI -> an honest skip line, `board mirror` never called
#   AC4  without --mirror-hermes-home the leg is off
#   AC5  one repo's origin unfetchable -> `board mirror` is NOT called this tick
#        (a partial registry would make the planner archive that repo's live cards)
#   AC6  origin reachable -> `board mirror` runs against the origin-snapshot registry
#   AC7  build_origin_mirror_registry reads origin/<default>, never the dirty working tree
#   AC8  a killed run still moves every temp artifact out of the repo root
#   AC9  --dry-run reaches `board mirror`
#   AC10 --dry-run with a mirror leg leaves a real health-state.json byte identical
#   AC11 INT or TERM during `board mirror`: exit 130 or 143, no origin copy left at the repo root,
#        no health record of a run that never finished
#   AC12 the leg script is gone: the sweep fails (rc 1) after the syncs, the mirror is recorded failed,
#        `board mirror` is never called, and the other legs still run
#
# A scratch $HOME gives the sweep its own $HOME/.local/bin (hermes, gh). The
# board command is a stub: no real hermes, board, or kanban is ever touched.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="$HERE/../lib/sync/sweep/board-sweep"
MIRROR_LEG="$HERE/../lib/adapters/hermes/legs/mirror.sh"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s\n" "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'command rm -rf "$WORK"' EXIT
mkdir -p "$WORK/_meta" "$WORK/.local/bin"
: > "$WORK/boards.txt"

cat > "$WORK/board" <<'EOF'
#!/usr/bin/env bash
echo "board called: $*" >> "${FAKE_CALL_LOG:-/dev/null}"
echo "board env HERMES_HOME=${HERMES_HOME:-UNSET}" >> "${FAKE_CALL_LOG:-/dev/null}"
if [ "${1:-}" = "mirror" ]; then
  [ -n "${FAKE_MIRROR_UP:-}" ] && : > "$FAKE_MIRROR_UP"
  [ -n "${FAKE_MIRROR_SLEEP:-}" ] && sleep "$FAKE_MIRROR_SLEEP"
  echo "mirror stub plan applied"
  exit "${FAKE_MIRROR_RC:-0}"
fi
exit 0
EOF
chmod +x "$WORK/board"
printf '#!/usr/bin/env bash\necho "on-clean ran" >> "$FAKE_CALL_LOG"\n' > "$WORK/hook-clean"
chmod +x "$WORK/hook-clean"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/.local/bin/hermes"
chmod +x "$WORK/.local/bin/hermes"
export FAKE_CALL_LOG FAKE_MIRROR_RC FAKE_MIRROR_SLEEP FAKE_MIRROR_UP

run_sweep() {  # extra sweep args...
  HOME="$WORK" PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
    "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/board" --repo-root "$WORK" \
    --mirror-hermes-home "$WORK/hermes-home" "$@"
}

echo "case mirror-fires (hermes on PATH -> mirror runs with the pinned home and explicit paths):"
FAKE_CALL_LOG="$WORK/call-fires.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=0 run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exits 0" || bad "sweep exited $rc"
grep -q "mirror rc=0" <<<"$out" && ok "mirror leg logged rc=0" || bad "no mirror rc=0 line: $out"
grep -qF "board env HERMES_HOME=$WORK/hermes-home" "$FAKE_CALL_LOG" \
  && ok "mirror pinned to --mirror-hermes-home" || bad "mirror HERMES_HOME wrong: $(grep HERMES_HOME "$FAKE_CALL_LOG" | tail -1)"
grep -q "home=$WORK/hermes-home" <<<"$out" && ok "log line names the store" || bad "log does not name the store: $out"
grep -qE "^board called: mirror --repo-root ${WORK} --registry .+ --snapshot ${WORK}/_meta/\\.board-mirror-snapshot\\.jsonl\$" "$FAKE_CALL_LOG" \
  && ok "argv: --repo-root, the origin-snapshot --registry, the kit's default --snapshot path" || bad "argv mismatch, got: $(cat "$FAKE_CALL_LOG")"
FAKE_CALL_LOG="$WORK/call-snap.log"; : > "$FAKE_CALL_LOG"
FAKE_MIRROR_RC=0 run_sweep --mirror-snapshot "$WORK/custom.jsonl" >/dev/null 2>&1
grep -qE -e "--snapshot ${WORK}/custom\\.jsonl\$" "$FAKE_CALL_LOG" && ok "--mirror-snapshot overrides the default" || bad "snapshot flag ignored: $(cat "$FAKE_CALL_LOG")"

echo "case mirror-fail-noflip (mirror errors -> logged, sweep still exits 0):"
FAKE_CALL_LOG="$WORK/call-fail.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=1 run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep still exits 0 despite a mirror failure (observational leg)" || bad "sweep exited $rc on a mirror failure"
grep -q "mirror rc=1" <<<"$out" && ok "mirror failure still logged" || bad "no mirror rc=1 line: $out"

echo "case no-hermes (hermes NOT on PATH -> mirror skipped, board never called):"
mv -f "$WORK/.local/bin/hermes" "$WORK/hermes.away"
FAKE_CALL_LOG="$WORK/call-noherm.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=0 run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exits 0" || bad "sweep exited $rc"
grep -q "mirror skipped: hermes CLI not on PATH" <<<"$out" && ok "honest skip line printed" || bad "no skip line: $out"
grep -q "board called: mirror" "$FAKE_CALL_LOG" 2>/dev/null && bad "board mirror was invoked despite hermes being absent" \
  || ok "board mirror never invoked (negative control holds)"
mv -f "$WORK/hermes.away" "$WORK/.local/bin/hermes"

echo "case leg-off (no --mirror-hermes-home -> no mirror leg at all):"
FAKE_CALL_LOG="$WORK/call-off.log"; : > "$FAKE_CALL_LOG"
out="$(HOME="$WORK" PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/board" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exits 0" || bad "sweep exited $rc"
grep -q "mirror" <<<"$out" && bad "the mirror leg spoke without being asked: $out" || ok "no mirror output"
grep -q "board called: mirror" "$FAKE_CALL_LOG" 2>/dev/null && bad "board mirror invoked with the leg off" || ok "board mirror never invoked"

# a real bridge=on row whose origin is a bare repo under $WORK (good case) or
# missing entirely (bad case, toggled per case by pointing the remote elsewhere)
FIXTURE_ORIGIN="$WORK/fixture-origin.git"
FIXTURE_ROOT="$WORK/fixture-repo"
git init --quiet --bare "$FIXTURE_ORIGIN"
git clone --quiet "$FIXTURE_ORIGIN" "$FIXTURE_ROOT" 2>/dev/null
mkdir -p "$FIXTURE_ROOT/_meta"
cat > "$FIXTURE_ROOT/_meta/BACKLOG.md" <<'BACKLOG'
| ID | Item | Notes | Status |
|---|---|---|---|
| ID-1 | fixture row | | queued |
BACKLOG
git -C "$FIXTURE_ROOT" -c user.email=t@example.com -c user.name=t add _meta/BACKLOG.md
git -C "$FIXTURE_ROOT" -c user.email=t@example.com -c user.name=t commit --quiet -m seed
# branch-guard: allow: pushes to a throwaway bare fixture repo under $WORK, never a real remote
git -C "$FIXTURE_ROOT" push --quiet origin HEAD:main
printf 'fixture   %s/_meta/BACKLOG.md   on rail=crew\n' "$FIXTURE_ROOT" > "$WORK/boards.txt"

echo "case mirror-gated-unreachable (one repo's origin unfetchable -> mirror skipped, board never called):"
git -C "$FIXTURE_ROOT" remote set-url origin "$WORK/nonexistent-origin.git"
FAKE_CALL_LOG="$WORK/call-gated.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=0 run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep still exits 0" || bad "sweep exited $rc"
grep -q "mirror-origin: drop fixture" <<<"$out" && ok "per-repo drop reason logged" || bad "no per-repo drop line: $out"
grep -q "mirror skipped this tick: fixture unresolved" <<<"$out" && ok "tick-skip summary line logged" || bad "no tick-skip summary line: $out"
grep -q "board called: mirror" "$FAKE_CALL_LOG" 2>/dev/null && bad "board mirror was invoked despite an unresolved repo (would archive its live cards)" \
  || ok "board mirror never invoked for a tick with an unresolved repo"

echo "case mirror-gated-clean (origin reachable -> mirror invoked with the snapshot registry):"
git -C "$FIXTURE_ROOT" remote set-url origin "$FIXTURE_ORIGIN"
FAKE_CALL_LOG="$WORK/call-clean.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=0 run_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exits 0" || bad "sweep exited $rc"
grep -q "mirror rc=0" <<<"$out" && ok "mirror leg ran and logged rc=0" || bad "mirror did not run: $out"
grep -qE "^board called: mirror --repo-root ${WORK} --registry .+ --snapshot " "$FAKE_CALL_LOG" \
  && ok "board mirror invoked with the origin-snapshot registry" || bad "argv mismatch: $(cat "$FAKE_CALL_LOG")"
[ -z "$(ls -A "$FIXTURE_ROOT" | grep 'board-mirror-origin' || true)" ] && ok "no origin copy left at the repo root after the tick" || bad "a stray origin copy was left in the repo"

echo "case dry-run (--dry-run reaches board mirror):"
FAKE_CALL_LOG="$WORK/call-dry.log"; : > "$FAKE_CALL_LOG"
FAKE_MIRROR_RC=0 run_sweep --dry-run >/dev/null 2>&1
grep -qE "^board called: mirror .* --dry-run\$" "$FAKE_CALL_LOG" && ok "mirror is planned, not applied" || bad "no --dry-run on mirror: $(cat "$FAKE_CALL_LOG")"

echo "case dry-run-health (a dry run with the mirror leg leaves a real health-state.json byte identical):"
HSR="$WORK/real-health.json"; printf '{"keep":"me"}\n' > "$HSR"; before="$(cksum < "$HSR")"
FAKE_CALL_LOG="$WORK/call-dryhealth.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=1 run_sweep --dry-run --health-state-file "$HSR" 2>&1)"
grep -q "mirror rc=1" <<<"$out" && ok "the leg ran and failed in the dry run" || bad "no mirror line: $out"
[ "$(cksum < "$HSR")" = "$before" ] && ok "the real health state is byte identical (the leg recorded into the scratch copy)" || bad "a dry run wrote the real health state: $(cat "$HSR")"

echo "case leg-signal (INT or TERM during board mirror: the sweep ends 130 or 143, nothing is left at the repo root):"
mirror_sig_case() {  # <INT|TERM> <expected rc>
  local sig="$1" want="$2" i=0 pid rc hs="$WORK/sig-health.json"
  rm -f "$hs" "$WORK/mirror.up"; FAKE_CALL_LOG="$WORK/call-sig.log"; : > "$FAKE_CALL_LOG"
  set -m
  FAKE_MIRROR_SLEEP=1 FAKE_MIRROR_UP="$WORK/mirror.up" HOME="$WORK" PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
    "$SWEEP" --registry "$WORK/boards.txt" --board-cmd "$WORK/board" --repo-root "$WORK" --mirror-hermes-home "$WORK/hermes-home" \
    --health-state-file "$hs" --on-clean "$WORK/hook-clean" > "$WORK/sig.out" 2>&1 < /dev/null &
  pid=$!
  set +m
  while [ ! -f "$WORK/mirror.up" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done
  if [ ! -f "$WORK/mirror.up" ]; then bad "$sig: board mirror never started"; kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return; fi
  [ -n "$(ls -A "$FIXTURE_ROOT" | grep 'board-mirror-origin' || true)" ] && ok "$sig: (control) the origin copy exists while board mirror runs" || bad "$sig: no origin copy during the run"
  kill -"$sig" "$pid"
  wait "$pid"; rc=$?
  [ "$rc" -eq "$want" ] && ok "$sig: the sweep exits $want" || bad "$sig: exit $rc (want $want): $(cat "$WORK/sig.out")"
  [ -z "$(ls -A "$FIXTURE_ROOT" | grep 'board-mirror-origin' || true)" ] && ok "$sig: no origin copy left at the repo root" || bad "$sig: a stray origin copy: $(ls -A "$FIXTURE_ROOT")"
  [ "$(jq -r '.mirror // "none"' "$hs" 2>/dev/null)" = "none" ] && ok "$sig: no mirror record for a run that never finished" || bad "$sig: health state: $(cat "$hs")"
  grep -q "board-sweep: end" "$WORK/sig.out" && bad "$sig: the end line was printed" || ok "$sig: no end line"
  grep -q "on-clean ran" "$FAKE_CALL_LOG" && bad "$sig: on-clean ran" || ok "$sig: no on-clean hook"
}
mirror_sig_case TERM 143
mirror_sig_case INT 130

echo "case leg-missing (the mirror leg script is gone: the syncs ran, the sweep fails, board mirror is never called):"
XDIR="$WORK/ext-adapters"; mkdir -p "$XDIR/hermes/legs"
for f in adapter.py adapter.tsv hermes.py; do command cp "$HERE/../lib/adapters/hermes/$f" "$XDIR/hermes/$f"; done
for f in expire.sh link-check.sh; do command cp "$HERE/../lib/adapters/hermes/legs/$f" "$XDIR/hermes/legs/$f"; done
FAKE_CALL_LOG="$WORK/call-missing.log"; : > "$FAKE_CALL_LOG"
hs="$WORK/missing-health.json"; rm -f "$hs"
out="$(KIT_ADAPTERS_DIR="$XDIR" FAKE_MIRROR_RC=0 run_sweep --health-state-file "$hs" --on-clean "$WORK/hook-clean" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "the sweep ends rc 1" || bad "exit $rc: $out"
grep -q "leg mirror failed: $XDIR/hermes/legs/mirror.sh not found" <<<"$out" && ok "the line names the leg and its script" || bad "no failed line: $out"
grep -q "board called: mirror" "$FAKE_CALL_LOG" && bad "board mirror ran with no leg script" || ok "board mirror never called"
[ "$(jq -r '.mirror.rc' "$hs" 2>/dev/null)" = "1" ] && ok "the mirror is recorded failed" || bad "health state: $(cat "$hs" 2>/dev/null)"
grep -q "board called: sync" "$FAKE_CALL_LOG" && ok "the per-repo sync ran" || bad "no sync call: $(cat "$FAKE_CALL_LOG")"
grep -q "on-clean ran" "$FAKE_CALL_LOG" && bad "on-clean ran" || ok "on-clean held"
FAKE_CALL_LOG="$WORK/call-present.log"; : > "$FAKE_CALL_LOG"
out="$(FAKE_MIRROR_RC=0 run_sweep --on-clean "$WORK/hook-clean" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "on-clean ran" "$FAKE_CALL_LOG" && ! grep -q "leg mirror failed" <<<"$out" && ok "(control) with the script present the same sweep ends rc 0 and runs on-clean" || bad "control: rc=$rc $out"

# ---- build_origin_mirror_registry in isolation ------------------------------
# Extract the function alone. Sourcing the whole sweep would run the sweep.
TMP="$WORK/unit"; mkdir -p "$TMP"
sed -n '/^build_origin_mirror_registry() {/,/^}/p' "$MIRROR_LEG" > "$TMP/fn.sh"

fail=0
assert() {  # $1 label, $2 expected substring, $3 actual
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) bad "$1: expected '$2' in: $3" ;;
  esac
}
assert_not() {  # $1 label, $2 forbidden substring, $3 actual
  case "$3" in
    *"$2"*) bad "$1: did not expect '$2' in: $3" ;;
    *) ok "$1" ;;
  esac
}

echo "case origin-registry (origin/<default> wins over a dirty working tree):"
ORIGIN="$TMP/origin.git"
ROOT="$TMP/clone/repo"
mkdir -p "$TMP/clone"
git init --quiet --bare "$ORIGIN"
git clone --quiet "$ORIGIN" "$ROOT" 2>/dev/null
mkdir -p "$ROOT/_meta"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-1 | fresh row from origin | | queued |\n' > "$ROOT/_meta/BACKLOG.md"
git -C "$ROOT" -c user.email=t@example.com -c user.name=t add _meta/BACKLOG.md
git -C "$ROOT" -c user.email=t@example.com -c user.name=t commit --quiet -m "fresh row"
# branch-guard: allow: pushes to a throwaway bare fixture repo under $TMP, never a real remote
git -C "$ROOT" push --quiet origin HEAD:main
git -C "$ROOT" branch --quiet -M main 2>/dev/null || true
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-1 | STALE row still on disk | | queued |\n' > "$ROOT/_meta/BACKLOG.md"

REGISTRY="$TMP/boards.txt"
printf '# comment line\nfixture   %s/_meta/BACKLOG.md   on rail=crew\nother     %s/_meta/BACKLOG.md   off\n' "$ROOT" "$ROOT" > "$REGISTRY"
OUT_REGISTRY="$TMP/out-registry.txt"; SNAP_LIST="$TMP/snap-list.txt"; FAILED_LIST="$TMP/failed-list.txt"
: > "$SNAP_LIST"; : > "$FAILED_LIST"
bash -c '
  set -u
  '"$(cat "$TMP/fn.sh")"'
  build_origin_mirror_registry "'"$REGISTRY"'" "'"$OUT_REGISTRY"'" "'"$SNAP_LIST"'" "'"$FAILED_LIST"'"
' >/dev/null 2>&1

rewritten_line=$(grep '^fixture ' "$OUT_REGISTRY" || true)
assert_not "bridge=on row no longer points at the live checkout" "$ROOT/_meta/BACKLOG.md" "$rewritten_line"
assert "bridge=off row passes through unchanged" "$ROOT/_meta/BACKLOG.md" "$(grep '^other ' "$OUT_REGISTRY" || true)"
assert "comment line preserved" "# comment line" "$(head -1 "$OUT_REGISTRY")"
assert "the rail column rides through the rewrite" "rail=crew" "$rewritten_line"
snap_path=$(printf '%s\n' "$rewritten_line" | awk '{print $2}')
if [ -n "$snap_path" ] && [ -f "$snap_path" ]; then
  content=$(cat "$snap_path")
  assert "snapshot carries origin's fresh row" "fresh row from origin" "$content"
  assert_not "snapshot does not carry the dirty on-disk row" "STALE row still on disk" "$content"
else
  bad "snapshot file missing at '$snap_path'"
fi
assert "snapshot path recorded for cleanup" "$snap_path" "$(cat "$SNAP_LIST")"
[ -s "$FAILED_LIST" ] && bad "a clean run should not populate failed_list: $(cat "$FAILED_LIST")" || ok "a clean run leaves failed_list empty"

echo "case origin-fetch-fails (drop the repo, log once, no fallback to the dirty on-disk row):"
BROKEN="$TMP/broken-clone/repo"
mkdir -p "$TMP/broken-clone"
git init --quiet "$BROKEN"
mkdir -p "$BROKEN/_meta"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-2 | STALE row, origin unreachable | | queued |\n' > "$BROKEN/_meta/BACKLOG.md"
git -C "$BROKEN" -c user.email=t@example.com -c user.name=t add _meta/BACKLOG.md
git -C "$BROKEN" -c user.email=t@example.com -c user.name=t commit --quiet -m "seed"
git -C "$BROKEN" remote add origin "$TMP/nonexistent-origin.git"
REGISTRY2="$TMP/boards2.txt"; OUT_REGISTRY2="$TMP/out-registry2.txt"; SNAP_LIST2="$TMP/snap-list2.txt"; FAILED_LIST2="$TMP/failed-list2.txt"
printf 'broken    %s/_meta/BACKLOG.md   on rail=crew\n' "$BROKEN" > "$REGISTRY2"
: > "$SNAP_LIST2"; : > "$FAILED_LIST2"
out2=$(bash -c '
  set -u
  '"$(cat "$TMP/fn.sh")"'
  build_origin_mirror_registry "'"$REGISTRY2"'" "'"$OUT_REGISTRY2"'" "'"$SNAP_LIST2"'" "'"$FAILED_LIST2"'"
' 2>&1)
assert "fetch failure logs a drop line" "drop broken" "$out2"
assert "fetch failure names the cause" "fetch origin failed" "$out2"
assert "fetch failure records the repo name in failed_list" "broken" "$(cat "$FAILED_LIST2")"
[ -z "$(grep '^broken ' "$OUT_REGISTRY2" || true)" ] && ok "fetch failure drops the row entirely" || bad "fetch failure kept a row"
assert_not "fetch failure never falls back to the live checkout path" "$BROKEN/_meta/BACKLOG.md" "$(cat "$OUT_REGISTRY2")"

echo "case trap (a killed run still moves every temp artifact out of the repo root):"
sed -n '/^    # BEGIN mirror-cleanup-trap/,/^    # END mirror-cleanup-trap/p' "$MIRROR_LEG" > "$TMP/trap.sh"
assert "trap block extracted" "trap 'mirror_cleanup; exit 143' TERM" "$(cat "$TMP/trap.sh")"
TRAP_ROOT="$TMP/trap-fixture"; mkdir -p "$TRAP_ROOT"
bash -c '
  set -u
  MIRROR_REGISTRY="'"$TRAP_ROOT"'/registry.txt"
  MIRROR_SNAP_LIST="'"$TRAP_ROOT"'/snap-list.txt"
  MIRROR_FAILED="'"$TRAP_ROOT"'/failed.txt"
  MIRROR_DISCARD="'"$TRAP_ROOT"'/discard"
  mkdir -p "$MIRROR_DISCARD"
  : > "$MIRROR_REGISTRY"
  : > "$MIRROR_FAILED"
  FAKE_SNAP="'"$TRAP_ROOT"'/repo-root/.board-mirror-origin.fixture.md"
  mkdir -p "$(dirname "$FAKE_SNAP")"
  echo "fake snapshot" > "$FAKE_SNAP"
  printf "%s\n" "$FAKE_SNAP" > "$MIRROR_SNAP_LIST"
  '"$(cat "$TMP/trap.sh")"'
  kill -TERM "$$"
  sleep 5
' >/dev/null 2>&1
trap_rc=$?
assert "SIGTERM handler exits 143 (killed, not swallowed)" "143" "$trap_rc"
assert "trap moved the per-repo snapshot into the discard dir" "fake snapshot" "$(cat "$TRAP_ROOT/discard/.board-mirror-origin.fixture.md" 2>/dev/null)"
[ -f "$TRAP_ROOT/repo-root/.board-mirror-origin.fixture.md" ] && bad "trap left the snapshot at the repo root" || ok "trap left nothing behind at the repo root"
[ -f "$TRAP_ROOT/failed.txt" ] && bad "trap left the failed-list temp file in place" || ok "trap moved the failed-list temp file out"
[ -f "$TRAP_ROOT/registry.txt" ] && bad "trap left the registry temp file in place" || ok "trap moved the registry temp file out"
[ -f "$TRAP_ROOT/snap-list.txt" ] && bad "trap left the snap-list temp file in place" || ok "trap moved the snap-list temp file out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
