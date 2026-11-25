#!/usr/bin/env bash
# Suite for the proof-capture module. Standalone: sources nothing from the kit.
# Prints one line per case (PASS, FAIL or SKIP) and a recap; exit 0 when nothing failed.
# Every case runs the tool through a stub browser or stub vhs, never a real one (case 11 is opt-in).
# The tool gets a private TMPDIR, so "nothing left behind" is an exact assertion.
# operator-layer: unpinned-ok the suite never reaches the config resolver; the kit-config text below is a planted lint violation
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRY="$HERE/../bin/proof-capture"
EXAMPLES="$HERE/../examples"

BASE_TMP=${TMPDIR:-/tmp}
BASE_TMP=${BASE_TMP%/}
SUITE_TMP=$(mktemp -d "$BASE_TMP/pcsuite.XXXXXX") || exit 1
TOOL_TMP="$SUITE_TMP/tmp"
mkdir "$TOOL_TMP"
export TMPDIR="$TOOL_TMP"
STUB_PIDS="$SUITE_TMP/stub.pids"
: >"$STUB_PIDS"
export STUB_PIDS
OUTF="$SUITE_TMP/stdout"
ERRF="$SUITE_TMP/stderr"
TOOL_PID=""
NPASS=0; NFAIL=0; NSKIP=0

cleanup() {
  if tool_alive; then kill -TERM "$TOOL_PID" 2>/dev/null; fi
  [ ! -f "$STUB_PIDS" ] || kill_owned
  case "$SUITE_TMP" in */pcsuite.*) rm -rf "$SUITE_TMP" ;; esac
}
trap cleanup EXIT

# ---- case bookkeeping ---------------------------------------------------------------------------
begin_case() { CN=$1; CNAME=$2; CBAD=0; CNOTES=""; }
note_bad() { CBAD=1; CNOTES="$CNOTES  - $1
"; }
end_case() {
  if [ "$CBAD" = 0 ]; then
    NPASS=$((NPASS + 1)); echo "PASS $CN $CNAME"
  else
    NFAIL=$((NFAIL + 1)); echo "FAIL $CN $CNAME"; printf '%s' "$CNOTES"
  fi
}
skip_case() { NSKIP=$((NSKIP + 1)); echo "SKIP $1 $2"; }

# ---- running the tool ---------------------------------------------------------------------------
# start_tool <args...>: runs the entry in its own process group (job control on, so INT and TERM reach it),
# stdin from /dev/null, output in $OUTF and $ERRF. RUN_PATH, when set (even empty), is the PATH it gets.
start_tool() {
  : >"$OUTF"; : >"$ERRF"
  {
    set -m
    PATH="${RUN_PATH-$PATH}" "$BASH" "${ENTRY_USE:-$ENTRY}" "$@" </dev/null >"$OUTF" 2>"$ERRF" &
    TOOL_PID=$!
    set +m
  } 2>/dev/null
}

# tool_alive: the tool is a running job of this shell. A job bash has already reaped is not listed, so a pid that
# may have been reused is never signalled.
tool_alive() { [ -n "$TOOL_PID" ] && jobs -pr 2>/dev/null | grep -qx "$TOOL_PID"; }

# wait_tool [limit]: waits for the tool by pid, under a guard (default 30 s) that kills only that pid.
wait_tool() {
  local end=$((SECONDS + ${1:-30}))
  TIMED_OUT=0
  while tool_alive; do
    if [ "$SECONDS" -ge "$end" ]; then
      kill -KILL "$TOOL_PID" 2>/dev/null
      TIMED_OUT=1
      break
    fi
    sleep 0.2
  done
  { wait "$TOOL_PID"; } 2>/dev/null
  RC=$?
  TOOL_PID=""
}

run_tool() { start_tool "$@"; wait_tool; [ "$TIMED_OUT" = 0 ] || note_bad "the tool hit the 30 s guard"; }

# ---- assertions ---------------------------------------------------------------------------------
want_rc() { [ "$RC" = "$1" ] || note_bad "$2: exit $RC, wanted $1"; }
want_err_has() { grep -qF -- "$1" "$ERRF" || note_bad "$2: stderr lacks: $1"; }
want_err_is() {
  local got
  got=$(cat "$ERRF")
  [ "$got" = "$1" ] || note_bad "$2: stderr is not exactly the one expected line (got: $got)"
}
want_out_empty() { [ ! -s "$OUTF" ] || note_bad "$1: stdout is not empty"; }
want_absent() { [ ! -e "$1" ] || note_bad "$2: file exists but should not"; }
want_tool_tmp_clean() {
  local left
  left=$(ls -A "$TOOL_TMP")
  [ -z "$left" ] || note_bad "$1: the private TMPDIR is not empty (left: $left)"
}

reset_env() {
  unset PROOF_CAPTURE_BROWSER PROOF_CAPTURE_VHS PROOF_CAPTURE_DEADLINE RUN_PATH STUB_READY
  export PROOF_CAPTURE_BROWSER_CANDIDATES="$SUITE_TMP/no-such-a:$SUITE_TMP/no-such-b"
}

new_dir() { local d; d=$(mktemp -d "$SUITE_TMP/d.XXXXXX") || return 1; echo "$d"; }

MSG_NOBROWSER='proof-capture: no Chromium-family browser found; install Chrome, Chromium or Edge, or set PROOF_CAPTURE_BROWSER=<path>'

# ---- stub browser -------------------------------------------------------------------------------
# The stub parses --screenshot= and --user-data-dir=, appends its argv (one word per line) to $STUB_ARGV and its
# pid to $STUB_PIDS, then acts by $STUB_MODE. Every mode that waits ends in `exec sleep 20`, so the process the
# suite recorded is the process that sleeps. $STUB_READY, when set, is touched last, once the stub is set up.
STUB_DIR="$SUITE_TMP/stubs"
mkdir "$STUB_DIR"
cat >"$STUB_DIR/stub-browser" <<'STUBEOF'
#!/bin/bash
PATH=/usr/bin:/bin:$PATH
shot=""; prof=""
for a in "$@"; do
  case "$a" in
    --screenshot=*) shot=${a#--screenshot=} ;;
    --user-data-dir=*) prof=${a#--user-data-dir=} ;;
  esac
done
if [ -n "${STUB_ARGV:-}" ]; then printf '%s\n' "$@" >>"$STUB_ARGV"; fi
rec() { local l; l=$(ps -o lstart= -p "$1" 2>/dev/null); echo "$1|$(echo $l)" >>"$STUB_PIDS"; }
rec $$
[ -z "$prof" ] || mkdir -p "$prof"
ready() { if [ -n "${STUB_READY:-}" ]; then : >"$STUB_READY"; fi; }
case "${STUB_MODE:-ok}" in
  ok) cp "$STUB_PNG" "$shot"; ready; exit 0 ;;
  slow-write)
    head -c 20 "$STUB_PNG" >"$shot"; ready
    sleep 1.5
    tail -c +21 "$STUB_PNG" >>"$shot"
    exit 0 ;;
  write-then-hang)
    cp "$STUB_PNG" "$shot"
    sleep 20 &
    rec $!
    ready
    exec sleep 20 ;;
  never-write) ready; exec sleep 20 ;;
  term-ignore)
    trap '' TERM
    ( trap '' TERM; exec sleep 20 ) &
    rec $!
    ready
    exec sleep 20 ;;
  term-mark)
    trap ': >"$STUB_TERMED"' TERM
    ( trap '' TERM; exec sleep 20 ) &
    rec $!
    ready
    while :; do sleep 20 & wait $!; done ;;
  swap-outdir)
    mv "$STUB_SWAP_DIR" "$STUB_SWAP_DIR.moved"
    ln -s "$STUB_SWAP_TO" "$STUB_SWAP_DIR"
    cp "$STUB_PNG" "$shot"; ready; exit 0 ;;
  exit-no-file) ready; exit 0 ;;
