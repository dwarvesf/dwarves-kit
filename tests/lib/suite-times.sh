#!/usr/bin/env bash
# suite-times.sh -- the per-host history of how long each test suite and each test run takes.
#
# Every tests/run-all.sh run and every bin/test-affected run appends one line per suite that
# ran, plus one run line, to a log OUTSIDE the repo, so a timeout can be re-tuned and a wall
# target measured from stored numbers instead of a fresh full run. Reach the read verbs through
# the runner: `bash tests/run-all.sh --times <verb>`.
#
#   suite-times.sh append <tsv> [<sha> <load1>]  append the run's suite lines (suite secs exit per
#                                                 line of <tsv>), then trim to the cap
#   suite-times.sh append-run <entry> <selected> <wall> <exit> [<sha> <load1>]
#                                                 append one run line for an entry point
#   suite-times.sh p95 [<suite>]                 per-suite runs and p95 seconds, slowest first
#   suite-times.sh runs                          the last 20 run lines, then p50 and p95 wall
#                                                 per entry point over those lines
#   suite-times.sh expected [<jobs>]             expected wall seconds of a full run, from the
#                                                 suite names on stdin (median each, jobs wide)
#   suite-times.sh tune [--write] [--allow-lower]
#                                                the timeouts file by D4's rule; prints it,
#                                                --write rewrites it
#
# Log line (TSV): UTC time, git sha, suite, seconds, exit, 1-min load. A run line has the suite
# field `run:<entry>` (run-all or test-affected), the total wall seconds, the run's exit, and two
# more fields: `kind=run` and `selected=<N>`. Run lines never count as suites.
#
# What tune does with a suite, in order (a suite whose timeouts line carries a `#` comment is
# hand-set and kept as is):
#   - candidate = max(60, 2 x p95 of the exit-0 runs), used only with at least 5 such samples;
#   - the candidate replaces an existing line only when it is not lower, unless --allow-lower;
#   - an exit-124 row (a kill) is a lower bound on p95: the limit ends up at least twice the seconds it was
#     killed at, with or without enough samples.
# A missing, empty or unreadable log is not an error: read verbs say so on stderr and exit 0,
# and `tune` leaves the timeouts file untouched. Every failure to WRITE the log is swallowed
# (exit 0), so recording a timing can never change a test run's exit code.
# Env: KIT_SUITE_TIMES_FILE  the log (default ${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv)
#      KIT_SUITE_TIMES_CAP   lines kept (default 20000; non-numeric falls back to it)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$DIR/../.." && pwd)"
TIMEOUTS="${SUITE_TIMES_TIMEOUTS:-$KIT_DIR/bin/test-affected.timeouts}"
TAB="$(printf '\t')"
MIN_SAMPLES=5

log_file() { printf '%s' "${KIT_SUITE_TIMES_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv}"; }

cap() {
  local c="${KIT_SUITE_TIMES_CAP:-20000}"
  case "$c" in ''|*[!0-9]*|0) c=20000 ;; esac
  printf '%s' "$c"
}

load1() {
  local l
  l="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
  [ -n "$l" ] || l="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
  printf '%s' "${l:-0}"
}

# True when the log exists and holds at least one line.
have_log() { [ -s "$(log_file)" ]; }
no_log() { echo "suite-times: no history at $(log_file); run tests/run-all.sh to start one" >&2; }

# Append stdin to the log, then trim to the cap. Any failure returns 0.
write_lines() {
  local f c tmp
  f="$(log_file)"; c="$(cap)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  cat >>"$f" 2>/dev/null || return 0
  if [ "$(wc -l <"$f" 2>/dev/null | tr -d ' ')" -gt "$c" ] 2>/dev/null; then
    tmp="$f.trim.$$"
    if tail -n "$c" "$f" >"$tmp" 2>/dev/null; then mv -f "$tmp" "$f" 2>/dev/null || command rm -f "$tmp" 2>/dev/null; fi
  fi
  return 0
}

