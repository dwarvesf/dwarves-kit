# Proof of done: registry-freshness-guard

**Spec:** `docs/specs/SPEC-294-registry-freshness-guard.md`. **Board:** ID-905. **Branch:** `feat/registry-freshness-guard`.

A push whose diff edits an input of `docs/FEATURES.md` and leaves the generated projection stale is
refused by `hooks/ship-gate.sh`, through the same `feature-registry.sh check` verb that
`tests/test-meta.sh` now pins freshness with.

## Green run

| Command | Exit | What it covers |
|---|---|---|
| `bash tests/test-registry-freshness-guard.sh` | 0 | 11 assertions: the `check` verb fresh/stale/`--fix`, and the pre-push arm across block, pass, short-circuit, no-input, escape hatch, consumer repo |
| `bash tests/test-meta.sh` | 0 | 853/853, including the freshness pin now routed through `check` |
| `bash tests/test-config-registry.sh` | 0 | 50/50, the new `DWARVES_KIT_SKIP_REGISTRY_FRESHNESS` row lints clean |
| `bash tests/test-codex-hooks.sh` | 0 | 86/86, the Codex trust command repins the edited hook's content hash |
| `bash tests/run-all.sh --changed` | 0 | 44 suites, all green |

```
ok - check on a fresh projection exits 0
ok - check on a stale projection exits 1
ok - the stale summary names docs/FEATURES.md
ok - check --fix regenerates in place and leaves it fresh
ok - input moved + stale projection -> blocked (exit 2)
ok - the refusal names the regenerate command
ok - input moved + regenerated projection -> pass (exit 0)
ok - diff carries docs/FEATURES.md -> regen skipped, pass (exit 0)
ok - diff touching no input -> not gated (exit 0)
ok - DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1 skips the arm (exit 0)
ok - repo without the generator is not gated (exit 0)
---
PASS=11 FAIL=0
```

```
=== Results ===
Passed: 853 / 853
All meta tests passed.
```

**Verdict: PASS**

## Negative control

Produced by `bash lib/gate/negctl.sh "$PWD" "<test cmd>" "<mutate cmd>"` on a clean tree after the
feature commit. The mutation neuters the arm's input pattern so a changed `tests/test-*.sh` no
longer counts as a FEATURES.md input, which is exactly the incident shape the arm exists to catch.

```
## Negative control (negctl)
Command: bash tests/test-registry-freshness-guard.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's|tests/test-\[^/\]+\\.sh|tests/nomatch-[^/]+\\.sh|' hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## The `run-all --changed` half of the goal

No selection rule was added, and none was needed. `tests/test-meta.sh` line 2 carries

```
# always: the registry pin and structural lints cover every kit artifact
```

which `tests/run-all.sh --changed` reads to force the suite onto every diff regardless of what the
diff names. The run above is the evidence: this branch's diff selected 44 suites and
`test-meta` is among them, reported `ok`. The goal draft's pause-if clause fired, and the scope
shrank to the pre-push arm.

## Reproduce

```bash
cd .claude/worktrees/registry-freshness-guard
bash tests/test-registry-freshness-guard.sh
bash tests/test-meta.sh
bash tests/run-all.sh --changed
bash lib/gate/negctl.sh "$PWD" \
  "bash tests/test-registry-freshness-guard.sh" \
  "sed -i '' 's|tests/test-\[^/\]+\\\\.sh|tests/nomatch-[^/]+\\\\.sh|' hooks/ship-gate.sh"
```

## Not proven

- **A wrong regeneration shipped with the diff.** The arm skips its regeneration when the push also
  carries `docs/FEATURES.md`, so a hand-edited or partially regenerated projection pushed alongside
  an input change passes the gate. `tests/test-meta.sh` catches it in CI, one step later than the
  push. This is the deliberate cost of keeping the ~20s regeneration off the common path.
- **A hand edit to `docs/FEATURES.md` alone.** A push touching only the projection and no input is
  not gated. Same CI backstop.
- **The ~20s regeneration cost under the gate.** Every fixture in
  `tests/test-registry-freshness-guard.sh` copies the generator into a stub repo, so each case
  regenerates a handful of rows in well under a second. The real cost was measured once by hand
  (`22.1s` wall on an M4 Air) and is not asserted anywhere; a regression that made the generator ten
  times slower would show up as a slow push, not a red suite.
- **Behavior on a repo whose `origin/HEAD` resolves to neither `main` nor `master`.** The arm reuses
  the hook's existing `_resolve_base`, unchanged and untested by this branch.