esac
exit 3
STUBEOF
chmod +x "$STUB_DIR/stub-browser"
STUB_BROWSER="$STUB_DIR/stub-browser"

# A PNG-shaped file: the real magic, IHDR and IEND trailer (the tool checks only magic and trailer; the IDAT checksum is not real).
STUB_PNG="$STUB_DIR/stub.png"
png_hex="89504e470d0a1a0a0000000d49484452000000010000000108020000009077 53de0000000c4944415408d763f8cfc00000030101 00c9fe92ef0000000049454e44ae426082"
png_hex=${png_hex// /}
: >"$STUB_PNG"
i=0
while [ "$i" -lt "${#png_hex}" ]; do
  printf "\\x${png_hex:$i:2}" >>"$STUB_PNG"
  i=$((i + 2))
done
export STUB_PNG
PNG_SIZE=$(wc -c <"$STUB_PNG")
PNG_SIZE=${PNG_SIZE//[[:space:]]/}

# A pid record is "pid|start time", written by the stub itself. The suite signals a pid only when the live process
# shows the recorded start time (proof it is that stub and not a reused pid). It counts a pid as gone only when the
# pid is dead or shows a different start time; a pid it cannot tell about counts as alive.
lstart_of() { local l; l=$(ps -o lstart= -p "$1" 2>/dev/null); echo $l; }

proves_own() {
  local pid=${1%%|*} start=${1#*|} now
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -n "$start" ] && [ "$start" != "$1" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  now=$(lstart_of "$pid")
  [ -n "$now" ] && [ "$now" = "$start" ]
}

record_gone() {
  local pid=${1%%|*} start=${1#*|} now
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 0
  [ -n "$start" ] && [ "$start" != "$1" ] || return 1
  now=$(lstart_of "$pid")
  [ -n "$now" ] && [ "$now" != "$start" ]
}

kill_owned() {
  local r
  while read -r r; do
    [ -n "$r" ] || continue
    if proves_own "$r"; then kill -KILL "${r%%|*}" 2>/dev/null; fi
  done <"$STUB_PIDS"
}

records_valid() {
  local r bad=0
  while read -r r; do
    [ -n "$r" ] || continue
    case "$r" in
      [0-9]*'|'*) case "${r%%|*}" in *[!0-9]*) bad=1 ;; esac ;;
      *) bad=1 ;;
    esac
  done <"$STUB_PIDS"
  [ "$bad" = 0 ]
}

reset_pids() {
  kill_owned
  : >"$STUB_PIDS"
}

pids_alive() {
  local r n=0
  while read -r r; do
    [ -n "$r" ] || continue
    record_gone "$r" || n=$((n + 1))
  done <"$STUB_PIDS"
  echo "$n"
}

# want_pids_gone <label> [bound]: at least one pid was recorded, and every one is gone within the bound.
want_pids_gone() {
  local end=$((SECONDS + ${2:-15}))
  [ -s "$STUB_PIDS" ] || { note_bad "$1: the stub recorded no pid (the check would be empty)"; return 0; }
  records_valid || note_bad "$1: a pid record is malformed, so the check cannot be trusted"
  while [ "$(pids_alive)" != 0 ] && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
  [ "$(pids_alive)" = 0 ] || note_bad "$1: a recorded stub pid is still alive"
}

want_same_file() { cmp -s "$1" "$2" || note_bad "$3: output differs from the expected bytes"; }
want_no_hidden_left() {
  local left
  left=$(ls -A "$1" | grep '^\.proof-capture\.')
  [ -z "$left" ] || note_bad "$2: a .proof-capture.* file is left next to the output"
}

# stub_env <mode> <argv file>: point the tool at the stub through PROOF_CAPTURE_BROWSER.
stub_env() {
  reset_env
  reset_pids
  export PROOF_CAPTURE_BROWSER="$STUB_BROWSER"
  export STUB_MODE="$1" STUB_ARGV="$2"
  : >"$2"
}

# ---- case 1: page file --------------------------------------------------------------------------
case_1() {
  local d
  begin_case 1 "page file"
  d=$(new_dir)

  stub_env ok "$d/argv"
  run_tool run page "$EXAMPLES/hello.html" "$d/o.png"
  want_rc 0 "ok"
  want_same_file "$d/o.png" "$STUB_PNG" "ok"
  [ "$(cat "$OUTF")" = "proof-capture: wrote $d/o.png ($PNG_SIZE bytes)" ] || note_bad "ok: the stdout line is wrong"
  want_tool_tmp_clean "ok"
  want_no_hidden_left "$d" "ok"

  run_tool run page "$EXAMPLES/hello.html" "$d/new/sub/o.png"
  want_rc 0 "missing parent"
  want_same_file "$d/new/sub/o.png" "$STUB_PNG" "missing parent"

  printf 'OLD' >"$d/exist.png"
  run_tool run page "$EXAMPLES/hello.html" "$d/exist.png"
  want_rc 0 "replace"
  want_same_file "$d/exist.png" "$STUB_PNG" "existing output replaced"

  stub_env slow-write "$d/argv2"
  run_tool run page "$EXAMPLES/hello.html" "$d/slow.png"
  want_rc 0 "slow-write"
  want_same_file "$d/slow.png" "$STUB_PNG" "slow-write is byte for byte"
  want_tool_tmp_clean "slow-write"

  stub_env exit-no-file "$d/argv3"
  run_tool run page "$EXAMPLES/hello.html" "$d/none.png"
  want_rc 1 "exit-no-file"
  want_err_has "exited without a valid artifact" "exit-no-file"
  want_absent "$d/none.png" "exit-no-file wrote an artifact"
  want_tool_tmp_clean "exit-no-file"
  want_no_hidden_left "$d" "exit-no-file"
  end_case
}

# ---- case 2: page URL and path encoding ---------------------------------------------------------
case_2() {
  local d last
  begin_case 2 "page URL and path encoding"
  d=$(new_dir)

  stub_env ok "$d/argv"
  run_tool run page "http://example.invalid/page?x=1#top" "$d/u.png"
  want_rc 0 "http url"
  last=$(tail -n 1 "$d/argv")
  [ "$last" = "http://example.invalid/page?x=1#top" ] || note_bad "http url: not passed through unchanged (got: ${last//"$d"/D})"

  cp "$EXAMPLES/hello.html" "$d/a b#c?d%e.html"
  : >"$d/argv"
  run_tool run page "$d/a b#c?d%e.html" "$d/p.png"
  want_rc 0 "special path"
  last=$(tail -n 1 "$d/argv")
  [ "$last" = "file://$d/a%20b%23c%3Fd%25e.html" ] || note_bad "special path: not percent-encoded (got: ${last//"$d"/D})"

  cp "$EXAMPLES/hello.html" "$d/rel.html"
  : >"$d/argv"
  cd "$d" || note_bad "cd failed"
  run_tool run page "./rel.html" "$d/r.png"
  cd "$HERE" || note_bad "cd back failed"
  want_rc 0 "relative path"
  last=$(tail -n 1 "$d/argv")
  [ "$last" = "file://$d/rel.html" ] || note_bad "relative path: not resolved to an absolute file URL (got: ${last//"$d"/D})"

  : >"$d/argv"
  run_tool run page "file:///some/where.html" "$d/f.png"
  want_rc 0 "file url"
  last=$(tail -n 1 "$d/argv")
  [ "$last" = "file:///some/where.html" ] || note_bad "file url: not passed through unchanged (got: ${last//"$d"/D})"
  want_tool_tmp_clean "case 2"
  end_case
}

# ---- case 3: argv, profile and leftovers --------------------------------------------------------
case_3() {
  local d prof shot
  begin_case 3 "argv, profile and leftovers"
  d=$(new_dir)

  stub_env ok "$d/argv"
  run_tool run page "$EXAMPLES/hello.html" "$d/o.png"
  want_rc 0 "run"
  grep -qxF -- "--headless=new" "$d/argv" || note_bad "argv lacks --headless=new"
  grep -qxF -- "--disable-sync" "$d/argv" || note_bad "argv lacks --disable-sync"
  grep -qxF -- "--use-mock-keychain" "$d/argv" || note_bad "argv lacks --use-mock-keychain"
  grep -qxF -- "--password-store=basic" "$d/argv" || note_bad "argv lacks --password-store=basic"
  grep -qxF -- "--window-size=1280,800" "$d/argv" || note_bad "argv lacks the default window size"
  if grep -q -- '--virtual-time-budget' "$d/argv"; then note_bad "argv has a time budget although --wait was not given"; fi
  prof=$(grep -- '^--user-data-dir=' "$d/argv" | head -n 1)
  prof=${prof#--user-data-dir=}
  shot=$(grep -- '^--screenshot=' "$d/argv" | head -n 1)
  shot=${shot#--screenshot=}
  case "$prof" in "$TOOL_TMP"/proof-capture.*/profile) ;; *) note_bad "the profile is not under the private TMPDIR work dir" ;; esac
  case "$shot" in "$TOOL_TMP"/proof-capture.*/*) ;; *) note_bad "the browser writes outside the private work dir" ;; esac
  [ -n "$prof" ] && [ ! -e "$prof" ] || note_bad "the profile dir still exists after the run"
  want_tool_tmp_clean "case 3"
  want_no_hidden_left "$d" "case 3"
  [ "$(ls -A "$d" | grep -v '^argv$' | tr '\n' ' ')" = "o.png " ] || note_bad "something besides the output was left in the output dir"

  : >"$d/argv"
  run_tool run page "$EXAMPLES/hello.html" "$d/w.png" --width 400 --height 600 --wait 3000
  want_rc 0 "flags run"
  grep -qxF -- "--window-size=400,600" "$d/argv" || note_bad "argv lacks --window-size=400,600"
  grep -qxF -- "--virtual-time-budget=3000" "$d/argv" || note_bad "argv lacks --virtual-time-budget=3000"
  end_case
}

# wait_ready <file> [bound]: wait for the stub's ready marker (the stub touches it last, once it is set up).
wait_ready() {
  local end=$((SECONDS + ${2:-20}))
  while [ ! -e "$1" ] && [ "$SECONDS" -lt "$end" ]; do sleep 0.1; done
  [ -e "$1" ]
}

# want_gone_by <label> <t0> <limit>: every recorded pid is gone within <limit> seconds of <t0> (a SECONDS value).
# Stubs sleep 20 s on their own, so a limit past that would pass for the wrong reason; a late finish is reported.
want_gone_by() {
  local left=$(($3 - (SECONDS - $2)))
  [ "$left" -ge 1 ] || left=1
  want_pids_gone "$1" "$left"
  [ $((SECONDS - $2)) -lt 19 ] || note_bad "$1: finished too late to prove anything (the stub's own 20 s sleep may have ended it)"
}

# signal_row <mode> <signal>: the tool gets <signal> mid-run; it must exit 1 with the one line, leave nothing behind.
signal_row() {
  local mode=$1 sig=$2 d t0 label="$1 stub, $2"
  d=$(new_dir)
  stub_env "$mode" "$d/argv"
  export STUB_READY="$d/ready"
  t0=$SECONDS
  start_tool run page "$EXAMPLES/hello.html" "$d/s.png"
  if ! wait_ready "$d/ready"; then
    note_bad "$label: the stub never became ready"
    tool_alive && kill -TERM "$TOOL_PID" 2>/dev/null
    wait_tool 15
    return 0
  fi
  tool_alive && kill -s "$sig" "$TOOL_PID"
  wait_tool 15
  [ "$TIMED_OUT" = 0 ] || note_bad "$label: the tool did not exit after the signal"
  want_rc 1 "$label"
  want_err_is "proof-capture: interrupted" "$label"
  want_gone_by "$label" "$t0" 17
  want_tool_tmp_clean "$label"
  want_no_hidden_left "$d" "$label"
  want_absent "$d/s.png" "$label wrote an artifact"
}

# ---- case 4: a browser that writes the file and never exits ------------------------------------
case_4() {
  local d t0
  begin_case 4 "write-then-hang"
  d=$(new_dir)
  stub_env write-then-hang "$d/argv"
  t0=$SECONDS
  start_tool run page "$EXAMPLES/hello.html" "$d/o.png"
  wait_tool 15
  [ "$TIMED_OUT" = 0 ] || note_bad "the tool did not return"
  want_rc 0 "write-then-hang"
  want_same_file "$d/o.png" "$STUB_PNG" "write-then-hang"
  [ "$(wc -l <"$STUB_PIDS" | tr -d ' ')" -ge 2 ] || note_bad "the stub and its helper were not both recorded"
  want_gone_by "write-then-hang (the helper too)" "$t0" 17
  want_tool_tmp_clean "write-then-hang"
  want_no_hidden_left "$d" "write-then-hang"
  end_case
}

# ---- case 6: TERM, INT and HUP to the tool mid-run ---------------------------------------------
case_6() {
  local mode sig
  begin_case 6 "TERM, INT and HUP to the tool"
  for mode in never-write term-ignore; do
    for sig in TERM INT HUP; do
      signal_row "$mode" "$sig"
    done
  done
  end_case
}

# ---- case 12: KILL to the tool; the watchdog ends the group ------------------------------------
case_12() {
  local d t0 w
  begin_case 12 "KILL to the tool, the watchdog ends the group"
  d=$(new_dir)
  stub_env never-write "$d/argv"
  export STUB_READY="$d/ready"
  t0=$SECONDS
  start_tool run page "$EXAMPLES/hello.html" "$d/k.png" --deadline 2
  if ! wait_ready "$d/ready"; then
    note_bad "the stub never became ready"
  fi
  { tool_alive && kill -KILL "$TOOL_PID"; wait_tool 10; } 2>/dev/null
  [ "$(pids_alive)" -ge 1 ] || note_bad "the stub was already gone right after the KILL, so the check would prove nothing"
  want_gone_by "KILL to the tool" "$t0" 17
  # The documented residual: the work dir of a killed tool stays under TMPDIR. Remove it so later cases start clean.
  for w in "$TOOL_TMP"/proof-capture.*; do
    [ -d "$w" ] || continue
    case "$w" in "$TOOL_TMP"/proof-capture.*) rm -rf "$w" ;; esac
  done
  want_absent "$d/k.png" "KILL case wrote an artifact"
  end_case
}

# ---- case 13: a second signal during the reap --------------------------------------------------
# The term-mark stub touches $STUB_TERMED when it gets the tool's TERM and then keeps running, so the marker tells
# the suite the reap is inside its TERM wait. The second TERM goes out at once. The tool must read it, skip the rest
# of the wait and KILL: it exits well inside the 2 s wait. Without the flag check it would sit out the whole wait.
second_term_attempt() {
  local d n
  d=$(new_dir)
  stub_env term-mark "$d/argv"
  export STUB_READY="$d/ready" STUB_TERMED="$d/termed"
  start_tool run page "$EXAMPLES/hello.html" "$d/s.png" --deadline 2
  wait_ready "$d/ready" || note_bad "the stub never became ready"
  if ! wait_ready "$d/termed" 20; then
    note_bad "the stub never got the tool's TERM"
    tool_alive && kill -TERM "$TOOL_PID" 2>/dev/null
    wait_tool 15
    return 0
  fi
  tool_alive && kill -s TERM "$TOOL_PID" 2>/dev/null
  n=0
  while tool_alive && [ "$n" -lt 24 ]; do sleep 0.05; n=$((n + 1)); done
  SECOND_FAST=1
  if tool_alive; then SECOND_FAST=0; fi
  wait_tool 15
  [ "$TIMED_OUT" = 0 ] || note_bad "the tool did not exit"
  want_rc 1 "second TERM"
  want_pids_gone "second TERM during the reap" 6
  want_tool_tmp_clean "second TERM"
  want_no_hidden_left "$d" "second TERM"
}

case_13() {
  local keep
  begin_case 13 "a second signal during the reap"
  SECOND_FAST=0
  second_term_attempt
  if [ "$SECOND_FAST" = 0 ] && [ "$CBAD" = 0 ]; then
    # one retry: a loaded host can delay the tool past the bound without the flag check being missing
    second_term_attempt
  fi
  [ "$SECOND_FAST" = 1 ] || note_bad "the tool did not leave the TERM wait at once after the second TERM (twice)"
  end_case
}

# ---- case 5: deadline -----------------------------------------------------------------------------
case_5() {
  local d t0
  begin_case 5 "deadline"
  d=$(new_dir)

  stub_env never-write "$d/argv"
  printf 'OLD' >"$d/keep.png"
  run_tool run page "$EXAMPLES/hello.html" "$d/keep.png" --deadline 2
  want_rc 1 "never-write"
  want_err_is "proof-capture: no valid artifact within 2s" "never-write"
  [ "$(cat "$d/keep.png")" = "OLD" ] || note_bad "never-write: the existing output was changed"
  want_pids_gone "never-write"
  want_tool_tmp_clean "never-write"
  want_no_hidden_left "$d" "never-write"

  reset_pids
  run_tool run page "$EXAMPLES/hello.html" "$d/none.png" --deadline 2
  want_absent "$d/none.png" "never-write wrote an artifact"

  reset_pids
  export PROOF_CAPTURE_DEADLINE=2
  run_tool run page "$EXAMPLES/hello.html" "$d/none.png"
  want_rc 1 "env deadline"
  want_err_is "proof-capture: no valid artifact within 2s" "env deadline"
  want_pids_gone "env deadline"

  reset_pids
  export PROOF_CAPTURE_DEADLINE=300
  run_tool run page "$EXAMPLES/hello.html" "$d/none.png" --deadline 2
  want_rc 1 "flag wins over env"
  want_err_is "proof-capture: no valid artifact within 2s" "flag wins over env"
  want_pids_gone "flag wins over env"

  # A browser and a helper that ignore TERM: the KILL step must end every recorded pid.
  stub_env term-ignore "$d/argv"
  t0=$SECONDS
  run_tool run page "$EXAMPLES/hello.html" "$d/none.png" --deadline 2
  want_rc 1 "term-ignore"
  want_err_is "proof-capture: no valid artifact within 2s" "term-ignore"
  want_gone_by "term-ignore (KILL escalation)" "$t0" 17
  want_tool_tmp_clean "case 5"
  end_case
}

# ---- case 7: browser dependencies ----------------------------------------------------------------
case_7() {
  local d f
  begin_case 7 "browser dependencies"
  reset_env
  d=$(new_dir)
  f="$EXAMPLES/hello.html"

  export PROOF_CAPTURE_BROWSER="$SUITE_TMP/not-a-browser"
  run_tool run page "$f" "$d/o.png"
  want_rc 69 "bad PROOF_CAPTURE_BROWSER"
  want_err_is "proof-capture: PROOF_CAPTURE_BROWSER is not an executable file: $SUITE_TMP/not-a-browser" "bad PROOF_CAPTURE_BROWSER"
  want_absent "$d/o.png" "bad PROOF_CAPTURE_BROWSER wrote an artifact"

  : >"$SUITE_TMP/plain-file"
  export PROOF_CAPTURE_BROWSER="$SUITE_TMP/plain-file"
  run_tool run page "$f" "$d/o.png"
  want_rc 69 "non-executable PROOF_CAPTURE_BROWSER"
  want_err_has "PROOF_CAPTURE_BROWSER is not an executable file" "non-executable PROOF_CAPTURE_BROWSER"

  reset_env
  run_tool run page "$f" "$d/o.png"
  want_rc 69 "candidates seam, only nonexistent entries"
  want_err_is "$MSG_NOBROWSER" "candidates seam, only nonexistent entries"
  want_out_empty "candidates seam, only nonexistent entries"
  want_absent "$d/o.png" "candidates seam wrote an artifact"

  export PROOF_CAPTURE_BROWSER_CANDIDATES="no-such-name-a:no-such-name-b"
  run_tool run page "$f" "$d/o.png"
  want_rc 69 "candidates seam, only nonexistent names"
  want_err_is "$MSG_NOBROWSER" "candidates seam, only nonexistent names"

  reset_env
  RUN_PATH=""
  run_tool run page "$f" "$d/o.png"
  want_rc 69 "empty PATH"
  want_err_is "$MSG_NOBROWSER" "empty PATH, nonexistent candidates, before any external command"
  want_absent "$d/o.png" "empty PATH wrote an artifact"
  unset RUN_PATH

  # control: the same seam holding the stub succeeds, so the 69 above is caused by the missing browser
  stub_env ok "$d/argv"
  unset PROOF_CAPTURE_BROWSER
  export PROOF_CAPTURE_BROWSER_CANDIDATES="$SUITE_TMP/no-such-a:$STUB_BROWSER"
  run_tool run page "$f" "$d/ctl.png"
  want_rc 0 "candidates seam with the stub (control)"
  want_same_file "$d/ctl.png" "$STUB_PNG" "candidates seam with the stub (control)"

  # control on an empty PATH: the dependency check needs no external command
  RUN_PATH=""
  run_tool run page "$f" "$d/ctl2.png"
  unset RUN_PATH
  want_err_has "proof-capture:" "empty PATH with the stub"
  [ "$RC" != 69 ] || note_bad "empty PATH with the stub: reported a missing dependency"

  # discovery: no seam, PATH holds a stub named google-chrome first; no real browser may start
  stub_env ok "$d/argv2"
  unset PROOF_CAPTURE_BROWSER PROOF_CAPTURE_BROWSER_CANDIDATES
  mkdir "$d/bin"
  cp "$STUB_BROWSER" "$d/bin/google-chrome"
  RUN_PATH="$d/bin:/usr/bin:/bin"
  run_tool run page "$f" "$d/disc.png"
  unset RUN_PATH
  want_rc 0 "built-in discovery"
  [ -s "$d/argv2" ] || note_bad "built-in discovery: the PATH stub was not the browser that ran"
  want_same_file "$d/disc.png" "$STUB_PNG" "built-in discovery"

  # PROOF_CAPTURE_BROWSER as a bare name is looked up on PATH, and the file that was checked is the file that runs
  stub_env ok "$d/argv3"
  mkdir "$d/bin2"
  cp "$STUB_BROWSER" "$d/bin2/mybrowser"
  export PROOF_CAPTURE_BROWSER=mybrowser
  RUN_PATH="$d/bin2:/usr/bin:/bin"
  run_tool run page "$f" "$d/bare.png"
  unset RUN_PATH
  want_rc 0 "PROOF_CAPTURE_BROWSER as a bare name"
  [ -s "$d/argv3" ] || note_bad "PROOF_CAPTURE_BROWSER as a bare name: the named browser did not run"
  export PROOF_CAPTURE_BROWSER=no-such-bare-name
  RUN_PATH="$d/bin2:/usr/bin:/bin"
  run_tool run page "$f" "$d/bare2.png"
  unset RUN_PATH
  want_rc 69 "PROOF_CAPTURE_BROWSER as an unknown bare name"
  want_err_is "proof-capture: PROOF_CAPTURE_BROWSER is not an executable file: no-such-bare-name" "unknown bare name"

  want_tool_tmp_clean "case 7"
  end_case
}

# ---- case 8: usage table -------------------------------------------------------------------------
case_8() {
  local d f row_n
  begin_case 8 "usage table"
  reset_env
  d=$(new_dir)
  f="$EXAMPLES/hello.html"
  printf 'KEEP' >"$d/target.png"
  ln -s "$d/target.png" "$d/link.png"
  mkdir "$d/adir" "$d/realdir"
  ln -s "$d/realdir" "$d/linkdir"
  printf 'Output x.gif\n' >"$d/f.tape"

  # row <label> <expected stderr fragment> <args...>: exit 64, that message, no stdout.
  row() {
    local label=$1 frag=$2
    shift 2
    run_tool "$@"
    want_rc 64 "$label"
    want_err_has "$frag" "$label"
    want_out_empty "$label"
  }

  row "no arguments" "usage:"
  row "unknown verb" "unknown verb: frob" frob page a b
  row "run without a kind" "missing kind" run
  row "unknown kind" "unknown kind: shot" run shot "$f" "$d/o.png"
  row "unknown flag" "unknown flag" run page "$f" "$d/o.png" --nope 1
  row "one positional" "needs an input and an output path" run page "$f"
  row "three positionals" "too many arguments" run page "$f" "$d/o.png" "$d/extra.png"
  row "flag without a value" "--width needs a value" run page "$f" "$d/o.png" --width
  row "missing input file" "input file not found" run page "$d/missing.html" "$d/o.png"
  row "javascript scheme" "refusing the scheme 'javascript:'" run page "javascript:alert(1)" "$d/o.png"
  row "chrome scheme" "refusing the scheme 'chrome:'" run page "chrome://settings" "$d/o.png"
  row "data scheme" "refusing the scheme 'data:'" run page "data:text/html,x" "$d/o.png"
  row "input path starting with a dash" "path starting with '-'" run page "-x.html" "$d/o.png"
  row "output path starting with a dash" "path starting with '-'" run page "$f" "-o.png"
  row "wait 0" "--wait must be" run page "$f" "$d/o.png" --wait 0
  row "wait too large" "--wait must be" run page "$f" "$d/o.png" --wait 120001
  row "deadline 0" "--deadline must be" run page "$f" "$d/o.png" --deadline 0
  row "deadline 601" "--deadline must be" run page "$f" "$d/o.png" --deadline 601
  row "width abc" "--width must be" run page "$f" "$d/o.png" --width abc
  row "width 0" "--width must be" run page "$f" "$d/o.png" --width 0
  row "width 10001" "--width must be" run page "$f" "$d/o.png" --width 10001
  row "height abc" "--height must be" run page "$f" "$d/o.png" --height abc
  row "output is a directory" "output path is a directory" run page "$f" "$d/adir"
  row "output ends with a slash" "output path ends with a slash" run page "$f" "$d/newdir/"
  [ ! -e "$d/newdir" ] || note_bad "an output path ending in a slash created a directory"

  export PROOF_CAPTURE_DEADLINE=0
  row "env deadline 0" "PROOF_CAPTURE_DEADLINE must be" run page "$f" "$d/o.png"
  export PROOF_CAPTURE_DEADLINE=601
  row "env deadline 601" "PROOF_CAPTURE_DEADLINE must be" run page "$f" "$d/o.png"
  export PROOF_CAPTURE_DEADLINE=abc
  row "env deadline abc" "PROOF_CAPTURE_DEADLINE must be" run page "$f" "$d/o.png"
  unset PROOF_CAPTURE_DEADLINE

  row "output is a symlink" "refusing a symlink" run page "$f" "$d/link.png"
  [ "$(cat "$d/target.png")" = "KEEP" ] || note_bad "the symlink target was changed"
  row "output directory is a symlink" "refusing a symlink" run page "$f" "$d/linkdir/o.png"
  [ -z "$(ls -A "$d/realdir")" ] || note_bad "something was written through the directory symlink"

  row "tape: missing file" "tape file not found" run tape "$d/missing.tape" "$d/o.gif"
  row "tape: path starting with a dash" "path starting with '-'" run tape "-x.tape" "$d/o.gif"
  row "tape: page-only flag" "applies to run page only" run tape "$d/f.tape" "$d/o.gif" --width 5
  row "tape: deadline 0" "--deadline must be" run tape "$d/f.tape" "$d/o.gif" --deadline 0
  row "tape: output is a symlink" "refusing a symlink" run tape "$d/f.tape" "$d/link.png"

  for row_n in o.png o.gif; do want_absent "$d/$row_n" "a usage row wrote $row_n"; done
  want_tool_tmp_clean "case 8"
  end_case
}

# ---- stub vhs -----------------------------------------------------------------------------------
# Records its argv and pid like the stub browser, takes `-o <path>`, and acts by $STUB_MODE.
cat >"$STUB_DIR/stub-vhs" <<'STUBEOF'
#!/bin/bash
PATH=/usr/bin:/bin:$PATH
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = -o ]; then out=$2; fi
  [ -z "${STUB_ARGV:-}" ] || printf '%s\n' "$1" >>"$STUB_ARGV"
  shift
done
rec() { local l; l=$(ps -o lstart= -p "$1" 2>/dev/null); echo "$1|$(echo $l)" >>"$STUB_PIDS"; }
rec $$
ready() { if [ -n "${STUB_READY:-}" ]; then : >"$STUB_READY"; fi; }
case "${STUB_MODE:-ok}" in
  ok) cp "$STUB_GIF" "$out"; ready; exit 0 ;;
  exit-no-file) ready; exit 0 ;;
  bad-file) echo "not a gif" >"$out"; ready; exit 0 ;;
  exit-nonzero) cp "$STUB_GIF" "$out"; ready; exit 3 ;;
  hang) ready; exec sleep 20 ;;
  term-ignore)
    trap '' TERM
    ( trap '' TERM; exec sleep 20 ) &
    rec $!
    ready
    exec sleep 20 ;;
esac
exit 3
STUBEOF
chmod +x "$STUB_DIR/stub-vhs"
STUB_VHS="$STUB_DIR/stub-vhs"

# The smallest GIF: header, one pixel, trailer byte 3b.
STUB_GIF="$STUB_DIR/stub.gif"
gif_hex="47494638396101000100800000ffffff00000021f90401000000002c00000000010001000002024401003b"
: >"$STUB_GIF"
i=0
while [ "$i" -lt "${#gif_hex}" ]; do
  printf "\\x${gif_hex:$i:2}" >>"$STUB_GIF"
  i=$((i + 2))
done
export STUB_GIF

# stub_vhs_env <mode> <argv file>
stub_vhs_env() {
  reset_env
  reset_pids
  export PROOF_CAPTURE_VHS="$STUB_VHS"
  export STUB_MODE="$1" STUB_ARGV="$2"
  : >"$2"
}

# ---- case 9: the tape lane ----------------------------------------------------------------------
case_9() {
  local d t0 last
  begin_case 9 "tape"
  d=$(new_dir)
  printf 'Sleep 1s\n' >"$d/x.tape"

  # a relative tape path reaches vhs as an absolute path, with -o <partial under the private TMPDIR>
  stub_vhs_env ok "$d/argv"
  cd "$d" || note_bad "cd failed"
  run_tool run tape ./x.tape "$d/o.gif"
  cd "$HERE" || note_bad "cd back failed"
  want_rc 0 "ok"
  want_same_file "$d/o.gif" "$STUB_GIF" "ok"
  [ "$(cat "$OUTF")" = "proof-capture: wrote $d/o.gif ($(wc -c <"$STUB_GIF" | tr -d ' ') bytes)" ] || note_bad "ok: the stdout line is wrong"
  [ "$(sed -n 1p "$d/argv")" = "-o" ] || note_bad "ok: vhs did not get -o first"
  case "$(sed -n 2p "$d/argv")" in "$TOOL_TMP"/proof-capture.*/partial.gif) ;; *) note_bad "ok: the partial is not in the private work dir" ;; esac
  [ "$(sed -n 3p "$d/argv")" = "$d/x.tape" ] || note_bad "ok: the tape path is not absolute"
  want_tool_tmp_clean "ok"
  want_no_hidden_left "$d" "ok"

  stub_vhs_env exit-no-file "$d/argv"
  run_tool run tape "$d/x.tape" "$d/a.gif"
  want_rc 1 "exit-no-file"
  want_absent "$d/a.gif" "exit-no-file wrote an artifact"

  stub_vhs_env bad-file "$d/argv"
  run_tool run tape "$d/x.tape" "$d/b.gif"
  want_rc 1 "bad-file"
  want_absent "$d/b.gif" "bad-file wrote an artifact"

  stub_vhs_env exit-nonzero "$d/argv"
  run_tool run tape "$d/x.tape" "$d/c.gif"
  want_rc 1 "non-zero exit with a valid file"
  want_err_has "vhs exited with status 3" "non-zero exit"
  want_absent "$d/c.gif" "non-zero exit wrote an artifact"

  reset_env
  export PROOF_CAPTURE_VHS="$SUITE_TMP/not-vhs"
  run_tool run tape "$d/x.tape" "$d/e.gif"
  want_rc 69 "bad PROOF_CAPTURE_VHS"
  want_err_is "proof-capture: PROOF_CAPTURE_VHS is not an executable file: $SUITE_TMP/not-vhs" "bad PROOF_CAPTURE_VHS"

  reset_env
  RUN_PATH=""
  run_tool run tape "$d/x.tape" "$d/f.gif"
  unset RUN_PATH
  want_rc 69 "no vhs on an empty PATH"
  want_err_is "proof-capture: vhs not found; install it (brew install vhs) or set PROOF_CAPTURE_VHS=<path>" "no vhs on an empty PATH"

  # control: a stub named vhs on PATH is found by name, so the 69 above is caused by the missing vhs
  stub_vhs_env ok "$d/argv2"
  unset PROOF_CAPTURE_VHS
  mkdir "$d/vbin"
  cp "$STUB_VHS" "$d/vbin/vhs"
  RUN_PATH="$d/vbin:/usr/bin:/bin"
  run_tool run tape "$d/x.tape" "$d/g.gif"
  unset RUN_PATH
  want_rc 0 "vhs found by name (control)"
  want_same_file "$d/g.gif" "$STUB_GIF" "vhs found by name (control)"

  stub_vhs_env hang "$d/argv"
  t0=$SECONDS
  run_tool run tape "$d/x.tape" "$d/h.gif" --deadline 2
  want_rc 1 "hang"
  want_err_is "proof-capture: no valid artifact within 2s" "hang"
  want_gone_by "hang" "$t0" 17
  want_tool_tmp_clean "hang"

  stub_vhs_env term-ignore "$d/argv"
  t0=$SECONDS
  run_tool run tape "$d/x.tape" "$d/i.gif" --deadline 2
  want_rc 1 "term-ignore"
  want_gone_by "term-ignore at the deadline" "$t0" 17
  want_tool_tmp_clean "term-ignore"

  stub_vhs_env hang "$d/argv"
  export STUB_READY="$d/ready"
  t0=$SECONDS
  start_tool run tape "$d/x.tape" "$d/j.gif"
  if wait_ready "$d/ready"; then
    tool_alive && kill -s TERM "$TOOL_PID"
  else
    note_bad "the stub never became ready"
    tool_alive && kill -TERM "$TOOL_PID" 2>/dev/null
  fi
  wait_tool 15
  want_rc 1 "TERM mid-run"
  want_err_is "proof-capture: interrupted" "TERM mid-run"
  want_gone_by "TERM mid-run" "$t0" 17
  want_tool_tmp_clean "TERM mid-run"
  want_absent "$d/j.gif" "TERM mid-run wrote an artifact"

  reset_env
  run_tool run tape "-x.tape" "$d/k.gif"
  want_rc 64 "tape path starting with a dash"
  end_case
}

