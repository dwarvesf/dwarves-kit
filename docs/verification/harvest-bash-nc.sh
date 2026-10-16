#!/usr/bin/env bash
# harvest-bash-nc.sh <n> -- the mutation for negative control <n> of SPEC-409, run from the repo
# root by lib/gate/negctl.sh as its <mutate-cmd>. Each edit must change a tracked file, else negctl
# fails the control as vacuous.
#
#   bash lib/gate/negctl.sh "$PWD" "bash tests/test-harvest-parity.sh" \
#     "bash docs/verification/harvest-bash-nc.sh 2"
# NC1 is the exception: its test is the concurrency row of tests/test-kit-foldin-hooks.sh.
set -eu
H=hooks/harvest.sh
case "${1:?usage: harvest-bash-nc.sh <1-9>}" in
  1) # take no lock around the dedup and the append
    perl -0pi -e 's/lock_run wait "\$ledger\.lock" bash "\$SELF" --stage-locked/bash "\$SELF" --stage-locked/' "$H" ;;
  2) # never apply the fuzzy threshold
    perl -0pi -e 's/if \(fuzzy > 0\) \{/if (0) {/' "$H" ;;
  3) # ignore the glossary files
    perl -0pi -e 's/done < "\$gl"; \} > "\$known"/done < \/dev\/null; } > "\$known"/' "$H" ;;
  4) # let one batch stage the same slug twice
    perl -0pi -e 's/\(slug in K\) \|\| \(slug in S\)/(slug in K)/' "$H" ;;
  5) # keep the payload file after a detached child
    perl -0pi -e 's/\{ rm -f "\$pf"; \} 2>\/dev\/null/{ true; } 2>\/dev\/null/' "$H" ;;
  6) # fire the stop-trigger on every turn
    perl -0pi -e 's/if \[ \$\(\( \(cur % n \+ n\) % n \)\) -ne 0 \]; then/if [ 1 -ne 1 ]; then/' "$H" ;;
  7) # keep a timed-out extractor'"'"'s stdout
    perl -0pi -e 's/  \[ ! -e "\$2\.timedout" \] \|\| : > "\$2"[^\n]*\n//' "$H" ;;
  8) # drop the sweep-child recursion guard
    perl -0pi -e 's/\[ "\$\{HARVEST_SWEEP_CHILD:-\}" = "1" \]/[ "\${HARVEST_SWEEP_CHILD:-}" = never ]/' "$H" ;;
  9) # append to a ledger that is not valid UTF-8
    perl -0pi -e 's/  if \[ -f "\$ledger" \] && ! iconv -f UTF-8 -t UTF-8 "\$ledger" >\/dev\/null 2>&1; then return 1; fi\n//' "$H" ;;
  *) echo "unknown NC $1" >&2; exit 2 ;;
esac
