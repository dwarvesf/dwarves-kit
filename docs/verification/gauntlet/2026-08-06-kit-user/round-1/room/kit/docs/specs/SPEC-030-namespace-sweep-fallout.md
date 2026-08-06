# Spec: Namespace sweep fallout (install.sh + hooks still emit /user:)

Generated: 2026-05-22
Status: VALIDATED

## Problem

SPEC-029 swept the dead `/user:<cmd>` invocation form to `/kit:<cmd>` across the
live markdown docs and added a meta-test guard. But its sweep set and its guard
were **markdown-only** (SPEC-029 "File scope" lists only `*.md`; DEC-004 scans
`git ls-files '*.md'`). Two user-facing runtime surfaces were never in scope and
still emit the dead form:

- **`install.sh`** (lines 29, 209, 279, 297) echoes `/user:` to the operator,
  including `Run /user:start to detect project state...` (the first thing a new
  bash installer sees after a successful install).
- **`hooks/*.sh`** print `/user:` in live output: `session-state-save.sh:90`
  (`Run /user:start ...`), `context-readiness.sh:86,94,102,104,107` (the
  `SUGGEST=` next-command hints), `anti-rationalization.sh:92` (the guess-fix
  block reason) and `:53` (a code comment).

The SPEC-029 guard passes anyway because its selector is `git ls-files '*.md'`;
`install.sh` and `hooks/*.sh` are `.sh`, so the guard never scans them. ID-031
part 3 promised "no `/user:` in shipped docs **and install**", and part 2 named
`install.sh` explicitly. SPEC-029 delivered the docs half; this spec finishes the
install/runtime half and closes the guard hole so it cannot recur. This is the
re-open-shipped (ID-025) class: a follow-up spun from a shipped spec.

