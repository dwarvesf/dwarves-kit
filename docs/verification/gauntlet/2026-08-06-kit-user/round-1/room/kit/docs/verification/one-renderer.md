# Proof of Done: one renderer, actually

**Feature:** the two private copies of the staged-block grammar import the shared renderer, and C5 can no longer pass vacuously for a file that defines its own.
**Date:** 2026-07-15 · **Lane:** normal · **Host:** Hans-Air-M4 (macOS 26.5) · **Spec:** SPEC-200 I1 / ADR-0034 decision 1

## What was wrong

SPEC-200 I1 says every proposer renders through `lib/learn/staging-format.py`. Two did not:
`hooks/backlog-stage.py` (`render_candidate`) and `lib/stats/src/stats/anomalies.py`
(`render_block`) each kept a private copy of the block grammar.

The copies drifted. The shared renderer collapses whitespace per field (a guard added on
2026-07-14, when these fields started carrying LLM-extracted transcript text, i.e.
attacker-influenceable content). The hook's copy did a bare `.strip()`; stats' copy did not even
that. An embedded newline therefore survived into a line-oriented grammar and **forged a second
`## [staged]` block**: one candidate in, two proposals out, and the forged one was
indistinguishable from a real one to `learn drain` and `board promote`.

**C5 could not catch it.** The rule grepped for `render_block|render_candidate`, and a file that
DEFINES that function matches its own grep. The rule passed vacuously for the exact two files it
existed to catch. The negative control planted the comment-mention evasion, not the
keep-your-own-copy evasion, so it never surfaced.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `hooks/backlog-stage.py` renders through the shared module | SPEC-200 I1 |
| A2 | `lib/stats/.../anomalies.py` renders through the shared module | SPEC-200 I1 |
| A3 | A forged title (embedded `\n\n## [staged] ...`) produces exactly ONE block from the hook | NEGATIVE CONTROL (the live hole) |
| A4 | C5 fails a file that DEFINES its own renderer | NEGATIVE CONTROL (the vacuous-pass) |
| A5 | Every pre-existing suite stays green (stats propose, hooks, learn) | regression |

## Implementation

| Piece | What | Where |
|---|---|---|
| Hook | `render_candidate` delegates to `sf.render_block` | `hooks/backlog-stage.py` |
| Stats | `render_block` delegates; the `#u-*/#f-*` tag string maps back to `u`/`f` | `lib/stats/src/stats/anomalies.py` |
| C5 | must LOAD `staging-format.py`, not merely NAME a renderer; a file defining one next to the import is flagged | `tests/test-kit-contract.sh` |
| C5 NC | plants a private renderer (the evasion that shipped), not a comment mention | same |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Forgery closed (A1/A3) | render a forged title through the hook, parse the output | 1 block (was 2) | PASS |
| Contract (A4) | `bash tests/test-kit-contract.sh` | `25 passed, 0 failed`, incl. the new C5 NC | PASS |
| Stats propose (A2/A5) | `bash lib/stats/tests/test-feedback.sh` | `47 passed, 0 failed` | PASS |
| Hooks (A5) | `bash tests/test-hooks.sh` | all passed | PASS |
| Learn (A5) | `bash tests/test-learn-propose.sh` + `test-learn-drain.sh` | all passed | PASS |

## Run detail

```
$ python3 - <<'PY'   # the live hole, before and after
hook renderer -> blocks: 2      # BEFORE: one candidate forged two staged rows
hook renderer -> blocks: 1      # AFTER
PASS: the hook can no longer forge a second block
PY
Exit: 0

$ bash tests/test-kit-contract.sh | tail -5
  PASS C5 catches a writer that only MENTIONS the renderer in a comment
  PASS C5 catches a writer that DEFINES its own renderer (the copy that drifted)
=== kit-contract: 25 passed, 0 failed ===
Exit: 0
Verdict: PASS
```

NEGATIVE CONTROL, on the lint itself: plant a file that defines `render_block` and writes a
`## [staged]` line. The old C5 passed it (its own definition satisfied the grep); the new C5
flags it. That is the assertion, not a story.

## The lesson, stated plainly

`docs/data-flow.md` said of these copies: *"byte-identical today, which is exactly how it will
drift tomorrow."* Tomorrow arrived in one day, and it arrived as a security hole, not a style
nit. This is the third instance of the same bug class in two days: a hand-list beside a deriving
resolver (skill-curator's alias), a second implementation of the ledger-root chain (stats), and
now a private copy of a shared grammar. **A copy of a shared thing is not a copy for long.**

## Reproduce

```bash
cd <dwarves-kit>
bash tests/test-kit-contract.sh
bash lib/stats/tests/test-feedback.sh
```
