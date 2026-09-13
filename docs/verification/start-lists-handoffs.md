# Proof of done: kit:start lists open handoff files

`_meta/handoffs/*.md` and `.claude/handoffs/*.md` had no reader: they piled up until an
operator manually audited each one's Next section against reality. `lib/session/handoffs.sh
list [--repo DIR] [--days N]` scans both locations (skipping `done/`/`_archive/`) and prints
one line per file, oldest first, with the first excerpt under a `## Next`/`Next step`/`Open`
heading, plus a trailing count line. `commands/start.md`'s always-show state list now cites it
next to the goal-drafts bullet.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash lib/session/tests/test-handoffs.sh` | 0 | PASS 9/9 (golden path, excerpt, no-Next fallback, count, done/ exclusion, `--days` filter, empty-repo honest-zero, unknown-subcommand usage error) |
| 2 | `bash lib/registry/feature-registry.sh generate /tmp/features-check.md` then diff against `docs/FEATURES.md` | 0 | NO DIFF (this change touches no `commands/agents/skills/hooks` feature row; `lib/*.sh` is outside the generator's scan set) |
| 3 | `KIT_CONFIG_OPERATOR=$(mktemp -d) bash tests/run-all.sh` | 1* | 140/140 suites that ran are green; `test-orchestrate-wavefront` hit the 300s per-suite ceiling under load from two other concurrent full-suite runs on this machine, which is a runner-ceiling fact, not an assertion failure per run-all's own message |
| 4 | `bash tests/test-orchestrate-wavefront.sh` (standalone, no contention) | 0 | PASS, every assertion green |

\* run-all.sh's own exit for that run was 1 (a `TIMED OUT` name), piped through `tail -100` for
capture, which reports its own exit (0) and silently discards run-all's real code. Row 4
re-runs the flagged suite standalone to settle it directly: green outside the contention.

## Negative control

`bash lib/gate/negctl.sh <root> "bash lib/session/tests/test-handoffs.sh" "<mutate>"`, mutate
dropped the `-not -path '*/done/*' -not -path '*/_archive/*'` exclusion from the `find` call in
`lib/session/handoffs.sh`.

```
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Mutation: drop the done/_archive exclusion from the find call
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The decoy fixture (`_meta/handoffs/done/decoy.md`) leaked into the listing under the
mutation, failing both the count assertion and the decoy-absent assertion.

## Reproduce

```bash
bash lib/session/tests/test-handoffs.sh
bash lib/session/handoffs.sh list --repo /path/to/repo
bash lib/session/handoffs.sh list --repo /path/to/repo --days 14
```
