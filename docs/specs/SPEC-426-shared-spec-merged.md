# Spec: one active-spec lookup and one merged check

Generated: 2026-11-25
Status: DRAFT
Lane: full
Depth: research (repo: how the hooks, wrap and wt.sh each answer "which spec is active" and "has this branch landed", read at file:line, and where the answers differ) + blind-spot (failure: a shared lookup that filters on `Status:` loses the spec at the very push it gates, because `/kit:ship` flips the spec to SHIPPED before the push)
Type: spec-feature
Board: ID-938
File: `docs/specs/SPEC-426-shared-spec-merged.md`
References: `lib/spec/spec-find.sh` (the model: a sourced resolver, no verb, never sets shell options; `spec_for_slug` is already the one slug-to-file pick); `lib/spec/spec-status.sh live` (the one reader of `Status:`); `lib/wrap/wrap-common.sh` `_merge_ladder` (the model for the merged grammar `SAFE|LEAVE <code> <detail>`, already shared by scan, apply and land); `tests/test-spec-states.sh` (the `spec-state-ok:` per-line marker, the model for the lint markers below); `lib/gate/default-branch-warn.sh` (a lib/gate file that wrap already sources, the precedent for where the merged function lives)

## Problem

Two questions are answered by more than one piece of code, and the answers disagree on real inputs.

**Which spec is active.** Branch `feat/alpha`, specs `SPEC-010-alpha` (SHIPPED), `SPEC-020-beta` (DRAFT), `SPEC-030-gamma` (DRAFT), and a co-located `tools/x/docs/specs/SPEC-005-delta`:

| Caller | Answer for branch feat/alpha |
|---|---|
| `hooks/ship-gate.sh` (spec_for_slug) | `SPEC-010-alpha`, by name, SHIPPED or not |
| `hooks/pre-compact-backup.sh`, `hooks/post-compact-reinject.sh` | `SPEC-030-gamma`, the highest open number, branch ignored |
| `hooks/context-readiness.sh` | `spec:ambiguous(SPEC-020,SPEC-030)`, no pick |
| `hooks/spec-drift-guard.sh` | the union of beta and gamma |
| `lib/spec/spec-index.sh` | all four, plus any copy under a dot-dir worktree |

A compaction snapshot can therefore brief the model on a spec that is not the branch's spec while the session-start hook calls the same state ambiguous.

**Whether a branch is merged.** Thirteen sites decide it (table in `## Contract`). Three of them guard a deletion with three different meanings: `wrap apply` (ladder: ancestor, absorbed content, or a merged PR at the exact tip), `wrap land` (the PR it just merged is MERGED and its tree verifies), and `lib/goal/wt.sh close` (the first PR gh lists for the head says MERGED, no tip compared). On a branch that took one more commit after its PR merged, the ladder says `LEAVE tip` and `wt.sh close` removes the worktree and runs `git branch -D`, losing the commit (reproduced in `## Grounding`).

Row contract: give each question one function, make every caller use it, and add a test that fails when a caller keeps its own copy.

## Terms

none. `spec_active` and `branch_merged` are function names, not domain terms.

## Solution

### Approaches considered

1. **One function per question, a mode flag for the callers that ask a looser version.** `spec_active` takes `--live` for the session hooks; `branch_merged` takes `--need pr` for the callers that today refuse an ancestor-only branch. Tradeoff: two flags to document, but every caller's policy is one visible argument instead of a private copy of the lookup.
2. **Only move today's most-shared function** (`_merge_ladder` to lib, `spec_for_slug` untouched) and leave the outliers alone. Tradeoff: smallest diff, and exactly what the row calls out as not enough: the compact hooks, the readiness hook, `wt.sh` and the origin sweep keep their copies.
3. **Make every caller use the strictest meaning.** Tradeoff: one meaning, but `wrap apply` stops deleting plain-merged branches and the compaction hooks stop finding a header-less spec; that is a behavior change the row does not ask for.

### Chosen approach + why

Approach 1. The two questions already have a shared core (`spec_for_slug`, `_merge_ladder`); the work is to promote the ladder out of `lib/wrap`, add the one missing function for the session-side pick, and move the outliers onto them. The policy differences that are real (enforcement is status-blind; remote deletes need a PR) become arguments, never loosened for any caller.

### Extensibility & boundaries

- Load-bearing dimension: the number of callers per question (seven pick sites, thirteen merged sites today). The lint (`## Test plan` C20 to C24) makes a new caller either call the function or carry a pinned, reasoned marker, so the count of private copies cannot grow silently.
- Units: `spec-find.sh` stays the file enumeration and slug pick; `spec-status.sh` stays the `Status:` reader; `spec-active.sh` composes them and adds no parsing of its own. `branch-merged.sh` owns every git and gh read that answers "has this tip landed"; callers own what they delete and their extra guards (open-PR protection, lease, dirty tree).

## Picture

