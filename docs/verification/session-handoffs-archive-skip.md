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

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | An arbitrarily-named subdirectory (not on any list, e.g. `old/`) is excluded | case [16] | PASS |
| AC2 | The originally-reported named shapes (`archive/`, `_archive/`, nested `.claude/session-state/`) are also excluded | case [16] | PASS |
| AC3 | Live files sitting directly in both `.claude/handoffs` and `_meta/handoffs` still list, exact count 2 | case [17] | PASS |
| AC4 | A repo checked out under a `.claude/` ancestor path loses neither scan root | case [18] | PASS |
| AC5 | A repo with only subdirectory-nested files (arbitrary and named) gets the honest "no handoffs" message | case [19] | PASS |
| AC6 | Every pre-existing case ([1]-[15]) is unaffected | full suite | PASS |

## Implementation

- `lib/session/handoffs.sh` `cmd_list` -- the `-prune`/`-name` denylist filter (`find "$d"
  -mindepth 1 \( -name done -o -name _archive -o -name archive -o -name .claude \) -type d
  -prune -o -type f -name '*.md' -print`) is replaced with `find "$d" -maxdepth 1 -type f -name
  '*.md'`: depth alone decides open vs. consumed, no name enumerated anywhere. The header-doc
  passages (lines ~5-8, ~20-23) and the DEAD-verdict advice line describe the one-level rule
  instead of a name list.
- `lib/session/tests/test-handoffs.sh` -- cases `[16]`-`[19]` rebuilt: `[16]` now fixtures an
  arbitrarily-named subdirectory (`old/x.md`) alongside the original named shapes in the same
  repo, proving the design is not a denylist; `[17]` (exact-count live check) and `[18]`
  (ancestor-path check) kept; `[19]` (only-excluded repo) extended with the arbitrary name too.
  22 total assertions in the file, unchanged from the prior revision.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash lib/session/tests/test-handoffs.sh` | 0 | smoke: all 22 passed |

## Run detail

```
[16] an arbitrarily-named subdirectory (not on any list) is excluded
  ok: arbitrary and named subdirectory paths excluded
[17] live files under both scan roots present, exact count 2
  ok: both live files listed
  ok: count: 2 open handoffs
[18] a .claude/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a .claude/ ancestor
[19] only-excluded repo (arbitrary + named subdirectories): honest 'no handoffs'
  ok: no handoffs for only-excluded repo

smoke: all 22 passed
```

## Negative control (negctl.sh mutate mode, two reversions)

**NC1: revert to the pre-SPEC-333 two-clause `-not -path` filter** (commit `194c89f0`, the
`done/`/`_archive/`-only filter that predates this spec entirely). Must turn the suite RED on
the arbitrary and named subdirectory cases, then restore GREEN.

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

**NC2: apply the rejected name-denylist design** (commit `359d8836`, the `-prune`/`-name`
filter this worktree's history briefly shipped as the first fix for this spec, DEC-A). Must
turn the suite RED specifically on the arbitrarily-named-subdirectory case (`old/x.md`),
since `old` is not one of the four denylisted names, proving the future-proofing gap the
operator's override exists to close.

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

Manual reproduction (mutation applied directly, inspected, then restored) confirmed the
specific failure signature negctl's exit-code check alone does not distinguish: the denylist
mutation fails exactly cases `[16]`, `[17]`, and `[19]`, all three keyed on the `old/x.md`
arbitrary-name fixture, while case `[18]` (the ancestor-path case) still passes under the
denylist mutation, since DEC-A already fixed that half:

```
[16] an arbitrarily-named subdirectory (not on any list) is excluded
  FAIL: a nested path leaked: ... _meta/handoffs/old/x.md ...  3 open handoffs
[17] live files under both scan roots present, exact count 2
  FAIL: expected '2 open handoffs', got: 3 open handoffs
[18] a .claude/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a .claude/ ancestor
[19] only-excluded repo (arbitrary + named subdirectories): honest 'no handoffs'
  FAIL: expected 'no handoffs', got: ... _meta/handoffs/old/x.md ...  1 open handoffs

smoke: 3 FAILED, 19 passed
```

Working tree confirmed clean (`git status --short` empty) after both restores.

## Reproduce

```
cd dwarves-kit  # this worktree
bash lib/session/tests/test-handoffs.sh                                            # 22/22, exit 0
bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh"            # NC1
bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 359d8836:lib/session/handoffs.sh > lib/session/handoffs.sh"            # NC2
```

## Not proven
- The broader `tests/test-hooks.sh` suite is not re-run here: this spec's `## Verification`
  names only `tests/test-handoffs.sh` (an unrelated repo-wide test is not this change's proof).

Verdict: PASS
