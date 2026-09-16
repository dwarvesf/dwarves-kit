# Test-value audit: which suites earn their seconds

Date: 2026-09-16

## Method

This audit timed every `tests/test-*.sh` suite in the kit (154 files matching the glob) from the worktree root, 4 at a time under `xargs -P 4`, each capped at 300 seconds via `timeout`. A suite whose `# requires:` header named a tool missing from PATH would have been skipped; none were (all 154 ran). Per suite the script recorded elapsed seconds, exit code, and an approximate assertion count: the number of output lines containing `PASS`, or starting with `ok:` or `ok `, after stripping ANSI color codes. That count is approximate. It over-counts suites whose harness prints a `PASS`-labeled line per case and under-counts suites that print a single summary line for many checks, so use it as a rough signal of suite size, not a precise assertion tally. Suite output was discarded after counting. The pass ran once. Two suites hit the 300-second cap during the parallel pass; both were rerun standalone afterward and both hit the cap again, so the parallel load was not the cause. Another agent was running a smaller test set on this machine at the same time, per the operator's brief; that overlap is the likely explanation for elevated seconds across several suites, not just the two that timed out.

## Summary by category

| Category | Suites | Total seconds | Share |
|---|---|---|---|
| git-mechanics | 64 | 887 | 45.5% |
| timing | 3 | 538 | 27.6% |
| config-lint | 14 | 238 | 12.2% |
| gate | 39 | 229 | 11.7% |
| other | 11 | 45 | 2.3% |
| doc-structure | 21 | 9 | 0.5% |
| runner-self | 2 | 5 | 0.3% |
| **Total** | **154** | **1951** | **100.0%** |

## The 12 longest suites

| Suite | Seconds | Category | Verdict | One-line reason |
|---|---|---|---|---|
| `test-orchestrate-wavefront.sh` | 300 (timeout) | git-mechanics | RETIRE-CANDIDATE | Its own header calls out the 288s-under-load flake this run reproduced twice (parallel and standalone); a machine-alone timing assertion cannot survive shared-Mac reality. |
| `test-pane-viewer.sh` | 300 (timeout) | timing | RETIRE-CANDIDATE | Fully mocked (VIEWER_CMD/TMUX_CMD), 17 assertions, still hangs to the cap standalone; a mocked suite should never be timing-sensitive, so something in the harness blocks for real. |
| `test-multiplexer.sh` | 235 | timing | THIN | 16 mocked tmux-wiring assertions for 235 seconds is a broken cost curve; the mock scaffolding is the expense, not the `_wave_run` logic it is meant to pin. |
| `test-meta.sh` | 131 | config-lint | KEEP | Tree-wide structural lint over every kit artifact, 853 assertions; loses version mismatches, missing frontmatter, and stale cross-references that no single-file review would catch. |
| `test-hooks.sh` | 107 | gate | KEEP | The general hook suite, 498 assertions; a break here means a safety/ship/commit-format hook silently stops blocking, or starts wrongly blocking, real pushes and edits. |
| `test-orchestrate.sh` | 67 | git-mechanics | KEEP | Pins the non-LLM `/goal` driver end to end (next-unchecked-sub-goal, gate stop, box-flip advance, no-self-claim negative control); without it the autonomous loop can silently advance without real work happening. |
| `test-config-seams.sh` | 55 | config-lint | KEEP | Cross-kit seam report over the config registry's join table; a consumer repo's config seam can drift from the registry with nothing to catch it. |
| `test-model-routing.sh` | 50 | git-mechanics | KEEP | Proves the `Model:` field is load-bearing on dispatch, not advisory; without it a sub-goal's declared model tier can silently be ignored and every dispatch runs on the default, burning the wrong budget. |
| `test-orchestrate-hardening.sh` | 47 | git-mechanics | KEEP | Pins stream/session-log retention pruning plus secret redaction in captured transcripts; without it a captured session log can sit on disk past its retention window, possibly carrying secret-shaped text. |
| `test-spec-reserve.sh` | 45 | git-mechanics | KEEP | Proves atomic SPEC-number reservation under real concurrency; without it two parallel agents can mint the same spec number and collide. |
| `test-wrap.sh` | 45 | git-mechanics | KEEP | The full acceptance matrix for `bin/wrap` across merged/unmerged/squash/locked/dirty worktree states, 518 assertions; without it session-close can delete a branch or worktree it should not, or leave stale state nobody notices. |
| `test-runaway-guards.sh` | 39 | git-mechanics | KEEP | The three runaway guards on the autonomous run queue (stale-window watchdog, circuit breaker, spend ceiling); without it an unattended queue run keeps burning tokens or spend past where a human would have stopped it. |

