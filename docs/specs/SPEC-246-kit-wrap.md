# Spec: `/kit:wrap`, the landing step after ship

Generated: 2026-09-06
Status: DRAFT
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-246-kit-wrap.md`
References: the operator's `session-closeout` skill Phase 2 and its skim-first report shape (dotfiles `home/dot_claude/skills/session-closeout/SKILL.md`, the six numbered steps and the `## Closeout` block: port the steps and the report grammar, drop the operator-specific distill phase); `repo-wrapup` scripts `wrapup-scan.sh` (report-only scanner: checkout, ahead/behind, dirty files, worktrees, branch verdicts, open PRs) and `wrapup-apply.sh` (gated executor: branch delete only as an ancestor of the default branch or with a merged PR whose head equals the tip, worktree remove only under a flag and only clean and attached, pull ff-only on the default branch; every skip prints its reason): port both verbatim as `wrap scan` and `wrap apply`, generalising `origin/main` to the detected default branch; `bin/learn` + `lib/learn/learn.sh` (shim and verb entry); `lib/precedent/precedent.sh` (repo-root resolution, `kit_config_get_root` for a consumer key); `commands/retro.md` (the cycle-scoped reflect step this command calls); ops-toolkit `_meta/lablog-add` (the activity-log line format: `YYYY-MM-DD · <slug>: <one sentence>` prepended newest-first, dash refusal, 300-char warn).

## Problem

The kit's lifecycle ends at `/kit:ship` (review gate, tests, changelog, PR). Nothing in the kit lands the session after that: board rows are not flipped to shipped, the operator's own green PRs are not merged, a merged-but-undeployed PR is not noticed, branches and worktrees pile up, the default branch is not pulled, no activity line is written, and `/kit:retro` has no caller (`/kit:start` suggests it; nothing runs it). The operator carries all of that in a personal skill (`session-closeout`, dotfiles) whose Phase 2 is generic git and board mechanics, with a second personal skill (`repo-wrapup`) holding the two scripts. Every adopter without those skills ends sessions by hand, and the operator's copies cannot be retired while the kit has no home for them.

## Solution

### Approaches considered

1. **A new session-scoped command `/kit:wrap` over a `wrap` subsystem** (`bin/wrap` with `scan`, `apply`, `log` verbs, `lib/wrap/`). The command orders the steps per touched repo, calls `board set` and `gh`, and ends by calling `/kit:retro` when a spec cycle merged. Tradeoff: one more command and one more bin entry.
2. **Extend `/kit:retro` with a landing tail.** Tradeoff: retro is cycle-scoped and never writes git state (PHILOSOPHY, detect not dictate); a session touches several repos and needs merges and deletes. Mixing the two bloats a reflection ritual with mechanics.
3. **Extend `/kit:ship` past the PR.** Tradeoff: ship is per feature and stops at the PR by design; merging, deploy checks and worktree tidy are session-wide and need every PR of the session, not the one just opened.

### Chosen approach + why

Approach 1. Session scope is the distinguishing property: one pass over every repo the session touched, after every ship. Retro keeps its scope and gains its missing caller. Ship keeps its fence.

### Extensibility & boundaries

- Load-bearing dimension: the number of touched repos and the number of consumer seams (activity log today; a deploy verifier later). Repos are positional arguments; a seam is one config key read with `kit_config_get_root`, never a project toml (it names a file the kit writes to).
- Units: `lib/wrap/wrap.sh` (verbs, gates, default-branch detection), `commands/wrap.md` (the ordered steps, the merge and deploy rules, the report grammar), `tests/test-wrap.sh` (fixture remotes and clones). The verbs never merge a PR, never switch a branch, never touch a dirty file; those stay in the command as judgment calls with named rules.
- Out of the closed set: the distill phase (til, learned-ledger, memory routing) stays with the operator overlay; `learning-kit` owns the study side (LK-23).

### Architecture

See `## Design`.

## Picture

