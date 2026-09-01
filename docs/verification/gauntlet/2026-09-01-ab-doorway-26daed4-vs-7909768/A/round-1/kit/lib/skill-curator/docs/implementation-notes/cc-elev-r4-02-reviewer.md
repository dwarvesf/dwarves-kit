# Implementation notes: skill-curator Phase A reviewer (cc-elevation-r4 sub-goal 02)

Delta from SPEC-103 (TASK-001..005) + goal `02-skill-reviewer.md`. Only what the spec does NOT pin.

## 2026-06-19, CONTEXT.md `--allowedTools Read,Write` was stale; DEC-008 wins
- At build time CONTEXT.md still listed `--allowedTools Read,Write` (pre-DEC-008). The reviewer runs
  `--allowedTools ""` (no model write) per SPEC-103 DEC-008 + Interfaces invariant. Followed DEC-008.
  (CONTEXT.md was corrected to `--allowedTools ""` in the 04 doc pass after a doc-verifier flagged it;
  see ADR-0001.)

## 2026-06-19, wrapper-side secret scan (defense in depth beyond prompt + promote)
- Spec puts the secret guard in the reviewer PROMPT + the promote checklist. With the model mocked
  in tests, "no draft contains a seeded secret" cannot be proven against the prompt alone.
- Decision: the trusted wrapper (`reviewer-run.sh`) scans a returned draft body for high-precision
  secret patterns (sk-ant-, sk-…, AKIA…, ghp_…, xox[bp]-, JWT eyJ…, PEM private key, AIza…) and
  DROPS the whole draft (logs, ledger `dropped:secret`, no write) if any match. Makes the control a
  hard wrapper guarantee + testable with a mock.
- Alternatives: redact-in-place (risks shipping a half-secret); prompt-only (untestable). Rejected.

## 2026-06-19, test seam `SKILL_CURATOR_REVIEWER_CMD` mirrors cc-harvest's `CC_HARVEST_EXTRACTOR`
- The `claude -p` call is isolated behind `SKILL_CURATOR_REVIEWER_CMD` (reads prompt on stdin, emits a
  `claude -p --output-format json` ENVELOPE on stdout). Tests build envelopes with `jq -n` (no hand
  escaping) and point the seam at `cat <fixture>`. The default is the real claude invocation.

## 2026-06-19, two-layer JSON parse
- Outer: the `claude -p --output-format json` envelope gives `.total_cost_usd` + `.usage` (cost is
  logged from the envelope, the first-class cost-observability AC) and `.result` (the model's text).
- Inner: `.result` is itself the model's JSON `{draft:{slug,name,description,body}|null, reason}`.
  The wrapper parses both; a failure at either layer logs and exits 0 (no partial draft).

## 2026-06-19, scaffolded the ops-tool-shape layout manually
- Built the `bin/ hooks/ lib/ prompts/ config/ tests/ docs/` layout + tool.toml + README + gitignore
  by hand (matching CONTEXT.md "Key files") rather than invoking the `ops-tool-shape` skill, for
  loop speed. Layout is the same standard; audit-compatible.

## 2026-06-19, Phase A scope: basic async check only
- Goal 02 owes "a basic async check"; the full `test-async.sh` / `test-reentrancy.sh` /
  `test-staging-gate.sh` are TASK-006/009 (sub-goal 03). Phase A ships `test-transcript-parse.sh` +
  `test-reviewer.sh` (draft / null / secret-drop / ledger) + a basic hook-returns-fast check.

## 2026-06-19, cross-loop isolation (same as 01)
- Runs in a worktree off origin/main; never mutates the OBS-owned main checkout. ROADMAP/NOTES
  bookkeeping rides in-branch. 02 is the base of the 02->03->04 stack.
