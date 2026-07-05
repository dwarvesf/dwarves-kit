You are running an autonomous mega-goal loop in the ops-toolkit repo. Read `_meta/megagoals/cc-elevation/ROADMAP.md` every turn; it is the source of truth. Walk it top to bottom, pick the next unchecked sub-goal that is not blocked, load its file under `_meta/megagoals/cc-elevation/goals/`, and execute it to its `Done =`.

WORKFLOW (hard rules):
- One PR per sub-goal via `gh`. Sub-goals 01-05 are independent: branch each off `main` (base `main`), open in parallel. Sub-goal 06 is stacked: branch off `feat/cc-elevation-05-sweeps` and `gh pr create --base feat/cc-elevation-05-sweeps`.
- Branch into a worktree under `.claude/worktrees/<branch>` (native EnterWorktree), never an in-place branch.
- The moment `gh pr create` returns, set the ROADMAP line to `- [ ] NN-... PR #X`.
- A box flips to `[x]` only when: PR open + CI green (`gh pr checks`) + no CHANGES_REQUESTED + the sub-goal's own Done verified. No other form of checked box.
- Do NOT merge any PR under any rationale. The human merges bottom-up.
- ROADMAP is truth, not memory. No new sub-goals mid-loop; discoveries go to `NOTES.md` ## Proposed additions.

SDD (this repo is kit-adopted):
- Per sub-goal, classify the lane: `bash ~/.claude/dwarves-kit/lib/lane-classify.sh classify "<sub-goal outcome>"`, run that lane, let the ship-gate be the Done check. New tools (01-05) each owe a `tools/<name>/docs/proof-of-done.md` or the gate blocks the push; 06 extends 05's proof.

PRIVACY (hard):
- Sub-goal 03 embeds locally on the Air only (fastembed). Do NOT send til/research/ledger prose to any cloud embedder (no Voyage), and do NOT include the Obsidian vault, unless the sub-goal file says Han flipped that knob.
- Sub-goal 04 may use Claude Haiku (the transcript is already in-session); it stages `queued` ledger rows only, never writes GLOSSARY/til/research.

VERIFICATION:
- Each sub-goal file has its own close-the-loop commands. Run those, not generic tests.
- Before claiming success: extract every PR # from ROADMAP and `gh pr view <N> --json state,reviewDecision,statusCheckRollup`. Any failure: uncheck and resume.

NOTES.md DISCIPLINE:
- ## Active blockers: updated in place, fingerprint `cmd · failure · prerequisite · last verified`; same fingerprint twice bumps the timestamp only.
- ## Proposed additions and ## Event log: append-only.

STOP CONDITIONS: all sub-goals checked-with-PR (success); every remaining sub-goal blocked on an unchanged prerequisite; or token budget exhausted.

FAST-STOP: the first fast-stop appends a final summary block to `NOTES.md` ## Event log; subsequent fast-stops (no prerequisite change, no PR moved) emit ONE line `LOOP BLOCKED - STOP /goal MANUALLY` and nothing else.

CLOSE-OUT (ops-toolkit): before marking the mega-goal complete, add a concise `_meta/LAB_LOG.md` entry (dated, newest-first) covering the arc (slug cc-elevation, 6 sub-goals, PR range, key lessons) on the LAST sub-goal's branch so it rides into that PR (SPEC-005). Then mark complete.
