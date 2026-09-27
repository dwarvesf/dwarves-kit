# Spec: proof-of-done BLOCKED message names a rejected verdict file
Generated: 2026-09-27
Status: VALIDATED
Lane: full

## Problem

`lib/gate/proof-ledger.sh check()` (called from `hooks/ship-gate.sh` at push) only accepts a
`docs/verification/*.md` proof for a `behavioral` change when the file's **LAST** `Verdict:`
line is not `FAIL`/`INCONCLUSIVE`. The per-file loop:

```sh
last_v="$(grep -iE '^[[:space:]]*Verdict:' "$p" | tail -1)"
grep -qi 'NEGATIVE CONTROL' "$p" && { grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' "$p" || _has_committed_image "$p" "$root"; } \
  && ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*(INCONCLUSIVE|FAIL)' && ok=0 && break
```

(and its set-wise twin over `docs/verification/<slug>/` groups) has the exact same shape. A
proof file that correctly records its negative control's outcome as its own `Verdict: FAIL as
expected` line, then never adds a later `Verdict: PASS` line for the real run, fails this
condition: the file exists, carries a `NEGATIVE CONTROL` marker, and even carries a green
`Exit: 0`/`PASS` somewhere in it, but `ok` never flips to 0 because `last_v` is a FAIL/INCONCLUSIVE
line.

When `ok` stays 1, `check()` falls through past the override branch (lines ~356-388) to the
generic blocked block (lines ~391-411), which prints:

```
BLOCKED: proof of done. This is a '$class' change; it cannot ship/merge without a matching proof-of-done entry in docs/verification/.
  Need: a docs/verification/<slug>.md added by this branch with a green run AND a NEGATIVE CONTROL (revert -> RED -> restore).
        ('green run' = a text run-table (Command:/Exit:/Verdict: PASS) OR a committed screenshot/GIF embed for visual/demo work.)
  Type-specific shape: run 'bash lib/gate/proof-gate.sh contract "<your task>"' for the exact artifact this work-type owes + the skill that owns it (e.g. a data/CLI tool owes a recorded live run; an eval owes a TEST-REPORT).
  Produce it via /kit:verify (or record it), or log an explicit override (audited):
    bash lib/gate/proof-ledger.sh override '${slug:-<branch-slug>}' "<reason>"
  Or switch this gate off for the repo: [gate] proof_of_done = false in a committed .kit.toml (lib/gate/README.md, 'Switching a gate off').
