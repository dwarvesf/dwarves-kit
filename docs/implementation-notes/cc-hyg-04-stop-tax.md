# Implementation notes cc-hyg-04 (delta from spec)

## Decisions the spec left open

- **slop-cleaner: kept, not dropped.** The bloat signal is worth keeping; only the
  repetition was the tax. Resolution memory fixes the repetition without losing the
  signal.
- **session-state-save: change-gated debounce chosen** over time-debounce (staleness
  risk) and over keep-every-Stop (the 38 min/month churn the mega-goal targets).

## Deltas discovered during build

1. **session-state fingerprint must exclude the hook's own output.** First cut used
   `git status --porcelain | wc -l`, but that counts the untracked
   `.claude/session-state/` files the hook itself writes, so the fingerprint changed
   every run and the debounce never fired. Also git collapses a wholly-untracked dir
   to a single `?? .claude/` line, so a plain `grep -vF '.claude/session-state/'`
   missed it. Fix: `git status --porcelain --untracked-files=all` (lists individual
   files) then filter `.claude/session-state/`. Caught by the debounce test failing.

2. **override rejection is deploy-path-aware, not extension-only.** First cut rejected
   any override whose remainder had a source-code EXTENSION. That broke
   `test-deployable-done.sh` AC4 (a `deploy/rollout.sh` is a `.sh`, but a deploy
   script is override-able by design , SPEC-095 verifies deploy via deploy-proof/UAT,
   and the override is the sanctioned manual-verification escape). Fix: exclude files
   under a `deploy/` path from the source-remainder check. So: source code OUTSIDE
   `deploy/` -> reject (the rtk-611 case, a `lib/` change); anything under `deploy/`
   or any non-code file -> still override-able. Reconciles cc-hyg-04 with SPEC-095.

3. **Test signal for the debounce = the DEBUG "skipping" line, not archive count.**
   Archive filenames are `state-<YYYYmmdd-HHMMSS>.md` (1s resolution); rapid test runs
   collide on the same name, so counting archives is flaky. The test runs the hook with
   `DWARVES_KIT_DEBUG=1` and asserts the "skipping" message appears/absents instead.

## Tests added

- `test-hooks.sh`: slop resolution memory (report once / silent on unchanged /
  re-flag on content change); session-state change-gated debounce (skip unchanged /
  write after a real change); proof-ledger override (source -> REJECTED,
  deploy-inert -> PASS).
- `test-deployable-done.sh` AC4b: override on NON-deploy source is still rejected.

## Proof

See `docs/proof-of-done.md` (co-located per SPEC-016 style): full CI run-table,
all 11 suites green.

## Adversarial review round (kit:security-reviewer, REVISE -> fixed)

The security review reproduced three real bypasses against the first cut; all fixed
+ covered by new tests (test-hooks 445 -> 449):

1. **`deploy/` exemption was a substring match at any depth** (`grep -vE '(^|/)deploy/'`)
   -> `src/deploy/core.py` (real app logic) bypassed rejection, reopening rtk-611.
   Fix: exempt only SANCTIONED deploy locations via `case`: `deploy/*` (repo root) or
   `tools/*/deploy/*` (per-tool). Nested `src/deploy/`, `lib/deploy/` are NOT exempt.
2. **Extensionless shebang scripts bypassed the extension regex** (the kit's own
   `lib/goal/handoff-gen` is such a file). Fix: a file with no dot in its basename counts
   as source if it is a shebang script (`head -c2 == '#!'`).
3. **session-state debounce used a dirty-file COUNT** -> further edits to an
   already-dirty file (count unchanged) were silently skipped, staling crash recovery
   for a single-file editing streak. Fix: fingerprint the CONTENT (hash of
   `git diff HEAD` + the untracked list, minus `.claude/session-state/`), not a count.

New tests: proof-ledger (c) nested-deploy REJECTED, (c2) tools/*/deploy PASS, (d)
extensionless shebang REJECTED; session-state content-change-to-already-dirty-file
re-saves.

## Spec/impl-notes naming

Named `cc-hyg-04-*` (not the next `SPEC-099`) to avoid colliding with the concurrent
kit-telemetry mega-goal's SPEC numbering; marks its cc-hygiene provenance.
