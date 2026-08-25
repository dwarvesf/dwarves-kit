# CI/CD pipeline: the deploy-pipeline formula

Distills the foundation-workers memo publish pipeline (measured 110s to 78s, 2026-08-19) plus the expand/contract migration rule and GitHub's Actions hardening guide. Each pattern earned its place by a real failure or a measured win; the source column names the proof.

## The formula, in build order

1. **Path-filter the trigger.** A run that starts is the most expensive no-op. Filter at the `on:` block so an irrelevant push never boots a runner.
2. **Guard before work.** Fail on missing env vars first (`require_env`). Read secrets capture-first into variables, mask each value, export once. An auth failure then fails in seconds, not after the build.
3. **Gate sub-deploys on the push range.** In a monorepo, diff `event.before..sha` against each deployable's paths plus its deps. Skip the deploy whose inputs did not change. Every uncertain answer (force push, missing base sha, manual dispatch) must fall back to deploying. The skip can then only ever be a correct no-op.
4. **Order generators as a staged DAG, parallel inside each stage.** Write the dependency reason as a comment on the stage list. An unstated dependency becomes a silent ENOENT that ships bad output (the directory-tree bug shipped for weeks).
5. **Carry caches on the runner, not the cloud.** On a self-hosted runner, a persistent local dir for the compiler cache and the package store beats a cloud-cache tarball round trip (~40s saved per run).
6. **Parallelize the deploy tail.** Independent jobs (static assets, object storage, data plane) run as background jobs with collected exit codes. The tail costs max(job) instead of sum(job).
7. **Migrations apply before code deploys.** Fail-closed code that needs a new table must never reach production before the table exists. Expand/contract is the general form.
8. **Write deltas, not snapshots.** Hash-gate data-plane writes (seed only changed rows). Content-hash asset uploads come free from the platform (wrangler manifests); do not rebuild that layer.
9. **Retry only idempotent network calls.** Three attempts with backoff on puts and deploys. Never retry a step whose repeat changes state.
10. **Sweep hazards by property, not by name.** Oversize files get dropped by a size test. A filename list rots on the next addition.

## Cross-cutting rules

- **The script is runner-agnostic.** Every knob is an env var. No CI expressions inside the script. Any machine with the toolchain can run it by hand, which is also how you debug it.
- **Heuristic guards fail open, correctness guards fail closed.** A "previous run was green" check proceeds when the API errors. A migrations check never does.
- **Under `set -euo pipefail`, a `grep` with no matches kills the pipeline it sits in.** Wrap classification greps as `{ grep ... || true; }`. This exact bug failed six reaper runs before its message could print.
- **Cleanup jobs race their producers.** A close-triggered reaper can run while the preview job it cleans up after is still uploading. Design the periodic sweep as the recovery path, and make raced orphans inert (no crons, no bindings) so the race costs nothing.
- **`gh pr merge --auto` merges the head armed at that moment.** Commits pushed after arming orphan silently. Verify landed changes by content in `origin/main`, not by PR state.

## Sources

- `foundation-workers/docs/verification/memo-deploy-dag.md` and `preview-cron-guard.md` (the measured runs, the negative controls, the reaper race evidence)
- `foundation-workers/apps/memo/scripts/build-and-deploy.sh` (the reference implementation of 1, 2, 5, 6, 7, 8, 9, 10)
- [ParallelChange / expand-contract (Martin Fowler site)](https://martinfowler.com/bliki/ParallelChange.html)
- [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions) (untrusted input via env vars, least-privilege permissions)

Verified: 2026-08-19.
