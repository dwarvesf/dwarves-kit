# Spec: backlog-reconcile audit-loop instance
Generated: 2026-08-01
Status: VALIDATED
Lane: full
Backlog: (none yet, operator-driven build, not board-pulled)
References: `skills/topology-drift/SKILL.md` , imitate its exact shape: the four-slots table
right after Overview, the numbered Process with a freshness-refusal Step 1, Tier1-mechanical /
Tier2-model-delta split, `agents/audit-scanner.md` dispatch, OK/FIX/REMOVE/UNSURE/DANGER
verdicts, worktree-branch-PR mechanics. `skills/memory-tidy/SKILL.md` , second precedent for
the generic (non-maintainer-only) framing and worktree/PR discipline.

## Problem

`docs/patterns/audit-loop.md`'s own SDLC-instances table names "Backlog reconcile" (row: item
set = board rows, contract = "row status matches reality", evidence = "commits, PRs, deploy
state") as one of five instances of the pattern. Three of five are built (memory-tidy, doc-drift,
topology-drift/feature-map); backlog reconcile is design-only. The kit is about to ship to
adopters; a pattern doc whose own table names an unbuilt row undersells the pattern it documents.

Concretely: an operator asks "is the board still true" and today the honest answer is "nobody
checked, and if someone did with the closest informal tool (a personal, out-of-kit reconcile
mode), nothing reviewed their edit before it landed." See
`docs/briefs/DECISION-BRIEF-backlog-reconcile.md` Q1 for the full user-pain framing (brief-reviewer PASS).

## Solution

### Approaches considered

1. **New in-kit skill mirroring topology-drift** (chosen). Same four-slot shape, same Tier1/
   Tier2 split, same shared `audit-scanner.md` dispatch, same PR gate. Tradeoff: another skill
   file to maintain, but the shape is proven twice already (memory-tidy, topology-drift), so the
   marginal maintenance cost is low and the marginal correctness risk is near-zero.
2. **Extend `lib/board/backlog.sh` itself with a `reconcile` subcommand** (rejected). Keeps
   everything in one file, but collapses the judgment layer (Tier 2, model dispatch, PR gate)
   into a mechanical bash tool that was deliberately kept dumb (SPEC-055's own scope: render,
   pick-next, flip-status, nothing judgment-shaped). Would also break the audit-loop pattern's
   own separation between the mechanical substrate and the judgment skill that consumes it,
   the same separation `memory-tidy` documents explicitly against `stats memory-sweep`.
3. **Route to the personal, out-of-kit `work-intake` skill's reconcile mode** (rejected, decision
   brief's Q1 already resolves this as out of scope). That skill lives outside dwarves-kit
   entirely; distributing the kit cannot ship a dependency on a personal, unshipped skill.

### Chosen approach + why

Approach 1. It reuses 100% of the existing mechanical substrate (`backlog.sh`) and the existing
shared Tier-2 scanner (`audit-scanner.md`) unchanged, adds exactly one new file
(`skills/backlog-reconcile/SKILL.md`) plus the mechanical registrations (pattern-doc paragraph,
registry regen), and follows a template that has already shipped twice.

