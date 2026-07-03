# Proof of done: docs + wiring (SPEC-120, orchestrate-hardening 05, final)

`WORKFLOW.md` gains a "Mega-goal delegate execution (ADR-0032)" section (two run modes with `/goal`
staying the official outer loop, per-sub-goal model routing, the ledger-under-delegation guarantee,
the mega TIER-4 close, the opt-in multiplexer); `AGENTS.md` zone 1 item 4 points at it. Every claim is
backed by a no-orphan sweep against `lib/orchestrate.sh`/`lib/gate-ledger.sh` live call sites, and an
over-claim (multiplexer described as default-on) is a caught negative control, mirroring the
kit-hardening `c6fbd99` precedent. Executes ADR-0032; docs-last so they reflect the final wired state
of sub-goals 01-04 (all merged to master).

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | WORKFLOW.md carries a "Mega-goal delegate execution" section stating `/goal` stays the official outer loop; AGENTS.md points at it | PASS |
| AC2 | WORKFLOW.md describes per-sub-goal `Model:`/`Effort:` routing | PASS |
| AC3 | WORKFLOW.md names the ledger-under-delegation guarantee: gate/proof by construction, token via stream-to-file, debt split conductor/worker | PASS |
| AC4 | WORKFLOW.md describes the mega TIER-4 close (no-orphan sweep + verifier session + held human gate, never auto-merges) | PASS |
| AC5 | WORKFLOW.md documents the multiplexer as opt-in/off-by-default and does NOT affirmatively describe it as default-on | PASS |
| AC6 | `Model:` -> `--model` routing has a live call site in `lib/orchestrate.sh` | PASS |
| AC7 | Token capture records via `lib/gate-ledger.sh` (`\| TOKENS \|` marker) with a live call site | PASS |
| AC8 | TIER-4 close is actually invoked from the run terminal in `lib/orchestrate.sh` | PASS |
| AC9 | A tmux pane spawns under `MULTIPLEXER=1` with a live call site | PASS |
| AC10 | NEGATIVE CONTROL (load-bearing): a planted over-claim ("the multiplexer is enabled by default for every wave run") is CAUGHT by the sweep | PASS |
| R | Regression: `test-meta.sh` (662/662), `test-hooks.sh` (452/452) | PASS |

## Run table

```
$ bash tests/test-docs-wiring.sh
=== docs-wiring (SPEC-120 AC1-AC10) ===
--- AC1-5: doc-presence (WORKFLOW.md / AGENTS.md carry the required vocabulary) ---
  PASS AC1: WORKFLOW.md exists
  PASS AC1: WORKFLOW.md has a Mega-goal delegate execution section
  PASS AC1: WORKFLOW.md states /goal stays the official outer loop
  PASS AC2: WORKFLOW.md describes per-sub-goal model routing
  PASS AC3: WORKFLOW.md names the ledger-under-delegation guarantee
  PASS AC3: WORKFLOW.md describes token capture as stream-to-file
  PASS AC3: WORKFLOW.md describes the debt-ledger split
  PASS AC4: WORKFLOW.md describes the mega TIER-4 close
  PASS AC4: WORKFLOW.md names the no-orphan sweep as part of the close
  PASS AC4: WORKFLOW.md states the close holds the human gate (never auto-merges)
  PASS AC5: WORKFLOW.md documents the multiplexer
  PASS AC5: WORKFLOW.md states the multiplexer is opt-in/off-by-default
  PASS AC5: WORKFLOW.md does NOT affirmatively describe the multiplexer as default-on
  PASS AC1: AGENTS.md exists
  PASS AC1: AGENTS.md points at the delegate-execution section
--- AC6-9: no-orphan sweep (each documented capability has a LIVE call site) ------
  PASS AC6: Model: -> --model routing fires (live call site in lib/orchestrate.sh)
  PASS AC7: token capture records via gate-ledger.sh (live call site in lib/orchestrate.sh)
  PASS AC7: the TOKENS ledger marker is emitted (live call site in lib/gate-ledger.sh)
  PASS AC8: TIER-4 close is actually invoked from the run terminal (live call site in lib/orchestrate.sh)
  PASS AC9: a pane spawns under MULTIPLEXER=1 (live call site in lib/orchestrate.sh)
--- AC10 [NEGATIVE CONTROL, load-bearing]: an over-claim is CAUGHT by the sweep ---
  PASS AC10: negative-control precondition holds (MULTIPLEXER does NOT default to 1 today)
  PASS AC10: the sweep CATCHES the planted over-claim ('the multiplexer is enabled by default for every wave run')

=== 22/22 passed ===
```

