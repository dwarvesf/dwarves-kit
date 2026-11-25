# Spec: mega tick, record a merged sub-goal from gh truth

Generated: 2026-11-25
Status: DRAFT
Lane: full
Depth: standard (every external shape the verb reads is sampled live in ## Grounding, and the code it extends is two files read at line level)
Type: spec-feature
File: `docs/specs/SPEC-430-mega-tick.md`
References: `lib/queue/orchestrate.sh` `cmd_flip` (lines 990 to 1020: the one existing ROADMAP writer; imitate its lock path, its re-read under the lock, its write-temp-then-`mv`, and its use of `box_token` instead of a literal box); `lib/mega/mega.sh` `cmd_status` (lines 290 to 364: imitate its root resolution, its line loop over `box_re` plus `BOX_ID_RE`, and its first-`PR #<n>` parse); `lib/gate/default-branch-warn.sh` `kit_default_branch_here` (the default-branch resolver to reuse, not copy); `lib/goal/attempt-state.sh` `as_status` and `as_commit_result` (the attempt store the verb records into, read through its CLI only)

## Problem

A mega-goal lead closes every sub-goal the same way: check on GitHub that the PR merged, copy the merge sha, edit the sub-goal's ROADMAP line by hand, and record the result in the attempt store. In one VimMotion run (`01-human-first-upgrade`, 44 sub-goals) the lead wrote that `gh` audit plus `sed` by hand about ten times. Two of those hand edits put wrong data into the ledger:

- Commit `3047044` ticked `- [x] 21-app-shell-seams, PR #57, merged OPEN `. The word `OPEN` went into the sha slot. By the lead's own account (not sampled), the PR's `mergeable` read `UNKNOWN` at that moment and the hand flow pressed on.
- A tick wrote `merged 2819920` for PR #37, whose merge commit is `281992a`. The wrong sha stayed in the ROADMAP until a later audit (commit `8e749b2`, "fix 13 sha").

`mega status` finds a `[x]` line whose PR is not merged (CLAIM-UNVERIFIED), but only after the fact, and it never reads the sha. Nothing writes the line from gh truth to begin with. The kit owns the ROADMAP grammar (`lib/mega/box.tsv`) and the attempt store. It should also own the one verb that moves a sub-goal to done.

## Terms

none

## Solution

### Approaches considered

1. **A new `mega tick` verb in `lib/mega/mega.sh`.** It audits the PR through `gh`, rewrites one line, and records the attempt. Tradeoff: `lib/mega` has held read-only verbs until now; this is its first writer.
2. **A `--tick` flag on `lib/goal/mega-merge.sh merge`.** Tradeoff: that verb only runs when the kit does the merge. A human-merged PR (a `gate` sub-goal, the release-pipeline PR merged by Han) and a `wrap merge` landing never pass through it, and those are the cases that need ticking most.
3. **A post-merge hook inside `wrap land` or `wrap merge`.** Tradeoff: `wrap` does not know which mega-goal or sub-goal a PR belongs to, and adding that knowledge couples `wrap` to the ROADMAP grammar.

### Chosen approach + why

Approach 1. One verb serves every merge path, because it starts from the PR number, not from whoever merged it. `mega-merge.sh` and `wrap` stay unchanged. The tradeoff: `lib/mega/README.md` changes from "read-only views" to "views plus one writer", and the writer inherits the box-grammar and shared-lookup lints that cover `lib/mega`.

### Extensibility & boundaries

- Load-bearing dimension: the number of sub-goals and runs. The verb touches one line per call, so a longer ROADMAP costs one more line scan. A second id form (SG-NN) is the likely growth; it is out of scope here (see `## Out of Scope`). The id check reads `box_id_re slug`, so adding SG-NN later means accepting a second id row and a second line shape. The audit and attempt code stay as they are.
- Units, each testable alone through the CLI and fixtures:
  - `_tick_audit`: one PR number in, one verdict line out (`MERGED <oid> <base>` or a refusal). It reads gh only.
  - `_tick_line`: the ROADMAP text, the id and the PR in; the new line or a refusal out. Pure text.
  - `_tick_attempt`: the task id in; the attempt id to commit, `none`, or a refusal out. It reads `attempt-state.sh status` only.
  - `cmd_tick`: runs the checks in order, then takes the lock, writes, and records.

### Architecture

See `## Design` below.

## Picture

```
  operator / lead
       |
       |  mega tick <mega> <NN-slug> --pr N [--note T | --keep-note]
       v
  +-----------------------------+
  | lib/mega/mega.sh cmd_tick   |
  +-----------------------------+
     |  1 ledger branch      |  2 gh audit            |  3 line + attempt checks
     v                       v                        v
  kit_default_branch_here   gh pr view N (code-root)  ROADMAP.md (read)
  + current branch of the    state, mergeCommit,      attempt-state.sh status
    ROADMAP checkout         baseRefName, headRef     <NN-slug>
     |                       |                        |
     +---------- any refusal: exit != 0, nothing written ----------+
                             |
                             v  all pass
              <megadir>/.orchestrate/flip.lock  (mkdir lock)
                             |
                             v
              ROADMAP.md  (one line rewritten, temp file + mv)
                             |
                             v
              attempt-state.sh commit-result <NN-slug> <aid> PR#N@<sha7>
```

## Design

Design-bearing: it adds a write verb to a read-only module and defines a CLI contract that leads and scripts will depend on.

**Ordering:** the CLI contract (args, exits, output lines) first, then the line format, then the check order, then the lock.

### Approaches considered + chosen

See `## Solution`. No new tradeoff appears in the design view.

### Diagram

The check order as a flowchart (ASCII; this repo's operator rule forbids mermaid):

```
 args ok? --no--> exit 64
   | yes
 ROADMAP checkout on a named, non-default branch? --no--> exit 4
   | yes
 gh: state MERGED, oid 40-hex, base == code-root default? --no--> exit 1
   | yes
 take flip.lock within 10 s? --no--> exit 7
   | yes
 exactly one open/done line for <id>; not parked;
 primary PR absent or == N; annotation rule holds? --no--> unlock, exit 3
   | yes
 attempt record: none | eligible attempt (live on dispatched, or winner on done)? --no--> unlock, exit 5
   | yes
 new line == current line? --yes--> UNCHANGED (no write)
   | no
 write temp + mv  --> TICKED
   |
 unlock
   |
 attempt record present? --no--> ATTEMPT none, exit 0
   | yes
 commit-result ok? --no--> exit 6 (ROADMAP already written; a re-run converges)
   | yes
 exit 0
```

### ADR link(s)

None. The choice is reversible (one verb, one file), and no irreversible decision is made.

### Boundaries & failure modes

Out of bounds: merging, pushing, committing, fetching, and any ROADMAP line other than the named one. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**CLI**

```
mega tick <mega-slug> <sub-id> --pr <N>
          [--note <text> | --keep-note]
          [--attempt <aid>]
          [--megagoals-root <path>] [--code-root <path>]
```

- `<mega-slug>`: the directory under the megagoals root that holds `ROADMAP.md`. The root resolves as `mega status` does: `--megagoals-root` > `$MEGAGOALS_ROOT` > `$REPO_ROOT/_meta/megagoals` > `<git toplevel of cwd>/_meta/megagoals`.
- `<sub-id>`: an `NN-slug` id. It must match `box_id_re slug` in full. An `SG-NN` id is refused with exit 64.
- `--pr <N>`: required, digits only.
- `--note <text>`: emit ` (<text>)` after the sha. The text must not contain a newline.
- `--keep-note`: keep the current line's trailing annotation verbatim (defined under "Line format"). `--note` and `--keep-note` together give exit 64.
- `--attempt <aid>`: commit this attempt id instead of the resolved one.
- `--code-root <path>`: the repo whose PRs and default branch are git truth. It resolves as `mega status` does: flag > `$CODE_ROOT` > git toplevel of cwd. `gh` runs with this directory as its working directory, as `gh pr view <N> --json state,mergeCommit,baseRefName,headRefName`.
- Environment seams, the same convention `mega status` already uses: `GH_BIN` (the gh binary), `ATTEMPT_STATE_BIN` (default: the sibling `lib/goal/attempt-state.sh`), `ATTEMPT_REGISTRY_DIR` (honored by attempt-state itself), `MEGA_TICK_LOCK_WAIT_SECS` (default 10, the lock wait before exit 7), and `MEGA_TICK_TEST_PAUSE_FILE` (tests only: after acquiring the lock, wait while this file exists, so a test can inspect the held lock).

**Line format** (written)

```
- [x] <NN-slug>, PR #<N>, merged <sha7>
- [x] <NN-slug>, PR #<N>, merged <sha7> (<annotation>)
```

- `- [x]` is built from `box_token done`, never spelled as a literal (the `tests/test-mega-box.sh` section 14 lint scans `lib/mega`).
- `<sha7>` is the first 7 characters of gh's `mergeCommit.oid`. It is never an argument and never read from the line or from local git.
- This is the format the VimMotion ROADMAP declares ("Format on completion: `- [x] NN-slug, PR #N, merged <sha>`"). `commands/mega.md` line 164 describes the SG-NN scaffold's done form as `- [x] SG-NN ... -- PR #N`. That form stays as it is, because SG-NN is out of scope.

**Line match** (read)

- A candidate line matches `^<box_re> <BOX_ID_RE>` (both from `lib/mega/box.sh`). Its captured id must EQUAL `<sub-id>`; a prefix match is not enough (`13-hintkit` never matches `13-hintkit-labels`).
- Primary PR: the first `PR #<digits>` in the line, the same parse `cmd_status` uses (`mega.sh:317`). Annotation text after it (`fix-forward PR #43`) never counts.
- Repairable ticked shape: a done-box line is rewritten only when it has the shape `<box> <id>, PR #<n>` optionally followed by `, merged` and one word with no space or `(`, optionally followed by ` (<text>)`, and nothing else but trailing spaces. This covers the canonical line, a wrong sha (`merged 2819920`), a non-sha word (`merged OPEN `), and a bare `merged`. Any other done-box line (for example the older kit form `- [x] 01-module-collapse (dwarves-kit), <prose>, PR #190 merged cb64f15 (<prose>)`) refuses with exit 3, so no prose is dropped in silence. The line is fixed by hand first.
- Existing annotation: the `<text>` of the ` (<text>)` group above, from the first ` (` after the merged word to the final `)`.
- An open-box line keeps nothing after its id. Its planning prose is replaced by the completion format, as the ROADMAP's own "Format on completion" rule says.

**Exit codes and output**

| Exit | Meaning | Writes |
|---|---|---|
| 0 | `TICKED` or `UNCHANGED`, and the attempt line | ROADMAP (TICKED only) and the attempt store (when a record exists) |
| 1 | gh audit refused: not MERGED, no merge commit oid, base is not the code-root default branch, gh failed or returned unparseable JSON, or no default branch resolves for code-root | nothing |
| 3 | line refused: no line for the id, more than one line, a parked box, a ticked line whose primary PR differs from `--pr`, a ticked line not in the repairable shape, `--keep-note` with no annotation, or an existing annotation with neither `--note` nor `--keep-note` | nothing |
| 4 | ledger checkout refused: the ROADMAP's checkout is on its default branch, HEAD is detached, or no default branch resolves | nothing |
| 5 | attempt refused before any write: a record exists and no attempt is eligible (see "Attempt record"). The stderr line names the task state and each attempt's state, and the way out: `--attempt <aid>` for an eligible attempt, or settle the record with `attempt-state.sh` first | nothing |
| 6 | the ROADMAP was written, then `attempt-state.sh commit-result` failed. Re-running the same command converges: the line reads UNCHANGED, and the commit is retried | ROADMAP only |
| 7 | `<megadir>/.orchestrate/flip.lock` stayed held for 10 s | nothing |
| 64 | usage error | nothing |

stdout on success, one line each, in this order:

```
AUDIT PR #96 MERGED base=develop head=feat/vn-40-drag-by-labels merge=0c471eb999dcbbcb51723e4ea22912d217e73fb8
TICKED 40-drag-by-labels: - [x] 40-drag-by-labels, PR #96, merged 0c471eb
COMMITTED 40-drag-by-labels attempt=a1 ref=PR#96@0c471eb
```

- The second line reads `UNCHANGED 40-drag-by-labels` when the new line equals the current one.
- The third line is `attempt-state.sh`'s own output, passed through (`COMMITTED ...` or `NOOP ... already committed ...`). It reads `ATTEMPT none 40-drag-by-labels (no attempt record)` when the store has no record for the id.
- Every refusal prints one line to stderr, `mega tick: REFUSED <reason>`, with the gh state, the line, or the branch it saw, and nothing to stdout.

**Attempt record**

- Task id = `<sub-id>`. This matches the real store (`44-uat-pack-release-gate.task`, see `## Grounding`).
- Ref = `PR#<N>@<sha7>`, the form the real lead already used (`winner=a1 ref=PR#96@0c471eb`).
- The attempt to commit is resolved before any write, from `attempt-state.sh status <sub-id>`. An attempt is ELIGIBLE only when `commit-result` will succeed on it, per the transition tables at `attempt-state.sh:63-75`: the task is `dispatched` and the attempt is `running` or `disconnected` (commit), or the task is `done` and the attempt is the `winner=` attempt (`NOOP`). Resolution: `--attempt` if given, and it must be eligible; else the one `running` or `disconnected` attempt of a `dispatched` task; else the `winner=` attempt of a `done` task; else exit 5. So a `lost` or `superseded` attempt, a task in state `lost` or `queued`, or a non-winner attempt on a done task all refuse before the ROADMAP is touched. Unknown task: no record, so no attempt call.
- The verb runs `attempt-state.sh` with `cwd = <code-root>`. The store therefore resolves under the code repo's git common dir, as it did when the lead dispatched from there. `ATTEMPT_REGISTRY_DIR` still overrides for tests.

**Invariants**

- Every refusal (exits 1, 3, 4, 5, 7, 64) leaves the ROADMAP bytes and the attempt store byte-identical.
- Lock protocol, matching `orchestrate.sh` `_lock` / `_lock_stale` / `_unlock` (lines 336 to 393): acquire with `mkdir <megadir>/.orchestrate/flip.lock`, then write the verb's own pid (`$$`) into `flip.lock/pid` at once. While the verb runs, that pid is alive, so the driver's `_lock_stale` reads the lock as fresh and never reclaims it mid-tick. Release only a lock whose `pid` is the verb's own: move the pid file aside (never `rm`), then `rmdir`, on every exit path after acquire (an EXIT trap).
- Only the one matched line changes. `diff` of the ROADMAP before and after shows exactly one `<` and one `>` line.
- The verb never runs `git commit`, `git push`, `git fetch`, or `gh pr merge`.
- The `gh pr view` statement carries a `# merged-ok: <reason>` marker (it reads one PR number the caller names), and the pinned count for `lib/mega/mega.sh` in `tests/test-shared-lookups.sh` goes from 2 to 3.

### Data model changes

None. The ROADMAP line format is the one the ROADMAP already declares; the attempt record uses the existing `commit-result` verb.

### API changes (endpoints, request/response shapes)

New CLI verb `mega tick` through `bin/mega` (which already forwards every verb). `mega.sh --help` lists it.

### UI changes (screens, components, interactions)

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-001: Add `cmd_tick` and its three helpers to `lib/mega/mega.sh`, wire `tick` into `main`, extend the header usage block and the `usage()` line range, source `lib/gate/default-branch-warn.sh` for `kit_default_branch_here`, add the `# merged-ok:` marker, and bump the pinned count in `tests/test-shared-lookups.sh`. Acceptance: every row of the Exit codes table is reachable; `bash tests/test-mega-box.sh` and `bash tests/test-shared-lookups.sh` pass; `bin/mega --help` prints a `tick` line.
- [ ] TASK-002: Add `tests/test-mega-tick.sh` with the fixture and cases in `## Test plan`, a `GH_BIN` stub keyed on the PR number that logs its argv, a fixture ledger repo with a bare origin and `origin/HEAD` set, and `ATTEMPT_REGISTRY_DIR` in a temp dir. Acceptance: the suite passes, and each negative control in `## Grounding` turns its named case red when its mutation is applied by hand.

### Phase 2: Docs

- [ ] TASK-003: Document the verb: `lib/mega/README.md` (entry point line, "read-only views" becomes "views plus one writer", tests line), and one line in `commands/mega.md` Step 4 telling the lead to record a merged sub-goal with `mega tick` instead of editing the line. Acceptance: `rg -n 'mega tick' lib/mega/README.md commands/mega.md` finds both.

## After state

- [ ] `bin/mega tick <mega-slug> 40-drag-by-labels --pr 96 --megagoals-root <fixture> --code-root <fixture>` against a fixture writes `- [x] 40-drag-by-labels, PR #96, merged 0c471eb`, checkable by `bash tests/test-mega-tick.sh`. (Today: no verb; the lead runs `gh` and `sed` by hand.)
- [ ] A line holding a wrong sha for the same PR (`merged 2819920` for PR #37) is rewritten to gh's `281992a`. (Today: it stays wrong until someone audits it.)
- [ ] An OPEN PR, a MERGED PR with no merge commit oid, and a PR merged into a non-default base each exit 1 with the ROADMAP unchanged. (Today: commit `3047044` shows `merged OPEN` written into a line.)
- [ ] A ledger checkout on its default branch exits 4 with nothing written.
- [ ] A dispatched task whose attempt is `running` ends `state=done winner=<aid> ref=PR#<N>@<sha7>` in `attempt-state.sh status`.
- [ ] `bash tests/test-mega-box.sh` and `bash tests/test-shared-lookups.sh` pass with the new writer in `lib/mega`.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover the happy path, the two incidents, and every refusal in the Exit codes table
- [ ] No regressions in existing functionality (`mega status`, `review`, `report`, `runs`, `labels` unchanged)

## Test plan

Fixture ROADMAP rows are copied from the real VimMotion ROADMAP (quoted in `## Grounding`), plus synthetic rows for the refusal cases:

```
- [x] 01-release-pipeline, PR #21, merged 06376c9 (human gate, merged by Han)
- [x] 07-axlive-press-ladder, PR #38, merged 1cbdac4 (G2 fix-forward PR #41, 8af731e; seam fix PR #72, 128b043)
- [x] 13-hintkit-labels, PR #37, merged 2819920
- [x] 21-app-shell-seams, PR #57, merged OPEN
- [ ] 40-drag-by-labels, prose, `auto`, PR #
- [ ] 44-uat-pack-release-gate, README, UAT plan ... held for Han. `gate`, PR #
- [~] 45-parked-thing, rehomed
- [ ] 46-dup-line, a
- [ ] 46-dup-line, b
```

The gh stub returns: PR 96 MERGED/develop/`0c471eb999dc...`; PR 37 MERGED/develop/`281992a3530e...`; PR 57 MERGED/develop/a fixed oid; PR 102 OPEN/develop/null; PR 103 MERGED/develop/null mergeCommit; PR 104 MERGED/base `feat/stack`/an oid; PR 105 exits 1 with no JSON; PR 106 OPEN/develop with a non-null oid (synthetic: gh never sends it, but it isolates the state check from the oid check).

Each case starts from a fresh copy of the fixture ROADMAP and a fresh attempt store, so no case depends on another's write.

| # | Case | Expect |
|---|---|---|
| C1 | tick 40 with PR 96, attempt `a1` running | exit 0; line `- [x] 40-drag-by-labels, PR #96, merged 0c471eb`; status `done winner=a1 ref=PR#96@0c471eb`; diff is exactly 1 `<` and 1 `>` |
| C2 | tick 13 with PR 37 and `--keep-note` refused (no annotation); without flags | exit 3 for `--keep-note`; then exit 0 and `merged 281992a` (wrong-sha repair) |
| C3 | tick 21 with PR 57 | exit 0; `merged OPEN` replaced by gh's sha7 |
| C4 | run C1 a second time | exit 0; `UNCHANGED`; attempt line `NOOP`; ROADMAP bytes identical |
| C5 | tick 44 with PR 102 (OPEN) | exit 1; ROADMAP and store unchanged |
| C6 | tick 44 with PR 103 (MERGED, null oid) | exit 1; unchanged |
| C7 | tick 44 with PR 104 (base `feat/stack`) | exit 1; unchanged |
| C8 | tick 44 with PR 105 (gh fails) | exit 1; unchanged |
| C9 | tick `99-missing` | exit 3; unchanged |
| C10 | tick `13-hintkit` (prefix of a real id) | exit 3; unchanged |
| C11 | tick 13 with PR 96 (ticked with PR #37) | exit 3; unchanged |
| C12 | tick 45 (parked) | exit 3; unchanged |
| C13 | tick 46 (two lines) | exit 3; unchanged |
| C14 | tick 07 with PR 38, no flags (line has an annotation) | exit 3; then with `--keep-note`, exit 0 and the annotation is kept verbatim |
| C15 | tick 01 with PR 21 and `--note "merged by Han"` | exit 0; line ends ` (merged by Han)` |
| C16 | ledger fixture checked out on its default branch | exit 4; unchanged |
| C17 | ledger fixture on a detached HEAD | exit 4; unchanged |
| C18 | attempt record `queued`, no live attempt, no `--attempt` | exit 5; ROADMAP unchanged |
| C19 | no attempt record for the id | exit 0; `ATTEMPT none`; store dir has no new file |
| C20b | while the verb holds the lock (paused through the `MEGA_TICK_TEST_PAUSE_FILE` seam: the verb waits while that file exists), source `orchestrate.sh` and call `_lock_stale` on the lock | returns 1 (fresh), and `flip.lock/pid` holds the verb's pid |
| C20 | flip.lock dir pre-created by another pid | exit 7 after the bounded wait (the test pins the wait to under 1 s through an env knob); unchanged |
| C21 | `SG-01` id, `--note` plus `--keep-note`, a missing or non-digit `--pr` | exit 64 each |
| C22 | `attempt-state.sh` stubbed to fail on commit-result | exit 6; ROADMAP written; a re-run with the real script converges to exit 0 |
| C23 | gh stub argv log | every call is `pr view <N> --json state,mergeCommit,baseRefName,headRefName` run from code-root; no `merge`, no `fetch` |
| C24 | tick 44 with PR 106 (OPEN, oid present) | exit 1; unchanged |
| C25 | store record for 44: task `dispatched`, `a1` `lost`, `a2` `running`; run with `--attempt a1`; then a done task with `--attempt` naming a non-winner | exit 5 each; unchanged. Without `--attempt` on the first record: exit 0, `a2` committed |
| C26 | ticked legacy line `- [x] 47-legacy (repo), prose, PR #190 merged cb64f15 (note)`, tick with PR 190 | exit 3; unchanged |

"Unchanged" means `cmp` of the ROADMAP against a pre-run copy, plus an `ls` of the attempt store dir against a pre-run listing.

## Verification

```
bash tests/test-mega-tick.sh && bash tests/test-mega-box.sh && bash tests/test-shared-lookups.sh && bash tests/test-mega.sh && bash tests/run-all.sh --changed
```

## Edge Cases

1. The ROADMAP sits behind a symlink (the kit's own `_meta` links to `dwarves-kit-internal`). The ledger branch check runs `git -C "$(dirname <roadmap>)"`, which resolves the link target's repo; the test covers a symlinked megagoals root.
2. Ledger and code are the same repo (VimMotion) or two repos (kit-modularity: ROADMAP in ops-toolkit, PRs in dwarves-kit). The branch check reads the ROADMAP's checkout; the default-branch check for the PR base reads code-root. The test uses two separate fixture repos.
3. gh can print a multi-line hint to stderr on `pr view` (seen in the PR 102 sample). The verb parses stdout JSON only and drops stderr; `## Grounding` shows the stdout-only read is the bare JSON object.
4. A rebase merge or a squash merge: gh's `mergeCommit.oid` is still the commit on the base branch, so it is taken as is.
5. The line ends with trailing whitespace (`merged OPEN ` in commit `3047044`). The rewrite drops it, because the new line is built and never edited in place.
6. The ROADMAP has CRLF line ends. Out of scope; every ROADMAP in the estate is LF. The verb refuses (exit 3, no line matches) instead of writing a mixed file.
7. `--note` text containing `)`. Accepted as is; `--keep-note` on a later tick takes everything up to the final `)`, so it round-trips.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| gh unavailable or unauthenticated | `gh` exits nonzero or prints no JSON | exit 1, nothing written; rerun once gh works |
| gh API shape change (field renamed) | `jq` yields empty `state` or `oid` | treated as not MERGED, exit 1; fail closed, never a sha-less tick |
| Lock left by a crashed run | `flip.lock` exists for 10 s | exit 7 naming the lock path and its recorded pid; the next driver `_lock` reclaims a dead holder, or the operator does. The verb never reclaims a lock it does not own. A tick that crashes after acquire leaves its own dead pid, which the driver's `_lock_stale` reclaims |
| Concurrent driver flip of the same file | the driver holds `flip.lock` | the verb waits, then re-reads the line under the lock |
| Attempt store write fails after the ROADMAP write | `commit-result` nonzero | exit 6; re-running converges (the line reads UNCHANGED, the commit is retried) |
| Wrong `--pr` for the sub-goal | the line already records another PR | exit 3 for a ticked line. An open line has no PR to compare; the operator's `--pr` is trusted, and the AUDIT line shows the head branch for a human check |

## Out of Scope

- SG-NN ids and the `- [x] SG-NN ... -- PR #N` form. `/kit:mega` scaffolds SG-NN today, but its done line keeps a title the `NN-slug` format drops; it needs its own line shape. This verb refuses SG-NN with exit 64 instead of guessing.
- Fixing `mega status`'s sha parse. It matches `PR #N merged <sha>` with no comma (`mega.sh:319`), so it never reads the sha of a `PR #N, merged <sha>` line. Classification does not use the sha, so nothing breaks today.
- A local `merge-base --is-ancestor` check of the merge commit against `origin/<default>`. That needs a fetch, a stale ref would refuse a good tick, and `wrap land`'s `_tree_verify` already owns the deeper tree check. gh's `baseRefName` equal to the default branch is the check here.
- Committing or pushing the ROADMAP change. The caller commits, as with every other kit write verb.
- Ticking several sub-goals in one call.

## Touches

- lib/mega/mega.sh
- lib/mega/README.md
- tests/test-mega-tick.sh
- tests/test-shared-lookups.sh
- commands/mega.md

## Decision Log

- DEC-001: the sha comes only from gh's `mergeCommit.oid`. Both incidents were a sha typed or copied by hand. Rejected: a `--sha` argument, and reading the sha from local git.
- DEC-002: the verb never reads `mergeable`. By the lead's account that field read `UNKNOWN` in the `merged OPEN` incident, and merge status is answered by `state` plus `mergeCommit`. Rejected: waiting for `mergeable` to settle.
- DEC-003: an existing annotation is kept only with `--keep-note`, and a ticked line that carries one refuses (exit 3) when neither `--note` nor `--keep-note` is given. The item said an annotation is kept "only when passed", and dropping a long fix-forward history in silence (line 07) loses data. Rejected: always keep it, which breaks the item's rule; and always drop it, which loses data.
- DEC-004: an absent attempt record is not an error (`ATTEMPT none`, exit 0). Not every run dispatches through `attempt-state.sh`, and the kit's own git dir has no `kit-attempts/` store at all. A record that exists but cannot be committed refuses before any write (exit 5). Rejected: always requiring a record, which would block human-merged sub-goals that were never dispatched.
- DEC-005: the ledger branch check refuses (exit 4) where `default-branch-warn.sh` only warns. The item asks for a refusal: a tick on the default branch is a commit that cannot land through a PR. The resolver `kit_default_branch_here` is reused; only the policy differs. A detached HEAD or an unresolved default also refuses (fail closed).
- DEC-006: the lock is `orchestrate.sh flip`'s own `<megadir>/.orchestrate/flip.lock`, taken with plain `mkdir` plus the pid file (the protocol in Invariants), a bounded 10 s wait, and no stale reclaim by the verb itself. Sharing the path keeps a running driver's flip and a lead's tick from interleaving. Rejected: sourcing all of `orchestrate.sh` for `_lock`, and extracting `_lock` into a shared file, which is a refactor of the driver outside this item.
- DEC-007: a ticked line whose primary PR equals `--pr` is rewritten (the repair path). This is what fixes the `2819920` and `merged OPEN` lines. An open line's PR field is not compared, because open lines carry `PR #` with no number.
- DEC-008: exit codes are distinct per refusal class (1, 3, 4, 5, 6, 7) so each negative control asserts its own code, not just "nonzero".

## Grounding

Live samples, read-only, taken 2026-11-25.

**gh PR shape, merged** (`cd /Users/tieubao/orca/workspaces/VimMotion/next-run-2`):

```
$ gh pr view 96 --json state,mergeCommit,baseRefName,number,headRefName
{"baseRefName":"develop","headRefName":"feat/vn-40-drag-by-labels","mergeCommit":{"oid":"0c471eb999dcbbcb51723e4ea22912d217e73fb8"},"number":96,"state":"MERGED"}

$ gh pr view 37 --json state,mergeCommit,baseRefName
{"baseRefName":"develop","mergeCommit":{"oid":"281992a3530ea05c37709663c04ea2514dec0654"},"state":"MERGED"}
```

**gh PR shape, open** (`mergeCommit` is `null`; gh also printed a multi-line `gh event listen` hint on stderr, not stdout):

```
$ gh pr view 102 --json state,mergeCommit,baseRefName,mergeable
{"baseRefName":"develop","mergeCommit":null,"mergeable":"MERGEABLE","state":"OPEN"}
```

**gh PR shape, closed without merge**: VimMotion has none in its last 30 closed PRs. Sampled from a public repo instead:

```
$ gh pr list -R cli/cli --state closed --limit 40 --json number,state,mergeCommit,baseRefName | jq -c '[.[]|select(.state=="CLOSED")][0]'
{"baseRefName":"trunk","mergeCommit":null,"number":15158,"state":"CLOSED"}
```

**gh streams: stdout alone is the bare JSON** (same PR, stderr dropped):

```
$ gh pr view 102 --json state,mergeCommit,baseRefName 2>/dev/null
{"baseRefName":"develop","mergeCommit":null,"state":"OPEN"}
```

**gh PR shape, missing PR** (grounds the PR 105 stub: nonzero exit, nothing on stdout):

```
$ gh pr view 99999 --json state; echo rc=$?
GraphQL: Could not resolve to a PullRequest with the number of 99999. (repository.pullRequest)
rc=1
$ gh pr view 99999 --json state 2>/dev/null | wc -c
       0
```

**gh PR shape, MERGED with a null mergeCommit**: not sampled; no such PR was found. The verb treats it as fail closed (exit 1), and C6 covers it with a stub.

**Default branch, both resolvers agree on the ledger repo**:

```
$ gh repo view --json defaultBranchRef,nameWithOwner
{"defaultBranchRef":{"name":"develop"},"nameWithOwner":"consolelabs/VimMotion"}
$ git symbolic-ref refs/remotes/origin/HEAD
refs/remotes/origin/develop
$ bash -c 'source "$1/lib/gate/default-branch-warn.sh"; printf "default=%s\n" "$(kit_default_branch_here .)"' _ <kit worktree>   # cwd: the VimMotion checkout
default=develop
$ git symbolic-ref --quiet --short HEAD
run/next-megagoal-2
```

**ROADMAP lines** (`git -C /Users/tieubao/orca/workspaces/VimMotion/next-run-2 show HEAD:docs/megagoals/01-human-first-upgrade/ROADMAP.md`):

```
Format on completion: `- [x] NN-slug, PR #N, merged <sha>`. A line is checked only with a PR number and a merge sha.
- [x] 01-release-pipeline, PR #21, merged 06376c9 (human gate, merged by Han)
- [x] 07-axlive-press-ladder, PR #38, merged 1cbdac4 (G2 fix-forward PR #41, 8af731e; G2 attempt 2 fix-forward PR #50, 02cf7ff; ...)
- [x] 13-hintkit-labels, PR #37, merged 281992a
- [x] 40-drag-by-labels, PR #96, merged 0c471eb (security rounds 1 to 4, SECURE at round 4; nil-source mouse events)
- [ ] 44-uat-pack-release-gate, README, UAT plan, upkeep record, sign-off block, grep proofs and RUN_REPORT are committed, and the PR is open and held for Han. `gate`, PR #
```

**The two incidents in that file's history**:

```
$ git show 8e749b2 -- docs/megagoals/01-human-first-upgrade/ROADMAP.md     # "docs(megagoal): fix 13 sha, log PR #98"
-- [x] 13-hintkit-labels, PR #37, merged 2819920
+- [x] 13-hintkit-labels, PR #37, merged 281992a

$ git log -p -- docs/megagoals/01-human-first-upgrade/ROADMAP.md           # commit 3047044 "docs(megagoal): tick 21, ..."
+- [x] 21-app-shell-seams, PR #57, merged OPEN 
```

**Attempt store** (VimMotion git common dir `/Users/tieubao/workspace/dwarvesf/VimMotion/.git/kit-attempts/`; task files are named by sub-goal id):

```
$ bash lib/goal/attempt-state.sh status 40-drag-by-labels
task=40-drag-by-labels state=done
winner=a1 ref=PR#96@0c471eb
attempt=a1 worker=<agent id> state=committed

$ bash lib/goal/attempt-state.sh status 44-uat-pack-release-gate
task=44-uat-pack-release-gate state=dispatched
attempt=a1 worker=<agent id> state=running
```

The dwarves-kit checkout has no `kit-attempts/` dir under its git common dir, which grounds DEC-004.

**Kit-internal shapes the verb must satisfy** (read at file:line, not external):
- `lib/mega/box.tsv`: done token `[x]`, alias `[X]`; slug id ERE `[0-9]+[A-Za-z]?-[A-Za-z][A-Za-z0-9_-]*`.
- `tests/test-shared-lookups.sh:57` `PAT_MERGED` matches `pr view ... --json ... state`, and line 112 pins `merged-ok lib/mega/mega.sh 2`.
- `lib/queue/orchestrate.sh:1003` lock path `$megadir/.orchestrate/flip.lock`.

### Negative-control dry traces

Each trace: the mutation to the new code, the fixture it reads, the path it then takes, and the case that goes red.

| NC | Mutation | Fixture read | Path after the mutation | Red case |
|---|---|---|---|---|
| NC1 | drop the `state == MERGED` test in `_tick_audit` | stub PR 106: `OPEN` with an oid (PR 102's real shape has a null oid, so the oid check would still refuse it; 106 isolates the state check) | the audit passes and the line is ticked for an unmerged PR | C24 expects exit 1 and `cmp` equal; gets 0 and a changed file |
| NC2 | drop the 40-hex oid check | stub PR 103: `MERGED`, `mergeCommit: null` | `jq -r .mergeCommit.oid` yields `null`; sha7 = `null`, written into the line (the `merged OPEN` class of bug) | C6 expects exit 1; gets 0 with `merged null` |
| NC3 | drop the base == default test | stub PR 104: base `feat/stack` | a stacked PR merged into a feature branch is ticked as done | C7 expects exit 1; gets 0 |
| NC4 | take the sha from the existing line when it is 7-hex | fixture line `13-hintkit-labels, PR #37, merged 2819920`, stub oid `281992a...` | the rewrite keeps `2819920` | C2 expects `merged 281992a`; finds `2819920` |
| NC5 | match the id by prefix (`index($0, "- [x] " id) == 1`) | fixture has only `13-hintkit-labels`; arg `13-hintkit` | the prefix hits the 13 line, and it is rewritten under the wrong id | C10 expects exit 3 and `cmp` equal; gets 0 and a changed file |
| NC6 | skip the primary PR compare on a ticked line | fixture 13 records PR #37; arg `--pr 96` | the line is rewritten to PR #96 | C11 expects exit 3; gets 0 |
| NC7 | take the LAST `PR #n` as primary | fixture 07: `PR #38 ... PR #72` | the primary PR reads 72, so `--pr 38` refuses | C14's `--keep-note` run expects exit 0; gets 3 |
| NC8 | skip the ledger branch check | ledger fixture on `main` (its default) | the line is written on the default branch | C16 expects exit 4; gets 0 |
| NC9 | treat a detached HEAD's empty branch as "not default" | ledger fixture with HEAD detached | the write proceeds | C17 expects exit 4; gets 0 |
| NC10 | skip `commit-result` | store record `44...`: dispatched, `a1` running (shape of the real record) | ROADMAP ticked, store still `dispatched` | C1 expects `state=done winner=a1`; reads `dispatched` |
| NC11 | resolve the attempt after the ROADMAP write | store record `queued` with no live attempt | ROADMAP written, then exit 5 | C18 expects `cmp` equal; the file changed |
| NC12 | drop the annotation refusal | fixture 07 with its fix-forward annotation, no flags | the annotation is silently dropped | C14 expects exit 3; gets 0 and a shorter line |
| NC13 | write before taking the lock | lock dir pre-created by the test | the write proceeds under another holder | C20 expects exit 7 and `cmp` equal; gets 0 |
| NC14 | write the box as a literal `- [x]` | none (static lint) | the section 14 scan of `lib/mega` hits the new line | `tests/test-mega-box.sh` "no reader hardcodes the box grammar" fails |
| NC15 | omit the `# merged-ok:` marker on `gh pr view` | none (static lint) | `PAT_MERGED` hits an unmarked statement | `tests/test-shared-lookups.sh` reports `UNMARKED merged lib/mega/mega.sh` |
| NC16 | accept any `--attempt` that appears in `status` | C25 record: `a1` `lost` | the ROADMAP is written, then `commit-result` hits the illegal `lost -> committed` move and exits 6, on every re-run | C25 expects exit 5 and `cmp` equal; gets 6 and a changed file |
| NC17 | drop the repairable-shape check on ticked lines | C26 legacy line with prose | the line is rewritten and its `(repo), prose` and note are lost | C26 expects exit 3; gets 0 |
| NC18 | omit the pid write after `mkdir` | a driver `_lock` racing the tick, simulated by calling `_lock_stale` on the held lock with `FLIP_LOCK_STALE_SECS=0` | an absent pid reads stale past the timeout, so the driver reclaims a live tick's lock | C20b: while the verb holds the lock (paused through a test seam), `_lock_stale` must return 1 (fresh); it returns 0 |

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
