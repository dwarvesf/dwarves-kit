# Implementation notes: lo-05-docs (docs + wiring)

Delta from `_meta/megagoals/ledger-observatory/goals/05-docs-wiring.md` only. Spec/ADR
decisions already recorded elsewhere are not restated here.

## 2026-07-04 09:00 Scope: SKILL.md is in-scope despite the goal file's omission

**Context:** the goal file's Scope-edges "In:" list names only README.md,
docs/proof-of-done.md, tool.toml/MANIFEST.md, and the no-orphan check. It does not name
`skill/SKILL.md`.

**Decision:** treat `skill/SKILL.md` as in-scope for the honesty fixes (per the worker
dispatch note): it is the agent-facing interface and TIER-4 found it stale (claims the
feedback loop "not built yet" when 04 shipped and merged).

**Why:** a no-orphan/honesty pass that leaves the single most agent-facing doc lying about
a shipped feature defeats the purpose of the sub-goal.

**Alternatives considered:** strictly honor the goal file's scope edges and leave SKILL.md
stale, flagging it as a follow-up. Rejected: the dispatch explicitly overrides the omission,
and the doc lying about live functionality is exactly the c6fbd99 bug class this sub-goal
exists to catch.

**Impact:** `skill/SKILL.md` gets the same edit-in-place treatment as README.md; no new file.

## 2026-07-04 09:05 PR base: main, not feat/lo-04-feedback

**Context:** the goal file says `PR base: feat/lo-04-feedback` (written when the stack was
still open). The worker dispatch says 01-04 are all merged to `main` and to branch/PR
against `main`.

**Decision:** branch `feat/lo-05-docs` off `main`, PR base `main`. The `feat/lo-04-feedback`
branch no longer exists post-merge; basing there would be stale.

**Why:** reality (04 merged, `main` HEAD = a0806ff3) supersedes the goal file's stack-era
assumption.

**Impact:** none on deliverable content; only affects the PR's base ref.

## 2026-07-04 09:10 tool.toml / MANIFEST.md / INVENTORY.md rows already existed

**Context:** the contract asks to add a `tool.toml` + `MANIFEST.md` row + an `INVENTORY.md`
row "if that's the convention." All three already exist (added incidentally during 02),
but the `INVENTORY.md` notes column and README status table still say "SG-03/04/05 pending".

**Decision:** update the existing rows in place rather than re-creating them; refresh stale
"pending" language to match the now-merged 03/04.

**Why:** avoids duplicate rows; matches the "hand-edited index, update in place" contract in
`_meta/SCHEMAS.md`.

**Impact:** `MANIFEST.md`/`tool.toml` content is largely already correct (consumers/systems/
secrets); `INVENTORY.md` notes + tier get a refresh.

## 2026-07-04 09:15 No-orphan test placement + over-claim NC mechanism

**Context:** the contract asks for `tests/test-docs-wiring.sh` proving (a) docs presence,
(b) the no-orphan sweep (skill fires -> CLI invoked -> work-intake fed), (c) an over-claim
negative control that is CAUGHT.

**Decision:** the over-claim NC works by writing a temp copy of README.md with an injected
line claiming a nonexistent `ledger foo` command, running the same grep-based "every `ledger
<verb>` claimed in the README has a matching `@app.command()` in cli.py" check against the
mutated copy, and asserting the check fails (catches the fabricated command) while the same
check against the real README passes clean. This proves the check is falsifiable, not
vacuous, without touching the real README.

**Why:** a no-orphan check that can never fail is not a check; the c6fbd99 lesson (and this
mega-goal's own binding "cross-cutting WIRING GATE" assumption) requires the NC to bite.

**Impact:** new `tests/test-docs-wiring.sh`; no changes to CLI code.
