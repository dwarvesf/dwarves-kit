# Implementation notes: example-guide-facts

Delta from the audit, not a mirror.

## Decisions
- hello-spec `AGENTS.md` is byte-identical to `lib/adopt/AGENTS.pointer.md`; `WORKFLOW.md`, `docs/verification/README.md` and `.kit.toml` come from a real `lib/adopt.sh --no-single-source` run in a temp repo. A new pin in `tests/test-meta-contract.sh` compares the example `AGENTS.md` to the pointer template, so it cannot drift again.
- The ambient operator config turned `single_source` and two extra gates on in my adopt run. I reran with `--no-single-source` and set `understanding_gate` and `commit_format` back to false in the example `.kit.toml`, so the example shows the shipped defaults.
- Example `CLAUDE.md` gains the `kit:adopt` loader block adopt appends; its own project content is unchanged.
- SPEC-001 keeps `TASK-001` ids (the kit's own specs use them; the audit noted the template's `TASK-A` is the odd one out). Normal lane, so `Picture`, `Failure modes` and `Amendments` are omitted; `Design` is the one-line `obvious:` form.
- Two pins changed because the old text is gone: the four-zone headings and `Pause if` in the example `AGENTS.md`, and `docs/specs/` in the example `WORKFLOW.md`. Message strings avoid the exact token "adopt pointer" so `docs/FEATURES.md` stays fresh.
- Cheap-probe recipe moved to `tests/gauntlet/deploy/README.md` with a generic provider (`cheap`, `<endpoint-host>`, `<model-id>`); the tutorial keeps a pointer plus the `watch.sh` line. The unverifiable "proven" claim is now a hedge, not a dated fact.
- `gates-and-proof.md` gains a "four hard stops" list and a separate "advises, never blocks" block for the spec-drift guard.
- `dispatch-vs-mega.md` has a prerequisites box (a second ASCII block in that guide).

## Skipped
- Audit row 29 (gauntlet.md has no diagram): a planted gauntlet gap (`tests/gauntlet/seed-card-contributor.md`). Row 32 (a template sentence) was not in the slice.
- Guide merges, new guides (adopt, wrap, review), impl-playbook index: not in the slice.

## Open questions
- `kit.toml` ships a private 1P vault path as the default `probe_key_ref`. The tutorial now says to set your own, but the shipped default still needs a placeholder (cross-slice).