# ---- case 10: the standalone lint ----------------------------------------------------------------
# lint_file <file>: succeeds when the non-comment lines hold none of the forbidden tokens (a kit path or kit
# config, a climb out of the module, a name-based kill, the live desktop, a process-table listing).
lint_file() {
  grep -v '^[[:space:]]*#' "$1" | grep -qE 'DWARVES_KIT|kit-config|\.\./\.\./|pkill|killall|pgrep|osascript|screencapture|ps -A' && return 1
  return 0
}

case_10() {
  local d bad_a bad_b bad_c
  begin_case 10 "standalone lint"
  d=$(new_dir)
  lint_file "$ENTRY" || note_bad "the module executable holds a forbidden token"

  # the lint must be able to fail: plant each violation in a copy
  bad_a="$d/kit-dependency"
  cp "$ENTRY" "$bad_a"
  printf 'source ../../config/kit-config.sh\n' >>"$bad_a"
  if lint_file "$bad_a"; then note_bad "the lint missed a planted kit dependency"; fi
  bad_b="$d/name-kill"
  cp "$ENTRY" "$bad_b"
  printf 'pkill -f chrome\n' >>"$bad_b"
  if lint_file "$bad_b"; then note_bad "the lint missed a planted name-based kill"; fi
  bad_c="$d/commented"
  cp "$ENTRY" "$bad_c"
  printf '# pkill -f chrome in a comment is fine\n' >>"$bad_c"
  lint_file "$bad_c" || note_bad "the lint flagged a comment line"
  end_case
}

