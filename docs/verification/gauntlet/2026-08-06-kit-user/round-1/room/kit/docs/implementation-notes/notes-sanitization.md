# Implementation notes: notes-sanitization (SPEC-223)

The DELTA from the spec, not a mirror of it. Every entry is something the spec left open, something
the build chose differently, or a constraint found only by running the code.

## 2026-07-31 17:58 The spec number is 223, not 222

Context: the run was told to reserve SPEC-222 and to claim it by pushing a stub branch immediately,
because two number collisions happened this week from prose-only reservations.

Decision: `bash lib/spec/spec-next.sh reserve` returned 223. The reservations ledger shows a
parallel session claimed 222 about a minute earlier. The spec is SPEC-223.

Why: the atomic reserve verb is the mechanism SPEC-128 built for exactly this race, and it is a
STRONGER claim than a pushed branch: it is shared state, written under a mkdir mutex, folded into
the next caller's scan. The early push could not happen anyway, see the next entry.

Alternatives: taking 222 anyway and letting `test-meta.sh` catch the duplicate later. Rejected: the
ledger already showed the collision, so shipping it knowingly would be worse than the accident it
was meant to prevent.

Impact: every reference in code, tests, commit body, and the board row says 223.

## 2026-07-31 17:59 The early claim-push was refused by the ship-gate, and was not bypassed

Context: the plan was to push a one-line spec stub immediately so a parallel session's `spec-next`
could see the number on a remote branch.

Decision: the push was blocked twice by `hooks/ship-gate.sh`, first for a spec with no `Lane:`
header, then, once a lane existed, for a `full` lane whose twelve gates had not run. The push was
NOT retried through any other command shape.

Why: bypassing a guardrail is the one thing AGENTS.md zone 4 says to stop and ask about, and
`--no-verify` would not have helped regardless (the block is a PreToolUse hook on the command, not
a git hook). The reservations ledger achieves the same claim without touching the gate.

Impact: the branch is pushed once at the end of the run, with the gates honestly recorded. Anyone
repeating this instruction should reserve, not push, to claim a number early.

## 2026-07-31 18:05 The lane is `full` while the classifier said `normal`

Context: `lane-classify.sh classify "sanitize untrusted board notes before an agent reads them"`
printed `normal`.

Decision: `Lane: full`, recorded as such in the spec header and in the gate ledger's START row
(`lane=full classified=normal`).

Why: the change touches `lib/` on the path that drives an unattended
`--dangerously-skip-permissions` session, which is the AGENTS.md full-lane trigger list
(audit/security, enforcement surface). The house rule is to take the heavier lane when in doubt.

Impact: the run owes the full gate set, including a real review round rather than a waiver.

## 2026-07-31 18:20 The sanitized surface is the pointer BODY, not the Notes cell

Context: board row ID-459 and the prior-art survey both say "free-text Notes cells flow into a
write-capable agent unsanitized".

Decision: `sanitize_cell` is applied to the pointer file body inside `_goal_line`, not to the row
text.

Why: reading the code, `lib/board/parse-board.sh` never emits the row's prose. It emits
`id / repo-root / resolved-pointer`, and the only part of the cell it reads is a `#queue{}` token
already constrained to `^[A-Za-z0-9_./-]+$`. The text that actually reaches a model is the file
`_goal_line` reads and `_mux_type` types. Sanitizing the cell would have been a transform over a
string nothing consumes.

Alternatives: sanitizing the cell as literally described. Rejected as theatre.

Impact: this is DEC-001 in the spec, and it is the one place the build deliberately diverges from
the row's own wording. The row's intent (untrusted text must not reach the model unfiltered) is met.

## 2026-07-31 18:25 The deny-glob detects, it does not prevent

Context: the task asked for "a static protected-files deny-glob naming what an autonomous run may
NOT write".

Decision: shipped as two halves. The glob set is stated inside the typed prompt as a rule, and
`_protected_touched` checks after the run and rewrites the verdict to `gated`.

Why: the launched session holds `--dangerously-skip-permissions`. No bash wrapper sits between it
and the filesystem, so a prevention claim would be false. Detection plus a terminal verdict is the
strongest true claim available at this layer.

Impact: DEC-007. The spec, the code comments, and the changelog all say detection, never prevention.

## 2026-07-31 18:30 `QUEUE_PERL_CMD` exists because of the fail-closed TEST, not the feature

Context: the fail-closed path needed a test, and the first attempt simulated a missing perl by
emptying `PATH`.

Decision: added `QUEUE_PERL_CMD` (default `perl`) and pointed the test at a name that does not
exist.

Why: emptying `PATH` also removes `bash`, `git`, and `awk`, so the row failed for the wrong reason
and the assertion passed vacuously. A named binary seam is what `MUX_CMD` and `QUEUE_CLAUDE_CMD`
already do in this file.

Impact: one extra env knob, documented in the sanitize header. It also gives an operator a way to
point at a non-default perl.

## 2026-07-31 18:35 Size cap is 20000 characters, derived not copied

Context: the feed suggested a board-cell scale of about 500 characters.

Decision: `QUEUE_MAX_PROMPT_CHARS` defaults to 20000.

Why: the sanitized text is a goal prompt, not a table cell. Measured against this repo's real
pointer files, a typical `POINTER_PROMPT.md` is about 4 KB and the largest notes file is about
15 KB. A 500-character cap would have truncated honest work on the first real night.

Impact: DEC-008, and a negative control in the test asserts the default cap does not fire on a
realistic prompt.

## 2026-07-31 19:05 Pre-existing `test-queue.bats` failures, confirmed not caused here

Context: `bats tests/test-queue.bats` reports three failures (cases 9, 13, 14).

Decision: recorded as pre-existing rather than fixed in this branch.

Why: verified by extracting `origin/master` with `git archive` into a temp dir and running the same
suite there. The identical three cases fail. Fixing them is a separate concern and would hide this
branch's own signal.

Impact: the spec's `## Verification` states the expectation as "no NEW failures versus master" and
names the three cases.

## 2026-07-31 19:20 Review findings applied

Context: the architecture lens returned three findings (one MEDIUM, two LOW).

Decision: the MEDIUM (the spec was cited by code but not yet committed) is resolved by committing
the filled spec in the same branch. LOW #2 (two independent derivations of "what changed" in the
same call chain) gets a cross-reference comment naming the drift risk and the fix if a third caller
appears; the functions stay separate because they answer different questions. LOW #3 (a rename into
a protected path is missed while uncommitted) is promoted from a code comment to DEC-009.

Why: the MEDIUM was real and cheap. The LOWs are honest limits worth recording, and merging the two
git readers would couple the breaker's evidence rules to the deny-glob's.
