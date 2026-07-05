# SG-06: enforce output-offload + deterministic-verify default

Merge policy: gate
Time budget: ~1 session
Depends on: (none hard)
Model: sonnet
Effort: medium

## Directional outcome
Stop the two cheap leaks the forensic found: thousands of >2k-token tool outputs riding in
context, and burning Opus on verification that a deterministic check (or a cheap model) could
do.

## Done =
(1) A PostToolUse hook (or a kit helper + guidance) that detects a tool output over ~2k tokens,
offloads the full payload to a file, and leaves a short pointer in context. (2) The kit's verify
guidance prefers deterministic checks (tests/lint) or a cheap-model verifier over Opus. A
test/assertion pins the offload threshold. PR opened.

## Close the loop (verification)
```
bash tests/<offload-test>.sh            # threshold: >2k offloaded, <=2k passes through
grep -ri 'deterministic\|cheap.*verif' WORKFLOW.md   # verify-routing guidance present
```

## Scope edges
The hook + the verify-routing doc only. Don't change WHAT gets verified, only on what (cheap vs
Opus). The offload must be reversible (full payload on disk, not dropped).

## Where to look
`hooks/`, the forensic >2k-tok finding (`research/2026-06-28-token-spend-forensic.md`),
`WORKFLOW.md` verify lane.

## Proof expectation
A test run-table for the threshold + a captured example of an offloaded output (the pointer in
context, the full payload on disk). Full reviewable proof (behavioral).

## PR body
feat(kit): enforce >2k-token output offload + deterministic-verify default. Gated for team
review.

## From the token-efficient note (2026-06-29)
Use the NATIVE lever first: `BASH_MAX_OUTPUT_LENGTH` caps giant shell output at the source , wire
/ document it rather than reinventing truncation. The hook handles non-Bash tool outputs + the
file-offload pointer. See `research/2026-06-28-token-efficient-design.md` Part 4 + quick-ops.
