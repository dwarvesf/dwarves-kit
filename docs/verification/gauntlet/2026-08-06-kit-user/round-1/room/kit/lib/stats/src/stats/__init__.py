"""stats: a read-only, stateless projection over the kit ledger + source ledgers.

The FILES (the append-only ledger + the source stores) are canonical. `stats` materializes
an in-memory DuckDB lens per invocation, runs the query, and persists NOTHING (SPEC-182):
delete its output (there is none) and re-run and you get the same answer from the log.
Nothing here ever writes back to a source ledger.
"""

__version__ = "0.3.0"
