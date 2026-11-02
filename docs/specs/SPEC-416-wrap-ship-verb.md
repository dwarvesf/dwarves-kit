# Spec: wrap ship composes start, commit, proof override and land
Generated: 2026-11-02
Status: DRAFT
Lane: normal
Depth: standard (every fact is settled by reading `lib/wrap/wrap-start.sh`, `lib/wrap/wrap-land.sh` and `lib/wrap/wrap-adopt.sh`; the new verb composes verbs that already exist and tests)
References: `lib/wrap/wrap-adopt.sh:_adopt_one` (imitate its order: start, stage, commit, recheck the committed diff, log the override, land; and its rule that the verb never removes what a failure leaves); `lib/wrap/wrap-land.sh:cmd_land` (the `_LAND_KIND`/`_LAND_REF`/`_LAND_PULL`/`_LAND_WT` globals it sets, which a same-shell caller reads instead of parsing output); `lib/wrap/wrap-start.sh:cmd_start` (its stdout contract: the worktree path is the only stdout line).

## Problem

An operator who ships a small docs or content change from a shared, dirty main checkout runs the same five steps by hand:

1. `wrap start <repo> <branch> --carry <paths>`
2. `git add` and `git commit` inside the new worktree
3. `bash lib/gate/proof-ledger.sh override <slug> "<reason>"`
4. write a PR body to a `mktemp` file
5. `wrap land <wt> --title ... --body-file ...`

Measured evidence (operator report, one session): the same five steps ran 8 times by hand. That is 40 hand-typed steps with 8 chances each to slip on a path list, a slug, a branch prefix or a temp file.

What goes wrong in the hand sequence:
- The override slug is the branch name minus its first `type/` segment (`hooks/ship-gate.sh:241`, `lib/gate/gate-ledger.sh:1152`), while the worktree directory uses the part after the LAST `/` (`lib/wrap/wrap-start.sh:85`). Typing the wrong one logs an override the gate never reads.
- `git add -A` in a worktree that was started with `--carry` is tempting and harmless there, but the same habit in the shared main checkout sweeps in other sessions' files.
- A commit made in the wrong directory lands on the default branch of the shared checkout.
- A shell with `noclobber` turns the body-file step into an empty PR body (the failure SPEC-404 recorded).

No single verb owns the sequence. `adopt` composes start, commit, override and land for ONE fixed file set; nothing does it for an operator-named path set.

## Terms

none

## Solution

### Approaches considered
1. A new verb `wrap ship` in its own file that calls `cmd_start`, git, `proof-ledger.sh override` and `cmd_land` in order. Tradeoff: one more verb on the surface; it must not copy any refusal.
2. Flags on `land` (`land --commit-message-file`, `land --carry`). Tradeoff: `land` takes a finished branch in an existing worktree; it would grow a start half and a commit half, and `cmd_land` is already over 440 lines.
3. A shell script or skill that types the five steps. Tradeoff: fixes the typing, not the slug rule, the default-branch commit risk or the empty-body class, and a script file defeats the branch guard hook.

### Chosen approach + why
Approach 1, shaped like `adopt` (which already proves the composition works in one process). Every refusal a step makes stays inside that step's own verb; `ship` adds only what no existing verb can own: the argument contract, the stage-by-named-path rule, the committed-diff guard, and the explicit-only override.

### Extensibility & boundaries
- The dimension that grows is the set of flags a caller wants passed through to `land` (`--draft`, `--with-ci`, `--verify`). This spec passes through only `--title`, `--body-file` and `--no-pull`. A caller who needs more runs `start` and `land` directly; adding a flag later is one more pass-through arm.
- Units: `wrap-ship.sh` holds `cmd_ship` (argument parse and the step loop) and one helper `_ship_in_scope` (path-in-carry-set test). A unit that needs a third helper means a refusal was copied instead of inherited.

## Picture

