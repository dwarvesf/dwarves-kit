# fix/curator-bad-json: delta note

## Cause
The reviewer called `claude -p --bare`. `--bare` reads auth only from `ANTHROPIC_API_KEY` or `apiKeyHelper`, never OAuth or keychain. This host logs in with a subscription, so every call returned an error envelope: `is_error:true`, `result:"Not logged in · Please run /login"`, cost 0, tokens 0. The wrapper saw a non-empty `.result` that was not JSON and ledgered `bad-json`.

## Evidence
- Ledger: 1543 rows, 1541 `bad-json`, 2 `no-output`, 0 `staged`. All rows have cost 0 and tokens 0 (a real haiku call costs about 0.001 to 0.01).
- First `bad-json` 2026-09-08, last 2026-11-09 (still running). `no-output` rows are 2026-10-08.
- Live repro with a synthetic prompt: `--bare` gives the error envelope above, rc 1. Without `--bare`, or with `--safe-mode`, the same prompt returns `is_error:false` and the JSON verdict.

## Changes
- `reviewer-run.sh` and `curate.sh`: `--bare` becomes `--safe-mode` (strips hooks, CLAUDE.md, plugins, MCP; keeps auth).
- `reviewer-run.sh`: an `is_error:true` envelope is ledgered `api-error` and sent to `egress_fail`, never parsed as a verdict.
- Docs in the tool folder name `--safe-mode`. Dated specs under `docs/specs/` are history and keep `--bare`.

## Decisions and tradeoffs
- `--safe-mode` over dropping the flag: keeps the reentrancy belt (hooks off) and a small context. Cost of a trivial prompt: about 0.001 versus 0.012 without it.
- Not added: an API-key branch that keeps `--bare`. Nothing needs it today.
- `--safe-mode` needs a recent claude CLI. An older CLI would reject the flag and ledger `no-output`, which now shows up in the egress ledger.

## Open
- The curator now spends quota: 20 to 45 reviews a day normally, a burst of 560 rows on one day. Lead decision: `signal_gate` now defaults to true (opt out with `signal_gate = false`), so only sessions with signal markers spend quota. The suites that test the reviewer pipeline on marker-free fixtures export `SKILL_CURATOR_SIGNAL_GATE=false`.
- 1541 old `bad-json` rows stay as written.
