# Implementation notes: board backward notice

Delta from the brief. No spec file backs this change.

- `set` now prints `board set: <ID> moves back from '<from>' to '<to>'` on stderr when both states are `active` and the target sits earlier in `states.tsv`. The write, stdout, and exit codes stay as before.
- Direction comes from the file order through `_is_backward`. A test swaps two rows in a copied table and the same move flips direction, so a hardcoded list would fail it.
- `hold` and `terminal` keep today's behavior. A move into or out of `parked` is quiet. A move out of a terminal state keeps the reopen notice.
- Writeback used to discard what `set` said on stderr. It now writes that text to a scratch file, repeats it on its own stderr with a `writeback:` prefix, and adds it to the commit body as a `note:` line. The PR reviewer sees the backward move.
- A failing `set` still stops the group: writeback returns the exit code after showing the stderr text, which matches the old `set -e` death.
- Only `states.tsv` comments and the `backlog.sh` header gained a line about the notice. No spec says otherwise.

Open question: the Hermes bridge owns no rule for a card that Hermes moved back on purpose. The notice only informs. A rule would need a separate decision.