## Negative control (revert -> RED -> restore)

The doc-presence checks (AC1-5) are non-vacuous: reverting `WORKFLOW.md`/`AGENTS.md` to their
pre-sub-goal-05 state (`git checkout 30a7f96 -- WORKFLOW.md AGENTS.md`, the tip of sub-goal 04) turns
11 of them RED while the no-orphan/AC10 checks (which test `lib/orchestrate.sh`/`lib/gate-ledger.sh`,
untouched by this revert) stay green, proving the doc-presence assertions actually read the new prose
rather than passing unconditionally:

```
$ git checkout 30a7f96 -- WORKFLOW.md AGENTS.md
$ bash tests/test-docs-wiring.sh
  FAIL AC1: WORKFLOW.md has a Mega-goal delegate execution section
  FAIL AC1: WORKFLOW.md states /goal stays the official outer loop
  FAIL AC2: WORKFLOW.md describes per-sub-goal model routing
  FAIL AC3: WORKFLOW.md names the ledger-under-delegation guarantee
  FAIL AC3: WORKFLOW.md describes token capture as stream-to-file
  FAIL AC3: WORKFLOW.md describes the debt-ledger split
  FAIL AC4: WORKFLOW.md names the no-orphan sweep as part of the close
  FAIL AC4: WORKFLOW.md states the close holds the human gate (never auto-merges)
  FAIL AC5: WORKFLOW.md documents the multiplexer
  FAIL AC5: WORKFLOW.md states the multiplexer is opt-in/off-by-default
  FAIL AC1: AGENTS.md points at the delegate-execution section
=== 11/22 passed ===

$ git checkout feat/oh-05-docs -- WORKFLOW.md AGENTS.md
$ bash tests/test-docs-wiring.sh
=== 22/22 passed ===
```

The AC10 negative control (planted over-claim caught) is additionally load-bearing on its own: it
proves the sweep mechanism itself would catch a *future* regression where the docs drift ahead of what
`lib/orchestrate.sh` actually dispatches, not just that today's docs happen to match today's code.

## Reproduce

```
cd <dwarves-kit>
bash tests/test-docs-wiring.sh   # 22/22 PASS
bash tests/test-meta.sh          # 662/662 PASS (regression)
bash tests/test-hooks.sh         # 452/452 PASS (regression)
```

## Coverage delta

**Covered:** doc-presence for all 5 ADR-0032 guarantees (AC1-5) · no-orphan live-call-site sweep for
all 4 dispatched capabilities (AC6-9) · the over-claim negative control (AC10) · a real revert-based
negative control on the doc-presence checks themselves.

**Explicitly UNcovered (with reason):** a live `orchestrate.sh run` end-to-end mega-goal execution
exercising all four capabilities in one process , out of scope for a docs sub-goal; each capability's
own live-run proof already exists in `docs/verification/model-routing-enforce.md`,
`token-capture-delegate.md`, `tier4-mega-close.md` (or equivalent), and `multiplexer-panes.md` from
sub-goals 01-04. This proof's job is the docs-to-code wiring, not re-proving the machinery.

## Gate ledger

Lane `normal` (docs-only change, no `lib/`/`hooks/` touch beyond the pre-existing test file):
spec · spec-validate · execute · docs-wiring test · this proof-of-done. `docs/specs/SPEC-120-docs-wiring.md`
carries the full Problem/Solution/Verification; `docs/implementation-notes/SPEC-120-docs-wiring.md`
carries the two deltas from the goal file (spec authored without the research fan-out; AGENTS.md gets
a pointer, not a new zone).