```
 wrap ship <repo> <branch> --carry P... --message-file M [--title T] [--body-file B]
                                        [--proof-override R] [--no-pull]
        |
        v
  [preflight, no write]  args, gh usable, PR template needs B, P dirty in <repo>
        |
        v
  cmd_start <repo> <branch> --carry P...   ---- refuses as start does ----> exit as start
        |  prints <wt>
        v
  HEAD of <wt> == <branch>, not default  ---- else refuse, no commit ----> exit 1
        |
        v
  git -C <wt> add -- P...  ;  something staged?  ---- no ----> exit 1
        |
        v
  git -C <wt> commit -F M   ---- hook rejects ----> exit 1, worktree kept
        |
        v
  committed files all inside P?  ---- no ----> exit 1, nothing pushed
        |
        v
  R given? ---yes---> (cd <wt>; proof-ledger.sh override <slug> R)   ---- fails ----> exit as ledger
        |no (logs NOTHING)
        v
  cmd_land <wt> [--title T] [--body-file B] [--no-pull]   ---- refuses as land does ----> exit as land
        |
        v
  LAND: ...   then   SHIP: shipped ...
```

## Design
<!-- Design-bearing: a new verb with an irreversible tail (merge). Control flow is the Picture above; the contract is below. -->

### Approaches considered + chosen
See `## Solution`: approach 1, a new verb composing existing verbs.

### Diagram
The `## Picture` flow is the control flow. The only new decisions in it are the two diamonds `HEAD of <wt> == <branch>` and `committed files all inside P`, and the branch on `R given?`.

### ADR link(s)
none. The verb is additive; deleting `wrap-ship.sh` and its dispatch arm removes it and changes no other verb.

### Boundaries & failure modes
The verb writes git and GitHub state through verbs that already own those writes (a worktree, a stash, a commit, a ledger line, a push, a PR, a merge). The one write `ship` owns is the commit. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

Command:

```
wrap ship <repo> <branch> --carry <path>... --message-file <file>
          [--title <t>] [--body-file <file>] [--proof-override "<reason>"] [--no-pull]
```

Arguments:
- `<repo>`, `<branch>`: as `start`. The branch is NEW; `start` refuses an existing one.
- `--carry <path>...`: REQUIRED, one or more repo-relative paths, read up to the next `--` flag. A bare `--carry` is refused (exit 64): staging "everything" is the shared-checkout hazard this verb removes. A path that is absolute, has a `..` component, starts with `:` or `-`, or holds a glob character (`*`, `?`, `[`) is refused (exit 64).
- `--message-file <file>`: REQUIRED, an existing non-empty file, passed as `git commit -F`. The caller writes it; `ship` never composes a message, so the commit-format hook judges the caller's text.
- `--title <t>`, `--body-file <file>`: passed to `land` unchanged. `land`'s own title fallback and PR-template rule apply.
- `--proof-override "<reason>"`: the ONLY way an override is logged. Non-empty, no newline. Absent means `ship` logs nothing and the ship-gate decides at `land`'s push.
- `--no-pull`: passed to `land` (a stopped main checkout, per `commands/wrap.md` step 0).
- Not accepted (exit 64, "use start and land directly"): `--draft`, `--with-ci`, `--verify`, `--pick`.

Outputs (stdout unless noted; each step prints one line):
- `ship: worktree <path>` after `start`.
- `ship: committed <sha7> (<n> files)` after the commit.
- `ship: override logged (slug <slug>)` only when `--proof-override` was given and the ledger exited 0.
- `land`'s own lines, unchanged, ending with its `LAND:` line.
- Last line, always exactly one, so a caller reads the outcome with `| tail -1`:
  - `SHIP: shipped #<n> (<sha7>) pull=<ok|blocked|skipped> worktree=<removed|kept>`
  - `SHIP: already landed (<proof>) pull=... worktree=...` (the content was already on the default branch)
  - `SHIP: refused (<step>, exit <rc>) worktree=<path|none>` where `<step>` is `preflight`, `start`, `carry`, `branch`, `stage`, `commit`, `guard`, `override` or `land:<_LAND_STEP>`.
- On stderr, after any refusal that leaves a worktree: `resume: wrap land <wt>` with the same `--title`, `--body-file` and `--no-pull` the caller gave. The `--proof-override` reason is never echoed.

Exit codes:
- 0: shipped (merged, or already landed).
- 64: usage or argument refusal, before any write.
- A step's own non-zero code, unchanged: `start` 1 or 2, `proof-ledger.sh override` 64, 66 or 1, `land` 1, 2, 3 or 130.
- 1: a refusal `ship` owns (preflight, `branch`, `stage`, `commit`, `guard`).

