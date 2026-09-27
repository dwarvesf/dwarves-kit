# Spec: proof-of-done BLOCKED message names a rejected verdict file
Generated: 2026-09-27
Status: DRAFT
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
- **Outputs / produces:** `check()`'s stderr BLOCKED block gains zero or more `Hint:` lines
  (one per near-miss file/group) between the existing "Need:" paragraph and the "Type-specific
  shape:" line. Exit code and stdout are unchanged.
- **Invariants:** `check()`'s return value depends only on `ok`, exactly as today. The new hint
  logic must never set `ok=0` and must never be reached when `ok` is already 0 (i.e. it only
  runs on the already-decided BLOCKED path, right before the message is printed).

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
- [x] TASK-A: Write this spec, validated by a fresh-context validator.

### Phase 2: Core
- [ ] TASK-B: In the per-file loop (around line 300-315 of `lib/gate/proof-ledger.sh`), when
  the behavioral branch's full condition (NEGATIVE CONTROL present AND a green run/PASS
  present) holds but the file is rejected solely because `last_v` matches
  `FAIL|INCONCLUSIVE`, append that file's path to a `near_miss` accumulator (newline-joined,
  matching the existing accumulator style used elsewhere in this file, e.g. `src_remainder` in
  the override branch). Do not alter `ok`, the `break`, or any existing condition.
  Acceptance: a fixture proof file with a NEGATIVE CONTROL marker, a green
  `Exit: 0`/`Verdict: PASS` line, and a final `Verdict: FAIL as expected` line as its true last
  line lands in `near_miss` with its correct relative path, while `check()` still returns 1
  for it exactly as before the change.
- [ ] TASK-C: Apply the same accumulation in the set-wise (grouped) loop (around line
  319-344), using the group's content/last_v the same way, appending the group's representative
  path(s) (or the group prefix) to `near_miss`.
  Acceptance: an equivalent fixture split across `docs/verification/<slug>/run.md` +
  `.../control.md` produces the same `near_miss` entry via the grouped path.
- [ ] TASK-D: In the BLOCKED message block (around line 391-411), when `class = "behavioral"`
  and `near_miss` is non-empty, print one line per entry, placed after the existing
  `('green run' = ...)` line and before the `Type-specific shape:` line:
  `  Hint: <path> has a NEGATIVE CONTROL and a PASS run, but its LAST Verdict line reads
  FAIL/INCONCLUSIVE ("<last_v-for-that-file>"). The gate reads the file's FINAL Verdict line
  as the outcome: record the negative control's own outcome as ` + "`Result: RED as expected`"
  + ` (not ` + "`Verdict:`" + `), and end the file on ` + "`Verdict: PASS`" + ` after the real
  run.`
  Acceptance: the fixture from TASK-B produces this exact `Hint:` line on stderr, naming the
  file, and the message is silent (no `Hint:` line) when the branch adds no proof file at all
  (the pre-existing "nothing found" case is unchanged).
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
  `Hint:` line (checkable by `bash tests/test-proof-verdict-hint.sh`, case "no file").
- [ ] Every existing `tests/test-proof-*.sh` file still passes unchanged (checkable by running
  each).

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `tests/test-proof-verdict-hint.sh` covers: (a) the near-miss shape producing the named
  hint, (b) the pre-existing "no proof file" shape producing no hint, (c) a genuinely PASSing
  proof file still passing (no message at all)
- [ ] No regressions in existing `tests/test-proof-*.sh` behavior

## Verification
`bash tests/test-proof-verdict-hint.sh && for t in tests/test-proof-*.sh; do bash "$t" || exit 1; done`

## Test plan

**Test file:** `tests/test-proof-verdict-hint.sh`, shaped like the existing
`tests/test-proof-override-order.sh` (a throwaway git fixture under `/tmp`, `pass()`/`fail()`
counters, a final `ALL PASS (N/N)` / `FAILS: N` line and matching exit code).

Cases, each built as a fixture repo with a `docs/verification/README.md` marker and a
behavioral (`.sh`) diff, matching `make_fixture()` in `test-proof-override-order.sh`:

