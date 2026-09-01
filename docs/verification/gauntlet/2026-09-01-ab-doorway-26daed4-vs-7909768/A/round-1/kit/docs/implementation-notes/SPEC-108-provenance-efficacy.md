# Implementation notes: SPEC-108 provenance-efficacy

Delta from the spec. References, does not restate.

## 2026-07-03 spec-validate findings resolved (4)

- **F1 (HIGH, wiring gate):** the first draft proved the emit with `grep 'generated-by'
  commands/draft-agent.md` , word-presence, not a NEW-generation fixture (the c6fbd99 orphan
  class). Fix: reused the EXISTING install-sim seam in `tests/test-meta-agent.sh:79-89` (which
  already strips the DRAFT marker and lints the result as a live agent) , added a stamp step
  (`awk` inject after `model:`) + a well-formed `generated-by` assertion + a re-lint. This proves
  the install PATH emits a well-formed key on a NEW (post-install) agent, by fixture. The golden
  DRAFT fixture (`drafted-agent.md`) deliberately does NOT carry the key (it is pre-install; the
  stamp is a Step-4 install act).
- **F2 (MODERATE, silent spread):** added a SET-EQUALITY guard to `test-meta.sh` , the set of
  `agents/*.md` carrying `generated-by:` must EQUAL the known generated roster (the 5). Catches
  both silent spread (someone clones advisor.md as a template and keeps the line) AND silent
  vanish. The goal's "negative control" (lint tolerates the key) is preserved separately (test-meta
  stays green with the key).
- **F3 (LOW, metric 11):** renamed "catch RATE" -> "catch COUNT" (catches-only v1 has no dispatch
  denominator; a rate label would make any `<X%` threshold meaningless); embedded the LITERAL
  copy-pasteable grep in SPEC-073 `## Amendments` (AC2: every figure traces to a command); stated
  the metric-6 distinction (per-lens curve vs per-generated-agent count, same source, different cut).
- **F4 (INFO, YAML):** the awk lints tolerate any key, but real CC parses frontmatter as YAML , a
  colon-space in `<context>` breaks an unquoted scalar. The 5 backfill contexts are colon-free
  (commas, not colons), and draft-agent Step 4.2's stamp instruction explicitly forbids colons in
  `<context>`.

## Notes

- Metric 11 v1 is a COARSE name-match count (`grep -rIl "$agent" docs/verification/`); a
  Re-audit-line-scoped refinement is a future tightening if the count proves noisy (noted in the
  SPEC-073 amendment). The dispatch-count ACTION line stays OUT (filed to mega NOTES).
- The install-sim's stamp value uses a colon-free context too (`install-sim fixture (SPEC-108)`),
  matching the rule the real emit must follow.
