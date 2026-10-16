# Retro: context-hints runs as bash plus jq (SPEC-406)
Date: 2026-10-16
Sprint: one session, first of the four remaining Python hook ports

Answers below were drafted by the lead from the session record, not collected one question at a time.

## Metrics
- Goldens: 120, generated from the Python shim before the port was written
- Real prompts replayed through both hooks: 1,266, identical
- Negative controls: 5, all red under their mutation
- Fresh review rounds: 1

## What worked
- The state file is the behavior. Seeding it and reading it back (`seed` and `read` in the shared harness) pinned the write-before-crash order that stdout alone cannot show.
- The installed Python hook had already written real state files on this machine, and the transcripts held real prompts. That gave a real-data check at no collection cost.
- Running the harness under `/bin/bash` and `/usr/bin/jq` found a bash 3.2 syntax error in the shared library that the Homebrew bash hid.

## What hurt
- The Mini ran at load average 25 to 70 for the whole session. Every parity run took minutes, so the negative controls ran in the background while the records were written.
- `rm` and `cp` are aliased to interactive mode in this shell, and a noclobber `>` silently kept an old file twice. Both cost a stalled command.

## Action items
- None for the operator. The next port adds an executable-seed and a `touch` field to the harness as it needs them.