# ---- case 11: real browser (opt-in) -------------------------------------------------------------
# Runs only with PROOF_CAPTURE_REAL=1. A wrapper records its pid and execs the real browser, so the recorded pid is
# the process group id; after the run the group must be empty. The browser is PROOF_CAPTURE_REAL_BROWSER, else the
# first of the usual Chromium-family names or macOS app paths.
case_11() {
  local d real name wh w h gone
  if [ "${PROOF_CAPTURE_REAL:-}" != 1 ]; then
    skip_case 11 "real browser (set PROOF_CAPTURE_REAL=1)"
    return 0
  fi
  begin_case 11 "real browser"
  reset_env
  reset_pids
  real="${PROOF_CAPTURE_REAL_BROWSER:-}"
  if [ -z "$real" ]; then
    for name in google-chrome chromium chromium-browser microsoft-edge; do
      real=$(command -v "$name" 2>/dev/null) && break
      real=""
    done
  fi
  if [ -z "$real" ]; then
    for name in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Chromium.app/Contents/MacOS/Chromium" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
      if [ -x "$name" ]; then real=$name; break; fi
    done
  fi
  if [ -z "$real" ]; then
    note_bad "PROOF_CAPTURE_REAL=1 but no Chromium-family browser was found"
    end_case
    return 0
  fi
  d=$(new_dir)
  printf '#!/bin/bash\nl=$(ps -o lstart= -p $$ 2>/dev/null)\necho "$$|$(echo $l)" >>"$STUB_PIDS"\nexec "$REAL_BROWSER" "$@"\n' >"$d/wrapper"
  chmod +x "$d/wrapper"
  export REAL_BROWSER="$real"
  export PROOF_CAPTURE_BROWSER="$d/wrapper"
  start_tool run page "$EXAMPLES/hello.html" "$d/real.png" --width 800 --height 500
  wait_tool 90
  want_rc 0 "real browser"
  want_err_is "" "real browser stderr"
  if artifact_dims=$(od -An -tu1 -j16 -N8 "$d/real.png" 2>/dev/null); then
    set -- $artifact_dims
    w=$(( $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 ))
    h=$(( $5 * 16777216 + $6 * 65536 + $7 * 256 + $8 ))
    [ "$w" = 800 ] && [ "$h" = 500 ] || note_bad "the PNG is $w by $h, wanted 800 by 500"
  else
    note_bad "cannot read the PNG header"
  fi
  want_tool_tmp_clean "real browser"
  gone=0
  while read -r wh; do
    wh=${wh%%|*}
    case "$wh" in ''|*[!0-9]*) continue ;; esac
    if [ -n "$(pgrep -g "$wh" 2>/dev/null)" ]; then gone=1; fi
  done <"$STUB_PIDS"
  [ "$gone" = 0 ] || note_bad "a process of the recorded group is still alive"
  unset REAL_BROWSER
  end_case
}

