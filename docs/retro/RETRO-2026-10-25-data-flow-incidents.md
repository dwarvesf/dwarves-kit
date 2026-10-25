# Retro: data-flow incidents moved out of the living doc
Date: 2026-10-25
Sprint: doc-drift fix batch; these paragraphs were incident narrative inside `docs/data-flow.md`

The invariants they produced stay in `docs/data-flow.md`. This file keeps the history. Paths named below describe the code as it was then; the staging hook has since been ported to bash plus jq and `hooks/backlog-stage.py` no longer exists.

## Metrics
- Lifecycle diagrams found by a 2026-07-14 sweep: 14, with zero data-flow diagrams. That gap is why `docs/data-flow.md` was written.
- Forged-block hole: one candidate in, two proposals out. Fixed 2026-07-15.
- Queue journal path: wrong default until 2026-07-14.

## What worked
- Drawing the data-flow diagram exposed a writer the lint could not see. That is the origin of the shared-module rule (C5) and the shared log-dir resolver (C6) in `docs/kit-contract.md`.
- A negative control that plants a private renderer proves the shared module is loaded, not just named.

## What hurt
- **Private renderer copies drifted, and one became a hole.** `hooks/backlog-stage.py` and `lib/stats/.../anomalies.py` each kept their own `render_block` and `render_candidate`. The shared renderer learned to collapse whitespace per field, a guard added when these fields began to carry LLM-extracted transcript text. The copies did not learn it. The hook's bare `.strip()` let an embedded newline forge a second `## [staged]` block. The forged block looked real to `board promote`.
- Cleanup after the fix: `anomalies.py` and `add-backlog` load the one module. `add-backlog` had kept its own `parse_staging`; it reads blocks through `parse_blocks` now.
- **The queue journal lived under the plugin dir.** `queue.sh` defaulted its journal and logs under `~/.claude/dwarves-kit/` until 2026-07-14. A plugin reinstall wipes that directory. The journal is the queue's idempotency state, so a wipe re-ran completed work. Moving every path behind `kit_resolve_log_dir` (SPEC-097) fixed it, and C6 lints for the pattern.

## Action items
- None open. Both fixes are pinned by tests and by the kit-contract lint.
