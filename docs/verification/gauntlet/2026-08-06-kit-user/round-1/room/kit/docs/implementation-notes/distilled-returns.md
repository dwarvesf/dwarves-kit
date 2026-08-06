# Impl notes: distilled subagent returns (SG-04)

Delta from SPEC-087 Mechanism C. Only off-spec calls live here.

## 2026-06-29 contract appended to ALL agents/*.md, not only the 4 named
- Context: the goal's verification grep names worker/task-verifier/integration-checker/reviewer;
  the scope line says "across dispatched roles".
- Decision: append the `## Return contract` block to every `agents/*.md` (all are dispatched
  subagent defs), so the lead's growth is bounded no matter which role it spawns. Worker has no
  agent file -> its contract goes in `commands/execute.md` dispatch prose.
- Why: a partial rollout leaves the high-volume roles (research-*, security-auditor) dumping.

## 2026-06-29 block APPENDED at end, not inserted before ## Rules
- Decision: append the section at the end of each file rather than splicing before `## Rules`.
- Why: 11 files with different internal structure; a uniform append is mechanical and low-risk.
  Cost: the existing `Source:` footer is no longer the literal last line in files that had one.
  Accepted as cosmetic; the contract reads fine as the closing section.
- Alternative rejected: 11 bespoke "insert before X" edits, higher chance of a mis-splice for
  no real gain.

## 2026-06-29 "subagent is not automatically cheaper" decision rule
- Placed in SPEC-087 Mechanism C (design rationale) + a one-liner in execute.md, not in every
  agent def (it governs WHEN the lead dispatches, not how a role returns). Source:
  research/2026-06-28-token-efficient-design.md Part 1.

## 2026-06-29 verification grep adapted
- The goal's grep lists `agents/worker.md`, which does not exist. Proof uses the real file set
  + an explicit check that execute.md carries the worker return contract.
