# Retro: OpenRig absorption build wave
Date: 2026-10-05
Sprint: 2026-09-28 to 2026-09-30, plus the registry follow-up on 2026-10-04

This retro closes the Reflect gate that SPEC-368, SPEC-369, SPEC-370, SPEC-371 and SPEC-372 overrode to it. It landed five days after the last spec merged (see What hurt).

## Metrics

| Measure | Value |
|---|---|
| Specs planned and shipped | 7 of 7 (SPEC-366 to SPEC-372); none parked |
| Spec PRs | #834 (366), #831 (367), #840 (368), #847 (369), #841 (370), #833 (371), #843 (372) |
| Spec PR size | 11,302 lines added, 1,078 removed, 187 file touches across 7 PRs |
| Research PRs | #808, #811, #812, correction #844 |
| Supporting PRs | #810 post-compact hook, #820 test ledger isolation, #824 rid dispatch tag, #830 #832 #838 #845 master test fixes, #848 specs marked shipped and fixture orphan dropped |
| Closed, not merged | #846 (superseded by #847 to avoid a force-push) |
| Follow-up | Registry Tests column #904 and one-pass matcher #915 (generate 50 s to 4 s), both merged 2026-10-04; the stuck `feat/registry-test-scan` branch is not needed |
| Wall clock | 2026-09-28 20:02 UTC (first research PR) to 2026-09-30 09:01 UTC (cleanup), about 37 hours; the seven spec PRs merged between 02:33 and 08:36 UTC on 2026-09-30 |
| Workers | Sonnet subagent builders (Devin weekly quota was exhausted); Opus review lenses; one fresh acceptance verifier per spec |
| Review result | 7 of 7 specs got FIX FIRST or FIX THEN SHIP from a fresh-context review, and every one had real findings fixed before merge |
| Master after the wave | `test-meta` 887 of 887 at SPEC-371; `feature-registry.sh check` reports `docs/FEATURES.md is fresh` on master (checked 2026-10-05) |

## What worked

