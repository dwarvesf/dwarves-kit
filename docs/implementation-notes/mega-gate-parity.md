# Implementation notes -- mega-gate-parity

Deltas from `docs/specs/SPEC-399-mega-gate-parity.md`. Nothing here repeats what the spec already states.

## The helper owns the base resolver and the switch reader too

- Context: the spec names the two rules. Both need the remote-default base and the `[gate]` switch, which lived as private functions in the hook.
- Decision/Change: `ship_rules_resolve_base`, `ship_rules_merge_base` and `ship_rules_switch_on` moved into the helper. The hook keeps one-line wrappers (`_resolve_base`, `_gate_on`) for its other callers.
- Why: a copy of the base logic in the mega gate could drift from the hook's, the failure this change removes.
- Impact: the hook resolves the helper from the install location, else from its own checkout, because `tests/test-hooks.sh` (6c) runs it with a plugin root that has no `lib/`. It exits 0 only when neither holds.

## The hard-path fixture is `.github/`, not `kit.toml`

- Context: the brief named `kit.toml` as a hard path. `lane-classify.sh floor` treats only a project `.kit.toml` (plus `[lanes] extra_hard_paths`) as the kit-config kind; the kit's own hooks/ and lib/ paths are not built in.
- Decision/Change: the test fixture touches `.github/workflows/ci.yml` (kind `ci`).
- Why: it needs no extra config and exercises the same floor code path.
- Impact: none on the helper; the floor test is path-kind agnostic.

## Log lines and the outcome marker stay in the hook

- Context: the mega gate is decision-only.
- Decision/Change: the helper logs only under `SHIP_RULES_LOG=1`; the hook sets it. The `outcome ship end caught=true` ledger write stays in the hook, after the helper returns 2.
- Why: the mega gate must not write `ship-gate.log` or an OUTCOME bracket it never opened.
- Impact: the order of the log line and the outcome write changed (helper log, then outcome); both are audit-only.

## The mega gate's ledger check passes `KIT_PROJECT_ROOT` through the helper

- Context: the hook ran `check <lane>` with `KIT_PROJECT_ROOT=<repo>`; `gate` did not, so a project `.kit.toml` lane override applied only when the cwd was the repo root.
- Decision/Change: `ship_rules_ledger_check <root> <lane> <rid> <ledger>` sets it. The hook and `gate` both call it.
- Why: the same class of seam this change removes; one caller-independent resolver.
- Impact: with no repo or no helper, `gate` still runs the bare check.

## A broken helper blocks; lanes and the lane_gates switch read at the merge base

- Context: a security review found that `source ship-rules.sh || exit 0` opened every gate, including the proof and plain ledger checks master enforced without the helper. It also found the lane check and the `lane_gates` switch read the PR head.
- Decision/Change: the hook and `gate` block (exit 2 and 1) when the helper fails to load and a kit lib/ exists; the hook exits 0 only with no kit lib/ at all. `KIT_LANE_PROJECT_AT=<rev>` makes `lane_resolve` read the project layer from the `.kit.toml` committed at `<rev>`, and `_lane_fp` keys the check cache on that blob. `ship_rules_ledger_check` takes the merge base; `_gate_on lane_gates` takes it too.
- Why: a PR must not switch off its own gates or rewrite its own lanes (the floor already read at the merge base). No existing test encoded head-read behavior.
- Impact: a project `.kit.toml` lane override takes effect at ship only once it is on the default branch. The `proof_of_done` switch is still read from the head; left for a separate change.
