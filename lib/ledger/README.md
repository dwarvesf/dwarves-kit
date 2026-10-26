# ledger

The kit's one append substrate. It holds the root lookup and the single-line append that the gate, proof, and audit writers share. It removes per-writer copies of that logic.

**Entry points**
- `lib/ledger/ledger.sh append <stream> <text...>`: append one line to `<root>/<stream>`. Newlines collapse to spaces.
- `lib/ledger/ledger.sh read <stream>`: print the stream, empty if absent.
- `lib/ledger/ledger.sh root`: print the resolved ledger root.
- `source lib/ledger/ledger.sh`: gives `ledger_append`, `ledger_read`, and `ledger_root` to a caller. `lib/gate/gate-ledger.sh` and `lib/gate/proof-ledger.sh` do this.

There is no `bin/` forwarder. Callers source the file or run it by path.

The root comes from `lib/telemetry/kit-log-dir.sh`: `KIT_LEDGER_DIR`, then `DWARVES_KIT_LOG_DIR`, then the XDG state default.

**Tests**: no module suite dir. Root suites `tests/test-ledger-substrate.sh` and `tests/test-ledger-durability.sh` cover it. Run `bash tests/run-all.sh --only ledger`.

**Spec and docs**: `docs/specs/SPEC-097-ledger-durability.md` covers durability.
