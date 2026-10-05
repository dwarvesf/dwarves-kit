# Implementation note: test-affected-precise

Delta from `docs/specs/SPEC-397-test-affected-precise.md` only; the spec carries the design.

## Where the guard lives

`tests/lib/test-affected-replay.sh`, beside `suite-times.sh`, not under `bin/`: it is a maintainer check with no operator surface, so `tests/test-bin-forwarders.sh` and its census are untouched. It is not a forwarder and has no kit-verb header.

## The touched rule had to learn what the selection already did

The first replay over 30 PRs reported 31 MISS on the branch script. All were the replay being looser than the selection, not selection gaps:

- A non-source path inside a longer path (`docs/verification/README.md` for `README.md`, `$TMPDIR_T/render/_meta/BACKLOG.md` for `_meta/BACKLOG.md`) is not a reference. The replay now applies the same longer-path exclusion as `refs_exact`.
- A `# runner:` suite (`tests/test-meta.sh`, `tests/test-wrap.sh`) is expanded to its siblings by the selection, so the replay never requires the runner itself.

After both, master's script and the branch both show 0 MISS, so the column "MISS before" is a real baseline, not an assumption.

## kit.toml: the key's section also picks

A changed key picks suites naming the key and also suites naming its section (`[review]`, `kit_config_get review ...`). A suite that reads a whole section never names each key, so key-only tokens would drop it. A bare dotted form (`section.x`) was rejected: it matches `test.sh` and `gate.sh`. The candidate set is still only the suites naming `kit.toml`, so the rule can only narrow.

The attribution reads the working-tree kit.toml against `git merge-base BASE HEAD`, so committed, staged and unstaged edits land in one diff. A missing merge base, a new or deleted kit.toml, or a diff with no hunk keeps every candidate.

## Not changed

Module rule (`lib/<mod>/*` to `tests/test-<mod>*.sh`), the wrap fan-out, the meta-area picks, non-source full-path matching, the cache key and the runner. The cache key still hashes every source a suite names by basename, so it invalidates a little more than the selection picks; that is safe and was left alone.

## Known gap

A suite that builds a path at runtime (`bash "$DIR/$name"`) names neither the full path nor the basename. Selection and the replay's touched rule are both blind to it; only the module rule or a CI failure catches it.
