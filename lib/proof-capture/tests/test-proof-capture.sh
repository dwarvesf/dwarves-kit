#!/usr/bin/env bash
# Suite for the proof-capture module. Standalone: sources nothing from the kit.
# Prints one line per case (PASS, FAIL or SKIP) and a recap; exit 0 when nothing failed.
# Every case runs the tool through a stub browser or stub vhs, never a real one (case 11 is opt-in).
# The tool gets a private TMPDIR, so "nothing left behind" is an exact assertion.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRY="$HERE/../bin/proof-capture"
EXAMPLES="$HERE/../examples"

SUITE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pcsuite.XXXXXX") || { echo "cannot make a temp dir" >&2; exit 1; }
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

# ---- main ---------------------------------------------------------------------------------------
case_7
case_8

echo "$NPASS passed, $NFAIL failed, $NSKIP skipped"
[ "$NFAIL" = 0 ]
