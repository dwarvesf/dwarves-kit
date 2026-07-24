# Rendered snapshots (generated, dated, for review only)

One-off renders committed so PR reviewers can open the three surfaces without
running anything. Each is a stateless projection: the committed generators +
data reproduce it byte-equivalently-in-content, so these files are never
edited, only replaced by a freshly dated render if ever refreshed.

| File | Surface | Reproduce |
|---|---|---|
| `scoreboard-2026-07-25.html` | benchmark scoreboard (both smoke-code runs, 12 cells) | `python3 bench.py render <(cat runs/2026-07-25-smoke-code.jsonl runs/2026-07-25-smoke-code-r2.jsonl) --suite suites/smoke-code --html out.html` |
| `run-viewer-2026-07-25.html` | workflow diagram player (5 demo scenarios + the real board-tool session replay) | `python3 viewer.py build --ledger "real session · board-tool (replayed)"=board-tool --out out.html` (plus demo scenarios; needs the host ledger for the real run) |
| `control-plane-report-2026-07-25.html` | control-plane RUN_REPORT (6 real kit-absorptions rids) | `python3 report.py build --rids kit-template-fields,grill-conditioning,kit-emit-sweep,kit-pitch,lane-de-escalation,mega-mirror-sync --overlay ../kit-absorptions.overlay.json --out out.html` |

The real-session renders embed data read from this host's run ledgers
(`~/.local/state/dwarves-kit/logs/runs/`), which is exactly why the snapshot is
committed: a machine without those ledgers can still open the result.