- Spec validators corrected the research record before it hardened. Three claims were wrong (recheck-verifier "0 FAIL", trading's "322 lines behind", "drop the test-plan review team"). Each correction changed a design: recheck became sampled instead of cut, adopt got a "not a kit copy" rule instead of a sync job, the review team kept a light pass. See the corrections table in `docs/research/2026-09-29-openrig-absorption.md`.
- Fresh-context review earned its cost on every spec. Examples: a gameable sampling rule and an unchecked continuation in SPEC-369, byte-level data-loss checks in SPEC-371, a GNU `tr` range bug and a stuck footer in SPEC-366, an unsafe runbook step in SPEC-370.
- The threat model ended the parser arms race. SPEC-368 states that the lane gates guard a cooperative agent, not an adversary, and names a native pre-push hook as the structural step. After four probe rounds that stopped more patching.
- The A/B run measured SPEC-369 instead of arguing it. Medium 4-task fixture, one run per arm: old spine 18 dispatches and 605,367 net tokens, new spine 15 and 436,168 (minus 28 percent), same 4 of 4 outcome, same wall time (`docs/verification/whole-spec-dispatch-ab.md`).
- The SPEC-371 measurement was cheap once built: four headless sessions, about three minutes each. The pointer cuts 6.5k tokens from every first call and lost no hard rule (`docs/verification/onboarding-pointer/RESULT.md`).
- The handoff's "Decisions (do not relitigate)" and "Dead-ends" lists kept later sessions from reopening the gate parser and Devin.

## What hurt

- The command-parser arms race. SPEC-368 took four security probe rounds (`probe.sh` to `probe4.sh`), each closing bypasses the last round exposed, before the threat model made the stop rule explicit. The structural fix, a native pre-push hook, is not built.
- Shared scratchpad commit-message files crossed branch subjects. #831 (ceremony lens) squash-merged as "feat(board)...". The PR title was fixed afterward; the subject on master stays wrong.
- Our own merges broke `test-config-registry` and the stats skill description check, and nobody noticed until a later builder ran the suite. It took #830, #832 and #845 to repair.
- Two heavy suites in one worktree at once give a false `FEATURES.md` failure. The fix is to run one at a time, which cost reruns.
- The wave ended with a duplicate PR. #846 had to be closed and replaced by #847 to avoid a force-push.
- Both A/B arms stopped at the lead's context ceiling before ship. Arm A never applied its review fixes, so arm B's three extra fix dispatches are work arm A never reached. The validator also had to be overridden twice to run headless. Treat the A/B as direction, n = 1.
- The Reflect overrides were debt. Five specs deferred their reflection to "a retro at session close" and the retro landed five days later. The override text named the lessons, so nothing was lost, but the gate did not do its job.
- `execute.md` sits at 29,702 of 30,000 bytes. The next change to it must move content out first.
- The SPEC-371 measurement showed a gap neither arm closes. With no hint in the prompt, neither the old copy nor the pointer stopped to ask which file was canonical. Both decided and disclosed. Under the spec's literal rule ("no" on contract read and "no" on paused reverses the design) the pointer run qualifies, but the old copy did the same, so the pointer did not cause it.
- `adopt --check` reads the operator's `adopt.single_source` knob. On a repo adopted by the old kit in normal mode the check reports "not adopted" under that knob, which turned the J2 checker RED for the old arm until `--no-single-source` was passed.

## Step 1b: doc-impact and completeness sweep

| Check | Result |
|---|---|
| `docs/FEATURES.md` freshness | fresh on master (`bash lib/registry/feature-registry.sh check`) |
| Companion docs | The backfill (#848) and the inventory work (#904, #915) closed the doc gaps the wave opened. No new gap found in this pass |
| `completeness.log` | Not read: a machine-local log of other sessions' warnings, not scoped to this wave |

## Step 1c: decision capture

None fell through. The lane-gate threat model lives in SPEC-368 `## Threat model`, whole-spec dispatch in ADR-0038, the light-pass verdict rule in SPEC-372 AMEND-001, and the adopt-never-overwrites rule in SPEC-371. The one open call is the SPEC-371 hold or reverse decision below; it becomes an ADR only if the answer is reverse.

## Step 1d: lane telemetry

`lane-telemetry.sh report`: 378 runs, 13 lane-misrouted, 141 shipped. `misfires` printed 13 lines. Dispositions:

| Misfire | Disposition |
|---|---|
| `ab-old-spine`, `ab-old-take2`, `ab-old-run3`, `ab-new-run1` (chosen full, classified normal) | accepted noise: A/B fixture rids forced to the full spine on purpose to measure it |
| `whole-spec-dispatch` (chosen full, classified normal) | accepted noise: the spec rewrites `commands/execute.md`, the spine itself; full was the right call and the classifier under-reads prose edits to a command file |
| `circle-new-people`, `github-batch-logline`, `land-ignored-fixture-guard`, `ledger-check-fast`, `ledger-io-core`, `master-green`, `never-pinged-lifecycle`, `test-launchctl-leak` | accepted noise: other cycles and other repos, not part of this wave |

The wave's own rids (`lanes-as-data`, `spec-depth-line`, `whole-spec-dispatch`, `execution-view`) routed as classified except `whole-spec-dispatch`, above.

## Action items

- [ ] Run the SPEC-370 live trial: set Orca's persistent Claude launch mode to bypass by hand, run `docs/verification/orca-trial/RUNBOOK.md`, restore the prior mode, record the trial -- owner: @tieubao -- deadline: 2026-10-12
- [ ] Decide hold or reverse for SPEC-371 against the literal "no and no" rule, using `RESULT.md`; if hold, consider one line in the pointer's rule 4 that says to ask when two files disagree -- owner: @tieubao -- deadline: 2026-10-12
- [ ] Design the native pre-push hook installed by `adopt` that runs the ship-gate floor on the exact refs git passes on stdin (the SPEC-368 structural next step), before any more parser patching -- owner: @tieubao -- deadline: 2026-10-19
- [ ] Make `adopt --check` detect either layout regardless of the `adopt.single_source` knob, with a test for an old-copy repo under the knob -- owner: @tieubao -- deadline: 2026-10-12
- [ ] Worker brief template: a new `mktemp` per commit message file and `wrap land --title`, never a shared scratchpad message file -- owner: @tieubao -- deadline: 2026-10-12
- [ ] Confirm `bin/test-affected` selects `test-config-registry` when a change adds a config key or env var outside `lib/config/`; add the mapping if not -- owner: @tieubao -- deadline: 2026-10-12
- [ ] Before the next edit to `commands/execute.md`, move content out; it is 298 bytes under its cap -- owner: @tieubao -- deadline: 2026-10-19
- [ ] When a Reflect override names a retro, have `/kit:wrap` list it as owed until a retro doc exists -- owner: @tieubao -- deadline: 2026-10-19

## Kit feedback

- The ship-gate command parser cannot account for every shell form, and the fix is a hook that sees the real refs, not a better parser (SPEC-368 `## Threat model`).
- `lane-telemetry.sh report` prints 424 lines with 295 untracked runs and takes minutes on this host; the retro step needs a per-rid or per-date filter.
- `lib/adopt/onboarding-cost.sh` counts a turn as one distinct assistant message, which differs from `num_turns` in the Claude Code result line (14 against 21 on one run). Both are shown in `RESULT.md`; the script's header could say so.
- The headless measurement sessions wrote four small rids to the live gate ledger (`readme-upper-flag`, `fix-readme-flag`, two pause runs). A flag to send measurement runs to a scratch ledger would keep the lane report clean.
