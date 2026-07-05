# Sub-goal 06: Weekly scheduled intelligence job

**Time budget:** ~4-6h (largest sub-goal)
**Depends on:** none (cc-observe #261 + repo-sweep #268/#269 already merged)
**Branch:** feat/cc-elev-r2-06-sched
**PR base:** main

## Outcome

A scheduled (weekly) job that runs my read-only intelligence in one pass and emits a single dated digest: (a) `cc-observe report` + `repo-sweep run` (usage + cross-repo health), (b) cross-session synthesis (propose merges of repeated concepts across `_meta/learned-ledger.md` + GLOSSARYs), (c) repeat-sequence detection (a manual sequence done 3x across sessions -> suggest `extract-workflow`). Digest written to a dated file, optionally pushed via 01's cc-notify.

## Quality bar

Minimum-infra: a launchd job calling the existing CLIs, no new always-on listener; BTM-friendly plist (ProgramArguments[0] = bare-name executable, no `.sh`, no `/bin/bash` wrapper). Propose-don't-dispose: synthesis + repeat-detect emit suggestions, they never auto-write durable homes. No mini.ollama; any reasoning step uses Claude Haiku.

## How to close the loop

- Build the digest assembler (calls cc-observe + repo-sweep) + the synthesis + repeat-detect modules; author the launchd plist + a runbook.
- Given fixtures: synthesis proposes a merge for a concept seen across 2 fixture sessions writing nothing durable; repeat-detect flags a 3x sequence and suggests extract-workflow; the assembler produces one digest file. Negative control: a clean fixture yields a digest with no false proposals.
- Verify the plist loads (`launchctl print`) + runs the job once on demand.
- Lane via lane-classify; the new tool (e.g. `tools/cc-cron/` or an extension of repo-sweep) owes proof-of-done with the on-demand run + the fixture runs.

**Done =** a BTM-friendly launchd job runs cc-observe + repo-sweep weekly into one dated digest, with synthesis + repeat-detect proposing (never auto-writing durable homes) proven on fixtures, plus a runbook; proof-of-done; on PR #NN.

## Scope edges

**In:** the scheduler plist + digest assembler + synthesis + repeat-detect modules + runbook + proof.
**Out:** acting on the digest (human); domain-fusion to Notion; the auto-lab-log (09).
**Not:** a new daemon with a network listener; auto-merging concepts; mini.ollama.

## Open knobs (do NOT flip without Han)

- Host: Air vs Mini for the launchd job (default Air; the work is local + read-only). Push channel reuses 01.

## Where to look

cc-observe + repo-sweep CLIs, `_meta/learned-ledger.md` + the learning-ledger skill (dedup/merge), knowledge-capture consolidation, the BTM-friendly plist rule (CLAUDE.md), `tools/mac-mini-substrate/` plists for shape, extract-workflow.

## PR body

Outcome: a weekly launchd job that runs cc-observe + repo-sweep into one digest + proposes cross-session merges + repeat-sequence -> extract-workflow.
Verify: fixtures (synthesis + repeat-detect propose, nothing durable written); plist loads + runs once; clean fixture = no false proposals.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 06).

## Notes
