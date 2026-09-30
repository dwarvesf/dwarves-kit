# Implementation notes: adopt pointer and two-idea tour

Only decisions, deviations, tradeoffs and open questions that differ from the spec.

| # | Note |
|---|---|
| 1 | Premise check: `lib/adopt.sh:179` hard exit, `:203-207` copy, `:197` import, `tests/test-adopt.sh:37-41` and `:86-96` all match the spec. All 28 historical `AGENTS.md` versions start with `# AGENTS.md: the operating layer`. |
| 2 | Ledger: `gate-ledger.sh record` accepts only `ran` or `skipped`. The Build start is recorded as `Build ran "start"`. |
| 3 | Commit subjects of the three implementation commits (`c70595e2`, `7742b870`, `dcced8f6`) are wrong: a stale message file was reused under noclobber. Content is correct (adopt.sh and tests, onboarding-cost.sh, onboard.md and adopt.md). No amend allowed, so the subjects stay. |
| 4 | `tests/test-meta.sh` has 1 failure: `docs/FEATURES.md is fresh`. The drift is the spec-ref counts on `/kit:adopt` and `/kit:design` rows, which grow when a new spec names those commands. `docs/FEATURES.md` is outside this spec's Touches, so it is not regenerated here. The lead runs `feature-registry.sh check --fix`. |
| 5 | AC-7 (`RESULT.md`, J2 and Claude Code runs) is left for the lead: post-build measurement. |
| 6 | Review fixes: template-missing guard, tmp + mv pointer writes that exit 1 on failure, refusal to adopt the kit's own tree (`pwd -P` against SRC_ROOT and KIT_ROOT), CR and BOM stripped before the first-line match. Tests added for each, plus CRLF and BOM old copies. |
| 7 | Single-source (amendment, lead-approved): the operator config sets `single_source = true`, and the first build exited 1 there on an empty target. Now AGENTS.md is the pointer plus folded notes, CLAUDE.md stays the one-line import, an existing AGENTS.md is never rewritten. The operate-contract block is skipped when AGENTS.md starts with the pointer marker: pointer plus block is over the 1200 byte cap (AC-1). `is_adopted` accepts the pointer marker in single-source mode. A legacy AGENTS.md with a block still gets its block refreshed. Tests 19, 22-26 and T7 changed to match. |
| 8 | The knob tests edited the tracked `kit.toml` in place. They now run a temp copy of the kit tree (lib, kit.toml, AGENTS.md). |
| 9 | `.github/workflows/test.yml`: `fetch-depth: 0` on checkout so the known-list test runs in CI. |
| 10 | FEATURES freshness: the lead regenerated it; `feature-registry.sh check` says fresh here after these changes. The earlier meta FAIL matched the drift from the spec-ref counts, not a separate cause. See the final meta run in the report. |