1. **Near miss, per-file shape.** `docs/verification/<slug>.md` contains a green run
   (`Exit: 0`, or `Verdict: PASS`) block, then a `## ... [negative control]` block whose own
   line reads `Verdict: FAIL as expected` as the file's true last `Verdict:` line. Assert
   `check()` exits 1 (unchanged) AND its stderr contains a `Hint:` line naming this file and
   the exact remediation text (`Result: RED as expected`, `Verdict: PASS`).
2. **Near miss, set-wise shape.** Same content split across
   `docs/verification/<slug>/run.md` (green) and `docs/verification/<slug>/control.md`
   (`Verdict: FAIL as expected` last). Assert the same hint fires, naming the group.
3. **Genuine pass (control group).** Same as case 1 but the file's true last line is
   `Verdict: PASS` (control's own outcome recorded as `Result: RED as expected` instead of
   `Verdict:`). Assert `check()` exits 0 and prints nothing (proves the fix doesn't fire when
   nothing is wrong).
4. **No proof file at all (control group).** No `docs/verification/*.md` added. Assert
   `check()` exits 1 and its stderr contains the existing generic `Need:` text but NO `Hint:`
   line (proves the new hint is scoped to the near-miss shape, not printed unconditionally).
5. **Unrelated rejection (control group).** A proof file with a green run and a final
   `Verdict: PASS` line but no `NEGATIVE CONTROL` marker at all. Assert `check()` exits 1 with
   no `Hint:` line (the existing generic message is the only output; a different failure mode
   must not be mistaken for this one).

**Negative control (mechanised, base-ref mode):** this repo's own checkout is shared and
often dirty (per `lib/gate/negctl.sh`'s own rationale for `--base-ref` mode), and the fix does
not exist yet at `origin/master`. Prove the CURRENT behavior (no hint) at the pre-fix ref
directly, then prove the fixed behavior only exists after this branch's commit:

```
bash lib/gate/negctl.sh --base-ref origin/master . 'bash tests/test-proof-verdict-hint.sh'
```

`tests/test-proof-verdict-hint.sh` does not exist at `origin/master`, so this command is
expected to fail at the `test_cmd` step there (no such file) -- which negctl.sh reports as
`Exit: <nonzero>` and, since a nonzero exit is what `--base-ref` mode wants (RED expected),
prints `Verdict: PASS`, correctly proving the pre-fix ref cannot satisfy the new test. Record
this alongside the direct run of case 1 against the base ref's `proof-ledger.sh` (extracted the
same way, or via `git show origin/master:lib/gate/proof-ledger.sh`) showing case 1's assertion
on the `Hint:` line fails there (RED), then passes on this branch's HEAD (green), which is the
actual revert -> RED -> restore shape for THIS specific change.

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
   a `Hint:` line; the other stays covered by the existing generic `Need:` text.
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
| Hint logic accidentally flips `ok` or the return code | `test-proof-verdict-hint.sh` case (c) (a genuinely passing file) starts failing, or any existing `test-proof-*.sh` starts failing | TASK-B/C acceptance requires `ok`/`break`/existing conditions untouched; run the full existing suite in TASK-F before considering this done |
| Hint fires on a file that has no NEGATIVE CONTROL at all (over-broad match) | `test-proof-verdict-hint.sh` case with a non-NEGATIVE-CONTROL FAIL-ending file asserts no hint | Reuse the exact existing `grep -qi 'NEGATIVE CONTROL'` condition already gating the win path; do not write a new, looser pattern |

## Out of Scope
- Changing which verdict wins (last-verdict-wins stays as-is).
- Extending the hint to the `stateful` branch.
- Any change to `override()`, `is_overridden()`, `classify()`, or `delivery_ratio()`.

## Touches
Not intended for `/kit:dispatch` fan-out (single-file, single-branch full-lane spec).

## Decision Log
- DEC-A: Additive-only hint appended to the existing BLOCKED message, not a rewrite of the
  message or the pass/fail logic. Rationale: the task explicitly states "no change to what
  passes or fails"; alternatives rejected: changing verdict semantics (changes behavior),
  a generic unnamed hint (does not remove the observed cost).

## Open questions
(none)
