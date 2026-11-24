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