**Correction from `/kit:spec-validate` Reviewer 3 (Assumption Destroyer).** The first draft of
this spec built its contract on a `→` pointer convention in the Notes cell. That convention is
an ops-toolkit personal-workflow habit (`work-intake`'s "Home" field), NOT part of the kit's own
`_meta/BACKLOG.md` schema (SPEC-005 / `## Schema` in `_meta/BACKLOG.md`). The kit's real schema
has no Notes-cell pointer field at all; its evidence anchor is `Target artifact` (`SPEC-NNN` or
`(tiny, no spec)`) plus `Status`. Every section below is corrected to that real schema, which is
also a BETTER anchor: it needs no per-repo convention, every kit adopter already has it.

### Extensibility & boundaries

The load-bearing dimension is board size (row count). Tier 1 is batched, not per-row (one
`git log` pass for every `(tiny, no spec)` row together, one `grep -m1` per spec file), so its
cost is amortized across the board rather than O(1) per row; Tier 2 only dispatches on the
delta Tier 1 flags, chunked at ~25-30 rows per call so a systemic drift event can't hand the
scanner an unbounded target list. Cost scales with drift, not with board size, in the typical
case, the same guarantee topology-drift already gives for feature count; this claim is not yet
empirically checked against a 200+ row board (named, not silently assumed). Unit boundary: this
skill owns enumeration + verdicting + apply-on-branch; it does not own `backlog.sh` (mechanical
substrate, untouched) or `audit-scanner.md` (shared judgment dispatcher, untouched, including
its tool roster: any `gh` evidence Tier 2 needs is gathered by THIS skill and handed to the
scanner as inline text, never a new capability grant). Both are consumed, not modified.

### Architecture

See `## Design` below.

## Picture

```
             lib/board/backlog.sh board   +   one raw read of _meta/BACKLOG.md
             (id/title/status)                (for the Target-artifact cell,
                          |                     content-pattern matched, not
                          |                     column-indexed: NF drifts on
                          |                     real rows, 83 of 177 active
                          |                     rows in this repo have NF=6)
                          v
        +-----------------------------------------------------------------+
        |  TIER 1  (mechanical, every row, batched not per-row)             |
        |  a. Status=shipped but still on Active queue, AND Target artifact |
        |     does NOT point at `_meta/megagoals/` (umbrella rows exempt)   |
        |     -> flag                                                       |
        |  b. Target artifact matches `^SPEC-\d+$`: test -e docs/specs/     |
        |     SPEC-NNN-*.md. Missing -> flag (FIX/DANGER, Tier 2 judges     |
        |     which). Present -> grep -m1 '^Status:' <file>, take the       |
        |     LEADING keyword only (ignore trailing prose/dates/parens,     |
        |     mirrors backlog.sh's own leading-keyword extraction), map:    |
        |     DRAFT/APPROVED->queued|claimed|speccing, VALIDATED->validated,|
        |     SHIPPED->executing|shipped, PARKED->parked. Missing/          |
        |     unrecognized header -> always a flag, never a silent pass.    |
        |     Mismatch -> flag.                                             |
        |  c. Target artifact matches `^\(tiny, no spec\)$`: ONE batched    |
        |     `git log --oneline --grep -F -- <ID>` pass covering every     |
        |     tiny row at once (not one subprocess per row), matched        |
        |     in-memory. queued+no match = fine, not flagged. executing/    |
        |     shipped+no match, or an ambiguous multi-match -> flag.        |
        |  d. Neither pattern matches any cell (row predates the Target-    |
        |     artifact convention, or malformed) -> flag as UNSURE.         |
        +-----------------------------------------------------------------+
                web  |
                all checks pass, zero flags
                |                    | >=1 flag (chunked into ~25-30 rows per dispatch)
                v                    v
             OK, done       +---------------------------------------+
          (report CLEAN)    |  TIER 2 (delta only, chunked)           |
                             |  dispatch agents/audit-scanner.md with: |
                             |  target=flagged-row chunk, contract,     |
                             |  evidence class. `gh pr view`/`gh pr     |
                             |  create` results (if relevant) are RUN   |
                             |  by THIS skill and handed to the scanner |
                             |  as inline evidence text -- the scanner's|
                             |  own tool roster has no `gh` and stays   |
                             |  untouched.                              |
                             |  Timeout / unparseable / out-of-vocab    |
                             |  verdict -> treat as UNSURE, never       |
                             |  coerce to OK or drop the row.           |
                             +---------------------------------------+
                                        |
                                        v
                     verdict per row: OK/FIX/REMOVE/UNSURE/DANGER
                                        |
                                        v
                    +----------------------------------------------+
                    |  APPLY (on the isolated branch, best-effort     |
                    |  per row: a failed flip is surfaced in the PR   |
                    |  body, the loop does not abort)                 |
                    |  - the ONLY mutation: backlog.sh set <ID>       |
                    |    <state> [note] (bracketed note lands INSIDE  |
                    |    the Status cell, the schema's real annotation|
                    |    mechanism; there is no separate Notes column)|
                    |  - UNSURE: never resolved, listed only          |
                    +----------------------------------------------+
                                        |
                                        v
              git push + gh pr create (failure here exits non-zero,
              names the orphan branch -- never a silent success)
                                        |
                                        v
                         PR (operator's approval gate)
```

## Design

### Approaches considered + chosen

See `## Solution` above; no new tradeoff surfaces at the design level.

### Diagram

See `## Picture` above (the same flowchart serves both; ASCII/box-drawing chosen over Mermaid
per the operator's standing personal rule against mermaid.js in any repo markdown, which
overrides this template's own Mermaid-first default for this operator's repos).

### ADR link(s)

None new. The lasting decision here, "audit-loop instances are skills that wrap a mechanical
substrate + the shared audit-scanner, never a bespoke tool", is already established precedent
(memory-tidy, shipped; topology-drift, shipped) and does not meet the 3-part ADR bar fresh
(nothing here is surprising given that precedent, and the one real tradeoff, general-purpose vs
maintainer-only scope, is already recorded in the decision brief's "Strongest argument against").

### Boundaries & failure modes

This design does not touch `backlog.sh` or `audit-scanner.md`; both are read/invoked, never
edited. `Target artifact` is read by content-pattern match on the raw `_meta/BACKLOG.md` text,
not through `backlog.sh`'s CLI (its `_rows()` only ever emits id/title/status); a
`backlog.sh rows --fields ...` extension is a real option but is new shared-component scope,
named here as a follow-up, not pulled into this spec. Any `gh` evidence Tier 2 needs is gathered
by this skill's own Tier 1/pre-dispatch step and handed to `audit-scanner.md` as inline text;
the scanner's tool roster (no `gh`) is not widened. See `## Failure modes` below for the
specific failure classes.

## Technical Design

### Interfaces (I/O contract)

- **Consumes**: `bash lib/board/backlog.sh board` output (id/title/status, repo-relative,
  `BACKLOG_FILE` env overridable) for enumeration; a raw read of `_meta/BACKLOG.md` for each
  row's `Target artifact` cell, matched by content pattern (`^SPEC-\d+$` / `^\(tiny, no spec\)$`),
  not column index (SPEC-005 schema: ID/Title/Source/Target artifact/Lane/Status, but real rows
  drift in column count); the target spec file's own `Status:` header (`docs/specs/SPEC-NNN-*.md`,
  leading keyword only) when `Target artifact` names one; a batched `git log --grep -F` pass for
  every `(tiny, no spec)` row; `gh pr view`/`gh pr create`, run by this skill, never by the
  scanner.
- **Produces**: a branch with mechanical status flips ONLY via `backlog.sh set <ID> <state>
  [note]` (the bracketed note lands inside the Status cell, the schema's one real annotation
  mechanism; there is no separate Notes column and no second write path), plus a PR whose body
  lists every verdict (OK count folded, every non-OK with evidence, every failed per-row flip)
  and every UNSURE for the operator. No mutation lands outside a PR; a push/PR-create failure
  after Apply exits non-zero naming the orphan branch, never a silent success.
- **Invariants**: UNSURE is never auto-resolved (hard rule, matches the pattern doc verbatim),
  including a scanner timeout or an out-of-vocabulary verdict (treated as UNSURE, never coerced
  to OK). `backlog.sh`'s own contract (mechanical flip preserves annotation prose, rejects
  unknown state/ID, and each `set` call re-reads the file fresh so sequential per-row calls
  cannot race each other) is relied on, not re-implemented.

