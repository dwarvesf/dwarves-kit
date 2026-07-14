> Renamed 2026-07-11 (kit naming invariant, function-named callables): the CLI
> names below read `cc-*` historically; the shipped callables are now
> `session-intel` / `session-observe` / `session-semantic` / `session-report` /
> `session-recall`, env knobs `SESSION_INTEL_*` / `SESSION_SEMANTIC_*` / `SESSION_REPORT_*`.

# SPEC: cc-intel

## Problem
My read-only intelligence (CC usage, repo health, ledger dedup, repeated manual sequences) is never assembled; I would have to run several tools by hand and eyeball cross-session patterns.

## Solution
A weekly LaunchAgent runs `cc-intel run`, assembling one dated digest from cc-observe + repo-sweep + deterministic synthesis + repeat-detect. Proposals only; the human acts.

## Contract
- `run --out DIR`: writes `DIR/intel-YYYY-MM-DD.md` with 4 sections; shells out to cc-observe / repo-sweep (`CC_INTEL_OBSERVE_CMD` / `CC_INTEL_SWEEP_CMD` overrides), degrading to `_unavailable_`.
- `synthesis`: concept names repeated (normalized, punctuation -> space) across ledger rows + GLOSSARY headings -> merge candidates.
- `repeat --min N`: consecutive bash-command 3-grams repeated >= N across recent transcripts -> extract-workflow candidates.
- `propose [--staging F] [--backlog F] [--dry-run]`: the SAME two detectors, rendered as `## [staged]` blocks through `lib/learn/staging-format.py` (SPEC-200 I1, the kit's one proposal currency) and appended to the staging buffer. Deduped by normalized title against every staging state + the board, so re-runs are idempotent and a rejected proposal never re-stages. The digest keeps printing the prose (that is the READING surface); this is the ACTING surface. The ONLY write is the staging buffer; `--dry-run` writes nothing; the board is never touched (human gate: `learn drain` to review, `board promote` to accept).
- Never writes durable homes. No network / LLM.

## Non-goals
- Acting on proposals (human).
- LLM-grade synthesis (a deterministic heuristic is enough for a proposal).
- Scheduling itself (the `deploy/macos` plist; loading it is a deploy step).

## Verification
`tests/smoke.sh` (6 assertions incl. 2 negative controls): synthesis flags a planted dup + a clean control; repeat flags a planted 3-gram + a clean control; `run` assembles all sections with stubbed observe/sweep; `run` degrades when they fail. The live plist load is a deploy check (runbook).
