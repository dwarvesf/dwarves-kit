# Implementation notes -- adopt-land

Deltas from SPEC-387. Nothing here repeats what the spec already states.

## 2026-10-04 Lead decisions on the validation process

- The round 1 reviewers read blob `a7b2ee75` (ledger round 2). That round closed `void why=head` because handoff commits moved HEAD, so the ledger holds no NEEDS-REVISION close. Its findings live only here and in the handoff. The re-validation diffs against `a7b2ee75`, the blob the reviewers actually saw, not the first pin `ba485ee0`.
- All seven re-validation reviewers run on Opus, not Sonnet. Sonnet sits at its weekly limit until Oct 8.
- The full lane's separate fold-diff check is skipped. The re-validation round re-runs all seven lenses with the fold diff as context, which covers the same ground.
- The handoff said to fold every finding into the spec. `commands/spec-validate.md` folds criticals only, so warnings and notes went to this file instead.

## 2026-10-04 Validation round 1: warnings and notes for the builder

The criticals and the design-record warnings are in the spec (DEC-H to DEC-N). Two warnings were folded with a critical because its fix needs them: land's exit code first plus the exact `tree verified` line (R8), and the `2>&1 | tee` capture read through `PIPESTATUS[0]` (R9). Everything below is builder guidance, one bullet per finding, with the source quote where it was checked.

### Scope lens (R4)

- Drop `--title`. The commit subject and the PR title are both `ADOPT_COMMIT_SUBJECT`, and with no `--title` `cmd_land` reads it from the one commit ahead (`_land_feature_title`: "Falls back to the oldest non-merge commit ahead when every one is housekeeping"). A flag that can only restate the default is surface with no user. If dropped, R1, Interfaces, the Picture and case 24 lose their `--title` mentions in the same change.
- Label the live-repo checks as observed, not guaranteed: Grounding G1's per-repo output, the Verification third line, and the After state's first bullet name real repos whose state moves (dotfiles has since been adopted single-source). Read them as "observed at spec time"; the fixture cases are the contract.

### Security lens (R1)

- Honor `WRAP_ADOPT_SH` only under a test flag (for example `KIT_WRAP_TEST=1`, or whatever flag `tests/lib/wrap-stub.sh` already exports). Unflagged, an inherited env var swaps the file writer that runs right before an override and a merge.
- Log the override only after the counted merge, with `pr=#<n>` in the reason. Two source facts shape this. First, after a counted merge `_land_tidy` removes the worktree, so the call must run from `<repo>`; `_repo_id` keys on the git common dir, so the main checkout and the worktree share one id (`proof-ledger.sh`: "so ALL worktrees of one repo share a key"). Second, a resume through a hand `wrap land <wt>` (spec R12) never returns to the verb, so a post-merge override is never written on that path. G4 says the override gates nothing on land's push, so the only cost is a missing audit line on resumed repos. Pick one and record it here.
- Refuse one `--body-file` across a multi-repo batch (usage, exit 64): one PR body written for one repo's template is wrong for the next.
- Run every repo argument through `_reject_packed adopt "$arg"`, as `cmd_start` and `cmd_land` do (`wrap-common.sh`: "the shape an unsplit variable (zsh `$args`) produces").

### Failure-modes lens (R2)

- When land printed no `REFUSED`/`FAILED` line, fall back to its last captured stderr line plus the exit code. The `wrap.sh land: ...` refusals (dirty, detached, no commits ahead, gh state) carry neither word.
- Refuse a gitignored `ADOPT_PATHS` entry in preflight. With `.claude/` ignored by the target repo, `git add -A` in the worktree skips `.claude/settings.json`, so the adoption commits without its hook wiring and `adopt.sh --check` may still read it as adopted. `git -C <repo> check-ignore -q -- <path>` per path is the cheap read; `git status --porcelain --ignored=matching` is the form `cmd_land` already uses for its baseline (`wrap-land.sh`: `st0="$(git -C "$wt" status --porcelain --ignored=matching ...)"`).
- R3f: `ls-remote` exit codes other than 0 and 2 mean `refused: origin unreachable`, never "absent". Also read the tracking ref `refs/remotes/origin/chore/kit-adopt`, as `cmd_start` does (`wrap-start.sh`: `_ref_exists "$repo" "refs/remotes/origin/${branch}" || git -C "$repo" ls-remote --exit-code --heads origin "$branch"`).
- Print each summary row as its repo finishes, then the full `ADOPT SUMMARY` at the end. A batch interrupted mid-way otherwise shows no result for the repos that already ran.

### Design lens (R5)

- R3j, refuse a default branch ahead of origin: NOT built as written. The spec's Out of Scope keeps this repo shape running on purpose ("land still merges; the row names the `PULL BLOCKED` line (case 21)"). Adding R3j changes case 21 and needs a spec change first, not a builder call.
- Edge case 1 wording: the fast-forward updates only the paths that differ between `HEAD` and `origin/<def>`, and `_land_ff_pull` carries a dirty `merge=union` file across (`wrap-land.sh`: "A dirty file the repo declares merge=union is carried across"). Dirt on any other path does not block the pull. Read edge 1 that way.
- Case 22: also set an `output.style` knob in the fixture, so the drift guard covers `.claude/output-styles/<name>.md` and the `outputStyle` key (`adopt.sh` step 6b writes both).

### Assumptions lens (R3)

- Capture form: the lens proposed `> >(tee "$log") 2>&1` (process substitution) to keep land in this shell. The spec chose `2>&1 | tee "$log" || land_rc=${PIPESTATUS[0]}`. `lib/wrap/wrap.sh` runs `set -uo pipefail` with no `-e`, so the failing pipeline does not abort, and a scratch run confirmed `PIPESTATUS[0]` holds the function's exit code there. Process substitution needs a wait for `tee` to flush before the parse; the pipe does not.
- An open `chore/kit-adopt` PR with no local branch (deleted by hand, or a second machine): R3f's `on origin` refusal should also look up the open PR with `gh pr list --head chore/kit-adopt` and print its number with a resume hint. That covers a repo that requires review, has squash disabled, or a non-GitHub origin, where land opened the PR and stopped.
- Only `ls-remote --exit-code` exit 2 means absent (`wrap-land.sh`: "exit 2 of --exit-code is the only \"absent\""). Same as the R2 bullet above.
- Stale-read note: preflight never fetches, so when the main checkout's `HEAD` differs from its local `refs/remotes/origin/<def>`, R3a and R3i read an older tree. Print one `note: main checkout differs from origin/<def> as last fetched` line on the dry-run row.
- R3g should also check `@{u}`: a default branch whose upstream is not `origin/<def>` makes `pull --ff-only` pull from elsewhere.
