# Backlog staging (auto, via learn propose)

Candidates auto-extracted from the ledger. Review + promote by hand (`board promote`).
Gitignored: may name unfiled work. NEVER the source of truth.

## [staged] Audit high override rate on reflect gate
- Intent: Bring the reflect gate's override rate down from its current outlier level.
- Approach: Sample reflect-gate override reasons to find the common cause; adjust gate criteria or the retro flow that keeps triggering it.
- Tags: #u-hi #f-hi
- Home: dwarves-kit
- Source: learn propose 2026-07-12 | lens=gate-yield figure="reflect override_pct=28.0" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Add a token-runaway guard for sessions
- Intent: Stop sessions from ballooning into billions of tokens unnoticed.
- Approach: Add a session-level token ceiling check that alerts or halts; separately root-cause the 2.1B-token session that triggered this.
- Tags: #u-hi #f-mid
- Home: ops-toolkit
- Source: learn propose 2026-07-12 | lens=anomalies:token_runaway figure="session_id=8ae69411-07d1-474e-a33d-64b1531ce251 project_slug=-Users-tieubao-workspace-tieubao-ops-toolkit total_tokens=2115144012" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Tighten the observability spec against its deviation log
- Intent: Bring the 01-observability spec out of under-specced territory.
- Approach: Review the 15 logged implementation deviations and fold the recurring ones back into the spec.
- Tags: #u-mid #f-hi
- Home: dwarves-kit
- Source: learn propose 2026-07-12 | lens=deviation-rate figure="repo=dwarves-kit; slug=01-observability; file=lib/session/observe/docs/implementation-notes/01-observability.md; n_deviations=15; zero_marker=False; first_ts=2026-06-14 00:00; last_ts=2026-06-15 14:40; class=UNDER-SPECCED" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Sweep memory notes pointing at dead paths
- Intent: Stop memory notes from citing paths that no longer exist in the repo.
- Approach: Run a dead-path scan across memory notes and remove or repoint the stale ones.
- Tags: #u-lo #f-hi
- Home: dwarves-kit
- Source: learn propose 2026-07-12 | lens=memory-sweep figure="21 memory notes reference dead paths, 0 stale (>180d)" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Add a self-answer detection check to `/kit:think` (and any other forcing-question command):
- Intent: Action item a retro committed to; it lived only as a checkbox nobody could promote.
- Approach: Add a self-answer detection check to `/kit:think` (and any other forcing-question command):
- Tags: #u-mid #f-mid
- Source: retro 2026-08-01 | RETRO-2026-08-01-backlog-reconcile.md

## [staged] Make "fetch origin before cutting any new branch" a reflex step in the
- Intent: Action item a retro committed to; it lived only as a checkbox nobody could promote.
- Approach: Make "fetch origin before cutting any new branch" a reflex step in the
- Tags: #u-mid #f-mid
- Source: retro 2026-08-01 | RETRO-2026-08-01-backlog-reconcile.md

## [staged] wrap merge union retry
- Intent: bin/wrap merge: on a CONFLICTING squash caused by GitHub ignoring merge=union, merge the default branch into the branch worktree and retry once
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-08

## [staged] wrap merge: wait for CI instead of returning on pending
- Intent: This session hand-rolled the same watch-then-merge-then-clean script three times (merge-527/528/529.sh in scratch). bin/wrap merge returns immediately on a pending PR, so every caller reinvents the wait. Enhancement belongs in wrap merge, not a fourth script. The fork that makes it a judgment: blocking wrap on CI holds the landing step for the full macOS leg (~9 min observed today), so it likely wants a --watch flag plus a timeout, not a new default.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-08

## [promoted ID-651] wrap Step 7a is unreachable when landing from a default branch
- Intent: gate-ledger.sh rid refuses on master/main ('not on a work branch'), so /kit:wrap Step 7a silently skips the DEBT marker for exactly the sessions most likely to need it: a long multi-repo session landed from the default branch. Either derive a rid from the session rather than the branch, or make Step 7a say the marker was skipped for a structural reason rather than reporting a clean skip.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-09

## [staged] wrap apply: name the untracked file that blocks an ff pull
- Intent: Twice this session a git pull --ff-only aborted because an untracked local file was byte-identical to one that had just merged (a research note, then a handoff), and the fix was manual both times: git show origin/main:<path> > tmp, cmp, mv the local copy aside, pull again. wrap apply owns the pull and reports it as FAILED with no reason the operator can act on. Judgment fork, which is why this is staged rather than built: reporting the blocking path and the identical-or-not verdict is safe, but moving or deleting an operator file to unblock a pull is a write on something wrap did not create, and that call belongs to the operator.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarvesf/dwarves-kit
- Source: session 2026-09-10

## [dropped: fixed upstream by #574] wrap log prepends above the LAB_LOG header
- Intent: bin/wrap log's fallback path writes the new entry above the '# LAB_LOG' header instead of below it, so the header drifts down the file one session at a time; the 2026-09-10 compaction found it at line 878 of 4190 and had to move it back by hand. Fix the fallback insertion point and add a test asserting the header stays at line 1 after a log write.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-10

## [promoted ID-829] repo-hygiene audit-loop instance
- Intent: Add a repo-hygiene instance to the kit's audit-loop family (siblings: doc-drift, topology-drift, ci-drift, backlog-reconcile, web-drift; shared read-only audit-scanner). Detectors: a non-code file nothing references after N days; a gitignored dir that is large and cold; an _inbox item older than 30 days; a _meta entry that is an owned record; a log past its line threshold. Each finding carries evidence (file:line, or the grep that proves nothing references it) because verification, not detection, was 90 percent of the cost when this ran by hand on 2026-09-10. Surfaces findings only, never deletes: route-versus-trash needed Han's call four times in one pass, and twice he decided against the recommendation.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-10

## [built 67cbc53] worker brief template for subagent dispatch
- Intent: Twenty-plus dispatch prompts repeated the same preamble by hand: pwd, fetch origin main and merge, absolute paths, git -C, rename branch, do not edit shared modules, verification file required, LAB_LOG line, STE-lite, no dashes, commit not push, report in N lines. Drift between copies caused two real defects: workers blind to merged docs, and a fenced worker leaving stale doc lines. Fork: a kit doc the commands cite, versus a lib helper that emits the block, versus fields on the agent definitions.
- Approach: Built as `docs/patterns/worker-brief.md`, the kit-doc-a-command-cites option (the reversible first step). The lib-helper and agent-definition-fields alternatives are still open; see the fork note above.
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-11

## [built 4595dea] proof-gate contract emits the verification skeleton
- Intent: Fifteen-plus workers each wrote docs/verification/<slug>.md from a prose description re-specified in every dispatch: run table with Command/Exit/Verdict, negative control, determinism hash, rollback note, Not proven. proof-gate.sh contract already tells a work type what it owes; it could emit the file skeleton too. Fork: contract prints it versus a separate verb writes the file, and whether the skeleton belongs in the kit or in each adopting repo.
- Approach: Built as a new `proof-gate.sh skeleton "<slug>" ["<task>"]` subcommand; `contract` prints a pointer to it rather than the skeleton itself. Lives in the kit since proof-gate.sh already does. The determinism-hash field named in the intent did not carry into the built shape; the skeleton carries Green run, Negative control, Rollback (stateful only), and Not proven.
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-11