```
/kit:ship (per feature, ends at the PR)
      │
      ▼
/kit:wrap  (per session, per touched repo)            bin/wrap ──exec──▶ lib/wrap/wrap.sh
  0 concurrent-writer check (worktree list, reflog)        scan  <repo>...        report only
  1 board rows        board set <ID> shipped|parked|dropped apply [--apply] [--worktrees] <repo>...
  2 commit by name    (command, judgment)                   log   <repo> "<slug>: <sentence>"
  3 merge own PRs     gh pr merge, own command, gh pr view      └─ prepends to wrap.activity_log
  4 deploy check      headSha == merge SHA where deploy is a dispatch   (kit-root kit.toml key)
  5 branches, worktrees, pull  wrap scan -> wrap apply (dry) -> wrap apply --apply
  6 activity line     wrap log
  7 reflect           /kit:retro when a spec cycle merged this session
  8 report            skim-first block: Needs you, What happened, Shipped, Left alone, FYI
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Diagram

```
operator: "/kit:wrap [<repo>...]"
   │  no repos given: the current repo
   ▼
commands/wrap.md
   ├─ for each repo: bin/wrap scan <repo>            (fetch --prune, checkout, ahead/behind vs default, dirty, worktrees, branch verdicts, own open PRs)
   │     STOP on: a dirty file this session did not write, an index.lock, a worktree with recent foreign activity
   ├─ board set … for every row this session's source of truth closed
   ├─ commit by name; merge own green PRs one per command; verify with gh pr view
   ├─ deploy check where the repo deploys by dispatch
   ├─ bin/wrap apply <repo> (dry) -> read every SKIP -> bin/wrap apply --apply [--worktrees] <repo>
   ├─ bin/wrap log <repo> "<slug>: <sentence>"      (no key set: prints the line, exits 0, says where it did not land)
   ├─ /kit:retro when a spec cycle merged
   └─ the report block
```

### ADR link(s)

ADR-0034 (`bin/<subsystem> <verb>`; `wrap` is a subsystem noun with three verbs). ADR-0028 P5 unchanged: retro remains the reflect step; wrap is its caller. No new ADR.

### Boundaries & failure modes

The verbs are read-only except three gated writes: `git branch -d`/`-D` under the two proofs, `git worktree remove` under `--worktrees` on a clean attached worktree, `git pull --ff-only` on the default branch, and the activity-log prepend. `gh` absent: branch verdicts fall back to "unknown, leave", the command reports it. Default branch: `refs/remotes/origin/HEAD` when set, else `main` if `origin/main` exists, else `master`; none: the repo is reported and skipped. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

```
wrap scan  <repo> [<repo>...]                      report only, exit 0; a non-repo path prints a skip line
wrap apply [--apply] [--worktrees] <repo> [<repo>...]   dry-run by default; --apply executes the gated subset
wrap log   <repo> "<slug>: <one sentence>" [--date YYYY-MM-DD]
wrap default-branch <repo>                        prints main|master|<name>, exit 1 when none resolves
wrap --help
```

- `scan` prints, per repo: `== <repo>`, `-- checkout on:`, `-- vs origin/<default>: ahead=N behind=M`, `-- dirty files` (first 10 or `(clean)`), `-- worktrees`, `-- local branches` with one verdict per branch (`SAFE-d: ancestor of origin/<default>`, `SQUASH-MERGED per gh: safe to -D`, `NOT merged / unknown: LEAVE`), `-- open PRs authored by me` (or `(gh unavailable)`). Closing lines say it is report only.
- `apply` prints `[DRY-RUN]`/`[APPLY]` per action and `SKIP <what>: <reason>` for every refusal: worktree without `--worktrees`, dirty worktree, detached worktree, the checked-out branch, a branch held by a worktree, no merged PR for the head, tip differs from the merged PR head, pull when not on the default branch (then `fetch origin <default>:<default>`, which refuses non-ff on its own). Never merges PRs, never switches branches, never force-pushes.
- `log` reads `wrap.activity_log` with `kit_config_get_root` (a repo-relative file path, resolved against `<repo>`; empty by default). Prepends `<date> · <text>` as the first line of that file, refuses an em or en dash, warns over 300 chars, prints the line. Key unset: prints the line and `wrap log: no wrap.activity_log key in the kit-root kit.toml; line not written`, exit 0.
- `default-branch`: the detection above.
- Exit codes: 64 on usage, 1 on a repo that is not a git checkout when it is the only argument, 0 otherwise.

`commands/wrap.md` carries the eight steps with these fixed rules: only PRs this session opened, green checks, no open review threads, `gh pr merge <n> --squash` alone in its command, verified by `gh pr view <n> --json state,mergeCommit`; merged is not deployed (a `workflow_dispatch` repo gets the dispatch and a `headSha == merge SHA` check before `DEPLOYED` is claimed); a squash-merged EnterWorktree worktree is kept unless the operator confirms; pull is ff-only, last, only on the default branch; the report block is the `## Closeout` grammar from the reference with `Needs you` first and the fixed uppercase tokens; `Distilled` and `Candidates` lines are emitted only when an overlay supplies them (the kit prints `NOTHING`).

