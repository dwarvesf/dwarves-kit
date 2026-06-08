# Spec: Proof-of-Done task-type contracts (a compose axis on the verification gate)

Generated: 2026-06-08
Status: SHIPPED
Source: maintainer session 2026-06-08 (Han). Grew out of building a data-pull CLI in ops-toolkit and discovering the "what counts as done" standard was being reinvented ad-hoc instead of routed through the kit. Brainstormed + design approved 2026-06-08.
Prior spec: SPEC-042 (proof of done , the 3-part recorded artifact + negative control) and its later ship-gate enforcement (ADR-0025). This spec adds the task-TYPE axis on top of that foundation.
Depends on: the existing verification framework, which this EXTENDS, not replaces: `lib/proof-gate.sh` (proof-class classifier), `lib/lane-classify.sh` (risk-lane classifier), `lib/proof-ledger.sh` + `hooks/ship-gate.sh` (the ship/merge gate, ADR-0025), `docs/verification/README.md` + `docs/verification/proof-of-done.md` (the discipline).
Lane: full (touches hooks + the enforcement gate).
This spec's own proof class: behavioral (changes the gate's output + adds a classifier); its proof of done is a recorded run of the gate on sample tasks + a negative control (a task that should fail the gate does).

## Problem

The kit already routes work by **risk**: `lane-classify.sh` -> tiny/normal/full/bug, and `proof-gate.sh` -> a **proof class** (inert/behavioral/stateful) that says HOW RIGOROUS the proof of done must be (recorded run? negative control? rollback?). The ship-gate enforces that a fresh proof exists.

What is missing is the **shape** of the proof for different KINDS of work. "Behavioral" tells you to "run the real primary flow + a negative control", but it does not say *what artifact* a given work-type should produce. An evaluation should produce a TEST-REPORT (the `tool-eval-experiment` 5-pillar report); a data/API CLI should produce a recorded live run (`prove.py` -> `docs/proof-of-done.md`); a research task should produce a cited report. Today each of those lives in a separate skill (or, worse, gets reinvented per task). There is no single place that says "for THIS type of work, done means THIS artifact", and no enforcement that the right-shaped artifact is present.

Concretely: building the `growatt-pull` CLI in ops-toolkit, the operator first shipped a coverage table as "proof", which describes the API surface, not a working run. The correct proof for that work-type is a recorded live run. That distinction should be a routed, enforced standard, not a per-task argument.

## Design

### Two-axis model (compose, not replace)

Keep the existing **proof-CLASS** axis as the rigor floor. Add a second, orthogonal **task-TYPE** axis that names the artifact shape and the skill that owns the methodology. The required proof of done = **the TYPE's artifact shape, produced at the CLASS's rigor.**

```
task description
  -> lane-classify.sh   -> risk lane (tiny/normal/full/bug)        [unchanged]
  -> proof-gate.sh CLASS -> inert | behavioral | stateful           [unchanged] = rigor floor
  -> task-type-classify  -> eval | data-tool | research | ...       [NEW]      = artifact shape + skill
  -> required proof = shape(TYPE) at rigor(CLASS)
  -> ship-gate enforces a fresh, TYPE-appropriate proof artifact    [extended: type-aware]
```

Worked examples:
- `growatt-pull` CLI = TYPE `data-tool` x CLASS `behavioral` -> "recorded live run (`prove.py` -> `docs/proof-of-done.md`) + negative control."
- A Serena-vs-X benchmark = TYPE `eval` x CLASS `behavioral` -> "TEST-REPORT (5 pillars) + falsifiability control."
- A schema migration = TYPE `migration` x CLASS `stateful` -> "dry-run record on a copy + rollback path."

### New pieces (in dwarves-kit)

1. **`lib/task-type-classify.sh`** , deterministic `desc -> task-type`, keyword-based, mirrors `lane-classify.sh` (suggests, never blocks; human override). Precedence-ordered, first match wins. Pure bash + grep.
2. **A declarative registry** `docs/verification/task-types.md` , one row per type: `task-type | artifact shape | owning skill | default proof class`. **This is the extension point**: a new work-type later = add one row (+ optionally one classifier rule). No code change to add a type's contract.
3. **`proof-gate.sh` gains a `contract` subcommand** (or extends `requirement`) that composes CLASS + TYPE: reads the registry, returns the type-specific requirement string + the owning skill pointer, at the class's rigor.
4. **The ship-gate message becomes type-aware (first cut, messaging only)**: the diff-based gate derives the proof CLASS from a diff but cannot derive the TYPE (which needs task intent), so the `proof-ledger.sh` BLOCKED message now points to `proof-gate.sh contract "<task>"` for the type-specific artifact + skill. The fresh-proof + branch-diff enforcement mechanism is **unchanged** (opt-in per repo, logged-override, fails-open); `hooks/ship-gate.sh` is untouched. **Phase 2 (deferred, see Scope):** auto-deriving the expected artifact for a type from the diff so the gate hard-enforces the exact shape.

### Seed registry (extensible)

| task-type | artifact (proof shape) | owning skill | default class |
|---|---|---|---|
| eval | TEST-REPORT (5 pillars) + PROVENANCE | `tool-eval-experiment` | behavioral |
| data/api/cli-tool | recorded live run (`prove.py` -> `docs/proof-of-done.md`) + negative control | `ops-tool-shape` Done gate | behavioral |
| research | cited report + sources, adversarially verified | `deep-research` | inert/behavioral |
| spec-feature | tests pass + acceptance criteria met | kit `/execute` verifier | behavioral |
| migration/deploy | dry-run record on a copy + rollback path | kit native (stateful) | stateful |
| doc | doc-verifier confirms docs match code | kit `/docs` | inert |

