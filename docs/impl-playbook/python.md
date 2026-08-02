# Python implementation rules

Distills PEP 8 plus Ruff's current rule catalog, the practical enforced layer PEP 8 prose alone does not capture.

## Style
- 4-space indent. `snake_case` for functions and variables, `PascalCase` for classes, `_leading_underscore` for internal-only names.
- Type hints on every public function signature. Only add hints a type checker actually runs against.
- f-strings for formatting. Never `%`-formatting or `.format()` in new code. Exception: `logging.*()` calls, use lazy `%s`-style args (`logging.info("user=%s", user)`), not an f-string. Ruff's G004 flags f-strings there because they format eagerly even when the log level would suppress the message, and an already-interpolated string can't be parameterized by a log aggregator.

## Structure
- Explicit over implicit: no wildcard imports (`from x import *`), no bare `except:`.
- Flat over nested: prefer early returns and guard clauses over deep `if` nesting.

## Errors
- Catch specific exception types. A bare `except Exception` is only for a genuine top-level boundary or an immediate re-raise.
- Use `raise ... from err` when re-raising inside an `except` block, to preserve the chain.

## Dependency and environment
- `uv` for everything. Never bare `pip`/`venv`/`poetry`.
- Pin dependencies via `uv.lock`. Do not hand-edit version ranges without a reason.

## Tooling
- `ruff check` and `ruff format` before commit. That is the enforced layer; PEP 8 prose is the fallback for what Ruff does not cover.

## Sources
- [PEP 8](https://peps.python.org/pep-0008/)
- [Ruff rules](https://docs.astral.sh/ruff/rules/)

Verified: 2026-08-03.
