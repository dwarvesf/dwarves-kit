# Implementation notes -- shared-evidence-discipline

Cross-pollinate the two evidence systems built this session: proof-of-done (dwarves-kit)
and the tool-eval-experiment / benchmark (ops-toolkit + chezmoi skill). Two borrows, kept
distinct (confirmation vs comparison).

## 2026-06-07 The reproducibility + single-source halves already existed; the gaps were narrow
- Context: the experiment side already had reproducibility-rerun (`*2.json`, skill "Core rigor") AND a single-source generator (`gen_docs.py`). The proof-of-done side already had the negative control.
- Decision: do NOT reinvent. The genuine gaps were (a) the experiment lacked a RECORDED falsifiability check (it had "avoid trivial markers" as advice only), and (b) proof-of-done hand-typed its numbers. So: experiment <- a recorded falsifiability check (negative-control twin); proof-of-done <- single-source numbers (gen pattern). Plus mutual sibling xref.
- Why: honesty , claim only the new work, not the parts that already shipped.

## 2026-06-07 proof-of-done single-source = generate suite counts, link not transcribe
- Decision/Change: `lib/verif-counts.sh` runs the suites and writes pass counts into the GEN block of `docs/verification/COUNTS.md`; verification logs link there. Demonstrated the regenerate by adding this feature's own 3 meta pins (365 -> 368) and re-running , the figure followed the source with no hand-edit.
- Alternatives considered: a full gen_docs.py-style generator over all log numbers (rejected: over-engineering for a verification log, violates the quality bar "no build system for a log"). One small counts generator is the minimum that proves the borrow.
- Note: kept the meta-pin NON-circular , it checks COUNTS.md HAS a GEN block, not that the number matches the live suite (that would be a fragile self-referential assertion).

## 2026-06-07 experiment falsifiability = query a marker where the answer is absent
- Decision/Change: `harness/probes/falsifiability.py` queries each marker in the positive project (present -> hit 1) and a negative project (absent -> hit 0); `results/falsifiability.json` (2/2 falsifiable, rerun identical); folded into `gen_docs.py` so the numbers are single-sourced into TEST-REPORT.md.
- Why: the eval twin of the proof-of-done negative control , a marker that cannot fail measures nothing. Reused the live codebase-memory-mcp index (ops-toolkit vs dwarves-kit) for a real present/absent contrast.
