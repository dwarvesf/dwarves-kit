# SPEC-323: wrap step 10 titles PRs from the first commit

**Status:** VALIDATED
Lane: normal
Type: spec-feature
**Proof:** `tests/test-wrap.sh`, the step-10 wording block.

## Problem

`commands/wrap.md` step 10 tells the lead to open follow-through PRs with `gh pr create ... --fill`. On a branch with more than one commit, `--fill` titles the PR after the branch name. On 2026-09-26 that produced PR #774 titled `feat/negctl hint`, and the squash merge put that title on master.

## Contract

- The BUILD/FINISH command (one commit per branch) uses `--fill-first`, which takes the title and body from that commit.
- The full-lane draft command takes `--title "<the feature commit subject the worker reported>" --body-file docs/verification/<slug>.md`, because that branch's first commit is the spec, not the feature.
- Nothing else in step 10 changes.

## Design

obvious: two command lines in step 10 change their title source; `gh` has supported `--fill-first` since 2.34.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1 | `commands/wrap.md`, `tests/test-wrap.sh` | the BUILD/FINISH command says `--fill-first`; the draft command carries the explicit title; a `chk_no` pin rejects a bare `--fill` |

## Test plan

| Case | Expected |
|---|---|
| draft pin | the draft command's explicit `--title` present |
| BUILD/FINISH pin | `gh pr create --head <branch> --fill-first` present |
| no bare `--fill` | `chk_no` on the literal ``--fill` `` (flag then closing backtick) passes |

## Verification

`bash tests/test-wrap.sh` exits 0.

## After state

Follow-through PRs carry the feature commit's subject as their title.

## Decision Log

- `--fill-first` where the first commit is the feature; an explicit title on the full-lane draft, whose first commit is the spec (fresh validation, warning 1).
- The ship-gate blocks `gh pr create --dry-run` while gates are missing, so the flag combination `--title` with `--fill-first` was not probed; the draft command avoids combining them.
