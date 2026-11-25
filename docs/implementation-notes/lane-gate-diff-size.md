# lane-gate-diff-size: implementation notes

Spec: `docs/specs/SPEC-424-lane-gate-diff-size.md`. Only deltas from the spec.

## Spec revision
- The first draft's Rule A (a deny list over free text) was replaced by a closed line grammar after the security validation returned BLOCK on ten findings. The revised spec is the contract; this file logs what the build changed from it.

## Build delta
- Every Rule A check is one line tagged `# chk:<id>` in `lib/classify/lane-classify.sh`. The suite's `rule-a-checks-are-load-bearing` case copies `lib/`, switches one id off (`bad(` becomes a no-op, `return 1` becomes `true`) and requires that finding's rows to go red. This replaces a per-finding negative-control script; the spec named the rows, not the mechanism.
- Block-scalar content is checked only by the byte rules; the first content line must be indented exactly 10 and a non-blank line below 10 ends the block. A separate mutation (`BLK`) moves that bound and the "key-shaped text inside a block stays text" row goes red.
- Rows that the allow-list grammar alone would refuse (an escaped `write`, for example) cannot go red under a single-check mutation, so the byte-rule rows put the backslash, tab, CR and non-ASCII byte inside a `run: |` block, the one place the grammar admits any text.
- The `on:` and name checks are layered: the mutation for a finding switches off every tagged line of that finding, and a few lines carry two ids (the required-section check at the end of the grammar, the collision compare).
- `tests/test-ceremony-fits-diff.sh` sets `core.autocrlf=false` in its `_git` helper: a host with `autocrlf=input` rewrote the CR the CR rows plant.
- The default-branch tip must resolve to an `origin/` ref; the suite's workflow fixture adds an `origin` remote that points at the scratch repo itself.
- A mixed-diff row for finding 9 uses a comment-only `.github/dependabot.yml` and a `.github/NOTES.md` next to the workflow: both are blanked before the loop, so Rule A reads the unblanked list (`paths.all`).
- `ship-rules.sh`: comment-only lines are capped at 20 with an `L` count line; Rule A lines are never capped.
- Test fixture note: git rewrote nothing else; the 50 drop and 8 second budget is shared by both drop rules.

## Review round delta
- `_WF_BASENAMES` is gone. `_WF_BASECHECK` classifies each base workflow file (exit 3 on an unclassifiable line, `workflow_run` anywhere) and prints name globs; `_WF_GLOBMATCH` matches the new names against them. Each file is classified as it is read, so there is no concatenated base file.
- `floor` exports `GIT_NO_REPLACE_OBJECTS=1` and `_floor_git` passes `--no-replace-objects`; both, because lane-data reads config with its own git calls.
- `_floor_tools_ok` runs at the verb entry only. A tool missing mid-scan is not covered.
- The `uses:` check is one generic `uses:` branch (allow list, then the 40-hex pin) so the allow-list mutation can switch it off alone.
- Mutation ids added: R1 to R7, PERM, PIN, EMPTY, MODE, EXTRA. R1, R4, R6 and R7 use a custom sed because their check is not a `bad(` or `return 1` line. The single-fault rows are matched by label (`WANT`).
- Red-before for the new cases was taken from the libs of the previous commit: every new rule row failed there, the single-fault rows are red only under their mutation.
- Not changed: the hook's own base follows `origin/main` (a local rewind of that ref still sizes, as before).

## Review round 2 delta
- `_WF_BASECHECK` tracks the indent of the last `name:` line it read (`pend`); the next non-blank, non-comment line deeper than that keeps the floor. A glob that still holds `}}` or `${{` keeps the floor.
- `_floor_tools_ok` lists git awk sed tr grep wc head cut cmp mktemp cp mv rm cat sort paste basename env, read from the floor path's functions (floor, the _floor_* helpers, Rule A, the exemption and extras readers, the config readers). `dirname` is left out on purpose: the script runs it while loading, before the verb starts.
- Row `job-name-continues-with-expression` is not red on the previous build: its new job key still collided with the base name; the first two continuation rows carry the red-before. The mutation case still turns the whole case red.

## Review round 3 delta
- `_floor_wf_read` runs a byte rule before the classifier: `sed` strips one CR at each line end, `tr` deletes every allowed byte (0x20 to 0x7E and LF), and any leftover byte keeps the floor. Each step goes through a temp file and its exit status is tested; no pipe. An empty file still passes, as before.
- A CR at the very end of a file with no final LF is read as a line-end CR and allowed; nothing can follow it.
