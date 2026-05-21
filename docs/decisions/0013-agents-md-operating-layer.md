# ADR-0013: AGENTS.md as the tool-agnostic operating-layer entrypoint

## Status: proposed (2026-05-21).

## Context
A study of `hoangnb24/harness-experimental` (OpenAI "harness engineering" framing) showed an operator writing a rich, multi-section `/goal` (Context to read first / Constraints / Operating rules / Validation loop / Done when / Pause if) and running it reliably against a brownfield repo. That altitude is not prompt skill. Each section is a pointer to a *named artifact* the harness installs into the consuming repo: an ordered source-of-truth list, a feature-intake/risk doc, a test matrix, a done-definition, and an "ask before" list, all anchored by a single agent entrypoint, `AGENTS.md`. The operator references structure the repo already carries; they do not invent it in the prompt.

dwarves-kit today out-enforces that harness (the hooks, verifier, and push-blocker are real guardrails; theirs is advisory markdown) but under-ships the *legible in-repo operating layer a `/goal` can point at*:
- The kit's entrypoint is `CLAUDE.md` (+ `WORKFLOW.md`), which is Claude-Code-specific. There is no tool-agnostic entrypoint.
- "Pause if" / ask-before-a-human is enforced by safety hooks but never stated as a directive the goal can mirror.
- There is no brownfield "review the codebase and backfill docs" entry; the cycle is greenfield-feature oriented (`/think -> /spec`).

This is the operating-layer half of the v3.x "multi-runtime support (Codex, Gemini)" roadmap item (PHILOSOPHY section 5), brought forward.

## Decision
Adopt `AGENTS.md` as the kit's tool-agnostic operating-layer entrypoint, shipped into consuming repos.

1. **`AGENTS.md` is the front door.** It carries the portable operate-contract: the ordered source-of-truth read list, the task loop, the done-definition, and the explicit "Pause if / ask a human before" list. Plain markdown, readable by any agent runtime (Claude Code, Codex, Gemini), not just Claude Code.

2. **Layering, no duplication (replace, don't duplicate).**
   - `AGENTS.md` - tool-agnostic operate-contract (read order, task loop, done, pause-if). Canonical for *what to read and how to operate*.
   - `CLAUDE.md` - thin Claude-Code-specific layer (the bits that are CC-only: hooks, slash commands, plugin). Points to `AGENTS.md` for the operate-contract; does not restate it.
   - `WORKFLOW.md` - the cycle / lanes / gates detail (role unchanged). `AGENTS.md` points to it for lane selection.

   This mirrors harness-experimental's `AGENTS.md -> HARNESS.md` split and the Codex / obra-superpowers `AGENTS.md`-canonical convention.

3. **No empty content scaffolds (PHILOSOPHY: every file must justify itself).** The kit does NOT ship empty `docs/product/`, `docs/stories/`, or `TEST_MATRIX.md` homes. `AGENTS.md` names the homes the kit *already* has (`docs/specs/`, `docs/decisions/`, `CHANGELOG.md`, the verifier pipeline) plus the on-demand homes the work creates. Content homes are created when real content exists to fill them, which is also harness-experimental's own rule ("those should arrive only when a selected story needs them", HARNESS.md). What ships is the entrypoint + templates + a brownfield backfill lane, not phantom folders.

4. **Brownfield backfill becomes a first-class lane.** `WORKFLOW.md` gains a `backfill` entry: review an existing codebase and write the operating layer (the AGENTS.md homes: product/architecture/test-matrix docs) without changing application behavior. This is the exact use case in the trigger screenshot.

5. **The rich `/goal` is generated, not hand-written.** The kit's goal-crafter (`/user:assign` + the `.claude/goals/<slug>.md` draft body, ADR-0011) emits the six-section directive shape, each section pointing at `AGENTS.md`'s named artifacts. The operator gets the altitude for free because the vocabulary lives in the repo.

6. **Honest scope of "tool-agnostic."** Portability covers the *read/operate contract* (markdown any runtime reads). It does NOT make the *guardrails* portable: the hooks (safety-gate, push-blocker, anti-rationalization, verifier) are Claude-Code-only. Under Codex/Gemini, `AGENTS.md` is advisory; enforcement stays a Claude-Code feature until the v3.x agent-hook / Codex-hook work lands. We add portable guidance, not portable guardrails, and must not over-claim.

## Alternatives considered
- **Keep CLAUDE.md canonical, add AGENTS.md as a pointer to it.** Keeps Claude coupling and defeats portability (a Codex agent reading AGENTS.md gets redirected to a CC-specific file). Rejected.
- **Both files carry the full operate-contract.** Duplication; the two drift. Violates "replace, don't deprecate." Rejected.
- **Ship the full harness-experimental scaffold (empty product/stories/test-matrix).** Violates "every file must justify its existence" + "no phantom features." Their product *is* the scaffold; ours isn't. Rejected.
- **Do nothing; rely on the existing goal-craft prose.** Leaves the operator hand-writing structure every time with no in-repo referent; never reaches the altitude. Rejected.

## Consequences
- Downstream repos get a single, portable agent entrypoint; the rich `/goal` becomes writable (and generatable) because its sections point at named artifacts.
- Brownfield adoption (install the kit into an existing repo, backfill the operating layer) is now a documented flow, not an improvisation.
- `CLAUDE.md` shrinks to a CC-specific pointer; some current operate-contract prose moves to `AGENTS.md`. The `install.sh` tip and the WORKFLOW doc-impact map must update.
- Initiates the v3.x multi-runtime direction at the operating-layer level while explicitly deferring portable enforcement. Sets an expectation we must not over-claim ("works with Codex" means *reads* with Codex, not *enforced* under Codex).
- A new top-level downstream file (`AGENTS.md`) means the doc-impact map (WORKFLOW.md), README "Project structure", `docs/architecture.md`, and the `examples/hello-spec/` template must all gain it.

## Source
`hoangnb24/harness-experimental` (its `AGENTS.md` / `HARNESS.md` / `FEATURE_INTAKE.md` operating model; OpenAI "harness engineering"). The `AGENTS.md` convention (OpenAI Codex; obra/superpowers `AGENTS.md` v5.1.0). PHILOSOPHY section 5 v3.x "multi-runtime support". Builds on ADR-0010 (spec location), ADR-0011 (goal-draft store), SPEC-006 (orchestration spine).
