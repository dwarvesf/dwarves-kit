# NOTES, kit-adopt-enforce

## Active blockers

(none. All sub-goals 01-04 MERGED; absorption A1+A2 MERGED. See Event log 2026-06-10.)

## Proposed additions

(append-only. Sub-goals discovered mid-run but NOT worked. Format: `- <YYYY-MM-DD>: idea — <one-line Done> — discovered during NN — <why>`)

- 2026-06-09: sub-goal 04 (dwarves-kit), install.sh ships the root AGENTS.md + WORKFLOW.md into ~/.claude/dwarves-kit (or adopt.sh/gate-ledger resolve them via the symlinked lib with pwd -P), Done = `bash ~/.claude/dwarves-kit/lib/adopt.sh <tmp>` works AND `gate-ledger required full` reads the matrix, both from the INSTALL with no repo present, discovered during 03, without this the mega-goal's "self-install" only works when the kit repo is checked out next to the install (both files missing from the install break adopt's AGENTS.md source + the lane-matrix read). HIGH: this is the gap between the 3 shipped sub-goals and the destination fully holding.
- 2026-06-09: sub-goal 05 (dwarves-kit), ship-gate resolves the active spec without coupling to the branch slug (fall back to the newest VALIDATED spec, or warn when a branch has gate-ledger entries but no slug-matching spec), Done = a dev branch whose name differs from its spec slug still gets gated, discovered during 02, today the kit fails open on its own mismatched-slug pushes.
- 2026-06-10: A3 (dwarves-kit), absorb repository-harness's 10-flag risk checklist + count-based lane tree into lane-classify, Done = a kit-machinery change classifies `full` not `normal` without a manual override, discovered during the 2026-06-10 dogfood, the keyword classifier under-classified BOTH #24 and #25 as `normal` when they were `full` (had to override by hand). MED. Source: dwarves-kit docs/absorption/2026-06-10-repository-harness.md.
- 2026-06-10: A4 (dwarves-kit), decision-capture as a routine terminal-lane step (the reflect gate emits a short structured decision file, not just narrative), discovered during the 2026-06-10 absorption. MED.
- 2026-06-10: deferred review nits from the 2026-06-10 dogfood (LOW, non-blocking, code merged without them). dwarves-kit lib/adopt.sh: canonicalize TARGET with realpath (a `../x` path traverses out of the intended dir). install.sh: prune the empty `~/.claude/dwarves-kit/` + `logs/` on --uninstall. tests/test-install-contract.sh: drop the dead `CLAUDE_PLUGIN_ROOT` passed to gate-ledger (it resolves via BASH_SOURCE, the env var is ignored). lib/adopt.sh usage: document the `--` terminator for a target dir starting with `-`. Full findings: the 6 reviewer reports were transcript-only; these 4 are the survivors worth tracking.

## Event log

(append-only, one line per event: `<YYYY-MM-DD HH:MM> · <type> · <detail>`. Final summary block on each stop.)

2026-06-10 · sub-goal 04 + absorption SHIPPED & MERGED · PR #24 (install ships AGENTS.md+WORKFLOW.md) + PR #25 (absorb A1 @AGENTS.md import + A2 --dry-run/--refresh) both squash-merged to dwarves-kit master. Full suite green on merged master (adopt 12/12, install-contract 3/3, meta 395/395).
2026-06-10 · DOGFOOD (the point of the whole mega-goal) · ran BOTH PRs back through the kit's own 3-lens review-team before merge. It bit: caught a CRITICAL (--refresh awk ate CLAUDE.md when END marker missing; 3 reviewers independently) + 2 HIGH (install rm -f could destroy a real file; tests simulated the layout, never ran install.sh). All fixed via respond-to-review + re-verified with live proof + negative control, recorded in dwarves-kit docs/verification/{kit-adopt,install-ships-contract}.md. This is the proof the gate works: a full-lane change does NOT ship review-less.
2026-06-10 · DOGFOOD FINDING (-> A3) · lane-classify called both kit-machinery PRs `normal`; they are `full`. Overrode by hand. The keyword classifier keeps under-classifying the changes that matter most; absorbing repository-harness's flag-count tree (A3) is the fix.