default_sha() { git -C "$KIT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown; }

do_append() {
  local tsv="${1:-}" sha="${2:-}" load="${3:-}" now
  [ -r "$tsv" ] || return 0
  [ -n "$sha" ] || sha="$(default_sha)"
  [ -n "$load" ] || load="$(load1)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  awk -F'\t' -v t="$now" -v s="$sha" -v l="$load" 'NF >= 3 { printf "%s\t%s\t%s\t%s\t%s\t%s\n", t, s, $1, $2, $3, l }' "$tsv" 2>/dev/null | write_lines
  return 0
}

do_append_run() {
  local entry="${1:-}" n="${2:-0}" wall="${3:-0}" rc="${4:-0}" sha="${5:-}" load="${6:-}" now
  [ -n "$entry" ] || return 0
  [ -n "$sha" ] || sha="$(default_sha)"
  [ -n "$load" ] || load="$(load1)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\trun:%s\t%s\t%s\t%s\tkind=run\tselected=%s\n' "$now" "$sha" "$entry" "$wall" "$rc" "$load" "$n" | write_lines
  return 0
}

# suite <TAB> runs <TAB> p95 <TAB> median, from exit-0 suite lines, nearest-rank percentile.
stats() {
  awk -F'\t' '$5 == "0" && $4 ~ /^[0-9]+$/ && $3 !~ /^run:/ { print $3 "\t" $4 }' "$(log_file)" \
    | sort -t "$TAB" -k1,1 -k2,2n \
    | awk -F'\t' '
      function flush(   r) {
        if (n == 0) return
        r = int(0.95 * n); if (r < 0.95 * n) r++; if (r < 1) r = 1
        printf "%s\t%d\t%d\t%d\n", cur, n, v[r], v[int((n + 1) / 2)]
      }
      $1 != cur { flush(); cur = $1; n = 0 }
      { v[++n] = $2 }
      END { flush() }'
}

# suite <TAB> the longest exit-124 (killed) seconds, a lower bound on what the suite needs.
kills() {
  awk -F'\t' '$5 == "124" && $4 ~ /^[0-9]+$/ && $3 !~ /^run:/ { if ($4 + 0 > m[$3] + 0) m[$3] = $4 + 0; seen[$3] = 1 }
              END { for (s in seen) printf "%s\t%d\n", s, m[s] }' "$(log_file)"
}

do_p95() {
  have_log || { no_log; return 0; }
  stats | sort -t "$TAB" -k3,3nr | awk -F'\t' -v only="${1:-}" '
    only == "" || $1 == only { printf "%-46s %4d runs  p95 %ds\n", $1, $2, $3 }'
  return 0
}

do_runs() {
  have_log || { no_log; return 0; }
  local rows; rows="$(awk -F'\t' '$3 ~ /^run:/' "$(log_file)" | tail -n 20)"
  [ -n "$rows" ] || { echo "suite-times: no run lines in $(log_file) yet" >&2; return 0; }
  printf '%s\n' "$rows" | awk -F'\t' '{
    e = $3; sub(/^run:/, "", e); sel = $8; sub(/^selected=/, "", sel)
    printf "%s  %-8s  %-13s  selected=%-4s wall=%ss  exit=%s  load=%s\n", $1, $2, e, sel, $4, $5, $6 }'
  printf '%s\n' "$rows" | awk -F'\t' '{ e = $3; sub(/^run:/, "", e); print e "\t" $4 }' \
    | sort -t "$TAB" -k1,1 -k2,2n | awk -F'\t' '
      function flush(   r) {
        if (n == 0) return
        r = int(0.95 * n); if (r < 0.95 * n) r++; if (r < 1) r = 1
        printf "%-13s %3d runs  p50 %ds  p95 %ds  (over the lines above)\n", cur, n, v[int((n + 1) / 2)], v[r]
      }
      $1 != cur { flush(); cur = $1; n = 0 }
      { v[++n] = $2 }
      END { flush() }'
  return 0
}

do_expected() {
  local jobs="${1:-1}" names
  case "$jobs" in ''|*[!0-9]*|0) jobs=1 ;; esac
  have_log || return 0
  names="$(cat)"; [ -n "$names" ] || return 0
  stats | awk -F'\t' -v jobs="$jobs" '
    NR == FNR { want[$1] = 1; total++; next }
    ($1 in want) { sum += $4; known++; if ($4 > longest) longest = $4 }
    END {
      if (known == 0) exit
      w = sum / jobs; if (longest > w) w = longest
      printf "%d %d %d\n", w, known, total - known
    }' <(printf '%s\n' "$names") - | {
      read -r w known unknown || exit 0
      [ -n "${w:-}" ] || exit 0
      printf 'run-all: expected wall about %ds (median per suite from %s, %s suites with history, %s without)\n' \
        "$w" "$(log_file)" "$known" "$unknown"
    }
  return 0
}

