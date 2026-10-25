#!/usr/bin/env bash
# timeout.sh -- a per-suite time limit that works on a stock macOS, which ships no `timeout`.
# Sourced by tests/run-all.sh and bin/test-affected, so both enforce the same ceiling.
#
#   source tests/lib/timeout.sh
#   kit_timeout <seconds> <command...>   exit 124 when the limit hit, else the command's status
#   kit_have_timeout                     0 when kit_timeout can enforce a limit on this host
#
# GNU `timeout` (or Homebrew's `gtimeout`) when present; else perl, which every macOS and Linux
# host has: the command runs in its own process group, the group gets TERM at the limit and KILL
# five seconds later, and the exit status follows GNU timeout (124 on a timeout, 128+N when a
# signal ended the command). Without any of the three the command runs with no limit, as before.
# Bash 3.2 safe.

kit_have_timeout() {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || command -v perl >/dev/null 2>&1
}

kit_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e '
      my $limit = shift @ARGV;
      my $pid = fork();
      exit 125 unless defined $pid;
      if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
      my $hit = 0;
      $SIG{ALRM} = sub {
        if (!$hit) { $hit = 1; kill "TERM", -$pid; alarm 5 }
        else { kill "KILL", -$pid }
      };
      alarm $limit;
      my $got;
      do { $got = waitpid($pid, 0) } while ($got == -1 && $! == 4);
      alarm 0;
      my $st = $?;
      exit 124 if $hit;
      exit(($st & 127) ? 128 + ($st & 127) : $st >> 8);
    ' "$@"
  else shift; "$@"
  fi
}