# ---- helpers for the cases below ------------------------------------------------------------------
# make_copy <dest> <before|after> <anchor ERE> <line>: a copy of the tool with <line> placed next to the one line
# the anchor matches (exactly one match is required). It simulates a signal or a second writer landing at one exact
# point of the run, which a stub cannot time. The anchors use [$] and no backslash, so awk takes them as written.
make_copy() {
  awk -v where="$2" -v a="$3" -v l="$4" '
    $0 ~ a { c++; if (where == "before") print l }
    { print }
    $0 ~ a { if (where == "after") print l }
    END { exit (c == 1 ? 0 : 3) }' "$ENTRY" >"$1" || { note_bad "injection anchor not found exactly once: $3"; return 1; }
  chmod +x "$1"
}

# drop_work_dirs: remove the work dirs a killed tool leaves under the private TMPDIR (the documented residual).
drop_work_dirs() {
  local w
  for w in "$TOOL_TMP"/proof-capture.*; do
    [ -d "$w" ] || continue
    case "$w" in "$TOOL_TMP"/proof-capture.*) rm -rf "$w" ;; esac
  done
}

# fake_ps <dir>: a process lister that can wait for a marker or sleep, report a fixed pgid or ppid, and otherwise
# runs the real one.
fake_ps() {
  mkdir -p "$1"
  cat >"$1/ps" <<'PSEOF'
#!/bin/bash
[ -z "${PS_MARK:-}" ] || : >"$PS_MARK"
n=0
while [ -n "${PS_WAIT_FILE:-}" ] && [ ! -e "$PS_WAIT_FILE" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
sleep "${PS_SLEEP:-0}"
PATH=/usr/bin:/bin
case "$*" in
  *pgid=*) if [ -n "${PS_FAKE_PGID:-}" ]; then echo "$PS_FAKE_PGID"; exit 0; fi ;;
  *ppid=*) if [ -n "${PS_FAKE_PPID:-}" ]; then echo "$PS_FAKE_PPID"; exit 0; fi ;;
