# Implementation notes: orchestrator run-modes (SG-01)

Delta from goal file `goals/01-run-modes.md` (token-optim-v2). The goal pins the contract;
this records only off-spec decisions.

## 2026-06-29 arg parsing rewrite
- Context: `cmd_run` parsed `--dry-run` positionally (`[ "${2:-}" = "--dry-run" ]`). Adding two
  more flags positionally would be brittle.
- Decision: replaced with a flag loop that accepts `--dry-run`, `--step`, `--stream` in any
  order, plus the megagoal dir as the one positional. Unknown `--flag` -> exit 64.
- Why: three opt-in flags now; order-independence is the only sane shape.
- Impact: existing call sites (`run <dir>`, `run <dir> --dry-run`) unchanged.

## 2026-06-29 --step as a stdin gate, not a TTY keypress
- Decision: `--step` pauses after each completed sub-goal and reads ONE line from the
  orchestrator's stdin (free: the prompt goes to `claude` via `< "$pfile"`, not the driver's
  stdin). Empty / `y` / `c` continues; `q` / `n` / `quit` stops cleanly (return 0). EOF (closed
  stdin, no operator) stops cleanly too -- can't get consent, so don't march on.
- Why over a raw keypress: testable without a PTY (pipe `"\n"` / `"q\n"`), and the pi-swarm
  `confirmAction` borrow is a y/n line read, not a single-char raw read.
- Impact: pausing only happens when there IS a next sub-goal (no trailing pause before the
  gate-stop or done).

## 2026-06-29 --stream wires stream-json + tee, opt-in
- Decision: `--stream` invokes `claude -p --output-format stream-json --verbose ... | tee
  <dir>/.orchestrate/<id>.stream.jsonl`. Off by default => byte-identical default invocation
  (kept as a separate branch, not a built-up pipeline, so the no-stream path has no `tee`).
- Why `--verbose`: `claude -p --output-format stream-json` requires it in non-interactive mode.
- Why persist under `.orchestrate/`: the goal's proof wants a captured terminal slice; a file
  next to the megagoal is the lazy durable capture + live tail in one (`tee`). Pipefail (already
  set) keeps the `if ! ... | tee` failure check honest.
- Note: `.orchestrate/` is runtime state; consumers should gitignore it (documented in README).
