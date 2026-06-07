# Verification log -- shared-evidence-discipline

The proof-of-done side of the cross-pollination with the experiment discipline: the kit's
verification numbers are now single-sourced (borrowed from the benchmark's `gen_docs.py`),
and the convention names the experiment as its sibling. This log dogfoods the borrow: it
does NOT transcribe the suite count, it links the single source. Shape:
`docs/verification/README.md`.

## 2026-06-07 01:11 PASS -- shared-evidence-discipline [single-source]
- Command: `bash lib/verif-counts.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  wrote docs/verification/COUNTS.md (meta=368/368, hooks=164/164)
  meta: All meta tests passed.
  hooks: All tests passed.
  ```
- Verdict: PASS
- Note: the live counts are in `docs/verification/COUNTS.md` (the GEN block), not typed
  here. To change a number, change the tests then `bash lib/verif-counts.sh`.

## 2026-06-07 01:11 REGENERATE -- single-source proof (figure follows the source)
- Command: add 3 meta-test pins, then `bash lib/verif-counts.sh`
- Output (excerpt):
  ```
  COUNTS before regen: | meta (tests/test-meta.sh) | 365/365 |
  wrote docs/verification/COUNTS.md (meta=368/368, ...)
  COUNTS after regen:  | meta (tests/test-meta.sh) | 368/368 |
  ```
- Verdict: PASS
- Note: editing the source (the tests) and re-running the generator moved the figure
  365 -> 368 with no hand-edit. That is the single-source property: a number lives in one
  generated place and follows its source, instead of being copied into N docs where it drifts.

## 2026-06-07 01:11 NEGATIVE CONTROL -- shared-evidence-discipline
- Command: `git worktree add --detach /tmp/sed2 HEAD && cd /tmp/sed2 && mv -f lib/verif-counts.sh docs/verification/COUNTS.md docs/verification/README.md /tmp/ && bash tests/test-meta.sh`  (throwaway worktree; removed after; shared checkout untouched)
- Exit: 1
- Output (excerpt):
  ```
  FAIL lib/verif-counts.sh exists and is executable
  FAIL COUNTS.md carries the generated single-source block
  FAIL convention names the experiment sibling + single-source borrow
  Failed: 9
  ```
- Verdict: RED-as-expected (remove the single-source impl -> its 3 pins fail)
- Note: proves the pins bite; the green above is not trivially green.

## Provenance
- This is the QC twin of the experiment's falsifiability check
  (`ops-toolkit/experiments/codebase-tool-benchmark/`, the Falsifiability section in its
  TEST-REPORT). Both are recorded, reproducible, and able to fail. See the "Sibling
  discipline" section in `docs/verification/README.md`.
- Reproduce: `bash lib/verif-counts.sh` (regenerates COUNTS.md from the live suites).