esac
exec ps "$@"
PSEOF
  chmod +x "$1/ps"
}

# ---- case 14: the other signals ------------------------------------------------------------------
case_14() {
  local sig
  begin_case 14 "QUIT, USR1, USR2, ALRM and PIPE to the tool"
  for sig in QUIT USR1 USR2 ALRM PIPE; do
    signal_row never-write "$sig"
  done
  end_case
}

# ---- case 15: the launch window, a slow ps, and the no-own-group branch -----------------------------
case_15() {
  local d copy t0
  begin_case 15 "launch window, slow ps, no own group"
  d=$(new_dir)

  # a signal after the launch and before "CPID=$!": the tool must still end the child it just started
  copy="$d/tool-window"
  if make_copy "$copy" before '^    CPID=[$]!$' '    n=0; while [ ! -e "${STUB_READY:-/nonexistent}" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done; kill -TERM $$'; then
    stub_env never-write "$d/argv"
    export STUB_READY="$d/ready"
    t0=$SECONDS
    ENTRY_USE="$copy" start_tool run page "$EXAMPLES/hello.html" "$d/w.png"
    wait_tool 20
    [ "$TIMED_OUT" = 0 ] || note_bad "window: the tool did not exit"
    want_rc 1 "window"
    want_err_is "proof-capture: interrupted" "window"
    want_gone_by "a signal between the launch and CPID" "$t0" 17
    want_tool_tmp_clean "window"
  fi

  # a KILL to the tool while the ps check is slow: the watchdog must already be running
  fake_ps "$d/psbin"
  stub_env never-write "$d/argv2"
  export STUB_READY="$d/ready2" PS_MARK="$d/psmark" PS_SLEEP=6
  t0=$SECONDS
  RUN_PATH="$d/psbin:/usr/bin:/bin" start_tool run page "$EXAMPLES/hello.html" "$d/k.png" --deadline 2
  wait_ready "$d/psmark" || note_bad "slow ps: the tool never reached the ps check"
  wait_ready "$d/ready2" || note_bad "slow ps: the stub never became ready"
  { tool_alive && kill -KILL "$TOOL_PID"; wait_tool 10; } 2>/dev/null
  [ "$(pids_alive)" -ge 1 ] || note_bad "slow ps: the stub was already gone right after the KILL, so the check would prove nothing"
  want_gone_by "KILL during a slow ps check" "$t0" 17
  drop_work_dirs
  unset PS_MARK PS_SLEEP

  # no own group (the lister reports another pgid): the one pid is ended while it is still this tool's child ...
  stub_env never-write "$d/argv3"
  export STUB_READY="$d/ready3" PS_FAKE_PGID=12345 PS_WAIT_FILE="$d/ready3"
  RUN_PATH="$d/psbin:/usr/bin:/bin" start_tool run page "$EXAMPLES/hello.html" "$d/n.png"
  wait_tool 20
  want_rc 1 "no own group"
  want_err_is "proof-capture: cannot isolate the browser process group" "no own group"
  want_pids_gone "no own group, the child of the tool" 10
  want_tool_tmp_clean "no own group"

  # ... and left alone when the pid is not its child (a reused pid)
  stub_env never-write "$d/argv4"
  export STUB_READY="$d/ready4" PS_WAIT_FILE="$d/ready4" PS_FAKE_PPID=1
  RUN_PATH="$d/psbin:/usr/bin:/bin" start_tool run page "$EXAMPLES/hello.html" "$d/n2.png"
  wait_tool 20
  want_rc 1 "no own group, not its child"
  [ "$(pids_alive)" -ge 1 ] || note_bad "no own group: a pid that was not the tool's child was signalled"
  reset_pids
  unset PS_FAKE_PGID PS_FAKE_PPID PS_WAIT_FILE STUB_READY
  want_tool_tmp_clean "case 15"
  end_case
}

