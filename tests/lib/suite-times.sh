#!/usr/bin/env bash
# suite-times.sh -- the per-host history of how long each test suite takes.
#
# Every tests/run-all.sh run appends one line per suite to a log OUTSIDE the repo, so a
# timeout can be re-tuned from stored numbers instead of a fresh full run. Reach the read
# verbs through the runner: `bash tests/run-all.sh --times <verb>`.
#
#   suite-times.sh append <tsv> [<sha> <load1>]  append the run's lines (suite secs exit per
#                                                 line of <tsv>), then trim to the cap
#   suite-times.sh p95 [<suite>]                 per-suite runs and p95 seconds, slowest first
#   suite-times.sh expected [<jobs>]             expected wall seconds of a full run, from the
#                                                 suite names on stdin (median each, jobs wide)
#   suite-times.sh tune [--write]                the timeouts file by D4's rule, 2 x p95 with
#                                                 a 60 s floor; prints it, --write rewrites it
#
# Log line (TSV): UTC time, git sha, suite, seconds, exit, 1-min load.
# Only exit-0 runs feed p95 and the median: a killed or red run measures the ceiling or a
# crash, not the suite. A timeouts line carrying a `#` comment is hand-set and kept as is.
# A missing, empty or unreadable log is not an error: read verbs say so on stderr and exit 0,
# and `tune` leaves the timeouts file untouched. Every failure to WRITE the log is swallowed
# (exit 0), so recording a timing can never change a test run's exit code.
# Env: KIT_SUITE_TIMES_FILE  the log (default ${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv)
#      KIT_SUITE_TIMES_CAP   lines kept (default 20000; non-numeric falls back to it)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$DIR/../.." && pwd)"
TIMEOUTS="${SUITE_TIMES_TIMEOUTS:-$KIT_DIR/bin/test-affected.timeouts}"

log_file() { printf '%s' "${KIT_SUITE_TIMES_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/suite-times.tsv}"; }

cap() {
  local c="${KIT_SUITE_TIMES_CAP:-20000}"
  case "$c" in ''|*[!0-9]*|0) c=20000 ;; esac
  printf '%s' "$c"
}

# True when the log exists and holds at least one line.
have_log() { [ -s "$(log_file)" ]; }
no_log() { echo "suite-times: no history at $(log_file); run tests/run-all.sh to start one" >&2; }

do_append() {
  local tsv="${1:-}" sha="${2:-unknown}" load="${3:-0}" f c now tmp
  [ -r "$tsv" ] || return 0
  f="$(log_file)"; c="$(cap)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  awk -F'\t' -v t="$now" -v s="$sha" -v l="$load" 'NF >= 3 { printf "%s\t%s\t%s\t%s\t%s\t%s\n", t, s, $1, $2, $3, l }' "$tsv" >>"$f" 2>/dev/null || return 0
  if [ "$(wc -l <"$f" 2>/dev/null | tr -d ' ')" -gt "$c" ] 2>/dev/null; then
    tmp="$f.trim.$$"
    if tail -n "$c" "$f" >"$tmp" 2>/dev/null; then mv -f "$tmp" "$f" 2>/dev/null || command rm -f "$tmp" 2>/dev/null; fi
  fi
  return 0
}

# suite <TAB> runs <TAB> p95 <TAB> median, from exit-0 lines, nearest-rank percentile.
stats() {
  awk -F'\t' '$5 == "0" && $4 ~ /^[0-9]+$/ { print $3 "\t" $4 }' "$(log_file)" \
    | sort -t "$(printf '\t')" -k1,1 -k2,2n \
    | awk -F'\t' '
      function flush(   i, r) {
        if (n == 0) return
        r = int(0.95 * n); if (r < 0.95 * n) r++; if (r < 1) r = 1
        printf "%s\t%d\t%d\t%d\n", cur, n, v[r], v[int((n + 1) / 2)]
      }
      $1 != cur { flush(); cur = $1; n = 0 }
      { v[++n] = $2 }
      END { flush() }'
}

do_p95() {
  have_log || { no_log; return 0; }
  stats | sort -t "$(printf '\t')" -k3,3nr | awk -F'\t' -v only="${1:-}" '
    only == "" || $1 == only { printf "%-46s %4d runs  p95 %ds\n", $1, $2, $3 }'
  return 0
}

do_expected() {
  local jobs="${1:-1}" names total_sum known unknown
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

# Print the timeouts file as D4 would write it from the history.
tuned_file() {
  awk -F'\t' '
    FNR == NR { p95[$1] = $3 + 0; have[$1] = 1; next }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {
      if ($0 ~ /^# tuned from suite-times history/) next
      if (!body) head = head $0 "\n"
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
      for (s in have) {
        if (s in keptline) continue
        v = 2 * p95[s]; if (v < 60) v = 60
        out[s] = v
      }
      for (s in old) if (!(s in out)) out[s] = old[s]            # no history: keep the old number
      printf "%s", head
      printf "# tuned from suite-times history (2 x p95 of exit-0 runs, floor 60); lines with a # comment are hand-set and kept\n"
      for (s in keptline) printf "%d\t%s\n", keptsecs[s], keptline[s]
      for (s in out) printf "%d\t%s %d\n", out[s], s, out[s]
    }' <(stats) "$TIMEOUTS" \
    | awk -F'\t' '
        /^#/ { print; next }
        { n++; sec[n] = $1; txt[n] = $2 }
        END { for (i = 1; i <= n; i++) idx[i] = i
              for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++)
                if (sec[idx[j]] > sec[idx[i]] || (sec[idx[j]] == sec[idx[i]] && txt[idx[j]] < txt[idx[i]])) { t = idx[i]; idx[i] = idx[j]; idx[j] = t }
              for (i = 1; i <= n; i++) print txt[idx[i]] }'
}

do_tune() {
  local write=0 out tmp
  [ "${1:-}" = "--write" ] && write=1
  { have_log && [ -n "$(stats)" ]; } || { no_log; echo "suite-times: $TIMEOUTS left as it is" >&2; return 0; }
  [ -r "$TIMEOUTS" ] || { echo "suite-times: no timeouts file at $TIMEOUTS" >&2; return 0; }
  out="$(tuned_file)" || return 1
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
  append)   shift; do_append "$@" 2>/dev/null; exit 0 ;;
  p95)      shift; do_p95 "$@" ;;
  expected) shift; do_expected "$@" ;;
  tune)     shift; do_tune "$@" ;;
  -h|--help|help|"") sed -n '2,/^set -u/p' "$0" | sed '$d;s/^# \{0,1\}//' ;;
  *) echo "suite-times: unknown verb: $1 (append|p95|expected|tune)" >&2; exit 64 ;;
esac
