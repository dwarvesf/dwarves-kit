#!/bin/bash
# negctl test command for SPEC-405. negctl's restore() leaves INT/TERM/HUP ignored for the
# rest of its process, and bash cannot re-trap a signal ignored on entry, so the
# post-restore run would fail every TERM-based case. perl resets the three to default
# before exec'ing the suite. Full output goes to a file; the tail goes to negctl.
o="$(mktemp "${TMPDIR:-/tmp}/nc405.XXXXXX")"
perl -e 'for (qw(INT TERM HUP)) { $SIG{$_} = "DEFAULT" } exec @ARGV or die "exec: $!"' \
  bash tests/test-wrap-merge.sh >"$o" 2>&1
rc=$?
grep -a "FAIL" "$o" | tail -6
tail -1 "$o"
exit "$rc"