```
 ACTIVE SPEC                                          MERGED
 ship-gate -----------+                               wrap scan --------+
 validate-round ------+--> spec_active                wrap apply (x3) ---+
 proof-ledger --------+    (--slug, name only)        wrap land ---------+--> branch_merged
 mega-merge, pitch ---+          |                   wt.sh close -------+    (default: any rung)
                                 v                   origin sweep -------+--- --need pr
 pre-compact ----+          spec_for_slug            wrap adopt --------+--- --need pr
 post-compact ---+--> spec_active --live             wrap carry: patch-id stays out
 context-readiness+   (root only, no find)                  |
 spec-drift-guard + --set                                   v
 spec-index (list) --> spec_files               ancestor | absorbed | merged PR at exact tip

 start.md / next.md prose --> `spec-active.sh --live`
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Diagram

`## Picture` above is the module view. The state flow of `spec_active --live`:

```
 slug from branch  ->  name pick (root docs/specs, exact slug)  -- live? --> kind=name
                              | none or not live
                              v
                    live set (root docs/specs, one spec-status pass)
                      0 -> exit 1
                      1 -> kind=live
                      n -> branch token match: 1 -> kind=branch ; else kind=ambiguous (all, exit 2)
```

### ADR link(s)

None needed: no irreversible choice. Every migration is a call-site swap behind a test; the old code is deleted in the same task, and a revert restores it.

### Boundaries & failure modes

Out of bounds: `Status:` grammar (spec-status.sh), spec numbering (spec-next.sh), the floor sizing in `lib/classify/lane-classify.sh` and `lib/gate/ship-rules.sh`. Failure classes: `## Failure modes`.

## Contract

### spec_active (new file `lib/spec/spec-active.sh`, sourced like `spec-find.sh`; also runnable as a CLI)

```
spec_active [--live | --set] (--slug S | --branch B) <root>
```

