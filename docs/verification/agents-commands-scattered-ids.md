# Verification log: stripping scattered ids from agents/ and commands/

Branch `chore/ids-agents-commands`, base a57a6fd (origin/master).

423 scattered-id hits removed across `agents/*.md` (72 hits, 31 files) and `commands/*.md`
(351 hits, 38 files) -- the two surfaces that load into a model's context every session,
where the id buys nothing because the model cannot open the spec. Registered as lint zones
6 and 7 in `tests/test-no-scattered-ids.sh`.

## Rewrite shapes used

- A bare parenthetical (`(SPEC-089)`, `(SPEC-089 TASK-019)`) dropped whole, or just the id
  token when the parenthetical carried other content.
- `ADR-0028 "Some Title"` -> `the "Some Title" decision` (the quoted title survives as the
  plain-word name; the number goes).
- A citation to another spec's filename (`docs/specs/SPEC-088-....md`) -> a plain-words
  description (`the agent-effectiveness-validator design spec under docs/specs/`), since the
  literal filename string still carries the id and still trips the lint.
- Repeated identical headings (`## Return contract (distilled return, SPEC-087 Mechanism C)`,
  30 occurrences across both zones) collapsed to `## Return contract (distilled return)`.
- Illustrative id-shaped examples in a spec/goal template (`TASK-001`, `DEC-001`, `SG-01`)
  rewritten with letters or plain words (`TASK-A`, `DEC-A`, "sub-goal 1") so the example still
  reads correctly without matching the id regex.

## Green run

Command: `bash tests/test-no-scattered-ids.sh && bash tests/test-meta.sh`
Exit: 0 for each
Output (excerpt):
```
=== Zone 6: no id anywhere in agents/*.md ===
  PASS no scattered id in agents

=== Zone 7: no id anywhere in commands/*.md ===
  PASS no scattered id in commands

test-no-scattered-ids: all 8 passed
```
```
Passed: 852 / 852
All meta tests passed.
```
Verdict: PASS

## Negative control

Mutation: prepended `<!-- negative-control: SPEC-999 -->` as a new first line of
`agents/advisor.md` (a file already stripped clean by this batch).
Command: `bash tests/test-no-scattered-ids.sh`
Exit: 0 before; 1 under mutation; 0 after restore
Output (excerpt) under mutation:
```
=== Zone 6: no id anywhere in agents/*.md ===
     agents/advisor.md:1:<!-- negative-control: SPEC-999 -->
  FAIL 1 hit(s) in agents; see lib/lint/README.md for the exemption list

test-no-scattered-ids: 7 passed, 1 FAILED
```
Rollback / restore: reverted `agents/advisor.md` to its post-strip content; re-ran, all 8
zones passed again.
Verdict: RED-as-expected, then PASS on restore.

Rollback for the whole branch, if ever needed: `git revert` the two commits on
`chore/ids-agents-commands` (the strip commit and the board-flip commit); nothing outside
`agents/`, `commands/`, the two changed test files, `docs/FEATURES.md`,
`tests/test-no-scattered-ids.sh`, and this doc is touched, so the revert is clean.

## A transient false failure during the run, and why it wasn't real

A `test-meta.sh` run taken mid-batch (while a sibling fork was still mid-edit on
`commands/kit-health.md` in this same worktree) showed 5 failures, including a stale-text
assertion that no longer matched the file's in-flight content. A clean re-run after every
fork finished (`git status` showing 75 files changed, both lint zones at 0 hits) passed all
852 assertions. The failure was a read against a file being written by a concurrent editor
in the same working tree, not a defect in the strip.

## Deliberately not done

`SG-01`/`SG-02` used as a genuine sub-goal LABEL inside a provenance-format example in
`commands/mega.md` ("Provenance per sub-goal") were rewritten to the non-digit placeholder
form `SG-<N>` already used elsewhere in that same file (`SG-NN`), rather than invented fresh.
No hit was left un-rewritten; every hit in both zones now reads zero on the enumerator.
