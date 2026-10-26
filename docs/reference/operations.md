# Operations: testing, CI, scheduler and dependencies

What a maintainer or operator runs around the kit: the test runner, the CI rules, the weekly scheduler, the external tools it expects, and the optional codebase index. Debug mode and hook logs are in [`hooks.md`](hooks.md); recovery steps are in the [troubleshooting section of the manual](../MANUAL.md#troubleshooting-and-recovery).

## Testing

`bash tests/run-all.sh` with no argument runs only the suites the diff touches, plus the always-on tree-wide lints (kit-contract, config-registry, no-personal-paths, no-scattered-ids, boundary-lint), about 1 to 2 minutes on a Mac. `test-meta` (about 200 seconds) joins only when the diff touches a path it reads (`meta_input` in `bin/test-affected`). `--all` is the full glob, 13 to 15 minutes, for CI and the nightly job only: it refuses (exit 64) unless `CI` is set or `KIT_RUN_ALL=1`. `RUN_ALL_JOBS` defaults to `auto` on macOS and `1` on Linux. Single suites still run on their own: `bash tests/test-hooks.sh` covers hook behavior, `bash tests/test-meta.sh` covers structural integrity (manifests, frontmatter, cross-links), `bash tests/run-workflow.sh` walks the CI workflow's steps locally and prints only the red ones.

## CI

`.github/workflows/test.yml` runs on `workflow_dispatch` and on a `v*` tag push, nothing else. A push or a pull request starts no run, and merging a PR waits on no check. Run `gh workflow run test` before cutting a release tag. The local check is what catches a regression:

```
  edit on a branch
       |
       v
  bash tests/run-all.sh ....... diff-scoped suites + the always-on lints
       |                        (about 1-2 min on a Mac)
       v
  commit --> push --> PR --> merge      no CI run fires anywhere on this line
       |
       v
  cutting a release
       |
       +--> gh workflow run test ........ the macOS + Ubuntu matrix, on demand
       +--> git push origin v<x.y.z> .... the same workflow, on the tag
       |
       v
  KIT_RUN_ALL=1 bash tests/run-all.sh --all ... the full glob (13-15 min);
                                  before the tag, never on a commit; without
                                  CI or KIT_RUN_ALL=1 it refuses (exit 64)
```

## Weekly scheduler

The kit ships ONE weekly LaunchAgent: a dispatcher over a declarative jobs list (session-intel digest, `reflect propose`, print-only unless `BACKLOG_STAGE_AUTO=1` is set in `~/.config/kit-weekly/env`; adding a job = one line, never a new plist). Consumer instantiates it: `bash deploy/macos/install`; runbook at [`deploy/macos/README.md`](../../deploy/macos/README.md).

## External dependencies

Install these alongside; the kit does not bundle them.

- [Context Hub](https://github.com/andrewyng/context-hub) - `npm install -g @aisuite/chub`
- [Context7](https://github.com/upstash/context7) - MCP server for library docs
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - AST-level codebase indexing

The required and recommended tools, and the formatters the auto-format hook detects, are listed in [`architecture.md`](architecture.md) "Dependencies".

## Codebase index (opt-in)

If `codebase-memory-mcp` is installed, the
`codebase-index.sh` SessionStart hook keeps the current repo's structural index fresh
in the background (built on the first session in a repo, incremental refresh after),
so `/kit:spec` and `/kit:execute` query the index (`search_code`, `search_graph`,
`get_architecture`, `trace_path`) instead of grepping, cutting orientation cost. With
the tool absent the hook no-ops and the kit greps exactly as before, nothing to
configure and nothing breaks. Enable: put the binary on `PATH`, run
`claude mcp add --scope user codebase-memory -- codebase-memory-mcp`, then re-run
`install.sh`.
