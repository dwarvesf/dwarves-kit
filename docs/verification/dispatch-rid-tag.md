# Proof of done: dispatch rid tag

Every Agent/Task dispatch that `commands/execute.md` and `commands/spec.md` instruct now puts `rid=<rid>` in its `description`. Claude Code writes that description into each subagent's `.meta.json`, so a transcript reader can count dispatches and tokens per run.

| Check | Command | Result |
|---|---|---|
| Green run | `bash tests/test-meta.sh` | `Passed: 887 / 887`, `All meta tests passed.` |
| New assertion | `execute.md and spec.md state the rid=<rid> dispatch-description convention` | PASS |
| Negative control | commit cc6039f2, then `git checkout HEAD~1 -- commands/execute.md`, rerun | `Passed: 886 / 887`, FAIL on the new assertion (`expected '0', got '1'`) |
| Restore | `git checkout HEAD -- commands/execute.md`, rerun | `Passed: 887 / 887` |
| Registry freshness | `lib/registry/feature-registry.sh check docs/FEATURES.md` | fresh (the convention example avoids a literal agent name so reference counts do not drift) |

Reproduce: run `bash tests/test-meta.sh` and grep for `rid=<rid>`. The suite takes about 5 minutes.
