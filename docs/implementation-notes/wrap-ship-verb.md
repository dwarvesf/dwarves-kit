# wrap-ship-verb: implementation notes

Spec: `docs/specs/SPEC-416-wrap-ship-verb.md`. Only deltas from the spec.

## Build delta

### Decisions and changes
- A carry path of `.` or with a `.` component is refused (exit 64) along with `..`. `git add -- .` would stage the whole worktree, which is the bare-`--carry` hazard DEC-D removes. The spec's list did not name it.
- The `resume: wrap land <wt>` line prints only when a commit exists and `wrap land` would continue it correctly: after an `override` or `land` refusal. After `branch`, `stage`, `commit`, `carry` and `guard` refusals the worktree is named on the `SHIP:` line instead. A `guard` refusal holds out-of-set files, so a resume to `land` would be wrong; the other four have no commit, so `land` would refuse "no commits ahead".
- `--message-file` and `--body-file` are made absolute before use, so `git -C <wt> commit -F` does not read them relative to the worktree.
- A usage or argument refusal (exit 64) also prints the `SHIP: refused (preflight, exit 64) worktree=none` line, as `land` prints its `LAND:` line on exit 64.
- The AC-12 case sources the wrap modules in a subshell and redefines `cmd_start`; no seam was added to production code.
- The modules-under-test header line of the wrap suites and `tests/lib/wrap-stub.sh` gained `lib/wrap/wrap-ship.sh` (the test-affected cache key).