## Recommended cuts

| Suite | Seconds | Verdict | Reason | Seconds saved if cut |
|---|---|---|---|---|
| `test-orchestrate-wavefront.sh` | 300 | RETIRE-CANDIDATE | Flakes under load by its own admission; timed out twice in this audit (parallel and standalone). Either move it to a dedicated machine-alone lane outside `run-all.sh`'s default parallel sweep, or drop the wall-clock assertion and keep only the ready-set logic it also pins. | up to 300 |
| `test-pane-viewer.sh` | 300 | RETIRE-CANDIDATE | Fully mocked, 17 assertions, still hangs to the cap standalone. A mocked suite hanging for 300 seconds is a bug in the suite, not evidence it is doing valuable work. Fix the hang or retire it; do not let it keep silently eating 5 minutes of every full run. | up to 300 |
| `test-reflect-propose-precision.sh` | 4 | RETIRE-CANDIDATE | Prints a measured precision percentage from a 17-item synthetic sample; it is a one-off measurement dressed as a test, not a pass/fail assertion, and the file says outright the sample is too small to mean anything alone. Move it to a `docs/verification/` note or a script under `research/`, not `tests/`. | 4 |
| `test-advisor-ledger-emit.sh` | 0 | MERGE | Opens the same two files (`agents/advisor.md`, `commands/review-team.md`) `test-advisor.sh` already reads, to pin a different additive marker. Fold as another case in `test-advisor.sh`. | ~0, one fewer file to maintain |
| `test-references-field.sh` | 0 | MERGE | Re-derives the exact Reviewer-6 pure function `test-design-record.sh` already owns, to prove an unrelated spec field is a no-op. Fold as one more fixture case in `test-design-record.sh`. | ~0, one fewer file to maintain |

Total direct time recovered if both RETIRE-CANDIDATE timeouts are fixed or moved off the default sweep: up to 604 of 1951 seconds (31% of the whole run), with zero loss of coverage since both suites' current behavior (hang to cap) already delivers nothing but the 300-second tax.

### The six always-on lints vs the full glob

`bash tests/run-all.sh` normally runs diff-scoped selection plus six suites marked `# always:` in their header, because a tree-wide lint can never be reached by a diff-derived pick: `test-kit-contract.sh` (4s), `test-config-registry.sh` (15s), `test-no-personal-paths.sh` (21s), `test-no-scattered-ids.sh` (6s), `test-boundary-lint.sh` (0s), `test-meta.sh` (131s). That floor is 177 seconds on every single push, dominated by `test-meta.sh` alone (131s, 74% of the floor). A change that touches one `lib/` file pays those 177 seconds plus the handful of suites the diff selects, typically well under a minute of suite-specific time. The full glob (`bash tests/run-all.sh --all` or equivalent) pays the whole 1951 seconds, more than 10x the typical per-push cost, and about a third of that total is the two suites above that were not doing useful work in this run at all.

## Full per-suite table (sorted by seconds descending)

