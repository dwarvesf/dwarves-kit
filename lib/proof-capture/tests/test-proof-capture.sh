#!/usr/bin/env bash
# Suite for the proof-capture module. Standalone: sources nothing from the kit.
# Prints one line per case (PASS, FAIL or SKIP) and a recap; exit 0 when nothing failed.
# Every case runs the tool through a stub browser or stub vhs, never a real one (case 11 is opt-in).
# The tool gets a private TMPDIR, so "nothing left behind" is an exact assertion.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRY="$HERE/../bin/proof-capture"
EXAMPLES="$HERE/../examples"

BASE_TMP=${TMPDIR:-/tmp}
BASE_TMP=${BASE_TMP%/}
SUITE_TMP=$(mktemp -d "$BASE_TMP/pcsuite.XXXXXX") || { echo "cannot make a temp dir" >&2; exit 1; }
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
  local p
  if [ -n "$TOOL_PID" ] && kill -0 "$TOOL_PID" 2>/dev/null; then kill -TERM "$TOOL_PID" 2>/dev/null; fi
  if [ -f "$STUB_PIDS" ]; then
    while read -r p; do
      case "$p" in ''|*[!0-9]*) continue ;; esac
      kill -KILL "$p" 2>/dev/null
    done <"$STUB_PIDS"
  fi
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
    PATH="${RUN_PATH-$PATH}" "$BASH" "$ENTRY" "$@" </dev/null >"$OUTF" 2>"$ERRF" &
    TOOL_PID=$!
    set +m
  } 2>/dev/null
}

# wait_tool [limit]: waits for the tool by pid, under a guard (default 30 s) that kills only that pid.
wait_tool() {
  local end=$((SECONDS + ${1:-30}))
  TIMED_OUT=0
  while kill -0 "$TOOL_PID" 2>/dev/null; do
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
  unset PROOF_CAPTURE_BROWSER PROOF_CAPTURE_VHS PROOF_CAPTURE_DEADLINE RUN_PATH
  export PROOF_CAPTURE_BROWSER_CANDIDATES="$SUITE_TMP/no-such-a:$SUITE_TMP/no-such-b"
}

new_dir() { local d; d=$(mktemp -d "$SUITE_TMP/d.XXXXXX"); echo "$d"; }

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
echo $$ >>"$STUB_PIDS"
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
    echo $! >>"$STUB_PIDS"
    ready
    exec sleep 20 ;;
  never-write) ready; exec sleep 20 ;;
  term-ignore)
    trap '' TERM
    ( trap '' TERM; exec sleep 20 ) &
    echo $! >>"$STUB_PIDS"
    ready
    exec sleep 20 ;;
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

reset_pids() {
  local p
  while read -r p; do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    kill -KILL "$p" 2>/dev/null
  done <"$STUB_PIDS"
  : >"$STUB_PIDS"
}

pids_alive() {
  local p n=0
  while read -r p; do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    if kill -0 "$p" 2>/dev/null; then n=$((n + 1)); fi
  done <"$STUB_PIDS"
  echo "$n"
}

# want_pids_gone <label> [bound]: at least one pid was recorded, and every one is gone within the bound.
want_pids_gone() {
  local end=$((SECONDS + ${2:-15}))
  [ -s "$STUB_PIDS" ] || { note_bad "$1: the stub recorded no pid (the check would be empty)"; return 0; }
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

# ---- case 5: deadline -----------------------------------------------------------------------------
case_5() {
  local d
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
  printf '#!/bin/bash\necho $$ >>"$STUB_PIDS"\nexec "$REAL_BROWSER" "$@"\n' >"$d/wrapper"
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
    case "$wh" in ''|*[!0-9]*) continue ;; esac
    if [ -n "$(pgrep -g "$wh" 2>/dev/null)" ]; then gone=1; fi
  done <"$STUB_PIDS"
  [ "$gone" = 0 ] || note_bad "a process of the recorded group is still alive"
  unset REAL_BROWSER
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
run_case 5 case_5
run_case 7 case_7
run_case 8 case_8
run_case 11 case_11

echo "$NPASS passed, $NFAIL failed, $NSKIP skipped"
[ "$NFAIL" = 0 ]
