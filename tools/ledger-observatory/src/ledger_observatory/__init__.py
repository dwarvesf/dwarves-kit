"""ledger-observatory: a read-only DuckDB lens over the scattered ledgers.

The FILES are canonical; the DuckDB db is a derivable, disposable lens
(delete-and-rematerialize). Nothing here ever writes back to a source ledger.
"""

__version__ = "0.2.0"
