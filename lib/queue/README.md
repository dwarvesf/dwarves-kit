# queue

The overnight launcher and the mega-goal runner. Both are dumb non-LLM drivers: no session carries more than one unit of context, and a box flips only on grounded proof.

**Entry points**
- `bin/queue` forwards to `lib/queue/queue.sh`.
- `queue.sh run <src.tsv>`: open a real interactive `/goal` session per queued mega in a tmux window, watch for `RUNNER_DONE` or `RUNNER_GATED`, journal each outcome, then start the next. Flags: `--dry-run`, `--max-megas N`, `--from-boards`, `--journal`, `--ready`, `--push-only`, `--sanitize-prompt`.
- `queue.sh watch [--apply] [--max N] [--board PATH]`: filter a board's `queued` rows marked `#auto` into the same TSV (`watch-board.sh`). Dry run by default.
- `queue.sh wait <slug> [--timeout S]`: block until a run reaches a terminal journal state.
- `orchestrate.sh next|run|flip|panes|queue|status|orca-reset <megagoal-dir>`: drive a mega-goal as one fresh `claude -p` session per sub-goal. `run` takes `--dry-run`, `--step`, `--stream`, `--capture-tokens`, `--board` and `--backend claude|orca`. There is no `bin/` forwarder.

**Layout**
- `harness.sh`: resolve a CLI-agent vendor to its headless argv.
- `orca-backend.sh`: opt-in Orca backend, sourced only under `--backend orca`.
- `sanitize.sh`: untrusted-input pass for prompts that come from board rows.
- `pane-tail.jq`: control-byte filter for the subagent tail panes.

**Tests**: root `tests/test-queue.sh`, `tests/test-orchestrate*.sh`, `tests/test-harness-*.sh`, `tests/test-runaway-guards.sh`, `tests/test-self-grill-watcher.sh` and `tests/test-subagent-panes.sh`. Run `bash tests/run-all.sh --only queue`, or `--only orchestrate` for the runner.

**Spec and docs**: `docs/specs/SPEC-148-overnight-queue-launcher.md`, `docs/specs/SPEC-370-orca-mega-backend.md`.
