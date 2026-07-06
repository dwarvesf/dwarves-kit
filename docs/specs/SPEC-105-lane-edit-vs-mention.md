# SPEC-105: lane-classify edit-vs-mention signal

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

`lib/classify/lane-classify.sh`'s `kit-machinery` hard-gate matches any textual MENTION of a machinery
basename (`gate-ledger`, `mega-merge`, `lane-classify`, ...), so a doc / research / audit task
ABOUT the machinery over-classifies to `full` (SPEC-073 lane-rule audit, ID-088). It fails SAFE
(over-gates, never under-gates), so it is low urgency, but it adds friction on the wave's own
doc-heavy tasks (every sub-goal of this very wave classified `full` off a machinery mention).

## Solution

Give the classifier a touched-files signal. `kit-machinery` is a proxy for "touches the
enforcement surface", which is a FILE fact, not a semantic one (unlike `auth` / `data-model`,
which are subject-risky regardless of the files). So:

- Add an optional `--files "<paths>"` argument to `classify` / `explain` / `check`.
- When `--files` IS supplied, the `kit-machinery` gate escalates on an actual EDIT to a machinery
  file (a touched path under `lib/` or `hooks/`, SPEC-069's own definition of the enforcement
  layer), NOT on a description that merely names a basename.
- When `--files` is NOT supplied, the current text-only behavior is UNCHANGED (a mention
  escalates), so nothing regresses for callers that pass none. This is the `bug`/`backfill`/`tiny`
  precedence-preserving, additive discriminator the goal asked for; the flag-scoring model and the
  other (semantic) hard-gates are untouched.

Implementation: two small helpers (`_extract_files` pulls `--files` out of the args into
`FILES`/`FILES_SET`; `_files_touch_machinery` tests the paths against `lib/`/`hooks/`) and a
special-case for the `kit-machinery` branch of `classify_core`'s hard-gate loop. `--files` is
parsed in the dispatch and stripped before the description reaches `classify_core`.

## Verification

```bash
cd dwarves-kit
bash lib/classify/lane-classify.sh classify --files "" "explain mega-merge.sh in the architecture doc"   # normal
bash lib/classify/lane-classify.sh classify --files "lib/goal/mega-merge.sh" "add a guard clause"              # full
bash lib/classify/lane-classify.sh classify "explain mega-merge.sh in the architecture doc"              # full (legacy, no --files)
bash tests/test-lane-classify.sh   # 23/23; the new edit-vs-mention block + regression guard
```

Pins (in `tests/test-lane-classify.sh`, the classifier suite created by the prior kit-telemetry
wave): mention-with-`--files` -> not full; edit (`--files lib/…` or `hooks/…`) -> full; a test-only
edit that names machinery -> not full; semantic `auth` still full with `--files`; **no-`--files` ->
current text behavior unchanged** (the regression guard). All green on bash 5.x AND bash 3.2 (the
macos CI runner).

**Not yet wired into callers (in scope: the discriminator + interface only).** No command passes
`--files` yet (`commands/assign.md`, `commands/dispatch.md`, `lib/queue/orchestrate.sh:_emit_start` all
still classify text-only), so the over-gate this fixes still occurs in practice until a follow-up
wires `--files` at a site that has the touched-file list (the `git diff` at spec->build). That
wiring is deliberately out of this sub-goal (it owed the signal, not the plumbing); tracked as a
follow-up in the mega-goal NOTES `## Proposed additions`. This sub-goal ships the capability + its
proof, not a live behavior change on existing callers.

## After state

- `lib/classify/lane-classify.sh` accepts `--files` on `classify`/`explain`/`check` and escalates the
  `kit-machinery` gate on a machinery-file edit, not a mention; text-only behavior unchanged
  without `--files`.
- `docs/verification/edit-vs-mention.md` carries the run-table + negative controls.

## Open questions

The machinery-file predicate is "touches `lib/` or `hooks/`" (SPEC-069's enforcement layer), which
is conservative (a non-enforcement `lib/` helper edit also escalates) but drift-free (no second
copy of the machinery basename list to rot). The alternative (match specific `lib/<basename>.sh`)
was rejected to avoid drift; noted for a future refinement if over-gating a `lib/` helper edit ever
bites.
