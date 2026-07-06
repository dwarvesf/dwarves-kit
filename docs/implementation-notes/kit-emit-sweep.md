# Implementation notes: kit-emit-sweep (SPEC-139)

Delta from the spec only; see `docs/specs/SPEC-139-kit-emit-sweep.md` for the full design and
its own `## Decision Log` for the three design decisions pinned there (DEC-001/002/003). This
file covers what came up DURING implementation that the spec did not (or could not) anticipate.

## 2026-07-04 08:00 the sweep's positive check had to be loosened from a strict regex to a loose substring

**Decision:** the sweep's "does this command emit" check is `grep -qi 'gate-ledger'` (any
mention, case-insensitive), not a stricter invocation-shape regex.

**Why:** the first draft used `` `bash lib/gate-ledger\.sh <verb>` `` (mirroring the exact
phrasing convention `spec.md`/`review.md`/etc. use). Running it against the real repo before
trusting it surfaced a false negative: `commands/quiz-gate.md`'s real emit is phrased
`` `gate-ledger.sh debt-response` `` (no `bash lib/` prefix in the same backtick span, since its
prose describes the underlying `lib/gate/quiz-gate.sh`'s own internal call rather than instructing
the reading agent to run gate-ledger.sh directly). A strict regex would have wrongly flagged a
genuinely-wired command an orphan. The loose substring check trades false-negative risk for a
coarser signal, matching what the sub-goal's own contract actually asks for ("either contains a
gate-ledger call OR is listed in the exemption table" -- not "contains a call in exactly this
shape").

**Impact:** the sweep is deliberately not a strict wiring-shape verifier; AC3 (per-newly-wired-
command phase check) supplies the STRICT proof (a phase-specific regex) for exactly the 9 files
this SPEC wired, while AC1's loose check covers the other 20 without needing to hand-tune a
regex per file's prose style.

## 2026-07-04 08:05 the WORKFLOW.md table parser had to anchor on the first column only

**Decision:** `exemption_list()` parses ONLY lines matching `^\| *`name.md`...`, ignoring any
other backtick-wrapped `.md` mention in the section.

**Why:** the first draft grepped the WHOLE "## Command emit coverage" section for any
backtick-`.md` token, which over-matched: the prose paragraph above the table mentions
`test-plan.md`/`review.md`/`devs-team.md` as convention examples, and several table rows'
OWN rationale text re-mentions their own filename (the `mega.md` row explains itself twice --
"the emission is real... not as a literal call inside `mega.md`'s own prose" -- and `dispatch.md`
similarly). Both produced duplicate/spurious entries in the parsed exemption list, breaking
AC2's exact-set assertion. Anchoring to the table's FIRST COLUMN (line-start `| \`name.md\``)
fixed it cleanly without having to avoid re-mentioning a filename in the prose (which would have
made the rationale text stilted).

**Impact:** none outside the test file; this is purely a parsing-robustness fix, not a design
change. Documents a reusable lesson for the THREE prior sibling no-orphan sweeps (not applied to
them, out of scope): a section-wide grep for a marker string is fragile once the section's own
prose legitimately re-mentions that marker.

## 2026-07-04 08:05 a negative-control fixture almost defeated its own purpose

**Decision:** the AC4 fixture's description text avoids the literal substring "gate-ledger"
entirely, with a comment inside the fixture explaining why.

**Why:** the first fixture's frontmatter description read "a command with no gate-ledger
mention and no exemption entry" -- which itself contains the substring "gate-ledger", so the
sweep's own `grep -qi gate-ledger` check matched the fixture's SELF-DESCRIPTION and wrongly
counted it as wired. A classic self-referential test-fixture trap (the same shape as a
fixture that says "this file has no secrets" and thereby trips a secret-scanner on the word
"secrets"). Caught immediately by actually running the test rather than trusting the design on
paper.

**Impact:** none outside the test file. Recorded as SPEC-139's Test plan case 8 (the "security/
abuse" category row) so it is not lost as tribal knowledge.

## 2026-07-04 08:10 `Build` and design-record stay unrecorded -- named, not fixed

**Decision:** `execute.md` is untouched; no new `record <rid> build ran` or
`record <rid> design-record ran` call was added anywhere.

**Why:** both are genuine pre-existing gaps (confirmed: `execute.md` narrates escalation/action
verbs around a build but never calls `record` for the `Build` phase itself; no command anywhere
calls `record <rid> design-record ran`, since that row is enforced statically by
`/kit:spec-validate` Reviewer 6 rather than separately recorded). Neither is in this sub-goal's
named 9-command list, and `execute.md` was already counted among the mega-goal's own "11
emitting" commands (it DOES call gate-ledger.sh, just not for the `Build` phase specifically) --
touching it would be scope creep against the explicit DO-NOT-add-new-gates /
DO-NOT-change-lane-matrix-cells constraint, and against the "surgical changes" discipline (only
touch what the task requires).

**Impact:** for THIS sub-goal's own ship, both gates were satisfied by a MANUAL
`bash lib/gate/gate-ledger.sh record <rid> build ran "..."` / `... design-record ran "..."` call
(the same generic escape hatch AGENTS.md already names for any phase gate with no dedicated
command instruction), not by editing any kit source file. WORKFLOW.md's new section names both
gaps honestly as out of scope, with a candidate backlog note in
`docs/retro/RETRO-2026-07-04-kit-emit-sweep.md`.
