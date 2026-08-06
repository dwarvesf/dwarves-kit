# Implementation notes: prose-rag auto-inject gate (cc-elevation-r2 sub-goal 03)

Delta from `_meta/megagoals/cc-elevation-r2/goals/03-prose-rag-autoinject.md`. The base tool (index/query/hook) is the cc-elevation sub-goal 03 (see `03-prose-rag.md`); this note only covers the controlled-activation delta.

## 2026-06-15 Gate is precision-biased, not recall-complete
- Decision: `looks_like_recall()` matches an explicit recall-phrase list ("have i written", "did i already", "what did i conclude", ...). It deliberately does NOT try to catch research-shaped questions ("how does X work") because those overlap with operational prompts and would re-introduce the per-prompt tax.
- Why: the quality bar is "no latency tax on operational prompts". Precision (skip almost everything) beats recall here; a missed recall prompt costs nothing because the `prose-rag` skill still does explicit on-demand retrieval.
- Impact: tune the marker list over time from real misses; it is data, not logic.

## 2026-06-15 Opt-in master switch is an env, default OFF
- Decision: the hook is inert unless `PROSE_RAG_INJECT=1` (or `--force` for tests). `--no-gate` / `PROSE_RAG_NO_GATE=1` bypasses the recall gate.
- Why: lets the hook be wired into `settings.json` but stay dormant until I flip the env (controlled rollout). The spec said "behind an opt-in env flag"; this is the chosen name + semantics.
- Impact: deploy = wire the hook AND export `PROSE_RAG_INJECT=1` when ready. Wiring alone does nothing.

## 2026-06-15 Reworked existing smoke [5]/[6] instead of leaving them
- Change: the cc-elevation smoke [5]/[6] drove `hook` with a keyword prompt ("flarnium zorbnik...") that is NOT recall-phrased, so the new gate would skip it and the tests would break. Re-scoped them to `--force --no-gate` (they test retrieval, which is gate-independent) and added [8] (opt-in off), [9] (gate skips operational), [10] (gate passes recall).
- Why: [5]/[6] were always retrieval tests; the gate is a separate concern with its own tests. Conflating them would make a green [5] ambiguous.

## 2026-06-15 The "no model load" proof runs on plain python3
- Decision: smoke [9] runs the gated-out path with system `python3` (no venv), not `uv run`. If the gate did not short-circuit before `search()`, the script would `import fastembed`/`sqlite_vec` and crash (ModuleNotFoundError) -> non-zero. Exit 0 + silent is the proof that the embed never loads on an operational prompt.
- Measured: gated-out wall-clock ~44ms (python startup only) vs the ~250ms fastembed cold start on a fired prompt.

## 2026-06-15 Left search() import order + floors unchanged (surgical)
- `search()` still does `import sqlite_vec` before its db-existence check; a recall prompt with a missing index imports sqlite_vec (cheap) but never loads fastembed (the 250ms cost is after the db check). Not reordered: out of scope, and the gate already prevents the common operational case from reaching `search()` at all.
- Kept the hook floor at 0.62 (calibrated in cc-elevation). The spec said "tune the floor"; measurement showed no retune needed, so none made.