| Suite | Seconds | Exit | Approx assertions | Category | Verdict | What breaks without it |
|---|---|---|---|---|---|---|
| `test-orchestrate-wavefront.sh` | 300 | timeout | 48 | git-mechanics | RETIRE-CANDIDATE | Own header admits it flakes under load (288s at load 10.8 vs ~130s idle); it hit the 300s cap both in the 4-way parallel pass and again standalone (another session was also running tests on this Mac, which its own header calls the exact failure mode it exists to survive). A timing assertion that needs the machine to itself fails the moment two agents share it. |
| `test-pane-viewer.sh` | 300 | timeout | 17 | timing | RETIRE-CANDIDATE | Mocked end to end (VIEWER_CMD/TMUX_CMD, no real tmux or GUI), only 17 assertions, yet timed out at 300s both in the parallel pass and standalone; a fully-mocked suite should not be timing-sensitive at all, which points at a real hang in the harness, not machine load. |
| `test-multiplexer.sh` | 235 | 0 | 16 | timing | THIN | 235s to run 16 mocked assertions is a 15s-per-assertion tax for tmux-wiring wiring proofs that never touch a real tmux server; the mock harness itself is the cost, not the logic under test. |
| `test-meta.sh` | 131 | 0 | 853 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. always: the registry pin and structural lints cover every kit artifact test-meta.sh -- Structural integrity tests for kit artifacts. |
| `test-hooks.sh` | 107 | 0 | 498 | gate | KEEP | Guards a live blocking/safety gate. Automated test suite for dwarves-kit hooks Run: bash tests/test-hooks.sh Each test: pipe sample JSON to hook, check exit code and output. |
| `test-orchestrate.sh` | 67 | 0 | 65 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins lib/queue/orchestrate.sh ( phase 1): the non-LLM driver finds the next unchecked sub-goal, runs the auto chain via a MOCK |
| `test-config-seams.sh` | 55 | 0 | 53 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. `bin/config seams [--check]`, the cross-kit seam report over the "## Seams" join table (lib/config/config.sh |
| `test-model-routing.sh` | 50 | 0 | 6 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. proves the `Model:` field is LOAD-BEARING on the delegate dispatch path, not advisory. |
| `test-orchestrate-hardening.sh` | 47 | 0 | 12 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. orchfin-06 tiny sweep: three independent orchestrate.sh papercuts (/096/098), batched because each is too small for its |
| `test-spec-reserve.sh` | 45 | 0 | 35 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. atomic wavefront SPEC-number reservation. |
| `test-wrap.sh` | 45 | 0 | 518 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. the whole acceptance matrix for `bin/wrap` and `lib/wrap/wrap.sh`. |
| `test-runaway-guards.sh` | 39 | 0 | 44 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (board row ), the three runaway guards on the autonomous run queue. |
| `test-kit-foldin-hooks.sh` | 28 | 0 | 94 | gate | KEEP | Guards a live blocking/safety gate. fixture tests for the 4 kit-foldin hooks (kit-foldin sub-goal 02): backlog-stage, citation-guard, context-hints, harvest. |
| `test-wave-rid-check.sh` | 25 | 0 | 4 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins the WAVE (parallel) path's START/rid emission. |
| `test-tier4-close.sh` | 24 | 0 | 30 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins the TIER-4 mega-close that replaces `orchestrate.sh`'s "done"-and-return. |
| `test-precedent.sh` | 22 | 0 | 69 | other | KEEP | Runs real logic against a fixture. (precedent-inventory ): records-surface tests for `bin/precedent` / `lib/precedent/precedent.sh`, plus the shared fixture |
| `test-no-personal-paths.sh` | 21 | 0 | 3 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. always: scans the whole tree for operator paths and hostnames test-no-personal-paths.sh -- the kit ships no operator-specific path or... |
| `test-install-modules.sh` | 20 | 0 | 42 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (kit-modularity, install/wire): install.sh is LAYERED. |
| `test-notes-sanitization.sh` | 19 | 0 | 52 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (board row ), the untrusted-input pass on the autonomous run queue. |
| `test-wave-token-capture.sh` | 19 | 0 | 4 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins the WAVE (parallel) path's per-sub-goal TOKENS ledger extraction, closing the declared gap ("the wave-path |
| `test-cheap-guards.sh` | 18 | 0 | 23 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (board row ), the two cheap guardrails on the autonomous run queue: draft-PR-by-default and a self-reported |
| `test-orchestrate-gate-dispatch.sh` | 16 | 0 | 24 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins the two orchestrate.sh defects a real 5-sub-goal run surfaced: A. |
| `test-watchdog-token-capture.sh` | 16 | 0 | 6 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins token accounting on the watchdog-stall branch of `_run_one_session`/orchestrate.sh: a session that STALLS |
| `test-config-registry.sh` | 15 | 0 | 50 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. always: lints every KIT_* env read in the tree against the module registry test-config-registry.sh --, harness-loop sub-goal 08. |
| `test-repohygiene.sh` | 14 | 0 | 98 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/repohygiene/repohygiene.sh, the Tier 1 scanner of the kit:repo-hygiene audit loop. |
| `test-install-compat.sh` | 13 | 0 | 10 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. install.sh is plugin-aware: when the kit plugin is installed, it does a COMPAT-ONLY install (legacy path symlinks) and must NOT merge |
| `test-bin-forwarders.sh` | 10 | 0 | 0 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. ( decisions 1/7): the bin/ census and every forwarder's dispatch chain, exercised THROUGH the stable entrypoints |
| `test-install-clis.sh` | 10 | 0 | 0 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. install.sh CLI shims (step 5b + kit_write_cli_shim): enabled modules expose their CLIs on ~/.local/bin as exec-shim FILES targeting the... |
| `test-mutation-smoke.sh` | 10 | 0 | 33 | gate | KEEP | Guards a live blocking/safety gate. the ADVISORY mutation smoke (lib/gate/mutation-smoke.sh, ). |
| `test-reflect-propose.sh` | 9 | 0 | 48 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `reflect propose` (harness-loop ). |
| `test-reserved-config-guard.sh` | 9 | 0 | 9 | gate | KEEP | Guards a live blocking/safety gate. harness-ops sub-goal 08 (reserved-keys-guard). |
| `test-token-capture.sh` | 9 | 0 | 10 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins the LEAN token capture under delegation ( section 3): a delegated child streams to a FILE |
| `test-board-mirror.sh` | 6 | 0 | 77 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (runner-fastpath sub-goal 07): lib/board/board-mirror.sh + the `board.sh mirror`/`board.sh status` subcommands it backs. |
| `test-codex-hooks.sh` | 6 | 0 | 86 | other | KEEP | Runs real logic against a fixture. Contract tests for the Codex hook package and runtime adapter. |
| `test-no-scattered-ids.sh` | 6 | 0 | 9 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. always: scans the whole tree for scattered spec and task ids test-no-scattered-ids.sh -- the provenance rule, enforced where the repo is... |
| `test-ship-gate-coverage-map.sh` | 6 | 0 | 11 | gate | KEEP | Guards a live blocking/safety gate. spec ## Test plan -> proof-of-done coverage map. |
| `test-adopt.sh` | 5 | 0 | 28 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/adopt.sh: fresh adopt, idempotency, --check, |
| `test-gate-ledger-plan-record.sh` | 5 | 0 | 37 | gate | KEEP | Guards a live blocking/safety gate. `gate-ledger.sh plan-record <rid> <lane>...` writes one GATE line per named plan phase in a single call, and refuses |
| `test-gate-opt-out.sh` | 5 | 0 | 28 | gate | KEEP | Guards a live blocking/safety gate. The [gate] block switches a quality gate off per project. |
| `test-gate-outcome.sh` | 5 | 0 | 25 | gate | KEEP | Guards a live blocking/safety gate. kit-run-integrity. |
| `test-intake.sh` | 5 | 0 | 27 | gate | KEEP | Guards a live blocking/safety gate. `bin/intake gate` / `lib/intake/intake.sh`: the scripted dedup gate that replaces the five hand-written prose copies the intake skills... |
| `test-ledger-durability.sh` | 5 | 0 | 37 | gate | KEEP | Guards a live blocking/safety gate. kit-telemetry. |
| `test-ship-gate-fail-closed.sh` | 5 | 0 | 8 | gate | KEEP | Guards a live blocking/safety gate. the lane arm fails CLOSED on spec-exists-no-lane in an adopted repo, and stays fail-open everywhere else. |
| `test-attempt-state.sh` | 4 | 0 | 27 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Contract tests for lib/goal/attempt-state.sh, the dispatch Attempt state machine. |
| `test-board-writeback.sh` | 4 | 0 | 54 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (runner-fastpath sub-goal 08): lib/board/board-writeback.sh + the `board.sh writeback` subcommand it backs. |
| `test-gate-vocab-recording.sh` | 4 | 0 | 20 | gate | KEEP | Guards a live blocking/safety gate. orchestrator-finish mega-goal sub-goal 01. |
| `test-kit-contract.sh` | 4 | 0 | 25 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. always: the naming contract scans every module in the tree test-kit-contract.sh --: the standing contract EVERY kit module must satisfy. |
| `test-mega-reconcile.sh` | 4 | 0 | 35 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. kit-hardening. |
| `test-redteam-gate.sh` | 4 | 0 | 40 | gate | KEEP | Guards a live blocking/safety gate. rung-4 redteam cost checkpoint (ops-toolkit research/2026-07-18-rung4-cost-checkpoint.md). |
| `test-reflect-propose-precision.sh` | 4 | 0 | 5 | other | RETIRE-CANDIDATE | Prints a promote-precision percentage from a 17-item synthetic sample; it is a measurement, not a pass/fail assertion, and the sample is explicitly called too small to mean anything on its own. |
| `test-weekend-batch.sh` | 4 | 0 | 40 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. understanding-gate. |
| `test-gate-opt-in.sh` | 3 | 0 | 17 | gate | KEEP | Guards a live blocking/safety gate. The quality gates are OPT-IN: with only the kit root's kit.toml (every key false) and no operator overlay, each blocking hook PASSES and |
| `test-gitattributes-union.sh` | 3 | 0 | 27 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. the repo's own `.gitattributes` and what it buys. |
| `test-harness-dispatch.sh` | 3 | 0 | 38 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. requires: claude codex opencode test-harness-dispatch.sh Pins the WIRING: the `Harness:` goal-file header actually routes a sub-goal to a... |
| `test-install-plugin-detect.sh` | 3 | 0 | 6 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. install.sh step 3: bare command symlinks are created on shell-only installs, skipped (and cleaned up) when the kit is also |
| `test-lane-telemetry.sh` | 3 | 0 | 29 | other | KEEP | Runs real logic against a fixture. kit-telemetry. |
| `test-pitch.sh` | 3 | 0 | 30 | other | KEEP | Runs real logic against a fixture. kit-run-integrity mega-goal sub-goal 06. |
| `test-proof-negctl.sh` | 3 | 0 | 5 | gate | KEEP | Guards a live blocking/safety gate. lib/gate/negctl.sh (and the proof-ledger.sh `negctl` forwarder): the mechanised negative control. |
| `test-quiz-gate.sh` | 3 | 0 | 34 | gate | KEEP | Guards a live blocking/safety gate. understanding-gate; seam per /. |
| `test-run-all-timeout.sh` | 3 | 0 | 0 | runner-self | KEEP | Tests the test runner itself. requires: timeout run-all.sh must report a per-suite TIMEOUT as a DIFFERENT fact from a red assertion. |
| `test-ship-gate-profiles.sh` | 3 | 0 | 7 | gate | KEEP | Guards a live blocking/safety gate. Exercises the REAL ship-gate.sh hook (PreToolUse on git push) end to end, per profile, in the docs/verification/<slug>/ directory |
| `test-subagent-panes.sh` | 3 | 0 | 46 | timing | KEEP | Measures real wall-clock/concurrency behavior. read-only jsonl-tail panes over background-subagent transcripts. |
| `test-board-publish.sh` | 2 | 0 | 1 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `board publish`, the git leg of 's intake -> publish -> relay sequencing (ops-toolkit ). |
| `test-board.sh` | 2 | 0 | 49 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (runner-fastpath sub-goal 04): lib/board/board.sh + lib/board/parse-board.sh. |
| `test-config-stamp.sh` | 2 | 0 | 17 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. bench-plane prerequisite (DECISION-BRIEF-bench-plane.md §1). |
| `test-coverage-delta.sh` | 2 | 0 | 18 | gate | KEEP | Guards a live blocking/safety gate. advisory coverage-delta gate. |
| `test-deployable-done.sh` | 2 | 0 | 18 | gate | KEEP | Guards a live blocking/safety gate. kit-hardening. |
| `test-e2e.sh` | 2 | 0 | 20 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. the golden run ( / ). |
| `test-kit-weekly.sh` | 2 | 0 | 16 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. the ONE weekly scheduler ( decision 9, harness-loop ). |
| `test-mega-merge.sh` | 2 | 0 | 30 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. kit-telemetry. |
| `test-mega-review.sh` | 2 | 0 | 26 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `mega review --html <slug>` (, harness-loop sub-goal 07). |
| `test-mega.sh` | 2 | 0 | 19 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/mega/mega.sh (kit-modularity sub-goal 08): `mega status <slug>` reconciles a mega-goal's ROADMAP.md sub-goal claims against GIT TRUTH. |
| `test-outcome-emit-sweep.sh` | 2 | 0 | 51 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. harness-loop sub-goal 02. |
| `test-proof-visual-evidence.sh` | 2 | 0 | 5 | gate | KEEP | Guards a live blocking/safety gate. Guards the "screenshot/GIF counts as captured run-evidence" path in proof-ledger.sh check AND fix #1 (the embedded image must |
| `test-run-all-changed.sh` | 2 | 0 | 0 | runner-self | KEEP | Tests the test runner itself. run-all.sh --changed must run only the suites the diff touches. |
| `test-self-grill-watcher.sh` | 2 | 0 | 38 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (board row, the manager-loop pilot). |
| `test-significance-classify.sh` | 2 | 0 | 25 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. understanding-gate. |
| `test-spec-next-pr-scan.sh` | 2 | 0 | 8 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. spec-next mints against open PR heads, not only the local scan. |
| `test-stable-interface.sh` | 2 | 0 | 14 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. the bin/ stable consumer entrypoints. |
| `test-sync-cron-install.sh` | 2 | 0 | 29 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/sync/deploy/macos/install tests (kit board: sync.mode = cron). |
| `test-sync-dispatch.sh` | 2 | 0 | 5 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. cmd_sync dispatcher tests: config resolution from.kit.toml for BOTH board conventions (_meta/BACKLOG.md and root-level BACKLOG.md),... |
| `test-sync.sh` | 2 | 0 | 0 | other | KEEP | Runs real logic against a fixture. Runs the board-sync python suite (core planner + the three spoke adapters, fake transports only, no network). |
| `test-understanding-wiring.sh` | 2 | 0 | 19 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. understanding-gate (the FINAL, docs-last sub-goal). |
| `test-batch-debt-warn.sh` | 1 | 0 | 9 | gate | KEEP | Guards a live blocking/safety gate. sequence tests for the batch-debt-warn PreToolUse hook. |
| `test-bench.sh` | 1 | 0 | 1 | other | KEEP | Runs real logic against a fixture. repo-root entry for lib/bench's own Python tests ( C4 wants every module reachable from tests/); runs each module test file the way |
| `test-board-promote.sh` | 1 | 0 | 34 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/board/bin/add-backlog (operator entry: `board promote`). |
| `test-board-set-note.sh` | 1 | 0 | 17 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `backlog.sh set` note semantics: a terminal state's note SUPERSEDES the in-flight ones, every other state keeps stacking them. |
| `test-break-it.sh` | 1 | 0 | 68 | other | KEEP | Runs real logic against a fixture. the adversarial prober lens. |
| `test-classify-md-inert.sh` | 1 | 0 | 5 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins the classify fix: a markdown/txt-only diff is INERT regardless of the commit subject (a docs-only "migrate" commit is not |
| `test-command-emit-sweep.sh` | 1 | 0 | 18 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. kit-run-integrity mega-goal sub-goal 05. |
| `test-context-budget.sh` | 1 | 0 | 13 | gate | KEEP | Guards a live blocking/safety gate. sequence tests for the context-budget UserPromptSubmit hook. |
| `test-design-record.sh` | 1 | 0 | 26 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. Proves the §1 design record (BEFORE gate). |
| `test-every-step-review.sh` | 1 | 0 | 17 | gate | KEEP | Guards a live blocking/safety gate. kit-hardening ( P4). |
| `test-explain.sh` | 1 | 0 | 15 | other | KEEP | Runs real logic against a fixture. understanding-gate. |
| `test-gate-ledger-report.sh` | 1 | 0 | 8 | gate | KEEP | Guards a live blocking/safety gate. `gate-ledger.sh report --period week|month` cross-cutting markdown report. |
| `test-goal-dispatch.sh` | 1 | 0 | 21 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/goal/goal.sh dispatch behavior. |
| `test-intake-sweep.sh` | 1 | 0 | 0 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. hooks/intake-sweep.py: the deferred-link sources -> staging funnel adapter (jsonl + command kinds), its three dedup layers, the config |
| `test-kri-wiring.sh` | 1 | 0 | 31 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. No-orphan wiring check for kit-run-integrity's five sub-goals (01-05, plus the |
| `test-lane-deescalate.sh` | 1 | 0 | 22 | gate | KEEP | Guards a live blocking/safety gate. kit-run-integrity sub-goal 07 ( kit half). |
| `test-lane-classify.sh` | 1 | 0 | 32 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. kit-telemetry. |
| `test-lane-escalation.sh` | 1 | 0 | 22 | gate | KEEP | Guards a live blocking/safety gate. kit-hardening. |
| `test-lint-scattered-ids.sh` | 1 | 0 | 9 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. serial: stages a fixture into the REAL repo index, because the enumerator under test reads `git ls-files` and would never see an untracked... |
| `test-money-gate.sh` | 1 | 0 | 0 | gate | KEEP | Guards a live blocking/safety gate. money-gate hook (hooks/money-gate.sh + money-gate.py): fires only for money-touching edits inside a CONSUMER-NAMED financial repo... |
| `test-onboard-detect.sh` | 1 | 0 | 19 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. harness-loop sub-goal 09. |
| `test-picture-section.sh` | 1 | 0 | 21 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. Proves the `## Picture` presence check (spec's PRE-build twin of 's post-build visual proof). |
| `test-premerge.sh` | 1 | 0 | 20 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. merge the default branch into the working branch before a PR opens, so a GitHub squash-merge never disagrees with a union-mergeable |
| `test-proof-dir-layout.sh` | 1 | 0 | 4 | gate | KEEP | Guards a live blocking/safety gate. Proves proof-ledger.sh check validates the docs/verification/<slug>/ directory layout SET-WISE: a green run in one runs/ file + a |
| `test-proof-experiment-verification-path.sh` | 1 | 0 | 5 | gate | KEEP | Guards a live blocking/safety gate. Guards the co-located verification path for owners OTHER than tools/: a fresh proof at |
| `test-proof-override-order.sh` | 1 | 0 | 6 | gate | KEEP | Guards a live blocking/safety gate. Proves proof-ledger.sh check lets a REAL proof-of-done win outright even when an override was ALSO logged for the same slug. |
| `test-proof-table-gen.sh` | 1 | 0 | 25 | gate | KEEP | Guards a live blocking/safety gate. the generated proof-of-done confirmation table (, reconciled to 01's real marker shape per ). |
| `test-prose-rag-adapter.sh` | 1 | 0 | 32 | other | KEEP | Runs real logic against a fixture. `bin/prose-rag` resolves the engine binary ($PROSE_RAG_BIN, then `prose-rag` on PATH) and states the three |
| `test-reflect-drain.sh` | 1 | 0 | 24 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (harness-loop sub-goal 06). |
| `test-release.sh` | 1 | 0 | 9 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. bin/release --dry-run against a fixture repo. |
| `test-research-pair-contract.sh` | 1 | 0 | 41 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. backfill items 4+5/6,. |
| `test-role-classify.sh` | 1 | 0 | 24 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. the shared specialist-domain classifier. |
| `test-stats-no-persist.sh` | 1 | 0 | 5 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. (kit-modularity ): the LOAD-BEARING event-sourcing guarantee that `stats` is a stateless projection and persists |
| `test-sync-cron-launcher.sh` | 1 | 0 | 14 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. lib/sync/deploy/macos/board-sync-cron tests (kit board ). |
| `test-tool-policy-guard.sh` | 1 | 0 | 25 | gate | KEEP | Guards a live blocking/safety gate. backfill item 6/6,. |
| `test-verbatim-rows.sh` | 1 | 0 | 11 | gate | KEEP | Guards a live blocking/safety gate. lib/gate/verbatim-rows.sh: every row in a rewritten structured index must appear verbatim in the pre-edit original (see the script's |
| `test-webcheck.sh` | 1 | 0 | 0 | other | KEEP | Runs real logic against a fixture. Runs the webcheck python suite (three tiers + the SSRF guards + the WEB_DRIFT_SITES resolver). |
| `test-advisor.sh` | 0 | 0 | 15 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. kit-hardening. |
| `test-agent-effectiveness.sh` | 0 | 0 | 24 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. kit-hardening. |
| `test-advisor-ledger-emit.sh` | 0 | 0 | 27 | doc-structure | MERGE | Pins the same two files (agents/advisor.md, commands/review-team.md) test-advisor.sh already opens for a different assertion; one file reading both dispatch sites once would cover both. |
| `test-audit-scanner-contract.sh` | 0 | 0 | 15 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. . |
| `test-board-dedupe-all.sh` | 0 | 0 | 5 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `backlog.sh dedupe-all`: the whole-file sweep a union re-merge runs automatically, as opposed to `dedupe <id>` which a human names one id... |
| `test-board-file-guard.sh` | 0 | 0 | 4 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `backlog.sh`: a missing/unreadable BACKLOG_FILE exits 1 with a message naming the variable, instead of dying deep inside _rows's awk call... |
| `test-boundary-lint.sh` | 0 | 0 | 6 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. always: the engine-names-no-consumer lint scans the whole tree test-boundary-lint.sh -- (learning-boundary, ): the engine names no... |
| `test-command-triggers.sh` | 0 | 0 | 9 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. Skill selection runs on the description line. |
| `test-config.sh` | 0 | 0 | 19 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. the config-layer resolver (lib/config/kit-config.sh). |
| `test-delivery-ratio.sh` | 0 | 0 | 8 | gate | KEEP | Guards a live blocking/safety gate. the ADVISORY delivery-ratio verb on proof-ledger.sh. |
| `test-docs-wiring.sh` | 0 | 0 | 25 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. Two things this file proves, mirroring the kit-hardening c6fbd99 precedent |
| `test-gate-ledger-history.sh` | 0 | 0 | 9 | gate | KEEP | Guards a live blocking/safety gate. `gate-ledger.sh history` CSV/JSON export. |
| `test-gauntlet-proof-audit.sh` | 0 | 0 | 11 | gate | KEEP | Guards a live blocking/safety gate. pins the gauntlet-proof-audit skill's Tier-1 logic so it is a re-runnable regression, not a one-time hand run. |
| `test-harness-adapter.sh` | 0 | 0 | 21 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. Pins lib/queue/harness.sh (multi-vendor headless dispatch adapter) + the `fable` tier fix. |
| `test-grill-conditioning.sh` | 0 | 0 | 23 | gate | KEEP | Guards a live blocking/safety gate. mega-goal kit-absorptions sub-goal 04. |
| `test-install-contract.sh` | 0 | 0 | 5 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. adopt.sh + gate-ledger work from an INSTALL that has AGENTS.md + WORKFLOW.md (+ docs/WORKFLOW.md bulk, ) deployed. |
| `test-install-self-symlink.sh` | 0 | 0 | 6 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. on a dev machine ~/.claude/dwarves-kit is a symlink to the checkout, so the compat branch's link targets resolve to the same |
| `test-ledger-substrate.sh` | 0 | 0 | 9 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. (kit-modularity ): the ledger append substrate (lib/ledger/ledger.sh) + the KIT_LEDGER_DIR one-root wiring shared by |
| `test-loop-engineering-contract.sh` | 0 | 0 | 32 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. backfill item 2/6,. |
| `test-mega-report.sh` | 0 | 0 | 1 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `mega report <slug>` (the RUN_REPORT telemetry generator). |
| `test-memory-tidy-contract.sh` | 0 | 0 | 28 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. backfill item 1/6,. |
| `test-meta-agent.sh` | 0 | 0 | 72 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. the meta-agent drafter (token-optim-v3 ). |
| `test-proof-tool-verification-path.sh` | 0 | 0 | 2 | gate | KEEP | Guards a live blocking/safety gate. Guards the monorepo tool-co-located verification path: a fresh proof at tools/<name>/docs/verification/<slug>.md |
| `test-references-field.sh` | 0 | 0 | 15 | doc-structure | MERGE | Re-derives the exact Reviewer-6 pure function test-design-record.sh already owns, just to prove an unrelated field is a no-op; fold as one more case into test-design-record.sh. |
| `test-research-arch-contract.sh` | 0 | 0 | 28 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. backfill item 3/6,. |
| `test-review-team-plants.sh` | 0 | 0 | 8 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. Behavioral regression guard for the /review-team security lens. |
| `test-right-arm-parity.sh` | 0 | 0 | 38 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. kit-hardening. |
| `test-routing.sh` | 0 | 0 | 17 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. data-driven model routing suggester (token-optim-v3 ). |
| `test-runs-dashboard.sh` | 0 | 0 | 21 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. serial: fails under concurrency on ubuntu while passing sequentially, alone, and on macOS. |
| `test-security-hardening.sh` | 0 | 0 | 22 | gate | KEEP | Guards a live blocking/safety gate. security remediation for the kit-run-integrity run. |
| `test-spec-index.sh` | 0 | 0 | 9 | config-lint | KEEP | Standing tree-wide lint; cheap, catches drift a single-file review misses. the read-only SPEC registry view (lib/spec/spec-index.sh). |
| `test-staging-stage.sh` | 0 | 0 | 33 | git-mechanics | KEEP | Exercises real git/board/queue fixtures, not mocked prose. `python3 lib/reflect/staging-format.py stage`, the one staging WRITER (dedupe + render_block + append in a single |
| `test-test-writer-contract.sh` | 0 | 0 | 11 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. . |
| `test-web-drift-refusal-guard.sh` | 0 | 0 | 7 | doc-structure | THIN | Greps a markdown/command file for a phrase or section; proves the prose exists, not that the behavior runs. web-drift's boardless-consumer refusal guard. |

## What this audit does not settle

- Assertion counts are approximate (PASS/ok-line greps), not a verified count of behavioral checks; a suite that prints one summary line for many checks looks artificially small here.
- Category and verdict were assigned from each suite's own header comment plus, for the top and flagged suites, a closer read of the first 40 lines. Suites in the middle of the full table were not individually re-read line by line; the "what breaks without it" column there is drawn from the suite's own stated purpose, not independent verification.
- The doc-structure THIN verdicts are not RETIRE-CANDIDATEs. Most of them pin a prose contract for a skill or command that has no other executable form (a prompt-driven reviewer, an agent's frontmatter), so a grep-based pin is the only mechanism available, not a lazy shortcut. Whether that pin is worth its own file versus folding into a sibling suite was only checked for the two MERGE cases named above; the other 19 doc-structure suites were not individually checked for overlap.
- Whether `test-orchestrate-wavefront.sh` and `test-pane-viewer.sh` hang because of genuine load contention, a real bug in the suite, or a bug in this audit's harness (both ran under `xargs -P 4` and, standalone, alongside another session's own test run) was not root-caused here. The recommendation to retire or fix them stands either way, but the underlying cause is still open.
- Whether the seven-plus gate-ledger marker suites (`test-gate-outcome.sh`, `test-gate-ledger-history.sh`, `test-gate-ledger-plan-record.sh`, `test-gate-ledger-report.sh`, `test-config-stamp.sh`, `test-token-capture.sh`, `test-wave-token-capture.sh`, `test-watchdog-token-capture.sh`) could share one property-based harness instead of one file per marker was not evaluated; they were kept as individual KEEPs because each pins a distinct additive marker or dispatch path, but the repeated fixture-setup boilerplate across them was not measured.
- The proof-ledger verification-path family (`test-proof-tool-verification-path.sh`, `test-proof-experiment-verification-path.sh`, `test-proof-dir-layout.sh`) guards the same class of bug (a grep anchored at the wrong directory) landing twice already; whether a third occurrence would be caught faster by one parametrized suite than three separate files was not evaluated.