Invariants:
- Nothing is written before `start` runs; every `preflight` refusal leaves the repo as it was.
- No commit is made unless `git -C <wt> branch --show-current` equals `<branch>` and `<branch>` is not the default branch, `main` or `master`.
- Staging is `git add -- <carry paths>`, never `-A`, never `.`.
- `proof-ledger.sh override` runs only when `--proof-override` was given, only inside `<wt>`, and only after the commit and the guard passed.
- `ship` removes nothing. A worktree a failure leaves is named on the `SHIP:` line.

### Data model changes
none. One ledger line (the override) when the flag is given, written by the existing verb.
### API changes (endpoints, request/response shapes)
none
### UI changes (screens, components, interactions)
none
### Infrastructure changes
none

## Task Breakdown

### Phase 1: The verb
- [ ] TASK-A: add `lib/wrap/wrap-ship.sh` (`cmd_ship`), the `ship` dispatch arm, the `source` entry and the usage lines in `lib/wrap/wrap.sh`. Done when:
  - AC-1 to AC-14 hold against it
  - `bin/wrap --help` names `ship` and every flag in the contract

### Phase 2: Tests
- [ ] TASK-B: add `tests/test-wrap-ship.sh` on the `tests/lib/wrap-stub.sh` harness, one section per AC, with the negative controls run on a mutated copy. Done when:
  - the suite is green and each named control turns its case red (AC-15)

### Phase 3: Docs
- [ ] TASK-C: document the verb in `commands/wrap.md` (the hand-made-worktree paragraph and step 10's land line), `docs/reference/wrap.md` (the situation table), `lib/wrap/README.md` and `docs/MANUAL.md`. Done when:
  - AC-16 holds

## After state
- [ ] `bin/wrap ship <repo> <branch> --carry <paths> --message-file <f> --proof-override "<reason>"` carries the named paths, commits them, logs one override and lands, in one call. (Today: five hand-typed steps.)
- [ ] Without `--proof-override` no override line is written, checkable by the ledger line count before and after a ship run.
- [ ] No commit lands on the default branch of the shared checkout, checkable by `git -C <repo> rev-parse <default>` equal before and after.
- [ ] Every refusal `start` and `land` make still fires through `ship`, each checkable by its own case in `tests/test-wrap-ship.sh`.
- [ ] `bin/wrap --help` lists `ship`, checkable by `bin/wrap --help | grep -c 'wrap.sh ship'` equal to 1.

## Quality requirements
none

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] The AC table below is green, and each negative control turns its case red
- [ ] No regressions in `tests/test-wrap-start.sh`, `tests/test-wrap-land.sh` or `tests/test-wrap-adopt.sh`

### AC table

