# Implementation notes: SPEC-246 /kit:wrap

Delta from the spec only.

## 2026-09-06 Before build

- The spec went through design-critique (architecture lens) and two spec-validate lenses (testability, security) before build; every REVISE item is folded into the Technical Design and the Decision Log rather than kept as a list, so the build reads one contract.
- Lane is `full` by classification (new command plus new subsystem); the review step is review-team with the bounded fix loop, then the battery.

## 2026-09-06 TASK-001 The unresolved-thread gate reads mergeStateStatus

Context: the Interfaces paragraph requires the merge verb to refuse a PR when a review
thread is unresolved. `gh pr view --json` exposes no `reviewThreads` field. Asking for it
makes gh reject the whole call, so the gate as literally worded has no gh CLI expression.

Decision: request `mergeStateStatus` on the same `pr view` call and refuse anything but
`CLEAN`, `HAS_HOOKS` or `UNSTABLE`.

Why: GitHub reports `BLOCKED` for a pull request whose merge is held by an unresolved
conversation or an unmet review requirement. One field on a call the verb already makes,
and it fails closed: an unknown state refuses rather than merges.

Alternatives: a `gh api graphql` reviewThreads query (a fourth gh invocation, needs an
owner and repo pair that a local-path origin does not carry, and it fails on any host
where graphql is blocked); dropping the gate (refused, the spec names it).

Impact: the verb also refuses a PR blocked for a reason other than a thread, for example a
missing required review. That direction is the safe one. A later task may add the graphql
query behind the same verdict string.

Open questions: none.

## 2026-09-06 TASK-001 A refused off-default fetch is a FAILED write, exit 2

Context: when the checkout sits off the default branch, `apply` skips the pull and runs
`fetch origin <default>:<default>` instead. The reference script printed a soft note when
that fetch refused. The spec says a write whose git command fails prints `FAILED` and
`apply` exits 2, and separately that the fetch refusal is reported.

Decision: the fetch is a write, so it takes the blanket rule: `FAILED` plus exit 2.

Why: one rule for every write beats two. A refused fetch means the local default branch
diverged from origin, which the operator must see, and a zero exit hides it from a caller.

Alternatives: keep the reference's soft note (a diverged local default branch then exits 0).

Impact: an `apply --apply` run in a repo whose local default branch diverged exits 2 even
though nothing else failed. The line names the fetch.

Open questions: none.

## 2026-09-06 TASK-001 The gh stub answers five invocations, not three

Context: the task description names three stub invocations. The merge verb needs
`mergeable`, `statusCheckRollup`, `reviewDecision`, `mergeStateStatus` and `baseRefName`
per PR, plus the post-merge state check.

Decision: the stub also answers `pr view <n> --json <detail fields>` and `pr view <n>
--json state,mergeCommit`, and `pr merge`. The per-branch merged-PR fixtures stay in env
vars keyed by the sanitized branch name, as described.

Why: `gh pr list --author "@me" --state open` cannot carry the gate fields, and inventing a
wider list call would diverge from the invocation the scan verb already uses.

Alternatives: one fat `pr list` with every field (a shape the scan verb would not share).

Impact: the test asserts the exact recorded argv for every call, so a change to the
invocation set is visible.

Open questions: none.

## 2026-09-06 TASK-001 Smaller calls the spec left open

Context: several details had no wording in the spec.

Decision and why, one line each:

- The activity-log prepend copies the target's mode onto the temp file before the `mv`, so
  the spec's "mode preserved" and its "mv over the target" both hold.
- `apply` prints an explicit `SKIP <branch>: default or protected branch name` line for the
  detected default plus `main` and `master`; the reference skipped them silently, and a
  silent skip reads like an oversight in a report a human scans.
- Argument collection uses an indexed array with a counter, never `arr+=()` with
  `${#arr[@]}`: an empty array reads as unbound under `set -u` in the bash 3.2 that macOS
  ships, and CI runs the macOS leg.
- `scan` prints `(gh query failed)` when gh is authenticated but the PR list call fails,
  which keeps the section honest instead of empty.

Impact: none beyond the report text and portability.

Open questions: none.
