# Implementation notes: gauntlet-stats (delta from SPEC-240)

## 2026-09-01 usage key location

Context: the spec names omp v3 `turn_end.usage`. Real transcripts nest usage under `.message.usage`.
Decision: the jq coalesces `.usage // .message.usage`.
Impact: none on the contract. The spec's field names were one level off.

## 2026-09-01 per-run transcript scoping

Context: the spec computes tokens per record. A record dir can hold several runs (`ROUNDS.md` + `J3-ROUNDS.md`). The review found the primary row absorbing sibling transcripts.
Decision: scope by round-dir convention. A prefixed run owns `<prefix>-round-*` subtrees. The primary run owns everything else, with `*-round-*` pruned. Campaign row dirs (`J1/`) never match the prune and stay with the primary.
Why: the convention already exists in every record on disk. No manifest needed.
Impact: multi-run dirs report true per-run cost. A future record that breaks the round-dir naming would misattribute again.

## 2026-09-01 marker sweep is strict full-line

Context: review found the substring match passed a line pairing a valid marker with a corrupted one.
Decision: strip backticks and edge whitespace, then require the whole line to be one valid marker.
Impact: a ROUNDS.md line that EMBEDS a marker in prose now fails the sweep. Record files keep markers on their own line, so the corpus is unaffected. Doc prose outside record dirs is never scanned.

## 2026-09-01 findings-graduated column not shipped

Per the spec's open question: rule-10 graduations have no greppable marker in ROUNDS.md prose, so the column does not exist yet. Add the marker first, then the column.

## 2026-09-01 suite baseline

`tests/test-meta.sh` fails 7/822 on origin/master before this branch (SPEC-239 ship drift). Filed as ID-639, untouched here.