| AC | Criterion | Test case (suite `tests/test-wrap-ship.sh`) | Negative control (mutation, expected red) |
|---|---|---|---|
| AC-1 | happy path: carried file is committed on the new branch, PR opened and merged, exit 0, last line `SHIP: shipped #` | `ship_happy` | skip the `cmd_land` call: no `SHIP: shipped`, case red |
| AC-2 | a dirty file NOT in `--carry` stays dirty in the main checkout and is absent from the commit | `ship_uncarried_dirt_stays` | drop the carry paths from the `cmd_start` call (carry everything): the file leaves the main checkout and enters the commit, case red |
| AC-3 | no `--proof-override`: the override log has the same line count after the run, including a run that fails at `land` | `ship_no_flag_logs_nothing` | call `proof-ledger.sh override` unconditionally: count grows, case red |
| AC-4 | with the flag: exactly one new line, keyed to slug `${branch#*/}`, and it exists BEFORE the push (a pre-push hook in the fixture reads the log) | `ship_override_before_push` | move the override after `cmd_land`: the hook sees no line, case red |
| AC-5 | `--carry` bare, or with no `--carry`: exit 64 and nothing written (no worktree, no branch) | `ship_carry_required` | default an empty carry list to everything: a worktree appears, case red |
| AC-6 | bad carry paths (absolute, `..`, glob, leading `-`) exit 64, nothing written | `ship_carry_path_refused` | delete the `..` arm: that path reaches `start`, case red |
| AC-7 | `--message-file` missing, not a file, or empty: exit 64, nothing written. `--draft`, `--with-ci`, `--verify`, `--pick` exit 64 | `ship_args_refused` | drop the emptiness test: an empty message commits, case red |
| AC-8 | nothing dirty under the carry paths in the main checkout: exit 1, `SHIP: refused (preflight`, no worktree created | `ship_nothing_to_ship` | remove the dirty probe: `start` creates an empty worktree, case red |
| AC-9 | repo with a PR template and no `--body-file`: refused at preflight, exit 1, no worktree | `ship_template_needs_body` | remove the template probe: the run reaches `land` after the commit, case red |
| AC-10 | inherited `start` refusals: default branch name, existing branch, existing worktree path each exit as `start` does, with the verb's own message, and no commit is made | `ship_inherits_start_refusals` | catch `start`'s non-zero and continue: a commit is attempted, case red |
| AC-11 | carry conflict (`start` exit 2): `ship` exits 2, `SHIP: refused (carry`, no commit, worktree named | `ship_carry_conflict_stops` | ignore `start`'s code when it printed a path: the commit runs, case red |
| AC-12 | the commit never lands on the default branch: with a stubbed `start` that returns the main checkout path, `ship` refuses at `branch`, and the default ref is unchanged | `ship_never_commits_on_default` (sources the wrap modules in a subshell and redefines `cmd_start`; no env seam is added to production code) | delete the HEAD check: the commit lands on the default branch, case red |
| AC-13 | a pre-commit hook that adds an uncarried file makes the committed diff leave the carry set: exit 1, `SHIP: refused (guard`, nothing pushed, no override logged | `ship_guard_committed_diff` | delete the guard: the push runs, case red |
| AC-14 | inherited `land` refusals pass through with their own exit: a pre-push hook exiting 1 gives `SHIP: refused (land:push, exit 1)`, a `resume: wrap land <wt>` line, worktree kept, and no `--proof-override` reason in any output | `ship_inherits_land_refusals` | print the reason in the resume line: the leak check fails, case red |
| AC-15 | every control above is red against its mutant | the control run in `## Verification` | n/a |
| AC-16 | `commands/wrap.md`, `docs/reference/wrap.md`, `lib/wrap/README.md` and `docs/MANUAL.md` each name `wrap ship`; `bin/wrap --help` lists it | `ship_docs_name_verb` | remove the usage line: case red |

## Verification
The exact commands:

```
bash tests/test-wrap-ship.sh
bash tests/test-wrap-start.sh && bash tests/test-wrap-land.sh && bash tests/test-wrap-adopt.sh
bash tests/run-all.sh --changed origin/master
```

