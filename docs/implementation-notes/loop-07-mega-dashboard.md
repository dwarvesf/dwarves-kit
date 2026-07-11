# Implementation notes: mega-review dashboard (SPEC-197, harness-loop SG-07)

Delta from the spec only. Spec/ADR decisions are referenced, not restated.

## 2026-07-12 09:20 Deferred the lib/mega/ directory promotion

Context: `lib/mega.sh`'s own header comment documents a load-bearing convention (SG-03's
"2+-verb subsystems get a grouped `lib/<x>/<x>.sh` case-dispatcher" rule): once a second verb
lands, the file should promote to `lib/mega/mega.sh` + siblings.

Decision: did NOT do the promotion here. Added `review` as a second `case` arm in the existing
orphan file (`lib/mega.sh`), with `lib/mega-review.py` as a plain sibling at `lib/` root
(mirroring `lib/gate/proof-table-gen.sh` -> `.py`, but one directory up since `mega.sh` itself
has no subdirectory).

Why: ADR-0034's own census table (decision 7, "bin/ consolidation") already names `bin/mega` +
the implied `lib/mega/` promotion as SG-04's target state, and the goal file's `## Touches`
names `lib/mega.sh` singular. Doing the promotion here would (a) touch files outside this
sub-goal's stated scope, (b) risk a same-file collision with SG-04's own consolidation wave
(both would touch `lib/mega.sh`'s location), and (c) the mega's own dependency chain gates
SG-04 on SG-01 (the taxonomy ADR), which is not yet merged -- promoting the directory shape
before the ADR that specifies its exact target (`lib/mega/mega.sh` vs. some other layout) is
premature.

Impact: `lib/mega.sh`'s header comment now explicitly documents the gap (see the file) so a
future reader isn't confused about why the promotion rule wasn't followed. SPEC-197 DEC-001
records the same reasoning. Recorded for the lead's DECISIONS.md: SG-04 should treat
`lib/mega-review.py` as a file to relocate alongside `lib/mega.sh` when it does the
promotion, not as a second orphan to separately consolidate.

## 2026-07-12 09:45 Ledger parsing: imported, not reimplemented

Decision: `lib/mega-review.py` imports `lib/gate/proof-table-gen.py`'s `parse_ledger` function
directly via `importlib.util.spec_from_file_location` (the module's filename has a hyphen, so
a normal `import` statement can't reach it) rather than writing a second GATE/OUTCOME line
parser. TOKENS-line parsing has no existing reader anywhere in the repo (proof-table-gen.py
does not parse it), so that ~20-line parser is new and local to `mega-review.py`.

Why: two independent parsers for the SAME `| GATE | ... |` / `| OUTCOME | ... |` line shapes
is exactly the drift ADR-0034 exists to prevent. `gate-ledger.sh` itself already establishes
the precedent this follows (it sources `lib/telemetry/kit-log-dir.sh` and `lib/ledger/
ledger.sh` as cross-subsystem siblings rather than duplicating their logic).

## 2026-07-12 10:05 Git-truth classification: shelled out, not reimplemented

Decision: rather than re-deriving OK/CLAIM-UNVERIFIED/MERGED-UNCHECKED/STALLED/WIP/PENDING/
INFO from PR state + branch + commit count in Python, `mega-review.py` shells out to
`bash lib/mega.sh status <slug> ...` and parses its stable, already-documented per-line
output format via a regex keyed on the label enum (`_STATUS_LINE_RE`).

Tradeoff accepted: this couples `mega-review.py` to `mega.sh status`'s exact stdout FORMAT
(not just its underlying logic) -- a future reformat of that one-liner would need to update
`_STATUS_LINE_RE` too. Chosen over the alternative (reimplementing `_classify()`'s ~15 lines
in Python) because the format is already documented, already tested (`tests/test-mega.sh`'s
16 checks), and a SINGLE classifier is worth a small format-coupling cost. If this proves
fragile later, the fix is a `--json` output mode on `mega.sh status` (not attempted here --
scope discipline: this sub-goal's Touches is `lib/mega.sh` for the `review` verb, not for
widening `status`'s existing, tested contract).

## 2026-07-12 10:40 Proof-of-done link discovery is best-effort, not exhaustive

Finding, not a decision: the real archived-mega corpus (harness-ops) shows proof-of-done
paths with NO single derivable naming convention (`docs/verification/wire-ledger.md`,
`docs/verification/ho-03-wire-mega/proof-of-done.md`, `docs/verification/manifest-reconcile/
proof-of-done.md` -- the middle one's `ho-03-` prefix is not derivable from either the
sub-goal slug or the rid). `find_proof_link` tries 5 candidate paths (rid-keyed generated
table, rid.md, rid/proof-of-done.md, bare-slug.md, bare-slug/proof-of-done.md) and reports
"(unlinked)" honestly when none match, rather than either guessing wrong or requiring a new
naming convention retrofit across every past mega (explicitly out of scope: no historical
backfill). Verified against the real corpus: found `docs/verification/wire-ledger.md` for
harness-ops's `02-wire-ledger` (bare-slug candidate); correctly reported unlinked for
`01-config-resolver` (its real proof lives in `RUN_REPORT.md` prose with no separate file).

## 2026-07-12 11:15 Local vs. UTC date bug caught by the test suite

Bug found and fixed during test-writing: `_staging_counts`'s "oldest age" computation
initially used `datetime.date.today()` (local) compared against a fixture date generated with
`date -u` (UTC) in the test, which off-by-one'd near the day boundary (Da Nang is UTC+7, so
local "today" can already be tomorrow relative to UTC). Traced the actual WRITER
(`hooks/backlog-stage.py`'s `date = payload.get("_today") or time.strftime("%Y-%m-%d")`,
no `utcnow`) and confirmed it writes LOCAL date, not UTC. Fixed both sides: the composer keeps
`datetime.date.today()` (matches the writer), and the test fixture switched from
`date -u -v-10d` to `date -v-10d` (local) to match. Comment added at the call site so this
doesn't regress silently.

## 2026-07-12 11:40 Real-corpus proof surfaced a ledger data-quality anomaly (not fixed here)

Finding: `~/.local/state/dwarves-kit/logs/runs/kitmod-03-subsystem-commands.log` (the real,
shared corpus on this machine) carries 4 `| OUTCOME |` lines and ZERO `| GATE |` lines, all
at the identical epoch timestamp -- the shape of a scripted test write that landed in the
SHARED corpus rather than a sandboxed one, not a real production run (kit-modularity SG-03
predates the OUTCOME emitter's wiring, SPEC-193). The composer's honest-empty handling
already covers this correctly (renders "(no GATE rows recorded... OUTCOME markers exist with
no paired GATE row)" instead of a fabricated table or a crash), so no code fix was needed.
Flagging the anomaly itself is out of scope for this sub-goal (it's a pre-existing corpus
artifact, not something this change introduced); the proof screenshots deliberately use a
clean real example instead (harness-ops's `02-wire-ledger`). SPEC-197 DEC-007 records this.

## 2026-07-12 12:00 TIER-4 wiring: render BEFORE the no-orphan sweep, not after

Decision: the dashboard render call sits in `_tier4_close` right after `corpus` is resolved
and BEFORE the no-orphan sweep / verifier dispatch, so every close attempt (held-clean,
orphan-blocked, or dissent-blocked) gets a dashboard snapshot, not just the successful path.
Best-effort: wrapped in `if ... ; then ... _say ... ; else ... WARN ... ; fi`, never affects
the close's own return code.

Test-hermeticity fix required by this wiring: `tests/test-tier4-close.sh` previously made no
`gh` calls at all. Once `_tier4_close` calls `mega.sh review` -> `mega.sh status` ->
`_open_pr_for` (which shells to `gh pr list` unconditionally whenever a sub-goal has a
resolved branch, independent of whether it has a PR number), the existing fixture scenarios
would have started making REAL, unauthenticated `gh` network calls in CI. Added a `mk_gh_stub`
helper + `GH_BIN`/`DWARVES_KIT_LOG_DIR` env exports to the two scenarios (A: clean close, F:
opt-out) that now touch the render path, mirroring `tests/test-mega.sh`'s own `STUBGH`
convention. All pre-existing assertions in that file stayed green, unmodified.

## No deviations beyond the above

Everything else matches SPEC-197 as written.