This is the exact failure ID-031 was created to kill ("invocation drift the kit's
own guards never caught"), reproduced one layer down: the guard that was the fix
has the same blind spot it was meant to remove.

## Solution

### Approaches considered

1. **Sweep install.sh + hooks to the plugin-canonical `/kit:<cmd>`** (match the
   docs). Rejected for the runtime surfaces: a bash-install user resolves bare
   `/<cmd>`, not `/kit:<cmd>`, so `/kit:start` would be a new wrong form for that
   cohort (re-introducing drift, just a different flavor).
2. **Sweep each surface to the form correct for its own cohort, hooks neutral
   (chosen).** `install.sh` knows it is the bash path, so it prints bare `/<cmd>`.
   Hooks run under both install paths and cannot detect which, so they name the
   command slash-free. Extend the meta-test guard to scan both surfaces.
3. **Make hooks detect the install path and branch the string.** Rejected: a hook
   has no reliable signal for plugin-vs-bash, and PHILOSOPHY forbids speculative
   complexity (every script readable in 30s).

### Chosen approach + why

Approach 2. The invocation form is install-path dependent, so the correct fix is
per-surface, not one literal. The truth table (no single slash form serves both
cohorts) forces it:

| form in output | bash install (`/<cmd>`) | plugin install (`/kit:<cmd>`) |
|---|---|---|
| `/user:start` | unknown command | unknown command |
| `/start` | resolves | does not resolve |
| `/kit:start` | does not resolve | resolves |
| `start` (no slash) | correct guidance | correct guidance |

`install.sh` is unambiguous (it IS the bash path) so it uses `/<cmd>`. Hooks must
serve both cohorts with one string and have no channel for README's "drop the
prefix" note, so they go slash-free. The guard extension makes the win durable.

### The hook-form decision (load-bearing)

Hooks use **neutral, slash-free command names** (e.g. `` consider `spec-validate` ``).
This is SPEC-029's Approach 3 (neutral phrasing), which SPEC-029 *rejected for
docs* because docs can carry the dual-ship note (DEC-001) and neutral reads worse
across ~70 references. That rejection does not bind here: hooks are a different
context (no note channel, must serve both cohorts, only a handful of strings), so
neutral is correct for hooks even though `/kit:` stays canonical for docs. Recorded
as DEC-002; this is the spec's primary point for review to attack.

### File scope: sweep vs exempt

SWEEP (live runtime output):
- `install.sh` lines 29, 209, 279, 297 -> bare `/<cmd>` (slash, no namespace).
- `hooks/session-state-save.sh`, `hooks/context-readiness.sh`,
  `hooks/anti-rationalization.sh` -> slash-free command names. The
  `anti-rationalization.sh:53` comment is swept too (the guard cannot distinguish
  comment from output, and leaving it would keep the guard red).

GUARD (extend, do not replace):
- `tests/test-meta.sh` namespace block also scans `install.sh` and `hooks/*.sh`
  for `/user:`.

EXEMPT (unchanged):
- All `*.md` (already handled by SPEC-029; not re-touched here).
- `tests/test-meta.sh`'s own body, which names `/user:` in its guard comment. The
  `.sh` scan targets `install.sh` + `hooks/*.sh` only, never `tests/`, so the guard
  does not self-flag.

## Technical Design

### Interfaces (I/O contract)

- Consumes: the `/user:` literal strings in `install.sh` and `hooks/*.sh`.
- Produces: `install.sh` with bare `/<cmd>` echoes; hooks with slash-free command
  names; an extended `tests/test-meta.sh` namespace guard.
- Invariants: hook **control flow, exit codes, and block/allow decisions are
  byte-unchanged** (only output string literals change); `*.md` files untouched;
  the existing `*.md` guard assertion is unchanged (the new `.sh` scan is additive).

### Infrastructure changes

The `tests/test-meta.sh` namespace guard (currently `git ls-files '*.md' | grep
-vE <exempt> | xargs grep -l '/user:'`) gains a second source: the tracked
`install.sh` and `hooks/*.sh` files, unioned into the same `USER_NS_HITS` check.
One assertion, two file sources. Denylist spirit (SPEC-029 DEC-004): a future hook
is covered automatically.

## Task Breakdown

### Phase 1: Foundation (guard first, TDD red)
- [x] TASK-001: Extend the `tests/test-meta.sh` namespace guard to also scan
  `install.sh` and `hooks/*.sh` for `/user:` (union into `USER_NS_HITS`; do NOT
  scan `tests/`). Acceptance: run `bash tests/test-meta.sh`; the namespace guard
  now FAILS (red), listing `install.sh` + the three hook files; no `tests/` or
  `*.md` file appears in the offending list.

### Phase 2: Core (sweep, turn it green)
- [x] TASK-002: Sweep `install.sh` `/user:<x>` -> `/<x>` (lines 29, 209, 279,
  297; bare with slash). Acceptance: `grep -n '/user:' install.sh` returns
  nothing; `install.sh --help`/dry behavior otherwise unchanged.
- [x] TASK-003: Sweep `hooks/session-state-save.sh`,
  `hooks/context-readiness.sh`, `hooks/anti-rationalization.sh` `/user:<x>` ->
  slash-free `` `<x>` `` in all output strings and the one comment. Acceptance:
  `grep -rn '/user:' hooks/` returns nothing; hook decisions/exit codes unchanged
  (verified by `bash tests/test-hooks.sh`).

### Phase 3: Polish
- [x] TASK-004: Run the full suite green and record the change. Acceptance:
  `bash tests/test-meta.sh && bash tests/test-hooks.sh` both pass; `_meta/BACKLOG.md`
  ID-032 advanced; `CHANGELOG.md` `[Unreleased]` notes the install/hook sweep +
  guard extension.

## After state
- [x] Zero `/user:` in `install.sh` and `hooks/*.sh`. Checkable: `grep -rn '/user:' install.sh hooks/` returns nothing.
- [x] `install.sh` prints bare `/<cmd>` (e.g. `Run /start to detect project state...`).
- [x] Hook next-command hints are slash-free command names (e.g. `` consider `spec-validate` ``).
- [x] The `tests/test-meta.sh` namespace guard scans `install.sh` + `hooks/*.sh`; reintroducing `/user:` to any of them turns it red. Checkable: temporarily add `/user:x` to a hook -> `bash tests/test-meta.sh` fails.
- [x] No `*.md` file changed; hook control flow / exit codes unchanged (`bash tests/test-hooks.sh` green).

## Acceptance Criteria (global)
- [x] All tasks pass their individual acceptance criteria
- [x] The extended guard goes red-before / green-after
- [x] No `*.md` file is modified by this spec (SPEC-029's domain)
- [x] No hook behavior change: `bash tests/test-hooks.sh` passes unchanged
- [x] No regressions: `bash tests/test-meta.sh && bash tests/test-hooks.sh` both pass

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh` (both green), and
`grep -rn '/user:' install.sh hooks/` returns nothing.

## Edge Cases
1. `tests/test-meta.sh` itself contains `/user:` in its guard comment. Expected:
   the `.sh` scan targets `install.sh` + `hooks/*.sh` only, never `tests/`, so the
   guard never flags its own description.
2. `anti-rationalization.sh:53` has `/user:debug` in a code comment, not user
   output. Expected: swept anyway (to slash-free `debug`); the guard cannot
   distinguish comment from output, and an unswept comment keeps it red.
3. A future hook reintroduces `/user:`. Expected: the extended denylist scan of
   `hooks/*.sh` catches it (the SPEC-029 DEC-004 anti-rot property, now covering
   runtime surfaces).

## Out of Scope
- Re-touching `*.md` docs (README/MANUAL/etc.): SPEC-029 already swept them to the
  plugin-canonical `/kit:` form. This spec does not change the doc form.
- The bash-vs-plugin dual-ship decision itself: settled in SPEC-029 DEC-001
  (docs plugin-canonical with a prefix-drop note). This spec only fixes runtime
  output, which that note cannot reach.
- Changing hook control flow, exit codes, or block/allow logic. String output only.
- Asserting a positive `/kit:` form in the guard: it stays `/user:`-absence-only
  (inherits SPEC-029 DEC-005), so install.sh's `/<cmd>` and hooks' slash-free
  names both pass.

## Decision Log
- DEC-001: `install.sh` echoes use bare `/<cmd>` (slash, no namespace). Rationale: install.sh IS the bash-install path; it symlinks flat personal commands that resolve bare, so its output must match what the operator just installed. `/kit:` would be wrong for that cohort.
- DEC-002: Hook output uses neutral, slash-free command names. Rationale: a hook runs under both install paths, cannot detect which, and no single slash form serves both (truth table above); a hook has no channel to carry README's prefix-drop note. This is SPEC-029's rejected-for-docs Approach 3, correct here because the context differs (no note channel, must serve both, few strings). Does not contradict SPEC-029 DEC-001; docs stay plugin-canonical.
- DEC-003: The guard is extended (not replaced) to scan `install.sh` + `hooks/*.sh`, excluding `tests/`. Rationale: ID-031 part 3 promised "no `/user:` in shipped docs/install"; SPEC-029 implemented `*.md`-only, leaving install/runtime uncovered. Matches SPEC-029 DEC-004's denylist spirit (future files covered) without scanning `tests/` (which documents the token).
- DEC-004: The guard stays `/user:`-absence-only (inherits SPEC-029 DEC-005). Rationale: positive-form detection is noisy; absence-of-the-dead-form is the durable invariant. Accepted limit: the guard prevents `/user:` regression in install/hooks, not every wrong form.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