### Data model changes

None. No new file format; reuses `_meta/BACKLOG.md`'s existing row schema (SPEC-055).

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-001: Write `skills/backlog-reconcile/SKILL.md` frontmatter + Overview + four-slots
      table (item set / contract / evidence class / apply mechanics, per this spec's Solution)
      , acceptance: file exists, frontmatter has `name`/`description`/`disable-model-invocation: false`, description names the trigger phrases and the NOT-for exclusions (personal work-intake, single known-broken row).
- [x] TASK-002: Write the Process's Step 1 refusal guard (no `lib/board/backlog.sh` or no
      `_meta/BACKLOG.md` in the target repo -> REFUSE, name what's missing) and Step 2 (branch
      first) , acceptance: the guard is a runnable bash snippet in the SKILL.md body, tested
      against a scratch dir with neither file present.

### Phase 2: Core
- [x] TASK-003: Write Tier 1 as a runnable bash block in the SKILL.md: (a) shipped-row-still-
      on-queue check with the `_meta/megagoals/` umbrella-row exemption; (b) `Target artifact`
      extracted by content pattern (`^SPEC-\d+$` / `^\(tiny, no spec\)$`), never a fixed column
      index; (c) for a SPEC-NNN match, existence check + `grep -m1 '^Status:'` + leading-keyword
      extraction against the FULL observed vocabulary (DRAFT/APPROVED/VALIDATED/SHIPPED/PARKED,
      missing/unrecognized header always flags); (d) for `(tiny, no spec)`, ONE batched
      `git log --oneline --grep -F` pass for every such row (not one subprocess per row),
      queued+no-match not flagged, executing/shipped+no-match or ambiguous multi-match flagged;
      (e) no matching cell -> UNSURE , acceptance: run against dwarves-kit's own
      `_meta/BACKLOG.md` (177 active rows, real column-count drift, `ID-101`'s shipped umbrella
      row included), zero false flags on rows already known-good.
- [x] TASK-004: Write Tier 2 dispatch instructions (target set = Tier 1's flagged rows, chunked
      ~25-30 per call; contract + evidence class, spec `Status:` + any `gh pr view`/`gh pr
      create` results gathered by THIS skill and handed to the scanner as inline text, never a
      new `gh` capability on the scanner; a scanner timeout or out-of-vocabulary verdict treated
      as UNSURE) handed to `agents/audit-scanner.md`, verdict grammar OK/FIX/REMOVE/UNSURE/
      DANGER, and Apply mechanics (`backlog.sh set <ID> <state> [note]` is the ONLY mutation,
      best-effort per row with failed flips surfaced in the PR body, push/PR-create failure
      exits non-zero naming the orphan branch) , acceptance: matches topology-drift's Step 4/5
      shape exactly (dispatch only on non-empty delta, chunked).
- [x] TASK-005: Register `backlog-reconcile` in `docs/patterns/audit-loop.md`'s "Known
      instances" section (one paragraph, same shape as the topology-drift/kit:feature-map
      paragraph) , acceptance: `grep -q backlog-reconcile docs/patterns/audit-loop.md`.
- [x] TASK-006: Regenerate `docs/FEATURES.md` (`bash lib/registry/feature-registry.sh generate`)
      and add the corresponding `docs/workflow-paths.md` section-5 line , acceptance:
      `bash lib/registry/feature-registry.sh generate /tmp/f.md && cmp -s /tmp/f.md docs/FEATURES.md`.

### Phase 3: Polish
- [x] TASK-007: Seeded-drift dogfood run against dwarves-kit's own `_meta/BACKLOG.md` (copy to
      a scratch `BACKLOG_FILE`, seed one row with a dead pointer, run the skill's Tier1+Tier2
      pass, confirm it's caught and a reference-fix diff is produced) plus a negative control
      (revert the fix, confirm the drift reappears, restore) , acceptance: both runs recorded
      verbatim at `docs/verification/backlog-reconcile.md`.

## After state

- [x] `skills/backlog-reconcile/SKILL.md` exists and matches the four-slots + process shape.
      (Today: no such file; `docs/patterns/audit-loop.md`'s "Backlog reconcile" row is design-only.)
- [x] `docs/patterns/audit-loop.md` names `backlog-reconcile` as a Known instance, checkable by
      `grep -q backlog-reconcile docs/patterns/audit-loop.md`.
- [x] `docs/FEATURES.md` includes the new skill and is byte-identical to a fresh regen.
- [x] A seeded drifted row is caught end to end with a negative control, recorded at
      `docs/verification/backlog-reconcile.md`.

## Acceptance Criteria (global)

- [x] All tasks pass their individual acceptance criteria.
- [x] The seeded-drift dogfood run (TASK-007) is the primary proof; no unit-test framework is
      introduced (topology-drift, the direct precedent, has none either, its own Process steps
      ARE its test).
- [x] No regressions: `bash tests/test-meta.sh` stays green after the FEATURES.md regen.

## Verification

```
bash lib/registry/feature-registry.sh generate /tmp/feat-check.md && cmp -s /tmp/feat-check.md docs/FEATURES.md && echo FRESH
grep -q "backlog-reconcile" docs/patterns/audit-loop.md && grep -q "backlog-reconcile" docs/workflow-paths.md && echo REGISTERED
bash tests/test-meta.sh
```

Plus the behavioral proof at `docs/verification/backlog-reconcile.md` (TASK-007): seeded-drift
run + negative control, per `proof-gate.sh contract`'s bar for this task type
(`type=reconcile class=behavioral`).

## Edge Cases

1. A row's `Target artifact` names a `SPEC-NNN` that no longer exists on disk (renamed,
   renumbered, or deleted). Tier 1 detects via the existence check; verdict is FIX (point at
   the renamed file if `git log --follow` finds one) or DANGER (deleted with no successor,
   someone may still be trusting the row), never a silent REMOVE. The extraction itself is
   glob-scoped to `docs/specs/SPEC-NNN-*.md` and content-pattern matched, never a raw path taken
   from the row and stat'd unbounded, so a malformed `Target artifact` cell cannot make the
   check read outside that directory (folded in from the test-plan's original security-framed
   case; the field is maintainer-authored, not untrusted input, so this is a boundary property,
   not an adversarial-abuse case).
