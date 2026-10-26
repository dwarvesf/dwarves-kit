# decide

Flick answers "pick one of N" questions through a decision API in about half a second. A kit step uses it in place of a 20 to 60 second in-session judgment. It runs in shadow mode only and fails open: every path exits 0 with valid JSON.

**Entry points**
- `lib/decide/flick.sh [decide] < request.json`: print one JSON object with backend, model, latency, mode, answers, error, and counts.
- `lib/decide/flick.sh body < request.json`: print the provider request body that the egress guard lets through. No network, no token. For tests and audits.
- `lib/decide/flick.sh --help`: print the contract.
- `bin/flick` forwards to `lib/decide/flick.sh`. If the engine is missing, it still prints a valid error JSON.

Hooks never call flick. Config is read from the root `kit.toml` only, because the `[decide]` block names a credential source and authorizes egress.

**Tests**: `bash tests/test-flick.sh`. Related: `tests/test-wrap-flick.sh` and `tests/test-bin-forwarders.sh`.

**Spec and docs**: `docs/specs/SPEC-381-flick.md`, `docs/verification/flick.md`.
