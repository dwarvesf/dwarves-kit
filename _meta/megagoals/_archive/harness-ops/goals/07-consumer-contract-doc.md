# Sub-goal 07: consumer-contract-doc

**Merge policy:** auto
**Time budget:** 1-2 hours
**Proof:** the rendered `docs/consumer-contract.md` + a check that its claimed files match what `/kit:adopt` actually injects (doc-vs-code). Rung 2 (doc-verifier style).
**Design:** obvious
**Depends on:** 05, 06
Model: sonnet
**Branch:** feat/harness-ops-07-contract-doc
**PR base:** main

## Outcome

`docs/consumer-contract.md` is the one page that tells a new project/machine exactly what to have to use the kit: the 4 adopt-injected files (AGENTS.md copy, CLAUDE.md kit-block, WORKFLOW.md pointer, docs/verification/README.md marker), the `KIT_LEDGER_DIR` knob (shared vs per-project), and the optional `<project>/.kit.toml` override. It reflects the FINAL state after 05/06 (stable entrypoint + project override), not the pre-work state.

## How to close the loop

- Write `docs/consumer-contract.md`: the 4 required files (what each is, copy vs pointer), the ledger knob, the `.kit.toml` override, and the stable entrypoint (from 05). One page, skimmable.
- Verify doc-vs-code: assert the 4 files it names are exactly what `lib/adopt.sh` injects (grep adopt.sh); no drift.
- Capture the check (the doc's file list == adopt's injected set).

**Done =** `docs/consumer-contract.md` exists and its named contract (4 files + KIT_LEDGER_DIR + .kit.toml + stable entrypoint) matches what `lib/adopt.sh` actually injects (captured doc-vs-code check).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → next Track-A remaining / Track-B; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** `docs/consumer-contract.md`.
**Out:** the adopt mechanics (05/06), the config schema (kit.toml.example).
**Not:** re-documenting the whole kit, duplicating AGENTS.md, a tutorial.

## PR body

Adds `docs/consumer-contract.md`, one page for onboarding a new project/machine (4 adopt files + KIT_LEDGER_DIR + optional `.kit.toml` + the stable entrypoint), verified against what `lib/adopt.sh` injects. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