# ---- case 16: the output path checked again before each write ----------------------------------------
case_16() {
  local d copy
  begin_case 16 "output path rechecked before it is written"
  d=$(new_dir)

  # <outdir> becomes a symlink while the browser runs (the browser stub plays the second writer)
  mkdir "$d/od" "$d/elsewhere"
  # The copy of the tool marks the point after the temp file would have been made: it must not be reached.
  copy="$d/tool-mktemp"
  if make_copy "$copy" after '^  FINAL_TMP=[$][(]mktemp' '  : >"$STUB_SEEN"'; then
    stub_env swap-outdir "$d/argv"
    export STUB_SWAP_DIR="$d/od" STUB_SWAP_TO="$d/elsewhere" STUB_SEEN="$d/seen"
    ENTRY_USE="$copy" run_tool run page "$EXAMPLES/hello.html" "$d/od/o.png"
    want_rc 1 "outdir swapped"
    want_err_has "refusing a symlink" "outdir swapped"
    [ -z "$(ls -A "$d/elsewhere")" ] || note_bad "outdir swapped: something was written through the symlink"
    [ ! -e "$d/seen" ] || note_bad "outdir swapped: the temp file was made through the symlink"
    want_tool_tmp_clean "outdir swapped"
    unset STUB_SWAP_DIR STUB_SWAP_TO STUB_SEEN
  fi

  # <out> becomes a symlink to a directory between the copy and the rename
  mkdir "$d/od2" "$d/elsewhere2"
  copy="$d/tool-swap"
  if make_copy "$copy" after '^  cp "[$]PARTIAL" "[$]FINAL_TMP"' '  ln -s "$STUB_SWAP_TO" "$OUT"'; then
    stub_env ok "$d/argv2"
    export STUB_SWAP_TO="$d/elsewhere2"
    ENTRY_USE="$copy" run_tool run page "$EXAMPLES/hello.html" "$d/od2/o.png"
    want_rc 1 "out swapped"
    want_err_has "refusing a symlink" "out swapped"
    [ -z "$(ls -A "$d/elsewhere2")" ] || note_bad "out swapped: something was written through the symlink"
    want_no_hidden_left "$d/od2" "out swapped"
    want_tool_tmp_clean "out swapped"
    unset STUB_SWAP_TO
  fi

  # a signal after the rename cannot undo the write: the run finishes and reports success
  copy="$d/tool-late"
  if make_copy "$copy" before '^  n=[$][(]file_size "[$]OUT"[)]$' '  kill -TERM $$'; then
    stub_env ok "$d/argv3"
    ENTRY_USE="$copy" run_tool run page "$EXAMPLES/hello.html" "$d/late.png"
    want_rc 0 "signal after the rename"
    want_same_file "$d/late.png" "$STUB_PNG" "signal after the rename"
    want_err_is "" "signal after the rename"
    want_tool_tmp_clean "signal after the rename"
  fi
  end_case
}