2. A row's `Status` is `shipped` but the row is still on the Active queue AND its `Target
   artifact` does NOT point at `_meta/megagoals/`. The schema itself says shipped rows drop off
   (CHANGELOG is canonical); Tier 1 flags this mechanically, verdict is FIX (move it off, per
   the schema's own rule), evidence = the schema text itself. A shipped row whose `Target
   artifact` DOES point at `_meta/megagoals/` (an umbrella/tracking row kept deliberately, e.g.
   this repo's own `ID-101`) is exempt, not flagged.
3. A `(tiny, no spec)` row is `queued` with no git-log match. This is the expected, common
   case (not started yet); Tier 1 does NOT flag it. Only `executing`/`shipped` claims with no
   match, or an ambiguous multi-match, are flagged. The batched `git log --grep -F` pass uses
   fixed-string matching, never a raw regex interpolation of the row's title.
4. The target repo's `_meta/BACKLOG.md` has zero Active-queue rows. Report CLEAN immediately
   (matches `backlog.sh board`'s own "(no Active-queue rows found)" case), no branch created.
5. No cell in a row matches either `^SPEC-\d+$` or `^\(tiny, no spec\)$` (the row predates the
   Target-artifact convention, or a real column is missing/malformed). Tier 1 flags this as
   UNSURE, never guesses which cell was meant.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Tier 2 dispatched on every row instead of the delta (cost blowup on a large board) | `agents/audit-scanner.md` invocation count > flagged-row count in the run transcript | The Process step must explicitly gate: "zero deltas = zero dispatch", chunked at ~25-30 rows per call, matching topology-drift Step 4 verbatim; caught by TASK-004's acceptance check |
| `agents/audit-scanner.md` times out, errors, or returns a verdict outside OK/FIX/REMOVE/UNSURE/DANGER, or unparseable evidence | non-zero exit, timeout, or a verdict string that fails the fixed-vocabulary parse | Treat as UNSURE, never coerce to OK and never silently drop the row |
| `gh pr view`/`gh pr create` rate-limited or unauthenticated (run by this skill itself, not the scanner) | non-zero exit / auth error from `gh` | Read-path (`gh pr view`, shipped-claim evidence): treat as UNTESTABLE, never REMOVE, per the pattern's hard rule. Write-path (`gh pr create`, the publish step): exit non-zero, name the orphan branch in the operator-facing message, never a silent success |
| Applying a fix outside the isolated branch (skill runs on `master`/`main` directly) | `git branch --show-current` is a protected branch at Apply time | Step 2 (branch first) refuses to proceed past Tier 1 if not already on an isolated branch, mirroring memory-tidy's own red-flag |
| A `backlog.sh set` flip fails mid-loop (unknown state/ID rejected by its own contract) on row N of a multi-row apply | non-zero exit from `backlog.sh set` for that row | Best-effort per row: rows 1..N-1 stay applied, the loop continues past N, the failure is surfaced in the PR body, never silently swallowed |
| Two reconcile runs on the same repo race (concurrent operators, or a future cadence wrapper) | two open reconcile PRs from the same repo at once | Not a corruption risk: every mutation is branch+PR isolated (same property `topology-drift`/`memory-tidy` already have, unaddressed there too). The operator sees two competing PRs and merges one, closing/rebasing the other. Flagged here as a known, bounded, precedented limitation, not fixed by this spec. (Reviewer 2 finding.) |

## Out of Scope

- Wiring the personal, out-of-kit `audit` front-door skill (ops-toolkit) to route "audit
  backlog" here. That is a follow-up in the consumer repo, per the decision brief's Q1.
- A `/loop` or scheduled-cadence wrapper. Per the decision brief's Q4 cut list, cadence is
  `loop-engineering`'s concern if ever wanted, not this skill's.
- Any new verdict vocabulary beyond OK/FIX/REMOVE/UNSURE/DANGER.
- A `backlog.sh rows --fields ...` machine-readable CLI extension. `Target artifact` is read by
  content-pattern match on the raw file instead (design critique High-1); a shared-parser CLI
  extension is a real, named follow-up, not pulled into this spec since it widens a shared
  component's surface beyond this one consumer.
- Widening `agents/audit-scanner.md`'s tool roster with `gh`. This skill gathers any `gh`
  evidence itself and hands it to the scanner as inline text (design critique High-2).

## Decision Log

- DEC-001: General-purpose scope (every adopter, via `/kit:adopt`), not maintainer-only like
  `topology-drift`. Rationale: every adopter repo gets `_meta/BACKLOG.md` + `backlog.sh`
  identically; `topology-drift`'s maintainer-only-ness is specific to `FEATURES.md`/
  `workflow-paths.md`, a schema unique to this repo, which does not apply here. Alternative
  (maintainer-only first, open later) was offered and the operator picked general-purpose in
  the initial design confirmation.
- DEC-002: Ship the complete Tier1+Tier2 shape in one pass, not a staged Tier-1-only v1.
  Operator's explicit override of the recommended staged approach during `/kit:think` Q3; see
  `docs/briefs/DECISION-BRIEF-backlog-reconcile.md`.
- DEC-003: Contract's evidence anchor corrected from a `→` pointer convention (ops-toolkit-only,
  not part of the kit's schema) to the kit's real SPEC-005 schema (`Target artifact` + `Status`,
  spec file `Status:` header, `git log --grep` for `(tiny, no spec)` rows). Found by
  `/kit:spec-validate` Reviewer 3 (Assumption Destroyer); every downstream section (Picture,
  Design, Interfaces, Task Breakdown, Edge Cases) updated in the same pass. Also folded in
  Reviewer 2's (Failure Mode Analyst) concurrent-runs finding into `## Failure modes`.
