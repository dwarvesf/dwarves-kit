# Verification -- no-auto-rows

A session no longer creates board rows or staging candidates as a side effect. Wrap step 7b reports an unbuilt candidate as REPORTED. The backlog-stage hook and `reflect propose` write the staging file only with `BACKLOG_STAGE_AUTO=1`.

| Check | Command | Exit | Result |
|---|---|---|---|
| Changed suites | `bash tests/run-all.sh --changed origin/master` | 0 | `run-all: all 55 suites passed, 0 skipped for missing tooling` |
| SessionEnd hook, knob unset | `echo '{"transcript_path":...}' \| bash hooks/backlog-stage.sh` in a scratch repo, forward-intent transcript, live extractor stub | 0 | no `_meta/backlog-staging.md` written |
| SessionStart surface, knob unset | `bash hooks/backlog-stage.sh --surface` with one staged block present | 0 | empty output, no `N backlog candidates staged` line |
| SessionEnd hook, `BACKLOG_STAGE_AUTO=1` | same as row 2 | 0 | `## [staged] fix flaky deploy` written |
| SessionStart surface, opt-in | same as row 3 | 0 | `📋 1 backlog candidate staged in .../_meta/backlog-staging.md.` |
| `reflect propose --retro`, knob unset | `bash lib/reflect/reflect.sh propose --retro RETRO.md --staging S --backlog B` | 0 | block printed, `printed, not staged (BACKLOG_STAGE_AUTO is off)`, no staging file |
| report-lint, REPORTED item | `bash lib/wrap/report-lint.sh r.md` | 0 | clean |
| report-lint, STAGED item | same | 1 | `uses a retired verdict` |
| report-lint, FILED item | same | 1 | `uses a retired verdict` |

## Green run
```
Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Verdict: PASS (55 suites; test-wrap, test-kit-foldin-hooks, test-intake-sweep, test-reflect-propose, test-config-registry, test-meta all ok)
```

## Negative control
```
Command: bash lib/gate/negctl.sh . "bash tests/test-kit-foldin-hooks.sh" "sed -i '' '/BACKLOG_STAGE_AUTO:-}\" in 1|true|yes|on/d' hooks/backlog-stage.sh"
Exit: 1 (under mutation, RED expected)
Verdict: PASS
```
Removing the hook's opt-in gate turns the `row 3-off` cases red. `git checkout HEAD --` restored the file and the suite went green again.

```
Command: bash lib/gate/negctl.sh . "bash tests/test-wrap.sh" "<re-admit STAGED and FILED in report-lint's verdict case>"
Exit: 1 (under mutation, RED expected)
Verdict: PASS
```
Re-admitting the retired verdicts turns the `STAGED`/`FILED` lint cases red. Restored and green again.

## Not proven
- `test-kit-foldin-hooks` row 4i (harvest section, untouched here) failed once under `run-all`'s parallel load and passed serially and on the rerun. It is a timing flake in the harvest detach check.
- The operator's own SessionStart wiring of `--surface` lives in the dotfiles `modify_settings.json`. It now prints nothing until `BACKLOG_STAGE_AUTO=1` is set; that repo was not touched.
- The weekly `kit-retro` job (`bin/reflect propose`) now prints to the kit-weekly log. A consumer who wants it staged sets `BACKLOG_STAGE_AUTO=1` in `~/.config/kit-weekly/env`.
