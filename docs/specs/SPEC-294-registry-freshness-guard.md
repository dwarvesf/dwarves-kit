# SPEC-294: a push that edits a FEATURES.md input without regenerating is refused

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Board:** ID-905. **Proof:** `docs/verification/registry-freshness-guard.md`.

## Problem

`docs/FEATURES.md` is a generated projection of `lib/registry/feature-registry.sh`. Its inputs are
the whole feature surface: `commands/*.md`, `agents/*.md`, `skills/*/SKILL.md`, `hooks/*.sh`,
`hooks/hooks.json`, `settings.json`, plus `tests/test-*.sh` and `docs/specs/SPEC-*.md`, which the
generator token-greps to fill the Specs and Tests columns.

That last pair is the trap. Adding a test file moves rows for every feature the file names, and an
author adding a test has no reason to think about a docs projection. PR #663 added
`tests/test-gitattributes-union.sh`, which moved the `/kit:docs` row's Tests column. Nobody
regenerated. `tests/test-meta.sh` went red on master, and every PR merge commit inherited that red
until PR #665 regenerated the file by hand.

The pin caught the drift. It caught it after the merge, which is the wrong side of the push.

## Solution

`lib/registry/feature-registry.sh check [--fix] [file]` already exists: it regenerates to a temp
file, byte-diffs against the committed copy, prints the diff, and exits 1 on drift. The verb was
built for hand use and nothing calls it. This spec wires it to the two places that decide whether
the drift reaches master.

**1. A pre-push arm in `hooks/ship-gate.sh`.** The hook already carries a doc-projection gate that
fires on a diff touching a projection surface. A sibling arm fires on a diff that touches a
FEATURES.md input, calls `check`, and exits 2 with the regenerate command when the projection has
drifted.

**2. `tests/test-meta.sh` calls `check`** instead of rebuilding the same regenerate-and-diff by
hand, so the pin and the gate can never disagree about what fresh means.

### The short-circuit

The regen costs about 20 seconds. Running it on every input-touching push would put it on most
pushes this repo sees, so the arm skips when the pushed diff **also carries `docs/FEATURES.md`**.
An author who regenerated is not the failure mode this gate exists for, and whether they
regenerated *correctly* is what `tests/test-meta.sh` pins in CI. The expensive path runs only on
the exact shape of the incident: an input moved, the projection did not.

### Scope and escape

Kit repo only, by file existence: the arm needs `lib/registry/feature-registry.sh` and
`docs/FEATURES.md` to both be present under the pushed repo's root, which no consumer repo has.
`DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1` skips it, matching the doc-projection arm's own hatch.
Separate names, because the two arms guard different files and an operator silencing one has no
reason to silence the other.

### Not built: a `run-all --changed` selection rule

The goal draft's pause-if clause fires. `tests/test-meta.sh` already carries the
`# always: the registry pin and structural lints cover every kit artifact` marker, which
`tests/run-all.sh --changed` reads to force the suite onto every diff regardless of what the diff
names. The freshness pin already runs on a diff touching only `tests/*.sh`. No rule to add; the
scope shrinks to the pre-push arm.

## Acceptance criteria

| Criterion | Check |
|---|---|
| `check` exits 0 and says fresh on a current projection | test-registry-freshness-guard case 1 |
| `check` exits 1 and names the drifted file on a stale projection | case 2 |
| `check --fix` regenerates in place and exits 0 | case 3 |
| A push touching an input with a stale projection is refused (exit 2) | case 4 |
| The refusal message names the regenerate command | case 5 |
| A push touching an input with a fresh projection passes (exit 0) | case 6 |
| A push that also carries `docs/FEATURES.md` skips the regen, even when stale | case 7 |
| A push touching no input is never gated | case 8 |
| `DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1` skips the arm | case 9 |
| A repo with no `feature-registry.sh` is never gated | case 10 |
| `tests/test-meta.sh` pins freshness through the `check` verb | test-meta: "docs/FEATURES.md is fresh (check verb)" |
| `run-all --changed` selects test-meta for a `tests/*.sh`-only diff | the `# always:` marker, asserted in the proof |

## Verification

```bash
bash tests/test-registry-freshness-guard.sh
bash tests/test-meta.sh
bash tests/test-config-registry.sh
bash tests/run-all.sh --changed
```
