# Implementation notes: visible LLM egress, waived gates, per-session marker

No spec: a normal-lane fix on three ranked risks from the system design (LLM egress fails silently; two meanings of "debt"; machine-global session marker). This log records the choices the brief left open.

## Choices

- **One shared helper, `lib/telemetry/egress-fail.sh`.** Sourced by the two bash hooks, run as `egress-fail.sh record <source> <reason>` by the Python callers and the skill-curator wrapper. It appends `ts | source | reason` to `egress-failures.log` through `ledger_append` and never fails. `ledger.sh` is sourced in a subshell, because it exits when its resolver is missing and a hook must not die on that.
- **The reader is the same script (`summary [days]`), not `bin/stats egress`.** `bin/stats` goes through `uv run`, which costs a Python start on every `/kit:start`. The summary is one awk pass over a small file. It prints one line, or nothing.
- **What counts as a failed call:** a non-zero exit, a timeout, or output with no non-blank character. A valid `[]` is a healthy "nothing worth keeping", never a failure. The caller keeps its old behaviour either way (`return 0`, exit 0).
- **Source names are the hook names:** `harvest` (also covers the `--lab-log` draft), `backlog-stage`, `skill-review`, `session-audit`, `reflect-propose`.
- **skill-review is ledgered in `lib/skill-curator/lib/reviewer-run.sh`, not in `hooks/skill-review.sh`.** The hook only spawns a detached child; the `claude -p` call and its empty-output branch live in the wrapper. The wrapper falls back to a no-op when `lib/telemetry` is absent, so the tool still runs standalone.
- **The metric is renamed in place, the column is not.** The anomaly key, threshold, title and metric become `waived_gates`, `waived_gates_max`, "Feedback: waived gates over threshold" and `waived_gates=N`. The `kit_runs.gates_ovr` column keeps its name (it is a stored schema). A proposal already staged under the old title no longer dedups against the new one, which is the intended break. Understanding debt stays the `| DEBT |` ledger line and `bin/reflect debt list`; the stats skill now says so and no longer triggers on "my debt".
- **The slop marker is keyed `/tmp/.dwarves-kit-session-start-<session_id>`, fallback `ppid<PPID>`.** `DWARVES_KIT_SESSION_MARKER` still overrides the whole path and skips the sweep. Markers older than 1440 minutes are deleted on every default-path run with `find -H` (`/tmp` is a symlink on macOS). A session that outlives a day loses its baseline once and skips one run.

## Test hygiene

The failure path now writes a ledger file, so every suite that drives a failing model stub pins `KIT_LEDGER_DIR` to its sandbox. The hook parity harness (`tests/lib/hook-parity.sh`) runs hooks under `env -i`; it now passes `KIT_LEDGER_DIR` through when the calling suite exported one, so the parity goldens (which list stray files) stay unchanged.
