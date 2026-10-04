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

## 2026-10-04 Final fold outcome

One critical (R3f printing `resume:` over a leftover that failed R6b) and three spec warnings went into the spec as DEC-V to DEC-Y, plus the wording corrections as DEC-Z. The operator approved this fold with a fold-diff check only, no new round.

### Into the spec

- C3, R3f re-runs R6/R6a on a leftover's committed diff before `resume:` (DEC-V, case 37).
- S1, R3k is plain `check-ignore` as the early refusal, and R6 fails on any `!!` line inside the worktree; the style file joins only when a style is reported (DEC-W, cases 32, 38). DEC-P's rationale is corrected: `add -A` drops only untracked ignored paths.
- S2, R3f matches a merged PR on head oid and base, with zero, one, and two-or-more outcomes and an unreadable state that never resumes (DEC-X, cases 30 (b), 31 (b), 39).
- S3, the INT/TERM trap in `cmd_adopt` (DEC-Y, case 34 with its `kill` mechanism).
- Wording: R8's `wrap merge` scan and last-line fallback, R6b `-z` over `merge-base..HEAD`, DEC-Q, the standing-pass override row, `WRAP_ADOPT_TEST=1`, `[--body-file F]` on every `resume:`, the Picture's exit-3 arm, T1c's scope, hand-built fixtures for cases 30 and 31, the gh precondition in Verification, Grounding G6, the T1d header check (DEC-Z).

### Builder guidance

- R6a base side: dedup hook entries with `unique_by(tostring)` before the compare, as `adopt.sh`'s merge does (`[.[].value[]] | unique_by(tostring) | sort_by(tostring)`). Add a case 22 variant whose base `.claude/settings.json` already holds one user hook and one stale kit hook; the guard must pass it.
- Read the staged `outputStyle` from the index blob `:.claude/settings.json` every time, never from the worktree file, so R6 and R6a judge the same bytes the commit takes.
- The `wrap merge` re-run path: when land leaves an open CONFLICTING PR, a later R3f could read that PR and quote land's `wrap merge --apply --pr <n>` line instead of `resume:`. Not in the spec; worth one case if it is built.
- A drift test asserting every shipped `.hooks` entry in the kit's `settings.json` is a kit entry under R6a's definition (type, key set, `KIT_HOOK_RE`). A new shipped hook shape then fails that test before it fails a real adoption.
- R6a's `outputStyle` pattern (`\A[A-Za-z0-9_.-]+\z`, no `..`) is stricter than `adopt.sh` step 6b, which rejects only `*/*` and `*..*`. A style name with another character fails closed: R6a refuses, nothing lands.
- T1b is the heaviest task. The builder may split the R6a cases (22, 25, 26, 36) into their own sub-task if T1b runs long.

## 2026-10-04 Fold-diff check

- An interrupted run keeps exit 1 under R11 (lead decision): the verb is operator-only, and the row already says `interrupted`, so no 130 or 143 exit code is needed.

## Fold-diff check outcome (clean, operator-approved path past the round ceiling)

- Case 34b: signal the process group (`kill -<SIG> -<pgid>`), never the verb's PID alone. A PID-only signal on `/bin/bash` 3.2.57 lets land finish and merge before the trap row prints, over a worktree land already tidied. The pgrp form matches a real Ctrl-C.
- Case 34a: the stub signals itself too (`kill -INT $PPID; kill -INT $$`). Bash defers SIGINT while it waits on a child that exits 0, so 130 shows up reliably only when the child also dies of the signal.

## T1a build

- `--apply` on a repo that passes preflight prints `failed: apply not built yet; nothing was written` (the not-yet-built refusal; smallest of the two options). Refusals under `--apply` report the same `refused:` row as the dry run. T1b replaces the row with `_adopt_one`.
- The `result:` line (`  result: - <row>`) already ships in T1a; the summary table stays T1c.
- R3g's upstream half is built (`main checkout tracks <up>, not origin/<def>`); it is skipped when R3b fired, since "main checkout is on ..." presumes a main checkout exists. `no default branch resolved` names the `_default_branch` failure both R3f and R3g depend on.
- The stale-read `note:` from the guidance is built: `note: main checkout differs from origin/<def> as last fetched`, printed as an indented line inside the repo block when HEAD disagrees with `refs/remotes/origin/<def>`.
- R3f's `ls-remote` exit-2-only-absent rule and `origin unreachable` are built; the tracking ref is checked first so a fetched remote never hits `ls-remote`.
- The open-PR-without-local-branch R3f hint (round-1 note) is NOT built: no spec row or case names its shape.
- `GH_STUB_MERGED_HEAD_RC` models a failed `--head` merged read (empty stdout, non-zero exit), beside `GH_STUB_MERGED_ALL_RC`.
- `bin/wrap` gains the `adopt` usage line too: the stable entrypoint's verb list would otherwise miss the verb.
- Case 5's collapse assertion greps `?? .claude/ ` with a trailing space: `?? .claude/` alone is a substring of `?? .claude/settings.json`.