### Data model changes
`kit.toml` gains `[wrap]` with `activity_log = ""` (`[consumer]`, a repo-relative file path). `lib/config/module-registry.md` gains the row.

### API changes
New `bin/wrap`, new `commands/wrap.md`. `commands/start.md` names `/kit:wrap` as the step after ship and before retro. `commands/retro.md` "When to run" gains "called by `/kit:wrap` when a spec cycle merged".

### UI changes
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: `lib/wrap/wrap.sh` (verbs `scan`, `apply`, `log`, `default-branch`, `--help`; port the two reference scripts verbatim with the default-branch generalisation; `log` per the contract) and `bin/wrap` (shim shape of `bin/learn`); `tests/test-wrap.sh` with a fixture: a bare remote plus a clone with a `main` default, a second pair with `master`, branches `merged-ancestor` (merged into the default), `unmerged` (ahead, no PR), a clean secondary worktree on a branch, a dirty secondary worktree, a detached worktree, `gh` stubbed on PATH to answer `pr list --state merged` for one branch whose head equals the tip and one whose head differs; registered in `.github/workflows/test.yml`; `tests/test-bin-forwarders.sh` census. Acceptance: `scan` prints every section and verdict named above for both fixtures; `apply` dry-run lists each SKIP reason; `apply --apply` deletes only `merged-ancestor` and the squash-proven branch, keeps the differing-tip branch, refuses the worktrees without `--worktrees`, removes only the clean attached worktree with it, pulls ff-only on the default branch; `log` prepends with the date, refuses a dash with exit 1, warns over 300 chars, exits 0 with the not-written line when the key is unset; `default-branch` answers `main` and `master` for the two fixtures and exits 1 on a remote-less repo; the suite, `test-meta.sh`, `test-bin-forwarders.sh` green.

### Phase 2: Core
- [ ] TASK-002: `commands/wrap.md` (frontmatter description; the eight steps with the fixed rules; the report block grammar; the `/kit:retro` call rule; a `## When this runs` section; the Self-intro banner line convention), `kit.toml [wrap]` + `lib/config/module-registry.md` row, `commands/start.md` and `commands/retro.md` pointers, README (lifecycle line and subsystem command list), `docs/architecture.md` bin paragraph, `docs/consumer-contract.md` entry, `docs/CHANGELOG.md` [Unreleased], `docs/FEATURES.md` regenerated (a new command adds a row), `tests/test-meta.sh` pins if any fire. Acceptance: `bash lib/registry/feature-registry.sh generate` is byte-stable; `test-meta.sh` green; `grep -n "kit:wrap" commands/start.md commands/retro.md README.md` each non-empty; `commands/wrap.md` names every rule in the Interfaces paragraph.

