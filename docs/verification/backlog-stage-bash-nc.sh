#!/usr/bin/env bash
# backlog-stage-bash-nc.sh <n> -- the mutation for negative control <n> of SPEC-408, run from the
# repo root by lib/gate/negctl.sh as its <mutate-cmd>. Each edit must change a tracked file, else
# negctl fails the control as vacuous.
#
#   bash lib/gate/negctl.sh "$PWD" "bash tests/test-backlog-stage-parity.sh" \
#     "bash docs/verification/backlog-stage-bash-nc.sh 1"
set -eu
H=hooks/backlog-stage.sh
U=lib/reflect/hook-util.sh
case "${1:?usage: backlog-stage-bash-nc.sh <1-8>}" in
  1) # count brackets to the last "]", not the matching one
    perl -0pi -e 's/if \.e != null then \. elif \$c\[\$i\] == 91 then \.d \+= 1\n\s*elif \$c\[\$i\] == 93 then \(\.d -= 1 \| if \.d == 0 then \.e = \$i else \. end\)/if false then . elif \$c[\$i] == 91 then .d += 1\n              elif \$c[\$i] == 93 then (.e = \$i)/' "$H" ;;
  2) # read a string content as text
    perl -0pi -e 's/elif \(\$c \| type\) == "string" or \(\$c \| type\) == "object" then \[\]/elif (\$c | type) == "string" then [\$c] elif (\$c | type) == "object" then []/' "$H" ;;
  3) # never write the throttle stamp
    perl -0pi -e 's/\{ : > "\$stamp" && touch "\$stamp"; \} 2>\/dev\/null/{ true; } 2>\/dev\/null/' "$U" ;;
  4) # drop the board dedup
    perl -0pi -e 's/\(\(\$bl \| sf_board_keys_lines\) \+ \(\$st \| sf_staging_titles_lines\)/((\$st | sf_staging_titles_lines)/' "$H" ;;
  5) # keep the payload file after --staged-run
    perl -0pi -e 's/\{ rm -f "\$pf"; \} 2>\/dev\/null/{ true; } 2>\/dev\/null/' "$H" ;;
  6) # exempt --staged-run from the BACKLOG_STAGE_AUTO gate
    perl -0pi -e 's/in 1\|true\|yes\|on\) ;; \*\) exit 0 ;; esac/in 1|true|yes|on) ;; *) case " \$* " in *" --staged-run "*) ;; *) exit 0 ;; esac ;; esac/' "$H" ;;
  7) # skip the forward-intent pre-filter
    perl -0pi -e 's/\[ "\$\{BACKLOG_STAGE_PREFILTER-1\}" != "0" \]/[ "\${BACKLOG_STAGE_PREFILTER-1}" = never ]/' "$H" ;;
  8) # hand the extractor the transcript text plus a trailing newline
    perl -0pi -e 's/printf \x27%s\x27 "\$text" > "\$W\/text"/printf \x27%s\\n\x27 "\$text" > "\$W\/text"/' "$H" ;;
  *) echo "unknown NC $1" >&2; exit 2 ;;
esac