Each negative control runs on a mutated copy of `lib/wrap/wrap-ship.sh` in a scratch worktree (the kit's `lib/gate/negctl.sh`), after the branch is frozen and committed (commit before the control, not after), and the named case must go red.

## Edge Cases
1. A carry path names a directory. `git add -- <dir>` stages everything under it; the guard accepts a committed file equal to a carry path or under one (`_ship_in_scope`).
2. A carried path is a deletion of a tracked file. `git add -- <path>` stages the deletion; the commit holds it. No special case.
3. A carry path is gitignored or does not exist. The dirty probe sees nothing, so preflight refuses with `nothing to ship`, before any write.
4. Two carry paths, one dirty and one clean. The clean one is silently a no-op for `start`'s stash; the commit holds only the dirty one. Not a refusal.
5. The branch has a multi-segment name (`docs/ops/x`). The worktree directory is `x` (after the last `/`); the override slug is `ops/x` normalized by `slugify` to `ops-x`, matching the gate. Both come from the existing rules; `ship` uses `${branch#*/}` and hands the result to the ledger.
6. `--proof-override` on a change that touches application source. The ledger itself rejects the override at the gate (`lib/gate/proof-ledger.sh` "override ... REJECTED"); `ship` adds no second check, so one authority decides.
7. `--message-file` points inside the carry set (the operator left it dirty in the repo). It is committed if carried; `ship` does not special-case it.
8. Ctrl-C during `land`: `land` returns 130; `ship` passes 130 and prints the `SHIP: refused` line with the worktree kept.
9. Guarantee inversion: "ship never commits on default". If `start` is ever changed to return a path whose HEAD is the default, the `branch` check still refuses. "Override is explicit only": a future edit that logs an override by default turns AC-3 red.
10. A second `ship` with the same branch after a failed one: `start` refuses (branch exists). The `resume:` line names `wrap land <wt>`, which is the correct continuation.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `start` succeeds, commit hook rejects | `SHIP: refused (commit, exit 1)` plus the hook's stderr | worktree kept and named; fix the message file, `git -C <wt> commit -F <f>`, then `wrap land <wt>` |
| A hook widens the commit past the carry set | `SHIP: refused (guard, exit 1)` listing the first out-of-set path | nothing pushed, no override logged; the operator inspects `<wt>` |
| Override logged, then `land` refuses | `SHIP: refused (land:...)`; one ledger line exists | the override is scoped to repo and slug and is reused by the rerun of `wrap land <wt>`; it is not logged twice |
| `land` merges, tree mismatch (exit 3) | `land`'s own `TREE MISMATCH` line | passed through unchanged; `ship` prints `SHIP: refused (land:verify, exit 3)` |
| The shared checkout is dirty in the carried paths after a failed carry | `start` exit 2 and its `stash ... kept` line | passed through; `ship` stops before the commit |
| gh unavailable | `SHIP: refused (preflight, exit 1)` | nothing written; fix `gh auth`, rerun |

## Out of Scope
- `--draft`, `--with-ci`, `--verify`, `--pick`: run `start` and `land` directly.
- Composing the commit message or the PR body. The caller writes both files; this is what keeps the commit-format and PR-template rules the caller's.
- A `--resume` mode. The `resume:` line names `wrap land <wt>`, which already continues the sequence from a committed worktree.
- A dry run. `adopt` has one because its file set is generated; here the caller names the paths, and every refusal that can fire before a write already does (`preflight`).
- Staging by `-A` or by `.`, ever, including as an opt-in flag.
- Source-code changes. The ledger's docs-only override rule still governs; `ship` is for docs and content.

## Touches
- lib/wrap/**
- commands/wrap.md
- docs/reference/wrap.md
- docs/MANUAL.md
- tests/test-wrap-ship.sh
- tests/lib/wrap-stub.sh

## Decision Log
- DEC-A: a new verb in its own file, shaped like `adopt`, not flags on `land`. `land` finishes ONE committed branch; start and commit are other concerns, and the draft work (SPEC-404) already showed `cmd_land` is long enough. Rejected: `land --carry`/`--commit` flags, a script or skill (does not fix the slug rule or the default-branch risk).
- DEC-B: compose by calling `cmd_start` and `cmd_land` in-process, as `adopt` does, not by re-running `bin/wrap`. A same-shell call lets `ship` read `_LAND_KIND`/`_LAND_REF`/`_LAND_PULL`/`_LAND_WT` for the final line and keeps one source of every refusal. Rejected: parsing `land`'s output (two copies of its grammar).
- DEC-C: the override is logged only when `--proof-override` carries a reason. No flag means no ledger write; the ship-gate decides at the push. Rejected: log a default reason when the gate would refuse (an automatic bypass is exactly what the audited override exists to prevent); detect "proof present" inside `ship` (a second copy of the gate's proof lookup, which drifts).
- DEC-D: `--carry` needs explicit paths, and staging is `git add -- <paths>`. The motivating case is a SHARED dirty checkout where other sessions' files sit beside the operator's. Rejected: allow bare `--carry` (stages the other sessions' files into the commit).
- DEC-E: the committed diff is re-read after the commit and must stay inside the carry set (the `adopt` R6b idea). A commit hook can add files after `git add`. Rejected: trust the pre-commit staged list.
- DEC-F: the HEAD check before the commit is independent of `start`'s own default-branch refusal. The invariant "never commit on the default branch" should hold even if `start` changes. Rejected: rely on `start` alone.
- DEC-G: only `--title`, `--body-file` and `--no-pull` pass through to `land`. `--no-pull` is the shape a stopped shared checkout needs (`commands/wrap.md` step 0). The other `land` flags change what a merge means and stay on `land`. Rejected: pass everything through (the surface becomes `land`'s surface plus `start`'s).
- DEC-H: preflight refuses before any write on the cheap reads `land` would otherwise refuse on AFTER a commit exists: gh unusable, PR template with no `--body-file`, nothing dirty under the carry paths. These are reads, not copies of `land`'s checks; `land` still runs its own. Rejected: let `land` find them (leaves a worktree and a commit for a refusal knowable up front).
- DEC-I: the override slug is `${branch#*/}`, the same rule the ship-gate and `gate-ledger.sh rid` use, and the ledger's own `slugify` normalizes it. Rejected: reuse the worktree directory name (the part after the LAST `/`, a different rule).
- DEC-J: `ship` writes one final `SHIP:` line after `land`'s `LAND:` line, so `| tail -1` reads the outcome. Exit codes are the failing step's own, so a caller that already handles `start` and `land` codes handles `ship`.

## Grounding

External shapes the spec asserts, each sampled read-only (a scratch repo with a bare origin under the session scratch directory, `bin/wrap` from this worktree). Nothing in a real repo or the real override log was touched; the override sample used `KIT_LEDGER_DIR` pointed at the scratch directory.

- `wrap start --carry` output. Sample, `bin/wrap start <repo> docs/x --carry note.md` with `note.md` dirty in the main checkout:
  ```
  /private/tmp/.../repo/.claude/worktrees/x
  carried: note.md 
  ```
  (exit 0; the first line is stdout, the `carried:` line is stderr). Afterwards the main checkout's `git status --short` showed only the uncarried `?? a.txt`, and the worktree's showed `?? note.md`. So the carry moves exactly the named path and leaves other dirt.
- `start` with nothing dirty in scope. Sample, `--carry nothing.md`: stdout was the new worktree path, stderr `nothing to carry`, exit 0. This is why preflight must probe the dirt itself: `start` creates the worktree anyway.
- `start` refusals. Samples: `wrap.sh start: branch docs/x already exists in <repo>` (exit 1); `wrap.sh start: no default branch resolved for <repo>` (exit 1, repo without `origin/HEAD`); `wrap.sh start: --pick needs a branch name` (exit 64).
- The dirty probe. Sample, `git -C <repo> status --porcelain --untracked-files=all -- a.txt nothing.md` printed `?? a.txt`; with only `nothing.md` it printed nothing (0 lines). An empty result means "refuse at preflight".
- Stage and commit. Sample in the carried worktree: `git add -- note.md` then `git diff --cached --name-only --no-renames` printed `note.md`; `git commit -q -F <msgfile>` produced `1867d5b docs: add note`; `git diff --name-only --no-renames HEAD^ HEAD` printed `note.md`. This is the list the guard compares to the carry set.
- `land` refusals. Samples: `wrap.sh land: <wt> is dirty, so the branch is not what a PR would carry` then `LAND: refused (preflight, exit 1)`; `wrap.sh land: docs/y has no commits ahead of origin/main` (exit 1); `wrap.sh land: --body-file '/nope' is not an existing file` (exit 64); `wrap.sh land: <repo> is the main checkout, not a worktree` (exit 1); and, on a committed worktree whose origin is not GitHub, `PR REFUSED: open-PR lookup for docs/x failed` then `LAND: refused (pr-lookup, exit 2)`. Every `land` run ends on one `LAND:` line; the forms are listed in the `cmd_land` header (`lib/wrap/wrap-land.sh:363-365`).
- `proof-ledger.sh override`. Sample, run inside the worktree with `KIT_LEDGER_DIR` pinned: `proof-of-done override logged for slug 'x' in repo '<repo>' (trace: <dir>/proof-overrides.log)` (exit 0). With no reason: `usage: override <slug> <reason>` (exit 64). The slug rule `${b#*/}` on `docs/x` printed `x`.
- `wrap --help` usage lines for `start` and `land` (the lines `ship` sits between), from `lib/wrap/wrap.sh:10-12`: `wrap.sh land <worktree> [--title T] [--body-file F] [--with-ci] [--no-pull] [--verify C]` and `wrap.sh start <repo> <branch> [--pick <branch>]... [--carry [<path>...]]`.
- A claim that cannot be sampled here: that the ship-gate (not a git hook) refuses a non-draft `land` push for a missing proof. `cmd_land`'s own header says "a ship-gate refusal on the push surfaces with the gate's own stderr and exit code" (`lib/wrap/wrap-land.sh:355-356`), but the scratch origin is not GitHub, so the push never ran. The test plan therefore stands in a fixture `pre-push` hook for the gate (AC-4, AC-14) and does not assert the real gate's text.

Dry traces, one per negative control (read from `lib/wrap/wrap-start.sh`, `lib/wrap/wrap-land.sh` and `lib/wrap/wrap-adopt.sh`; nothing mutated here):

- NC for AC-1 (skip `cmd_land`): the run ends after the commit, so no `LAND:` line and no `SHIP: shipped` line print; `ship_happy` asserts both and the PR number, and fails. Red.
- NC for AC-2 (drop the paths from the `cmd_start` call): `start` then takes the stash-everything branch (`lib/wrap/wrap-start.sh:141-145`), so the uncarried file leaves the main checkout and is applied in the worktree; `git add -- <paths>` still stages only the named path, but the file is no longer dirty in the main checkout. `ship_uncarried_dirt_stays` asserts it is still dirty there (`git status --short` shows it) and fails. Red.
- NC for AC-3 (unconditional override): `proof-ledger.sh override` appends through `ledger_append` (`lib/gate/proof-ledger.sh:305`), so the line count rises by one on every run. `ship_no_flag_logs_nothing` compares counts and fails. Red.
- NC for AC-4 (override after `land`): `land`'s push runs the fixture `pre-push` hook first; the hook reads the log, finds no line for the slug, and exits 1. The case asserts the hook saw the line and fails. Red.
- NC for AC-5 (default empty carry to everything): `start` receives `--carry` with no path, takes the stash-everything branch (`lib/wrap/wrap-start.sh:141-145`), and creates a worktree. The case asserts no worktree directory exists after exit 64. Red.
- NC for AC-6 (delete the `..` arm): `../x` reaches `start`, whose stash call discards git's pathspec error (`>/dev/null 2>&1`, `lib/wrap/wrap-start.sh:136`), so `start` prints `nothing to carry` and exits 0 with a worktree created. The case asserts exit 64 and no worktree. Red.
- NC for AC-7 (drop the emptiness test): `git commit -F` on an empty file aborts with "Aborting commit due to empty commit message", so the case would see exit 1 at `commit`, not 64, and a worktree. It asserts exit 64 and no worktree. Red.
- NC for AC-8 (remove the dirty probe): `start` runs and prints `nothing to carry` (sampled above); the stage step then stages nothing and exits 1 with a worktree left. The case asserts the step is `preflight` and no worktree exists. Red.
- NC for AC-9 (remove the template probe): the run reaches `land`, which refuses at `lib/wrap/wrap-land.sh:568-574` (`PR REFUSED: ... title-only PR body is not allowed`) AFTER the commit, leaving a worktree. The case asserts no worktree. Red.
- NC for AC-10 (continue past `start`'s failure): after `branch docs/x already exists` (exit 1, empty stdout) the mutant carries on with an empty worktree path, so `git -C "" branch --show-current` reads the main checkout and the run stops at the `branch` step instead. The case asserts the final line names step `start` and the exit equals `start`'s, so it sees `branch` and fails. Red.
- NC for AC-11 (ignore `start`'s code 2 when a path was printed): `_start_carry` returns 2 on an apply conflict (`lib/wrap/wrap-start.sh:166-168`) with the stash kept; the mutant proceeds to `git add` in a worktree holding conflict markers. The case asserts no commit exists past `origin/<default>`. Red.
- NC for AC-12 (delete the HEAD check): a `start` stub returning the main checkout path makes `git -C <main> add` and `commit` run on the default branch; the case asserts `rev-parse <default>` is unchanged. Red.
- NC for AC-13 (delete the guard): the pre-commit hook's extra file is committed and `land`'s push runs; the case asserts nothing reached the bare origin. Red.
- NC for AC-14 (echo the reason in `resume:`): the case greps stdout and stderr for a unique token placed in the reason; the mutant prints it. Red.
- NC for AC-16 (remove the usage line): `bin/wrap --help | grep -c 'wrap.sh ship'` prints 0 and `ship_docs_name_verb` fails. Red.

## Open questions
(none)
