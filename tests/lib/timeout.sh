#!/usr/bin/env bash
# timeout.sh -- a per-suite time limit that works on a stock macOS, which ships no `timeout`.
# Sourced by tests/run-all.sh and bin/test-affected, so both enforce the same ceiling.
#
#   source tests/lib/timeout.sh
#   kit_timeout <seconds> <command...>   exit 124 when the limit hit, else the command's status
#   kit_have_timeout                     0 when kit_timeout can enforce a limit on this host
#
# GNU `timeout` (or Homebrew's `gtimeout`) when present; else perl, which every macOS and Linux
# host has. The perl form runs the command as a plain child in the CALLER's process group (GNU
# timeout moves its child to a new group; an earlier version of this helper did too, and a stock
# macOS runner then hung two suites that had passed when no limit existed). At the limit it prints
# the live process tree under the command to stderr, so a stuck suite names what it is stuck on,
# sends TERM to that tree, and KILL five seconds later. Exit status follows GNU timeout: 124 on a
# timeout, 128+N when a signal ended the command. Without any of the three the command runs with
# no limit, as before. KIT_TIMEOUT_FORCE_PERL=1 skips the GNU tools (a test seam). Bash 3.2 safe.

kit_have_timeout() {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || command -v perl >/dev/null 2>&1
}

kit_timeout() {
  if [ -z "${KIT_TIMEOUT_FORCE_PERL:-}" ] && command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif [ -z "${KIT_TIMEOUT_FORCE_PERL:-}" ] && command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e '
      my $limit = shift @ARGV;
      my $pid = fork();
      exit 125 unless defined $pid;
      if (!$pid) { exec @ARGV; exit 127 }
      my ($hit, @doomed) = (0);
      # [pid, state, elapsed, command] for the command and everything under it
      sub tree {
        my (%kids, %row, @out, @queue);
        for (`ps -axo pid=,ppid=,stat=,etime=,command= 2>/dev/null`) {
          next unless /^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$/;
          push @{$kids{$2}}, $1; $row{$1} = [$1, $3, $4, $5];
        }
        @queue = ($pid);
        while (@queue) { my $p = shift @queue; push @out, $row{$p} if $row{$p}; push @queue, @{$kids{$p} || []}; }
        return @out;
      }
      $SIG{ALRM} = sub {
        if (!$hit) {
          $hit = 1;
          my @t = tree();
          print STDERR "timeout: ${limit}s reached; still running under pid $pid:\n";
          print STDERR "  pid=$_->[0] stat=$_->[1] etime=$_->[2] $_->[3]\n" for @t;
          @doomed = map { $_->[0] } @t; @doomed = ($pid) unless @doomed;
          kill "TERM", @doomed; alarm 5;
        } else { kill "KILL", @doomed }
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
