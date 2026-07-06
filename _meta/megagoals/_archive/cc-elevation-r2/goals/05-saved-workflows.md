# Sub-goal 05: Saved Workflows for recurring fan-outs

**Time budget:** ~3-4h
**Depends on:** none
**Branch:** feat/cc-elev-r2-05-workflows
**PR base:** main

## Outcome

Author 2-3 reusable named `Workflow` scripts for my recurring multi-agent fan-outs so I invoke them by name instead of re-improvising "ultracode" each time: `review-branch` (dimensions -> parallel review -> adversarial-verify each finding -> synthesize), `research-sweep` (multi-modal search -> deep-read -> synthesize), and `cross-repo-sweep` (one agent per repo -> consolidated digest). Each lives where the Workflow tool resolves named workflows (`.claude/workflows/`), authored in ops-toolkit and documented.

## Quality bar

Each workflow has a valid `meta` literal, uses pipeline/parallel correctly (pipeline by default), and smoke-runs end to end on a small input returning the expected consolidated shape. Documented so I know the name + what each does. No secrets baked in.

## How to close the loop

- Write the 2-3 workflow scripts + a short README mapping name -> purpose -> when to use.
- Smoke-run each on a tiny input (e.g. review-branch on a 1-file diff) and confirm it completes + returns the consolidated result; confirm an invalid input degrades gracefully (negative control).
- Lane via lane-classify; the new tool/dir owes a proof-of-done with the smoke runs.

**Done =** 2-3 named workflows (review-branch, research-sweep, cross-repo-sweep) exist, each with valid meta, each smoke-runs to a consolidated result, documented by name; proof-of-done; on PR #NN.

## Scope edges

**In:** the workflow scripts + README + proof.
**Out:** the meta-agent (08); changing ultracode opt-in; production runs on real large inputs.
**Not:** a library of every possible workflow (ship the 3 recurring ones; note others in Proposed additions).

## Where to look

The `Workflow` tool API (meta/phase/pipeline/parallel/agent), the cc-elevation adversarial-verify pattern (verify-claim), repo-sweep for the cross-repo shape, the Q1 discussion in this session (execution-half vs distillation-half).

## PR body

Outcome: 2-3 saved named Workflows for recurring fan-outs (review-branch, research-sweep, cross-repo-sweep), invocable by name.
Verify: each smoke-runs to a consolidated result; invalid input degrades gracefully; documented.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 05).

## Notes
