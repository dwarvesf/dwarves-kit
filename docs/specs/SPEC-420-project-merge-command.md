# Spec: merge.command, the project's own PR merge command

Generated: 2026-11-12
Status: VALIDATED
Lane: full (the diff floor: `kit.toml` is an enforcement-surface path; the change runs a command from a config file on every kit merge)
Depth: standard (every merge call site was found by searching `lib/`, `bin/`, `commands/`, `skills/`, `hooks/` for the merge verbs; see ## Call sites)
Type: spec-feature
File: `docs/specs/SPEC-420-project-merge-command.md`
References: `lib/wrap/wrap-common.sh` (`_gh_merge_retry`); `lib/wrap/wrap-merge.sh`; `lib/wrap/wrap-land.sh`; `lib/goal/mega-merge.sh`; `lib/goal/stack-merge.sh`; `lib/config/kit-config.sh` (`kit_config_show_at`); `docs/WORKFLOW.md` ("read only from the `.kit.toml` at the merge base" for `[[gate.hard_path_exempt]]`)

## Problem

`/kit:wrap` (`wrap merge`, `wrap land`) and the mega-merge script merge a PR with the plain GitHub squash. A consumer repo (`consolelabs/playdate-agent`) requires its own merge script (`bash scripts/pr-merge.sh <number>`), which refuses a draft, a red or pending check, a conflict, and a one-way door without a second approval. The kit's merge skips that script, so the one-way-door check never runs for a kit user.

## Rules

| # | Rule |
|---|---|
| R1 | New key `[merge] command` (default empty). Set, it is the command that merges a PR, run as `<command> <pr-number>`. Empty: every kit merge is unchanged. |
| R2 | Every place the kit merges a PR itself runs it when set: `wrap land` (both merge calls), `wrap merge`, `lib/goal/mega-merge.sh merge` (and through it the orchestrate converge hook), `lib/goal/stack-merge.sh`. See ## Call sites. |
| R3 | The command replaces the plain merge outright. The kit passes no merge flags; the gated head rides in `KIT_MERGE_HEAD_COMMIT` and the number in `KIT_MERGE_PR`. Before it starts, the kit re-reads the PR head and refuses (exit 3) if it moved off the gated one: the plain path pinned the head too. stack-merge has no gated head and passes none. |
| R4 | A non-zero exit stops the kit flow with the command's own output on the terminal and its exit code carried through. No retry (the transient-error retry stays plain-merge only), no conflict cycle, no fallback to the plain merge. |
| R5 | A zero exit is not trusted: wrap checks MERGED and the tree as after the plain merge; mega-merge and stack-merge check MERGED through `kit_merge_verify` and stop if GitHub disagrees. |
| R6 | Trust. The value comes from the `.kit.toml` COMMITTED on the default branch (`refs/remotes/origin/<default>`, fully qualified so a tag or branch named like it cannot stand in; best-effort fetch first), never the working tree, never HEAD, never the PR; then the operator `kit.toml`, then the kit-root one. The command runs from a clean detached checkout of that commit, with `BASH_ENV`, `GIT_*` and `KIT_CONFIG_*` removed and `pipefail` on, so the script it names is the reviewed one and a stack-merge reconcile or a local edit cannot swap it. Same read-model as `[[gate.hard_path_exempt]]`. |
| R7 | Fail closed. Exit 2 (refuse, never "unset") when: the repo dir is missing, the default-branch tree cannot be read, a project key exists only where it cannot be verified (default branch unresolvable), or the value is not one simple command (no `;` `&` `|` `<` `>` backtick `$(` newline `#`). Callers refuse on 2. |
| R8 | `wrap merge --repo <slug>` has no checkout to run the script in. The key is read through `gh api` from the default branch: set means refuse (exit 2); a 404 counts as unset only when the directory listing of the same ref is readable and lacks `.kit.toml`; any other failure refuses. This adds one `gh api` read to a slug merge with the key unset. |
| R9 | mega-merge keeps its own guards (`_merge_config_guard` already refuses to auto-merge a PR that touches the root `.kit.toml`). Its dry-run line prints the project command in place of the plain one. |
| R10 | stack-merge resolves the key before it reconciles or retargets anything, and on a refusal puts the retargeted child PR back on the parent branch. |

## Call sites

| Site | Change |
|---|---|
| `lib/wrap/wrap-common.sh` new `_merge_pr` (wraps the untouched `_gh_merge_retry`) | resolves the key; runs the project command or falls to `_gh_merge_retry` only when unset; sets `WRAP_MERGE_PROJECT` |
| `lib/wrap/wrap-land.sh` merge and the post-conflict-cycle merge | call `_merge_pr`; the first stops with `MERGE REFUSED` before any conflict cycle |
| `lib/wrap/wrap-merge.sh` the one merge | calls `_merge_pr` with the repo, or the slug and default branch; names the refusal |
| `lib/goal/mega-merge.sh` `merge --execute` and its dry-run lines | project command in place of the plain one; refusal or unreadable key returns non-zero with `BLOCKED` |
| `lib/goal/stack-merge.sh` `next_link` | project command in place of the squash; refusal stops the chain and restores the child |
| `wrap ship`, `wrap adopt`, `wrap carry` | merge only through `cmd_land`; covered |
| `lib/queue/orchestrate.sh` converge | calls `mega-merge.sh merge` through `WAVE_MERGE_CMD`; covered |

Prose that tells an operator to run the plain merge by hand (`commands/mega.md`, `commands/ship.md`) gains one sentence naming the key.

## Solution

### Approaches considered

| Approach | Verdict |
|---|---|
| A. One shared resolver and runner, `lib/config/merge-command.sh`, sourced by every merge site | chosen |
| B. A merge-command arg threaded through each caller | rejected: three scripts, three copies of the trust rule |
| C. A git alias or a `gh` wrapper on PATH | rejected: invisible, per machine, and the kit would still pass its own flags |

### Chosen approach + why

A. The trust rule (R6) and the run contract (R3, R4) live in one file with one test suite.

### Trust

This key names code the kit runs. Keys that do (`wrap.before`) are operator-only because a project `.kit.toml` rides inside an untrusted PR. R6 and R7 close the PR path: the command and the script it names come from the default branch as committed. The remaining exposure: a repo whose default branch is hostile can name any command, so an operator running `wrap` in a repo they do not trust runs that repo's code, the same trust as running its tests or git hooks. The owner approved a project key in principle; the committed-default-branch reading is the recommended safeguard. The cost: the script runs from a clean checkout, so untracked local files (a `.env`, `node_modules`) are not there.

## Technical Design

- `lib/config/merge-command.sh`: `kit_merge_command <repo>`, `kit_merge_command_slug <slug> <def>`, `kit_merge_exec <repo> <cmd> <pr> [<head>]`.
- `kit.toml` `[merge]`, `lib/config/module-registry.md`, `docs/guides/wrap.md`, `commands/wrap.md`, `commands/mega.md`, `CHANGELOG.md`.

## Task Breakdown

1. Resolver and runner.
2. Route the call sites above.
3. `tests/test-merge-command.sh` (resolver, wrap merge, wrap land, stack-merge, slug) and the mega-merge cases in `tests/test-mega-merge.sh`.
4. Docs.

## After state

A repo with `[merge] command` on its default branch merges every PR through its own script; a refusal ends the kit flow with the script's message. Every other repo is unchanged.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 resolver: committed default-branch value wins; working-tree, PR-branch edits ignored; operator and project order | `tests/test-merge-command.sh` resolver section |
| AC2 `wrap merge --apply` with the key: the command runs once with the PR number and head, `pr merge` is never called, the merge is still verified | wrap merge section |
| AC3 refusal in `wrap merge`, `wrap land`, `mega-merge`, `stack-merge`: the command's message shown, its code kept, no plain merge, no retry, no conflict cycle; an unreadable key, a moved head and a non-MERGED result also stop | the refusal sections |
| AC7 trust: a tag or branch named like the base, a PR-branch HEAD, a working-tree edit, an edited working-tree script, a hostile GIT_DIR and a non-simple value never change what runs | the resolver and exec sections |
| AC4 key unset: each site calls the plain merge exactly as before | the key-unset cases |
| AC5 slug: set refuses, 404 plain, other failure refuses | slug cases |
| AC6 negative control: make the router ignore the key and AC2 to AC5 go red | `docs/verification/project-merge-command.md` |

## Verification

```bash
bash tests/test-merge-command.sh
bash tests/test-mega-merge.sh
bash tests/run-all.sh --changed
```