# Print the timeouts file as the rules in the header of this file would write it.
tuned_file() {
  local allow="$1" meta nsamp nsuites d1 d2
  meta="$(awk -F'\t' '$5 == "0" && $3 !~ /^run:/ { n++; d = substr($1, 1, 10); if (min == "" || d < min) min = d; if (d > max) max = d; s[$3] = 1 }
                      END { c = 0; for (k in s) c++; printf "%d %d %s %s\n", n, c, min, max }' "$(log_file)")"
  read -r nsamp nsuites d1 d2 <<<"$meta"
  awk -F'\t' -v min="$MIN_SAMPLES" -v lower="$allow" -v nsamp="$nsamp" -v nsuites="$nsuites" -v d1="$d1" -v d2="$d2" -v today="$(date -u +%Y-%m-%d)" '
    FILENAME == ARGV[1] { p95[$1] = $3 + 0; cnt[$1] = $2 + 0; next }
    FILENAME == ARGV[2] { kill[$1] = $2 + 0; next }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {
      if (body) next
      if ($0 ~ /^# tuned from suite-times history/) next
      if ($0 ~ /^# Rule:/) { inrule = 1; if (!genpos) { head = head "@@GEN@@\n"; genpos = 1 } next }
      if (inrule) { if ($0 ~ /^# One hand-set/ || $0 ~ /^[[:space:]]*$/) inrule = 0; else next }
      head = head $0 "\n"
      next
    }
    {
      body = 1
      split($0, f, /[[:space:]]+/); name = f[1]; secs = f[2]
      if (name == "" || secs !~ /^[0-9]+$/) next
      if ($0 ~ /#/) { keptline[name] = $0; keptsecs[name] = secs + 0; next }   # hand-set: keep
      old[name] = secs + 0
    }
    END {
      for (s in p95) names[s] = 1
      for (s in kill) names[s] = 1
      for (s in old) names[s] = 1
      for (s in names) {
        if (s in keptline) continue
        cur = (s in old) ? old[s] : -1
        cand = (cnt[s] >= min) ? 2 * p95[s] : -1
        if (cand >= 0 && cand < 60) cand = 60
        nw = cur
        if (cand >= 0 && (cur < 0 || cand >= cur || lower == 1)) nw = cand
        if ((s in kill) && 2 * kill[s] > nw) nw = 2 * kill[s]   # a kill at N means p95 >= N, so D4 gives at least 2N
        if (nw >= 0) out[s] = nw
      }
      gen = "# Rule: seconds = max(60, 2 x p95 of the exit-0 runs), set only from " min " or more samples and never below the current line unless tune ran with --allow-lower.\n"
      gen = gen "# An exit-124 (killed) row is a lower bound on p95: the limit is at least twice the seconds it was killed at. A line with a # comment is hand-set and kept.\n"
      gen = gen "# Source: suite-times history, " nsamp " exit-0 samples across " nsuites " suites, runs " d1 " to " d2 " (tuned " today ").\n"
      if (!genpos) head = head "@@GEN@@\n"
      i = index(head, "@@GEN@@\n")
      printf "%s%s%s", substr(head, 1, i - 1), gen, substr(head, i + 8)
      for (s in keptline) printf "%d\t%s\n", keptsecs[s], keptline[s]
      for (s in out) printf "%d\t%s %d\n", out[s], s, out[s]
    }' <(stats) <(kills) "$TIMEOUTS" \
    | awk -F'\t' '
        /^#/ { print; next }
        NF < 2 { print; next }
        { n++; sec[n] = $1; txt[n] = $2 }
        END { for (i = 1; i <= n; i++) idx[i] = i
              for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++)
                if (sec[idx[j]] > sec[idx[i]] || (sec[idx[j]] == sec[idx[i]] && txt[idx[j]] < txt[idx[i]])) { t = idx[i]; idx[i] = idx[j]; idx[j] = t }
              for (i = 1; i <= n; i++) print txt[idx[i]] }'
}

do_tune() {
  local write=0 allow=0 a out tmp
  for a in "$@"; do
    case "$a" in
      --write) write=1 ;;
      --allow-lower) allow=1 ;;
      *) echo "suite-times: tune: unknown flag: $a" >&2; return 64 ;;
    esac
  done
  { have_log && [ -n "$(stats)$(kills)" ]; } || { no_log; echo "suite-times: $TIMEOUTS left as it is" >&2; return 0; }
  [ -r "$TIMEOUTS" ] || { echo "suite-times: no timeouts file at $TIMEOUTS" >&2; return 0; }
  out="$(tuned_file "$allow")" || return 1
  [ -n "$out" ] || return 0
  if [ "$write" = 1 ]; then
    tmp="$TIMEOUTS.tune.$$"
    printf '%s\n' "$out" >"$tmp" && mv -f "$tmp" "$TIMEOUTS"
    echo "suite-times: rewrote $TIMEOUTS"
  else
    printf '%s\n' "$out"
  fi
  return 0
}

case "${1:-}" in
  append)     shift; do_append "$@" 2>/dev/null; exit 0 ;;
  append-run) shift; do_append_run "$@" 2>/dev/null; exit 0 ;;
  p95)        shift; do_p95 "$@" ;;
  runs)       shift; do_runs "$@" ;;
  expected)   shift; do_expected "$@" ;;
  tune)       shift; do_tune "$@" ;;
  -h|--help|help|"") sed -n '2,/^set -u/p' "$0" | sed '$d;s/^# \{0,1\}//' ;;
  *) echo "suite-times: unknown verb: $1 (append|append-run|p95|runs|expected|tune)" >&2; exit 64 ;;
esac
