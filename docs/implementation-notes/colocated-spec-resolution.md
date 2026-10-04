# Implementation notes: colocated-spec-resolution

Spec: `docs/specs/SPEC-386-colocated-spec-resolution.md`. This file holds the delta from the spec only.

## Decisions not in the brief

- Scope grew from three callers to five. `proof-ledger.sh` `_negctl_required` and `pitch.sh` `_find_spec` carry the same root-only glob (spec DEC-5).
- Gates think, design and design-critique are overrides, not runs. The operator brief fixed the problem and the done list; the draft PR exists for the operator's design review.

## Stop: two sessions in one worktree

A second session wrote an untracked `docs/specs/SPEC-388-colocated-spec-resolution.md` into this worktree mid-round. It covers the same brief with a different design (`SPEC_FIND_MAX_PREFIX`, `tests/test-spec-colocated.sh`). Both sessions share the rid `colocated-spec-resolution`, so they also write one gate ledger. Validation round 1 was closed `incomplete`; no code was written. Resolved: the other session backed out, removed its SPEC-388 file, and stopped. SPEC-386 is the canonical spec. Its ledger lines (a second START with `classified=normal`, a grill skip, three overrides, a ui-design skip) stay, because the ledger is append-only. A `START-AMEND` now pins `lane=full classified=full repo=dwarves-kit`. Its spec-next reservation for 388 lapses after 24h.

## Round 1 findings (5 of 7 reviewers returned; 5 and 6 stopped)

The critical folded into the spec as `### Co-located name match`, Edge Case 9 and DEC-7. Root files keep the glob on purpose: the spec's invariant says a root-only repo keeps today's pick.

### Warnings for the build

- Path form: `spec_files` prints `<root>/<rel>`, never `<root>/./<rel>`. A test pins the string, because validate-round compares paths.
- Prune `vendor`, `target`, `dist` and `build` with the dot-dirs and `node_modules`. Vendored or built specs must not raise `next`.
- TASK-4: the `rg` AC misses the real root-only prose. Check `commands/start.md`, `commands/next.md` and `commands/dispatch.md` by hand. Active-spec lookup there stays root-only (Out of Scope); say so where the prose could mislead.
- Task order: TASK-1, then TASK-2, then TASK-3, then TASK-4.
- Test ship-gate's fallback: with `spec-find.sh` unreadable, ship-gate still finds a root spec.
- Test `spec-next check 001` in a repo with a co-located `SPEC-001`: it reports taken. Accepted by design (Edge Case 8 covers `next`; `check` now sees every namespace).
- Nested git repo under the root: validate-round's `top` and ship-gate's `ROOT` both come from the outer checkout here. Note any gap the build finds.
- Hostile names: `cd --` before the walk, `-type f`, and one test with a space in a spec path.

### Rejected warning

- "Status must be DRAFT, VALIDATED or SHIPPED, not APPROVED." `commands/spec.md` step 4 sets `APPROVED` before validation; 11 specs carry it. Round 2 flipped it to `VALIDATED`.

## Round 2: APPROVED, 0 critical, 35 warnings, 7 of 7 reviewers

Build decisions taken from the warnings (APPROVED means no spec fold):

- The walk filters on `-name 'SPEC-*.md'`, then keeps a line only when its parent dirs are exactly `docs/specs`. A `-path` glob alone lets `*` span slashes.
- Prune list: dot-dirs, `node_modules`, `vendor`, `target`, `dist`, `build`. `tests/fixtures` stays walked (Edge Case 10 accepts it).
- A path with a newline is dropped in the walk. validate-round already refuses whitespace in the spec path.
- `find` stderr goes to `/dev/null`; both functions end `return 0`.
- Every caller except ship-gate sources the resolver with the `source ... || FATAL` shape its file already uses. ship-gate keeps the root-glob fallback: the hook must fail open on a stale install. That fallback is the one bounded copy of the old glob.
- `spec_for_slug` iterates `spec_files`; it never calls `find` itself, so the mutant reaches every caller.
- spec-next counts root numbers twice (old `ls` plus `spec_files`). Harmless for max+1; kept for the additive change the spec asks for.
- Symlinked co-located specs are invisible (`-type f`, no `-L`). Accepted.
- Not done: the Picture box label and the Grounding histogram prefix (cosmetic, spec frozen at VALIDATED); a deep-namespace warning.

## Test-plan critique (light): NEEDS WORK, 1 critical, 7 high

The build's `tests/test-spec-find.sh` covers these on top of the matrix:

