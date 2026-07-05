# Sub-goal 06: orchestrate-sweep (tiny batch: ID-095 + ID-096 + ID-098)

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** one run-table per item. ID-095 owes a named negative control (a secret-bearing surface): assert a secret-shaped line is redacted OR a stream past the age/rotation cap is pruned. ID-096/098 = a `Done =` evidence line each. Rung 2 for ID-095, rung 1 for the other two.
**Design:** obvious
**Depends on:** 05 (stacked for orchestrate.sh merge hygiene, no logical dep)
Model: sonnet
**Branch:** fix/orchfin-06-sweep
**PR base:** fix/orchfin-05-rid-check

## Outcome

Three small independent hardening fixes to the orchestrator, batched (each too small for its own PR):
- **ID-095**, `.orchestrate/*.stream.jsonl` gets a rotation/redaction cap. Verified reality: these are NOT "unbounded growth" (each file is per-sub-goal-id and truncated per run, so the set is bounded by sub-goal count) , the real risk is that secret-bearing transcripts SIT ON DISK with no age cap and no redaction. Fix: an age/rotation cap on the `.orchestrate` dir (prune streams older than N) and/or redact secret-shaped lines in the stream writer.
- **ID-096**, `_route` validates the `Model:` value against the allowlist PRE-FLIGHT and rejects an unknown tier before dispatch, instead of failing deep in a `claude -p` call.
- **ID-098**, the happy path cleans up its tmux window (`kill-window`) on success, so a clean run leaves no orphaned windows.

## Quality bar

Three papercuts gone. No secret-bearing stream lingering on disk past a rotation cap, no dispatch on a typo'd model tier, no orphaned tmux windows after a clean run. Each fix is small, guarded, and individually verified.

## How to close the loop

Each item keeps its OWN check line (individually auditable inside this sweep):

- **ID-095:** add an age/rotation cap on `.orchestrate` and/or secret redaction in the stream writer; test (NEGATIVE CONTROL): age a stream past the cap and assert it is pruned, OR write a secret-shaped line and assert it is redacted in the stored stream. Run-table row.
- **ID-096:** add the allowlist check to `_route`; test: pass an off-allowlist `Model:` value, assert `_route` rejects pre-flight (no dispatch). Run-table row.
- **ID-098:** add `tmux kill-window` to the happy-path exit; test: simulate a successful run, assert the window is gone. Run-table row.

**Done =** all three land with their own captured check: (a) stream.jsonl age/rotation cap prunes an over-age stream OR a secret-shaped line is redacted (negative control run-table), (b) `_route` rejects an off-allowlist `Model:` pre-flight, (c) happy-path exit kills its tmux window.

**Kit-adopted repo? Record the gates** (from dwarves-kit cwd, `lane-classify` → `tiny`/`small`; still record build+review via `gate-ledger.sh`).

## Handoff on completion

1. ROADMAP `[x]` + PR #. 2. This is the LAST sub-goal: overwrite `HANDOFF.md` noting the mega is at TIER-4 close. 3. Append `DECISIONS.md`. 4. Report, EXIT.

## Scope edges

**In:** the stream-writer retention (`.orchestrate/*.stream.jsonl`), `_route`'s Model allowlist, the happy-path tmux cleanup, all in `orchestrate.sh`.
**Out:** the stream FORMAT, the model allowlist's membership, the tmux control plane's attach logic.
**Not:** batching in unrelated fixes, a general logging refactor, adding retention to other dirs.

## Where to look

`lib/queue/orchestrate.sh`: the stream-writer (`.orchestrate/*.stream.jsonl`), `_route` (Model handling), the happy-path exit / tmux window handling.

## PR body

Tiny hardening sweep (ID-095 stream.jsonl retention cap + ID-096 Model allowlist pre-flight + ID-098 happy-path tmux cleanup). Verify: the three per-item run-tables (ID-095 with a secret-pruning negative control). Stacked on #<05 PR>; review after it. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes
