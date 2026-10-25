# Proof of done: stats-python-pin

On the macOS runner, `test-bin-forwarders` and `test-stats-no-persist` ran past 300 s. The timeout dump in CI run 40238188383 showed what they waited on: clang and clang++ processes with `-DDUCKDB`, so `uv run --project lib/stats` was compiling DuckDB from source. DuckDB 1.5.4 ships macOS wheels for CPython 3.10 to 3.14 only, so any interpreter outside that range (a newer default `python3`, a free-threaded build) forces a source build. `lib/stats/.python-version` now pins 3.12, so uv resolves the same interpreter on every host and installs the wheel.

## Recorded run

```
Command: bash <check> <kit root>   # fresh UV_PROJECT_ENVIRONMENT, then uv run --project lib/stats python -c 'print version'
Exit: 0
Output:
fresh env resolves Python 3.12
Verdict: PASS
```

```
Command: a fresh copy of lib/stats with the pin, then uv sync --project .
Exit: 0
Output:
Using CPython 3.12.14
Downloading duckdb (14.8MiB)
 + duckdb==1.5.4
real 1.25
Verdict: PASS
```

`bash tests/test-bin-forwarders.sh` and `bash tests/test-stats-no-persist.sh` both exit 0 locally.

## Negative control

Mutation: move `lib/stats/.python-version` aside, run by `lib/gate/negctl.sh` after the commit. The check uses a fresh environment each run, so an old venv cannot mask the result.

- Without the pin: `fresh env resolves Python 3.14`, and the check fails.
- Restore: `git checkout HEAD -- lib/stats/.python-version`, then green again. Exit: 0 (green after restore).

## Rollback

Revert the squash commit. uv then picks whichever interpreter it finds first; on a host whose default has no DuckDB wheel, `bin/stats` compiles DuckDB on first use again.

Verdict: PASS
