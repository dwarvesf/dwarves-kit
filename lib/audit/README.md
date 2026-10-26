# audit

The cadence trigger for the audit-loop instances. Before it, an instance nobody remembered never ran. Now `audit due` says which passes are overdue. It starts no daemon, installs no cron, and never runs an instance itself.

**Entry points**
- `lib/audit/audit.sh due`: report each instance with its cadence, last run, age, and whether it is due. Exits 0 even when a pass is due.
- `lib/audit/audit.sh cadences`: print the declared table as `<instance>` and `<days>`, tab separated.
- `lib/audit/audit.sh ran <instance> [note]`: record that a pass just ran. This is the only write path.
- `bin/audit` forwards to `lib/audit/audit.sh`.

The cadence per instance comes from the `## Cadence` table in `docs/patterns/audit-loop.md`. Last-run markers go to the `audit-runs.log` stream of the append-only ledger (`lib/ledger/ledger.sh`). An instance with no marker reads as due.

**Tests**: `bash tests/test-audit-cadence.sh`. `tests/test-bin-forwarders.sh` covers the `bin/audit` forwarder.

**Spec and docs**: `docs/patterns/audit-loop.md`, `docs/specs/SPEC-295-audit-cadence-trigger.md`.
