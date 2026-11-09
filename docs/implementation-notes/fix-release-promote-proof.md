# fix/release-promote-proof: delta notes

Scout claims 1 to 3 reproduced with a failing test first. Claim 4 was measured, then built to the lead's rule (see below).

## Decisions

- **Dry-run refuses a dirty release surface.** It checks only the four files it restores (`VERSION`, `plugin.json`, `tool.toml`, `CHANGELOG.md`). Edits elsewhere in the tree still allow a preview. A real cut still needs a fully clean tree.
- **Tag check runs before any file moves**, for dry-run and real cuts alike.
- **promote slug check** (`_valid_slug`) rejects empty, `.`, `..`, any `/`, and reserved names (`_rejected`, `_replaced`, `_archive`). Applied to promote and reject, both return 2. Before this, `reject _replaced` moved the backup tree into `_rejected/`, and `reject ..` hit the state dir.
- **`--force` aborts (rc 5) when the backup mkdir or mv fails.** The draft stays staged and the live skill stays intact.
- **Reviewer skip rule.** A draft is skipped when `_rejected/<slug>` or `_rejected/<slug>-YYYYMMDD-HHMMSS` exists (`skip-rejected`), or `skills/<slug>` exists (`skip-live`). A different slug that merely shares a prefix is not blocked.
- **`test-staging-gate.sh` check 5 loosened by one line.** It banned every `$SKILL_CURATOR_SKILLS_DIR` reference in `reviewer-run.sh`. It now allows only the read-only `if [ -e "$SKILL_CURATOR_SKILLS_DIR/$slug" ]` check. Any other reference still fails (checked by appending a `cp` line).

## Item 4 (proof-ledger green reader)

Lead decision: no migration of stored proofs. A proof is green iff it is not vetoed and one of: (a) its last line-start `Verdict:` is PASS; (b) an `Exit: 0` line; (c) a table cell starting `PASS` or `PASSED`, with no cell that is exactly `FAIL` or `INCONCLUSIVE`; (d) a line-start `PASS` harness token (`PASS  C-cut fires`). Veto is unchanged: a last `Verdict:` of FAIL or INCONCLUSIVE. A bare PASS in prose no longer counts. Implemented as `_green_marks` in `lib/gate/proof-ledger.sh`.

Measured over 141 units (every `docs/verification/**/*.md`, every `proof-of-done.md`, two set-wise groups): 2 flip green to not green, 139 unchanged, 0 flip not-green to green. A strict reading of (c) alone flipped 11, which is why (d) and the `PASSED` cell form exist.

| Flipped unit | Why |
|---|---|
| docs/verification/test-design-standard.md | A standards doc, not a proof. PASS appears only in prose ("A false PASS is worse than an honest gap"). Accepted. |
| lib/webcheck/docs/proof-of-done.md | `PASSED 81/81` sits inside a backticked cell and `exit 0` is plain text, so no marker matches. The file flips only when next edited. Not edited here. |

A harness `FAIL` line does not veto (d), only a FAIL or INCONCLUSIVE table cell does: negative-control sections legitimately print RED lines.

## Open questions

- **Stream PUT ordering in `bin/release`** is unchanged: the stream PUT happens after the local commit and tag, so a failed PUT leaves a tagged commit with no published bundle. Needs a call on whether the PUT should come first or be retryable.
- **Same-slug update drafts.** The reviewer prompt cannot see the library and may propose a patch to an existing skill under the same slug. `skip-live` now drops those. `promote --force` was the intended path for such updates.
