# Implementation notes -- adopt-land

Deltas from SPEC-387. Nothing here repeats what the spec already states.

## 2026-10-04 Lead decisions on the validation process

- The round 1 reviewers read blob `a7b2ee75` (ledger round 2). That round closed `void why=head` because handoff commits moved HEAD, so the ledger holds no NEEDS-REVISION close. Its findings live only here and in the handoff. The re-validation diffs against `a7b2ee75`, the blob the reviewers actually saw, not the first pin `ba485ee0`.
- All seven re-validation reviewers run on Opus, not Sonnet. Sonnet sits at its weekly limit until Oct 8.
- The full lane's separate fold-diff check is skipped. The re-validation round re-runs all seven lenses with the fold diff as context, which covers the same ground.
- The handoff said to fold every finding into the spec. `commands/spec-validate.md` folds criticals only, so warnings and notes went to this file instead.

## 2026-10-04 Validation round 1: warnings and notes for the builder

The criticals and the design-record warnings are in the spec (DEC-H to DEC-N). Two warnings were folded with a critical because its fix needs them: land's exit code first plus the exact `tree verified` line (R8), and the `2>&1 | tee` capture read through `PIPESTATUS[0]` (R9). Everything below is builder guidance, one bullet per finding, with the source quote where it was checked. Round 2 moved several bullets into the spec; the round 2 section lists them.

### Security lens (R1)

- Honor `WRAP_ADOPT_SH` only under a test flag (for example `KIT_WRAP_TEST=1`, or whatever flag `tests/lib/wrap-stub.sh` already exports). Unflagged, an inherited env var swaps the file writer that runs right before an override and a merge.
- Override timing: decided in round 2 (spec DEC-Q). The override stays before land, as R7 says, so a hand `wrap land <wt>` resume never runs without it. Do not move it after the merge.

### Failure-modes lens (R2)

- When land printed no `REFUSED`/`FAILED` line, fall back to its last captured stderr line plus the exit code. The `wrap.sh land: ...` refusals (dirty, detached, no commits ahead, gh state) carry neither word.
- R3f: `ls-remote` exit codes other than 0 and 2 mean `refused: origin unreachable`, never "absent". Also read the tracking ref `refs/remotes/origin/chore/kit-adopt`, as `cmd_start` does (`wrap-start.sh`: `_ref_exists "$repo" "refs/remotes/origin/${branch}" || git -C "$repo" ls-remote --exit-code --heads origin "$branch"`).

### Design lens (R5)

- R3j, refuse a default branch ahead of origin: NOT built as written. The spec's Out of Scope keeps this repo shape running on purpose ("land still merges; the row names the `PULL BLOCKED` line (case 21)"). Adding R3j changes case 21 and needs a spec change first, not a builder call.
- Edge case 1 wording: the fast-forward updates only the paths that differ between `HEAD` and `origin/<def>`, and `_land_ff_pull` carries a dirty `merge=union` file across (`wrap-land.sh`: "A dirty file the repo declares merge=union is carried across"). Dirt on any other path does not block the pull. Read edge 1 that way.
- Case 22: also set an `output.style` knob in the fixture, so the drift guard covers `.claude/output-styles/<name>.md` and the `outputStyle` key (`adopt.sh` step 6b writes both).

### Assumptions lens (R3)

- Capture form: the lens proposed `> >(tee "$log") 2>&1` (process substitution) to keep land in this shell. The spec chose `2>&1 | tee -i "$log" || land_rc=${PIPESTATUS[0]}`. `lib/wrap/wrap.sh` runs `set -uo pipefail` with no `-e`, so the failing pipeline does not abort, and a scratch run confirmed `PIPESTATUS[0]` holds the function's exit code there. Process substitution needs a wait for `tee` to flush before the parse; the pipe does not.
- An open `chore/kit-adopt` PR with no local branch (deleted by hand, or a second machine): R3f's `on origin` refusal should also look up the open PR with `gh pr list --head chore/kit-adopt` and print its number with a resume hint. That covers a repo that requires review, has squash disabled, or a non-GitHub origin, where land opened the PR and stopped.
- Only `ls-remote --exit-code` exit 2 means absent (`wrap-land.sh`: "exit 2 of --exit-code is the only \"absent\""). Same as the R2 bullet above.
- Stale-read note: preflight never fetches, so when the main checkout's `HEAD` differs from its local `refs/remotes/origin/<def>`, R3a and R3i read an older tree. Print one `note: main checkout differs from origin/<def> as last fetched` line on the dry-run row.
- R3g should also check `@{u}`: a default branch whose upstream is not `origin/<def>` makes `pull --ff-only` pull from elsewhere.

## 2026-10-04 Round 2 (re-validation) outcome

Two criticals and the lead's decisions on the open warnings went into the spec. The rest is builder guidance below.

### Into the spec

- C1, R3f reads the merged-PR state before `resume:` (DEC-O, case 31, the exit-3 Failure-modes row).
- C2, R3k refuses a gitignored `ADOPT_PATHS` entry with `check-ignore --no-index` (DEC-P, case 32). The round 1 gitignore bullet left this file.
- `--title` dropped everywhere (DEC-Q). The round 1 `--title` bullet left this file.
- `--body-file` with more than one repo is usage; `resume:` repeats `--body-file F` (DEC-Q, case 24). The round 1 batch `--body-file` bullet left this file.
- `_reject_packed` on every repo argument (R1, case 24). The round 1 bullet left this file.
- Override timing stays before land (DEC-Q). The round 1 "pick one" bullet is now the decided bullet above.
- Operator-only `--apply` stated as policy, not mechanism (Boundaries, DEC-J).
- R6a precision: `jq` `test()` engine, `\A`/`\z` anchors, kit-entry key set, base-side strip, empty `hooks` drop, event/matcher/index in the row (DEC-R, case 25 variants).
- R6 narrows `.claude/output-styles/` to the staged style file (DEC-R, case 36).
- R6b post-commit recheck (DEC-S, case 33).
- Interrupt stop, `not run` rows, `tee -i`, and land's `wrap merge` advice quoted instead of `resume:` (DEC-T, cases 34, 35).
- Per-repo `result:` line as each repo finishes (Interfaces). The round 1 "print each row as it finishes" bullet left this file.
- Task and case mapping, T1d waiver, global AC suites, fixture-based Verification and After state (DEC-U). The round 1 "observed, not guaranteed" bullet left this file.
- Edge cases 3 and 5 now use the R6 and R8 row texts.
- The land-output-text coupling is named as suite-guarded in the spec's Extensibility.

### Builder guidance

- Case 22 runs with every hook-bearing module on: `board`, `session`, `advisor`, `cosmetic` all `true` in the fixture's `[modules]`. That wires the widest hook set `adopt.sh` can write (its header: "wires the currently-enabled HOOK-bearing modules (board, session, advisor, cosmetic)"), so R6a sees every shipped command shape.
- A counted merge where land then exits 2 on its tidy (`FAILED remove worktree ...` or `FAILED delete <branch>`, the last two `return 2` arms of `_land_tidy`): R8 runs the check and may read `adopted`. Append land's `FAILED` line to that row, so a stranded worktree or branch stays visible.
- A `no change` row leaves an empty worktree and a `chore/kit-adopt` branch with no commit ahead. Note it in the row text the spec already gives; the verb does no cleanup (R12), and R3f names both on a re-run.