==== MEGA-GOAL FULLY COMPLETE 2026-06-10 ====
All 4 sub-goals MERGED (01 #22, 02 #23, 03 #163, 04 #24) + absorption A1/A2 #25. Destination holds from the INSTALL (not just the dev checkout). Open follow-ups all LOW/MED and recorded above: sub-goal 05, A3, A4, 4 review nits. This record folder was uncommitted until now; persisted on its own branch.
==============================================


2026-06-09 17:05 · sub-goal 03 SHIPPED · ops-toolkit adopted (AGENTS.md + WORKFLOW.md + CLAUDE.md loader); PR #163. Proof: gate blocks a full-lane spec with unrecorded gates (exit 2, the growatt-tui shape) and passes once recorded. ops-toolkit has no CI -> box [x] on proven Done + no CHANGES_REQUESTED.

==== MEGA-GOAL COMPLETE 2026-06-09 17:05 ====
All 3 sub-goals [x]: 01 PR #22 MERGED, 02 PR #23 MERGED, 03 PR #163 open (no-CI repo, Done proven).
Audit: #22 MERGED, #23 MERGED, #163 OPEN + no failing checks + no CHANGES_REQUESTED.
Destination caveat (honest): the 3 defined sub-goals are done, but two INSTALL-packaging gaps
(adopt + gate-ledger can't find AGENTS.md/WORKFLOW.md from ~/.claude/dwarves-kit) mean "self-install"
only fully holds with the kit repo checked out. Filed as sub-goal 04 (HIGH) in ## Proposed additions.
Human action left: merge PR #163; run sub-goal 04 when ready.
==============================================

2026-06-09 16:35 · sub-goal 01 MERGED · PR #22 squashed to dwarves-kit master (Han). /kit:adopt now on master.
2026-06-09 16:40 · sub-goal 02 SHIPPED · PR #23. ship-gate.sh fails closed on spec-no-lane in adopted repos; install.sh adopt path; tests/test-ship-gate-fail-closed.sh 5/5; meta 392/392; full lane recorded (check full kit-adopt-02-gate exit 0). Commit 94d1772.
2026-06-09 16:40 · DOGFOOD FINDING · ship-gate keys the spec off the BRANCH slug (SPEC-*-<branch-slug>.md), so my dev branches (kit-adopt-0N-*) whose names differ from their spec slugs (kit-adopt, ship-gate-fail-closed) fail OPEN on their own pushes. Feature verified via matching-slug tests; the dev-branch naming just doesn't trigger self-enforcement. Filed to FEEDBACK.

==== FINAL SUMMARY, blocked-stop 2026-06-09 16:40 ====
Outcome: 2 of 3 sub-goals shipped. 01 MERGED (PR #22). 02 SHIPPED (PR #23, CI starting), awaiting Han's merge. 03 blocked on #23 merge.
To resume: confirm #23 CI green, merge PR #23 to dwarves-kit master, then re-paste POINTER_PROMPT.md into /goal; the loop runs sub-goal 03 (adopt ops-toolkit + prove the gate bites) in this repo.
====================================================

2026-06-09 15:50 · sub-goal 01 start · branched `feat/kit-adopt-01-cmd` off dwarves-kit master; parked unrelated dirty `docs/ABSORPTION.md` via stash (recover: `git switch master && git stash pop`).
2026-06-09 15:54 · classify · lane-classify=normal, OVERRIDDEN to full (foundational kit machinery + couples w/ full-lane 02 + when-in-doubt-heavier + operator asked); task-type=spec-feature; proof=behavioral. Recorded as gate-ledger ACTION on `kit-adopt-01-cmd`. Full lane = think,design,design-critique,spec,validate,test-plan,build,review,docs,ship,reflect.
2026-06-09 15:55 · correction · dwarves-kit default is `master` not `main`; fixed in ROADMAP + goals/02 + goals/03. (The running /goal hook still injects the old `main` text; harmless, the per-repo reality is logged.)
2026-06-09 15:56 · note · dwarves-kit full lane is being dogfooded via the lib machinery directly (lane-classify/task-type/proof-gate/gate-ledger + reviewer agents), NOT the `/kit:*` slash commands, which bind to the ops-toolkit session cwd and cannot target dwarves-kit. Same gates, same ledger. impl-notes: dwarves-kit/docs/implementation-notes/kit-adopt-command.md. Next gate: think -> spec (SPEC-047).
2026-06-09 16:05 · sub-goal 01 build · SPEC-047 + lib/adopt.sh + commands/adopt.md + tests/test-adopt.sh (5/5) + architecture.md inventory row; meta suite 392/392; behavioral proof docs/verification/kit-adopt.md (green live adopt + classifier reachable + no-clobber control). Commits 46e07b4, 6bc3138 on feat/kit-adopt-01-cmd (off master). Gates recorded: think,design,design-critique,spec,validate,test-plan,build,docs. Remaining: review (review-team) -> ship (PR #01) -> reflect.
2026-06-09 16:05 · validate-finding · gate reads WORKFLOW.md + lib from KIT_ROOT (gate-ledger.sh:21), not the consumer; confirmed adopt should inject a WORKFLOW POINTER, not a copy. Recorded as the validate gate.
2026-06-09 16:18 · sub-goal 01 SHIPPED · PR #22 (dwarvesf/dwarves-kit, base master). All 11 full-lane gates recorded; `gate-ledger check full kit-adopt-01-cmd` exit 0. CI (test.yml macos+ubuntu) pending. Commits 46e07b4, 6bc3138, 1a6eb45.
2026-06-09 16:19 · DOGFOOD FINDING (proves sub-goal 02) · the `review` gate silently failed to record the first time (reason string with special chars), leaving the ledger incomplete, AND the CURRENT fail-open ship-gate let `git push`/PR #22 through anyway (dry-run exit 0) despite the gap. This is exactly the hole sub-goal 02 closes: once the lane arm fails closed, an incomplete ledger blocks the push. Re-recorded review cleanly; check full now passes.

==== FINAL SUMMARY, first blocked-stop 2026-06-09 16:20 ====
Outcome: 1 of 3 sub-goals shipped to a PR (01 -> PR #22, CI pending). 02 + 03 not startable.
Built sub-goal 01 (/kit:adopt) end-to-end through the kit's full lane: SPEC-047, lib/adopt.sh +
commands/adopt.md + tests/test-adopt.sh (5/5), meta 392/392, behavioral proof, all 11 gates in the
ledger. PR #22 open on dwarvesf/dwarves-kit (base master), NOT merged (shared repo, your nod).
Blockers: see ## Active blockers. 02 cannot open until you MERGE #22; 03 needs #22 + #02 merged.
01's box flips [x] once `gh pr checks 22` is green.
To resume: review + merge PR #22 (confirm CI green), then re-paste POINTER_PROMPT.md into /goal;
the loop will rebase + start sub-goal 02.
====================================================

2026-06-09 16:24 · sub-goal 01 [x] · PR #22 CI green (SUCCESS+SUCCESS), no CHANGES_REQUESTED; box flipped. Still blocked on Han's merge for 02.
