# SPEC-185: root-slim (thin root stubs + bulk-in-docs for WORKFLOW/MANUAL/CHANGELOG)

Status: SHIPPED (code + tests)
Lane: full
Backlog: harness-ops sub-goal 12 (`_meta/megagoals/harness-ops/goals/12-root-slim.md`)
Branch: fix/harness-ops-12-root-slim

## Problem

Three root files overwhelm a newcomer landing on the repo: `WORKFLOW.md` (1266 ln),
`MANUAL.md` (589 ln), `CHANGELOG.md` (549 ln) -- 2584 lines combined, all sitting at
root before `README.md` even gets a look-in. But these are not pure prose: `WORKFLOW.md`
is parsed at RUNTIME by the gate machinery (`lib/gate/dispatch-gate.sh`,
`lib/gate/gate-ledger.sh`, the `orchestrate.sh` no-orphan lint), `MANUAL.md` is parsed by
`tests/test-meta.sh` / `tests/test-meta-agent.sh` (agent-roster cross-ref), and
`CHANGELOG.md` is read/prepended by `commands/ship.md`, `commands/kit-health.md`, and
`commands/docs.md`. A naive move breaks all of that; a naive no-op leaves the root
unwelcoming. This spec slims the root without breaking the parsers.

## Design

**Per file: thin root stub (intro + pointer) + bulk moved to `docs/<name>.md`, verbatim
content otherwise unchanged.**

| File | Bulk path | Root stub keeps |
|---|---|---|
| `WORKFLOW.md` | `docs/WORKFLOW.md` | Title, the blockquote intro (agent-facing contract framing), `## Required reading` (one paragraph), pointer to `docs/WORKFLOW.md` |
| `MANUAL.md` | `docs/MANUAL.md` | Title, one-paragraph intro, pointer to `docs/MANUAL.md` |
| `CHANGELOG.md` | `docs/CHANGELOG.md` | Title, one-line convention note, current version number, pointer to `docs/CHANGELOG.md` |

**Reader repoint, by class:**

1. **Runtime parsers of WORKFLOW.md's lane×phase matrix / gate sections** --
   `lib/gate/dispatch-gate.sh:31` and `lib/gate/gate-ledger.sh:40` change their default
   `WORKFLOW` variable from `$KIT_ROOT/WORKFLOW.md` to `$KIT_ROOT/docs/WORKFLOW.md`. The
   `DISPATCH_GATE_WORKFLOW` / `GATE_LEDGER_WORKFLOW` env overrides are unchanged (still
   name whichever file the caller wants).
2. **The no-orphan corpus scan** -- `lib/queue/orchestrate.sh:1600` corpus list
   (`commands/`, `lib/`, `AGENTS.md`, `WORKFLOW.md`) adds `docs/WORKFLOW.md` (agent
   dispatch refs that live in the moved sections must still count).
