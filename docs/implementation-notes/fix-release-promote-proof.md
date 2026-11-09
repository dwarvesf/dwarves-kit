# fix/release-promote-proof: delta notes

Scout claims 1 to 3 reproduced with a failing test first. Claim 4 was measured and stopped (see below).

## Decisions

- **Dry-run refuses a dirty release surface.** It checks only the four files it restores (`VERSION`, `plugin.json`, `tool.toml`, `CHANGELOG.md`). Edits elsewhere in the tree still allow a preview. A real cut still needs a fully clean tree.
- **Tag check runs before any file moves**, for dry-run and real cuts alike.
- **promote slug check** (`_valid_slug`) rejects empty, `.`, `..`, any `/`, and reserved names (`_rejected`, `_replaced`, `_archive`). Applied to promote and reject, both return 2. Before this, `reject _replaced` moved the backup tree into `_rejected/`, and `reject ..` hit the state dir.
- **`--force` aborts (rc 5) when the backup mkdir or mv fails.** The draft stays staged and the live skill stays intact.
- **Reviewer skip rule.** A draft is skipped when `_rejected/<slug>` or `_rejected/<slug>-YYYYMMDD-HHMMSS` exists (`skip-rejected`), or `skills/<slug>` exists (`skip-live`). A different slug that merely shares a prefix is not blocked.
- **`test-staging-gate.sh` check 5 loosened by one line.** It banned every `$SKILL_CURATOR_SKILLS_DIR` reference in `reviewer-run.sh`. It now allows only the read-only `if [ -e "$SKILL_CURATOR_SKILLS_DIR/$slug" ]` check. Any other reference still fails (checked by appending a `cp` line).

## Item 4 (proof-ledger verdict): stopped, not committed

Compared the old green reader (`Exit: 0`, `Verdict: PASS`, or bare `PASS` anywhere) with a reader that accepts `Exit: 0` or a last line-start `Verdict:` of PASS. Over 141 proof units in the kit (every `docs/verification/**/*.md` and `proof-of-done.md`, plus two set-wise groups): 17 flip from green to not green, 124 unchanged.

All 17 are older hand-written acceptance tables with `| PASS |` cells and no `Exit: 0` or `Verdict:` line:

- docs/verification/done-modes.md
- docs/verification/test-design-standard.md
- lib/bench/docs/proof-of-done.md
- lib/session/intel/docs/proof-of-done.md
- lib/webcheck/docs/proof-of-done.md
- lib/stats/docs/verification/{anomalies-advisor,defect-correlation,deviation-rate,docs-wiring,kit-gates-lens,memory-lens,review-yield-lens,sessions-digest}.md
- lib/stats/docs/verification/feedback-loop/feedback-loop.md and its group
- lib/stats/docs/verification/render-skill/render-skill.md and its group

The gate only reads files fresh in a diff, so history is not re-gated. A future edit to any of these would flip it to not green. The decision is open.

## Open questions

- **Stream PUT ordering in `bin/release`** is unchanged: the stream PUT happens after the local commit and tag, so a failed PUT leaves a tagged commit with no published bundle. Needs a call on whether the PUT should come first or be retryable.
- **Same-slug update drafts.** The reviewer prompt cannot see the library and may propose a patch to an existing skill under the same slug. `skip-live` now drops those. `promote --force` was the intended path for such updates.
- **Item 4 policy:** accept a table `PASS` cell as green, migrate the 17 files to a `Verdict:` line, or leave the bare-`PASS` rule.
