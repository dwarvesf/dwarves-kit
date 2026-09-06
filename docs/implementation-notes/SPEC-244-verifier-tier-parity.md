# Implementation notes: SPEC-244 verifier tier parity

Delta from the spec only. A mirror of the spec belongs in the spec.

## 2026-09-06 Generated feature registry needed a regenerate

- Context: the spec's file table did not list `docs/FEATURES.md`.
- Change: regenerated `docs/FEATURES.md` with `bash lib/registry/feature-registry.sh generate docs/FEATURES.md`.
- Why: `docs/FEATURES.md` is a generated projection. Adding SPEC-244 changed the spec-reference cells for several commands, so the SPEC-219 freshness pin in `tests/test-meta.sh` failed until the regenerate.
- Impact: no behavior change. The registry now matches the committed specs.
- Open questions: none.

## 2026-09-06 Parity phrase placed once per surface, with per-step pointers

- Context: the spec says `commands/verify.md` gains the override at Steps 3-6.
- Change: the full parity sentence sits once in Step 1 next to the `Model:` header read. Steps 3-6 each carry a short "at the spec tier per Step 1" clause instead of repeating it.
- Why: repeating one sentence four times in a prompt file adds tokens and invites drift between copies.
- Impact: the verbatim parity phrase still appears in both `commands/execute.md` and `commands/verify.md`, which is what the tests pin.
- Open questions: none.
