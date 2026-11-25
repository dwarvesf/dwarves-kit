# Spec: mega tick, record a merged sub-goal from gh truth

Generated: 2026-11-25
Status: DRAFT
Lane: full
Depth: standard (every external shape the verb reads is sampled live in ## Grounding except a MERGED PR with a null merge commit, which no sampled repo held and a stub case covers; the code it extends is read at line level)
Type: spec-feature
File: `docs/specs/SPEC-430-mega-tick-verb.md`
References: `lib/queue/orchestrate.sh` `cmd_flip` (lines 990 to 1020: the one existing ROADMAP writer; imitate its lock path, its re-read under the lock, its write-temp-then-`mv`, and its use of `box_token` instead of a literal box) and `_lock` / `_lock_stale` / `_lock_reclaim` / `_unlock` (lines 336 to 393: the lock protocol to match); `lib/mega/mega.sh` `cmd_status` and `_sub_branch` (lines 185 to 364: root resolution, the line loop over `box_re` plus `BOX_ID_RE`, the first-`PR #<n>` parse, the goal file's `**Branch:**` line); `lib/gate/default-branch-warn.sh` `kit_default_branch_here` (the default-branch resolver to reuse, not copy); `lib/goal/attempt-state.sh` `dir`, `status`, `commit-result` (the attempt store, read and written through its CLI only); `lib/board/work.sh` `src_orca` (line 155: the `timeout`/`gtimeout` bound on an external CLI)

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
- Units, each one purpose:
  - `_tick_args`: argv in; validated values or exit 64 / exit 3 out.
  - `_tick_audit`: one PR number and the code-root in; one verdict (`repo`, `base`, `head`, `oid`) or a refusal out. It reads gh only.
  - `_tick_store`: the sub-id and the two roots in; the store dir holding the record, `none <dirs>`, or a refusal out. It runs `attempt-state.sh dir` and `status` only.
  - `_tick_lock` / `_tick_unlock`: the megadir in; the held lock or a refusal out.
  - `_tick_line`: the ROADMAP text, the id, the PR, the oid and the note mode in; the line number and new line, or a refusal out. Pure text.
  - `cmd_tick`: runs the units in the order of the Design flowchart, then writes and records.

### Architecture

See `## Design` below.

## Picture

The same order as the Design flowchart; every arrow down is "passed".

```
  mega tick <mega-slug> <NN-slug> --pr N [--note T | --keep-note] [--attempt A | --no-attempt]
       |
       v
  [1] _tick_args ............................ exit 64 (or 3 for a note with a control char)
       |
  [2] ledger checkout: ROADMAP.md regular file (8);
      branch named and != kit_default_branch_here ..................... exit 4
       |
  [3] _tick_audit: gh pr view N  (cwd = code-root)
      state MERGED, oid 40-hex, base == code-root default,
      url names PR N ........................................ exit 1
       |
  [4] normalized goal file **Branch:** == headRefName, or --branch-override,
      or BRANCH unverified ............................................ exit 3
       |
  [5] _tick_store: attempt-state.sh dir (code-root, ledger), status <id> ... exit 5
       |
  [6] _tick_lock: mkdir -p .orchestrate; mkdir flip.lock; pid ......... exit 7 / 8
       |
  [7] _tick_line (under the lock) ............................ unlock, exit 3
       |
  [8] new line == current? -- yes --> UNCHANGED (no write)
       | no
  [9] mktemp + awk(ENVIRON, old line must still match) + chmod + mv ... unlock, exit 8
       |
  [10] unlock
       |
  [11] attempt-state.sh commit-result <id> <aid> PR#N@<sha7> ......... exit 6
       |
       v
     exit 0
```

## Design

Design-bearing: it adds a write verb to a read-only module and defines a CLI contract that leads and scripts will depend on. The chosen approach is a new `mega tick` verb in `lib/mega/mega.sh` (Solution approach 1), not a flag on `mega-merge.sh` and not a `wrap` hook, because only a verb keyed on the PR number serves human merges, `wrap` merges and driver merges alike.

**Ordering:** the CLI contract (args, exits, output lines) first, then the line format, then the check order, then the lock and the attempt store.

### Approaches considered + chosen

See `## Solution`. No new tradeoff appears in the design view.

### Diagram

The check order as a flowchart (ASCII; this repo's operator rule forbids mermaid). Steps match the Picture numbers.

```
 [1] args valid? ---------------------------------------- no --> exit 64 (note control char: exit 3)
   | yes
 [2] ROADMAP.md a regular file, not a symlink? ----------- no --> exit 8
     ledger HEAD on a named branch, default resolves,
     branch != default? ---------------------------------- no --> exit 4
   | yes
 [3] gh, jq present; gh ok within the timeout; JSON parses;
     state MERGED; oid 40-hex; base == code-root default;
     url is .../<owner>/<name>/pull/<N>? --------------- no --> exit 1
   | yes
 [4] goal file Branch resolves (after normalizing)? -- no --> print BRANCH unverified, go on
       | yes: == headRefName as a literal, or --branch-override? -- no --> exit 3
   | yes
 [5] attempt stores resolve; record in at most one store;
     record eligible, or positively absent, or --no-attempt with no record? -- no --> exit 5
   | yes
 [6] mkdir -p .orchestrate ok? --------------------------- no --> exit 8
     mkdir flip.lock: ok, or dir exists with a dead pid (reclaim, retry)?
       dir exists, live or no pid, past the wait --------------> exit 7
       mkdir failed and no dir exists ----------------------> exit 8
   | held
 [7] exactly one line for <id>; no CR; not parked; repairable shape;
     primary PR absent or == N; no other line names PR #N;
     annotation rule; kept annotation has no control char? -- no --> unlock, exit 3
   | yes
 [8] new line == current line? -- yes --> UNCHANGED, skip [9]
   | no
 [9] mktemp; record TICK_NR still == the line read in [7];
     write, chmod, mv ok? ------------------------------- no --> unlock, exit 8 (original intact)
   | yes: TICKED
 [10] unlock
 [11] record found? -- no --> ATTEMPT none / skipped, exit 0
       | yes: commit-result ok? -------------------------- no --> exit 6
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
          [--attempt <aid> | --no-attempt]
          [--branch-override <reason>]
          [--megagoals-root <path>] [--code-root <path>]

example (VimMotion keeps its megas under docs/megagoals):
  bin/mega tick 01-human-first-upgrade 40-drag-by-labels --pr 96 --megagoals-root docs/megagoals
```

- `<mega-slug>`: must match `^[A-Za-z0-9][A-Za-z0-9._-]*$` and must not contain `..`, else exit 64. It names the directory under the megagoals root that holds `ROADMAP.md`. The root resolves as `mega status` does: `--megagoals-root` > `$MEGAGOALS_ROOT` > `$REPO_ROOT/_meta/megagoals` > `<git toplevel of cwd>/_meta/megagoals`. The usage text names `--megagoals-root` for repos that keep megas elsewhere (VimMotion: `docs/megagoals`).
- `<sub-id>`: an `NN-slug` id. It must match `box_id_re slug` in full. An `SG-NN` id is refused with exit 64.
- `--pr <N>`: required, `^[1-9][0-9]{0,8}$` (no leading zero, at most 9 digits), else exit 64.
- `--note <text>`: emit ` (<text>)` after the sha. A note holding any control character (bytes 0x00 to 0x1f, or 0x7f) refuses with exit 3. Backslashes and every printable byte are kept verbatim.
- `--keep-note`: keep the current line's annotation verbatim (defined under "Line match"). `--note` and `--keep-note` together give exit 64.
- `--attempt <aid>`: commit this attempt id instead of the resolved one. `--no-attempt`: record nothing in the attempt store (see "Attempt record"). Both together give exit 64.
- `--branch-override <reason>`: accept a goal-file branch that differs from the PR head (a renamed or replacement branch). The reason follows the note rules (no control character, at most 200 bytes, else exit 3) and is printed on the AUDIT line as `branch-override=<reason, printf %q>`; the BRANCH line then reads `BRANCH override <goal branch> != <head>`.
- Text checks: every control-character test runs under `LC_ALL=C` over bytes 0x00 to 0x1f and 0x7f. A `--note` longer than 200 bytes is exit 3.
- `--code-root <path>`: the repo whose PRs and default branch are git truth. It resolves as `mega status` does: flag > `$CODE_ROOT` > git toplevel of cwd.
- Dependencies: `gh` and `jq` on `PATH` (or `GH_BIN`). Either missing gives exit 1, named on stderr.
- Environment seams, the convention `mega status` already uses: `GH_BIN`; `ATTEMPT_STATE_BIN` (default: the sibling `lib/goal/attempt-state.sh`); `ATTEMPT_REGISTRY_DIR` (when set, the only store); `MEGA_TICK_GH_TIMEOUT_S` (default 30; applied through `timeout` or `gtimeout` when one exists, as `lib/board/work.sh` does, and unbounded when neither exists); `MEGA_TICK_LOCK_WAIT_SECS` (default 10; accepts `0` or a decimal such as `0.5`; the poll interval is 0.2 s, so the wait is `ceil(wait / 0.2)` polls); `MEGA_TICK_TEST=1` plus `MEGA_TICK_TEST_PAUSE_FILE` (tests only: with both set, after taking the lock and reading the matched line, before the write, the verb waits while that file exists, at most 30 s; without `MEGA_TICK_TEST=1` the pause file is ignored).

**gh read** (one call, `cwd = <code-root>`, stdout parsed, stderr kept only for its first line)

```
GH_PROMPT_DISABLED=1 gh pr view <N> --json state,mergeCommit,baseRefName,headRefName,url </dev/null
```

- stdin is `/dev/null` and `GH_PROMPT_DISABLED=1` is set, so gh can never block on a prompt. The timeout is `MEGA_TICK_GH_TIMEOUT_S` through `timeout` or `gtimeout`; on a host with neither, the call is unbounded (the `lib/board/work.sh` precedent), and the usage text says so.

- Audit passes only when: `state == "MERGED"`; `mergeCommit.oid` is 40 lowercase hex; `baseRefName` equals `kit_default_branch_here <code-root>`; `url` matches `https://<host>/<owner>/<name>/pull/<N>` with `<N>` equal to `--pr`. `<owner>/<name>` is the repo the AUDIT line prints.
- Every PR-sourced string (`baseRefName`, `headRefName`, `url`) is refused (exit 1) when it is longer than 255 bytes or holds a control character. These strings are always quoted, never passed to `eval`, never word-split, and never interpolated into an `awk -v` or `sed` program.
- gh nonzero, timeout, empty stdout, or JSON `jq` cannot parse: exit 1, and the stderr line carries gh's first stderr line (control bytes stripped, cut to 200 bytes).
- `MERGED` with a null `mergeCommit`: exit 1 with "merged but gh has no merge commit yet; retry shortly".
- Every untrusted string printed in a message (gh stderr, a `**Branch:**` value, a PR string, a reason) has its control bytes stripped first. Every recovery command printed (exit 6, exit 7) is built with `printf %q` per argument, so it can be pasted as is.
- No default branch resolves for code-root: exit 1, and stderr names the resolver (`kit_default_branch_here`: `origin/HEAD`, then `origin/main`, then `origin/master`) and the fix `git -C <code-root> remote set-head origin -a`.

**Goal-file branch check**

- The goal file is `<megadir>/goals/<sub-id>.md`, read through the existing `_sub_branch` (its `**Branch:** <rest of line>`). `_sub_branch` itself is not changed, so `mega status` keeps its raw value.
- Normalize the value in `_tick_branch_norm`, in this order: strip one trailing CR; strip one trailing ` (...)` group (real shape: `ci/release-pipeline (existing)`); trim surrounding whitespace; strip one surrounding pair of backticks; trim again. An empty result counts as "no branch line".
- Compare the normalized value to gh `headRefName` as a quoted literal string (`[ "$goal" = "$head" ]`), never as an unquoted `[[ == ]]` pattern, so a value such as `feat/*` matches only itself.
- Mismatch: exit 3, naming both (control bytes stripped), unless `--branch-override <reason>` is given. This catches a wrong `--pr` on an open line.
- No goal file or no `**Branch:**` line: stdout `BRANCH unverified <sub-id> (no **Branch:** line in goals/<sub-id>.md)`, and the verb continues.
- Match: stdout `BRANCH ok <name>`.

**Line format** (written)

```
- [x] <NN-slug>, PR #<N>, merged <sha7>
- [x] <NN-slug>, PR #<N>, merged <sha7> (<annotation>)
```

- `- [x]` is built from `box_token done`, never spelled as a literal (the `tests/test-mega-box.sh` section 14 lint scans `lib/mega`).
- `<sha7>` is the first 7 characters of gh's `mergeCommit.oid`. It is never an argument and never read from the line or from local git.
- This is the format the VimMotion ROADMAP declares ("Format on completion: `- [x] NN-slug, PR #N, merged <sha>`"). `commands/mega.md` line 164 describes the SG-NN scaffold's done form as `- [x] SG-NN ... -- PR #N`. That form stays as it is, because SG-NN is out of scope.
- The new line is built by bash string concatenation and reaches the writer only through the environment: `awk` reads `ENVIRON["TICK_NR"]`, `ENVIRON["TICK_OLD"]` and `ENVIRON["TICK_LINE"]`, prints `TICK_LINE` for record `TICK_NR` only when that record still equals `TICK_OLD`, prints every other record unchanged, and exits nonzero when record `TICK_NR` no longer equals `TICK_OLD` (exit 8, temp moved aside). `awk -v` is never used for it, because `-v` expands backslash escapes (`\n` in a note would forge a second line). No `sed` program ever holds note text.

**Line match** (read, under the lock)

- A candidate line matches `^<box_re> <BOX_ID_RE>` (both from `lib/mega/box.sh`). Its captured id must EQUAL `<sub-id>`; a prefix match is not enough (`13-hintkit` never matches `13-hintkit-labels`). Zero or more than one candidate: exit 3.
- A matched line ending in `\r` (CRLF file): exit 3. The verb never writes a mixed-ending file.
- A parked box (`box_name` is `parked`): exit 3.
- Primary PR: the first `PR #<digits>` in the line, the same parse `cmd_status` uses (`mega.sh:317`). Annotation text after it (`fix-forward PR #43`) never counts.
- PR numbers are compared as exact strings (`PR #093` is not `93`; a mismatch refuses).
- Another DONE-box sub-goal line (any other id) whose primary PR is `<N>`: exit 3. One PR closes one sub-goal. Open and parked lines are not read for this rule, because open-line prose may cite a PR (`see PR #96`) without owning it.
- Repairable ticked shape: a done-box line is rewritten only when it has the shape `<box> <id>, PR #<n>` optionally followed by `, merged` and one word with no space or `(`, optionally followed by ` (<text>)`, and nothing else but trailing spaces. This covers the canonical line, a wrong sha (`merged 2819920`), a non-sha word (`merged OPEN `), and a bare `merged`. Any other done-box line (for example the older kit form `- [x] 01-module-collapse (dwarves-kit), <prose>, PR #190 merged cb64f15 (<prose>)`) refuses with exit 3, so no prose is dropped in silence; it is fixed by hand first.
- A ticked line whose primary PR differs from `--pr`: exit 3.
- Existing annotation: the `<text>` of the ` (<text>)` group above, from the first ` (` after the merged word to the final `)`. A ticked line that has one refuses (exit 3) unless `--note` or `--keep-note` is given. `--keep-note` with no annotation, or with an annotation holding a control character: exit 3.
- An open-box line keeps nothing after its id. Its planning prose is replaced by the completion format, as the ROADMAP's own "Format on completion" rule says.

**Lock** (shared with `orchestrate.sh flip`)

- Path: `<megadir>/.orchestrate/flip.lock`. First `mkdir -p <megadir>/.orchestrate`; a failure there is exit 8. (The VimMotion mega dir has no `.orchestrate/`; see `## Grounding`.)
- Acquire: `mkdir flip.lock`, then write the verb's pid (`$$`) to `flip.lock/pid` at once. While the verb runs that pid is alive, so the driver's `_lock_stale` reads the lock as fresh and never reclaims it mid-tick.
- `mkdir flip.lock` fails and the dir exists: the lock is held. If `flip.lock/pid` holds a pid that `kill -0` reports dead, reclaim it by the driver's rule (move the pid file aside to `${TMPDIR:-/tmp}`, never `rm`, then `rmdir`) and retry. A live pid, or no pid file, is waited on until `MEGA_TICK_LOCK_WAIT_SECS`, then exit 7.
- `mkdir flip.lock` fails and no dir exists (permissions, read-only file system): exit 8, with the `mkdir` error.
- Exit 7 stderr names the path, the recorded pid (or "no pid file"), and the exact recovery command: for a live pid, "retry once pid <p> exits"; for no pid file, `rmdir '<path>'` once no driver is running.
- Release, on every exit path after acquire (an EXIT trap): only when `flip.lock/pid` holds the verb's own pid; move the pid file aside, then `rmdir`. The same trap moves any `.roadmap.tick.*` temp file this run created aside (never `rm`).

**Write**

- ROADMAP.md must be a regular file and not a symlink (`[ -f ] && [ ! -L ]`), checked at step 2: else exit 8. A symlinked megagoals root directory is fine (Edge case 1); only the file itself may not be a link.
- `tmp=$(mktemp "<megadir>/.roadmap.tick.XXXXXX")`, the awk write above into `tmp`, `chmod` `tmp` to the original file's mode (read with `stat -c %a`, falling back to `stat -f %Lp`, the pair `orchestrate.sh _mtime` uses for portability), then `mv -f tmp ROADMAP.md`.
- Any step failing: the temp file is moved aside (never `rm`), the original ROADMAP is untouched, and the exit is 8.

**Attempt record**

- Task id = `<sub-id>`, ref = `PR#<N>@<sha7>`. Both match the real store (`40-drag-by-labels.task`, `ref=PR#96@0c471eb`; see `## Grounding`).
- Candidate stores: with `ATTEMPT_REGISTRY_DIR` set, that dir only. Otherwise `attempt-state.sh dir` run once with `cwd = <code-root>` and once with `cwd = <ledger checkout toplevel>`, deduplicated by path. In the same-repo layout (VimMotion) both give one dir. In the two-repo layout (ROADMAP in one repo, PRs in another) the lead may have dispatched from either, because `commands/dispatch.md` runs `attempt-state.sh` from the lead's own checkout, so both are probed.
- A `dir` call that fails (exit nonzero, empty path): exit 5, naming the root. A store that cannot resolve is never read as "no record".
- A record is the regular file `<dir>/<sub-id>.task`. Found in two distinct stores: exit 5, naming both. Found in one: every later `attempt-state.sh` call runs with `ATTEMPT_REGISTRY_DIR=<that dir>`, so it reads and writes exactly that store.
- Positive "no record": at least one candidate dir exists as a directory and none holds `<sub-id>.task`. Stdout: `ATTEMPT none <sub-id> (no <sub-id>.task in <dir>[, <dir>])`; exit 0. No candidate dir exists at all: exit 5, with the hint "pass --no-attempt if this mega never dispatched through attempt-state".
- `--no-attempt`: skip the store, stdout `ATTEMPT skipped <sub-id> (--no-attempt)`. A record found in any candidate store still refuses (exit 5): an explicit skip never hides a live dispatch.
- Eligibility, decided before any write from `attempt-state.sh status <sub-id>`, per the transition tables at `attempt-state.sh:63-75`: an attempt is eligible when the task is `dispatched` and the attempt is `running` or `disconnected` (commit), or the task is `done` and the attempt is the `winner=` attempt (`NOOP`). Resolution: `--attempt` if given, matched by exact field equality on the `attempt=<aid>` field, and it must be eligible (with no record anywhere, `--attempt` is exit 5); else the one `running` or `disconnected` attempt of a `dispatched` task (two or more live attempts with no `--attempt`: exit 5, naming the candidates); else the `winner=` attempt of a `done` task; else exit 5. A `lost` or `superseded` attempt, a task in state `lost` or `queued`, and a non-winner on a done task all refuse before the ROADMAP is touched. The exit 5 stderr names the task state, each attempt's state, and the way out (`--attempt <aid>` for an eligible attempt, or settle the record with `attempt-state.sh` first).
- Done task: when its `ref=` differs from the new `PR#<N>@<sha7>`, stderr prints `ATTEMPT ref-mismatch <sub-id> recorded=<ref> now=<ref>`. The exit code is unaffected (a done record has no legal move).

**Exit codes and output**

| Exit | Meaning | Writes |
|---|---|---|
| 0 | `TICKED` or `UNCHANGED`, plus the attempt line | ROADMAP (TICKED only); the attempt store (when a record exists) |
| 1 | gh audit refused: gh or jq missing, gh failed or timed out, unparseable JSON, not MERGED, no 40-hex oid, base is not the code-root default, no default resolves for code-root, url does not name PR N, or a PR string over 255 bytes or with a control character | nothing |
| 3 | content refused: note or override reason with a control character or over 200 bytes, goal-file branch (normalized) differs from the PR head without `--branch-override`, no line or more than one, CR line end, parked box, line not in the repairable shape, primary PR differs, another done line already names PR N, annotation rule broken, kept annotation with a control character | nothing |
| 4 | ledger checkout refused: on its default branch, HEAD detached, or no default branch resolves (stderr names the resolver and `git remote set-head origin -a`) | nothing |
| 5 | attempt refused before any write: a store cannot resolve, `--attempt` with no record, two live attempts without `--attempt`, a record in two stores, no store dir at all without `--no-attempt`, `--no-attempt` with a record present, or no eligible attempt | nothing |
| 6 | the ROADMAP was written, then `commit-result` failed. Stderr: "ROADMAP written; settle the record: re-run the same command with the same flags (the line reads UNCHANGED and the commit is retried), or run `ATTEMPT_REGISTRY_DIR=<dir> attempt-state.sh commit-result <id> <aid> PR#<N>@<sha7>`", each argument quoted with `printf %q` | ROADMAP only |
| 7 | `flip.lock` held by a live pid, or with no pid file, past the wait; stderr gives the recovery command | nothing |
| 8 | write path refused: ROADMAP.md is a symlink or not a regular file, the matched record changed between read and write, `.orchestrate/` or the lock dir cannot be created for a reason other than "exists", or `mktemp` / write / `chmod` / `mv` failed | nothing (the original file is intact) |
| 64 | usage error | nothing |

stdout on success, one line each, in this order:

```
AUDIT consolelabs/VimMotion PR #96 MERGED base=develop head=feat/vn-40-drag-by-labels merge=0c471eb999dcbbcb51723e4ea22912d217e73fb8
BRANCH ok feat/vn-40-drag-by-labels
TICKED 40-drag-by-labels: - [x] 40-drag-by-labels, PR #96, merged 0c471eb
COMMITTED 40-drag-by-labels attempt=a1 ref=PR#96@0c471eb
```

- Line 2 reads `BRANCH unverified ...` when no goal-file branch resolves.
- Line 3 reads `UNCHANGED 40-drag-by-labels` when the new line equals the current one.
- Line 4 is `attempt-state.sh`'s own output passed through (`COMMITTED ...` or `NOOP ... already committed ...`), or `ATTEMPT none ...` / `ATTEMPT skipped ...`.
- Every refusal prints one line to stderr, `mega tick: REFUSED <reason>`, with what it saw, and nothing more to stdout.

**Invariants**

- Every refusal except exit 6 leaves the ROADMAP bytes and the attempt store byte-identical.
- For a ROADMAP that ends in a newline, only the matched line changes: `diff` shows exactly one `<` and one `>` line. A file whose last byte is not a newline gains one (awk's output record separator); this is the one other byte that can change.
- Note text and kept annotations round-trip byte-exact, backslashes included.
- The verb never runs `git commit`, `git push`, `git fetch`, `gh pr merge`, or `eval`.
- The `gh pr view` statement carries a `# merged-ok: <reason>` marker (it reads one PR number the caller names), and the pinned count for `lib/mega/mega.sh` in `tests/test-shared-lookups.sh` goes from 2 to 3.

### Data model changes

None. The ROADMAP line format is the one the ROADMAP already declares; the attempt record uses the existing `commit-result` verb.

### API changes (endpoints, request/response shapes)

New CLI verb `mega tick` through `bin/mega` (which already forwards every verb). `mega.sh --help` lists it with the `--megagoals-root docs/megagoals` example.

### UI changes (screens, components, interactions)

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-001: Add the helpers `_tick_args`, `_tick_audit`, `_tick_branch_norm`, `_tick_store`, `_tick_lock`, `_tick_unlock` and `_tick_line` to `lib/mega/mega.sh`; wrap the bottom `main "$@"` in the `[ "${BASH_SOURCE[0]}" = "$0" ]` guard (the `attempt-state.sh` pattern) so the helpers can be sourced; source `lib/gate/default-branch-warn.sh` for `kit_default_branch_here`; add the `# merged-ok:` marker on the gh statement; bump the pinned count in `tests/test-shared-lookups.sh`. Acceptance: `bash -n lib/mega/mega.sh`; a one-line `bash -c` that sources `lib/mega/mega.sh` and calls `_tick_branch_norm` on the three fixture shapes (suffixed ` (existing)`, backticked, CR-ended) prints `ci/release-pipeline`, `feat/13`, `feat/x`; `bash tests/test-mega-box.sh` and `bash tests/test-shared-lookups.sh` pass.
- [ ] TASK-002: depends: TASK-001. Add `cmd_tick` in the flowchart order, wire `tick` into `main`, extend the header usage block and the `usage()` line range with the `--megagoals-root docs/megagoals` example, and update the `# Usage:` comment in `bin/mega` to name `tick`. Acceptance: `bin/mega --help` prints a `tick` line; `bin/mega tick` with no args exits 64.

### Phase 2: Tests

- [ ] TASK-003: depends: TASK-001, TASK-002. Create `tests/test-mega-tick.sh` with the fixtures of `## Test plan` (the `GH_BIN` stub keyed on the PR number that logs argv and cwd, a ledger repo and a separate code repo each with a bare origin and `origin/HEAD` set, the goal-file dir, attempt stores in both git dirs) and the audit, branch and line cases C1 to C25 plus C48 to C51. Acceptance: those cases pass, and NC1 to NC7, NC18 to NC23 and NC34 to NC36 turn their named case red when applied by hand.
- [ ] TASK-004: depends: TASK-003. Add the ledger, attempt, lock and write cases C26 to C47 to the same suite. Acceptance: the whole suite passes, and NC8 to NC17 and NC24 to NC33 turn their named case red when applied by hand.

### Phase 3: Docs

- [ ] TASK-005: depends: TASK-002. Document the verb in `lib/mega/README.md` (entry-point line, "read-only views" becomes "views plus one writer", tests line) in `lib/README.md` (the mega module's one-line entry, if it names verbs), and in `docs/WORKFLOW.md` "## Mega-goal delegate execution", at the point where a sub-goal closes ("box flipped"): an NN-slug ROADMAP line is closed with `mega tick`, never a hand edit. Acceptance: `rg -n 'mega tick' lib/mega/README.md docs/WORKFLOW.md` finds both.

## After state

- [ ] `bin/mega tick <mega-slug> 40-drag-by-labels --pr 96 --megagoals-root <fixture> --code-root <fixture>` writes `- [x] 40-drag-by-labels, PR #96, merged 0c471eb`, checkable by `bash tests/test-mega-tick.sh`. (Today: no verb; the lead runs `gh` and `sed` by hand.)
- [ ] A line holding a wrong sha for the same PR (`merged 2819920` for PR #37) is rewritten to gh's `281992a`. (Today: it stays wrong until someone audits it.)
- [ ] An OPEN PR, a MERGED PR with no merge commit oid, and a PR merged into a non-default base each exit 1 with the ROADMAP unchanged. (Today: commit `3047044` shows `merged OPEN` written into a line.)
- [ ] A `--pr` whose head is not the goal file's `**Branch:**` exits 3. (Today: a wrong PR number on an open line is written as given.)
- [ ] A `--note` carrying a literal `\n` is written as those two bytes on one line. (Today: no verb; an `awk -v` writer would split it.)
- [ ] A ledger checkout on its default branch exits 4 with nothing written.
- [ ] A dispatched task whose attempt is `running` ends `state=done winner=<aid> ref=PR#<N>@<sha7>`, found in whichever of the two repos' stores holds it.
- [ ] `bash tests/test-mega-box.sh` and `bash tests/test-shared-lookups.sh` pass with the new writer in `lib/mega`.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover the happy path, the two incidents, and every exit in the Exit codes table
- [ ] No regressions in existing functionality (`mega status`, `review`, `report`, `runs`, `labels` unchanged)

## Test plan

**Fixtures.** Two git repos in a temp dir, each with a bare origin and `origin/HEAD` set by `git remote set-head`: `ledger` (holds `docs/megagoals/m1/ROADMAP.md`, mode 644, checked out on `run/m1`; its default is `main`) and `code` (default `develop`). Neither has a `.orchestrate/` dir to start with, like the real VimMotion mega dir. Goal files with a `**Branch:**` line: `40-drag-by-labels.md` `feat/vn-40-drag-by-labels`; `44-uat-pack-release-gate.md` `feat/vn-44-uat`; `01-release-pipeline.md` `ci/release-pipeline (existing)` (the real suffixed shape); `13-hintkit-labels.md` `` `feat/13` `` (backticked); `21-app-shell-seams.md` `feat/x` followed by a CR byte; `50-glob.md` `feat/*`. No other goal file has one. Each case starts from a fresh copy of every fixture and both stores, so no case depends on another's write.

ROADMAP rows, copied from the real VimMotion ROADMAP (quoted in `## Grounding`) plus synthetic rows:

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
- [x] 47-legacy (repo), prose, PR #190 merged cb64f15 (note)
- [x] 48-backslash, PR #48, merged abcdef1 (path C:\tmp\x and a \n literal)
- [ ] 49-open-other, prose, PR #
- [ ] 50-glob, prose, PR #
- [ ] 51-cites, see PR #96 for context, PR #
```

**gh stub** (every PR returns `url` `https://github.com/acme/code/pull/<N>` unless noted, and logs its argv and cwd):

| PR | state | base | head | mergeCommit.oid |
|---|---|---|---|---|
| 96 | MERGED | develop | feat/vn-40-drag-by-labels | `0c471eb999dcbbcb51723e4ea22912d217e73fb8` |
| 37 | MERGED | develop | feat/13 | `281992a3530ea05c37709663c04ea2514dec0654` |
| 57, 38, 48 | MERGED | develop | feat/x | a fixed oid each |
| 21 | MERGED | develop | ci/release-pipeline | a fixed oid (the real PR 21 head) |
| 102 | OPEN | develop | feat/vn-44-uat | null |
| 103 | MERGED | develop | feat/vn-44-uat | null |
| 104 | MERGED | feat/stack | feat/vn-44-uat | an oid |
| 105 | exit 1, stderr `GraphQL: Could not resolve ...`, empty stdout | | | |
| 106 | OPEN | develop | feat/vn-44-uat | an oid (synthetic: isolates the state check from the oid check) |
| 107 | exit 0, stdout `not json` | | | |
| 108 | MERGED | develop | feat/someone-else | an oid |
| 109 | MERGED | develop | feat/vn-44-uat | an oid, but `url` names `/pull/110` |
| 111 | MERGED | develop | feat/x | an oid; `headRefName` 300 bytes long |

"Unchanged" means `cmp` of the ROADMAP against a pre-run copy, plus a listing (names and bytes) of both attempt stores against a pre-run listing.

| # | Case | Expect |
|---|---|---|
| C1 | tick 40 with PR 96 (line 51 is an open line citing PR #96 in prose); record `40...` in the code store: `dispatched`, `a1` running | exit 0; stdout AUDIT (repo `acme/code`), `BRANCH ok`, TICKED `- [x] 40-drag-by-labels, PR #96, merged 0c471eb`; status `done winner=a1 ref=PR#96@0c471eb`; diff is exactly 1 `<` and 1 `>`; file mode still 644; `.orchestrate/flip.lock` gone afterwards |
| C2 | tick 13 with PR 37, first with `--keep-note`, then with no flags | exit 3 (no annotation to keep); then exit 0, `merged 281992a`, `BRANCH ok feat/13` (backticked branch line) |
| C3 | tick 21 with PR 57 | exit 0; `BRANCH ok feat/x` (CR-ended branch line); `merged OPEN ` replaced by gh's sha7, trailing space gone |
| C4 | run C1 a second time | exit 0; `UNCHANGED`; attempt line `NOOP`; ROADMAP bytes identical |
| C5 | tick 44 with PR 102 (OPEN) | exit 1; unchanged |
| C6 | tick 44 with PR 103 (MERGED, null oid) | exit 1; unchanged |
| C7 | tick 44 with PR 104 (base `feat/stack`) | exit 1; unchanged |
| C8 | tick 44 with PR 105 (gh fails) | exit 1; stderr carries `GraphQL: Could not resolve`; unchanged |
| C9 | tick 44 with PR 107 (unparseable JSON) | exit 1; unchanged |
| C10 | tick 44 with PR 106 (OPEN, oid present) | exit 1; unchanged |
| C11 | tick 44 with PR 109 (url names another PR) and with PR 111 (300-byte head) | exit 1 each; unchanged |
| C12 | `GH_BIN` pointing at a missing file; and `PATH` without `jq` | exit 1 each, naming the missing tool; unchanged |
| C13 | code fixture with its origin refs removed and its `origin` remote still configured (no default resolves) | exit 1; stderr names `kit_default_branch_here` and `git -C <code-root> remote set-head origin -a`; unchanged |
| C14 | tick 44 with PR 108 (head `feat/someone-else`, goal file says `feat/vn-44-uat`) | exit 3, naming both branches; unchanged |
| C15 | tick 49 with PR 57 (another line, 21, already names PR #57) | exit 3; unchanged |
| C16 | tick `99-missing`; tick `13-hintkit` (prefix of a real id) | exit 3 each; unchanged |
| C17 | tick 13 with PR 96 (ticked with PR #37) | exit 3; unchanged |
| C18 | tick 45 (parked); tick 46 (two lines) | exit 3 each; unchanged |
| C19 | tick 47 with PR 190 (legacy ticked line with prose) | exit 3; unchanged |
| C20 | tick 07 with PR 38, no flags; then `--keep-note` | exit 3; then exit 0, annotation kept verbatim |
| C21 | tick 01 with PR 21 and `--note "merged by Han"` | exit 0; `BRANCH ok ci/release-pipeline` (suffixed branch line); line ends ` (merged by Han)` |
| C22 | tick 40 with PR 96 and `--note 'x\n- [x] 99-other, PR #1, merged abc1234'` (a literal backslash and `n`, no newline byte) | exit 0; the line ends ` (x\n- [x] 99-other, PR #1, merged abc1234)` byte-exact; `diff` shows 1 `<` and 1 `>`; `grep -c '^- \[x\] 99-other'` is 0 |
| C23 | tick 48 with PR 48 and `--keep-note` | exit 0; the annotation `path C:\tmp\x and a \n literal` is byte-exact; one-line diff |
| C24 | `--note` holding a real newline, a tab, and a 0x7f byte; and a 48 line whose annotation holds a tab, with `--keep-note` | exit 3 each; unchanged |
| C25 | the ledger fixture with CRLF line ends | exit 3; unchanged |
| C26 | ledger fixture checked out on `main` (its default) | exit 4; unchanged |
| C27 | ledger fixture on a detached HEAD | exit 4; unchanged |
| C28 | ledger fixture with its origin refs removed and a remote still configured (no default resolves) | exit 4; stderr names `git remote set-head origin -a`; unchanged |
| C29 | ROADMAP.md replaced by a symlink to a copy | exit 8; the link and its target unchanged |
| C30 | `ATTEMPT_REGISTRY_DIR` unset, two repos: record `40...` placed only in the LEDGER repo's store | exit 0; the ledger store's record reads `done`; the code store is unchanged |
| C31 | same, with a record in BOTH stores | exit 5, naming both dirs; unchanged |
| C32 | `ATTEMPT_STATE_BIN` stub whose `dir` exits 3 | exit 5, naming the root; unchanged |
| C33 | no record, the code store dir exists | exit 0; `ATTEMPT none 40-drag-by-labels (no 40-drag-by-labels.task in <dir>)`; no new file in either store |
| C34 | no store dir exists in either repo; then the same with `--no-attempt` | exit 5 with the `--no-attempt` hint; then exit 0 with `ATTEMPT skipped` |
| C35 | `--no-attempt` while a record exists | exit 5; unchanged |
| C36 | record: `dispatched`, `a1` lost, `a2` running; `--attempt a1`; then `--attempt a` (a prefix of no field) | exit 5 each; unchanged. Without `--attempt`: exit 0, `a2` committed |
| C37 | record `queued`, no live attempt; and a done task with `--attempt` naming a non-winner | exit 5 each; unchanged |
| C38 | done record with `ref=PR#96@1111111`, tick 40 with PR 96 | exit 0; stderr `ATTEMPT ref-mismatch 40-drag-by-labels recorded=PR#96@1111111 now=PR#96@0c471eb` |
| C39 | `flip.lock` pre-created holding the pid of a live `sleep`; `MEGA_TICK_LOCK_WAIT_SECS=0.4` | exit 7 within about 1 s; stderr names the pid and the retry; unchanged |
| C40 | `flip.lock` pre-created holding the pid of a finished process | exit 0; the stale lock is reclaimed (its pid file moved aside, not deleted) and released afterwards |
| C41 | `flip.lock` pre-created with no pid file, wait `0` | exit 7; stderr gives `rmdir '<path>'`; unchanged |
| C42 | `.orchestrate` exists as a FILE (so `mkdir -p` fails) | exit 8; unchanged |
| C43 | `MEGA_TICK_TEST=1` and a pause file: while the verb holds the lock, source `orchestrate.sh` and call `_lock_stale` on it; then the same pause file without `MEGA_TICK_TEST=1` | `_lock_stale` returns 1 (fresh) and `flip.lock/pid` holds the verb's pid; without the flag the verb does not pause |
| C44 | `ATTEMPT_STATE_BIN` stub that passes `dir` and `status` but fails `commit-result` | exit 6; ROADMAP written; stderr carries the settle command; a re-run with the real script converges to exit 0 with `UNCHANGED` |
| C45 | `chmod` stubbed to fail through `PATH` | exit 8; ROADMAP unchanged; no `.roadmap.tick.*` left in the mega dir |
| C46 | `SG-01` id; `--note` plus `--keep-note`; `--attempt` plus `--no-attempt`; `--pr` missing, `096`, `1234567890`, `9a`; mega slug `../x` and `.hidden` | exit 64 each |
| C47 | gh stub argv, cwd and env log over C1 | exactly one call, `pr view 96 --json state,mergeCommit,baseRefName,headRefName,url`, cwd = code-root, stdin not a TTY, `GH_PROMPT_DISABLED=1`; no `merge`, no `fetch`; no git call writes a ref |
| C48 | tick 44 with PR 108 and `--branch-override "branch renamed after review"` | exit 0; AUDIT ends `branch-override=branch\ renamed\ after\ review`; `BRANCH override feat/vn-44-uat != feat/someone-else` |
| C49 | tick 50 with PR 48 (goal file `feat/*`, head `feat/x`) | exit 3; unchanged |
| C50 | `--note` of 201 bytes; `--branch-override` with a tab | exit 3 each; unchanged |
| C51 | ROADMAP changed by another writer between the line read and the write (simulated with the C43 pause seam: the test edits line 40 while the verb waits) | exit 8; the other writer's edit stays; no `.roadmap.tick.*` left in the mega dir |

## Verification

```
bash tests/test-mega-tick.sh && bash tests/test-mega-box.sh && bash tests/test-shared-lookups.sh && bash tests/test-mega.sh && bash tests/run-all.sh --changed
```

## Edge Cases

1. The megagoals root sits behind a symlinked directory (the kit's own `_meta` links to `dwarves-kit-internal`). The ledger branch check runs `git -C "$(dirname <roadmap>)"`, which resolves the link target's repo. Only `ROADMAP.md` itself being a symlink is refused (C29).
2. Ledger and code are the same repo (VimMotion) or two repos (kit-modularity: ROADMAP in ops-toolkit, PRs in dwarves-kit). The branch check reads the ROADMAP's checkout; the PR base check reads code-root; the attempt store is probed in both (C30, C31).
3. gh can print a multi-line hint to stderr on `pr view` (seen in the PR 102 sample). The verb parses stdout JSON only; stderr's first line is used only in an exit 1 message.
4. A squash merge or a rebase merge: gh's `mergeCommit.oid` is still the commit on the base branch (PR 96's `0c471eb` is a one-parent squash commit on `origin/develop`; see `## Grounding`), so it is taken as is.
5. The line ends with trailing whitespace (`merged OPEN ` in commit `3047044`). The rewrite drops it, because the new line is built and never edited in place (C3).
6. `--note` text containing `)`. Accepted as is; `--keep-note` on a later tick takes everything up to the final `)`, so it round-trips.
7. A ROADMAP whose last byte is not a newline gains one on write (Invariants).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| gh unavailable, unauthenticated, or hung | gh exits nonzero, prints no JSON, or hits `MEGA_TICK_GH_TIMEOUT_S` | exit 1 with gh's first stderr line, nothing written; rerun once gh works |
| gh API shape change (field renamed) | `jq` yields an empty `state` or `oid` | treated as not MERGED, exit 1; fail closed, never a sha-less tick |
| Wrong `--pr` | the goal file's `**Branch:**` differs from gh's head (exit 3), or another line already names that PR (exit 3), or a ticked line records another PR (exit 3) | refused before any write. With no `**Branch:**` line the AUDIT line still shows the head for a human check, and `BRANCH unverified` flags it |
| A wrong tick that got through anyway | `mega status`, or a human reading the AUDIT/BRANCH lines | fixed by `git revert` or a hand edit, never by the verb: a re-tick with another PR refuses (exit 3, the line records a different PR). Before the commit, `git -C <ledger> restore <ROADMAP>`; after it, `git revert` the tick commit or hand-edit the line back to open, then tick with the right PR. The attempt record is terminal once `done` (no legal move out); `attempt-state.sh release <id>` drops it, and the merged PR plus the run ledger stay the durable trail |
| Attempt store unreachable or wrong | `attempt-state.sh dir` fails, or the record sits in a store nobody probed | `dir` failure is exit 5, never "no record"; both roots are probed; `ATTEMPT none` prints every dir it looked in |
| Lock left by a crashed run | `flip.lock` with a dead pid | reclaimed by the driver's rule (pid moved aside, `rmdir`), then the tick proceeds |
| Lock held by a live process, or with no pid file | the wait runs out | exit 7 with the recovery command; the verb never reclaims a live or pid-less lock |
| Lock parent missing | `<megadir>/.orchestrate/` absent | created with `mkdir -p`; a failure is exit 8, never read as "held" |
| Write fails midway | `mktemp`, awk, `chmod` or `mv` nonzero | exit 8; the temp file is moved aside; the original is untouched |
| Attempt store write fails after the ROADMAP write | `commit-result` nonzero | exit 6 with the settle command; re-running converges |

## Out of Scope

- SG-NN ids and the `- [x] SG-NN ... -- PR #N` form. `/kit:mega` scaffolds SG-NN today, but its done line keeps a title the `NN-slug` format drops; it needs its own line shape. This verb refuses SG-NN with exit 64 instead of guessing.
- Stacked PRs. A PR merged into a base other than the code-root default refuses (exit 1); a stacked sub-goal is ticked once its work reaches the default branch through a PR of its own, by hand or a later verb.
- Fixing `mega status`'s sha parse. It matches `PR #N merged <sha>` with no comma (`mega.sh:319`), so it never reads the sha of a `PR #N, merged <sha>` line. Classification does not use the sha, so nothing breaks today.
- A local `merge-base --is-ancestor` check of the merge commit against `origin/<default>`. That needs a fetch, a stale ref would refuse a good tick, and `wrap land`'s `_tree_verify` already owns the deeper tree check. gh's `baseRefName` equal to the default branch is the check here.
- Committing or pushing the ROADMAP change. The caller commits, as with every other kit write verb.
- Ticking several sub-goals in one call.
- The user-level `megagoal-agent-drive` skill that drives NN-slug runs lives outside this repo; pointing it at `mega tick` is a change there, not here.

## Touches

- lib/mega/mega.sh
- bin/mega
- lib/README.md
- lib/mega/README.md
- tests/test-mega-tick.sh
- tests/test-shared-lookups.sh
- docs/WORKFLOW.md

## Decision Log

- DEC-001: the sha comes only from gh's `mergeCommit.oid`. Both incidents were a sha typed or copied by hand. Rejected: a `--sha` argument, and reading the sha from local git.
- DEC-002: the verb never reads `mergeable`. By the lead's account that field read `UNKNOWN` in the `merged OPEN` incident, and merge status is answered by `state` plus `mergeCommit`. Rejected: waiting for `mergeable` to settle.
- DEC-003: an existing annotation is kept only with `--keep-note`, and a ticked line that carries one refuses (exit 3) when neither `--note` nor `--keep-note` is given. The item said an annotation is kept "only when passed", and dropping a long fix-forward history in silence (line 07) loses data.
- DEC-004: "no attempt record" is positive only when a probed store dir exists and holds no `<id>.task`. A store that cannot resolve is exit 5. No store dir anywhere is exit 5 unless `--no-attempt`, which itself refuses when a record exists. Rejected: reading every failure to find a record as "none", which let a tick exit 0 while the task stayed `dispatched`.
- DEC-005: the ledger branch check refuses (exit 4) where `default-branch-warn.sh` only warns. The item asks for a refusal: a tick on the default branch is a commit that cannot land through a PR. The resolver `kit_default_branch_here` is reused; only the policy differs. A detached HEAD or an unresolved default also refuses (fail closed).
- DEC-006: the lock is `orchestrate.sh flip`'s own `<megadir>/.orchestrate/flip.lock`, with the driver's protocol (pid file, dead-pid reclaim by move-aside then `rmdir`), a `mkdir -p` of the parent, and a bounded wait. Rejected: sourcing all of `orchestrate.sh` for `_lock`, and extracting `_lock` into a shared file, which is a refactor of the driver outside this item. The verb does not copy the driver's age-based reclaim of a pid-less lock: a pid-less lock is exit 7 with a recovery command.
- DEC-007: a ticked line whose primary PR equals `--pr` is rewritten (the repair path). This is what fixes the `2819920` and `merged OPEN` lines.
- DEC-008: exit codes are distinct per refusal class (1, 3, 4, 5, 6, 7, 8) so each negative control asserts its own code, not just "nonzero".
- DEC-009: note text reaches the file only through the environment (`ENVIRON` in awk) and bash concatenation, and any control character in a note or kept annotation refuses. `awk -v` expands backslash escapes, so a note with `\n` would forge a second ledger line.
- DEC-010: a wrong `--pr` is caught by the goal file's `**Branch:**` line (all 44 VimMotion goal files carry one; it is normalized before the compare, and `--branch-override <reason>` is the logged escape for a legitimate rename) and by the one-PR-one-line rule. With no branch line the verb continues and prints `BRANCH unverified`, because requiring one would block megas whose goal files never declared it.

## Grounding

Live samples, read-only, taken 2026-11-25.

**gh PR shape, merged** (`cd /Users/tieubao/orca/workspaces/VimMotion/next-run-2`):

```
$ gh pr view 96 --json state,mergeCommit,baseRefName,number,headRefName
{"baseRefName":"develop","headRefName":"feat/vn-40-drag-by-labels","mergeCommit":{"oid":"0c471eb999dcbbcb51723e4ea22912d217e73fb8"},"number":96,"state":"MERGED"}

$ gh pr view 96 --json url,headRefName 2>/dev/null
{"headRefName":"feat/vn-40-drag-by-labels","url":"https://github.com/consolelabs/VimMotion/pull/96"}

$ gh pr view 37 --json state,mergeCommit,baseRefName
{"baseRefName":"develop","mergeCommit":{"oid":"281992a3530ea05c37709663c04ea2514dec0654"},"state":"MERGED"}
```

**Squash merge oid on the default branch** (PR 96's merge commit has one parent and is on `origin/develop`):

```
$ git merge-base --is-ancestor 0c471eb999dcbbcb51723e4ea22912d217e73fb8 origin/develop && echo "0c471eb on origin/develop"
0c471eb on origin/develop
$ git show 0c471eb --format='%H parents=%P' --no-patch
0c471eb999dcbbcb51723e4ea22912d217e73fb8 parents=9fd1183fb6d0ed14991df6a1af52a31a412e0378
```

**gh PR shape, open** (`mergeCommit` is `null`; gh also printed a multi-line `gh event listen` hint on stderr):

```
$ gh pr view 102 --json state,mergeCommit,baseRefName,mergeable
{"baseRefName":"develop","mergeCommit":null,"mergeable":"MERGEABLE","state":"OPEN"}
$ gh pr view 102 --json state,mergeCommit,baseRefName 2>/dev/null
{"baseRefName":"develop","mergeCommit":null,"state":"OPEN"}
```

**gh PR shape, closed without merge**: VimMotion has none in its last 30 closed PRs. Sampled from a public repo instead:

```
$ gh pr list -R cli/cli --state closed --limit 40 --json number,state,mergeCommit,baseRefName | jq -c '[.[]|select(.state=="CLOSED")][0]'
{"baseRefName":"trunk","mergeCommit":null,"number":15158,"state":"CLOSED"}
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

**Mega dir shape** (`docs/megagoals/01-human-first-upgrade/` in the VimMotion checkout):

```
$ ls -d docs/megagoals/01-human-first-upgrade/.orchestrate
ls: docs/megagoals/01-human-first-upgrade/.orchestrate: No such file or directory
$ grep -n Branch docs/megagoals/01-human-first-upgrade/goals/40-drag-by-labels.md
11:**Branch:** feat/vn-40-drag-by-labels
$ grep -l '^\*\*Branch:\*\* ' docs/megagoals/01-human-first-upgrade/goals/*.md | wc -l ; ls docs/megagoals/01-human-first-upgrade/goals | wc -l
      44
      44
$ stat -f '%Lp' docs/megagoals/01-human-first-upgrade/ROADMAP.md
644
```

Distinct `**Branch:**` shapes across all 44 goal files (43 are a bare name, one carries a suffix; none is backticked or CR-ended):

```
$ grep -h '^\*\*Branch:\*\* ' goals/*.md | awk '{print NF}' | sort | uniq -c
  43 2
   1 3
$ grep -H '^\*\*Branch:\*\* ' goals/01-*.md goals/02-*.md goals/40-*.md goals/44-*.md
goals/44-uat-pack-release-gate.md:**Branch:** feat/vn-44-uat-pack-release-gate
goals/40-drag-by-labels.md:**Branch:** feat/vn-40-drag-by-labels
goals/01-release-pipeline.md:**Branch:** ci/release-pipeline (existing)
goals/02-package-scaffold.md:**Branch:** feat/vn-02-package-scaffold
$ gh pr view 21 --json headRefName 2>/dev/null
{"headRefName":"ci/release-pipeline"}
```

The suffixed line 01 normalizes to `ci/release-pipeline`, which equals PR 21's head; sub-goal 40's line equals PR 96's head. The backticked and CR-ended shapes are not in this run; the fixture adds them because hand-written goal files elsewhere may carry them.

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

**Attempt store** (VimMotion git common dir `/Users/tieubao/workspace/dwarvesf/VimMotion/.git/kit-attempts/`; task files are named by sub-goal id; worker ids masked):

```
$ bash lib/goal/attempt-state.sh dir                     # cwd: the VimMotion checkout
/Users/tieubao/workspace/dwarvesf/VimMotion/.git/kit-attempts
$ (cd /tmp && bash lib/goal/attempt-state.sh dir; echo rc=$?)
attempt-state: not a git repository (the store lives under .git)
rc=3

$ bash lib/goal/attempt-state.sh status 40-drag-by-labels
task=40-drag-by-labels state=done
winner=a1 ref=PR#96@0c471eb
attempt=a1 worker=<agent id> state=committed

$ bash lib/goal/attempt-state.sh status 44-uat-pack-release-gate
task=44-uat-pack-release-gate state=dispatched
attempt=a1 worker=<agent id> state=running
```

The dwarves-kit checkout has no `kit-attempts/` dir under its git common dir, which is why DEC-004 needs `--no-attempt` for a mega that never dispatched through the store.

**Kit-internal shapes the verb must satisfy** (read at file:line, not external):
- `lib/mega/box.tsv`: done token `[x]`, alias `[X]`; slug id ERE `[0-9]+[A-Za-z]?-[A-Za-z][A-Za-z0-9_-]*`.
- `tests/test-shared-lookups.sh:57` `PAT_MERGED` matches `pr view ... --json ... state`, and line 112 pins `merged-ok lib/mega/mega.sh 2`.
- `lib/queue/orchestrate.sh:1003` lock path `$megadir/.orchestrate/flip.lock`; `_lock_stale` (line 346) treats a live pid as fresh and a dead pid as reclaimable; `_lock_reclaim` moves the pid file aside and runs `rmdir`.
- `lib/goal/attempt-state.sh:63-75` the legal transitions: an attempt reaches `committed` only from `running` or `disconnected`; a task reaches `done` only from `dispatched`.

### Negative-control dry traces

Each trace: the mutation to the new code, the fixture it reads, the path it then takes, and the case that goes red.

| NC | Mutation | Fixture read | Path after the mutation | Red case |
|---|---|---|---|---|
| NC1 | drop the `state == MERGED` test | stub PR 106: `OPEN` with an oid (PR 102's real shape has a null oid, so the oid check would still refuse it) | the audit passes; an unmerged PR is ticked | C10 expects exit 1 and `cmp` equal; gets 0 |
| NC2 | drop the 40-hex oid check | stub PR 103: `MERGED`, null `mergeCommit` | `jq -r .mergeCommit.oid` yields `null`; `merged null` is written (the `merged OPEN` class) | C6 expects exit 1; gets 0 |
| NC3 | drop the base == default test | stub PR 104: base `feat/stack` | a stacked PR is ticked as done | C7 expects exit 1; gets 0 |
| NC4 | take the sha from the existing line when it is 7-hex | line `13-hintkit-labels, PR #37, merged 2819920`; stub oid `281992a...` | the rewrite keeps `2819920` | C2 expects `merged 281992a`; finds `2819920` |
| NC5 | match the id by prefix | arg `13-hintkit`; only `13-hintkit-labels` exists | the 13 line is rewritten under the wrong id | C16 expects exit 3; gets 0 |
| NC6 | skip the primary PR compare on a ticked line | line 13 records PR #37; arg `--pr 96` | the line is rewritten to PR #96 | C17 expects exit 3; gets 0 |
| NC7 | take the LAST `PR #n` as primary | line 07: `PR #38 ... PR #72` | the primary reads 72, so `--pr 38` refuses | C20's `--keep-note` run expects exit 0; gets 3 |
| NC8 | skip the ledger branch check | ledger on `main` (its default) | the line is written on the default branch | C26 expects exit 4; gets 0 |
| NC9 | treat a detached HEAD's empty branch as "not default" | ledger detached | the write proceeds | C27 expects exit 4; gets 0 |
| NC10 | treat an empty `kit_default_branch_here` result as "not default" on the ledger | ledger with origin refs removed | `"" != "run/m1"` passes, the write proceeds | C28 expects exit 4; gets 0 |
| NC11 | skip `commit-result` | code store record `40...`: dispatched, `a1` running | ROADMAP ticked, store still `dispatched` | C1 expects `state=done winner=a1`; reads `dispatched` |
| NC12 | resolve the attempt after the ROADMAP write | record `queued`, no live attempt | ROADMAP written, then exit 5 | C37 expects `cmp` equal; the file changed |
| NC13 | accept any `--attempt` that appears in `status` | record with `a1` lost | the write lands, then `commit-result` hits the illegal `lost -> committed` move: exit 6 on every re-run | C36 expects exit 5 and `cmp` equal; gets 6 |
| NC14 | match `--attempt` by substring | `--attempt a` against `attempt=a1`, `attempt=a2` | `a` matches a field and is passed on | C36 expects exit 5 for `a`; gets 6 or 0 |
| NC15 | read a failed `attempt-state.sh dir` as "no record" | `ATTEMPT_STATE_BIN` stub whose `dir` exits 3 | `ATTEMPT none`, exit 0, the real record never committed | C32 expects exit 5; gets 0 |
| NC16 | probe only code-root's store | record only in the ledger repo's store | `ATTEMPT none`, the ledger record stays `dispatched` | C30 expects the ledger record `done`; reads `dispatched` |
| NC17 | treat "no store dir anywhere" as "no record" | neither repo has `kit-attempts/` | exit 0 with `ATTEMPT none` | C34 expects exit 5 without `--no-attempt`; gets 0 |
| NC18 | pass `--note` through `awk -v` | C22's note `x\n- [x] 99-other, ...` | awk turns `\n` into a newline; a second line `- [x] 99-other, PR #1, merged abc1234` appears | C22 expects `grep -c '^- \[x\] 99-other'` = 0 and a one-line diff; gets 1 and two added lines |
| NC19 | drop the control-character check on notes | C24's note with a real newline | the newline is written into the ROADMAP | C24 expects exit 3; gets 0 |
| NC20 | skip the goal-file branch compare | stub PR 108: head `feat/someone-else`; goal file `feat/vn-44-uat` | the wrong PR is recorded on line 44 | C14 expects exit 3; gets 0 |
| NC21 | skip the one-PR-one-line check | line 21 already names PR #57; tick 49 with PR 57 | two lines name PR #57 | C15 expects exit 3; gets 0 |
| NC22 | drop the repairable-shape check | line 47 with `(repo), prose` | the prose and note are lost | C19 expects exit 3; gets 0 |
| NC23 | drop the annotation refusal | line 07, no flags | the fix-forward history is dropped | C20 expects exit 3; gets 0 |
| NC24 | `mkdir` the lock without `mkdir -p` of `.orchestrate/` | fixture with no `.orchestrate/` (the VimMotion shape) | `mkdir` fails with ENOENT, read as "held", exit 7 on every tick | C1 expects exit 0; gets 7 |
| NC25 | read any `mkdir` failure as "held" | `.orchestrate` is a file | the verb waits and exits 7 | C42 expects exit 8; gets 7 |
| NC26 | write before taking the lock | live-pid lock (C39) | the write proceeds under another holder | C39 expects exit 7 and `cmp` equal; gets 0 |
| NC27 | omit the pid write after `mkdir` | C43 pause, `_lock_stale` with `FLIP_LOCK_STALE_SECS=0` | an absent pid reads stale, so the driver would reclaim a live tick's lock | C43 expects `_lock_stale` = 1; gets 0 |
| NC28 | never reclaim a dead-pid lock | C40 lock with a finished pid | waits, then exit 7 | C40 expects exit 0; gets 7 |
| NC29 | honor the pause file without `MEGA_TICK_TEST=1` | C43's second half | the verb pauses in a non-test run | C43 expects no pause; the run blocks until the file is removed |
| NC30 | write the box as a literal `- [x]` | none (static lint) | the section 14 scan of `lib/mega` hits the new line | `tests/test-mega-box.sh` "no reader hardcodes the box grammar" fails |
| NC31 | omit the `# merged-ok:` marker on `gh pr view` | none (static lint) | `PAT_MERGED` hits an unmarked statement | `tests/test-shared-lookups.sh` reports `UNMARKED merged lib/mega/mega.sh` |
| NC32 | overwrite ROADMAP.md in place instead of temp plus `mv`, and skip the symlink check | C29 symlinked ROADMAP.md | the link target is rewritten | C29 expects exit 8 and both unchanged; gets 0 |
| NC34 | compare the raw `**Branch:**` value, no normalization | goal file 01 `ci/release-pipeline (existing)`; PR 21 head `ci/release-pipeline` | the values differ, exit 3 | C21 expects exit 0; gets 3 (C2 and C3 go red the same way for the backticked and CR shapes) |
| NC35 | compare with an unquoted `[[ $head == $goal ]]` | goal file 50 `feat/*`; PR 48 head `feat/x` | the pattern matches, the wrong PR is recorded | C49 expects exit 3; gets 0 |
| NC36 | apply the one-PR rule to open lines too | line 51 `see PR #96` in prose | ticking 40 with PR 96 refuses | C1 expects exit 0; gets 3 |
| NC37 | replace record `TICK_NR` without comparing it to `TICK_OLD` | C51 concurrent edit | the other writer's edit is overwritten | C51 expects exit 8 and the edit kept; gets 0 |
| NC33 | skip the `chmod` to the original mode | `mktemp` creates mode 600 | the ROADMAP ends at mode 600 | C1 expects mode 644; finds 600 |

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
