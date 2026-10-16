#!/usr/bin/env bash
# test-hook-util.sh -- lib/reflect/hook-util.sh: the helpers the bash staging hooks share. The
# Linux cases run on any host by putting a stat shim on the PATH that answers like GNU stat.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/reflect/hook-util.sh
source "$KIT_DIR/lib/reflect/hook-util.sh"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL $1: want '$3' got '$2'"; fi; }
T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1

# hu_int
check "hu_int plain" "$(hu_int 42 x)" 42
check "hu_int padded and signed" "$(hu_int ' +7 ' x)/$(hu_int '-5' x)" "7/-5"
check "hu_int not a number is the default" "$(hu_int abc 9)/$(hu_int '3.5' 9)/$(hu_int '' 9)" "9/9/9"
check "hu_int clamps a huge run of digits" "$(hu_int 99999999999999999999999 x)" 999999999999999999
check "hu_int leading zeros are decimal" "$(hu_int 010 x)" 10

# hu_join
check "hu_join plain" "$(hu_join /a/b c/d)" "/a/b/c/d"
check "hu_join does not double a trailing slash" "$(hu_join /a/b/ c)" "/a/b/c"
check "hu_join of the root" "$(hu_join / c)" "/c"

# hu_mtime, on this host and on a host whose stat answers like GNU stat
: > "$T/f"; touch -t 202001020304.05 "$T/f"
want=$(date -r "$T/f" +%s 2>/dev/null || date -d "@$(stat -c %Y "$T/f")" +%s)
check "hu_mtime native" "$(hu_mtime "$T/f")" "$want"
mkdir -p "$T/gnu"
real_stat=$(command -v stat)
cat > "$T/gnu/stat" <<EOS
#!/bin/sh
# answers like GNU stat: -c %Y is the mtime; -f is a filesystem query that prints lines and exits 1
if [ "\$1" = "-c" ] && [ "\$2" = "%Y" ]; then exec "$real_stat" -f %m "\$3" 2>/dev/null || exec "$real_stat" -c %Y "\$3"; fi
printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2\n' "\$3"; exit 1
EOS
chmod +x "$T/gnu/stat"
check "hu_mtime under a GNU-style stat" "$(PATH="$T/gnu:$PATH" hu_mtime "$T/f")" "$want"
check "hu_mtime of a missing file fails" "$(hu_mtime "$T/none" && echo ok || echo fail)" "fail"

# hu_throttled
check "hu_throttled first call stamps and does not throttle" "$(hu_throttled "$T/st" last 3600 && echo throttled || echo run)/$([ -f "$T/st/last" ] && echo stamp)" "run/stamp"
check "hu_throttled fresh stamp throttles" "$(hu_throttled "$T/st" last 3600 && echo throttled || echo run)" "throttled"
touch -t 202001020304.05 "$T/st/last"
check "hu_throttled old stamp runs" "$(hu_throttled "$T/st" last 3600 && echo throttled || echo run)" "run"
check "hu_throttled under a GNU-style stat still throttles" "$(PATH="$T/gnu:$PATH" hu_throttled "$T/st" last 3600 && echo throttled || echo run)" "throttled"
check "hu_throttled interval zero never throttles" "$(hu_throttled "$T/st" last 0 && echo throttled || echo run)" "run"
check "hu_throttled negative interval never throttles" "$(hu_throttled "$T/st" last -5 && echo throttled || echo run)" "run"
: > "$T/afile"
check "hu_throttled a state dir that cannot be made never throttles" "$(hu_throttled "$T/afile/x" last 3600 && echo throttled || echo run)" "run"

# hu_run_capture
hu_run_capture 5 "$T/out1" sh -c 'echo hello'; rc=$?
check "hu_run_capture returns the output and status" "$(cat "$T/out1")/$rc" "hello/0"
hu_run_capture 5 "$T/out2" sh -c 'exit 3'; rc=$?
check "hu_run_capture returns a non-zero status" "$rc" 3
start=$(date +%s); hu_run_capture 1 "$T/out3" sh -c 'sleep 5; echo late'; rc=$?; took=$(( $(date +%s) - start ))
check "hu_run_capture kills a command that overruns" "$([ "$rc" -ne 0 ] && [ "$took" -lt 4 ] && [ ! -s "$T/out3" ] && echo killed)" killed
check "hu_run_capture marks a timed-out run" "$([ -e "$T/out3.timedout" ] && echo marked)" marked
hu_run_capture 5 "$T/out3b" sh -c 'echo ok'
check "hu_run_capture leaves no mark on a run that finished" "$([ -e "$T/out3b.timedout" ] && echo marked || echo clean)" clean
hu_run_capture 1 "$T/out3c" sh -c 'echo partial; sleep 4'
check "hu_run_capture keeps partial output on disk for the caller to discard" "$(cat "$T/out3c")/$([ -e "$T/out3c.timedout" ] && echo marked)" "partial/marked"
HU_STDIN="$T/in" ; printf 'from stdin' > "$T/in"
hu_run_capture 5 "$T/out4" cat; unset HU_STDIN
check "hu_run_capture feeds HU_STDIN to the command" "$(cat "$T/out4")" "from stdin"
before=$(pgrep -f "sleep 7" 2>/dev/null | wc -l | tr -d ' ')
hu_run_capture 7 "$T/out5" true
sleep 0.3; after=$(pgrep -f "sleep 7" 2>/dev/null | wc -l | tr -d ' ')
check "hu_run_capture leaves no watchdog sleep behind" "$after" "$before"
took=$( ( trap '' TERM; start=$(date +%s); hu_run_capture 8 "$T/out6" true; echo $(( $(date +%s) - start )) ) )
check "hu_run_capture returns at once when the caller ignores TERM" "$([ "$took" -lt 4 ] && echo prompt)" prompt

# hu_utf8_ok
printf '{"a":"é"}' > "$T/ok.json"; printf '\xef\xbb\xbf{}' > "$T/bom.json"; printf 'bad \xff byte' > "$T/bad.json"
check "hu_utf8_ok accepts UTF-8" "$(hu_utf8_ok "$T/ok.json" && echo ok || echo no)" ok
check "hu_utf8_ok rejects a BOM" "$(hu_utf8_ok "$T/bom.json" && echo ok || echo no)" no
check "hu_utf8_ok rejects invalid UTF-8" "$(hu_utf8_ok "$T/bad.json" && echo ok || echo no)" no

echo "hook-util: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
