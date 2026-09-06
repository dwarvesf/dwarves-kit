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

## 2026-09-06 The VERSION bump pulled two more surfaces

- Context: the spec named `VERSION` and the changelog only.
- Change: bumped `.claude-plugin/plugin.json` and `tool.toml` to 2.1.0 as well.
- Why: `tests/test-meta.sh` pins all three surfaces against `VERSION` (SPEC-115). Bumping `VERSION` alone turned the suite red.
- Impact: none beyond the version strings.
- Open questions: none.

## 2026-09-06 run-workflow.sh restores side-effect files mid-run

- Context: a background `bash tests/run-workflow.sh` ran while the tree was edited.
- Observation: the runner restored side-effect files and silently reverted two uncommitted edits, so a commit found nothing to stage.
- Impact: the final full-suite run happened in the foreground on a committed tree instead.
- Open questions: worth a note in the testing docs if it bites again.