- Critical: the mutant block also turns `_negctl_required` (not `yes`) and `pitch.sh _find_spec` (no spec) red, so all five callers carry a negative control.
- Edge Case 1 at the callers: `validate-round open <co-located>` refuses `is not the ship-gate pick` when a root spec shares the slug; ship-gate reads the root spec's `Lane:`.
- Edge Case 9 at ship-gate: only the decoy present, ship-gate exits 0.
- Edge Case 5: a real `git worktree add` sibling holding SPEC-200 makes `next` print 201.
- Edge Case 8: a co-located `SPEC-001` makes `check 001` report taken and leaves `next` alone.
- Row 7: skip the unreadable-dir case when euid is 0.
- Each `reserve` case gets its own state dir.

## Build: callers and tests

- spec-next sources the resolver with the FATAL shape, not the best-effort shape of its kit-log-dir line. A missing `spec_files` inside `|| true` would silently drop every co-located number.
- ship-gate guards with `[ -r ] && source`; any failure falls back to the old root glob.
- `hooks/codex-hooks.json` repinned by `lib/codex/repin.sh`: the ship-gate edit changed its content hash.
- `docs/FEATURES.md` regenerated by `feature-registry.sh check --fix`. The new spec and test moved its counts.
- `_negctl_required` has no verb. The test drives it through `proof-ledger.sh check` under an operator overlay with `negative_control = "full"`: exit 1 means yes, exit 0 means waived. A no-spec control pins the waiver.
- `pitch.sh _find_spec` is driven through `pitch.sh ask`, the one verb that prints the spec path.
- Stale-install fixture: the kit copy drops `spec-find.sh` and strips its source lines from the four libs. Dropping the file alone makes gate-ledger FATAL, and ship-gate then blocks on the FATAL text, which proves nothing about the fallback.
- Edge Case 5 fixture puts SPEC-200 co-located inside the sibling worktree, so only the new `spec_files` line can count it.
- Edge Case 1 at ship-gate: the root twin has no `Lane:` header. The `has no 'Lane:' header` block shows ship-gate read the root spec.
- Each mutant flip has a root-spec positive control in the same mutant kit, so a crashed caller cannot pass as a flip.
- Manual negative control: root-only `spec_files` in the real resolver turned 20 of 55 cases red. Red: rows 1, 2, 3 (foo-cs), 5, 6, 7 (listing), 8, 9, 10, 12, EC5, EC8. Green by design: decoy, root-wins, stale-install, EC1, EC9, the mutant block. Restored by `git checkout`, then 55 of 55 green.
- Pre-existing, not touched: `tests/test-config-registry.sh` fails on `origin/master` too (undeclared `proof.*` root-only keys).

## Build state

- Done: TASK-1 `lib/spec/spec-find.sh`. TASK-2, the five callers. TASK-3 `tests/test-spec-find.sh`, 55 cases with the mutant block.
- Ledger: validate (round 2 APPROVED), design-record, test-plan and build are recorded. Test-plan critique (light) returned NEEDS WORK; the build covers every item, but no critique re-run is recorded.
- Stopped here: the session context passed 70 percent.
- Resume in this order:
  1. TASK-4 docs: `lib/spec/spec-index.sh` header lines 8-9, `commands/start.md:19`, `commands/next.md:11`, `commands/dispatch.md:21`, then any doc on spec-next, validate-round or ship-gate spec lookup. Dispatch `kit:doc-verifier`, then record `docs ran`.
  2. `/kit:battery`, then record `review ran` with the merged verdict.
  3. `gh pr create --draft`. ship-gate engages on it, so every full-lane gate up to `docs` must be in the ledger first.
- Known red, not from this branch: `test-config-registry` fails on a clean `origin/master` export too. `test-gate-validate-round` failed 1 of 196 once, then passed 12 runs in a row; the failing case was not captured.
- Test runs under Claude Code need a `# branch-guard: allow: <reason>` comment on the command line. The ship-gate tests send `git push` text to the hook.

## Review (light, two lenses in parallel)

Verdict FIX THEN SHIP. Left open for the operator design review on the draft PR:

- Medium: a missing `spec-find.sh` makes gate-ledger, proof-ledger, pitch and spec-next exit 1 at source time, while ship-gate falls back to root-only. ship-gate then blocks on their FATAL. Fail-closed, not a bypass. Fix needs a ship-gate edit and a new codex-hooks hash pin.
- Low: a root glob hit beats an exact co-located match (kept as today).
- Low: the walk runs in full even after a root hit. Try root first, walk on a miss.
- Low: an unrelated co-located spec with the branch slug over-blocks a push. Never under-blocks.
- Applied (b3246c14, 1f2a1657): callers fall back to a root-only lookup when spec-find.sh is missing, like ship-gate; the fallback is pipefail-safe and the stale-install fixture now runs fresh libs against the fallback.
- Applied (6a5aad74): spec_for_slug checks the root docs/specs glob first and walks only on a miss.