# ---- case 17: a closed stderr must not stop the cleanup -----------------------------------------------
case_17() {
  local d t0 rc
  begin_case 17 "stderr is a closed pipe"
  d=$(new_dir)
  stub_env never-write "$d/argv"
  export STUB_READY="$d/ready"
  t0=$SECONDS
  : >"$OUTF"
  {
    set -m
    ( "$BASH" "$ENTRY" run page "$EXAMPLES/hello.html" "$d/p.png" --deadline 2 </dev/null 2>&1 >"$OUTF" | true
      echo "${PIPESTATUS[0]}" >"$d/rc" ) &
    TOOL_PID=$!
    set +m
  } 2>/dev/null
  wait_tool 25
  [ "$TIMED_OUT" = 0 ] || note_bad "the tool did not exit"
  rc=$(cat "$d/rc" 2>/dev/null)
  [ "$rc" = 1 ] || note_bad "exit $rc, wanted 1"
  want_gone_by "closed stderr" "$t0" 17
  want_tool_tmp_clean "closed stderr"
  want_absent "$d/p.png" "closed stderr wrote an artifact"
  end_case
}

# ---- case 18: the suite signals only pids it can prove are its own --------------------------------------
case_18() {
  local decoy proven
  begin_case 18 "the suite never signals a pid it cannot prove"
  reset_pids
  sleep 8 &
  decoy=$!
  records_valid || note_bad "an empty record list was called malformed"
  printf 'not-a-record\n' >>"$STUB_PIDS"
  if records_valid; then note_bad "a malformed record was accepted"; fi
  : >"$STUB_PIDS"
  # a pid with no start time, and a pid with a start time that is not the process's: neither may be signalled
  printf '%s|\n%s|Mon Jan 1 00:00:00 2001\n' "$decoy" "$decoy" >>"$STUB_PIDS"
  records_valid || note_bad "well-formed records were called malformed"
  # no start time: cannot tell, so alive; a different start time: provably another process, so gone
  [ "$(pids_alive)" = 1 ] || note_bad "pids_alive: wanted 1 (the record with no start time), got $(pids_alive)"
  reset_pids
  kill -0 "$decoy" 2>/dev/null || note_bad "reset_pids signalled a pid it had no proof for"
  printf '%s|\n' "$decoy" >>"$STUB_PIDS"
  kill_owned
  kill -0 "$decoy" 2>/dev/null || note_bad "kill_owned signalled a pid it had no proof for"
  : >"$STUB_PIDS"
  # the control: a record with the right start time is signalled
  sleep 8 &
  proven=$!
  printf '%s|%s\n' "$proven" "$(lstart_of "$proven")" >>"$STUB_PIDS"
  kill_owned
  { wait "$proven"; } 2>/dev/null
  if kill -0 "$proven" 2>/dev/null; then note_bad "a pid with proof was not signalled (the helper does nothing)"; fi
  : >"$STUB_PIDS"
  kill "$decoy" 2>/dev/null
  { wait "$decoy"; } 2>/dev/null
  end_case
}

# ---- main ---------------------------------------------------------------------------------------
# SUITE_CASES="1 5" runs only those cases (a debugging and negative-control aid); unset runs all.
run_case() {
  case " ${SUITE_CASES:-$1} " in *" $1 "*) "$2" ;; esac
}
run_case 1 case_1
run_case 2 case_2
run_case 3 case_3
run_case 4 case_4
run_case 5 case_5
run_case 6 case_6
run_case 7 case_7
run_case 8 case_8
run_case 9 case_9
run_case 10 case_10
run_case 11 case_11
run_case 12 case_12
run_case 13 case_13
run_case 14 case_14
run_case 15 case_15
run_case 16 case_16
run_case 17 case_17
run_case 18 case_18

echo "$NPASS passed, $NFAIL failed, $NSKIP skipped"
[ "$NFAIL" = 0 ]