### Phase 3: Polish
- [ ] TASK-003 (lead): proof of done at `docs/verification/kit-wrap.md` (behavioral: a real `wrap scan` and `wrap apply` dry-run on this worktree's repo, `wrap log` against a scratch kit.toml, negative control by disabling the squash-proof gate and watching the suite go RED); battery before merge.

## After state
- [ ] `bin/wrap scan <repo>` on this kit prints the checkout, ahead/behind vs `origin/master`, dirty files, worktrees, branch verdicts, and own open PRs. (Today: the same report needs the operator's dotfiles script.)
- [ ] `bin/wrap apply --apply <repo>` deletes only proven-merged branches and pulls ff-only on the default branch, printing a reason for every skip. (Today: dotfiles script, `origin/main` only.)
- [ ] `bin/wrap log <repo> "x: y"` with `[wrap] activity_log = "_meta/LAB_LOG.md"` in the kit-root kit.toml prepends a dated line to that file. (Today: ops-toolkit's own `_meta/lablog-add`.)
- [ ] `/kit:wrap` exists as a command with the eight steps and calls `/kit:retro`; `/kit:start` names it. (Today: retro has no caller.)
- [ ] `bash tests/test-wrap.sh` exists and is green.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions: `tests/test-meta.sh`, `tests/test-bin-forwarders.sh`, `bash tests/run-workflow.sh`

## Verification

```
bash tests/test-wrap.sh && bash tests/test-meta.sh && bash tests/test-bin-forwarders.sh
bin/wrap scan . | grep -E '^-- vs origin/(main|master): ahead='
bin/wrap default-branch . | grep -E '^(main|master)$'
```

## Edge Cases
1. Repo whose default branch is `master`: every verdict and the pull use `origin/master`.
2. No `origin/HEAD` and neither `origin/main` nor `origin/master`: `default-branch` exits 1; `scan` prints a skip line; `apply` skips the repo.
3. `gh` not on PATH: `scan` prints `(gh unavailable)`, every non-ancestor branch is `unknown: LEAVE`, `apply` skips them with `no merged PR found`.
4. Branch tip differs from the merged PR head (unpushed commits): SKIP with both short SHAs.
5. Dirty secondary worktree: SKIP even with `--worktrees`.
6. Detached worktree: SKIP with the orphan reason.
7. Checkout not on the default branch: pull is skipped, `fetch origin <default>:<default>` runs and its non-ff refusal is reported, never forced.
8. `log` with an em dash or en dash: exit 1, nothing written.
9. `log` over 300 chars: written, warning on stderr.
10. `log` when the target file does not exist: exit 1 with the path, nothing created.
11. A path that is not a git checkout among several: skip line, the others proceed, exit 0.
12. `apply` without `--apply`: no write of any kind (`git status` and `git branch` unchanged, asserted).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Fetch fails (offline) | `(fetch failed; ...)` line | verdicts may be stale; nothing is deleted on stale data because the ancestor test then fails closed |
| Stale `gh` answer | tip differs from the merged head | SKIP, both SHAs printed |
| Concurrent writer in the same checkout | step 0 in the command: worktree list, reflog, index.lock | STOP and report, leave the repo |

## Out of Scope
- The distill phase (til, learned-ledger, memory notes): operator overlay; LK-23 for the study side.
- Deploy dispatch itself: the command checks, it never dispatches; the repo's own ship path does.
- A `touched repos` discovery: repos are arguments; the current repo is the default.

## Decision Log
- DEC-001: `wrap.activity_log` is a file path, not a command, and resolves from the kit-root `kit.toml` only. A command would let a repo-committed toml run code at wrap time; a file path is inert. The kit does the prepend itself in the `lablog-add` format.
- DEC-002: the two dotfiles scripts are ported verbatim into one `wrap.sh`, verbs `scan` and `apply`, rather than redesigned. Their gates have a year of use; the only change is the default-branch generalisation.
- DEC-003: the report grammar moves into the kit with "the operator" for "Han"; the two personal lines (`Distilled`, `Candidates`) print `NOTHING` unless an overlay supplies them.

## Open questions
(none)
