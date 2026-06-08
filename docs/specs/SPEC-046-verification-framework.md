# Spec: Verification framework (scientific-method spine + set-wise dir-layout gate)

Status: SHIPPED
Lane: feature

> Retroactive note: this work was first built as a `/goal` loop, then documented as a SPEC
> after the fact when the SDD lifecycle was applied to it (the dogfood the user asked for).
> The acceptance criteria below were verified by the recorded runs in
> `docs/verification/verification-framework/` and the consolidated `TEST-REPORT.md`.

## Problem

The kit's proof-of-done had grown three dialects that shared a grammar but not a shape:
the experiment `TEST-REPORT.md` + `PROVENANCE.md`, the tool `proof-of-done.md`, and the
feature `docs/verification/<slug>.md`. ops-toolkit additionally carried two competing
convention docs (`_meta/PROOF-OF-DONE.md` + `docs/verification/README.md`). The result:
proofs lived in three places, only one of which the ship-gate could see, and a re-run
overwrote prior entries instead of versioning them. There was no single, named model.

## Design

Name the scientific method that was already implicit and make it one spine:

1. **Hypothesis / assumptions** (`/kit:think`, `/kit:spec`) + **test design** (`/kit:test-plan`)
   land in a single stable `docs/verification/<slug>/test-design.md`.
2. **Execution** (`/kit:execute`, `/kit:verify`) writes one **immutable, versioned** record
   per run at `docs/verification/<slug>/runs/<timestamp>.md` (never overwritten).
3. The three task classes become three **profiles** of this one spine (eval / tool-build /
   feature), differing only in `test-design.md` content + run-report shape.
4. The verify stage runs a **bounded quality loop** (produce -> distinct-reviewer critique ->
   revise; hard round cap; `[[QL-VERDICT round=N clean=BOOL findings=K]]`; findings strictly
   fall) on the kit's existing reviewer dispatch. No new orchestrator.
5. The gate (`proof-ledger.sh check`) validates the `<slug>/` directory **set-wise**: a green
   run in one `runs/` file plus a negative control in another satisfies it; the flat
   `<slug>.md` and co-located `proof-of-done.md` paths stay per-file (back-compat).

## Scope

In: the canonical convention doc; the set-wise gate change; the quality-loop verify contract
(doc + reference); migrating the three existing dialects; reducing ops-toolkit's two convention
docs to pointers. Out: a new orchestrator / swarm runtime; coupling to OpenClaw or
pi-messenger-swarm (patterns borrowed, not imported); retrofitting every tool (three dogfood
instances is the bar). The `migrate`-keyword classifier false-positive was originally scoped
out, then pulled in as the recorded-live-run dogfood (see `docs/verification/classify-md-inert/`).

## Acceptance criteria

- AC1: one canonical convention doc in the kit defines the spine + `test-design.md` + `runs/`
  layout + quality-loop contract; ops-toolkit's two convention docs are pointers.
- AC2: the gate recognizes the `<slug>/` directory layout set-wise and the experiment dialect,
  verified by a real blocked-then-allowed push for each of the three profiles.
- AC3: each execution writes a new immutable `runs/` record; re-running a logged command
  reproduces its verdict with the negative control still flipping red.
- AC4: the three existing dialects are migrated to the unified layout, history preserved.
- AC5: no regression in the kit meta/hook suites.

## Test plan

| AC | Test (recorded) | Category |
|---|---|---|
| AC1 | structural: kit README has spine + layout + profiles; ops docs are pointers | doc-presence |
| AC2 | `tests/test-ship-gate-profiles.sh` (real hook, 3 profiles x allow+block) | behavioral + negative |
| AC2/AC3 | `tests/test-proof-dir-layout.sh` (set-wise accept; green-only blocks; pre-change lib blocks) | behavioral + 2 negative controls |
| AC3 | re-run both suites + `spec-to-cli/bin/proof negctl` (exit 3) | reproducibility |
| AC4 | `docs/verification/{codebase-tool-benchmark,spec-to-cli,verification-framework}/` exist | structural |
| AC5 | `tests/test-meta.sh` 390/390 | regression |

Consolidated results + verdict: `docs/verification/verification-framework/TEST-REPORT.md`.

## Resolved decisions (during build)

- Gate change is additive (`check()` gains a set-wise pass; `_fresh_proof_files` already
  matched the `runs/` files). Per-file path kept for back-compat.
- Migrating the experiment INTO `docs/verification/<slug>/` makes it gate-visible without
  teaching the gate about `experiments/.../TEST-REPORT.md`.
- ops-toolkit's `docs/verification/README.md` is KEPT (it is the opt-in marker); only its
  content becomes a pointer.

## Implementation status (2026-06-08)

SHIPPED. Evidence: kit commits f71346e / 0b65345 / 51a5ef9 (+ the meta-regression fix);
ops-toolkit commits 5a5d293 / 140a147 / 77e0000. Proof of done + consolidated report under
`docs/verification/verification-framework/`. Notes: `docs/implementation-notes/verification-framework.md`.
