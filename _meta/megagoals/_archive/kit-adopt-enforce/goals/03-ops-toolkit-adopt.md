# Sub-goal 03: adopt ops-toolkit + prove the gate bites

**Time budget:** 1-2 hours of loop work, after 01 + 02 are MERGED to dwarves-kit master
**Depends on:** 01 + 02 (the installed kit at `~/.claude/dwarves-kit` must carry the new command + the fail-closed gate; refresh the install if its hooks are copied rather than symlinked)
**Branch:** `feat/kit-adopt-03-otk` (in `~/workspace/<owner>/ops-toolkit`)

## Outcome

ops-toolkit stops being the repo where a full-lane change can ship review-less. After this, a session opening here is told to classify the work and pick a lane (the operate-contract is present and loaded), and a push that skips the lane's required gates is blocked, not waved through. The exact gap that bit the growatt-tui work is closed and proven closed.

## Quality bar

The proof is a reproduction, not an assertion. You must recreate the growatt-tui failure shape (an active spec, full lane, review gate never recorded) and show the gate now blocks the push, then show it passing once review is recorded. The contract files are real and loaded (CLAUDE.md actually points at AGENTS.md), not just dropped on disk.

## How to close the loop

    # 1. Adopt (uses the command from 01, now in the installed kit):
    cd ~/workspace/<owner>/ops-toolkit
    /kit:adopt .    # or the CLI it shells to
    test -f AGENTS.md && test -f WORKFLOW.md && grep -q -i 'AGENTS.md' CLAUDE.md
    # 2. Classifiers reachable + loop-type -> artifact resolves here:
    bash ~/.claude/dwarves-kit/lib/proof-gate.sh contract "add a data-pull CLI command"   # -> recorded live run
    bash ~/.claude/dwarves-kit/lib/proof-gate.sh contract "benchmark tool X vs Y"          # -> TEST-REPORT
    # 3. Reproduce the growatt-tui failure mode and show it BLOCKED:
    #    craft a branch state with an active full-lane spec + NO review gate recorded, then:
    printf '{"tool_input":{"command":"git push -u origin feat/demo"}}' \
      | bash ~/.claude/dwarves-kit/hooks/ship-gate.sh ; echo "exit=$?"   # expect 2 (blocked)
    #    record the lane + review gate, re-run:
    printf '{"tool_input":{"command":"git push -u origin feat/demo"}}' \
      | bash ~/.claude/dwarves-kit/hooks/ship-gate.sh ; echo "exit=$?"   # expect 0 (passes)

Capture this as a recorded run under `docs/verification/` (this is a behavioral/stateful change to how the repo gates pushes; it owes a recorded live run + the negative control = the blocked push).

**Done =** AGENTS.md + WORKFLOW.md + a CLAUDE.md loader pointer are present in ops-toolkit, `proof-gate.sh contract` resolves two task types to two artifacts from here, and a crafted push that skips the review gate on a full-lane spec is BLOCKED (exit 2) while the same push passes once review is recorded, captured as a recorded run with its negative control. PR open + CI green.

## Scope edges

**In:** ops-toolkit's new AGENTS.md + WORKFLOW.md (+ adjustments so they fit this repo, not dwarves-kit's self-development copy), the CLAUDE.md loader pointer line, a `docs/verification/<slug>.md` recorded run proving the gate bites.
**Out:** any dwarves-kit change (that was 01 + 02; if you find a kit bug here, log it to NOTES.md ## Proposed additions, do not fix it in this sub-goal).
**Not:** migrating other repos (family-office, trading, etc.) into the kit; rewriting ops-toolkit's existing CLAUDE.md beyond the one loader line + necessary lane notes; back-filling lanes onto past specs. Adopt this one repo, prove the bite, stop.

## Where to look

ops-toolkit root (`CLAUDE.md`, where AGENTS.md/WORKFLOW.md land), `docs/verification/README.md` (the proof marker that makes the gate engage here) and `tools/growatt-pull/docs/specs/growatt-tui.md` (the real full-lane spec to model the reproduction on), the installed kit at `~/.claude/dwarves-kit/` (hooks + lib the adopt + gate run from). Worktree off ops-toolkit main.

## PR body

Adopts ops-toolkit into the dwarves-kit operate-contract via `/kit:adopt`: AGENTS.md + WORKFLOW.md + a CLAUDE.md loader line land, the lane/loop-type/proof classifiers are reachable, and a recorded run proves the ship-gate now BLOCKS a review-less push on a full-lane spec (the exact growatt-tui gap) and passes once review is recorded.

Verify: see the close-the-loop block (adopt -> files present -> `proof-gate.sh contract` resolves two types -> crafted push blocked then passing). Recorded run + negative control under `docs/verification/`.

Part of mega-goal kit-adopt-enforce. Consumes the merged PRs for 01 + 02.

## Notes

(empty)
