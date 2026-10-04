# Spec: wrap adopt, one call that adopts a repo and lands the adoption
Generated: 2026-10-04
Status: DRAFT
Lane: full (kit machinery: `lib/wrap/`, the `wrap` command contract; the verb pushes and squash-merges onto other repos' default branches)
Depth: standard (every fact this spec rests on was sampled live; see ## Grounding)
Type: spec-feature
File: `docs/specs/SPEC-387-adopt-land.md`
References: the operator's hand loop `adopt-one.sh` (session scratch, quoted in ## Problem: the exact sequence this verb replaces); `lib/wrap/wrap-start.sh` (`cmd_start`, its refusals, the worktree path on stdout); `lib/wrap/wrap-land.sh` (`cmd_land`, `_land_tidy`, the `PULL BLOCKED` lines, `_pr_template`); `lib/wrap/wrap-scan.sh` (`_add_under`, the multi-repo arg shape); `lib/adopt.sh` (`--check`, `--dry-run`, the files it writes); `lib/gate/proof-ledger.sh` (`override`, `check`'s override path and its source-remainder rule); `hooks/ship-gate.sh` (line 151: `SLUG="${BRANCH#*/}"`, the slug an override must match)

## Problem

The operator adopted six repos by hand, running one loop per repo:

```
wt="$(wrap start "$R" chore/kit-adopt | tail -1)"
bash "$K/lib/adopt.sh" "$wt"
git -C "$wt" add -A && git -C "$wt" commit -m "chore: adopt the dwarves-kit operate-contract"
(cd "$wt" && bash "$K/lib/gate/proof-ledger.sh" override chore-kit-adopt "adoption scaffold only: ...")
(cd "$R" && wrap land "$wt")
bash "$K/lib/adopt.sh" --check "$R"
```

Two repos failed AFTER the PR merged, because the closing fast-forward pull in the main checkout could not run:

- One main checkout held an untracked `AGENTS.md`. The landed adoption adds a tracked `AGENTS.md`, so `pull --ff-only` refused.
- One main checkout had a merge in progress, so the pull refused.

Each failure leaves a repo adopted on origin and not adopted locally, found only by reading land's output. Grounding found a third defect in the loop itself: the override was logged under slug `chore-kit-adopt`, and the ship-gate looks up `kit-adopt` (the branch with its `type/` prefix stripped), so that override never matched anything.

## Rules

| # | Rule | Lands in |
|---|---|---|
| R1 | `wrap adopt [--apply] [--title T] [--body-file F] <repo> [<repo>...]`. Without `--apply` it is a dry run: it runs every preflight read (R3) and `adopt.sh --dry-run <repo>`, prints `would adopt` or the refusal, and writes nothing (no fetch, no worktree, no branch, no ledger line). | T1 |
| R2 | The branch is always `chore/kit-adopt`. The override slug is `kit-adopt`, derived as `${branch#*/}`, the same rule as `hooks/ship-gate.sh` line 151 and `gate-ledger.sh rid`. | T1 |
| R3 | Preflight, per repo, reads only, before any write. The first check short-circuits; the rest are all collected and the row names every reason found, joined by `; `. | T1 |
| R3a | `adopt.sh --check <repo>` exits 0: row `skip: already adopted`, no other check runs. | T1 |
| R3b | `<repo>` is not a main checkout (its git dir differs from its common dir, or it is not a repo): `refused: not a main checkout`. | T1 |
| R3c | A collision path (Interfaces: `ADOPT_PATHS`) shows any `git status --porcelain` line in the main checkout (untracked, modified, staged, or unmerged): `refused: <XY> <path> in the main checkout would block the post-land pull`, one per path. | T1 |
| R3d | A sequencer operation is in progress (`MERGE_HEAD`, `rebase-merge`, `rebase-apply`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, each read with `git rev-parse --git-path`): `refused: mid-merge` / `mid-rebase` / `mid-cherry-pick` / `mid-revert`. | T1 |
| R3e | `git ls-files -u` lists any path, whatever R3d found: `refused: unmerged paths: <paths>`. | T1 |
| R3f | `refs/heads/chore/kit-adopt` exists, or `ls-remote --exit-code --heads origin chore/kit-adopt` exits 0, or `<repo>/.claude/worktrees/kit-adopt` exists: `refused: chore/kit-adopt exists locally` / `on origin` / `worktree path exists`. | T1 |
| R3g | The main checkout is not on its detected default branch (`_default_branch`): `refused: main checkout is on <branch>, not <def>`, because land's pull would report `PULL BLOCKED`. | T1 |
| R3h | `_pr_template <repo>` names a template and no `--body-file` was given: `refused: <template> exists; pass --body-file`, because land refuses a title-only body there. | T1 |
| R3i | `adopt.sh --dry-run <repo>` exits non-zero (the kit's own tree, a `--single-source` both-files refusal, a missing template): `refused: adopt --dry-run: <its last stderr line>`. | T1 |
| R4 | `gh` state is read once per batch with `_gh_state`, before the first repo. Not `ok`: every repo's row is `refused: gh is <state>`, and no repo reaches a write. | T1 |
| R5 | Under `--apply`, a repo that passed R3 runs, in order and stopping at the first failure: `cmd_start <repo> chore/kit-adopt` (its stdout line is the worktree); `"${WRAP_ADOPT_SH:-$LIB_ROOT/adopt.sh}" <wt>`; the path guard (R6); one `git add -A` and one commit with the fixed message (Interfaces), target repo hooks honored, never `--no-verify`; the override (R7); `cmd_land <wt> --title <T> [--body-file F]`; `adopt.sh --check <repo>` (R8). start and land are called as functions in the same process. The verb never reimplements their pushes, PR, merge, pull, or tidy. | T1 |
| R6 | Path guard: every path in `git -C <wt> status --porcelain` must match `ADOPT_PATHS`. Any other path: row `failed: adoption wrote <path>, outside the scaffold set; worktree left at <wt>`, no commit, no override, no push. An empty status: row `no change: origin/<def> already carries the adoption; worktree left at <wt>`. | T1 |
| R7 | The override is logged only after R6 passes, from inside `<wt>`: `bash "$PROOF_LEDGER_SH" override kit-adopt "<OVERRIDE_REASON>"`, the fixed text in Interfaces. It never passes a source file: `check`'s own source-remainder rule refuses an override for any `.sh`/`.py`/... path, and R6 keeps such a path out of the commit. A failed override log (exit non-zero): row `failed: override: <stderr>; worktree left at <wt>`, no land. | T1 |
| R8 | After land, whatever land's exit, if land printed `merged #<n>`, run `adopt.sh --check <repo>` on the main checkout. Exit 0: row `adopted`. Exit 1: row `merged, not adopted on the main checkout: <land's first PULL BLOCKED line, trimmed>`, or `: adopt --check exit 1` when land printed none. Land never printed `merged`: row `failed: land: <land's first REFUSED/FAILED line>`. | T1 |
| R9 | Land's output streams to the terminal as it runs (a check wait can last minutes) and a copy is kept in a temp file for R8's parse; the temp file is removed by the verb's EXIT trap. | T1 |
| R10 | Batch: repos run one at a time in argument order. A refusal or failure on one repo never stops the next. The run ends with an `ADOPT SUMMARY` table, one row per repo in argument order: repo basename, PR (`#<n>` or `-`), result. | T1 |
| R11 | Exit: 64 on usage (no repo, unknown flag, a flag missing its value). Else 0 when every row is `adopted`, `would adopt`, or `skip: already adopted`; 1 when any row is anything else. | T1 |
| R12 | A failure after `cmd_start` never removes the worktree or the branch: the row names the path, and `wrap apply --worktrees <repo>` is the tidy. | T1 |

Boundaries: no change to `adopt.sh`, `cmd_start`, `cmd_land`, `proof-ledger.sh`, or the ship-gate. No `--under` (out of scope). No force anywhere.

## Solution

### Approaches considered

1. **`adopt.sh --land <repo> [--title T]`.** Adoption's own script grows git and gh orchestration. It would shell out to `bin/wrap start` and `bin/wrap land`, grow its own batch loop and report table, and need a dry-run default inside a script whose bare form writes. Its `--check` exit contract is single-target 0/1, which a batch cannot keep.
2. **`wrap adopt` verb (chosen).** `wrap` already owns start and land as in-process functions, takes repo lists, runs dry by default with `--apply` (`apply`, `merge`), prints per-repo report lines, and documents a closed write set. `adopt.sh` stays a pure file writer called as a child.
3. **Keep the hand loop as a documented recipe.** Zero kit code, but every refusal stays manual. Rejected: two of six repos failed in the one real run, and the recipe carried a wrong override slug nobody noticed.

### Chosen approach + why

Approach 2. The verb composes four existing pieces (start, adopt.sh, override, land) and adds only the preflight, the path guard, and the summary. Approach 1 traded away the dry-run convention and the batch shape `wrap` already has; approach 3 traded away the refusals.

### Extensibility & boundaries

- The load-bearing dimension is the number of repos per call. Each repo is independent and serial, so a longer list costs time linearly and never shares state. Parallel landing is out of scope (land's pull and gh rate limits).
- Units: preflight (reads only, returns reasons), the per-repo apply sequence (calls four existing pieces), the summary printer. Each is one function in `lib/wrap/wrap-adopt.sh`.
- `ADOPT_PATHS` is the one place the adoption's file set lives. A future `adopt.sh` write outside it fails R6 loudly, and test case 22 catches the drift.

## Picture

```
 wrap adopt [--apply] repoA repoB ...
      |
      v
 _gh_state once ----------------------- not ok -> every row "refused: gh is <state>"
      |
      v  for each repo, in order
 preflight (reads only) -------------- skip / refused -> row, next repo
   check, main checkout?, ADOPT_PATHS status,
   sequencer, ls-files -u, chore/kit-adopt,
   on default?, PR template, adopt --dry-run
      |
      |  (dry run stops here: row "would adopt")
      v  --apply
 cmd_start repo chore/kit-adopt ------> <repo>/.claude/worktrees/kit-adopt
      |
 adopt.sh <wt>  -> path guard (ADOPT_PATHS only) -- outside -> row failed, wt left
      |
 git add -A; git commit (fixed message)
      |
 proof-ledger.sh override kit-adopt "<fixed reason>"   (from inside <wt>)
      |
 cmd_land <wt> --title T  -- push, PR, squash-merge, tree verify, pull, tidy
      |                        (output streamed + kept for the parse)
      v
 adopt.sh --check repo ---- 0 -> row "adopted"
                        `-- 1 -> row "merged, not adopted ...: <PULL BLOCKED line>"
      |
      v
 ADOPT SUMMARY   repo | PR | result      exit 0 / 1
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds one tradeoff: preflight duplicates two checks `cmd_start` also makes (branch exists locally or on origin). The duplicate is a read, so a dry run can report it before any fetch; `cmd_start` keeps its own check as the authority at write time.

### Diagram

The sequence is the `## Picture` above. The per-repo result is a small state machine:

```
 preflight --skip--> [skip: already adopted]
     |  \--refuse--> [refused: <reasons>]
     v
 (dry run) --------> [would adopt]
     v
 start --fail------> [failed: start: <msg>]
 adopt --fail------> [failed: adopt exit N; wt left]
 guard --outside---> [failed: adoption wrote <path>; wt left]
       --empty-----> [no change: ...; wt left]
 commit --fail-----> [failed: commit: <tail>; wt left]
 override --fail---> [failed: override: <msg>; wt left]
 land --no merge---> [failed: land: <line>]
      --merged-----> check --0--> [adopted]
                           --1--> [merged, not adopted on the main checkout: <why>]
```

### ADR link(s)

None. The verb adds no lasting decision beyond the `wrap` write set, which `lib/wrap/wrap.sh`'s header documents.

### Boundaries & failure modes

The verb merges onto other repos' default branches, which is not reversible by the verb. Dry run by default (DEC-B) and the refuse-before-write preflight are the boundary. Failure classes: `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**Command.** `bin/wrap adopt [--apply] [--title T] [--body-file F] <repo> [<repo>...]`. `--title` defaults to `chore: adopt the dwarves-kit operate-contract`. `--body-file` must name an existing file (else 64), and passes through to every land in the batch.

**Constants in `lib/wrap/wrap-adopt.sh`:**

```
ADOPT_BRANCH="chore/kit-adopt"
ADOPT_PATHS="AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md .claude/settings.json .claude/output-styles/"
ADOPT_COMMIT_SUBJECT="chore: adopt the dwarves-kit operate-contract"
ADOPT_COMMIT_BODY="AGENTS.md pointer, CLAUDE.md loader, WORKFLOW pointer, proof marker, starter .kit.toml, kit hook wiring."
OVERRIDE_REASON="adoption scaffold only: AGENTS.md pointer, CLAUDE.md loader, WORKFLOW.md pointer, proof marker, starter .kit.toml, kit hook wiring; no project code changed"
```

A path matches `ADOPT_PATHS` when it equals a listed file or starts with the listed directory (`.claude/output-styles/`). R3c passes the same list to `git status --porcelain --`.

**Seam (tests only).** `WRAP_ADOPT_SH` replaces the adopt driver for the R5 call alone; preflight R3a and R3i and the R8 check always run the real `$LIB_ROOT/adopt.sh`. Default `$LIB_ROOT/adopt.sh`.

**Report lines.** Per repo: `== <repo>` then indented lines (adopt's and land's own output, indented four spaces). Summary:

```
ADOPT SUMMARY
  <repo basename padded>  <#n or ->  <result>
```

**Exit codes.** R11.

### Data model changes

None. One override line per adopted repo lands in the existing override log, keyed by repo and `kit-adopt`.

### API changes

`wrap` gains the `adopt` verb: the dispatcher case in `main`, `adopt` in the module `source` loop, one usage line in the header, and the `_usage` line range (`sed -n '2,33p'`) widened by the lines added. The header's closed write-set paragraph gains: `adopt`'s one `git add -A` and one commit in the worktree `start` created, one override log append per repo, and every write `start` and `land` own. `adopt.sh`'s own file writes happen in that worktree.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: the verb

- [ ] T1: `lib/wrap/wrap-adopt.sh` (new: `cmd_adopt`, `_adopt_preflight`, `_adopt_one`, `_adopt_summary`), `lib/wrap/wrap.sh` (dispatcher, module loop, usage line, `_usage` range, write-set paragraph), `tests/test-wrap-adopt.sh` (new, on `tests/lib/wrap-stub.sh`), and `lib/wrap/wrap-adopt.sh` appended to every `# modules under test:` line (`tests/lib/wrap-stub.sh` and each `tests/test-wrap*.sh` header) so the section cache invalidates on it. Acceptance: test plan cases 1 to 24 pass; `bash tests/test-wrap-start.sh`, `bash tests/test-wrap-land.sh`, `bash tests/test-wrap-cli.sh` and `bash tests/test-adopt.sh` show no new failure against master.

### Phase 2: docs and proof

- [ ] T2: `commands/wrap.md` (one bullet beside the `start`/`land` bullets: what `adopt` composes, its refusals, its summary), `commands/adopt.md` (one paragraph: several repos at once go through `bin/wrap adopt`), `docs/verification/adopt-land.md` (the test run with captured output, the negative control below, and one real dry run against two local repos). Acceptance: the proof passes `bash lib/gate/proof-ledger.sh check . <base> adopt-land`.

## After state

- [ ] `bin/wrap adopt <repo>` exists and is a dry run. (Today: `wrap: unknown verb 'adopt'`, exit 64.) Checkable by `bin/wrap adopt ~/workspace/tieubao/dotfiles; echo $?` printing a `refused:` line naming `AGENTS.md` and `1`.
- [ ] A dry run over an adopted and an unadopted clean repo prints `skip: already adopted` and `would adopt`, exit 0, and `git status`, `git branch` and `git worktree list` in both repos are unchanged.
- [ ] `--apply` on a clean unadopted fixture repo leaves origin's default branch holding the six adoption paths, the main checkout pulled, `adopt.sh --check` exit 0, no `chore/kit-adopt` locally or on origin, and one override line `| kit-adopt | OVERRIDE | adoption scaffold only...` for that repo.
- [ ] `bash tests/test-wrap-adopt.sh` passes and goes red on master (negative control below).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Every test plan row passes.
- [ ] No regression in the existing wrap, adopt, and proof-ledger suites against master's baseline.

## Test plan

All cases in `tests/test-wrap-adopt.sh`, on the wrap-stub harness: a bare remote, a clone as the main checkout, the gh stub on PATH, `KIT_LEDGER_DIR` and `KIT_CONFIG_OPERATOR` pinned to scratch. No case touches the network or a real repo.

| # | Case | Expect |
|---|---|---|
| 1 | clean unadopted clone, no `--apply` | `would adopt`; exit 0; no `.claude/worktrees/kit-adopt`, no `chore/kit-adopt` ref, no fetch (origin ref unchanged), gh stub log empty, override log absent |
| 2 | adopted clone (adoption committed and pushed) | `skip: already adopted`; exit 0; no other check output |
| 3 | untracked `AGENTS.md` in the clone, `--apply` | `refused:` naming `?? AGENTS.md`; exit 1; no worktree, no branch, gh log empty |
| 4 | modified tracked `CLAUDE.md`, `--apply` | `refused:` naming ` M CLAUDE.md` |
| 5 | untracked `WORKFLOW.md`, `.kit.toml`, `docs/verification/README.md`, `.claude/settings.json`, each in its own fixture | each `refused:` naming that path |
| 6 | two collision paths at once | one row naming both, joined by `; ` |
| 7 | real merge conflict left in progress (`MERGE_HEAD` set) | `refused:` with `mid-merge` and `unmerged paths:` |
| 8 | `rebase-merge` dir present | `refused: mid-rebase` |
| 9 | unmerged path with no sequencer file (a `stash pop` conflict) | `refused: unmerged paths: <path>`, no `mid-` reason |
| 10 | local `chore/kit-adopt` exists | `refused: chore/kit-adopt exists locally` |
| 11 | `chore/kit-adopt` on origin only | `refused: chore/kit-adopt exists on origin` |
| 12 | clone checked out on `feat/x` | `refused: main checkout is on feat/x, not main` |
| 13 | `.github/pull_request_template.md` tracked, no `--body-file` | `refused:` naming the template; with `--body-file` the same repo passes preflight |
| 14 | a linked worktree path given as `<repo>` | `refused: not a main checkout` |
| 15 | operator overlay `adopt.single_source = true`, both `AGENTS.md` and `CLAUDE.md` tracked and different | `refused: adopt --dry-run:` quoting adopt's "merge them by hand" line |
| 16 | gh stub reports not logged in, two repos | both rows `refused: gh is <state>`; no worktree in either |
| 17 | clean unadopted clone, `--apply`, gh stub opens #7 and merges | `opened PR #7`, `merged #7` streamed; summary row `#7  adopted`; exit 0; worktree and branch gone locally and on origin; clone's HEAD equals origin/main; `adopt.sh --check` exit 0; the merged commit subject equals `ADOPT_COMMIT_SUBJECT` |
| 18 | case 17's override log | exactly one line with the clone's repo id, `kit-adopt`, `OVERRIDE`, and `OVERRIDE_REASON` |
| 19 | `WRAP_ADOPT_SH` stub also writes `src/x.sh` | `failed: adoption wrote src/x.sh`; no commit on the branch; no override line; gh log has no create; worktree left and named |
| 20 | `WRAP_ADOPT_SH` stub writes nothing | `no change:` row; exit 1; no commit, no override |
| 21 | the clone's main branch carries one unpushed commit (not refused by preflight) | land merges #7, prints `PULL BLOCKED`; row `merged, not adopted on the main checkout: PULL BLOCKED: pull --ff-only refused ...`; exit 1 |
| 22 | drift guard: real `adopt.sh` on a fresh fixture, then every `git status --porcelain` path | each matches `ADOPT_PATHS` |
| 23 | batch: [case-3 fixture, case-17 fixture, case-2 fixture] with `--apply` | runs in that order; summary rows in that order: `refused`, `#7 adopted`, `skip: already adopted`; exit 1 |
| 24 | no repo; unknown flag `--force`; `--title` with no value; `--body-file` naming a missing file | each exit 64, nothing written |

## Verification

```
bash tests/test-wrap-adopt.sh
bash tests/test-wrap-start.sh && bash tests/test-wrap-land.sh && bash tests/test-wrap-cli.sh && bash tests/test-adopt.sh
bin/wrap adopt ~/workspace/dwarvesf/spacedown ~/workspace/tieubao/dotfiles ~/workspace/dwarvesf/foundation-workers
```

The third line is a real dry run: expect `skip: already adopted`, `refused: ?? AGENTS.md ...`, `would adopt`, exit 1, and no change in any of the three repos.

## Edge Cases

1. Dirt in the main checkout outside `ADOPT_PATHS` (an edited `src/app.ts`): not refused. The fast-forward only rewrites files the adoption touches, so the pull still runs.
2. A tracked, clean `AGENTS.md` or `CLAUDE.md` in the main checkout: not a collision. `adopt.sh` leaves a repo's own `AGENTS.md` alone and appends its block to `CLAUDE.md` in the worktree; the pull applies that change cleanly.
3. The main checkout is behind origin and origin already carries the adoption: R3a reads the stale checkout as not adopted, adopt in the worktree writes nothing, R6 reports `no change` and names the pull to run.
4. The target repo's own pre-commit or commit-msg hook refuses the commit: row `failed: commit: <last stderr line>; worktree left at <wt>`. Never `--no-verify`.
5. The repo's workflows trigger on `pull_request` and a check fails: land leaves the PR open (its own `MERGE REFUSED` line); row `failed: land: MERGE REFUSED #<n>: checks failed: ...`; PR column `#<n>`.
6. The same repo named twice: the second run reads it as adopted (or as holding `chore/kit-adopt` if the first failed) and skips or refuses by name.
7. Two `wrap adopt` runs on one repo at once: the second hits `cmd_start`'s existing-branch or worktree-path refusal; R12 keeps the first run's worktree untouched.
8. Case-insensitive filesystems: an untracked `agents.md` shows in `git status` under its own case, which R3c does not match. Out of scope; adopt and git agree on case on every repo seen so far.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Merged upstream, not adopted locally | R8 row `merged, not adopted on the main checkout: <PULL BLOCKED line>` | Resolve the named block in the main checkout, then `git pull --ff-only`; re-run `wrap adopt <repo>` dry to confirm `skip: already adopted` |
| Override written for an unmerged branch | override line exists, row is `failed: land:` | Harmless: the override is scoped to repo and `kit-adopt` and only excuses the adoption's own non-source diff; a re-run reuses the branch slug |
| `adopt.sh` grows a new write outside `ADOPT_PATHS` | R6 `failed: adoption wrote <path>` on every repo; test case 22 red | Add the path to `ADOPT_PATHS` in the same change that adds the write |
| gh rate limit mid-batch | land's own `PR REFUSED` or `MERGE FAILED` line on that repo's row | Later repos keep running and fail the same way; re-run the failed repos after the limit resets |

## Out of Scope

- `--under <root>`: adoption is a per-repo choice, and a root sweep would adopt repos the operator never picked.
- Refusing a main checkout whose default branch carries unpushed commits: land still merges; the row names the `PULL BLOCKED` line (case 21).
- Cleaning up a worktree after a failure (R12): `wrap apply --worktrees` owns that.
- Making the ship-gate hook engage on `wrap land` (see Grounding G4).

## Touches

- lib/wrap/**
- tests/**
- commands/**
- docs/verification/**

## Decision Log

- DEC-A: home is a `wrap adopt` verb, not `adopt.sh --land`. `wrap` already owns start and land in-process, repo lists, the dry-run then `--apply` convention, and a documented write set; `adopt.sh` stays a file writer whose bare form writes and whose `--check` is single-target. Rejected: `adopt.sh --land` (orchestration inside the file writer, two conflicting defaults in one script), the documented recipe (manual refusals, the wrong-slug bug).
- DEC-B: dry run by default, `--apply` to act. One call pushes, opens a PR, and squash-merges onto the default branch of each repo named, which the verb cannot undo; `wrap apply` and `wrap merge` use the same convention.
- DEC-C: the collision set is `ADOPT_PATHS`, wider than the session's five names: it adds `.claude/settings.json` and `.claude/output-styles/`, because a real adoption diff writes `.claude/settings.json` (Grounding G2). One constant serves R3c and R6.
- DEC-D: preflight also refuses a main checkout off its default branch (R3g), a linked worktree (R3b), a PR template without `--body-file` (R3h), and an `adopt.sh --dry-run` refusal (R3i). Each is a refusal land or adopt would hit later, after a worktree and commit exist; moving it to preflight keeps "refuse before any write" true.
- DEC-E: the override guard is the path allowlist (R6), not `proof-ledger.sh classify`. `classify` reads a real adoption diff as `behavioral` because of `.claude/settings.json` (Grounding G2), so "inert only" would refuse every adoption. The allowlist proves "scaffold only" by name, and `check`'s source-remainder rule stays as the second wall.
- DEC-F: the override slug is `kit-adopt` (R2). The hand loop's `chore-kit-adopt` never matched the ship-gate's lookup (Grounding G3).
- DEC-G: preflight reports every reason it finds, not the first, so one dry run lists the whole fix.

## Grounding

**G1. `adopt.sh --check` and the preflight reads, live, read-only.** The probe ran `adopt.sh --check`, `git status --porcelain -- AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md`, each sequencer path through `git rev-parse --git-path`, `git ls-files -u`, the local `chore/kit-adopt` ref, and `ls-remote --exit-code --heads origin chore/kit-adopt` against four local repos. Actual output:

```
== /Users/tieubao/workspace/dwarvesf/spacedown
adopted: /Users/tieubao/workspace/dwarvesf/spacedown
   check exit=0
   collide:
   unmerged paths:
   local chore/kit-adopt: no
   origin chore/kit-adopt ls-remote exit=2 (2 = absent)
== /Users/tieubao/workspace/tieubao/dotfiles
not adopted: /Users/tieubao/workspace/tieubao/dotfiles
   check exit=1
   collide: ?? AGENTS.md;
   unmerged paths:
   local chore/kit-adopt: no
   origin chore/kit-adopt ls-remote exit=2 (2 = absent)
== /Users/tieubao/workspace/dwarvesf/memo.d.foundation
not adopted: /Users/tieubao/workspace/dwarvesf/memo.d.foundation
   check exit=1
   collide: UU CLAUDE.md;
   unmerged paths: CLAUDE.md
   local chore/kit-adopt: no
   origin chore/kit-adopt ls-remote exit=2 (2 = absent)
== /Users/tieubao/workspace/dwarvesf/foundation-workers
not adopted: /Users/tieubao/workspace/dwarvesf/foundation-workers
   check exit=1
   collide:
   unmerged paths:
   local chore/kit-adopt: no
   origin chore/kit-adopt ls-remote exit=2 (2 = absent)
```

What it settles: `--check` prints `adopted: <path>` / `not adopted: <path>` with exit 0 / 1 (R3a). `dotfiles` is the session's untracked-`AGENTS.md` shape (R3c, case 3). `memo.d.foundation` shows an unmerged `CLAUDE.md` with no `MERGE_HEAD`, `rebase-*`, `CHERRY_PICK_HEAD` or `REVERT_HEAD` present (no `in-progress:` line printed), so R3e must stand apart from R3d (case 9). `ls-remote` exits 2 for an absent branch (R3f). A sweep of every repo under `~/workspace/tieubao` and `~/workspace/dwarvesf` found 5 adopted and the rest not.

**G2. What a real adoption writes, and how `classify` reads it.** In a throwaway repo under the session scratchpad (`git init`, one empty base commit), `lib/adopt.sh <scratch>` then `git add -A && git commit`:

```
adopt: single-source mode on (adopt.single_source knob)
adopt: project hook-module wiring for <scratch> -> modules: board session advisor
adopt: <scratch> (updated)
.claude/settings.json
.kit.toml
AGENTS.md
CLAUDE.md
WORKFLOW.md
docs/verification/README.md
classify: behavioral
```

What it settles: `.claude/settings.json` is in the adoption diff (DEC-C, `ADOPT_PATHS`). `classify` says `behavioral`, not `inert`, because `.claude/settings.json` is neither markdown nor `.kit.toml` (DEC-E). The operator's install has `adopt.single_source` on, so case 15's single-source refusal is a live path, not a hypothetical.

**G3. The override slug must be `kit-adopt`.** Same scratch repo, override log pinned with `KIT_LEDGER_DIR` to scratch:

```
check kit-adopt (empty override log): exit=1
check kit-adopt (only chore-kit-adopt logged): exit=1
check kit-adopt (both overrides logged): exit=0
proof-of-done: OVERRIDDEN for 'kit-adopt' (docs/deploy-inert remainder; logged, see <scratch>.ledger/proof-overrides.log)
```

What it settles: without an override, `check` blocks the adoption diff as behavioral. The hand loop's `chore-kit-adopt` override changes nothing. `kit-adopt` passes, and `check` accepts it because no adoption path has a source extension (R7).

**G4. The ship-gate hook does not engage on `wrap land`.** `printf '{"tool_input":{"command":"wrap land /x/.claude/worktrees/kit-adopt"}}' | bash hooks/ship-gate.sh` exits 0 with no output: the command line holds no literal `git push` or `gh pr create`, and land's own push runs inside the script. So the R7 override is the audit record, and the unlock for any later hand `git push` of the branch; it is not what lets `wrap adopt`'s land through. `grep` over `lib/wrap/` finds no `proof-ledger.sh check` call in land either.

**G5. Negative control, dry trace (case 3).** Fixture: wrap-stub bare remote, a clone as main checkout, `echo x > AGENTS.md` untracked. Command: `bin/wrap adopt --apply "$clone"`. Assertions: output carries `refused:` and `?? AGENTS.md`; exit 1; `[ ! -e "$clone/.claude/worktrees/kit-adopt" ]`; `git -C "$clone" rev-parse -q --verify refs/heads/chore/kit-adopt` fails; the gh stub log is empty.

- On master: `bin/wrap` execs `lib/wrap/wrap.sh`, `main` reaches `*) echo "wrap: unknown verb 'adopt' (try: wrap --help)" >&2; return 64`. Output lacks `refused:` and `AGENTS.md`, exit is 64 not 1: case 3's first two assertions go red.
- Mutation on the branch (the proof's recorded control): delete the R3c collision loop from `_adopt_preflight`. Preflight passes, `cmd_start` runs `git worktree add -b chore/kit-adopt "$clone/.claude/worktrees/kit-adopt" origin/main`, so the no-worktree and no-branch assertions go red, and `refused:` is absent. Restore the loop: green.

## Open questions

(none)
