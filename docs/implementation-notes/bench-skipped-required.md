# Delta: bench skipped required gate

- Only `events.py` derives `run_end`. `report.py` and `dashboard.py` score conformance with `pass`/`override` already, so a skipped required gate never counted there. No change needed.
- Required means the lane plan level contains `required`, read from `expected_plan()` (`gate-ledger.sh plan`). No lane table was re-declared.
- `run_end` now fails on `missed`, `unknown`, or `skip` for a required gate. Light gates may skip; `override` stays satisfied.
- Open: the conformance tile (`N/M required gates present`) and the `run_end` verdict now agree, since both treat skip as not present.
