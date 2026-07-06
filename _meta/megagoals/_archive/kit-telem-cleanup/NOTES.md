# NOTES , kit-telem-cleanup

## Active blockers

<none yet>

## Proposed additions

Surfaced by the TIER-4 close (integration-verifier PASS, security-reviewer SECURE, advisor P5/P6).
NOT built in this wave; each is a filed follow-up for Han to filter.

- 2026-07-02: follow-up (not this wave) , RE-RUN the SPEC-073 effectiveness eval on a START-complete corpus once 01 (start-wiring) has been live for several days of real usage. This is the capstone that PROVES the "clean data" theme delivered; it is time-gated (needs real runs to accumulate), so it cannot run in-loop. Advisor P6-5.
- 2026-07-02: **wire `--files` into the real callers** (advisor P6-1 / P5-1). SG-05 shipped the discriminator + `--files` interface but no caller passes it (`assign.md`, `dispatch.md`, `orchestrate.sh:_emit_start` still classify text-only), so the machinery-mention over-gate still happens in practice. Wire it at a site that has the touched-file list: `/kit:dispatch`'s spec->sub-goal fan-out and a ship-time re-classify using `git diff --name-only`. **Constraint (security):** source the file list from a trusted `git diff`, never a model free-text claim, or a curated list could under-gate a real machinery edit.
- 2026-07-02: **add a `board=<ID-NNN|PR #N>` field to `gate-ledger.sh start`** (advisor P6-2 / P5-5). Populate it in `_emit_start` from the goal file's known BACKLOG ID / roadmap line. Fully closes the boardless-detector residual (the 3 runs SG-02's ID/PR matcher can't clear because their ledgers carry no board link) for ALL future runs, not just retroactively. Natural now that the START-emission point (SG-01) and the board-matching logic (SG-02) both exist.
- 2026-07-02: **`mega-merge.sh sweep`** (advisor P6-3 / P5-2). Scan `gh pr list` for any gate/gated-final PR missing the draft+`do-not-merge` mark; surface at `/kit:retro` like boardless runs. Converts the mark from "the loop must remember to run it while reading mega.md prose" into a detectable, retro-visible fact , the durable close for EVERY PR-open site (mega.md AND the `/goal`-loop's own gated-final open step, the second half ID-089 named).
- 2026-07-02: **branch-mismatch detector** (advisor P6-4 / P5-3). Assert the session's actual `git branch --show-current` matches the START line's rid, flagged like a misfire. SG-01's rid-from-declared-`**Branch:**` assumes declared==actual; a mismatch silently orphans the START (the exact untracked-run failure this wave fights) and no current detector catches it. Cheap , glues the rid-from-branch + misfires-detection patterns the wave just built.
- 2026-07-02: **one-off cleanup of the 14 leaked `completeness.log` fixture lines** (advisor P6-6). A one-off operator action (SPEC-103 scoped it out); until run, "produces CLEAN data" is literally true only going forward, not retroactively. A tiny strip script makes it true today.
- 2026-07-02: **generalize `mega-merge.sh mark` as the kit's standard "hold this PR" primitive** (advisor P6-7) , e.g. a `/kit:ship` PR a security/perf lens flags could call the same verb instead of reinventing draft+label logic.

## Event log

2026-07-02 · scaffold · kit-telem-cleanup created from the five `#kit-telem-followup` dwarves-kit board rows (ID-085/086/087/088/089), the follow-ups the kit-telemetry mega-goal's eval + reviews surfaced. 5 sub-goals, all `auto`, gh independent-off-master + auto-bottom-up + gated-final, cross-repo (roadmap in ops-toolkit, PRs in dwarves-kit).

2026-07-02 · COMPLETE · all 5 sub-goals built + shipped per posture. Auto-merged bottom-up: SG-01 #120 (8dbe47f), SG-02 #121 (d681dc0), SG-03 #122 (917891e), SG-04 #123 (da0c3bb). SG-05 #124 opened + HELD for Han (gated-final: draft + do-not-merge, applied live via SG-04's own `mark` verb which verified the mark landed against real GitHub state) , carries SG-05 + the TIER-4 close. On wrap-up Han authorized the merge: un-held (ready + label dropped) + squash-merged as 5f93161. All 5 now merged. TIER-4: integration-verifier PASS (5/5 wired), security-reviewer SECURE (0 blocker/high; Medium `mark` silent-failure + Low `$FILES` quoting fixed), advisor P5 (5 doc-honesty findings corrected across SPEC-102/104/105 + proofs) + P6 (7 proposals filed above). One CI retry: SG-04 #123 first run failed only on macos (bash 3.2 empty-array `"${rf[@]}"` under set -u); fixed with `${rf[@]+...}`, re-verified on `/bin/bash` 3.2.57, green. Every merged PR audited green (state MERGED, checks pass). Loop done; the held #124 is Han's to review + merge.