Human override always wins; the registry suggests. More types get appended as new kinds of work appear (the maintainer flagged this is expected).

## Adoption / rollout

1. **Opt ops-toolkit into the kit verification framework**: add `docs/verification/README.md` (the opt-in marker) + make `lib/proof-gate.sh` / `lib/proof-ledger.sh` reachable + wire the ship-gate. Then ops-toolkit's tool work is gated by the kit, not a bespoke hook.
2. **Retire the ops-toolkit bespoke gate** built 2026-06-08 (`_meta/infra/scripts/done-gate-hook.sh` + its `settings.json` wiring) and **trim the ops-toolkit `CLAUDE.md` "Done gate"** to a thin pointer to the kit standard (remove the duplicated rule). Keep `tools/growatt-pull/` (`prove.py`, `docs/proof-of-done.md`) as the worked example of the `data-tool` contract. **Sequencing: retire only AFTER the kit framework is adopted in ops-toolkit**, so there is no enforcement gap; until then the bespoke hook stays as interim cover.
3. **Roll out to other repos** opt-in, as each needs it.

## Scope

**First cut (YAGNI):** `task-type-classify.sh` + `docs/verification/task-types.md` registry + `proof-gate.sh contract` compose + the 6 seed types above. The gate change lands as **type-aware messaging first** (the requirement string names the expected artifact); hard-enforcing the *exact* artifact per type is a follow-up, because the existing fresh-proof check already gates the merge.

**Out of scope (this spec):**
- Rewriting the proof-class semantics (the compose model keeps them).
- The ops-toolkit adoption + bespoke-gate retirement (Phase C above) , that is downstream per-repo work, tracked separately once this lands.
- Auto-classification accuracy tuning beyond keyword rules (humans override).

## Acceptance criteria

1. `lib/task-type-classify.sh classify "<desc>"` returns a type for each of the 6 seed types on representative descriptions; `... types` lists them.
2. `docs/verification/task-types.md` exists with one row per seed type (type, artifact, skill, default class).
3. `proof-gate.sh contract "<desc>"` composes CLASS + TYPE and returns the type-specific requirement + skill pointer (e.g. a CLI-build desc returns the recorded-run requirement pointing at `ops-tool-shape`).
4. Proof of done for THIS spec: a recorded run showing the new classifier + contract on sample tasks, plus a negative control (a description that should NOT match a type falls through to a sane default), captured in `docs/verification/SPEC-044.md`.
5. `tests/test-meta.sh` still passes (no duplicate SPEC number; registry well-formed).

## Resolved decisions (during build)

- Registry format: **markdown table** (`docs/verification/task-types.md`), parsed by `proof-gate.sh` via awk; matches the `MANIFEST.md`/`CONSUMERS.md` precedent and stays human-greppable. Cells use no `|` or `->` so the parse stays trivial.
- Classifier home: **own file** `lib/task-type-classify.sh`, mirroring `lane-classify.sh` (single-purpose), not folded into `proof-gate.sh`.
- Gate type-awareness (first cut): the diff-based ship-gate can derive the proof CLASS from a diff but not the TYPE (which needs task intent). So the BLOCKED message now **points to `proof-gate.sh contract "<task>"`** for the type-specific artifact, rather than auto-typing a diff. Auto-typing from a diff is the deferred follow-up.

## Implementation status (2026-06-08)

Implemented + self-verified on `feat/proof-done-task-types`. Acceptance criteria mapped to evidence:

1. classifier 6 types + `types` , **met** (test-meta pins `classify -> {eval,research,doc,migration,data-tool}` + default `spec-feature`).
2. registry with a row per type , **met** (`docs/verification/task-types.md`; test-meta pins each row).
3. `proof-gate.sh contract` composes , **met** (test-meta pins the data-tool artifact+owner + the migration class upgrade).
4. proof of done for this spec , **met** (`docs/verification/SPEC-044.md`: green run + negative control + reproducible).
5. `tests/test-meta.sh` passes , **met** (389/389, Exit 0; SPEC-008 collision resolved by renumber to 044).

Validation + ship record: the `/kit:*` commands could not target dwarves-kit from the ops-toolkit session that ran this loop, so the validate + review gates ran as **adversarial sub-agents** on the branch diff (the kit's `reviewer` + `security-auditor` agents, the same agents `/kit:spec-validate` / `/kit:review-team` dispatch):
- Security/regression audit: **SHIP** , gate control-flow byte-identical to master, no injection, `test-hooks.sh` 164/164, `hooks/ship-gate.sh` untouched.
- Correctness/architecture: **FIX-FIRST** , 0 correctness defects; flagged 2 spec-honesty + 1 precedence-doc + 2 cheap hardening items. All resolved before merge: Design item 4 marked messaging-only/Phase-2; migration>data-tool precedence documented; CHANGELOG count corrected (18 assertions, suite 371->389); `_registry_field` skips the header/separator rows; `contract` with no arg errors (exit 64).

Shipped via merge of PR #16 to master. CHANGELOG entry under [Unreleased] (no version bump; ships under the next tag, per the kit's release cadence). See `docs/implementation-notes/SPEC-044-proof-done-task-types.md`.
