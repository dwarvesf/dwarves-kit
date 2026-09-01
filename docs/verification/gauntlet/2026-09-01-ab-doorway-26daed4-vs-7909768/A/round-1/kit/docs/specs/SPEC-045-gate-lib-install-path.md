# Spec: Gate resolves its lib from the install path (consumer-repo enforcement fix)

Generated: 2026-06-08
Status: SHIPPED
Source: maintainer session 2026-06-08 (Han), found while preparing to adopt the proof-of-done gate in consumer repos (ops-toolkit + others). The gate did not actually enforce in any consumer repo.
Prior spec: SPEC-042 (proof of done), SPEC-044 (task-type contracts), ADR-0024/0025 (the gates + ledger).
Lane: full (touches the ship-gate hook + the installer).
This spec's own proof class: behavioral. Proof of done = a recorded run showing the gate BLOCK a behavioral change in a CONSUMER repo (the bug: it currently fails open there) + a negative control.

## Problem

`hooks/ship-gate.sh` resolves its enforcement lib as `PROOF="${CLAUDE_PLUGIN_ROOT:-$ROOT}/lib/gate/proof-ledger.sh"` (and the same `${CLAUDE_PLUGIN_ROOT:-$ROOT}/lib/gate/gate-ledger.sh`). In bash-install mode `CLAUDE_PLUGIN_ROOT` is unset, so it falls back to `$ROOT` = **the repo being pushed**. A consumer repo (ops-toolkit, dfoundation, ...) has no `lib/gate/proof-ledger.sh`, so `[ -f "$PROOF" ]` is false and the gate **fails open**, regardless of whether the repo added `docs/verification/README.md`. Net: the proof-of-done gate only enforces when pushing **dwarves-kit itself**; every consumer repo is unguarded. Worse, `install.sh` deploys only `hooks/` (no `lib/`) to `~/.claude/dwarves-kit/`, so even a stable-path fallback has nothing to point at today.

This blocks SPEC-044's Phase C (adopt in ops-toolkit) and the maintainer's intent to adopt across the active engineering repos.

## Solution

Resolve the lib from the **kit's install location**, not the consumer repo, and make `install.sh` put it there.

1. `hooks/ship-gate.sh`: change both fallbacks from `$ROOT` to the stable install root: `PROOF="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/proof-ledger.sh"` and the same for `gate-ledger.sh`. Plugin mode (`CLAUDE_PLUGIN_ROOT` set, e.g. the maintainer's `--plugin-dir` workflow) is unchanged; bash-install mode now finds the kit's lib for ANY repo being pushed.
2. `install.sh`: deploy `lib/` to `~/.claude/dwarves-kit/lib` (a dir symlink to `$KIT_DIR/lib`, mirroring the hooks step incl. the in-place guard), so repo edits stay live and the gate finds proof-ledger/gate-ledger.
3. `lib/gate/proof-gate.sh`: resolve `PROOF_GATE_DIR` with `pwd -P` (physical path) so when invoked through the symlinked lib, `../docs/verification/task-types.md` still resolves back to the real repo (keeps `contract`'s registry working from the installed path). proof-ledger does not need this (its block decision is self-contained, no registry).

## Scope

In: `hooks/ship-gate.sh` (2 path lines), `install.sh` (lib deploy + matching uninstall cleanup), `lib/gate/proof-gate.sh` (pwd -P), `tests/test-meta.sh` (pin: install materializes `lib/gate/proof-ledger.sh`).

Out: changing the gate's block LOGIC (unchanged, still proof-ledger), the proof classes/types (unchanged), per-consumer-repo adoption itself (that is the follow-on: add `docs/verification/README.md` to each repo). No new dependency.

## Acceptance criteria

1. `hooks/ship-gate.sh` resolves proof-ledger + gate-ledger from `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/`, not `$ROOT/lib/`.
2. `install.sh` into a throwaway `HOME` leaves `$HOME/.claude/dwarves-kit/lib/gate/proof-ledger.sh` resolvable; `--uninstall` removes it.
3. `tests/test-meta.sh` passes and pins (2) (fails if the lib deploy is reverted, the negative control).
4. Proof of done in `docs/verification/SPEC-045.md`: a recorded run where the gate BLOCKS a behavioral diff in a CONSUMER-style repo (real bug repro: before the fix it fails open; after, it blocks) + a negative control.

## Verification

`bash tests/test-meta.sh` (exit 0). Plus the consumer-gate repro recorded in the proof file.

## Validation + ship record (2026-06-08)

Adversarial review via the kit `reviewer` agent (ran from an ops-toolkit session, so `/kit:*` could not target dwarves-kit): verdict **SHIP** (9/10), 0 blockers. Two LOW items, both applied: a `$HOME`-unset fail-open guard in ship-gate, and the `assert_true $?` idiom in the new pin. Verified: idempotent reinstall + `--uninstall` clean, `pwd -P` keeps `contract` resolving, gate block-logic byte-identical to master, test-meta 390/390, test-hooks 164/164. Shipped via merge of the PR to master.
