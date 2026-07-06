# SPEC-070: rid = branch slug everywhere

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full)
Type: spec-feature / behavioral
Board: ID-059

## Problem

The run id (rid) and the ship-gate ledger key disagree by construction. `/kit:assign`
prose tells the operator to start the ledger under the SPEC slug (`spec-NNN` in
practice), while `hooks/ship-gate.sh` keys its gate check by the BRANCH slug
(`${BRANCH#*/}`). Every spec-driven ship therefore needs a mirror record dance
(re-record all gates under the branch slug), which happened 5 times in one day during
the quality wave and was named the worst friction in RETRO-2026-06-10-quality-wave.
The mirror rids also pollute lane-telemetry's `untracked` metric (mirrors have gates
but no START), making the headline dishonest.

## Decision

One canonical rid: the branch slug, derived once, used by both ends.

1. **New verb `lib/gate/gate-ledger.sh rid`**: prints the canonical rid for the cwd repo,
   defined as the current branch name with its leading `type/` segment stripped,
   exactly the ship-gate transform `${BRANCH#*/}`. A branch with no `/` prints
   unchanged. On `master`, `main`, or detached `HEAD` it exits 1 with "create the work
   branch first": a loud failure beats a silently wrong rid.
2. **Derivation stays duplicated, pinned.** `hooks/ship-gate.sh` resolves BRANCH from
   the cwd repo's `HEAD` (`rev-parse --abbrev-ref HEAD`, with the push command's
   leading `cd` resolved first) and stays self-contained; it keeps its own
   `${BRANCH#*/}` line. The duplication is kept for hook self-containment (no new
   dependency from the hook into the lib), and the two copies carry an agreement pin
   in `tests/test-meta.sh` (both files contain the literal `#*/` transform, so the
   lib's `rid` implementation must keep it greppable in code or comment), the
   SPEC-069 INTENTIONAL SEAM precedent.
3. **Placeholder sweep**: every `<spec-slug>` placeholder used as a gate-ledger RID
   argument becomes `<rid>`, with the derivation documented at the two entry points
   (`/kit:assign` Step, AGENTS.md gates section): `RID=$(bash lib/gate/gate-ledger.sh rid)`,
   run AFTER the branch exists. Swept surfaces: commands/{assign,start,ship,review,
   review-team,devs-team,test-plan,test-plan-review-team,execute}.md, AGENTS.md,
   WORKFLOW.md. Explicitly EXCLUDED: `commands/debug.md`'s `escaped-from=<spec-slug>`
   action field, which names the spec whose test plan leaked the defect, not a run id.
4. **No ledger migration.** Existing `spec-NNN` ledgers stay as history; the
   `untracked` metric becomes honest for new runs only (retro-accepted noise).
   Verified safe: ship-gate fails open for old in-flight runs (no spec file matches
   the new slug -> exit 0), nothing blocks.

Known limitation (accepted): `ledger_file` normalizes `/` and space to `-`, so the
rids `a/b` and `a-b` share one ledger file. Repo branch convention is
single-`/` `type/kebab-slug`, which cannot produce the collision; not worth a
separator change.

## Acceptance criteria

- AC1: in a repo on branch `feat/x-y`, `gate-ledger.sh rid` prints `x-y`, exit 0.
- AC2: on `master` (and detached HEAD), `rid` exits non-zero and prints nothing on
  stdout.
- AC3: a branch with no type prefix (`hotfix-z`) prints `hotfix-z` unchanged.
- AC4: the rid a fresh run starts under and the slug ship-gate later checks CONVERGE
  on the same ledger file: the verb emits the runid-normalized form (review S2: the
  visible key equals the filename stem), ship-gate's raw slug normalizes to the same
  stem inside `ledger_file`. Proven by the agreement pin (both files carry the `#*/`
  strip) + a convergence assertion + a live run.
- AC5: no gate-ledger RID call site still says `spec-slug`:
  `grep -rn 'spec-slug' commands/ AGENTS.md WORKFLOW.md | grep -v escaped-from | grep gate-ledger`
  returns zero hits (debug.md's `escaped-from` spec reference is exempt).
- AC6: a branch whose slug strips to empty (`feat/`) makes `rid` exit 1 (no hidden
  `.log` ledger file possible).

## Test plan

| # | Case | Proof | Expected |
|---|------|-------|----------|
| 1 | AC1 happy path | temp repo, `git switch -c feat/x-y`, run `rid` | stdout `x-y`, exit 0 |
| 2 | AC2 master guard | temp repo on master, run `rid` | exit 1, empty stdout |
| 3 | AC2 detached guard | temp repo, `git switch --detach`, run `rid` | exit 1, empty stdout |
| 4 | AC3 no-prefix | branch `hotfix-z`, run `rid` | stdout `hotfix-z` |
| 5 | AC4 agreement pin | grep both `hooks/ship-gate.sh` and `lib/gate/gate-ledger.sh` for the `#*/` strip transform | both present |
| 6 | AC5 sweep pin | grep `spec-slug` near gate-ledger calls across operating surfaces (escaped-from exempt) | zero hits |
| 7 | multi-slash branch | branch `feat/a/b`, run `rid` | stdout `a-b` (normalized filename stem; ship-gate's raw `a/b` maps to the same ledger file) |
| 8 | AC6 empty slug | branch `feat/` is unmakeable in git (trailing slash invalid), so simulate: the guard rejects an empty post-strip slug; unit-call the transform with `feat/` input if reachable, else pin the guard line exists | exit 1 |

Negative control: revert the `rid` verb (comment its case arm) -> every
dispatch-dependent assertion goes RED (measured live post-review: 9 RED), usage error
exit 64. Restored -> green. Run twice during build (pre-review: 7 RED of the smaller
suite; post-review-fixes: 9).

This run itself is the live AC4 proof: it starts under rid `rid-branch-slug` derived
from branch `feat/rid-branch-slug`, and ships through ship-gate with NO mirror records.

## Verification

- `tests/test-hooks.sh`: 329/329 (12 SPEC-070 assertions: master+main+detached
  refusals with empty stdout, prefix strip, prefixless passthrough with exit pin,
  normalized multi-slash, ledger-file convergence canary, empty-slug guard pin).
- `tests/test-meta.sh`: 432/432 (agreement pin both files, widened sweep pin
  covering `<slug>` grill sites, entry-point wiring pins).
- `tests/test-e2e.sh`: 20/20.
- Negative control: rid case arm disabled -> 9 RED; restored -> green.
- Live AC4: this run's own ledger is `runs/rid-branch-slug.log`, started at assign
  and checked at ship with zero mirror records.
- One unreproducible 328/329 flake observed once mid-review; 7 subsequent runs green
  (action-logged on the run, watching).

## Review

Date: 2026-06-11. Multi-lens (3 parallel reviewers, the SPEC-069 escalation rule:
lib/ touched). Pre-fix scores: security 7/10, architecture 6/10, test-coverage 6/10.

- Security: S1 MEDIUM `ledger_file` empty-stem guard (branch `feat/@` would merge
  audit trails into hidden `.log`) -> guard added; S2 LOW rid now emits the
  runid-normalized form so the visible key equals the filename stem.
- Architecture: A1 HIGH two grill call sites still said `<slug>` and the sweep pin
  was too narrow to catch them -> swept + pin widened; A2 HIGH assign.md derives RID
  with no branch-creation step before it -> branch-creation line added ahead of the
  derivation; A3 comment now quotes the local `${branch#*/}` form; A4 the rid
  definition paragraph moved above its first use in AGENTS.md.
- Test-coverage: T1 main-branch refusal untested -> fixture added; T2 detached
  stdout + T3 prefixless exit assertions added; T4 the live-parity assertion labeled
  as a dispatch canary (it re-applies the same expansion, cannot falsify the
  transform; the test-meta agreement pin is the real AC4 proof); T5 AC6 labeled
  source-text-pin-only; negative-control count corrected by measurement (9, not 7).

Post-fix: hooks 329/329, meta 432/432, e2e 20/20. Verdict: SHIP.
