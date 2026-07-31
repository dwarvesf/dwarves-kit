# Implementation notes: feature-registry (SPEC-217)

Delta log only; the spec carries the design.

## 2026-07-31 hook descriptions needed a fallback rule the spec did not pin

Context: SPEC-217 AC-3 says hook descriptions come from "the header comment". About half the hooks use `# name.sh -- desc`; others use `# name.sh, <desc>` or an em-dash separator (`statusline.sh`).
Decision: primary rule stays the ` -- ` convention; fallback takes the first comment line with the `<name>.sh` prefix and its separator stripped.
Why: deterministic, zero per-hook special cases; the fallback text is honest even when it reads like a role line ("PreToolUse hook, matcher: Bash").
Alternatives: normalizing every hook header (out of scope, touches ~14 files); leaving blanks (worse registry).
Impact: none on other rows.

## 2026-07-31 skills get the same disable-model-invocation rule as commands

Context: the dispatch design says "[I] skills" flatly, but skills carry `disable-model-invocation` frontmatter too (`skill-review` is `[H]` in docs/workflow-paths.md).
Decision: `true` -> `[H]` for skills as well; otherwise `[I]`.
Why: one rule, matches the hand-derived path index. Note: `skill-review`'s frontmatter is currently `false`, so the registry reports `[I]` while workflow-paths says `[H]`; the registry reports the machine truth, the discrepancy is a workflow-paths (or frontmatter) finding for Phase B.
Impact: Phase B's cross-check must expect this one known mismatch.

## 2026-07-31 refs are capped at 3 + "+N", and generation costs ~15-20s

Context: token-grep refs for hub commands (`/kit:spec` hits 130+ specs) would produce unreadable cells.
Decision: show first 3 (sorted) + `+N`; `-` for none. Generation runs one grep per feature per corpus (~19s total); the test-meta pin pays this once per suite run.
Why: registry is an index, not the record; determinism is preserved (sorted before capping).
Alternatives: full lists (unreadable), counts only (loses the entry point). A single-pass indexer would cut the 19s but is not worth the complexity yet.

## 2026-07-31 review round applied (reflect)

Two lenses (security, architecture+coverage) per SPEC-069. Security: PASS, one LOW (predictable temp name) fixed with an EXIT trap. Architecture: 8/10, MEDIUM (determinism only proven manually) fixed with a second-run cmp pin in test-meta; two LOWs deliberately not taken: the architecture.md subsystems-table omission is pre-existing drift across ~11 lib dirs (a doc-drift finding, not this PR's debt), and nullglob hardening guards a directory state this repo cannot reach. Reflect: the kit's own machinery held up; main friction was the full lane's 12-gate checklist for a change whose design arrived pre-approved, resolved with honest ledger overrides rather than ceremony re-runs.
