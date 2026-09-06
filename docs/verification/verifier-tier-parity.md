# Proof of done: verifier tier parity (SPEC-244)

A verifier is never dumber than its worker. A spec carrying `Model: opus` now dispatches its verifiers on opus, and `recheck-verifier` pins `model: opus` in frontmatter.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | `agents/recheck-verifier.md` frontmatter is `model: opus` | PASS |
| 2 | `commands/execute.md` carries the parity override sentence verbatim | PASS |
| 3 | `commands/verify.md` carries the same sentence verbatim, plus the spec `Model:` header read in Step 1 | PASS |
| 4 | `commands/battery.md` acceptance leg names the spec tier | PASS |
| 5 | `doc-verifier` and the reviewers are unchanged (decision c) | PASS |
| 6 | NEGATIVE CONTROL: the old wall-off sentence is gone from `commands/execute.md` | PASS |
| 7 | NEGATIVE CONTROL: reverting the frontmatter to sonnet turns `tests/test-meta.sh` red | PASS |
| 8 | `bash tests/test-meta.sh` green | PASS |

## Implementation

- `agents/recheck-verifier.md:13`: `model: sonnet` becomes `model: opus`.
- `commands/execute.md`: the wall-off sentence is removed from the tier paragraph and replaced by the "Verifier tier parity (SPEC-244)" paragraph; a short override note sits at the task-verifier, recheck-verifier, and integration-verifier dispatch sites.
- `commands/verify.md`: Step 1 reads the spec's bare `Model:` header and states the parity override; Steps 3-6 each point at it.
- `commands/battery.md`: the acceptance leg's tier cell reads "mid, or the spec's tier when it carries `Model: opus`".
- `docs/specs/SPEC-107-tier-defaults.md`: a "Superseded by SPEC-244 for verifiers" line next to the original wall-off sentence. History is not rewritten.
- `tests/test-meta.sh`: the SPEC-244 block, five assertions including the wall-off negative control.
- `docs/FEATURES.md`: regenerated, because it is a generated projection of the spec references.

## Green run

```
$ bash tests/test-meta.sh
...
=== Results ===
Passed: 829 / 829
All meta tests passed.
```

Exit: 0

Full suite on the final tree:

```
$ bash tests/run-workflow.sh
restored 3 side-effect file(s)
run-workflow: 0 red of 64 steps
```

Exit: 0

## Negative control

Revert the frontmatter pin and re-run the same command.

```
$ sed -i '' 's/^model: opus$/model: sonnet/' agents/recheck-verifier.md
$ bash tests/test-meta.sh
  FAIL recheck-verifier pins model: opus (SPEC-244) (expected '0', got '1')
=== Results ===
Passed: 828 / 829
Failed: 1
```

Exit: 1, RED-as-expected. Restored with `git checkout -- agents/recheck-verifier.md`; the re-run returned 829 / 829.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh
grep -c 'dispatch with an explicit model override matching the spec tier' commands/execute.md commands/verify.md
! grep -qF 'Verifiers keep their own frontmatter tiers (unchanged).' commands/execute.md
```

## Verdict: PASS

## Test plan coverage

| Row | Run / skip reason |
|---|---|
| 1 | green run, assertion "recheck-verifier pins model: opus (SPEC-244)" |
| 2 | green run, agent-frontmatter lint block (all agents sonnet\|haiku\|opus) |
| 3 | green run, assertion "execute.md carries the verifier parity override sentence" |
| 4 | green run, assertion "verify.md carries the verifier parity override sentence" |
| 5 | green run via row 4's surface; the Step 1 header read is prose in the same paragraph the row-4 grep matches |
| 6 | green run, assertion "negative control: old verifier wall-off sentence removed from execute.md" |
| 7 | green run, the graceful-degrade clause rides the same paragraph as row 3 and the SPEC-078 pin "tiering fallback sentence present" |
| 8 | manual grep on `commands/battery.md`, acceptance leg cell reads "mid, or the spec's tier when it carries `Model: opus`" |
| 9 | green run, assertion "doc-verifier stays sonnet (SPEC-244 decision c)" |
| 10 | negative control above, RED-as-expected then restored |
