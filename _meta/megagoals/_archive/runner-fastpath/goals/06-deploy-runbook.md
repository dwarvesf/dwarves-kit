# Sub-goal 06: deploy-runbook

**Merge policy:** gate (Han reviews this PR before the first real overnight run; the held review IS the pre-flight check)
**Time budget:** 1-2 hours after 04
**Proof:** run-table of the LIVE smoke queue run executed ON the Air, locally (real journal row + log excerpt) + the runbook file
**Design:** obvious (docs + a local smoke; no new component)
**Depends on:** 03K MERGED (the kit `orchestrate.sh queue`; the smoke uses a tsv/fixture queue).
Model: sonnet
**Branch:** `feat/runner-air-deploy` (ops-toolkit)
**PR base:** main

## Outcome

The Air can drain the queue tonight-onward with zero rediscovery (Han's call 2026-07-04: run on the Air, not the Mini): a runbook (prerequisites + start/attach/read/stop + failure modes) and a proven live smoke run started the exact way Han will start real nights: local tmux wrapped in `caffeinate`, manual Phase 1.

## Quality bar

Minimum infra: Phase 1 is a local `caffeinate -dims tmux new -d -s mega-queue '<kit>/bin/orchestrate.sh queue --from-boards'` one-liner, nothing else; no launchd, no new daemons, no ssh. The runbook covers the three planes (config in repo; secrets N/A; runtime state = `runs/` journal/logs, gitignored) and names the two later options WITHOUT building them: launchd Phase 2 (trigger: journal shows a steady nightly cadence) and a Mini migration (same steps over `ssh mini-tieubao`; the Mini is the always-on home if the Air proves annoying to leave awake).

## How to close the loop

- Runbook content: prerequisites (the kit on PATH: `orchestrate.sh` + `board`; NO build, it is bash; `CONSUMER_ROOT`=ops-toolkit so the queue reads the personal `boards.txt`), the `caffeinate -dims` + tmux one-liner running `orchestrate.sh queue --from-boards` (Mac sleep silently kills an unattended multi-hour run; on the Air it WILL sleep without `caffeinate`, say which), `orchestrate.sh queue --dry-run` as the mandatory pre-night sanity step, how to attach/detach, how to read the queue journal + logs in the morning, how to stop a night safely (tmux kill vs letting the row finish), the two 3am assumptions (error-twice stops the night; markers are contract).
- Live smoke, LOCAL on the Air: run the same throwaway-fixture smoke 03K defined (a `/goal` pointer ending in `RUNNER_DONE`, launched via tmux send-keys into a real Claude Code session) inside the exact caffeinate+tmux invocation the runbook prescribes. Capture the journal row + the tmux session name in the proof.
- The smoke must NOT touch real repos; the fixture repo lives under tmp.

**Done =** runbook committed (ops-toolkit; it documents running the KIT `orchestrate.sh queue` on the Air) + the Air smoke journal row captured in proof-of-done + this PR opened and HELD (gate banner: NEEDS APPROVAL; do not merge).

Kit-adopted repo: record gate-ledger phases before push.

## Handoff on completion

1. Flip the ROADMAP box + PR # (box may flip when the PR is open + CI green; the GATE hold is about MERGING, per the merge-autonomy rules).
2. Overwrite HANDOFF.md: next = convergence gate (or 05 if unparked).
3. Append to DECISIONS.md: the build-artifact choice + anything learned about running headless claude under caffeinate/tmux (auth, PATH, env).
4. Report IN the records, then EXIT IMMEDIATELY.

## Scope edges

**In:** runbook, local Air smoke, any tiny Makefile/build convenience the runbook needs.
**Out:** launchd plists (parked), cron, new users, new daemons, anything over ssh (the Mini paragraph is prose, not an executed step).
**Not:** running a REAL mega in this sub-goal; the first real night is Han's action after his gate review.

## Where to look

`tools/hermes/deploy/macos/personal/mini.hermes-runbook.md` (the canonical runbook shape; adapt, don't copy), 03K's contract + PR (the launcher's flags + journal), the machines table in the global CLAUDE.md (for the later-Mini paragraph only).

## PR body

- Outcome: Air deploy runbook + proven live local smoke (journal row inline). Phase 1 manual caffeinate+tmux; launchd + Mini migration parked with triggers named.
- Verification: the smoke run-table.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`. Stacked on 04's PR if unmerged. GATE: hold for Han.

## Notes

- 2026-07-04: retargeted Mini -> Air per Han ("ok chay o mac air nhe") before launch; the Mini remains the named later option in the runbook prose.