## T1b build

- The spec's `KIT_HOOK_RE` constant is named `ADOPT_HOOK_RE` in code: `test-config-registry`'s drift lint treats every `$KIT_*` expansion in `lib/` as an unregistered env surface (`ORPHAN: KIT_HOOK_RE`), and this is a compile-time constant, not an env knob.
- `WRAP_ADOPT_SH` swaps the file writer only when `WRAP_ADOPT_TEST=1` AND the variable is non-empty; an unflagged inherited value can never replace the writer that runs before the override and merge.
- R6 narrows `.claude/output-styles/` to the one file the staged settings' `outputStyle` names (read from the index blob, never the worktree file); any other style file is a miss.
- The R6a norm-compare dedups each side's entries (`sort | unique`, the `unique_by(tostring)` shape the guidance asked for) and drops base entries whose command contains `dwarves-kit/hooks/` (adopt's own strip rule), so a stale kit hook already on base does not refuse. Every jq read fails closed: an unreadable staged or base blob is a refusal, not a pass.
- The `tee -i` capture sets `land_rc=${PIPESTATUS[0]}` unconditionally after the pipeline; the `||` form misses exit 130/143 because `tee -i` swallows the signal and exits 0.
- R8 counts a merge only on land's exact `merged #<n> (<sha>): tree verified` line; on `adopted` any `FAILED ` line land printed (a `_land_tidy` exit-2 arm) is appended to the row per the fold guidance.
- R6b also refuses a commit hook that leaves unstaged output: a non-empty `status --porcelain` after the commit names its first path the same `the commit differs from the guarded set` way.
- R3f's leftover judgment and R6b share `_adopt_commit_guard <repo> <tip> <base>` (R6 path list plus R6a on `merge-base..tip`); a leftover whose committed diff misses reads `read <wt>` and never prints `resume:`.
- `ADOPT_PR` is the first `#<n>` in the captured land log (`opened PR #7`, `adopted PR #7`, or a `MERGE FAILED #7`), so the `result:` column names the PR on every outcome that got far enough to have one.
- The override runs `cd "$wt" && proof-ledger.sh override kit-adopt` so the ledger keys the target repo, not the caller's cwd; a failed log stops before land with a `resume:` row.
- Test helper `adopt_apply` defaults every `GH_STUB_*` via `${VAR:-...}` so a case can override `GH_STUB_LAND_REMOTE` with a throwaway bare: the stub pushes `chore/kit-adopt:refs/heads/main` on every `pr merge` call, even a failed one, and a failed-merge case that must resume later needs the real origin's main untouched.

## T1c build

- The `ADOPT SUMMARY` table prints at the end of every run, dry runs included ("The run ends with"); case 16 now counts the `result:` lines, since the summary repeats each row.
- The trap row prints its own `  result:` line before the summary, the way every finished repo does; later repos get no `== <repo>` block, only their `not run` summary row.
- Case 34a's stub signals every forked `wrap.sh adopt` ancestor below the verb, not just `$PPID`: land runs `gh pr merge` inside `$(...)`, so the stub's parent is that comsub subshell, and a TERM there never reaches land's pipeline subshell (land exits 2, the batch runs on).

## Integration (lead)

- Cases 34a/34b INT failed under `run-all.sh` only: run-all starts each suite as a background job, so SIGINT arrives ignored and bash cannot un-ignore it. `adopt_kill` now launches the verb through `perl -e '$SIG{INT} = $SIG{TERM} = "DEFAULT"; exec @ARGV'`. A skip (the `test-proof-negctl.sh` pattern) would leave the INT path untested in the nightly run.
- The spec's Grounding samples now read `<workspace>/<repo>`: `test-no-personal-paths` refuses the operator's home and username in tracked files.
- The session handoff under `.claude/handoffs/` is untracked on this branch; master tracks no handoffs, and it carried an absolute path.
