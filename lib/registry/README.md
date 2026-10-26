# registry

Generates `docs/reference/FEATURES.md`, the feature inventory, from the live tree. It removes the hand-kept feature list and the count strings that drift from it.

**Entry points**
- `lib/registry/feature-registry.sh generate [outfile]`: scan commands, agents, skills, hooks and lib verbs, then write the registry (default `docs/reference/FEATURES.md`). It also syncs the count strings in `README.md` and `docs/reference/architecture.md`.
- `lib/registry/feature-registry.sh check [--fix] [outfile]`: regenerate to a temp file and compare it with the committed registry. `--fix` rewrites a stale file.
- `lib/registry/strip-pure-id-parentheticals.py [--apply] <file>...`: strip parentheticals that hold only ids from living docs. It reports mixed parentheticals and leaves them alone.

A lib verb appears in the registry only when its script carries a `# kit-verb: <name> | <description>` header in its first 40 lines.

**Tests**: `tests/test-registry-verbs.sh`, `tests/test-registry-one-pass.sh`, `tests/test-registry-freshness-guard.sh` and `tests/test-meta.sh` (freshness). Run one with `bash tests/run-all.sh --only registry`. `hooks/ship-gate.sh` runs `check` before a push.

**Spec and docs**: `docs/specs/SPEC-219-feature-registry.md`, `docs/specs/SPEC-294-registry-freshness-guard.md`, `docs/specs/SPEC-396-registry-one-pass.md`. The output is `docs/reference/FEATURES.md`.