3. **`install.sh` docs-copy (CRITICAL, the gap the goal calls out):** `install.sh` today
   copies only `AGENTS.md` + `WORKFLOW.md` (the CONTRACT loop at ~:302 compat-symlink,
   ~:413 real-install copy) to the install location, because those are the only two
   files anything reads FROM an arbitrary `$KIT_ROOT` at runtime. Since the gate matrix
   now lives in `docs/WORKFLOW.md`, that file must ship the same way or every installed
   consumer's stub points at a file that was never copied (404). Both `install.sh`
   branches gain a `docs/WORKFLOW.md` step alongside the existing `WORKFLOW.md` step:
   compat mode symlinks it (`ln -sfn "$KIT_DIR/docs/WORKFLOW.md" "$CLAUDE_DIR/dwarves-kit/docs/WORKFLOW.md"`,
   `mkdir -p` the docs dir first), the real-install branch copies it into the CONTRACT
   loop (same managed/stamp bookkeeping, one more filename: `docs/WORKFLOW.md`).
   `MANUAL.md` and `CHANGELOG.md` do **not** need an install-copy fix: nothing reads
   them from an installed `$KIT_ROOT` today (`test-meta.sh` / `commands/ship.md` etc. all
   run against the dev checkout, which ships `docs/` in full via git, not via
   `install.sh`'s selective copy).
4. **Test files reading WORKFLOW.md/MANUAL.md content directly** repoint their
   `$KIT_DIR/WORKFLOW.md` (or `MANUAL.md`) variable to `$KIT_DIR/docs/WORKFLOW.md` (or
   `docs/MANUAL.md`): `tests/test-advisor.sh`, `tests/test-command-emit-sweep.sh`,
   `tests/test-design-record.sh`, `tests/test-docs-wiring.sh`, `tests/test-every-step-review.sh`,
   `tests/test-gate-vocab-recording.sh`, `tests/test-kri-wiring.sh`,
   `tests/test-lane-deescalate.sh`, `tests/test-meta.sh` (both the WORKFLOW.md content
   assertions and the MANUAL.md roster-sync block), `tests/test-meta-agent.sh`,
   `tests/test-understanding-wiring.sh`. `tests/test-adopt.sh`, `tests/test-install-compat.sh`,
   `tests/test-install-contract.sh`, `tests/test-hooks.sh` assert on the STUB's mere
   existence/symlink-ness at root, unchanged (they never grep its content).
5. **`commands/*.md` CHANGELOG readers/writers** -- `commands/ship.md`,
   `commands/kit-health.md`, `commands/docs.md` repoint the file they check/prepend from
   `CHANGELOG.md` to `docs/CHANGELOG.md`.
6. **`commands/draft-agent.md` prose** -- the roster-sync instruction ("add a row to
   `MANUAL.md`'s agent table") repoints to `docs/MANUAL.md`.
7. **`lib/adopt.sh`** -- the generated pointer text (`~72-83`, told to consumers of
   `/kit:adopt`) already says "read `$KIT_ROOT/WORKFLOW.md` for the lanes and the gate at
   each phase boundary"; unchanged (the root stub still exists at that path and forwards
   the reader to `docs/WORKFLOW.md`, so the pointer stays true without editing this
   block -- kept OUT of scope per the sub-goal's concurrency note: sub-goal 06 owns
   `adopt.sh`'s seed/settings-wiring region and this file's WORKFLOW-pointer block is the
   only hunk this PR touches, and here it needs no edit at all).
8. **Prose-only mentions in `README.md` / `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md`**
   that name a section heading which moved (e.g. `WORKFLOW.md "## Gate ledger and ship
   enforcement"`) are left pointing at the plain filename (`WORKFLOW.md`, `MANUAL.md`,
   `CHANGELOG.md`) -- the root stub is a real, permanent forwarding file, not a redirect
   that disappears, so "see WORKFLOW.md's such-and-such section" remains true one hop
   later via the stub's pointer. No edits needed to these four files; verified by the
   prose-dangling grep (only checks for a reference to the OLD flat path with no
   forwarding stub in existence, not for whether a mentioned section lives one hop away).

**Stub contract (all three files):** title unchanged, a 1-3 line intro unchanged in
spirit, then a bolded one-line pointer: `**Full content:** [`docs/<name>.md`](docs/<name>.md)`.
No content is deleted, only relocated; `git mv` + `sed`-split preserves history on the
bulk file, the stub is a new small file.

## Test plan

1. Full suite green (`bash tests/test-meta.sh`, `test-advisor.sh`,
   `test-command-emit-sweep.sh`, `test-design-record.sh`, `test-docs-wiring.sh`,
   `test-every-step-review.sh`, `test-gate-vocab-recording.sh`, `test-kri-wiring.sh`,
   `test-lane-deescalate.sh`, `test-meta-agent.sh`, `test-understanding-wiring.sh`,
   `test-adopt.sh`, `test-install-compat.sh`, `test-install-contract.sh`, `test-hooks.sh`).
2. New installed-copy test: run `install.sh` into a temp `$KIT_ROOT`, assert
   `docs/WORKFLOW.md` exists at the install location and `gate-ledger.sh` run against
   that installed root resolves the lane matrix (not a 404 / empty parse).
3. Per-file negative control: point a reader at the OLD flat path
   (`$KIT_ROOT/WORKFLOW.md` for the matrix, `$KIT_DIR/MANUAL.md` for the roster,
   `CHANGELOG.md` for the Unreleased-section check) and confirm it now FAILS (empty
   match / stub-only content), proving the repoint is load-bearing, not cosmetic.
4. `commands/*.md` prose-dangling grep: confirm no remaining root-flat-path reference in
   `commands/*.md` for the three files' BULK content class (the class the goal calls out
   as invisible to the test suite).