```

This text is identical whether the branch added **no** proof file at all, or added a proof file
that is one wrong line away from passing. Nothing in the message says a file WAS found, which
one, or why it was rejected. Cost observed: one blocked push, then a manual read of
`proof-ledger.sh`'s source to find the `last_v` line and work out the fix by hand.

## Solution

### Approaches considered
1. **Change what counts as a passing verdict** (e.g. accept a FAIL line anywhere as long as a
   later PASS exists, without requiring the FAIL to be non-final). Rejected: this changes
   gate semantics (what passes/fails), which the task explicitly rules out; "last verdict wins"
   is a deliberate, documented, review-landed contract (the `LAST-verdict-wins` comment) that
   exists to let a noisy run retry without a stale FAIL blocking forever.
2. **Add a generic "a file was found but rejected" line with no specifics.** Rejected: it does
   not tell the operator what to change, so it does not remove the observed cost (the manual
   source read).
3. **Detect the specific near-miss shape (NEGATIVE CONTROL + a green run present, but the
   file's own final Verdict line is FAIL/INCONCLUSIVE) during the existing scan, and append a
   named, actionable hint to the same BLOCKED message when that shape is found.** Chosen: it is
   additive to the existing loop (no change to `ok`, no change to the return code), fires only
   for the exact condition the task names, and states the fix in the file's own vocabulary
   (`Result:` vs `Verdict:`).

### Chosen approach + why
Approach 3. It never changes what makes `check()` return 0 vs 1 (same `ok` variable, same
final `return 1`), so behavior is unchanged. It only adds observability at the point the
information already exists in-memory (`last_v` is already computed) but is discarded today.

### Extensibility & boundaries
- The near-miss detection is scoped to the `behavioral` class only: `stateful`'s branch never
  computes a `last_v`-shaped verdict, it checks for `rollback`/`[UNAVAILABLE` plus
  `Command:`/`Exit:`, so there is no equivalent "last line decides" trap there today. If a
  future change adds a similar last-line convention to the stateful branch, this hint logic
  should extend there too, but that is out of scope here.
- Works for both the per-file (`docs/verification/<slug>.md`) and set-wise
  (`docs/verification/<slug>/*.md`, union of a group's content) shapes, since both already
  compute an equivalent `last_v` today.

### Architecture
See `## Design` below.

## Picture
```
 push
   |
   v
 hooks/ship-gate.sh
   |
   v
 proof-ledger.sh check()
   |
   +-- classify() -> behavioral
   |
   +-- per-file / set-wise scan over docs/verification/*.md
   |     |
   |     +-- has NEGATIVE CONTROL? -- has green (Exit:0 | PASS)? -- last Verdict FAIL/INCONCLUSIVE?
   |             |                          |                              |
   |             yes                        yes                           yes  <-- NEW: record as "near miss"
   |             |                          |                              |
   |             +--------------------------+------------------------------+
   |                                        |
   |                                   ok stays 1 (unchanged: gate still blocks)
   |
   v
 override check (unchanged)
   |
   v
 BLOCKED message
   |
   +-- generic Need: lines (unchanged)
   +-- NEW: "Found <file>: has a NEGATIVE CONTROL and a PASS run, but ends on
   |         Verdict: FAIL/INCONCLUSIVE. Record the control's own outcome as
   |         `Result: RED as expected`, end the file on `Verdict: PASS`."
   v
 operator fixes the named file, re-pushes
```

## Design
obvious: this is a message-only addition inside an existing, well-commented function; no new
component, no schema/data-model change, no external integration, and no new irreversible
decision. The only design question (does this change what passes/fails) is answered directly
in `## Solution` above: it does not.

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** the same `_fresh_proof_files` list `check()` already builds, and the
  same `last_v` string already computed per file/group. No new input.
- **Internal accumulator:** `near_miss` holds one `path<TAB>last_v` line per near-miss
  identity (tab-separated so a `last_v` line containing spaces or colons never breaks the
  field split at print time). `last_v` is overwritten on every loop pass exactly like the
  existing variable of the same name; only the value captured at the moment a path is
  appended is stored, so each `near_miss` line freezes that file's own final `Verdict:` line,
  not a live reference to the loop variable.
- **Outputs / produces:** `check()`'s stderr BLOCKED block gains zero or more `Hint:` lines
  (one per near-miss identity, deduped, see the set-wise dedupe rule below) between the
  existing "Need:" paragraph and the "Type-specific shape:" line. Exit code and stdout are
  unchanged.
- **Invariants:** `check()`'s return value depends only on `ok`, exactly as today. Appending to
  `near_miss` is side-effect-free: it never sets `ok`, never triggers a `break` on its own, and
  never runs on a path where `ok` already became 0 (a real pass short-circuits the scan before
  the near-miss test is reached). `near_miss` is read, and the `Hint:` lines are printed, only
  once the function has already committed to the BLOCKED path (i.e. after the existing
  `[ "$ok" -eq 0 ] && return 0` and override-branch returns have both been passed).

### Data model changes
None.

### API changes
None (internal shell function, no external interface).

### UI changes
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-A: Write this spec.

### Phase 2: Core
- [ ] TASK-B: In the per-file loop (around line 300-315 of `lib/gate/proof-ledger.sh`), when
  the behavioral branch's full condition (NEGATIVE CONTROL present AND a green run present)
  holds but the file is rejected solely because `last_v` matches `FAIL|INCONCLUSIVE`, append
  `"$f<TAB>$last_v"` to a `near_miss` accumulator (newline-joined, matching the existing
  accumulator style used elsewhere in this file, e.g. `src_remainder` in the override branch;
  tab-separated per the Interfaces note above). Do not alter `ok`, the `break`, or any existing
  condition. Acceptance: folded into TASK-D below (the accumulator itself is an internal shell
  variable with no independent external surface; what is observable is the stderr `Hint:` line
  TASK-D produces from it).
- [ ] TASK-C: Apply the same accumulation in the set-wise (grouped) loop (around line
  319-344), using the group's content/`last_v` the same way, appending `"<group-prefix><TAB>$last_v"`.
  **Dedupe rule:** before appending a group's near-miss entry, skip it if any path already
  recorded in `near_miss` (by TASK-B, from this same scan) starts with that group's prefix , a
  member file that already qualifies as a per-file near miss on its own is not reported a
  second time as part of the group rollup. Acceptance: folded into TASK-D (case 2 in
  `## Test plan`, both the pure-group and the overlap/dedupe sub-cases).
- [ ] TASK-D: In the BLOCKED message block (around line 391-411), when `class = "behavioral"`
  and `near_miss` is non-empty, print one `Hint:` line per entry (path, tab, `last_v` split back
  apart), placed after the existing `('green run' = ...)` line and before the `Type-specific
  shape:` line, using the exact literal in `## Test plan`'s "Hint literal" block below.
  Acceptance: the fixture from TASK-B produces this exact `Hint:` line on stderr, naming the
  file, and the message is silent (no `Hint:` line) when the branch adds no proof file at all
  (the pre-existing "nothing found" case is unchanged) , see `## Test plan` cases 1-7.
- [ ] TASK-E: Write `tests/test-proof-verdict-hint.sh` per `## Test plan` below; run it and
  fix any deviation.

### Phase 3: Polish
- [ ] TASK-F: Re-read the whole `check()` function once the three edits land, confirm no
  existing test in `tests/test-proof-*.sh` changed outcome (same exit codes, same `ok`
  semantics), and run the full `tests/test-proof-*.sh` set once.

## After state
- [ ] A behavioral-class proof file with a NEGATIVE CONTROL, a green run, and a final
  `Verdict: FAIL`/`INCONCLUSIVE` line produces a BLOCKED message that names the file and states
  the exact fix (`Result: RED as expected` for the control, `Verdict: PASS` as the file's last
  line). (Today: the message is generic and never names the file.)
- [ ] A branch with no proof file at all still gets the pre-existing generic message, with no
  `Hint:` line (checkable by `bash tests/test-proof-verdict-hint.sh`, case 4).
- [ ] Every existing `tests/test-proof-*.sh` file still passes unchanged (checkable by running
  each).

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `tests/test-proof-verdict-hint.sh` covers all seven cases in `## Test plan` (1, 2a, 2b,
  3, 4, 5, 6): the per-file near miss, the pure set-wise near miss, the set-wise/per-file
  dedupe, a genuine pass, no proof file at all, an unrelated (no-control) rejection, and a
  mixed branch with both a near miss and an unrelated rejection
- [ ] No regressions in existing `tests/test-proof-*.sh` behavior

## Verification
`bash tests/test-proof-verdict-hint.sh && for t in tests/test-proof-*.sh; do bash "$t" || exit 1; done`

## Test plan

**Test file:** `tests/test-proof-verdict-hint.sh`, shaped like the existing
`tests/test-proof-override-order.sh` (a throwaway git fixture under `/tmp`, `pass()`/`fail()`
counters, a final `ALL PASS (N/N)` / `FAILS: N` line and matching exit code). Resolve the
lib under test the same way `test-proof-override-order.sh` does , relative to the test file's
own location, so the test always exercises THIS worktree's copy, never an installed kit at
`~/.claude/dwarves-kit` or `$DWARVES_KIT`:
```sh
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
```

**Hint literal (pin once, exact):**
```
  Hint: <path> has a NEGATIVE CONTROL and a green run, but its LAST Verdict line reads
  FAIL/INCONCLUSIVE ("<last_v>"). The gate reads the file's FINAL Verdict line as the outcome:
  record the negative control's own outcome as `Result: RED as expected` (not `Verdict:`), and
  end the file on `Verdict: PASS` after the real run (the shape lib/gate/negctl.sh itself
  emits: `Exit: 0` / `Verdict: PASS` are the two valid "green run" spellings this gate already
  accepts).
```
Every case below asserts against this literal (path and `<last_v>` substituted), not a
paraphrase.

Cases, each built as a fixture repo with a `docs/verification/README.md` marker and a
behavioral (`.sh`) diff, matching `make_fixture()` in `test-proof-override-order.sh`:

1. **Near miss, per-file shape.** `docs/verification/<slug>.md` contains a green run
   (`Exit: 0`, or `Verdict: PASS`) block, then a `## ... [negative control]` block whose own
   line reads `Verdict: FAIL as expected` as the file's true last `Verdict:` line. Assert
   `check()` exits 1 (unchanged) AND its stderr contains the Hint literal naming this file.
2a. **Near miss, pure set-wise shape.** Content split across `docs/verification/<slug>/run.md`
   (green only) and `docs/verification/<slug>/control.md` (`NEGATIVE CONTROL` +
   `Verdict: FAIL as expected` only) , neither file alone satisfies the per-file condition
   (each is missing one half), only the group's union does. Assert the hint fires exactly
   once, identified by the group prefix `docs/verification/<slug>/`.
2b. **Set-wise dedupe.** `docs/verification/<slug>/run.md` alone already carries the FULL
   near-miss shape (green run + NEGATIVE CONTROL + final `Verdict: FAIL as expected`, so the
   per-file loop flags it on its own), plus a sibling `docs/verification/<slug>/notes.md` with
   unrelated prose in the same group directory. Assert `check()`'s stderr contains **exactly
   one** Hint line, naming `docs/verification/<slug>/run.md` (the per-file entry), and does
   NOT also print a second hint for the group prefix (the dedupe rule in TASK-C).
3. **Genuine pass (control group).** Same as case 1 but the file's true last line is
   `Verdict: PASS` (the control's own outcome recorded as `Result: RED as expected` instead of
   `Verdict:`, per the Hint literal's own guidance). Assert `check()` exits 0 and prints
   nothing (proves the fix doesn't fire when nothing is wrong).
4. **No proof file at all (control group).** No `docs/verification/*.md` added. Assert
   `check()` exits 1 and its stderr contains the existing generic `Need:` text but NO `Hint:`
   line (proves the new hint is scoped to the near-miss shape, not printed unconditionally).
5. **Unrelated rejection, no NEGATIVE CONTROL at all (control group, the over-broad-match
   guard).** A proof file with a green run (`Exit: 0`) whose final `Verdict:` line is
   `Verdict: FAIL` (a plain failed run, no control attempted, no `NEGATIVE CONTROL` marker
   anywhere in the file). Assert `check()` exits 1 with **no** `Hint:` line , the hint's first
   condition (`NEGATIVE CONTROL` present) is false, so this must fall through to the plain
   generic message untouched, proving the hint cannot fire on a merely-failing file that never
   attempted a control.
6. **Mixed branch (edge case 3).** Two proof files land on the same branch: `docs/verification/
   near-miss-slug.md` (the case-1 near miss) and `docs/verification/unrelated-slug.md` (the
   case-5 shape: green + plain FAIL, no control). Assert `check()` exits 1 and stderr contains
   **exactly one** `Hint:` line, naming only `near-miss-slug.md`.

**Negative control (mechanised, mutate mode, run AFTER the feature commit lands):**
```
bash lib/gate/negctl.sh . 'bash tests/test-proof-verdict-hint.sh' 'git checkout origin/master -- lib/gate/proof-ledger.sh'
```
The mutate command reverts just `lib/gate/proof-ledger.sh` to its pre-fix state at
`origin/master` (where the hint logic does not exist); negctl.sh requires the new test suite
to go RED under that reversion (proving the test actually exercises the new code, not a
tautology) and then restores the worktree's own `lib/gate/proof-ledger.sh`, verifying the
suite is GREEN again. `git checkout HEAD --` (its restore step) requires a clean tracked tree
first, so this command runs only once TASK-B through TASK-E are committed.

## Edge Cases
1. Proof file has a NEGATIVE CONTROL and a green run, but the LAST `Verdict:` line is
   `INCONCLUSIVE` rather than `FAIL`: the hint still fires (the grep pattern already covers
   both).
2. Proof file has a NEGATIVE CONTROL, no green run at all (relies on `_has_committed_image`
   instead), and a final FAIL/INCONCLUSIVE verdict: this is still a near miss under the same
   condition (the existing `{ grep -qE '...' "$p" || _has_committed_image "$p" "$root"; }`
   clause), so the hint fires for the image-evidence path too.
3. Multiple proof files on the branch: one is a genuine near miss, another has no
   NEGATIVE CONTROL at all (a different, unrelated failure mode). Only the near-miss file gets
   a `Hint:` line; the other stays covered by the existing generic `Need:` text. Covered by
   `## Test plan` case 6.
4. Set-wise group where only one file in the group carries the final Verdict line: the grouped
   `last_v` is computed from the concatenated, sorted content exactly as `check()` already does
   today, so the hint fires (or not) based on the same union the pass/fail decision already
   uses, no new source of truth.
5. A `stateful`-class change with an equivalent "looks right but rejected" shape: out of scope
   per `## Solution` (Extensibility & boundaries); the generic message is unchanged for
   `stateful`.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Hint logic accidentally flips `ok` or the return code | `test-proof-verdict-hint.sh` case 3 (a genuinely passing file) starts failing, or any existing `test-proof-*.sh` starts failing | TASK-B/C acceptance requires `ok`/`break`/existing conditions untouched; run the full existing suite in TASK-F before considering this done |
| Hint fires on a file that has no NEGATIVE CONTROL at all (over-broad match) | `test-proof-verdict-hint.sh` case 5 (a non-NEGATIVE-CONTROL FAIL-ending file) asserts no hint | Reuse the exact existing `grep -qi 'NEGATIVE CONTROL'` condition already gating the win path; do not write a new, looser pattern |
| Set-wise loop re-reports a file already flagged by the per-file loop (duplicate hint for one underlying issue) | `test-proof-verdict-hint.sh` case 2b asserts exactly one `Hint:` line | TASK-C's dedupe rule: skip a group append when an existing `near_miss` path already falls under that group's prefix |

## Out of Scope
- Changing which verdict wins (last-verdict-wins stays as-is).
- Extending the hint to the `stateful` branch.
- Any change to `override()`, `is_overridden()`, `classify()`, or `delivery_ratio()`.

## Touches
- lib/gate/**
- tests/**
- docs/verification/**

## Decision Log
- DEC-A: Additive-only hint appended to the existing BLOCKED message, not a rewrite of the
  message or the pass/fail logic. Rationale: the task explicitly states "no change to what
  passes or fails"; alternatives rejected: changing verdict semantics (changes behavior),
  a generic unnamed hint (does not remove the observed cost).

## Open questions
(none)
