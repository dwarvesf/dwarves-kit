# SPEC-324: render the AC1 pitch sample into a temp dir, not the tracked proof file

**Status:** VALIDATED
Lane: normal
Type: spec-fix
**Proof:** `docs/verification/pitch-test-tmp-out.md`; `tests/test-pitch.sh`

## Problem

`tests/test-pitch.sh` AC1 (line 74) runs:

```
( cd "$KIT_DIR" && bash "$LIB" render kit-emit-sweep --out "$PROOF_DIR/sample-pitch.md" ) >/dev/null
```

`$PROOF_DIR/sample-pitch.md` is `docs/verification/pitch-command/sample-pitch.md`, a file
tracked in git. Every `bash tests/test-pitch.sh` run (directly, or via `tests/run-all.sh`)
overwrites it with a fresh live render, so `git status --porcelain` comes back dirty after
every test pass even when nothing about the feature changed. A session restored this file by
hand four times in one day.

The file's own header (`tests/test-pitch.sh` lines 6-11) explains why AC1 renders against a
*real* shipped rid at all: the PR-link and grill-skip checks need ledger content that only
exists on a machine that already ran/shipped `kit-emit-sweep`, so a **frozen fixture**
(`tests/fixtures/pitch/real-sample/`, via `_render_with_origin`) covers those two assertions
on a fresh CI checkout. That fixture path is untouched by this spec. AC1's *first* three
assertions (lines 75, 76, 79: existence, section count, spec name) are different: they exist
to prove the assembler renders a real rid into a well-formed 5-section doc at all, and they
read the file the render just wrote.

A reason for regenerating the tracked file specifically *was* found, in
`docs/implementation-notes/kit-pitch.md` (~lines 86-90): when the frozen fixture was added
(SPEC-140), the tracked `sample-pitch.md` was deliberately left auto-refreshing on every local
run, on the reasoning that it stays "genuinely real evidence on a machine that has the
ledger." That reasoning is sound for a *human-facing* artifact but does not license a *test*
to carry the side effect: a test's job is to assert pass/fail, and a passing test run must
never leave the tree dirty regardless of what else it does well. The fix keeps the tracked
file as real evidence, just refreshed by an explicit, separate command instead of as a test
side effect (see `## After state`).

## Contract

- `tests/test-pitch.sh`'s AC1 render (currently line 74) writes to a fresh temp path (`mktemp
  -d`), never to `docs/verification/pitch-command/sample-pitch.md`.
- The three existing reads of that render target (lines 75, 76, 79: existence check, section
  count, spec-name grep) now read the temp path instead. Their pass/fail behavior is
  unchanged; only the file they inspect moves.
- A new assertion in the AC1 block asserts the literal string `$PROOF_DIR/sample-pitch.md`
  (or the tracked path it expands to) appears nowhere in the AC1 block except its own `PROOF_DIR=`
  definition -- a self-check so a half-done repoint (one read fixed, another missed) fails
  loudly instead of passing silently.
- `docs/verification/pitch-command/sample-pitch.md` stays in the repo as the canonical proof
  sample. The test no longer writes it. It is not deleted and not asserted against by the test
  (a committed doc is not a test fixture), and not covered by the negative control below (the
  mutation targets the render destination, not the sample's content).
- The tracked file's refresh moves from "implicit, every test run" to "explicit, on demand":
  `bash lib/pitch.sh render kit-emit-sweep --out docs/verification/pitch-command/sample-pitch.md`,
  named in `## After state` below and recorded as a delta note in
  `docs/implementation-notes/kit-pitch.md` (which is where the original "keep it live" decision
  lives).
- The `_render_with_origin real-sample` fixture path (lines 85-89) is untouched: it already
  renders into a `_mkws` scratch dir, never the tracked file.
- After `bash tests/test-pitch.sh` (alone, or via `bash tests/run-all.sh`), `git status
  --porcelain` is empty.

## Design

