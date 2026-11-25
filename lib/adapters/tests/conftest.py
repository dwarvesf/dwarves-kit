"""pytest path setup for the adapter tests: core on sys.path, then every adapter directory."""
from __future__ import annotations

import sys
from pathlib import Path

LIB = Path(__file__).resolve().parents[2]
for core in (LIB / "config", LIB / "sync" / "sweep", LIB / "sync"):
    sys.path.insert(0, str(core))
for adapter in sorted((LIB / "adapters").iterdir()):
    if adapter.is_dir() and (adapter / "adapter.tsv").is_file():
        sys.path.append(str(adapter))
