# Spec: a proof of done carries its captured output, and the output reaches the operator and the PR

Generated: 2026-10-03
Status: IMPLEMENTED, pending merge (branch `feat/proof-captured-output`)
Lane: full (`lib/gate/proof-ledger.sh` is a hard path; the gate runs on every push in every adopted repo)
Type: spec-feature
Depth: standard (one predicate added to an existing gate, two read-only verbs, one body builder; no unknown a probe would close)
References: `lib/gate/proof-ledger.sh` `check`, `lib/gate/negctl.sh`, `lib/gate/proof-gate.sh` `skeleton`, `lib/wrap/wrap-land.sh` `cmd_land`, `docs/verification/README.md` "What done means", `AGENTS.md` zone 3
Source: operator brief, session 2026-10-03, three requirements: the proof captures the output, the output is in the agent's reply, the output is in the PR

## Problem

A proof of done could pass the ship-gate with nothing a run printed. `check` took a green run from the words `Exit: 0`, `Verdict: PASS` or a bare `PASS`, so a typed claim counted as evidence. The verification README already asked for an `Output (excerpt):` under each run, and nothing enforced it.

The output also stopped at the file. `wrap land` with no `--body-file` opened the PR with the title as its whole body (observed on a consumer repo: a branch that added a proof file landed with a one-line PR body). The land's own stdout named no proof, so the agent's closing report had nothing to quote and said "tests pass".

## Rules

| # | Rule | Lands in |
|---|---|---|
| R1 | A run counts as captured only when the proof holds real lines under an `Output` slot, or the raw lines after `Exit:` inside a fenced run block, or embeds a committed image. A slot is a line `Output:` or `Output (<anything>):` in any case (a list bullet or bold is fine), or a `### Output` heading. Its lines are the text after the colon, then the lines below up to a run-table field at the start of a line (`Command:`, `Exit:`, `Verdict:`, `Result:`; an indented line never ends a slot), the next heading, the end of its fence, or a blank line once it has content. Blank lines, fence lines, a `<placeholder>` and filler (`none`, `n/a`, `...`, `see ...`) are not output. The full grammar is the comment above `_captured_output`. | `lib/gate/proof-ledger.sh` `_captured_output` |
| R2 | Behavioral: green run = (a green marker AND R1 output) OR a committed image. Stateful: recorded run = (`Command:` or `Exit:` AND R1 output) OR a committed image; a proof marked `[UNAVAILABLE: reason]` records that no run was possible and owes no output. The negative control, the last-Verdict rule, the rollback note, the set-wise directory layout and the override path are unchanged. | `check` |
| R3 | The BLOCKED message names each proof file that has no captured output and says what to add. | `check` |
| R4 | The kit's own producers emit the slot. `negctl.sh` prints `Output:` with the last 10 lines of the run after the green and the red run (`<no output>` for a silent run, which the gate does not count). `proof-gate.sh skeleton` carries an `Output:` slot and one line naming the image alternative. `/kit:verify` and `spec-task-done.sh` already write `Output (excerpt):`. | `lib/gate/negctl.sh`, `lib/gate/proof-gate.sh` |
| R5 | `wrap land` with no `--body-file` builds the PR body from the branch's proof files: the title, then `## Proof of done` with each file's content. The file lookup is the gate's own (`proof-ledger.sh proof-files`). A relative image link that resolves in the tree becomes `<repo page>/blob/<head sha>/<path>?raw=true`. A body over 40000 characters is cut and ends on a pointer to the file. | `lib/wrap/wrap-land.sh` `_land_proof_body` |
| R6 | An adopted PR keeps its body. It takes the proof body only when its body is empty or equals its title. | `cmd_land` |
| R7 | A land that merged ends on a `PROOF OF DONE` block: the proof file path, the PR link, at most 15 captured output lines per file, and the committed image paths. | `_land_proof_block` |
| R8 | The operate-contract and the command docs state one rule: the final report shows the captured output and the PR link, never only "tests pass". | `AGENTS.md`, `examples/hello-spec/AGENTS.md`, `commands/wrap.md`, `commands/verify.md`, `docs/verification/README.md` |

Boundaries:

