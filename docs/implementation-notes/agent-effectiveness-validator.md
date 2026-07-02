# Implementation notes: SPEC-088 agent-effectiveness validator (kit-hardening SG-01)

Delta from SPEC-088. Decisions the spec did not pin down.

## 2026-07-02 Agent model tier = sonnet (not opus)

Context: the sub-goal's `Model: opus / Effort: high` header governs the LOOP work
(how the validator is built), not the validator agent's own `model:` tier.
Decision: `agents/agent-effectiveness.md` declares `model: sonnet`.
Why: the quality bar says it must read as a sibling of `integration-checker` /
`doc-verifier`, both `sonnet`. The four-lens check is bounded judgment over one
`.md` file, not deep architectural reasoning. This is itself the Tier lens applied
to the validator: cheap-first (WORKFLOW.md verification cost routing).
Alternatives: opus (rejected, over-tiered for a bounded per-file lint-plus-judgment).

## 2026-07-02 Test is prompt-completeness + structure + wiring, not live-LLM

Context: AC1 (planted-bad flagged) / AC2 (roster clean) name LLM-judgment
outcomes; CI cannot dispatch a live Claude reviewer.
Decision: `test-agent-effectiveness.sh` follows the kit's established pattern
(`test-review-team-plants.sh`): plant a bad-agent fixture per lens, assert the
validator PROMPT carries the vocabulary/lens to name each defect class, and assert
the good fixture + the prompt's "do NOT false-positive" guards. AC3/AC4/AC5 are
fully deterministic (grep the frontmatter tools, the fail-safe posture, the
diff-keyed wiring).
Why: matches the kit's honest CI position ("we test prompt completeness because we
cannot dispatch a live reviewer in CI"), stated verbatim in test-review-team-plants.sh.
Impact: the fixtures also carry the literal defect (an over-grant fixture really
contains `Write`) so a grep proves the fixture represents the class, not just names it.

## 2026-07-02 Diff-keyed wiring (T2) lives in commands/draft-agent.md

Context: SPEC-088 T2 says "wire it diff-keyed into the phase where agents are
authored/changed".
Decision: added a validation step to `commands/draft-agent.md` (the meta-agent
command, the only agent-authoring phase). It dispatches `agent-effectiveness` on
the just-installed/changed agent def only, advisory + ship-visible, mirroring how
`/kit:docs` dispatches `doc-verifier` at its Step 4.5.
Why: draft-agent is the single point new/changed agent defs enter the repo; keying
on that phase IS the diff-keying (per-agent, not every-agent-every-run).

## 2026-07-02 Verdict vocabulary: PASS / FLAGGED / UNVALIDATED

Context: siblings use PASS / FAIL:fixable / FAIL:escalate; SPEC-088 adds the
fail-safe `unvalidated` state.
Decision: the validator emits PASS, FLAGGED (defects with file:line), or
UNVALIDATED (infra failure / could not complete a lens). UNVALIDATED is explicitly
"never a silent pass; treat as live-risk" (AC4).
Why: the fail-safe state is a first-class verdict, not a sub-case of FAIL, so a run
that could not judge is visibly distinct from a run that judged clean.