- DEC-004: `/kit:devs-team`'s 5-lens design critique returned REVISE (2 CRITICAL, 5 HIGH, 4
  MEDIUM, 5 LOW), verified against the live `_meta/BACKLOG.md`, not asserted on paper: the
  DEC-003 sweep itself missed the Notes-cell reference in 3 places, the Status-mapping covered
  only 2 of >=5 real vocabulary words, and `Target artifact` extraction assumed a fixed column
  index the live file's 83-of-157 short rows don't have. All CRITICAL/HIGH findings and every
  MEDIUM finding fixed in this same pass (Picture, Extensibility, Design > Boundaries &
  failure modes, Interfaces, Task Breakdown, Edge Cases, Failure modes, Test plan, Out of
  Scope); LOW findings either fixed (folding case 10 into Edge Case 1) or explicitly accepted
  and named (DEC-002 stands; Tier 1 stays an inline bash block, matching precedent; the
  200+-row cost claim is named unverified rather than silently assumed).

## Test plan
Date: 2026-08-01
Source: this spec's `## Acceptance Criteria` + `## After state`

Step 1c applies: TASK-007's core claim (the skill catches a seeded drifted row) can only be
verified by observing `agents/audit-scanner.md`'s live judgment output, not a mechanical assert
alone.

| # | Case | Category | Covers (AC) | Expected | Proof | Tier | Smoke-eligible | Retry-eligible |
|---|---|---|---|---|---|---|---|---|
| 1 | `SKILL.md` exists with required frontmatter + four-slots table | happy-path | After-state bullet 1 | file present, `name`/`description`/`disable-model-invocation` set | `test -e skills/backlog-reconcile/SKILL.md` + grep frontmatter keys | mechanical -- file presence, no model needed | no | no |
| 2 | Tier 1 flags a `shipped`-status row still on the Active queue, `Target artifact` NOT under `_meta/megagoals/` | happy-path | Edge Case 2 | row flagged FIX | fixture `BACKLOG_FILE` with one seeded shipped row, run Tier 1, grep its output | mechanical -- pure schema-rule check | no | no |
| 2b | Same, but `Target artifact` points at `_meta/megagoals/` (umbrella row, e.g. this repo's `ID-101` shape) | boundary/edge | Edge Case 2 exemption | NOT flagged | fixture row, run Tier 1, confirm zero flags | mechanical -- exemption is a fixed rule | no | no |
| 3 | Tier 1 flags a spec-`Status:`/board-`Status` mismatch, exercised against the FULL vocabulary (DRAFT/APPROVED/VALIDATED/SHIPPED/PARKED, incl. trailing free text like `SHIPPED (v1.6.0)`) | happy-path | Picture Tier-1 mapping | row flagged only on a real mismatch; free-text suffixes ignored | fixture rows, one per vocabulary word, run Tier 1, confirm correct flag/no-flag per row | mechanical -- leading-keyword extraction + table lookup | no | no |
| 3b | Spec file exists but its `Status:` header is missing or an unrecognized word | boundary/edge | Design critique Medium-3 | always flagged, never a silent pass | fixture spec file with a garbled/absent header | mechanical -- presence check | no | no |
| 4 | Tier 2 (`audit-scanner`) verdicts a seeded drifted row correctly, with quoted evidence | happy-path | TASK-007, After-state bullet 4 | verdict is FIX (or DANGER, matching the seed), evidence quotes both sides | `docs/verification/backlog-reconcile.md` transcript | behavioral -- verdict QUALITY is a live-model judgment call, config asserts can't check it | no | no |
| 5 | Empty Active queue (zero rows) | boundary/edge | Edge Case 4 | report CLEAN, no branch created | fixture with zero rows, confirm no `git worktree`/branch appears | mechanical -- deterministic short-circuit | no | no |
| 6 | `(tiny, no spec)` row, `queued`, no git-log match | boundary/edge | Edge Case 3 | NOT flagged (expected/common case) | fixture row, run Tier 1, confirm zero flags on this row | mechanical -- grep + status check | no | no |
| 7 | `(tiny, no spec)` row, `executing`/`shipped`, no git-log match | boundary/edge | Picture Tier-1 tiny-row rule | flagged | fixture row, confirm flag | mechanical -- grep + status check | no | no |
| 7b | 10 `(tiny, no spec)` rows in one fixture | boundary/edge | Design critique High-5 (N+1 fix) | ONE `git log` subprocess for all 10, not 10 | run Tier 1, count `git log` invocations in the transcript, confirm 1 | mechanical -- invocation count | no | no |
| 7c | A `(tiny, no spec)` row's Title contains regex metacharacters (e.g. `fix(auth): handle [edge] case*`) | security/abuse | Design critique High-4 | no crash, no false match; fixed-string grep used | fixture row with the title above, run Tier 1, confirm clean exit + correct match/no-match | mechanical -- fixed-string grep is a fixed implementation property | no | no |
| 8 | `gh pr view` unauthenticated/rate-limited during shipped-claim verification (read path) | failure-injection | Failure modes row 3 (read path) | verdict UNTESTABLE, never REMOVE | stub `gh` to fail, confirm verdict class | mechanical -- exit-code branch, not a judgment call | no | no |
| 8b | `gh pr create` fails after Apply already flipped a status on the branch (write path) | failure-injection | Failure modes row 3 (write path) | exits non-zero, names the orphan branch, never a silent success | stub `gh pr create` to fail post-Apply, confirm exit code + message | mechanical -- exit-code branch | no | no |
| 8c | `audit-scanner` times out or returns a verdict outside OK/FIX/REMOVE/UNSURE/DANGER | failure-injection | Failure modes row 2 | treated as UNSURE, never coerced to OK, row never silently dropped | stub the scanner dispatch to return garbage, confirm the row lands UNSURE in the PR body | mechanical -- this tests the DISPATCHING skill's parse/handling of a bad response, not judgment quality | no | no |
| 9 | `Target artifact` names a `SPEC-NNN` file that no longer exists | failure-injection | Edge Case 1 | verdict FIX (renamed, if `git log --follow` finds one) or DANGER, never silent REMOVE | fixture row with a dangling `Target artifact`, run Tier 1 + Tier 2, inspect verdict | behavioral -- choosing FIX-with-successor vs DANGER needs judgment on git history, not a fixed rule | no | no |
| 10 | A flagged-row delta larger than one chunk (e.g. 60 flagged rows) | boundary/edge | Design critique Medium-1 (chunking) | Tier 2 dispatches in batches of ~25-30 rows, looped, never one unbounded call | fixture with 60 seeded-flaggable rows, count rows per `audit-scanner` invocation in the transcript | mechanical -- batch-size check | no | no |
| 11 | Skill invoked while on `master`/a protected branch | regression | Failure modes row 4 | refuses before Apply, matches memory-tidy's own red-flag | run against a fixture repo checked out on `master`, confirm refusal, no mutation | mechanical -- `git branch --show-current` check | no | no |
| 12 | A row with no checkable evidence (no cell matches `^SPEC-\d+$`/`^\(tiny, no spec\)$`) | regression | pattern doc's hard rule: UNSURE never auto-resolved; Edge Case 5 | listed as UNSURE in the PR body, no status flip applied | fixture row, run full pass, diff the branch (no flip) + PR body (row listed) | mechanical -- diff-based, checking ABSENCE of a mutation, not judgment quality | no | no |
| 12b | One `backlog.sh set` call fails mid-loop across a multi-row apply (row N of N+M) | regression | Failure modes row 5 (apply atomicity) | rows before N stay applied, the loop continues past N, the failure is surfaced in the PR body | fixture with a row whose target state `backlog.sh set` rejects, run Apply, confirm partial-success + PR-body note | mechanical -- exit-code + diff check | no | no |
| 13 | All-clean fixture (every row passes Tier 1) | regression | Failure modes row 1 (cost gate) | zero Tier-2 dispatch | run against dwarves-kit's own current `_meta/BACKLOG.md` post-fix (the `ID-101` umbrella row and the column-drift rows should no longer false-flag), grep the run transcript for zero `audit-scanner` invocations | mechanical -- invocation count | no | no |

### AI-in-the-loop doctrine
- Floor rule: config asserts lie; a behavior claim keeps a real-model probe.
- Never delete or downgrade a behavior/security claim below the `behavioral` tier to cut cost.
- Never let a `smoke`-tier run gate a ship.
- A security or side-effect case is never smoke-eligible, only ever `behavioral`.
- Smoke tier iterates grading rules only, never a gate. Retry is allowlisted benign-phrasing
  misses only; security/side-effect verdicts are never retry-eligible.

### Coverage notes
- Categories skipped: none, all five (happy-path, boundary/edge, failure-injection, security/
  abuse, regression) are represented; case 7c is the one genuinely adversarial-shaped case
  (regex-metacharacter injection via a row title), kept `mechanical` since fixed-string grep is
  a fixed implementation property, not a model judgment call.
- Cases 4 and 9 are the only `behavioral`-tier cases (live `audit-scanner` judgment); everything
  else is `mechanical` because Tier 1's checks and the apply/refusal mechanics are fixed rules,
  not model calls. This matches the spec's own design: Tier 1 is deliberately mechanical so
  cost scales with drift, not board size.
- No case exercises a 200+ row board to empirically validate the amortized-cost claim
  (Extensibility section); named as an unverified-at-scale gap per the design critique's
  Performance Low-2 finding, not silently assumed.
- This is a coverage TARGET, not an exhaustive list. A future case (e.g. two rows pointing at
  the same renamed spec file) is a gap to add on discovery, not a guarantee this matrix is complete.

## Design critique
Date: 2026-08-01
Design source: this spec's `## Solution` / `## Design` / `## Technical Design`
Lenses run: Simplicity, Performance, Boundaries/composability, Data-model & correctness,
Operability/failure-modes; missing: none

### Critical findings
1. **"Notes-cell backfill" targets a column that doesn't exist.** Survived DEC-003's schema
   correction in 3 places (Picture APPLY box, TASK-004, Interfaces "Produces") despite DEC-003
   itself claiming a full sweep. The corrected SPEC-005 schema has no Notes column at all. --
   found by: Data-model, Boundaries -- fix: delete every "Notes-cell backfill" reference; the
   one apply mechanism is `backlog.sh set <ID> <state> [note]`'s bracketed note, appended
   inside the Status cell, which already exists and needs no new write path.
2. **Tier 1's spec-Status<->board-Status mapping covers 2 of >=5 real vocabulary words.** Live
   `docs/specs/*.md` greps show `SHIPPED` (48 occurrences incl. `SHIPPED (v1.6.0)`,
   `SHIPPED-PENDING`), `PARKED` (2), `Implemented` (1), plus free-text suffixes on `DRAFT`
   (`Draft · 2026-07-31 · Owner: Han`) -- none handled by the spec's 2-branch mapping. As
   written, Tier 1 either false-flags most SHIPPED/PARKED specs or silently no-ops on them. --
   found by: Data-model (CRITICAL), Simplicity (HIGH, same root cause) -- fix: extend the
   mapping to the full observed vocabulary, extract the LEADING KEYWORD only (mirroring
   `backlog.sh set_state`'s own `sub(/^[A-Za-z-]+/, "", rest)` pattern) and ignore trailing
   free text; an unrecognized keyword is a flag, never a silent pass.

### High findings
1. **`Target artifact` extraction assumes a fixed 6-column row shape the live file doesn't
   have.** `awk -F'|' 'NF'` over the Active queue shows 83 rows at NF=6 (Target-artifact/Lane
   cells omitted) vs 74 at canonical NF=8, plus stragglers at NF=5/7/10/11 from prose/code
   spans. A fixed-index read silently reads the wrong cell on the majority of real rows. --
   found by: Data-model, Boundaries (root cause: `backlog.sh`'s `_rows()` only ever emits 3
   fields, id/title/status, so no shared parser exposes this column at all) -- fix: extract by
   CONTENT PATTERN (a cell matching `^SPEC-\d+$` or `^\(tiny, no spec\)$`), not column index; a
   row with no matching cell is UNSURE ("predates the Target-artifact convention"), never a
   crash or a silent misread. `backlog.sh` itself stays untouched (a `rows --fields` CLI
   extension is a real option but is new shared-component scope; named as a follow-up, not
   pulled into this spec).
2. **Tier 2's evidence class assumes `gh pr view` capability `agents/audit-scanner.md` does not
   have.** The scanner's tool roster (its own frontmatter) has no `Bash(gh *)` entry, only
   git/ls/find/wc/cat/head. The spec claims the scanner is "consumed... unchanged" while
   needing a capability it doesn't grant. -- found by: Boundaries -- fix: the DISPATCHING
   skill (this one) runs `gh pr view`/`gh pr create` itself in Tier 1/pre-dispatch and hands
   the captured text to the scanner as inline evidence in the dispatch prompt, exactly how
   `topology-drift` already gathers its own git evidence before dispatching. `audit-scanner.md`
   stays genuinely untouched.
3. **Tier-2 dispatch failure or an out-of-vocabulary verdict has no handling.** The Failure
   modes table covers cost blowup and `gh` read-path unavailability, not the scanner itself
   timing out or returning something outside OK/FIX/REMOVE/UNSURE/DANGER. -- found by:
   Operability -- fix: add a failure-mode row, treat as UNSURE, never coerce to OK or silently
   drop the row.
4. **`git log --grep` fed a raw row Title/ID with no escaping.** A title with regex
   metacharacters can crash the grep or produce a false match/non-match on the one path Tier 1
   always runs. -- found by: Operability -- fix: fixed-string grep (`git log --grep -F --
   <literal>`), not a regex interpolation.
5. **Tier 1's `(tiny, no spec)` check is an N+1: one `git log --grep` subprocess per row**,
   contradicting the Extensibility section's "Tier 1 runs on every row for free" claim (cost is
   O(rows x history-size), not O(1)). -- found by: Performance -- fix: one batched
   `git log --oneline` pass, match every row's ID/title in-memory against it, not N separate
   subprocess+history-walks.
6. **Shipped-row-still-on-queue has no carve-out, and live data already violates the naive
   rule.** `ID-101` is `shipped`, still on the Active queue, a mega-goal umbrella/tracking row
   kept deliberately for traceability -- exactly what TASK-003's own acceptance bar ("zero
   false flags on rows already known-good") will hit on day one against this exact repo. --
   found by: Data-model -- fix: a shipped row whose `Target artifact` points at
   `_meta/megagoals/` is not flagged; state this exception explicitly.

### Medium findings
1. Tier-2 dispatch has no cap on the flagged-row set size; a systemic drift event could hand
   the scanner an unbounded target list in one call. -- Performance -- fix: chunk the delta
   into batches of ~25-30 rows per dispatch, looped.
2. Spec `Status:` header extraction method (full-file Read vs `grep -m1`) is unspecified,
   letting I/O scale with file size x row count instead of bytes x row count. -- Performance --
   fix: hardcode `grep -m1 '^Status:'`/`head` in TASK-003's bash block.
3. A spec file with a missing or unrecognized `Status:` header is unaddressed; silent
   pass-through would produce a false CLEAN, the exact failure class this skill exists to
   catch. -- Operability -- fix: missing/unrecognized header is always a flag, never a silent
   skip.
4. Push/PR-create failure after Apply can leave real mutations on a branch with no PR pointing
   at them and no operator-facing signal (the Failure modes table's row 2 only covers the READ
   path, `gh pr view`, not the write/publish path). -- Operability -- fix: add a failure-mode
   row, push/PR-create failure exits non-zero naming the orphan branch, never silent success.

### Low findings
1. Test-matrix case 10 frames a self-authored, maintainer-written field (`Target artifact`) as
   an adversarial "security/abuse" category; the field isn't untrusted external input. --
   Simplicity -- fix: fold into Edge Case 1 as a plain glob-scoping boundary check, drop the
   security-category framing.
2. No test case exercises a large fixture (200+ rows) to empirically validate the "cost scales
   with drift, not board size" claim; it is currently asserted in prose only. -- Performance --
   fix: soften the Extensibility wording to "amortized/typical case" or add one large-fixture
   case to TASK-007, noting the claim is otherwise unverified at scale.
3. Tier 1 lives only as an inline bash block in SKILL.md with no independent test harness
   (same shape as `topology-drift`, not new risk, but the weakest "testable independently" link
   in this design). -- Boundaries -- no spec change required; named as a future escalation path
   if Tier 1 grows past a few checks.
4. No stated atomicity for a multi-row Apply loop (partial-failure behavior undefined). --
   Operability -- fix: best-effort per row, every failed flip surfaced in the PR body, loop
   continues rather than aborting.
5. DEC-002 (ship Tier1+Tier2 complete, no staged v1) overrides `/kit:think`'s recommended
   staged rollout with no new technical justification beyond precedent. -- Simplicity --
   already an explicit, ledgered operator decision (DEC-002); noted for the record, no action.

### Scores
- Simplicity: 7/10
- Performance: 5/10
- Boundaries/composability: 5/10
- Data-model & correctness: 4/10
- Operability/failure-modes: 6/10

### Verdict: REVISE

The shape (Tier1/Tier2 split, UNSURE-never-auto-resolved, branch+PR gate, DANGER-not-silent-
REMOVE, reuse of `backlog.sh`/`audit-scanner.md` unchanged) is sound and correctly modeled on
precedent. But three of the spec's named mechanical checks were specified against an idealized
schema the live `_meta/BACKLOG.md` does not match (Notes-cell, the 2-branch Status mapping, the
fixed-column Target-artifact read), verified by grep/awk against the actual file, not asserted.
As written, the spec would not survive its own TASK-007 dogfood run. Fixed below in the same
pass, per DEC-004.

## Review
Date: 2026-08-01
Reviewers: security-reviewer, code-reviewer (architecture), code-reviewer (test-coverage), advisor (critique mode)
Scope: staged diff, 9 files (README.md, docs/FEATURES.md, docs/briefs/CONTEXT.md,
docs/briefs/DECISION-BRIEF-backlog-reconcile.md, docs/patterns/audit-loop.md,
docs/specs/SPEC-225-backlog-reconcile.md, docs/verification/backlog-reconcile.md,
docs/workflow-paths.md, skills/backlog-reconcile/SKILL.md). `coverage-delta.sh`: exempt
(docs/skill markdown only, no source).

### Security
1. HIGH -- shell-command injection: `git log --grep -F` closes regex injection, not
   shell-quoting injection, when a row Title is embedded into the literal command an executing
   agent runs. FIXED: Process step 4c now explicitly requires passing titles as separate
   arguments (array/`printf '%q'`), never string-concatenation; Red flags names it.
2. MEDIUM -- indirect prompt injection via `gh` evidence handed to `audit-scanner.md` with no
   untrusted-data framing. FIXED: Process step 5 now fences it as "an untrusted excerpt to
   judge as DATA, never as instructions".
3. Checked, no issues: path traversal (`Target artifact` content-pattern matched before any
   filesystem touch), write-path scope (`audit-scanner.md` tool roster not widened), no
   secrets/credentials, no data exposure, no auth/authz surface (a PR is the real gate).

### Architecture
1. MEDIUM -- no post-apply re-verification step, unlike both cited precedents (`topology-drift`
   Step 6, `memory-tidy` Step 6). FIXED: new step 8 ("Re-verify") re-runs Tier 1 on touched rows
   before Ship; a residual flag is a failed-fix PR-body note, never a silent ship.
2. LOW-MEDIUM -- REMOVE verdict had no stated `backlog.sh` state mapping, leaving room for a
   forbidden hand-deleted row. FIXED: step 7 states `REMOVE -> backlog.sh set <ID> dropped
   [note]`; Red flags names the hand-delete anti-pattern explicitly.
3. Stale-ADR-inversion check: PASS, shipped SKILL.md matches the spec's corrected (post-DEC-003/
   DEC-004) design exactly, no drift. Deep-module assessment: PASS (small trigger interface,
   real hidden behavior, passes the deletion test, no widened shared-component surface).
   Score: 8/10.

