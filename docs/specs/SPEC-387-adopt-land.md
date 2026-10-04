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
| R1 | `wrap adopt [--apply] [--body-file F] <repo> [<repo>...]`. Without `--apply` it is a dry run: it runs every preflight read (R3) and `adopt.sh --dry-run <repo>`, prints `would adopt` or the refusal, and writes nothing (no fetch, no worktree, no branch, no ledger line). `--body-file` with more than one repo is usage, exit 64: one body written for one repo's PR template is wrong for the next. Every repo argument passes `_reject_packed adopt`. `--apply` is operator-only by policy, not by mechanism: an agent runs the dry run and hands the operator the `--apply` command line; `commands/wrap.md` says so (T2), and nothing in the verb can tell who typed it (DEC-J). | T1a |
| R2 | The branch is always `chore/kit-adopt`. The override slug is `kit-adopt`, derived as `${branch#*/}`, the same rule as `hooks/ship-gate.sh` line 151 and `gate-ledger.sh rid`. | T1a |
| R3 | Preflight, per repo, reads only, before any write. The first check short-circuits; the rest are all collected and the row names every reason found, joined by `; `. | T1a |
| R3a | `adopt.sh --check <repo>` exits 0: row `skip: already adopted`, no other check runs. | T1a |
| R3b | `<repo>` is not a main checkout (its git dir differs from its common dir, or it is not a repo): `refused: not a main checkout`. | T1a |
| R3c | A collision path (Interfaces: `ADOPT_PATHS`) shows any line in `git status --porcelain --untracked-files=all --no-renames -- <ADOPT_PATHS>` in the main checkout (untracked, modified, staged, or unmerged): `refused: <XY> <path> in the main checkout would block the post-land pull`, one per path. `--untracked-files=all` lists each file under a new directory instead of the collapsed `?? .claude/`, and `--no-renames` lists a staged rename as its `D` and `A` paths, so R3c and R6 read paths the same way. | T1a |
| R3d | A sequencer operation is in progress (`MERGE_HEAD`, `rebase-merge`, `rebase-apply`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, each read with `git rev-parse --git-path`): `refused: mid-merge` / `mid-rebase` / `mid-cherry-pick` / `mid-revert`. | T1a |
| R3e | `git ls-files -u` lists any path, whatever R3d found: `refused: unmerged paths: <paths>`. | T1a |
| R3f | `refs/heads/chore/kit-adopt` exists, or `ls-remote --exit-code --heads origin chore/kit-adopt` exits 0, or `<repo>/.claude/worktrees/kit-adopt` exists: `refused: chore/kit-adopt exists locally` / `on origin` / `worktree path exists`. When that worktree exists on `chore/kit-adopt` with at least one commit ahead of the local `refs/remotes/origin/<def>` (no fetch), R3f reads `gh pr list --repo <origin> --head chore/kit-adopt --state merged --json number` (a read; R4 already proved gh `ok`). One merged PR: the row ends `; merged #<n>; read <wt>`, never `resume:`, because land's exit 3 returns before `_land_tidy` and leaves the worktree, the branch, and the origin branch behind a merged PR (`lib/wrap/wrap-land.sh`, the `MISMATCH*)` and `*)` arms after `_tree_verify`, each `return 3`). No merged PR: the row ends `; resume: wrap land <wt>` (R12). A failed lookup: `; PR state unreadable; read <wt>`. | T1a |
| R3g | The main checkout is not on its detected default branch (`_default_branch`): `refused: main checkout is on <branch>, not <def>`, because land's pull would report `PULL BLOCKED`. | T1a |
| R3h | `_pr_template <repo>` names a template and no `--body-file` was given: `refused: <template> exists; pass --body-file`, because land refuses a title-only body there. | T1a |
| R3i | `adopt.sh --dry-run <repo>` exits non-zero (the kit's own tree, a `--single-source` both-files refusal, a missing template): `refused: adopt --dry-run: <its last stderr line>`. | T1a |
| R3k | An `ADOPT_PATHS` entry is ignored by the target repo: `git -C <repo> check-ignore -q --no-index -- <entry>` exits 0 for any entry, as listed (the directory entry `.claude/output-styles/` included): `refused: <entry> is gitignored`, one per entry. `--no-index` counts a tracked path that an ignore rule also matches. An ignored path would drop out of R5's `git add -A`, so the adoption would land without it. | T1a |
| R4 | `gh` state is read once per batch with `_gh_state`, before the first repo. Not `ok`: every repo's row is `refused: gh is <state>`, and no repo reaches a write. | T1a |
| R5 | Under `--apply`, a repo that passed R3 runs, in order and stopping at the first failure: `cmd_start <repo> chore/kit-adopt` (its stdout line is the worktree); `"${WRAP_ADOPT_SH:-$LIB_ROOT/adopt.sh}" <wt>`; one `git -C <wt> add -A`; the path guard and the settings guard (R6, R6a) on the staged list; one commit with the fixed message (Interfaces), target repo hooks honored, never `--no-verify`; the post-commit recheck (R6b); the override (R7); `cmd_land <wt> [--body-file F]` (captured per R9; land's own title default reads the commit subject); `adopt.sh --check <repo>` (R8). start and land are called as functions of this script (land inside R9's pipeline subshell), never through `bin/wrap`. The verb never reimplements their pushes, PR, merge, pull, or tidy. | T1b |
| R6 | Path guard: every path in `git -C <wt> diff --cached --name-only --no-renames -z`, read after R5's `git add -A`, must match `ADOPT_PATHS`. Under `.claude/output-styles/` the only allowed path is `.claude/output-styles/<s>.md`, where `<s>` is the staged `outputStyle` (R6a); with no staged `outputStyle`, no path there is allowed. The staged list names each file under a new directory and splits a single-source `git mv CLAUDE.md AGENTS.md` into its two paths, where plain `git status --porcelain` would print `?? .claude/` and `R  CLAUDE.md -> AGENTS.md`. Any other path: row `failed: adoption wrote <path>, outside the scaffold set; worktree left at <wt>`, no commit, no override, no push. An empty list: row `no change: origin/<def> already carries the adoption; worktree left at <wt>`. | T1b |
| R6a | Settings guard, when the staged list holds `.claude/settings.json`: compare the staged blob (`git show :.claude/settings.json`) against `origin/<def>:.claude/settings.json` (`{}` when absent). Both must parse with `jq`. All matching runs in `jq` `test()` (Oniguruma), never `grep -E` and never a line-split loop, so an embedded newline stays inside one command string; `KIT_HOOK_RE` anchors with `\A` and `\z`, which reject a newline anywhere. A kit entry is a hook object with `type == "command"`, keys only from {`type`, `command`, `timeout`, `async`}, and `command` matching `KIT_HOOK_RE`. Every staged hook entry absent from the base must be a kit entry. Normalize both sides, then require them equal: on the staged side drop every kit entry; on the base side drop every entry whose `command` contains `dwarves-kit/hooks/` (what `adopt.sh` strips before its merge, the `contains("dwarves-kit/hooks/") \| not` filter); on both sides drop the `outputStyle` key, groups left with no hooks, events left with no groups, and a `hooks` object left empty; then `jq -S` with arrays sorted by their JSON text, as `adopt.sh` writes them. A staged `outputStyle` must be a bare name (`\A[A-Za-z0-9_.-]+\z`, no `..`), the shape `adopt.sh` step 6b accepts. Any miss: row `failed: adoption changed .claude/settings.json beyond kit hooks: <event> <matcher> #<index>` (or `: key <name>` for a non-hook key), never the raw command text; worktree left at `<wt>`; no commit, no override, no push. | T1b |
| R6b | Post-commit recheck, before R7: `git -C <wt> status --porcelain` must be empty, and R6 and R6a run again on `git -C <wt> diff --name-only --no-renames origin/<def> HEAD` and the committed `HEAD:.claude/settings.json`. A target repo's commit hook can rewrite or add to the commit after the staged guard ran. Any miss: row `failed: the commit differs from the guarded set: <path or entry>; worktree left at <wt>`, no override, no land, no `resume:`. | T1b |
| R7 | The override is logged before land, only after R6, R6a and R6b pass, from inside `<wt>`: `bash "$PROOF_LEDGER_SH" override kit-adopt "<OVERRIDE_REASON>"`, the fixed text in Interfaces. It never passes a source file: `check`'s own source-remainder rule refuses an override for any `.sh`/`.py`/... path, and R6 keeps such a path out of the commit. A failed override log (exit non-zero): row `failed: override: <stderr>; resume: wrap land <wt>`, no land. | T1b |
| R8 | Land's exit code is read first, then its captured lines. A merge counts only on land's exact line `merged #<n> (<sha>): tree verified` (`lib/wrap/wrap-land.sh`, the `OK)` arm after `_tree_verify`). Exit 3 is land's post-merge tree failure (`merged #<n> (<sha>): TREE MISMATCH, ...` or `merged #<n> (<sha>): tree <verdict>`): row `failed: land exit 3: <that line>; worktree left at <wt>`, no `resume:`. A counted merge (exit 0 or 2): run `adopt.sh --check <repo>` on the main checkout. Exit 0: row `adopted`. Exit 1: row `merged, not adopted on the main checkout: <land's first PULL BLOCKED line, trimmed>`, or `: adopt --check exit 1` when land printed none. No counted merge and exit not 3: row `failed: land exit <rc>: <land's first REFUSED/FAILED line>; resume: wrap land <wt> [--body-file F]`. Two exceptions. When that captured line names `wrap merge` (land's CONFLICTING-cycle exits, which leave a merge commit on origin), the row quotes land's advice and adds no `resume:`. Exit 130 or 143 (an interrupt): the row reads `interrupted: land exit <rc>; read <wt>`, the batch stops, and every repo not yet started gets the row `not run` (R10). | T1b |
| R9 | Land's stdout and stderr stream to the terminal as it runs (a check wait can last minutes) and a copy is kept in a temp file for R8's parse: `cmd_land ... 2>&1 \| tee -i "$log" \|\| land_rc=${PIPESTATUS[0]}` with `land_rc=0` set first. `tee -i` ignores SIGINT, so a Ctrl-C reaches land and the capture still holds land's last lines. `PIPESTATUS[0]` is land's own exit code, where a bare `$?` would be `tee`'s. Land's `REFUSED` and `FAILED` lines go to stderr, so the `2>&1` is what lets R8 quote them. The temp file is removed by the verb's EXIT trap. | T1b |
| R10 | Batch: repos run one at a time in argument order. A refusal or failure on one repo never stops the next; an interrupt in land (R8) stops the batch. The run ends with an `ADOPT SUMMARY` table, one row per repo in argument order: repo basename, PR (`#<n>` or `-`), result. | T1c |
| R11 | Exit: 64 on usage (no repo, unknown flag, a flag missing its value, `--body-file` naming a missing file or given with more than one repo). Else 0 when every row is `adopted`, `would adopt`, or `skip: already adopted`; 1 when any row is anything else (`not run` included). | T1a |
| R12 | A failure after `cmd_start` never removes the worktree or the branch, and the row names the path. Recovery depends on the stage. A failure after R6b and before a counted merge (override, or land with no counted merge, outside R8's two exceptions) ends the row with `resume: wrap land <wt>`, plus `--body-file F` when one was given; F must outlive the run, so the verb never deletes or copies it. Land adopts the PR it already opened, or pushes and opens one, and needs no adopt preflight. A failure before or at R6b (adopt, guard, settings guard, recheck, no change, commit) leaves the worktree for the operator to read, with no `resume:`; R3f names it on a re-run. A land exit 3 leaves a merged PR behind; R3f reads it and prints `merged #<n>; read <wt>`. `wrap apply --worktrees` is not the recovery: it prints `SKIP <wt>: <branch> is not proven merged into <def> (leave it)` for an unmerged branch and `SKIP <wt>: dirty` for an uncommitted one (`lib/wrap/wrap-apply.sh`). | T1b |

Boundaries: no change to `adopt.sh`, `cmd_start`, `cmd_land`, `proof-ledger.sh`, or the ship-gate. No `--under` (out of scope). No force anywhere. The ship-gate hook never sees the push `cmd_land` makes (Grounding G4): it reads the Bash command line, and `wrap adopt --apply` holds no literal `git push` or `gh pr create`. So no proof-of-done or lane gate stands between this verb and the target repo's default branch. The walls are the R3 preflight, the R6/R6a/R6b guards, and the fixed override text. R1's operator-only `--apply` is policy, not a mechanism: an agent with shell access can type it, the same ceiling ADR 0024 accepts for overrides (DEC-J).

## Solution

### Approaches considered

1. **`adopt.sh --land <repo>`.** Adoption's own script grows git and gh orchestration. It would shell out to `bin/wrap start` and `bin/wrap land`, grow its own batch loop and report table, and need a dry-run default inside a script whose bare form writes. Its `--check` exit contract is single-target 0/1, which a batch cannot keep.
2. **`wrap adopt` verb (chosen).** `wrap` already owns start and land as in-process functions, takes repo lists, runs dry by default with `--apply` (`apply`, `merge`), prints per-repo report lines, and documents a closed write set. `adopt.sh` stays a pure file writer called as a child.
3. **Keep the hand loop as a documented recipe.** Zero kit code, but every refusal stays manual. Rejected: two of six repos failed in the one real run, and the recipe carried a wrong override slug nobody noticed.

### Chosen approach + why

Approach 2. The verb composes four existing pieces (start, adopt.sh, override, land) and adds only the preflight, the path guard, and the summary. Approach 1 traded away the dry-run convention and the batch shape `wrap` already has; approach 3 traded away the refusals.

### Extensibility & boundaries

- The load-bearing dimension is the number of repos per call. Each repo is independent and serial, so a longer list costs time linearly and never shares state. Parallel landing is out of scope (land's pull and gh rate limits).
- Units: preflight (reads only, returns reasons), the per-repo apply sequence (calls four existing pieces), the summary printer. Each is one function in `lib/wrap/wrap-adopt.sh`.
- `ADOPT_PATHS` is the one place the adoption's file set lives. A future `adopt.sh` write outside it fails R6 loudly, and test case 22 catches the drift.
- R8 and R3f parse land's output text (`merged #<n> (<sha>): tree verified`, `TREE MISMATCH`, `PULL BLOCKED`, `REFUSED`, `FAILED`, `wrap merge`). That coupling is suite-guarded: cases 17, 21, 27, 29, 35 run the real `cmd_land` against the gh stub, so a reworded land line turns them red before a release.

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
   on default?, PR template, adopt --dry-run, gitignored?
      |
      |  (dry run stops here: row "would adopt")
      v  --apply
 cmd_start repo chore/kit-adopt ------> <repo>/.claude/worktrees/kit-adopt
      |
 adopt.sh <wt>; git add -A
      |
 path guard (staged list, ADOPT_PATHS only) + settings guard (kit hooks only)
      |                                  -- miss -> row failed, wt left
 git commit (fixed message)
      |
 recheck: clean status, guards again on origin/<def>..HEAD -- miss -> row failed, wt left
      |
 proof-ledger.sh override kit-adopt "<fixed reason>"   (from inside <wt>)
      |
 cmd_land <wt> [--body-file F] -- push, PR, squash-merge, tree verify, pull, tidy
      |                        (2>&1 | tee -i, rc from PIPESTATUS)
      |   no "tree verified" line, rc != 3 -> row failed, "resume: wrap land <wt>"
      |                                       (or land's own "wrap merge" advice)
      |   rc 3 (TREE MISMATCH)             -> row failed, wt left, no resume
      |   rc 130 / 143                     -> row interrupted, batch stops, rest "not run"
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
 start --fail---------> [failed: start: <msg>]
 adopt --fail---------> [failed: adopt exit N; worktree left at <wt>]
 add -A, guard (R6)
   --outside----------> [failed: adoption wrote <path>, outside the scaffold set; worktree left at <wt>]
   --empty------------> [no change: origin/<def> already carries the adoption; worktree left at <wt>]
 settings guard (R6a)
   --miss-------------> [failed: adoption changed .claude/settings.json beyond kit hooks: <event> <matcher> #<index>; worktree left at <wt>]
 commit --fail--------> [failed: commit: <last stderr line>; worktree left at <wt>]
 recheck (R6b)
   --miss-------------> [failed: the commit differs from the guarded set: <x>; worktree left at <wt>]
 override --fail------> [failed: override: <stderr>; resume: wrap land <wt> [--body-file F]]
 land (R8, R9)
   --rc 130/143-------> [interrupted: land exit <rc>; read <wt>]  (later repos: [not run])
   --rc 3-------------> [failed: land exit 3: <TREE line>; worktree left at <wt>]
   --names wrap merge-> [failed: land exit <rc>: <land's wrap merge line>]
   --no counted merge-> [failed: land exit <rc>: <line>; resume: wrap land <wt> [--body-file F]]
   --counted merge----> check --0--> [adopted]
                              --1--> [merged, not adopted on the main checkout: <why>]
```

### ADR link(s)

- `docs/decisions/0013-agents-md-operating-layer.md`: the files the verb lands (`AGENTS.md` front door, thin `CLAUDE.md`, `WORKFLOW.md` pointer) are this ADR's operating layer; the verb adds no new file shape.
- `docs/decisions/0024-gate-ledger-and-ship-enforcement.md`: the override is "an explicit logged reason in the ledger (operator-authored)". The verb writes it, not the operator; DEC-J records why that stays inside the ADR.
- `docs/decisions/0025-proof-of-done-ship-gate.md`: "an explicit, logged override is the only bypass" of the proof gate. R7 uses that bypass, scoped by R6 and R6a to the scaffold set, with `check`'s source-remainder rule as the second wall.

The verb adds no new lasting decision beyond these and the `wrap` write set, which `lib/wrap/wrap.sh`'s header documents.

### Boundaries & failure modes

The verb merges onto other repos' default branches, which is not reversible by the verb. Dry run by default (DEC-B) and the refuse-before-write preflight are the boundary. Operator-only `--apply` (R1) is policy, not a mechanism: the verb cannot tell an operator from an agent, the ceiling ADR 0024's threat model already accepts. The ship-gate does not guard this boundary: it never sees the push `cmd_land` makes inside the script (Grounding G4), so neither ADR 0024's lane gate nor ADR 0025's proof gate runs on it. The R6/R6a/R6b guards are the only content check before the merge. Failure classes: `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**Command.** `bin/wrap adopt [--apply] [--body-file F] <repo> [<repo>...]`. No `--title`: land's own default reads the one commit's subject, `ADOPT_COMMIT_SUBJECT`. `--body-file` must name an existing file and comes with exactly one repo (else 64). It passes to that repo's land and is repeated in any `resume:` line, so F must outlive the run.

**Constants in `lib/wrap/wrap-adopt.sh`:**

```
ADOPT_BRANCH="chore/kit-adopt"
ADOPT_PATHS="AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md .claude/settings.json .claude/output-styles/"
ADOPT_COMMIT_SUBJECT="chore: adopt the dwarves-kit operate-contract"
ADOPT_COMMIT_BODY="AGENTS.md pointer, CLAUDE.md loader, WORKFLOW pointer, proof marker, starter .kit.toml, kit hook wiring."
OVERRIDE_REASON="written by wrap adopt --apply: adoption scaffold only, every path in ADOPT_PATHS (R6); .claude/settings.json changes limited to kit hook commands and outputStyle (R6a); no other file changed"
KIT_HOOK_RE='\Abash \$HOME/\.claude/dwarves-kit/hooks/(anchor-root\.sh \$HOME/\.claude/dwarves-kit/hooks/)?[A-Za-z0-9_-]+\.sh( --[a-z][a-z-]*)*\z'
```

A path matches `ADOPT_PATHS` when it equals a listed file or starts with the listed directory (`.claude/output-styles/`, narrowed by R6 to the one staged style file). R3c passes the same list to `git status --porcelain --untracked-files=all --no-renames --`, and R3k checks each entry as listed.

`KIT_HOOK_RE` is passed to `jq` as `--arg re` and applied with `test($re)`. It matches the two command shapes the kit's `settings.json` ships, which `adopt.sh` copies verbatim: `bash $HOME/.claude/dwarves-kit/hooks/anchor-root.sh $HOME/.claude/dwarves-kit/hooks/<name>.sh` and `bash $HOME/.claude/dwarves-kit/hooks/<name>.sh` (`secrets-guard.sh`), each with optional `--flag` arguments (`harvest.sh --lab-log`). `$HOME` is literal text in the file, never expanded. In `jq`, `$` also matches before a final newline; `\z` does not, so a command ending in a newline fails.

**Seam (tests only).** `WRAP_ADOPT_SH` replaces the adopt driver for the R5 call alone; preflight R3a and R3i and the R8 check always run the real `$LIB_ROOT/adopt.sh`. Default `$LIB_ROOT/adopt.sh`.

**Report lines.** Per repo: `== <repo>`, then indented lines (adopt's and land's own output, indented four spaces), then one `  result: <#n or -> <row>` line printed as that repo finishes (T1b). The summary repeats every row at the end (T1c):

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

Four tasks, in order; each leaves the suite green.

- [ ] T1a: preflight, dry run, exit codes (R1 to R4, R11). `lib/wrap/wrap-adopt.sh` (new: `cmd_adopt` arg parse and dry-run path, `_adopt_preflight`), `lib/wrap/wrap.sh` (dispatcher, module loop, usage line, `_usage` range, write-set paragraph), `tests/test-wrap-adopt.sh` (new, on `tests/lib/wrap-stub.sh`). Acceptance: cases 1 to 16, 24, 30, 31, 32 pass.
- [ ] T1b: apply, guards, recheck, override, land parse (R5 to R9, R12). `lib/wrap/wrap-adopt.sh` (`_adopt_one`, the R6 path guard, the R6a settings guard, the R6b recheck, the R8 parse), `tests/test-wrap-adopt.sh`. Acceptance: cases 17 to 22, 25 to 29, 33, 35, 36 pass.
- [ ] T1c: batch and summary (R10). `lib/wrap/wrap-adopt.sh` (`_adopt_summary`, the batch loop, the interrupt stop), `tests/test-wrap-adopt.sh`. Acceptance: cases 23, 34 pass.
- [ ] T1d: test-header edits. `lib/wrap/wrap-adopt.sh` appended to every `# modules under test:` line (`tests/lib/wrap-stub.sh` and each `tests/test-wrap*.sh` header) so the section cache invalidates on it. The more-than-five-files rule for one task is waived here: each file takes one mechanical header line. Acceptance: every `tests/test-wrap*.sh`, `tests/test-adopt.sh` and `tests/test-proof-*.sh` shows no new failure against master.

### Phase 2: docs and proof

- [ ] T2: `commands/wrap.md` (one bullet beside the `start`/`land` bullets: what `adopt` composes, its refusals, its summary, its `resume: wrap land <wt>` line, and that `--apply` is operator-only: an agent runs the dry run and hands the `--apply` line to the operator), `commands/adopt.md` (one paragraph: several repos at once go through `bin/wrap adopt`), `docs/verification/adopt-land.md` (the test run with captured output, the negative control below, and one real dry run against two local repos). Acceptance: the proof passes `bash lib/gate/proof-ledger.sh check . <base> adopt-land`.

## After state

- [ ] `bin/wrap adopt <repo>` exists and is a dry run. (Today: `wrap: unknown verb 'adopt'`, exit 64.) Checkable on case 3's fixture (a clone with an untracked `AGENTS.md`): `bin/wrap adopt "$clone"; echo $?` prints a `refused:` line naming `?? AGENTS.md`, then `1`.
- [ ] A dry run over an adopted and an unadopted clean fixture repo (cases 2 and 1) prints `skip: already adopted` and `would adopt`, exit 0, and `git status`, `git branch` and `git worktree list` in both repos are unchanged.
- [ ] `--apply` on a clean unadopted fixture repo leaves origin's default branch holding the six adoption paths, the main checkout pulled, `adopt.sh --check` exit 0, no `chore/kit-adopt` locally or on origin, and one override line `| kit-adopt | OVERRIDE | written by wrap adopt --apply: adoption scaffold only...` for that repo.
- [ ] `bash tests/test-wrap-adopt.sh` passes and goes red on master (negative control below).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Every test plan row passes.
- [ ] No regression against master's baseline in every `tests/test-wrap*.sh`, `tests/test-adopt.sh`, and every `tests/test-proof-*.sh` (the proof-ledger suites).

## Test plan

All cases in `tests/test-wrap-adopt.sh`, on the wrap-stub harness: a bare remote, a clone as the main checkout, the gh stub on PATH, `KIT_LEDGER_DIR` and `KIT_CONFIG_OPERATOR` pinned to scratch. No case touches the network or a real repo.

| # | Case | Expect |
|---|---|---|
| 1 | clean unadopted clone, no `--apply` | `would adopt`; exit 0; no `.claude/worktrees/kit-adopt`, no `chore/kit-adopt` ref, no fetch (origin ref unchanged), gh stub log empty, override log absent |
| 2 | adopted clone (adoption committed and pushed) | `skip: already adopted`; exit 0; no other check output |
| 3 | untracked `AGENTS.md` in the clone, `--apply` | `refused:` naming `?? AGENTS.md`; exit 1; no worktree, no branch, gh log empty |
| 4 | modified tracked `CLAUDE.md`, `--apply` | `refused:` naming ` M CLAUDE.md` |
| 5 | untracked `WORKFLOW.md`, `.kit.toml`, `docs/verification/README.md`, `.claude/settings.json`, each in its own fixture; in the last, `.claude/` holds nothing else | each `refused:` naming that file path, never the collapsed `?? .claude/` |
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
| 17 | clean unadopted clone, `--apply`, gh stub opens #7 and merges | `opened PR #7`, `merged #7` streamed; the repo block's `result:` line reads `#7 adopted` (the summary table is case 23, T1c); exit 0; worktree and branch gone locally and on origin; clone's HEAD equals origin/main; `adopt.sh --check` exit 0; the merged commit subject equals `ADOPT_COMMIT_SUBJECT` |
| 18 | case 17's override log | exactly one line with the clone's repo id, `kit-adopt`, `OVERRIDE`, and `OVERRIDE_REASON` |
| 19 | `WRAP_ADOPT_SH` stub also writes `src/x.sh` | `failed: adoption wrote src/x.sh`; no commit on the branch; no override line; gh log has no create; worktree left and named |
| 20 | `WRAP_ADOPT_SH` stub writes nothing | `no change:` row; exit 1; no commit, no override |
| 21 | the clone's main branch carries one unpushed commit (not refused by preflight) | land merges #7, prints `PULL BLOCKED`; row `merged, not adopted on the main checkout: PULL BLOCKED: pull --ff-only refused ...`; exit 1 |
| 22 | drift guard: real `adopt.sh` on a fresh fixture, then `git add -A` and every `git diff --cached --name-only --no-renames -z` path; run once with `adopt.single_source` off and once on (a tracked `CLAUDE.md` in the fixture) | each path matches `ADOPT_PATHS`; the staged `.claude/settings.json` passes R6a |
| 23 | batch: [case-3 fixture, case-17 fixture, case-2 fixture] with `--apply` | runs in that order; summary rows in that order: `refused`, `#7 adopted`, `skip: already adopted`; exit 1 |
| 24 | no repo; unknown flag `--force` (and `--title`, now unknown); `--body-file` with no value; `--body-file` naming a missing file; `--body-file F` with two repos; a repo argument holding ` --apply` packed into one word | each exit 64, nothing written |
| 25 | `WRAP_ADOPT_SH` stub runs the real adopt, then adds a `PreToolUse` hook entry `{"type":"command","command":"bash /tmp/evil.sh"}`; variant (b): a kit-shaped command with an embedded newline, `"bash $HOME/.claude/dwarves-kit/hooks/x.sh\nbash /tmp/evil.sh"`; variant (c): a kit command with an extra key `"env"` | each `failed: adoption changed .claude/settings.json beyond kit hooks: PreToolUse <matcher> #<index>`, never the command text; no commit; no override line; gh log has no create; worktree left and named |
| 26 | `WRAP_ADOPT_SH` stub runs the real adopt, then sets `.permissions.allow` in `.claude/settings.json` | `failed: adoption changed .claude/settings.json beyond kit hooks: key permissions`; no commit, no override |
| 27 | case 17's fixture, gh stub refuses the merge (`gh pr merge` exits 1, PR not CONFLICTING) | row `failed: land exit 2: MERGE FAILED #7: exit 1; resume: wrap land <wt>`; exit 1; worktree and `chore/kit-adopt` kept; then `bin/wrap land <wt>` with the stub merging: `adopted PR #7`, `merged #7 (<sha>): tree verified`, and `adopt.sh --check` exit 0 |
| 28 | case 17 with operator overlay `adopt.single_source = true` and a tracked `CLAUDE.md` | the staged list holds `AGENTS.md` and `CLAUDE.md` (no rename line); row `#7  adopted`; exit 0 |
| 29 | case 17, gh stub reports `MERGED` with a merge commit whose tree differs from the branch tip | land exit 3; row `failed: land exit 3: merged #7 (<sha>): TREE MISMATCH, ...; worktree left at <wt>`; no `resume:`; exit 1 |
| 30 | a clean clone holding `chore/kit-adopt` one commit ahead of `origin/main`, checked out at `.claude/worktrees/kit-adopt` (the state case 27 leaves), gh stub lists no merged PR for the head, dry run | `refused:` with `chore/kit-adopt exists locally`, `worktree path exists`, and `resume: wrap land <wt>`; exit 1; nothing written |
| 31 | case 29's leftover: worktree, `chore/kit-adopt` locally and on origin, gh stub lists merged PR #7 for head `chore/kit-adopt`; dry run | `refused:` with `exists locally`, `on origin`, `worktree path exists`, and `merged #7; read <wt>`; no `resume:` anywhere in the output; exit 1; nothing written |
| 32 | clean unadopted clone whose tracked `.gitignore` holds `.claude/`; dry run, then `--apply` | both: `refused: .claude/settings.json is gitignored` and `refused: .claude/output-styles/ is gitignored`; exit 1; no worktree, no branch, gh log empty |
| 33 | case 17, plus a target-repo `pre-commit` hook that writes and stages `src/hooked.txt` | commit lands; `failed: the commit differs from the guarded set: src/hooked.txt`; no override line; gh log has no push or create; no `resume:`; worktree left and named |
| 34 | batch [case-17 fixture A, case-17 fixture B] with `--apply`; the gh stub makes land exit 130 on A | A's row `interrupted: land exit 130; read <wt>`; B's row `not run` and B has no worktree or branch; summary lists both; exit 1 |
| 35 | case 17, gh stub reports #7 CONFLICTING and the merge cycle ends on land's `run wrap merge --apply --pr 7` line | row quotes that `wrap merge` line; no `resume:`; exit 1 |
| 36 | case 17 with `output.style = "x"` and the stub also writing `.claude/output-styles/y.md` | `failed: adoption wrote .claude/output-styles/y.md, outside the scaffold set`; no commit, no override |

## Verification

```
bash tests/test-wrap-adopt.sh
for t in tests/test-wrap*.sh tests/test-adopt.sh tests/test-proof-*.sh; do bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done
fx="$(mktemp -d)"
for r in adopted collide plain; do git init -q -b main "$fx/$r.src"; git -C "$fx/$r.src" commit -q --allow-empty -m base; done
bash lib/adopt.sh "$fx/adopted.src" >/dev/null && git -C "$fx/adopted.src" add -A && git -C "$fx/adopted.src" commit -qm adopt
for r in adopted collide plain; do git clone -q --bare "$fx/$r.src" "$fx/$r.git"; git clone -q "$fx/$r.git" "$fx/$r"; done
echo x > "$fx/collide/AGENTS.md"
bin/wrap adopt "$fx/adopted" "$fx/collide" "$fx/plain"; echo "exit=$?"
```

The second line prints no `FAIL` line that master does not also print. The fixtures are built by bare clones, never a push, so the ship-gate hook has nothing to judge. The last line is a dry run over three local fixtures: expect `skip: already adopted`, `refused: ?? AGENTS.md ...`, `would adopt`, `exit=1`, and no new branch or worktree in any of them. A dry run over live repos (for example `~/workspace/dwarvesf/spacedown`, adopted) is observed-only: live repos change state, so it is evidence, never the contract.

## Edge Cases

1. Dirt in the main checkout outside `ADOPT_PATHS` (an edited `src/app.ts`): not refused. The fast-forward only rewrites files the adoption touches, so the pull still runs.
2. A tracked, clean `AGENTS.md` or `CLAUDE.md` in the main checkout: not a collision. `adopt.sh` leaves a repo's own `AGENTS.md` alone and appends its block to `CLAUDE.md` in the worktree; the pull applies that change cleanly.
3. The main checkout is behind origin and origin already carries the adoption: R3a reads the stale checkout as not adopted, adopt in the worktree writes nothing, and R6's row reads `no change: origin/<def> already carries the adoption; worktree left at <wt>`, with no `resume:`. The fix is `git pull --ff-only` in the main checkout.
4. The target repo's own pre-commit or commit-msg hook refuses the commit: row `failed: commit: <last stderr line>; worktree left at <wt>`. Never `--no-verify`.
5. The repo's workflows trigger on `pull_request` and a check fails: land leaves the PR open (its own `MERGE REFUSED` line); row `failed: land exit 2: MERGE REFUSED #<n>: checks failed: ...; resume: wrap land <wt>`; PR column `#<n>`. Fix the checks, then run the resume line.
6. The same repo named twice: the second run reads it as adopted (or as holding `chore/kit-adopt` if the first failed) and skips or refuses by name.
7. Two `wrap adopt` runs on one repo at once: the second hits `cmd_start`'s existing-branch or worktree-path refusal; R12 keeps the first run's worktree untouched.
8. Case-insensitive filesystems: an untracked `agents.md` shows in `git status` under its own case, which R3c does not match. Out of scope; adopt and git agree on case on every repo seen so far.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Merged upstream, not adopted locally | R8 row `merged, not adopted on the main checkout: <PULL BLOCKED line>` | Resolve the named block in the main checkout, then `git pull --ff-only`; re-run `wrap adopt <repo>` dry to confirm `skip: already adopted` |
| Override written for an unmerged branch | override line exists, row is `failed: land exit <rc>: ...; resume: wrap land <wt>` | Run the printed `wrap land <wt>`: it adopts the open PR (or pushes and opens one) and merges. The override is scoped to repo and `kit-adopt`, excuses only the adoption's own non-source diff, and is already in place for the resume. A `wrap adopt` re-run refuses (R3f) and prints the same `resume:` line (case 30) |
| `adopt.sh` grows a new write outside `ADOPT_PATHS` | R6 `failed: adoption wrote <path>` on every repo; test case 22 red | Add the path to `ADOPT_PATHS` in the same change that adds the write |
| `adopt.sh` grows a settings write beyond kit hooks and `outputStyle` | R6a `failed: adoption changed .claude/settings.json beyond kit hooks` on every repo; test case 22 red | Widen R6a in the same change that adds the write, with its own security read |
| gh rate limit mid-batch | land's own `PR REFUSED` or `MERGE FAILED` line on that repo's row, ending `resume: wrap land <wt>` | Later repos keep running and fail the same way; after the limit resets, run each printed `wrap land <wt>`. A `wrap adopt` re-run refuses those repos (R3f) and repeats the `resume:` line |
| Failure before or at the recheck (adopt, guard, settings guard, commit hook, R6b) | row `failed: ...; worktree left at <wt>` with no `resume:` | Read the worktree. Fix and commit by hand, then `wrap land <wt>`; or remove the worktree and branch by hand and re-run. `wrap apply --worktrees` skips both shapes (R12) |
| Merged, tree not verified (land exit 3) | row `failed: land exit 3: merged #<n> (<sha>): TREE MISMATCH, ...` (or `tree <verdict>`); land returned before `_land_tidy`, so the worktree, the local branch, and `origin/chore/kit-adopt` remain; a re-run's R3f prints `merged #<n>; read <wt>` (case 31) | Never resume: the PR is merged. Compare the merge commit's tree with the branch tip, fix the default branch by hand if it is wrong, then pull the main checkout and remove the worktree, the local branch, and the origin branch by hand. `adopt.sh --check <repo>` exit 0 confirms |
| Interrupt during land (exit 130 or 143) | row `interrupted: land exit <rc>; read <wt>`; later rows `not run` | Read the worktree and land's last lines; a re-run's R3f says `resume:` or `merged #<n>` from the PR state |

## Out of Scope

- `--under <root>`: adoption is a per-repo choice, and a root sweep would adopt repos the operator never picked.
- Refusing a main checkout whose default branch carries unpushed commits: land still merges; the row names the `PULL BLOCKED` line (case 21).
- Removing a worktree after a failure (R12): the verb names the path and the resume or the read; it never removes one.
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
- DEC-E: the override guard is the path allowlist (R6) plus the settings guard (R6a, DEC-I), not `proof-ledger.sh classify`. `classify` reads a real adoption diff as `behavioral` because of `.claude/settings.json` (Grounding G2), so "inert only" would refuse every adoption. The allowlist proves "scaffold only" by name, R6a proves the one executable-bearing file holds only kit hooks, and `check`'s source-remainder rule stays as the second wall.
- DEC-F: the override slug is `kit-adopt` (R2). The hand loop's `chore-kit-adopt` never matched the ship-gate's lookup (Grounding G3).
- DEC-G: preflight reports every reason it finds, not the first, so one dry run lists the whole fix.
- DEC-H (validation round 1, design and assumptions lenses, critical): the path guard reads the staged list, `git add -A` then `git diff --cached --name-only --no-renames -z`, and R3c reads `git status --porcelain --untracked-files=all --no-renames`. Plain porcelain prints `?? .claude/` for a new directory and `R  CLAUDE.md -> AGENTS.md` for a single-source fold (both reproduced in a scratch repo), so R6 failed nearly every real adoption. The commit now follows the guard, not the `add`. Cases 5, 22, 28 pin it.
- DEC-I (validation round 1, security lens, critical): R6a checks the content of `.claude/settings.json`, not just its name. Every added hook command must match `KIT_HOOK_RE`, and nothing else changes except `outputStyle`. The lens's proposed pattern `^\$HOME/\.claude/dwarves-kit/hooks/[A-Za-z0-9_-]+\.sh$` would refuse every real adoption: the kit's `settings.json` ships `bash $HOME/.claude/dwarves-kit/hooks/anchor-root.sh $HOME/.claude/dwarves-kit/hooks/<name>.sh` and `bash $HOME/.claude/dwarves-kit/hooks/secrets-guard.sh`, and one carries a flag (`harvest.sh --lab-log`). `KIT_HOOK_RE` keeps the intent and matches those two shapes. `outputStyle` stays allowed because `adopt.sh` step 6b sets it whenever `output.style` resolves. Cases 25, 26 pin it. The override reason now names its writer and states only what R6 and R6a prove.
- DEC-J (validation round 1, design-record lens): the verb writes the override, which ADR 0024 calls "operator-authored". It stays inside that ADR because the operator authors the run: `--apply` is operator-only (R1), the reason is fixed text reviewed here (Interfaces), and it opens `written by wrap adopt --apply` so an audit tells it apart from a hand override. ADR 0024's own threat model already accepts that a writer with shell access can log an override; the guarantee is the audit line, which this keeps. Operator-only `--apply` is policy, not a mechanism: nothing in the verb can tell an operator's shell from an agent's, and the spec claims no more than that (re-validation, design-record lens).
- DEC-K (validation round 1, failure-modes lens, critical): a failure after the commit and before a counted merge prints `resume: wrap land <wt>` (R7, R8, R12), and R3f repeats it on a re-run. The old R12 pointed at `wrap apply --worktrees`, which skips an unmerged branch, and R3f refused a re-run, so a pre-merge failure had no path forward. Cases 27, 30 pin it.
- DEC-L (validation round 1, scope lens, critical): T1 split into T1a (preflight, dry run), T1b (apply, guards, override, land parse), T1c (batch, summary), T1d (test headers), each with its own cases. `--apply` is operator-only, stated in R1 and in T2's `commands/wrap.md` bullet.
- DEC-M (folded with DEC-K, from the design and failure-modes warnings): R8 reads land's exit code first and counts a merge only on `merged #<n> (<sha>): tree verified`; exit 3 is the post-merge tree failure, with no resume. R9 captures land as `2>&1 | tee` and reads `PIPESTATUS[0]`. DEC-K needs both: the old "printed `merged #<n>`" rule also matched land's `TREE MISMATCH` line, which would print a resume after a merge, and a bare `$?` after `tee` is `tee`'s exit code. Case 29 pins exit 3.
- DEC-N (validation round 1, design-record lens): the design record links ADR 0013, 0024, 0025, names the G4 ship-gate gap in Boundaries, and the state machine now uses the R5 to R8 row texts.
- DEC-O (re-validation, failure-modes lens, critical): R3f reads the PR state before it prints `resume:`. A land exit 3 merges the PR and then returns before `_land_tidy` (the `MISMATCH*)` and `*)` arms after `_tree_verify` each `return 3`), so the worktree, branch, and origin branch all survive and R3f's old local test printed `resume:` over a merged PR. R3f now asks `gh pr list --head chore/kit-adopt --state merged` and prints `merged #<n>; read <wt>` instead. Case 31 pins it; the Failure modes table gains the exit-3 row.
- DEC-P (re-validation, assumptions lens, critical): new R3k refuses any `ADOPT_PATHS` entry the target repo ignores, read with `git check-ignore -q --no-index`. A scratch repo confirmed the flag semantics: with `AGENTS.md` both tracked and ignored, plain `check-ignore` exits 1 and `--no-index` exits 0; the directory entry `.claude/output-styles/` under an ignored `.claude/` exits 0. An ignored path drops out of `git add -A`, so the adoption would land without it. Case 32 pins it.
- DEC-Q (re-validation, lead decisions): the override stays before land (R7), so a hand `wrap land <wt>` resume never runs without it. `--title` is dropped: land's default already reads the one commit subject. `--body-file` with more than one repo is usage (exit 64), and `resume:` repeats `--body-file F`, which must outlive the run.
- DEC-R (re-validation, security lens): R6a names its engine, `jq` `test()` with `\A` and `\z` anchors. In `jq`, `$` matches before a final newline and `\z` does not (checked in a scratch run). A kit entry is `type == "command"` with keys from {`type`, `command`, `timeout`, `async`}, the two key sets the shipped `settings.json` uses. The base side drops every `dwarves-kit/hooks/` entry, mirroring `adopt.sh`'s `contains("dwarves-kit/hooks/") | not` strip, and an emptied `hooks` object is dropped before the compare. The failure row names event, matcher, and index, never the command text. R6 narrows `.claude/output-styles/` to the one staged style file. Cases 25 (three variants), 36 pin it.
- DEC-S (re-validation, security and failure-modes lenses): R6b re-runs the guards on the committed tree, with a clean-status check, before the override. A target repo's commit hook runs after the staged guard and can add or rewrite paths. A miss stops with no override, no land, and no `resume:`. Case 33 pins it.
- DEC-T (re-validation, failure-modes lens): an interrupt in land (exit 130 or 143) stops the batch, and the rest read `not run`; `tee -i` keeps the capture alive through the SIGINT. When land's own line names `wrap merge`, the row quotes it and adds no `resume:`, because land's CONFLICTING-cycle exits leave a merge commit on origin. Cases 34, 35 pin them.
- DEC-U (re-validation, scope lens): each task now leaves the suite green on its own. R11 moved to T1a with its usage cases, case 22 moved to T1b (it needs R6a), and case 17 asserts the per-repo `result:` line while the summary table stays in T1c. T1d waives the more-than-five-files rule: one mechanical header line per file. The global AC and Verification now run every `tests/test-wrap*.sh`, `tests/test-adopt.sh`, and `tests/test-proof-*.sh`. Verification and the After state point at fixtures; a live repo is observed-only.

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
