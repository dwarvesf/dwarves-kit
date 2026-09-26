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