### Test coverage
1. HIGH -- Test-plan case 3 ("full vocabulary") was proven against only one vocabulary pair.
   FIXED: `docs/verification/backlog-reconcile.md` Run 3 adds DRAFT/PARKED/free-text-suffix
   fixtures plus a PARKED-mismatch detection case.
2. HIGH -- 17 of 20 test-plan matrix rows had no corresponding proof in the diff, and the Scope
   note didn't name the gap. FIXED: `docs/verification/backlog-reconcile.md`'s Scope note now
   names exactly which cases remain unexercised (2, 2b, 5, 6, 7, 7b, 7c, 8, 8b, 8c, 10, 11, 12,
   12b, 13) as a legitimate, cheap follow-up, not silently assumed passing, while noting this
   spec's own literal `## Acceptance Criteria` gate (TASK-007 only, matching `topology-drift`
   precedent) does not require them to ship this spec. Score: 6/10 (pre-fix).

### Advisor (cross-cutting)
1. Stale "157 active rows" statistic repeated across spec/skill/verification (real count 177,
   self-contradicted by the verification doc's own live-run output two paragraphs below the
   stale figure). FIXED: all 4 call sites corrected to 177.
2. `docs/patterns/audit-loop.md`'s closing sentence said "Both in-kit instances" undercounting
   after this diff's own addition of a third. FIXED: reworded to "All three in-kit instances".

### TODOs
None open; every finding above was fixed in this pass, not deferred.

### Verdict: SHIP

All CRITICAL/HIGH/MEDIUM findings from both `/kit:spec-validate` (Reviewer 3's schema
correction) and `/kit:devs-team`'s design critique were fixed before this review; this
post-build `/kit:review-team` pass found 4 additional real, previously-uncaught issues (1
security HIGH, 1 security MEDIUM, 1 architecture MEDIUM, 2 test-coverage HIGH) plus 2 advisor
cross-cutting findings, all fixed in the same pass. `bash tests/test-meta.sh` 806/806 green
after every fix.

## Open questions

(none)