obvious: swap one `--out` argument's target from a tracked path to a `mktemp -d` scratch
path, and repoint the two assertions that read it at the same variable. No change to
`lib/pitch.sh`, no new fixture, no change to what AC1 proves.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: render AC1's live sample into a temp dir | `tests/test-pitch.sh` | line-74 render writes to `$(mktemp -d)/sample-pitch.md` (or equivalent), not `$PROOF_DIR/sample-pitch.md`; the three reads (lines 75, 76, 79: existence, section count, spec name) point at that temp path |
| T2: drop the now-unused tracked-path write | `tests/test-pitch.sh` | no `mkdir -p "$PROOF_DIR"` / write aimed at `docs/verification/pitch-command/sample-pitch.md` remains in the script |
| T3: guard against a half-done repoint | `tests/test-pitch.sh` | new assertion in the AC1 block: the tracked path string appears nowhere in the block outside its own `PROOF_DIR=` definition |
| T4: document the explicit manual refresh | `docs/implementation-notes/kit-pitch.md` | delta note: the test no longer auto-refreshes `sample-pitch.md`; names the refresh command (`bash lib/pitch.sh render kit-emit-sweep --out docs/verification/pitch-command/sample-pitch.md`) |
| T5: proof + notes for this fix | `docs/verification/pitch-test-tmp-out.md`, `docs/implementation-notes/pitch-test-tmp-out.md`, `docs/CHANGELOG.md` | green run + negative control recorded; delta-only implementation note; one CHANGELOG line |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Suite runs clean | `bash tests/test-pitch.sh` from a clean tree | exit 0, all AC green |
| Tree stays clean | `bash tests/run-all.sh --changed` (or `tests/test-pitch.sh` alone), then `git status --porcelain` | empty output |
| Temp render still proves the assembler | inspect the temp path the AC1 render just wrote | contains 5 numbered sections (`^## [1-5]\. `) and names the real spec (`command emit sweep`) |
| Tracked sample untouched | `git diff --stat -- docs/verification/pitch-command/sample-pitch.md` before/after the suite runs | no diff |
| Frozen fixture path unaffected | AC1's PR-link / grill-skip assertions (`_render_with_origin real-sample`) | unchanged, still pass |
| Half-done repoint is caught | temporarily reintroduce one stray read of `$PROOF_DIR/sample-pitch.md` in the AC1 block | the new self-check assertion (T3) fails |
| Explicit refresh still works | `bash lib/pitch.sh render kit-emit-sweep --out docs/verification/pitch-command/sample-pitch.md` run by hand | tracked file updates; not exercised by the test suite |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-pitch.sh" "<sed pointing the render back at the tracked docs/verification/pitch-command/sample-pitch.md path>"` | green before, RED under the mutation (dirty tracked file / or a targeted assertion fails), green + clean tree after restore |

## Verification

`bash tests/test-pitch.sh` exits 0. `bash tests/run-all.sh --changed` exits 0 with `git status
--porcelain` empty afterward. The negative control above is recorded in
`docs/verification/pitch-test-tmp-out.md`.

## After state

`tests/test-pitch.sh` proves the same things it always proved (AC1 through AC7), but running
it -- alone or via the suite -- never dirties the tree. `docs/verification/pitch-command/sample-pitch.md`
stays the canonical proof sample, no longer regenerated as a test side effect. Refreshing it
(when the real `kit-emit-sweep` ledger content moves on) is now an explicit, separate command:

```
bash lib/pitch.sh render kit-emit-sweep --out docs/verification/pitch-command/sample-pitch.md
```

Not covered: the frozen-fixture path (`tests/fixtures/pitch/real-sample/`) and the
`_render_with_origin` mechanism are untouched. Whether `docs/verification/pitch-command/sample-pitch.md`
itself is stale relative to the current `kit-emit-sweep` ledger state is out of scope; running
the command above by hand, if ever needed, is a separate task.

## Decision Log

- Lane: normal, per the dispatch instruction; the diff is a test-only fix with no behavioral
  change to `lib/pitch.sh` or the command it backs.
- A reason for the tracked file's auto-refresh does exist: `docs/implementation-notes/kit-pitch.md`
  (~lines 86-90) deliberately kept it live at SPEC-140 time, as "genuinely real evidence on a
  machine that has the ledger." That reasoning holds for the artifact, not for the test: a
  test's contract is pass/fail, and a green run leaving the tree dirty is itself a bug. This
  spec keeps the artifact's freshness goal, moves the refresh out of the test into an explicit
  command, and documents that trade in `docs/implementation-notes/kit-pitch.md` (T4) next to
  the original decision it revises.
- Scope held to the AC1 render target. No change to what AC1 proves, no change to the frozen
  fixture, no change to `lib/pitch.sh`.
