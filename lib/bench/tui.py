#!/usr/bin/env python3
"""MOVED: the TUI is a forge product now (forge repo: cli/forge-tui).

The kit keeps the data plane in events.py (protocol, ledger adapters,
conformance overlay); every frontend, including the forge TUI, consumes that.
"""
import sys

print("The TUI moved to the forge repo: cli/forge-tui (design-guideline skin).\n"
      "Data plane lives here in lib/bench/events.py.", file=sys.stderr)
sys.exit(1)
