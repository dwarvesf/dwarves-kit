# Implementation notes: adopt pointer and two-idea tour

Only decisions, deviations, tradeoffs and open questions that differ from the spec.

| # | Note |
|---|---|
| 1 | Premise check: `lib/adopt.sh:179` hard exit, `:203-207` copy, `:197` import, `tests/test-adopt.sh:37-41` and `:86-96` all match the spec. All 28 historical `AGENTS.md` versions start with `# AGENTS.md: the operating layer`. |
| 2 | Ledger: `gate-ledger.sh record` accepts only `ran` or `skipped`. The Build start is recorded as `Build ran "start"`. |
| 3 | Commit subjects of the three implementation commits (`c70595e2`, `7742b870`, `dcced8f6`) are wrong: a stale message file was reused under noclobber. Content is correct (adopt.sh and tests, onboarding-cost.sh, onboard.md and adopt.md). No amend allowed, so the subjects stay. |
| 4 | `tests/test-meta.sh` has 1 failure: `docs/FEATURES.md is fresh`. The drift is the spec-ref counts on `/kit:adopt` and `/kit:design` rows, which grow when a new spec names those commands. `docs/FEATURES.md` is outside this spec's Touches, so it is not regenerated here. The lead runs `feature-registry.sh check --fix`. |
| 5 | AC-7 (`RESULT.md`, J2 and Claude Code runs) is left for the lead: post-build measurement. |
