# Mega-goal: cc-elevation-r3

**Destination:** cc-observe/cc-intel stop being raw counters and start inferring *how I
work* (rework spirals, friction, context pressure, session shape, cost-by-model,
semantic drift), and the weekly intelligence stops being a file I must open , it reaches
me through **vps-mon + the public `/status` page**. Same read-only, propose-don't-dispose,
minimum-infra posture as r1/r2.

## Sub-goals

- [x] 01-friction-signals , cc-observe gains deterministic friction views (thrash/rework, permission-friction, context-pressure, skill-activation-precision), each proven on a seeded fixture + negative control , PR #333 (base: main; no-CI repo, proof = smoke 18/18 + real run)
- [x] 02-session-shape-signals , cc-observe gains session-archetype + circadian + interruption-rate views , PR #335 (base: 01; no-CI repo, proof = smoke 22/22 + real run; archetype excludes sidechain)
- [x] 03-cost-model-signals , cc-observe gains tokens-by-model + cache economics ($ estimate) from the transcript `usage` block; cost-per-merged-PR deferred (cross-repo + squash-merge, no clean data path) , PR #337 (base: 02; no-CI repo, proof = smoke 26/26 + real run)
- [x] 04-semantic-signals , an LLM (Haiku) pass infers topic/domain drift + self-correction rate, propose-only, never auto-written , PR #339 (base: main; cc-semantic sibling script; no-CI repo, proof = smoke incl. propose-only + unavailable negative controls; live claude -p path wired, deterministic paths proven)
- [x] 05-vps-mon-bridge , `cc-observe --json` ingested by vps-mon + cc-intel digest surfaced on the public `/status` page; closes the deferred channel decision , PR #343 (base: main; HMAC scheme = UTF-8 key bytes; created public page ai-substrate; supersedes r2 SG-01)
- [x] 06-otel-eval , eval native `CLAUDE_CODE_ENABLE_TELEMETRY=1` into vps-mon, ending in a documented adopt-or-skip (verdict: CONDITIONAL-ADOPT; wiring -> BACKLOG ID-101) , PR #344 (base: main)

## Dependencies

- **01 -> 02 -> 03 are stacked** (all heavily edit `tools/cc-observe/bin/cc-observe`; parallel PRs on the same file would conflict). 02 branches off 01, 03 off 02.
- **04, 05, 06 are independent**, each off `main`. 04 is a new module; 05 is vps-mon + cc-intel wiring; 06 is a settings/eval.
- **05 absorbs `cc-elevation-r2` SG-01 (cc-notify)**: the channel decision that blocked it is now RESOLVED = **vps-mon ingest + `/status` page** (Han, 2026-06-15). No separate phone-push channel. When 05 ships, mark r2 SG-01 closed (superseded by r3 SG-05).
- 05 surfaces richer data if 01-04 have landed, but does not require them: it can bridge the existing `report` shape and pick up new views as they merge.

## Merge discipline (human, on return)

Stacked chain 01->02->03: merge bottom-up. BEFORE merging+deleting 01's branch, retarget 02's
base to `main` (`gh pr edit <02-pr> --base main`); same for 03 before deleting 02. Skipping the
retarget auto-closes the child (see `feedback_stacked_pr_delete_branch`). 04/05/06 merge any time.

## Audit cheat sheet

Each sub-goal owes a co-located proof (`tools/<tool>/docs/proof-of-done.md` updated, or a
feature entry) with a green run + a negative control. cc-observe view sub-goals (01-03) extend
its single canonical proof; 04 (new module) + 05 (vps-mon) own their own; 06 emits an eval report.

## Source

`research/2026-06-15-claude-code-usage-metrics-and-tooling.md` (metrics + OSS landscape + the two
deferred bridges). Predecessors: `cc-elevation` (r1, 6/6 shipped) + `cc-elevation-r2` (8/9; SG-01
folded here). Channel decision: vps-mon + `/status` (Han, 2026-06-15).