- `--branch B` derives the slug as `${B#*/}` (the rule `hooks/ship-gate.sh` and `gate-ledger.sh rid` use). `--slug S` is the slug as given (validate-round, mega-merge, proof-ledger, pitch pass the rid).
- Default mode (no flag, enforcement): the name pick only, `spec_for_slug <root> <slug>`: root `docs/specs` first, then co-located `*/docs/specs`; status-blind. Output is byte-identical to today's `spec_for_slug`, so every enforcement caller keeps its pick.
- `--live` (session hooks): root `docs/specs` only, no `find`. The name pick counts only if its `Status:` is open. Then: one open spec, use it; several, the one whose slug tokens appear as whole tokens in the branch (split on `/ _ . -`, today's `context-readiness.sh` rule); else ambiguous.
- `--set`: every open spec at root `docs/specs`, one per line (the drift guard's union).
- stdout: one line per spec, `<kind><TAB><path>`; kind is `name`, `live`, `branch`, or `ambiguous` (one line per candidate). An enforcement caller reads only a `name` line, so a looser step can never feed a gate.
- exit: 0 exactly one resolved line (or `--set` with at least one); 1 none; 2 ambiguous; 64 usage. A caller that cannot read the file (stale install) treats a missing function as "none".
- Never sets shell options; never writes; bash 3.2; the paths it prints are `<root>/<rel>`.

### branch_merged (new file `lib/gate/branch-merged.sh`, sourced)

```
branch_merged [--need any|pr] [--tip SHA] [--prs-json FILE] <repo> <default> <ghstate> <branch>
```

- stdout: ONE line, the grammar `_merge_ladder` prints today, byte-identical: `SAFE ancestor|absorbed|squash <phrase>`, `LEAVE tip <sha>`, `LEAVE base <name>`, `LEAVE none <phrase>`, `LEAVE nogh <note>`. A caller branches on the first two words and never on the phrase.
- Default (`--need any`): rungs in order, ancestor of `refs/remotes/origin/<default>`, absorbed content, then the gh rung (a same-repo merged PR into `<default>` whose head is the exact tip).
- `--need pr`: skip ancestor and absorbed; only the gh rung can say SAFE. For callers that today refuse a branch with no merged PR.
- `--tip SHA`: judge this commit instead of `refs/heads/<branch>` (a caller that read and guarded a tip, or a remote-only branch).
- `--prs-json FILE`: use this merged-PR list (`gh pr list --state merged --json headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository`) instead of one gh call; the origin sweep reads once for all branches. Rows are filtered to `headRefName == <branch>`, `isCrossRepository != true`, `baseRefName == <default>`.
- exit: always 0 for a verdict (callers read stdout); 64 on usage error with empty stdout, which every caller reads as LEAVE.
- Moves with it, unchanged: `_absorbed`, `_squash_verdict`, `_gh_state`, `_gh_note`, `_origin_url`. `_squash_json` moves widened (it also requests `number`, `headRefName` and `isCrossRepository`), and `_squash_rows` is new: it keeps a merged-PR row only when `isCrossRepository` is exactly false and `headRefName` names the branch, so a field gh did not send never reads as the permissive value. `lib/wrap/wrap-common.sh` sources the file (precedent: it already sources `lib/gate/default-branch-warn.sh`); `lib/goal/wt.sh` sources `$LIB/gate/branch-merged.sh`.

### What is deliberately not a merged check (excluded by name, not by regex luck)

| Class | Sites | Why it is a different question |
|---|---|---|
| Post-merge confirmation: "is the PR I just merged MERGED" | `wrap-land.sh:1014`, `wrap-merge.sh:1274`, `lib/config/merge-command.sh:271`, `lib/goal/mega-merge.sh:555`, `lib/queue/orchestrate.sh:2790` | Reads one PR number the script itself just merged; no branch tip is judged |
| Merge commit on the default branch | `wrap-land.sh:31` (`_tree_verify`) | Verifies gh's merge commit, not a branch |
| Up to date: `is-ancestor origin/<def> HEAD` | `wrap-rebase.sh:247,269`, `wrap-common.sh:494,750`, `wrap-merge.sh:543,771,819`, `lib/gate/premerge.sh:46`, `lib/goal/stack-merge.sh:51,65` | Opposite direction: does the branch contain the base |
| Reports | `lib/mega/mega.sh:240,248`, `lib/mega/mega-review.py` | Print a state; delete nothing |

## Behavior changes (every place two callers disagree today) and the chosen answer

Merged checks, repro in `## Grounding`. Strictest caller that guards a deletion: `_apply_origin_branches` (`wrap-apply.sh:883`) for remote refs (exact origin tip, same-repo merged PR, no open PR on the branch as head or base, leased delete) and `_land_tidy` for the one PR land itself just merged (head equals the pushed tip, tree verified). The shared PR rung is the origin sweep's rule plus a base check, so it is never looser than either; the ancestor and absorbed rungs are what `wrap apply` accepts today, and no other caller gets them unless it already had them.

| # | Disagreement | Today | Chosen shared answer |
|---|---|---|---|
| DM1 | A merged PR exists, the branch has a later unpushed commit: `wt.sh close` vs ladder | `wt.sh` removes the worktree and `branch -D`s the branch, losing the commit; the ladder says `LEAVE tip` | `wt.sh close` calls `branch_merged --need pr`; refuses unless the exact tip is a merged PR head. Stricter, fail closed |
| DM2 | The PR merged into a non-default base: origin sweep vs ladder | the sweep deletes the origin branch (its jq has no base check); the ladder says `LEAVE base` | the sweep goes through `branch_merged --need pr --prs-json`; base must equal the default. Stricter |
| DM3 | Branch is an ancestor of origin/default, no PR: apply vs origin sweep vs `wt.sh` | apply deletes (SAFE ancestor); sweep and `wt.sh` refuse | no change: the sweep and `wt.sh` pass `--need pr`, so the difference is an argument |
| DM4 | Stray commits whose patch landed, with later edits to the same file: carry patch-id vs ladder | carry says landed (`reset --keep`); the ladder says `LEAVE none` | stays out of the shared function, as a named `merged-ok` exclusion: it answers "did this commit land", not "is this branch merged"; adding a looser rung to the shared function would loosen every deleting caller |
| DM5 | A merged `<branch>-squash` PR at any tip: carry sibling probe | counts as landed with no tip compared (`wrap-carry.sh:103`) | stays, as a named `merged-ok` exclusion: it only skips opening a duplicate PR; the reset after it is gated by a separate "origin holds HEAD" check |
| DM6 | Cross-repo PRs: ladder vs origin sweep | the sweep ignores a fork PR; the ladder counts it | both ignore it (`isCrossRepository != true`). Stricter, no known real input |
| DM8 | Default mode, a merged PR that exists only from a fork, or a row missing `isCrossRepository` or `headRefName` | the old ladder counted it (a fork row at the exact tip was SAFE squash; `LEAVE tip`/`LEAVE base` named it otherwise) | stricter: such rows never count, so the answer is `LEAVE none`. No known real input: gh sends both fields |
| DM9 | Two PRs from one head, one merged and a newer one open: `wt.sh close` | first PR's state decided; with the first PR OPEN or CLOSED it refused | refuse whenever an OPEN PR names the head or the open list cannot be read; the origin delete is leased to the judged tip, so a branch that moved on stays |
| DM10 | The origin sweep's open-PR protection through a pipe | a protect list past the pipe buffer let a base branch go | matched in the shell with a `case`; an open row that names no head or base skips the sweep |
| DM11 | `wt.sh close`: GitHub moved the PR head past the local tip (Update branch, a web suggestion), then the PR merged; local is still at the old tip | closed (the PR was MERGED) | refuses with `LEAVE tip <PR head>` and one more line, `Fix: git -C <worktree> pull --ff-only, then close again` (`Fix: in that worktree run ...` when the path has a character outside `A-Za-z0-9/._-`). A deliberate change: exact tip stays the rule |
| DM12 | `wt.sh close`: an open fork PR has the same head name (`gh --head` matches by name only) | closed | refuses (any open PR naming the head keeps the branch). A deliberate change |
| DM13 | `wt.sh close`: the origin ref moved past the judged tip, or cannot be read | removed the worktree and the local branch, the delete of the remote was unleased | the remote ref is read once before any removal and must be gone or at the judged tip, else `LEAVE remote <sha>` and nothing is removed; the remote delete stays leased. Uncommitted edits in the worktree are still discarded on a successful close, as on master |
| DM7 | Adopt accepts the merged PR head equal to the worktree tip or origin's tracking tip | two tips | adopt calls `branch_merged --need pr --tip` once per tip |

Active spec:

| # | Disagreement | Chosen shared answer |
|---|---|---|
| DA1 | Enforcement is status-blind and slug-exact; session hooks filter on status | Both stay, as the two modes. Default mode never filters on `Status:` (ship flips SHIPPED before the push; a filter would drop the spec at the gate) |
| DA2 | Compaction hooks pick the highest open number and ignore the branch; readiness reports ambiguous | `--live` for all of them. Compaction hooks change from a guess to the branch-aware pick, or `Spec: ambiguous (SPEC-020, SPEC-030)`. Matches `commands/start.md` ("never guess") |
| DA3 | A spec with no `Status:` is open for compaction and drift, closed for readiness | open everywhere, readiness included; no argument to change it. Readiness changes only when a header-less spec exists, the branch matches no spec by name, and several specs are open |
| DA4 | Hooks read `docs/specs` relative to the cwd | callers pass `git rev-parse --show-toplevel` (else `pwd`). Differs only when the hook runs from a subdirectory (today: no spec found) |
| DA5 | `spec-index.sh` enumerates with its own unpruned `find` | enumerates through `spec_files`; dot-dir copies (`.claude/worktrees/*/docs/specs`) disappear. It lists, it does not pick; the row's wording is corrected in `lib/spec/README.md` |
| DA6 | Root-only (session hooks, prose rule) vs co-located (ship-gate) | unchanged by mode: name mode searches both, `--live` and `--set` root only (`commands/start.md` names root as the sole active-spec home) |
| DA7 | Five stale-install fallback stubs of `spec_for_slug` | kept, allowlisted with a pinned marker (`gate-ledger.sh`, `proof-ledger.sh`, `spec-next.sh`, `pitch.sh`, `ship-gate.sh:700`). They are the fail-safe for a partial update and they already share the pick; removing them is out of scope |
| DA8 | SessionStart blocks on this path | `--live` runs no `find`, one `spec-status.sh live` pass; AC9 pins both |

## Technical Design

### Interfaces (I/O contract)

- Inputs: `Status:` through `spec-status.sh`; file lists through `spec_files`; gh through `gh pr list` (`--repo <origin url>`), git through full refs only (`refs/remotes/origin/<def>`, `refs/heads/<b>`, never a bare name, so a tag cannot stand in).
- Outputs: the two stdout grammars above; no file written, no state.
- Invariants: a SAFE verdict is never produced by a rung the caller excluded; enforcement callers read only `name`; a gh failure is `LEAVE nogh`, never SAFE; an unreadable or unparseable PR list is `LEAVE none`.

### Caller migration list

| Task | Caller (file, today's lines) | Becomes |
|---|---|---|
| T4 | `hooks/ship-gate.sh` 692-701 (anchor: `# Resolve the spec for this slug; fail open if there is no spec-driven run.`) | `spec_active --slug "$SLUG" "$ROOT"`; the stale-install glob fallback keeps a `spec-active-ok:` marker |
| T5 | `hooks/pre-compact-backup.sh` 46-60, `hooks/post-compact-reinject.sh` 28-36 | `spec_active --live --branch "$(git branch --show-current)"` |
| T6 | `hooks/context-readiness.sh` 48-93 | same call; the token loop and `spec:ambiguous` text read the function's `ambiguous` lines |
| T7 | `hooks/spec-drift-guard.sh` 30-45; `lib/spec/spec-index.sh` 67 | `--set`; `spec_files` |
| T3 | `lib/wrap/wrap-scan.sh:43`, `wrap-apply.sh:211,290,726`, `wrap-land.sh:674` | `branch_merged` (rename; grammar identical) |
| T8 | `lib/goal/wt.sh:49` | `branch_merged --need pr` |
| T9 | `lib/wrap/wrap-apply.sh:883-947` | per-branch `branch_merged --need pr --tip <origin tip> --prs-json`; open-PR protection, lease and chunking stay |
| T10 | `lib/wrap/wrap-carry.sh:328-330` (patch-id); `lib/wrap/wrap-adopt.sh:305-315` | stays, with a `merged-ok` marker and reason; `branch_merged --need pr --tip` x2 |
| T12 | `commands/start.md:19`, `commands/next.md:11` and the commands that say "resolve the way /kit:next does" | the same rule, now stated as `bash lib/spec/spec-active.sh --live --branch <b>` |

Pinned `merged-ok` exclusions after the build: `wrap-merge.sh` 664, 665, 668, 674 (stacked-parent detection), `wrap-carry.sh:104` (sibling probe), `wrap-carry.sh` 328 and 330 (patch-id: did this commit land),  `wrap-apply.sh` 351, 721 (`git cherry`, archive-first: nothing is deleted on that count alone). Pinned `spec-active-ok` markers: the five stubs above, `spec-next.sh:105` (numbering scan of other worktrees), `lib/registry/feature-registry.sh` 205 and 428 (the generator over the kit's own specs), `lib/lint/scattered-ids.sh:69` (a tracked-file listing), `lib/system-design/doc-figures:139`.

## Task Breakdown

Order: characterization first, then the two functions, then one caller per task, then the lint and docs.

### Phase 1: pin today
- [ ] TASK-1: `tests/test-active-spec-pick.sh`: the fixture repo of `## Problem` (branch feat/alpha, three root specs, one co-located, one dot-dir copy); run the REAL hooks and `spec_for_slug`, `spec-index.sh`, and record each answer in the table above. Rows marked `known-gap` pin today's disagreement and flip in the task named in their label. AC: green on master before any code change.
- [ ] TASK-2: `tests/test-branch-merged-callers.sh`: scratch repo plus a gh stub (`tests/lib/wrap-stub.sh` harness): `wt.sh close` refuses a PR-less branch and closes an exact-tip merged PR; `wt.sh close` with a later commit (`known-gap`, flips in TASK-8); origin sweep with a non-default base (`known-gap`, flips in TASK-9); carry patch-id landed with a later edit; adopt with the origin tracking tip. `tests/test-wrap-ladder.sh` already pins the ladder grammar and stays the grammar oracle. AC: green on master.

### Phase 2: the functions
- [ ] TASK-3: `lib/gate/branch-merged.sh`: move `_merge_ladder` (as `branch_merged`), `_absorbed`, `_squash_json`, `_squash_verdict`, `_gh_state`, `_gh_note` out of `wrap-common.sh` and `wrap-apply.sh` with no logic change; delete the originals; migrate scan, apply (3 sites) and land; update `tests/lib/wrap-stub.sh`, `test-wrap-ladder.sh`, `test-wrap-apply.sh`, `test-wrap-land.sh` to the new name. AC: `test-wrap-ladder.sh` output unchanged line for line.
- [ ] TASK-3b: add `--need`, `--tip`, `--prs-json` with unit cases (C10 to C15). AC: default-mode output unchanged.
- [ ] TASK-4a: `lib/spec/spec-active.sh` with unit cases (C1 to C9) and the CLI form. No caller yet.

### Phase 3: one caller per task
- [ ] TASK-4: ship-gate (`hooks/ship-gate.sh` 692-701), then `bash lib/codex/repin.sh` (`hooks/codex-hooks.json` pins this hook's hash). AC: `tests/test-spec-find.sh` and `tests/test-ship-gate-review-verdict.sh` unchanged; the C17 row stays on `name`.
- [ ] TASK-5: pre-compact-backup and post-compact-reinject (DA2, DA4 rows flip).
- [ ] TASK-6: context-readiness (DA3 row flips).
- [ ] TASK-7: spec-drift-guard (`--set`) and spec-index (`spec_files`; DA5 row flips).
- [ ] TASK-8: `wt.sh close` (DM1 flips).
- [ ] TASK-9: origin sweep (DM2 flips).
- [ ] TASK-10: wrap-adopt migration; wrap-carry keeps its patch-id check with a `merged-ok` marker and reason.

### Phase 4: lock it
- [ ] TASK-11: `tests/test-shared-lookups.sh`, the structural lint (C20 to C24) and its negative control through `lib/gate/negctl.sh`.
- [ ] TASK-12: docs: `lib/spec/README.md`, `lib/gate/README.md`, `commands/start.md`, `commands/next.md`, one line in `commands/dispatch.md:162` pointing at the shared check before a worktree or branch is removed, `CHANGELOG.md`, the module registry rows `tests/run-all.sh --changed` demands.

## After state

- [ ] `grep -n "docs/specs/SPEC-\*" hooks/pre-compact-backup.sh hooks/post-compact-reinject.sh hooks/context-readiness.sh hooks/spec-drift-guard.sh` prints nothing; each calls `spec_active`. (Today: four private `ls docs/specs/SPEC-*.md` lines.)
- [ ] `bash tests/test-shared-lookups.sh` passes, and goes red when a private copy is added (negative control recorded).
- [ ] `branch_merged` is the only code that reads `--state merged`, `mergedAt`, `git cherry`, `patch-id` or a merged-direction `merge-base --is-ancestor`, except the pinned `merged-ok` lines. (Today: 17 lines in 6 files.)
- [ ] `wt.sh close` on a branch with a commit its merged PR never carried refuses and prints `LEAVE tip`. (Today: deletes the branch.)
- [ ] `wrap apply` on an origin branch whose PR merged into a non-default base keeps it. (Today: deletes it.)
- [ ] `spec-index.sh` run from a checkout holding `.claude/worktrees/*` lists each spec once. (Today: a copy per worktree.)
- [ ] `hooks/pre-compact-backup.sh` on the `## Problem` fixture prints `Spec: ambiguous (...)` or the branch's own spec, never the highest-numbered unrelated one.

## Quality requirements

none.

## Acceptance Criteria (global)

- [ ] AC1: default-mode `spec_active` output equals `spec_for_slug` for every slug in the fixtures (root, co-located, SHIPPED, none).
- [ ] AC2: `--live` answers one of `name`, `live`, `branch`, `ambiguous`, none, per the state flow in `## Design`.
- [ ] AC3: `branch_merged` default output is byte-identical to today's `_merge_ladder` on every case of `tests/test-wrap-ladder.sh`.
- [ ] AC4: `--need pr` never prints SAFE ancestor or SAFE absorbed.
- [ ] AC5: DM1 and DM2 inputs produce LEAVE through the migrated callers; DM3 keeps today's outcome.
- [ ] AC6: each caller in the migration list calls the function (presence check) and holds no private lookup (absence check).
- [ ] AC7: the lint finds exactly the pinned markers, no more, none without a reason.
- [ ] AC8: all existing suites the diff touches pass, and no call site loses a refusal it has today except where `## Behavior changes` names it.
- [ ] AC9: `spec_active --live` runs with `find` stubbed to fail (no walk) and records one `spec-status.sh live` pass; SessionStart hook wall time on this repo's spec count is recorded in the proof.

## Verification

```bash
bash tests/test-active-spec-pick.sh && bash tests/test-branch-merged-callers.sh \
  && bash tests/test-spec-find.sh && bash tests/test-wrap-ladder.sh \
  && bash tests/test-shared-lookups.sh && bash tests/run-all.sh --changed --time
bash lib/gate/negctl.sh "$PWD" "bash tests/test-shared-lookups.sh" "<append a private ls docs/specs/SPEC-*.md line to hooks/pre-compact-backup.sh>"
```

## Test plan
Date: 2026-11-25
Source: this spec's ## Acceptance Criteria and ## Edge Cases

Fixtures: `tests/lib/wrap-stub.sh` (gh stub, clones, `chk`) for merged cases; a mktemp repo built like `## Problem` for spec cases; a fresh `HOME`, no inherited git env.

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| C1 | name pick, root spec | happy-path | AC1 | prints the root file, kind `name` | `tests/test-spec-active.sh` |
| C2 | name pick, co-located only | boundary/edge | AC1 | finds `tools/x/docs/specs/SPEC-005-delta.md` | same |
| C3 | name pick on a SHIPPED spec (default mode) | boundary/edge | AC1 | still returned (ship flips SHIPPED before the push) | same |
| C4 | `--live`, lone open spec, branch unrelated | happy-path | AC2 | kind `live` | same |
| C5 | `--live`, three open, branch token matches one | happy-path | AC2 | kind `branch`, one line | same |
| C6 | `--live`, several open, no match | failure-injection | AC2 | kind `ambiguous` lines, exit 2, no pick | same |
| C7 | `--live`, header-less spec | boundary/edge | AC2 | open | same |
| C8 | `--live`, co-located open spec, none at root | boundary/edge | AC2 | exit 1 (root only) | same |
| C9 | `--live` with `find` and `ls docs/specs/SPEC-` stubbed to exit 99 | failure-injection | AC9 | still answers; stub never ran | same |
| C10 | ladder grammar, every existing case | regression | AC3 | unchanged lines | `tests/test-wrap-ladder.sh` |
| C11 | `--need pr`, ancestor with no PR | boundary/edge | AC4 | `LEAVE none` | `tests/test-branch-merged.sh` |
| C12 | `--need pr`, merged PR at exact tip | happy-path | AC4 | `SAFE squash` | same |
| C13 | merged PR into another base | failure-injection | AC5 | `LEAVE base <name>` | same |
| C14 | `--tip` of a commit past the PR head | failure-injection | AC5 | `LEAVE tip <PR head>` | same |
| C15 | `--prs-json` with a cross-repo row at the tip | failure-injection | AC5 | `LEAVE none` | same |
| C17 | ship-gate pick unchanged | regression | AC1, AC8 | `name` line equals today's `SPEC=` | `tests/test-spec-find.sh` |
| C18 | `wt.sh close`: PR-less, exact-tip merged, later commit | failure-injection | AC5 | refuse, close, refuse (the last flips from today) | `tests/test-branch-merged-callers.sh` |
| C19 | origin sweep: base not default | failure-injection | AC5 | kept | same |
| C20 | lint finds a private active-spec copy in a fixture hook | failure-injection | AC6 | red | `tests/test-shared-lookups.sh` |
| C21 | lint finds a private merged read in a fixture script | failure-injection | AC6 | red | same |
| C22 | a marker with no reason, or an unpinned marker | failure-injection | AC7 | red | same |
| C23 | presence: each caller names the function | happy-path | AC6 | green | same |
| C24 | negative control: add a private `ls docs/specs/SPEC-*.md` to a hook | failure-injection | AC6 | C23/C20 red, restore green | `lib/gate/negctl.sh` |
| C25 | `spec-index.sh` with a dot-dir worktree copy | boundary/edge | AC8 | listed once | `tests/test-spec-index.sh` |
| C26 | compaction hook on the fixture | happy-path | AC8 | branch-aware or `ambiguous`, never highest unrelated | `tests/test-active-spec-pick.sh` |

### Lint design (C20 to C24)

Scope: `hooks/`, `lib/`, `bin/`, excluding `tests/`, `*.md`, `*.html`, `*.tsv`, `*.py`, and the two shared files. A comment-only line is skipped (`^\s*#` after the `file:line:` prefix). Patterns, measured against this tree on the date above:

- active spec: `(ls|find)[^#]*docs/specs`, `docs/specs/SPEC-\*`, `spec_files\(\)`, `spec_for_slug\(\)`, `\*/docs/specs/SPEC`. Today it hits 21 lines in 13 files.
- merged: `--state merged`, `mergedAt`, `--state merged`, `git[^|]* cherry `, `patch-id`, `--state all[^|]*--head`, `--head[^|]*--state all`, and a merged-direction `is-ancestor` (first argument not `origin/`, second `origin/` or `refs/remotes/origin/`). Today it hits 17 lines in 6 files (`wrap-common.sh` 3, `wrap-adopt.sh` 3, `wrap-apply.sh` 3, `wrap-merge.sh` 4, `wrap-carry.sh` 3, `wt.sh` 1). The up-to-date direction (`is-ancestor origin/<def> HEAD`) and the post-merge confirmations (`!= "MERGED"` on a PR number) are excluded by shape, so a bare `MERGED` or `is-ancestor` grep, which would drown in them, is never used.

Allowlist (the `patch-id` pair in `wrap-carry.sh` carries a `merged-ok` marker): a line carrying `spec-active-ok: <reason>` or `merged-ok: <reason>`. The list of `file:reason` pairs is pinned inside the test; a new marker needs a test edit, an empty reason fails, a marker that no longer matches a pattern fails (no dead exemptions). Presence check: each migrated caller must contain `spec_active`/`spec-active.sh` or `branch_merged`. A positive-control fixture holds one known-bad line per pattern so the lint cannot pass by matching nothing.

### Coverage notes
- Categories skipped: concurrency (no shared state is written), performance beyond AC9 (no loop over specs in the new code).
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list.

## Edge Cases

1. A slug that is a substring of another (`gate` vs `gateway`): the name pick is exact (`SPEC-*-gate.md`), the token rule is whole-token; neither matches `gateway`.
2. A spec file named with newlines or spaces: `spec_files` already refuses a newline path; the new code reads its list line by line and never word-splits.
3. Detached HEAD or no branch: `--branch ""` means no slug; `--live` falls to the lone-live rule; default mode prints nothing, exit 1.
4. Two specs with the same slug in root and co-located: root wins (today's rule).
5. gh missing or rate-limited: `LEAVE nogh`, never SAFE; callers that delete skip.
6. A tag or local branch named `origin/<def>`: full refs only, as today.
7. `spec_active` sourced under a caller with `set -e` or `set -u`: it sets no options and guards every expansion; tested under both.
8. The compaction hook runs from a subdirectory: the toplevel is used (DA4).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Stale install: hook updated, `spec-active.sh` missing | `source` fails | advisory hooks print "no spec resolved"; ship-gate keeps its root-glob fallback (marker); the install copies hooks and lib together, so this needs a partial update |
| A looser rung leaks into a deleting caller | AC4, C11 | `--need pr` default for those callers is pinned in the callers' tests |
| The `wt.sh` change blocks a legitimate close (PR merged, branch tip differs because of a merge-base update push) | `LEAVE tip` printed | the operator pushes or uses `wrap land`; stricter by design (DM1) |
| Lint false positive on a new innocent line | lint red naming file:line | add the marker with a reason in the same commit; the test edit is the review point |
| `hooks/codex-hooks.json` pins `ship-gate.sh` | `tests/test-codex-hooks.sh` red | `bash lib/codex/repin.sh` in TASK-4; the second of two branches touching the hook repins after rebase |

## Out of Scope

- The floor sizing in `lib/classify/lane-classify.sh` and `lib/gate/ship-rules.sh` (another branch; see Merge order).
- The stale-install stub removal (DA7), `spec-next.sh` numbering, the `Status:` grammar.
- The patch-id check in `wrap-carry.sh` (a commit-landed question, not a branch-merged one; marker and reason only).
- Folding `_land_tidy`'s own tree verification into `branch_merged`: it confirms a PR it just merged, not a branch (excluded class).
- `commands/dispatch.md:162-168` beyond the one pointer line in TASK-12.
- Two unmerged ship-gate specs (SPEC-422 fork heads, SPEC-423 push tokenizing) touch `push-refs.sh` and the hook's marker reads; they overlap neither question.

## Touches
- hooks/ship-gate.sh
- hooks/pre-compact-backup.sh
- hooks/post-compact-reinject.sh
- hooks/context-readiness.sh
- hooks/spec-drift-guard.sh
- hooks/codex-hooks.json
- lib/spec/**
- lib/gate/branch-merged.sh
- lib/wrap/**
- lib/goal/wt.sh
- tests/**
- commands/start.md
- commands/next.md

## Merge order

`hooks/ship-gate.sh`: this build edits only lines 692-701, the block that begins `# Resolve the spec for this slug; fail open if there is no spec-driven run.` and ends at the closing `fi` before `# Build-ran advisory`. The floor work on `lib/classify/lane-classify.sh` and `lib/gate/ship-rules.sh` may touch the `_floor_check` call lines around 738-742 (`if [ -z "$SPEC" ]; then _floor_check`), a separate hunk about forty lines below. The two hunks do not overlap, so either order rebases cleanly; land the floor branch first, rebase this one onto it, then run `bash lib/codex/repin.sh`, because `hooks/codex-hooks.json` pins `ship-gate.sh` by content hash and each branch that edits the hook changes that one line. TASK-3 to TASK-10 touch no file in the floor branch.

## Decision Log
- DEC-A: two modes in one function, not two functions. Rationale: the row asks for one lookup; the enforcement and session questions differ only in the status filter and namespace, both visible arguments. Rejected: a `spec_live` sibling (a second public name to copy).
- DEC-B: promote `_merge_ladder`, do not write a new one. Rationale: scan, apply and land already share it and `tests/test-wrap-ladder.sh` pins its grammar; the risk of a rewrite is all downside.
- DEC-C: DM1 and DM2 change behavior in the stricter direction on purpose. Rationale: each is a data-loss path today; the row says surface it, and a tighter delete never loses work.
- DEC-D: header-less specs are open everywhere (DA3). Rationale: hiding a spec in a compaction snapshot costs the model its recovery context; the readiness change is bounded to one input shape.

## Grounding

Each excerpt is a live run against this tree on a scratch repo (paths shortened to `$S`); the shell was bash.

Active spec, branch `feat/alpha`, specs 010 alpha SHIPPED, 020 beta DRAFT, 030 gamma DRAFT, co-located `tools/x` 005 delta:
```
ship-gate pick alpha (SHIPPED spec): docs/specs/SPEC-010-alpha.md
ship-gate pick delta (co-located): tools/x/docs/specs/SPEC-005-delta.md
pre-compact-backup:  Spec: docs/specs/SPEC-030-gamma.md
context-readiness:   spec:ambiguous(SPEC-020,SPEC-030) branch:feat/alpha
spec-index (with .claude/worktrees/w/docs/specs/SPEC-020-beta.md present):
  .claude/worktrees/w
    SPEC-020 | beta | DRAFT
  central docs/specs
    SPEC-010 | alpha | SHIPPED ...
```
`spec_files` on the same tree lists four paths and none under `.claude`.

Merged, scratch repo with a bare origin, a gh shim, feat/x = PR head A plus unpushed commit B:
```
wrap _merge_ladder: LEAVE tip 749ab094bc6b8993daba9667732df7ee52eae9b1
$ bash lib/goal/wt.sh close x feat      (real script; gh shim answers MERGED)
RELEASED x
closed feat/x @ 6de7be2
feat/x GONE; the unpushed commit B is reachable only through the reflog
```
Ancestor, no PR: `_merge_ladder` prints `SAFE ancestor ancestor of origin/master`; the `wt.sh` gate expression returns `[]` and refuses. Origin sweep, merged PR base `stack-base`: `WOULD delete 1 merged branches on origin: feat/x`; the ladder on the same tip: `LEAVE base stack-base`. Carry patch-id: `landed=0f525569` for a stray commit whose patch master took and then edited; the ladder on that tip: `LEAVE none no merged PR found for this head`.

Negative-control dry trace (C24): mutation, append `SPEC_LIST=$(ls docs/specs/SPEC-*.md)` to `hooks/pre-compact-backup.sh`; the lint reads `hooks/` and matches the active-spec pattern `docs/specs/SPEC-\*` on that line with no marker, so C20 and C23's absence check fail; restoring the file removes the line and the test passes.

## Open questions

none. The lead decided header-less specs (open everywhere, readiness included), the patch-id check (named exclusion), and the `commands/dispatch.md` pointer (one line in TASK-12).
