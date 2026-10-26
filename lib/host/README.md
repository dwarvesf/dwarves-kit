# host

Warns when the host is too loaded for a heavy run. It only warns. It never reroutes a job and never blocks one.

**Entry points**
- `lib/host/load-warn.sh [<what>]`: print one line to stderr when the 1-minute load average is over the threshold. `<what>` names the heavy run in the line. Always exits 0. An unreadable load or a non-numeric threshold prints nothing.
- `lib/host/load-warn.sh --over`: silent. Exit 0 when the load is over the threshold, 1 when it is not or cannot be read. `bin/test-affected` uses it to halve its job count.

The threshold is `KIT_LOAD_WARN` from the environment, else `[test].load_warn` in `kit.toml`, else 16. `KIT_LOAD_STUB=<number>` replaces the real load average for tests.

**Tests**: `bash tests/test-host-load-warn.sh`. Callers are covered by `tests/test-test-affected-parallel.sh` and `tests/test-run-all-times.sh`.
