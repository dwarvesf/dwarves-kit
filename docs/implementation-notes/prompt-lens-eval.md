# Implementation notes: prompt-lens-eval

Spec: `docs/specs/SPEC-316-prompt-lens-eval.md`. Delta from the spec only.

| Kind | Note |
|---|---|
| Deviation, folded back | Scoring moved from one line to one finding block after live run 1. The model wrote `12. **Dependency and credential lifespan.** Reviewer 7.` and put `no rotation path` on an indented line below, so the line grep missed a real finding. The spec Contract and Decision Log now say block. |
| Deviation, folded back | The quiet-case signal changed from a keyword list (`run cost\|heartbeat\|...\|retire`) to "any numbered finding tagged Reviewer 7". Live run 2's pass line said `alias-retirement`, so the keyword list matched the pass line itself. The new signal is the lens contract's own rule: a short-lived spec gets no findings. Both versions fail run 2's sample. |
| Tradeoff | A base ref starting with `-` is refused by the flag parser as an unknown flag, not by a separate check. Same exit 64, one fewer branch. |
| Tradeoff | `lib/bench/tool.toml` keeps `entry = "bench.py"`; only its summary names `lens-eval.sh`. The tool has one entry field. |
| Open question | Live run 2 shows the Reviewer 7 lens can raise a finding on a short-lived spec while also printing `not long-lived` (an alias-removal warning on the flag-rename fixture). SPEC-314's single recorded quiet run did not. N=1 cannot say whether that is variance or a weak calibration line. Rerun with `--samples 3` before editing the lens. |
| Not built | No per-call timeout and no parallel calls, as the spec's Not covered says. A run of 3 calls took 107s and 140s. |
| Deviation, folded back | Review round (REVISE): the scorer drops a Passed section, splits table rows, and credits `### Reviewer N` headings. A block is emitted as `<reviewer heading><US><block>`: the `reviewer` regex sees the heading, the `pattern` sees the block alone, so an anchored pattern such as `^[0-9]+[.)] ` still works. |
| Deviation, folded back | The `quiet-pass` signal left the case file. Real reports put `Reviewer 7: not long-lived` under `## Passed`, which the scorer now drops. The quiet case keeps only the hard `treatment: miss`, which cannot tell a silent Reviewer 7 from a correct one. |
| Tradeoff | The `-any` signals now name `treatment: hit, control: fewer` on the same unscoped pattern. A reviewer-scoped comparison would be vacuous, because control has no Reviewer 7. |
| Deviation | L2 asked to refuse an absolute fixture path outside the repo. The script refuses every absolute path, because the contract already makes `fixture` relative to the case file and an in-repo absolute path has no use. |
| Deviation | L2 asked to refuse signal names containing `\|`. Signal names now use the case-name charset `[A-Za-z0-9._-]`, which also keeps the unit separator and newlines out of the table. |
| Tradeoff | With N odd, a majority always exists, so the old tie negative control became vacuous. The new control deletes the Passed-section drop. |
| Tradeoff | A missing `claude` keeps exit 2, as the spec's exit table already said, with its own verdict text. It is checked after the dry-run exit, so a dry run works without claude. |
| Open question, partly answered | Live run 3 (N=3) answers the quiet-case question above: Reviewer 7 raised a numbered finding (the alias-removal trigger, jointly with Reviewer 3) in 1 of 3 samples, 2 of 4 live samples overall. The signal passes on the majority, but the leak recurs. Tightening the Reviewer 7 calibration line is lens work, out of scope here. |
