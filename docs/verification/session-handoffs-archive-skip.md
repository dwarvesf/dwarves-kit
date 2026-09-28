# Proof of done: handoffs-archive-skip (SPEC-333)

`lib/session/handoffs.sh cmd_list`'s `find` filter is now a strict one-level scan
(`find "$d" -maxdepth 1 -type f -name '*.md'`): a file sitting directly in a scan root is
open, a file in ANY subdirectory of either scan root, whatever it is named, counts as
consumed. No name list is maintained. This is an operator override of the prior fix in this
worktree, which shipped a four-name `-prune` denylist (`done`, `_archive`, `archive`,
`.claude`); that denylist correctly excluded the four named shapes and fixed the ancestor-path
bug, but a fifth archive-folder convention a repo might invent would still slip through it.
The one-level scan has no such gap and structurally keeps the ancestor-path fix (no
path-substring match happens at all). Does not change the two scan roots, `handoff_liveness`,
or any other function.

This revision folds five re-validation warnings (W1-W5): the runtime `DEAD` message and its
header line now say "delete it or move it into any subdirectory"; `commands/start.md`'s
kit:start line describes the one-level rule instead of a name list; the spec's Contract gains
an explicit "one handoff = one top-level `.md`" consequence; test case `[18]` (the `.claude/`
ancestor) now also asserts the exact `2 open handoffs` count; and a new case `[20]` fixtures a
`done/` ancestor (`$(mktemp -d)/done/repo`), the decisive case for NC1 since the pre-SPEC-333
filter's `-not -path '*/done/*'` matches that ancestor segment directly.

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | An arbitrarily-named subdirectory (not on any list, e.g. `old/`) is excluded | case [16] | PASS |
| AC2 | The originally-reported named shapes (`archive/`, `_archive/`, nested `.claude/session-state/`) are also excluded | case [16] | PASS |
| AC3 | Live files sitting directly in both `.claude/handoffs` and `_meta/handoffs` still list, exact count 2 | case [17] | PASS |
| AC4 | A repo checked out under a `.claude/` ancestor path loses neither scan root, exact count 2 | case [18] | PASS |
| AC5 | A repo with only subdirectory-nested files (arbitrary and named) gets the honest "no handoffs" message | case [19] | PASS |
| AC6 | A repo checked out under a `done/` ancestor path loses neither scan root, exact count 2 | case [20] | PASS |
| AC7 | The runtime `DEAD` message and its header advice describe the subdirectory option, not just deletion | case [10], header read | PASS |
| AC8 | Every pre-existing case ([1]-[15]) is unaffected | full suite | PASS |

## Implementation

- `lib/session/handoffs.sh` `cmd_list` -- unchanged from the prior revision: `find "$d"
  -maxdepth 1 -type f -name '*.md'`, depth alone decides open vs. consumed.
- `lib/session/handoffs.sh` `handoff_liveness` -- the `DEAD` message at line 143 is now `"DEAD
  (all $n cited rows closed, delete it or move it into any subdirectory)$suffix"`; the matching
  header passage (lines ~41-48) reworded to the same phrasing instead of "delete it" alone.
- `commands/start.md` -- the kit:start "Open handoffs" line no longer names `done/`/`_archive/`
  specifically; it describes the one-level rule (a file directly in a scan root is open, a
  file in any subdirectory counts as consumed).
- `docs/specs/SPEC-333-handoffs-archive-skip.md` -- Contract item 6 (and DEC-B) added: a
  handoff is one top-level `.md` file; a multi-file bundle needs a top-level index file, since
  a subdirectory counts as consumed regardless of contents. Test plan gained a new row 3 (the
  `done/`-ancestor fixture), renumbering the rows after it. Touches gained `commands/start.md`.
  Status set to VALIDATED.
- `lib/session/tests/test-handoffs.sh` -- case `[10]`'s `DEAD` assertion updated to match the
  new message; case `[18]` gained an exact-count assertion; new case `[20]` fixtures
  `DREPO="$(mktemp -d)/done/repo"` with live files directly in both scan roots. 25 total
  assertions in the file (was 22).

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash lib/session/tests/test-handoffs.sh` | 0 | smoke: all 25 passed |

## Run detail

```
[16] an arbitrarily-named subdirectory (not on any list) is excluded
  ok: arbitrary and named subdirectory paths excluded
[17] live files under both scan roots present, exact count 2
  ok: both live files listed
  ok: count: 2 open handoffs
[18] a .claude/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a .claude/ ancestor
  ok: count: 2 open handoffs
[19] only-excluded repo (arbitrary + named subdirectories): honest 'no handoffs'
  ok: no handoffs for only-excluded repo
[20] a done/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a done/ ancestor
  ok: count: 2 open handoffs

smoke: all 25 passed
```

## Negative control (negctl.sh mutate mode, two reversions)

**NC1: revert to the pre-SPEC-333 two-clause `-not -path` filter** (commit `194c89f0`, the
`done/`/`_archive/`-only filter that predates this spec entirely). Must turn the suite RED,
decisively on the new `done/`-ancestor case `[20]` in addition to the arbitrary/named
subdirectory cases, then restore GREEN.

```
$ bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh"
## Negative control (negctl)
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Mutation: git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Manual reproduction (mutation applied directly, inspected, then restored) confirmed the exact
failure signature: cases `[16]`, `[17]`, `[19]` (the `old/x.md` arbitrary-name fixture) AND
case `[20]` (the `done/`-ancestor fixture) all fail; case `[18]` (the `.claude/`-ancestor
fixture) still passes since `-not -path '*/done/*'`/`'*/_archive/*'` do not match a `.claude`
segment:

```
[17] live files under both scan roots present, exact count 2
  ok: both live files listed
  FAIL: expected '2 open handoffs', got: 5 open handoffs
[18] a .claude/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a .claude/ ancestor
  ok: count: 2 open handoffs
[19] only-excluded repo (arbitrary + named subdirectories): honest 'no handoffs'
  FAIL: expected 'no handoffs', got: ... 2 open handoffs
[20] a done/ ancestor above the repo root blanks neither scan root
  FAIL: a done/ ancestor blanked a scan root: no handoffs
  FAIL: expected '2 open handoffs', got: no handoffs

smoke: 6 FAILED, 19 passed
```

**NC2: apply the rejected name-denylist design** (commit `359d8836`, the `-prune`/`-name`
filter this worktree's history briefly shipped as the first fix for this spec, DEC-A). Must
turn the suite RED specifically on the arbitrarily-named-subdirectory case (`old/x.md`),
since `old` is not one of the four denylisted names, proving the future-proofing gap the
operator's override exists to close. Both ancestor cases (`[18]` `.claude/`, `[20]` `done/`)
are expected to PASS under this mutation, since `-name`-based pruning already fixed the
ancestor bug for both segment names; only the denylist's missing fifth name should fail.

```
$ bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 359d8836:lib/session/handoffs.sh > lib/session/handoffs.sh"
## Negative control (negctl)
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Mutation: git show 359d8836:lib/session/handoffs.sh > lib/session/handoffs.sh
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Manual reproduction confirmed the specific failure signature negctl's exit-code check alone
does not distinguish: exactly cases `[16]`, `[17]`, `[19]` fail (all keyed on the `old/x.md`
arbitrary-name fixture), while both ancestor cases `[18]` and `[20]` pass:

```
[17] live files under both scan roots present, exact count 2
  ok: both live files listed
  FAIL: expected '2 open handoffs', got: 3 open handoffs
[18] a .claude/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a .claude/ ancestor
  ok: count: 2 open handoffs
[19] only-excluded repo (arbitrary + named subdirectories): honest 'no handoffs'
  FAIL: expected 'no handoffs', got: ... _meta/handoffs/old/x.md ...  1 open handoffs
[20] a done/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a done/ ancestor
  ok: count: 2 open handoffs

smoke: 4 FAILED, 21 passed
```

Working tree confirmed clean (`git status --short` empty) after both restores, and the suite
re-ran green (25/25) after each.

## Reproduce

```
cd dwarves-kit  # this worktree
bash lib/session/tests/test-handoffs.sh                                            # 25/25, exit 0
bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh"            # NC1
bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 359d8836:lib/session/handoffs.sh > lib/session/handoffs.sh"            # NC2
```

## Not proven
- The broader `tests/test-hooks.sh` suite is not re-run here: this spec's `## Verification`
  names only `tests/test-handoffs.sh` (an unrelated repo-wide test is not this change's proof).

Verdict: PASS