- The gate still judges only a proof file the branch itself adds or changes. A proof already merged is never read again.
- A branch in flight whose proof was written before this change is refused at its next push, with the R3 hint naming the file. Adding the `Output:` lines of the run it already recorded clears it.
- A cumulative `proof-of-done.md` is judged as one file, as before: an old filled slot in it satisfies R1 for a new entry. Same reach the green marker always had.
- No proof file on the branch: `land` behaves as before (title as the body, no block).
- A repo with a PR template still refuses a new PR without `--body-file`. The proof body does not replace a template.
- Out of scope: a video or GIF recorder, judging whether the pasted lines are true, the `--body-file` path (the caller wrote that body).

## Tasks

| ID | Task | Files | Done when |
|---|---|---|---|
| T1 | The captured-output predicate, R2 and R3 in `check`, and the read verbs `proof-files`, `captured-output`, `images` | `lib/gate/proof-ledger.sh` | a typed-only proof is BLOCKED, a filled slot or a committed image passes |
| T2 | Producers emit the slot | `lib/gate/negctl.sh`, `lib/gate/proof-gate.sh` | a proof made of negctl's block passes; an unfilled skeleton does not |
| T3 | PR body, adopted-PR rule, closing block | `lib/wrap/wrap-land.sh`, `lib/wrap/wrap.sh` | the `pr create` call carries the proof section; the land ends on the block |
| T4 | State R8 | the five docs in R8 | each names the captured output and the PR link |
| T5 | Tests, and the existing fixtures that record a typed-only run | `tests/test-proof-captured-output.sh`, `tests/test-wrap-land.sh`, the proof fixtures | the suite is green |

## Test plan

| # | Category | Case | How |
|---|---|---|---|
| 1 | gate, negative | typed `Exit: 0` / `Verdict: PASS`, no output | `check` exits 1, message names the file and `Output:` |
| 2 | gate, positive | `Output:` with lines below, on the same line, in a fenced block | `check` exits 0 for each |
| 3 | gate, boundary | empty slot; slot holding only a `<placeholder>` | `check` exits 1 |
| 4 | gate, image | committed image embed; dangling image reference | exits 0; exits 1 |
| 5 | gate, stateful | `Command:`/`Exit:` + rollback, with and without output | exits 0; exits 1 |
| 6 | producers | skeleton slot and image line; unfilled skeleton; negctl block | grep; `check` exits 1; `check` exits 0 |
| 7 | land body | summary line, section, output line, pinned image link, dangling link kept, cut with pointer, no proof file | `_land_proof_body` called directly |
| 8 | land flow | new PR, adopted PR with a title-only body, adopted PR with its own body, `--body-file`, no proof file | `wrap land` against the gh stub |

## Verification

```bash
bash tests/test-proof-captured-output.sh
LAND_CACHE=0 LAND_ONLY=proofbody bash tests/test-wrap-land.sh
LAND_CACHE=0 bash tests/run-all.sh --all
grep -nP '\x{2013}|\x{2014}' docs/specs/SPEC-384-proof-captured-output.md   # no output
```

Negative control: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-proof-captured-output.sh" "git show origin/master:lib/gate/proof-ledger.sh > lib/gate/proof-ledger.sh"` goes RED on the old gate and restores.

## After state

- A proof whose run is typed words alone cannot ship. The refusal names the file and the slot to fill.
- `negctl.sh` output pasted into a proof passes the gate without hand edits.
- A PR landed through `wrap land` shows the proof, with its images, in the PR body.
- `wrap land` ends on a block the agent's final report can quote: proof file, PR link, output lines.

## Design

Design-bearing: no. One predicate beside the existing image predicate, two read-only verbs that expose lookups the gate already has, one body builder in the verb that already creates the PR. No new component, schema or stored state.

Choices worth recording:

- **The slot name is `Output`, with the two qualifiers the kit already writes.** `Excerpt:` and `Tail:` alone are not slots. One name keeps the rule exact and the refusal says what to rename.
- **A green marker is still required beside the output** (behavioral). Output alone does not say the run passed.
- **Stateful proofs take the same rule.** A deploy recorded as `Command:` alone was the same hole on the riskiest class.
- **`land` asks the gate for the proof files** instead of holding a second copy of the path rule. A new proof home changes one regex.
- **Fail-open is where it was.** `check` still returns 0 on an unresolved base and an inert diff. In `land`, any failure to read the proof leaves the body and the block empty, which is the old behaviour.

## Decision Log

- 2026-10-03, operator set the three requirements and the five deliverables in the session brief. Think, design, design-critique, validate and design-record are recorded as overrides on that brief; the post-build review ran.
