# Spec: wrap land --draft opens a draft PR and stops
Generated: 2026-10-10
Status: DRAFT
Lane: full
Depth: standard (every fact is settled by reading `lib/wrap/wrap-land.sh` and one `gh --help`; the draft path reuses land's own push, body builder and adopt path)
References: `lib/wrap/wrap-land.sh:396-833` (`cmd_land`; imitate its refusal order, its open-PR lookup, its adopt checks and its in-process `--body` build); `lib/wrap/wrap-land.sh:168-200` (`_land_proof_body`; reuse as is); `lib/wrap/wrap-land.sh:207-219` (`_land_proof_block`; reuse as is).

## Problem

A full-lane change must open as a DRAFT PR for the operator's design review and must never merge. `bin/wrap land` pushes, opens a PR with a body built from the branch's proof-of-done file, and then merges. It has no way to stop after the open. So a session that builds a full-lane change opens the draft by hand: `git push`, then `gh pr create --draft --body-file docs/verification/<slug>.md`. `commands/wrap.md` step 10 hand-rolls the same two commands.

Hand-rolling failed in practice:
- One session ran the sequence three times, because each step is a separate command with its own failure.
- Once, the shell's `noclobber` option made a redirect fail, and the PR opened with an empty body. The reviewer saw a draft with no proof.
- The hand sequence skips every refusal `land` runs before its push: the dirty-tree check, the ignored-file guard, the PR-template check, the existing-PR checks.

## Terms

none

## Solution

### Approaches considered
1. A `--draft` flag on `wrap land`. It reuses the push, the body builder, the adopt path and every pre-push refusal, and stops before the merge. Tradeoff: `cmd_land` is already 440 lines, so the flag adds branches to a long function.
2. A new verb `wrap draft <worktree>` in a new file. Clean surface. Tradeoff: it copies or extracts the refusals and the adopt path, and two copies drift (the template check was added to `land` after the first version).
3. A thin shell wrapper that runs the hand sequence from one script. Tradeoff: it fixes the typing, not the missing refusals or the empty-body class.

### Chosen approach + why
Approach 1. The refusals, the body and the adopt checks already exist and are tested in `land`. The draft mode differs only in three places: how a PR is created (`--draft`), what happens to an existing PR (no `gh pr ready`), and where the run ends (after the open, before any merge or tidy). Approach 2 pays a refactor of `cmd_land` for no new behavior. Approach 3 leaves the original failure in place.

### Extensibility & boundaries
- The dimension that grows is the number of exits from `cmd_land`. The draft exit is one early `return` placed after the open-or-adopt block. Everything after that block (checks gate, merge, tree verify, ship record, tidy) stays untouched.
- The draft mode owns no new helper. It uses `_land_proof_body`, `_land_proof_block`, `_pr_template` and the existing lookup. A unit that needs a new helper means the reuse failed.

## Picture

```
 wrap land <wt> [--draft]
        |
        v
 +--------------------+   same for both modes (unchanged order)
 | arg parse          |-- --draft + (--with-ci|--verify|--no-pull) --> exit 64
 | dirty / branch /   |
 | gh / ahead checks  |-- refuse --> exit 1
 | open-PR lookup     |-- unreadable --> exit 2
 +--------------------+
        |
        v
 +--------------------+
 | already landed?    |-- land: tidy, remove worktree
 | (merge proof)      |-- draft: refuse exit 2, keep worktree        <== new
 +--------------------+
        |
        v
 +--------------------+
 | ignored-file guard |-- refuse --> exit 1, nothing pushed
 | template / body    |-- refuse --> exit 2, nothing pushed
 | draft only:        |
 |  open PR not draft |-- refuse --> exit 2, nothing pushed          <== new
 |  no proof, no body |-- refuse --> exit 2, nothing pushed          <== new
 |  ship-gate hook    |-- exit 2 --> refuse exit 2, nothing pushed    <== new
 +--------------------+
        |
        v
 git push origin <branch>
        |
        v
 +--------------------+
 | open or adopt PR   |   land:  create (ready) / adopt + pr ready
 |                    |   draft: create --draft / adopt, stay draft  <== new
 +--------------------+
        |
        +-- draft: print PR URL + proof block, exit 0. Worktree kept.  <== new
        |
        v   (land only)
 checks gate -> merge -> tree verify -> ship record -> tidy
```

## Design

### Approaches considered + chosen
See `## Solution`: approach 1, a flag on `land`.

### Diagram
The `## Picture` flow above is the control flow. The draft mode adds one flag, two pre-push refusals, one refusal on the already-landed branch, one `--draft` argument to `gh pr create`, and one early return.

### ADR link(s)
none. The choice is reversible: removing the flag removes the mode.

### Boundaries & failure modes
The mode touches git and GitHub state (a push, a PR). See `## Failure modes`. A draft PR is the only new GitHub state. It is closable and the push is the same push `land` does.

## Technical Design

### Interfaces (I/O contract)

CLI contract:

```
wrap.sh land <worktree> --draft [--title T] [--body-file F]
```

- Inputs: a committed, clean worktree on a non-default branch with commits ahead of `origin/<default>`. `--title` and `--body-file` mean what they mean for `land`.
- Accepted with `--draft`: `--title`, `--body-file`.
- Refused with `--draft`, exit 64 and `wrap.sh land: --draft cannot combine with --with-ci` (and likewise `--verify`, `--no-pull`): those three flags only steer the merge and the tidy, which `--draft` never runs. Silently ignoring them hides an operator mistake.
- Outputs (stdout, in order): `land <branch> -> <def> (<wt>)`, `     pushed <branch> (<sha>)`, then `     opened draft PR #<n>` or `     adopted draft PR #<n>`, then `     draft PR: <url>`, then `     worktree kept: <wt>`, then the existing `PROOF OF DONE` block when the branch has a proof file.
- Exit codes: 0 draft open or adopted. 1 a pre-state refusal `land` already uses (dirty tree, detached HEAD, default branch, no commits ahead, ignored-file guard). 2 a PR or push refusal. 64 usage.
- Ship gate: the last check before the push pipes `{"cwd":"<wt>","tool_input":{"command":"git push origin <branch>"}}` to `hooks/ship-gate.sh` (the kit's own copy, `$SELF_DIR/../../hooks/ship-gate.sh` from `lib/wrap/wrap.sh`; tests override the path with `WRAP_LAND_SHIP_GATE`). That is the payload the PreToolUse hook gets for a literal push, so the draft push meets the same lane, proof, implementation-notes and registry checks the hand `git push` met. Hook exit 2 refuses. A missing hook file refuses too, because the gate is the reason this mode exists.
- Invariants: with `--draft` the run never calls `gh pr merge`, never calls `gh pr ready`, never removes the worktree or the branch, never deletes the origin branch, never pulls the main checkout, and never writes a Ship record to the gate ledger. The PR it leaves is a draft.

Refusals, all before the push unless stated (each prints one `... REFUSED:` line and nothing is pushed):

| Refusal | Exit | Message |
|---|---|---|
| inherited from `land`: not a worktree, main checkout, dirty, detached, default branch, gh not ok, no commits ahead, ignored-file guard, flush failure | 64/1 | unchanged |
| open-PR lookup failed or unparseable | 2 | `PR REFUSED: open-PR lookup for <branch> failed` (unchanged) |
| template exists, new PR, no `--body-file` | 2 | `PR REFUSED: <tpl> exists, so a title-only PR body is not allowed; ...` (unchanged) |
| branch already on the default branch (merge proof hit) | 2 | `DRAFT REFUSED: <branch> is already landed (<proof>); nothing to review` |
| one open PR for the branch and it is not a draft | 2 | `DRAFT REFUSED: open PR #<n> is not a draft; gh pr ready --undo <n> converts it, then rerun` |
| new PR, no `--body-file`, and the branch has no proof file | 2 | `DRAFT REFUSED: no proof-of-done file and no --body-file; a draft with a title-only body is not allowed` |
| `hooks/ship-gate.sh` exits 2 for the synthesized push, or the hook file is missing | 2 | `DRAFT REFUSED: ship-gate blocked the push` followed by the hook's own stderr |
| more than one open PR | 2 | `PR REFUSED: <n> open PRs for <branch>` (unchanged; this one fires after the push, as in `land`) |
| open PR targets another base, another author, or the login does not resolve | 2 | unchanged (after the push, as in `land`) |
| `git push` fails | its rc | `PUSH REFUSED: ...` (unchanged) |
| `gh pr create` fails or names no number | 2 | unchanged |

The PR body: `--body-file` when given; else the proof body `_land_proof_body` builds (title, then each proof file); passed to `gh` as `--body "<string>"`, built in process, never through a shell redirect, so `noclobber` cannot blank it. An adopted draft whose body is empty or title-only takes the proof body through the existing `gh pr edit` path. An adopted draft with its own body keeps it.

### Data model changes
none
### API changes (endpoints, request/response shapes)
`gh pr create` gains `--draft` in draft mode. No other call changes.
### UI changes (screens, components, interactions)
none
### Infrastructure changes
none

## Task Breakdown

### Phase 1: Flag and refusals
- [ ] TASK-A: parse `--draft` in `cmd_land`; refuse it with `--with-ci`, `--verify`, `--no-pull`; add it to the usage line. Done when:
  - `land <wt> --draft --with-ci` exits 64 and names the flag (AC-1)
  - `--verify` and `--no-pull` refuse the same way (AC-2)
  - `land` without `--draft` behaves byte for byte as before (AC-3)
- [ ] TASK-B: the draft-only pre-push refusals: already-landed, open non-draft PR, no proof and no body. Done when:
  - the already-landed branch refuses, keeps the worktree and branch, pushes nothing (AC-4)
  - an open non-draft PR refuses before the push (AC-5)
  - a new PR with no proof file and no `--body-file` refuses before the push (AC-6)
  - a ship-gate exit 2 refuses before the push, and a missing hook file refuses the same way (AC-16)

### Phase 2: The draft path
- [ ] TASK-C: create with `--draft`, adopt a draft without `gh pr ready`, and return before the checks gate. Done when:
  - a new PR is created with `--draft` and the proof body (AC-7)
  - an adopted draft stays a draft, is not marked ready, and an empty body takes the proof body (AC-8)
  - the run calls no merge, leaves the worktree and branch, prints the PR URL and the proof block, exits 0 (AC-9)
  - the run writes no Ship record (AC-10)
  - every pre-push refusal of `land` still fires first and pushes nothing (AC-11)

### Phase 3: Tests and docs
- [ ] TASK-D: a `draft` section in `tests/test-wrap-land.sh` with one named case per AC and the negative controls. Done when:
  - `LAND_ONLY=draft bash tests/test-wrap-land.sh` is green (AC-12)
  - each negative control turns its named case red (AC-13)
- [ ] TASK-E: docs. Update the `wrap.sh` header usage and write-set comment, and `commands/wrap.md` step 10 to open the draft with `bin/wrap land --draft <wt> --title "<feature commit subject>" --body-file docs/verification/<slug>.md` in place of `git push` + `gh pr create --draft`. Done when:
  - the usage text names `--draft` (AC-14)
  - step 10 no longer carries the hand `gh pr create --draft` line, its `land --draft` line carries `--body-file`, and its "never merges a full-lane PR" and "`wrap land` and `wrap merge` never run on it" text says plain `land` and `merge` (AC-15)

## After state
- [ ] `bin/wrap land <wt> --draft` pushes, opens a draft PR with the proof body, prints the URL, and leaves the worktree. (Today: no `--draft`; a session runs `git push` then `gh pr create --draft` by hand.)
- [ ] The run never merges and never tidies, checkable by `grep -c 'pr merge' <gh stub log>` equal to 0 in the `draft` section.
- [ ] `commands/wrap.md` step 10 has no hand-rolled `gh pr create --draft` line, checkable by `grep -c 'gh pr create --draft' commands/wrap.md` equal to 0.
- [ ] A draft opened under `set -o noclobber` carries a non-empty body, checkable by the `noclobber` case.

## Quality requirements
none

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] The AC table below is green, and each negative control turns its case red
- [ ] No regressions in the `land` sections of `tests/test-wrap-land.sh`

### AC table

| AC | Criterion | Test case (section `draft`) | Negative control (mutation, expected red) |
|---|---|---|---|
| AC-1 | `--draft --with-ci` exits 64, names `--with-ci` | `draft_flag_with_ci_refused` | delete the `--with-ci` arm of the draft check: case red |
| AC-2 | `--draft --verify X` and `--draft --no-pull` exit 64 | `draft_flag_verify_nopull_refused` | delete the `--no-pull` arm: case red |
| AC-3 | `land` with no `--draft` still merges and tidies | the existing `happy` section | n/a, existing section stays green |
| AC-4 | already-landed branch with `--draft` exits 2, worktree and branch remain, origin untouched | `draft_already_landed_refused` | remove the draft check before `_land_tidy`: worktree is removed, case red |
| AC-5 | open non-draft PR exits 2, origin has no new branch | `draft_nondraft_open_refused` | move the check after the push: origin gains the branch, case red |
| AC-6 | no proof file, no `--body-file`, no PR: exits 2, nothing pushed | `draft_no_proof_refused` | delete the check: a title-only PR is created, case red |
| AC-7 | new PR: `gh pr create` argv holds `--draft` and a `--body` that holds `## Proof of done` | `draft_new_pr_is_draft_with_proof` | drop `--draft` from the create call: case red |
| AC-8 | adopted draft: no `pr ready` call; title-only body is replaced by the proof body | `draft_adopt_stays_draft` | leave the existing `gh pr ready` call reachable: case red |
| AC-9 | no `pr merge` call; worktree and branch exist; stdout holds the PR URL; exit 0 | `draft_stops_before_merge` | delete the early return: the run reaches the merge, case red |
| AC-10 | the gate ledger holds no `Ship` line for the rid after a draft run | `draft_no_ship_record` | delete the early return: the Ship record path runs, case red |
| AC-11 | dirty tree, ignored file, and template-without-body each refuse and push nothing | `draft_inherits_refusals` | move the draft return above the ignored-file guard: case red |
| AC-12 | the section runs green | `LAND_ONLY=draft` | n/a |
| AC-13 | every control above is red against its mutant | the control run in `## Verification` | n/a |
| AC-14 | the usage text names `--draft` | `draft_usage_names_flag` | remove `--draft` from the header: case red |
| AC-15 | `commands/wrap.md` carries no `gh pr create --draft`, and its `land --draft` line carries `--body-file` | `draft_wrap_md_uses_verb` | restore the hand line, or drop `--body-file` from the verb line: case red |
| AC-16 | a ship-gate stub exiting 2 refuses with exit 2 and origin has no branch; a missing hook path refuses the same way; a stub exiting 0 lets the draft open and received the worktree as `.cwd` and `git push origin <branch>` as the command | `draft_runs_ship_gate` | delete the gate call: origin gains the branch, case red |
| AC-17 | a repo with a PR template plus `--body-file` opens the draft (the step 10 shape) | `draft_template_repo_with_body_file` | n/a, pins the step 10 path through the unchanged template check |
| extra | a draft opened under `set -o noclobber` has a non-empty body | `draft_noclobber_body_nonempty` | rebuild the body through a redirect to a file created with `>`: case red under noclobber |

## Verification
The exact commands:

```
LAND_ONLY=draft bash tests/test-wrap-land.sh
bash tests/test-wrap-land.sh
bash tests/run-all.sh --changed origin/master
```

Each negative control runs on a mutated copy of `lib/wrap/wrap-land.sh` in a scratch worktree (the kit's `lib/gate/negctl.sh`), after the branch is frozen and committed, and the named case must go red.

## Edge Cases
1. Re-run after a draft is already open for the branch: the second run adopts it, pushes nothing new if the tip is unchanged, and prints the same URL. It never opens a second PR.
2. Re-run after new commits: the push updates the draft; the adopted draft keeps its own non-empty body and the proof body is not re-applied.
3. A fork's same-named branch is open: the existing `isCrossRepository` filter drops it before the draft check.
4. Branch with a proof file and `--body-file`: `--body-file` wins, as in `land`. An adopted PR prints the existing "keeps its own title and body" note.
5. A proof body over the size cap: `_land_proof_body` already cuts it with a pointer, so the create call never hits GitHub's 65536 limit.
6. `--draft` given with a worktree that the operator later passes to plain `land`: `land` finds the open draft, marks it ready and merges it. This is the existing, intended `land` behavior, and the reason step 10 removes the worktree after the draft opens.
7. Guarantee inversion: "the run never merges" holds only because the early return sits before the checks gate. The AC-9 case and its control pin the position.
8. The branch is the default or a protected name: refused as in `land` before anything runs.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Push succeeds, `gh pr create` fails | `PR REFUSED: gh pr create exited <rc>` | The branch is on origin and no PR exists. Re-run: the lookup finds no PR and creates it. |
| Create succeeds with a `--draft` the plan ignores | the PR shows ready in the web UI | `gh pr create --draft` is a plain flag in `gh` 2.102.0 (see `## Grounding`); a ready PR is caught by the post-create read below |
| Open-PR lookup returns stale data | a second PR for the branch | The pre-push count is read once; the post-push `open_count > 1` refusal is unchanged and stays |
| gh account differs from the PR author | `PR REFUSED: ... authored by` | unchanged `land` refusal |
| Operator expects a merge | none, the run ends at the open | the output ends on `worktree kept` and the URL; the operator marks the draft ready after review |

After create, the draft path reads the PR once with `gh pr view <n> --json isDraft` and refuses with exit 2 when it is not a draft (`DRAFT REFUSED: PR #<n> was created ready`). This is the only added read, and it covers the row above.

## Out of Scope
- Converting an open non-draft PR to a draft (`gh pr ready --undo`). See DEC-C.
- Marking the draft ready or merging it after review. The operator does that, or plain `land` does.
- Choosing which changes are full-lane. `lib/classify/lane-classify.sh` owns that.
- Removing the worktree after the draft opens. Step 10 keeps its own `git worktree remove` line.
- Running the ship gate inside plain `land`. Its internal push is ungated today (the `via=land` comment in `cmd_land` says so). This spec closes the gap for `--draft` only, because `--draft` replaces a push the hook used to see.

## Touches
- lib/wrap/**
- commands/wrap.md
- tests/test-wrap-land.sh
- tests/lib/wrap-stub.sh

## Decision Log
- DEC-A: `--draft` is a flag on `land`, not a new verb, because the refusals, the body builder and the adopt path already live there. Rejected: a new `wrap draft` verb (two copies of the refusals drift), a wrapper script (keeps the empty-body class).
- DEC-B: `--draft` refuses `--with-ci`, `--verify` and `--no-pull` with exit 64. They only steer the merge and tidy that the mode skips. Rejected: ignore them silently (hides a wrong command).
- DEC-C: an open non-draft PR is REFUSED, not converted. Conversion needs `gh pr ready --undo`, which `gh` documents as plan dependent, and it silently pulls a PR out of review that someone marked ready. The refusal fires before the push and names the one command to convert. Rejected: convert (plan dependent, surprising).
- DEC-D: an already-landed branch is refused under `--draft`. `land` would tidy the worktree, and the draft mode promises to keep it. Rejected: reuse the tidy (breaks the keep-worktree promise).
- DEC-E: a new draft with no proof file and no `--body-file` is refused. The title-only fallback of `land` is the empty-body failure this item exists to remove. Rejected: fall back to the title (the observed failure).
- DEC-F: the draft path writes no Ship ledger record. A draft has not shipped, and a Ship line would trip the step 8 retro trigger early.
- DEC-G: after create, one `gh pr view --json isDraft` read confirms the PR is a draft. Rejected: trust the flag (a silent ready PR could then be merged by a later plain `land`).
- DEC-H (validation round 1, critical): `--draft` pipes a synthesized push payload to `hooks/ship-gate.sh` before its push. The PreToolUse hook only sees a literal `git push` in a Bash command, so moving step 10's push inside `cmd_land` would drop the full-lane gate from the one push it exists for. Rejected: a copy of the gate's checks in `wrap-land.sh` (two copies drift), keeping a hand `git push` in step 10 (keeps the hand sequence this spec removes).
- DEC-I (validation round 1, critical): step 10 passes `--body-file docs/verification/<slug>.md`, as the hand `gh pr create` did. The template check stays unchanged, so a repo with a PR template opens the draft exactly as before. Rejected: let a proof body satisfy the template check in draft mode (changes `land` semantics for one mode).

## Grounding

External shapes the spec asserts, each sampled read-only on this machine:

- `gh pr create` takes `--draft` and `--body-file`. Sample: `gh pr create --help | grep -- --draft` printed `-d, --draft                Mark pull request as a draft`, and the `--body-file` line printed `-F, --body-file file       Read body text from file (use "-" to read from standard input)`. Version: `gh version 2.102.0 (2026-09-30)`.
- `gh pr ready --undo` exists and is plan dependent. Sample: `gh pr ready --help` printed `If supported by your plan, convert to draft with --undo`.
- `isDraft` is a readable PR field. Sample: `gh pr list --repo dwarvesf/dwarves-kit --state all --limit 2 --json number,isDraft,isCrossRepository` printed `[{"isCrossRepository":false,"isDraft":false,"number":971},{"isCrossRepository":false,"isDraft":false,"number":970}]`. `cmd_land` already requests `isDraft` in its lookup (`lib/wrap/wrap-land.sh:498`).
- The proof lookup. Sample: `bash lib/gate/proof-ledger.sh proof-files . HEAD~15` printed three `docs/verification/*.md` paths (for example `docs/verification/mega-gate-pr-head.md`). A branch with no such file prints nothing, which is the DEC-E trigger.
- The ship-gate payload. `hooks/ship-gate.sh:15-21` reads stdin with `INPUT=$(cat)`, takes `.cwd` as the real cwd, and takes `.tool_input.command` as the command, then engages on `git ... push` (line 46). Its header (line 10) says exit 2 blocks. A direct pipe of the same JSON reaches the same code path the PreToolUse hook takes.
- The test stub answers `pr create` with a fixed URL and exits 0, and records argv (`tests/lib/wrap-stub.sh:171-174`). It has no `isDraft` answer for `pr view` yet; TASK-D adds one stub switch for the post-create read. The real shape is sampled above.

Dry traces, one per negative control (read from `lib/wrap/wrap-land.sh` at the cited lines, nothing mutated here):

- NC for AC-7 (drop `--draft` from create): the mutation edits the `gh pr create` calls at lines 629 and 631. The `draft_new_pr_is_draft_with_proof` case reads the stub's recorded create argv, finds no `--draft`, and fails its `chk_has`. Red.
- NC for AC-9 and AC-10 (delete the early return): without it, control falls to `_land_pr_checks_gate` (line 657) and `_gh_merge_retry` (line 659). The stub logs a `pr merge` call, so `draft_stops_before_merge` finds a merge in the log and fails. The Ship record at line 817 then runs, so `draft_no_ship_record` finds a `Ship` line and fails. Red.
- NC for AC-5 (move the non-draft check after the push): the push at line 577 runs first, so the bare origin gains the branch. `draft_nondraft_open_refused` asserts the origin ref is absent and fails. Red.
- NC for AC-4 (remove the already-landed refusal): the proof branch at lines 519-561 reaches `_land_tidy` at line 559, which removes the worktree. The case asserts the worktree path exists and fails. Red.
- NC for AC-8 (leave `gh pr ready` reachable): the existing block at lines 605-609 calls `gh pr ready` for a draft. The stub logs it and `draft_adopt_stays_draft` asserts no `pr ready` call. Red.
- NC for AC-11 (draft return above the ignored-file guard): the guard at line 565 never runs, so the ignored fixture file does not refuse and the push happens. `draft_inherits_refusals` asserts exit 1 and an absent origin branch. Red.
- NC for AC-16 (delete the gate call): no check stands between the template check (line 569) and the push (line 577), so the stub gate's exit 2 is never read and the bare origin gains the branch. `draft_runs_ship_gate` asserts the origin ref is absent and fails. Red.
- NC for the `noclobber` case: rebuilding the body through `> "$file"` under `set -C` fails when the file exists, so the body arg is empty. The case asserts the body holds `## Proof of done`. Red.

## Open questions
(none)
