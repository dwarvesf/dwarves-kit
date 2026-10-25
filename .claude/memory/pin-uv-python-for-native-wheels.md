---
name: pin-uv-python-for-native-wheels
description: A uv project with a native dependency must pin its Python in .python-version; uv otherwise picks an interpreter with no wheel and compiles the dependency from source for minutes.
metadata:
  type: project
---

`bin/stats` runs `uv run --project lib/stats`, which needs DuckDB. DuckDB publishes wheels for a fixed range of CPython versions. On a host whose first interpreter falls outside that range (a newer Homebrew default, a free-threaded build), uv builds DuckDB from the sdist with clang. On the macOS runner that pushed `test-bin-forwarders` and `test-stats-no-persist` past 300 s. `lib/stats/.python-version` pins 3.12, so every host resolves the same interpreter and installs the wheel in about a second. An existing `.venv` hides the problem, so check with a fresh `UV_PROJECT_ENVIRONMENT`. Bump the pin only once the dependency ships wheels for the new version. Related: [[ubuntu-latest-is-uutils]].
