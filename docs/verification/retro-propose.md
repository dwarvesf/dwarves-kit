# Proof of Done: retro action items reach the Learn gate

**Feature:** `learn propose --retro <RETRO.md>` stages a retro's action items as `## [staged]` blocks (SPEC-200 I1 / T7, the last proposer that leaked).
**Date:** 2026-07-15 · **Lane:** normal · **Host:** Hans-Air-M4 (macOS 26.5)

## What was wrong

`/kit:retro` wrote its outcomes as a checkbox list inside `docs/retro/RETRO-<date>.md`.
`board promote` reads ONLY the staging buffer, so those items could never be promoted: a human
had to retype one to act on it, and so nobody did. Every retro before today leaked its action
items exactly this way. Same disease `session-intel` had (T6, fixed in #250); this was the last
proposer still outside the one currency.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | Unchecked action items are staged as `## [staged]` blocks through the one renderer | SPEC-200 I1 |
| A2 | The title is the CHANGE alone; `-- owner:` / `-- deadline:` do not leak into it | parser correctness |
| A3 | Owner + retro filename ride on the `Source:` citation | traceability |
| A4 | A `[x]` (already-done) item is NOT staged | NEGATIVE CONTROL |
| A5 | The template placeholder (`[concrete change]`) is NOT staged | NEGATIVE CONTROL |
| A6 | The board is byte-identical after the run (sha256) | NEGATIVE CONTROL, propose-don't-dispose |
| A7 | Re-running stages nothing new (deduped against staging + board) | idempotence |
| A8 | `--dry-run` writes NO file | NEGATIVE CONTROL |

## Implementation

| Piece | What | Where |
|---|---|---|
| Parser | `## Action items` section -> unchecked `- [ ]` lines; ` -- ` split for owner/deadline | `lib/learn/propose.py::parse_retro_actions` |
| Stager | deterministic (no LLM, no grounding, no refute: the retro IS the evidence); renders via `staging-format.render_block`, dedups via `existing_keys` | `::run_retro` |
| CLI | `--retro FILE` on the EXISTING `propose` verb (SPEC-200 I4: `propose` = stage proposals; the flag names the SOURCE, it is not a new verb) | `::main` |
| Command | `/kit:retro` Step 3b runs it after writing the doc | `commands/retro.md` |
| Tests | 8 assertions, 4 of them negative controls | `tests/test-learn-propose.sh` |

Deliberately NOT done inside the `/kit:retro` prompt: that file is markdown an LLM reads, so
asking the model to also emit staging blocks is a promise it keeps only sometimes. A parser
either works or fails a test.

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Full suite (A1-A8) | `bash tests/test-learn-propose.sh` | `41 run, 41 passed, 0 failed` | PASS |
| Staged + clean title (A1/A2) | T7a, T7b | 2 blocks; title has no `owner:` | PASS |
| Citation (A3) | T7c | `Source: retro 2026-07-15 \| RETRO-2026-07-15.md owner=han` | PASS |
| NEGATIVE CONTROL checked item (A4) | T7d | `[x]` item absent from staging | PASS |
| NEGATIVE CONTROL placeholder (A5) | T7e | `[concrete change]` absent | PASS |
| NEGATIVE CONTROL board untouched (A6) | T7f | board sha256 identical | PASS |
| Idempotent (A7) | T7g | re-run adds nothing | PASS |
| NEGATIVE CONTROL dry-run (A8) | T7h | no file created | PASS |
| Reachable via the dispatcher | `bash lib/learn/learn.sh propose --retro ...` | runs | PASS |
| Contract | `bash tests/test-kit-contract.sh` | `24 passed, 0 failed` | PASS |

## Run detail

```
$ bash tests/test-learn-propose.sh | tail -11
== T7: learn propose --retro stages a retro's action items ==
  PASS  T7a: the two OPEN action items are staged
  PASS  T7b: the title is the change alone (owner/deadline stripped, not swallowed)
  PASS  T7c: owner + retro file ride on the citation
  PASS  T7d NC: a checked [x] item is NOT staged
  PASS  T7e NC: the template placeholder is NOT staged
  PASS  T7f NC: the board is byte-identical after propose --retro
  PASS  T7g: re-running stages nothing new (deduped)
  PASS  T7h NC: --dry-run writes NO staging file

== 41 run, 41 passed, 0 failed ==
Exit: 0
Verdict: PASS
```

The first cut of the parser failed T7b and T7d, which is why both are in the suite: a non-greedy
regex with optional trailing fields backtracked into swallowing `-- owner: han -- deadline: ...`
into the title, and a `[x]` item was staged as if it were open. Both bugs were caught by the
assertions above before the code left the branch.

## Reproduce

```bash
cd <dwarves-kit>
bash tests/test-learn-propose.sh
bash lib/learn/learn.sh propose --retro docs/retro/RETRO-<date>.md --dry-run
```
