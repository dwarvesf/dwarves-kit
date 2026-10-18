# Implementation notes -- gate-trust

No spec: the operator brief fixed the two fixes, the key and the test scope. Proof: `docs/verification/gate-trust.md`. These notes record only what the brief left open.

## Decisions

| Decision | Why |
|---|---|
| The ledger verdict is the first words of the existing `review ran "<verdict> ..."` reason; no new field | The shape is already what the three review commands write, and the stats readers key on `findings=`/`rejected=` inside the same reason. A new key would force a migration for no gain. The commands now say the verdict goes first and matches the spec's `### Verdict:` line. |
| New reader `gate-ledger.sh review-verdict <rid>`; ship-rules calls it | One parser for the ledger, in the file that owns the format. `battery` normalizes to the `review` gate, so battery records are read too. |
| A reason that does not start with a verdict is skipped, never clears an earlier verdict | Older runs and tests record `review ran "test"`. Treating those as "no verdict" keeps today's behavior for them. |
| Any difference blocks, and a spec with no verdict counts as different when the ledger has one | This is the brief's rule, and it also catches a deleted `## Review` section. A review that finished always wrote both places. |
| Cross-check shares the `review_verdict` key, off at the merge base | Brief: same key. An opt-out must already sit on the default branch, as before. |
| Lane order `tiny` < `normal` = `bug` = `backfill` < `full` | The special lanes keep today's free movement among themselves. Putting them at `normal`'s rank still closes the `full` -> `bug` shortcut, which would otherwise shed the think/spec/validate gates through the back door. |
| A lane with no rank (custom data lane) is not guarded | The guard cannot order what it does not know; the old rule stands for it. |
| Refusal exits 65 and writes nothing; `--lower` without a reason exits 64 | 65 matches the override verb's "refused for a reason" code; 64 is the usage code. |
| An accepted lowering writes `GATE \| lane-lower \| override \| <from> -> <to>: <reason>` before the `START-AMEND` | Lane telemetry already counts every `GATE ... override` line, so no reader changes. `lane-lower` is not a lane phase, so `check` ignores it. Writing it first keeps the `START-AMEND` the last START line. |
| `record-batch` is guarded by the same path | It amends through `start --amend`, so it inherits the refusal with no code of its own. |
| `--lower` and `--reason` must come before the rid | A flag loop that stops at the first non-flag word keeps rid parsing unchanged. |

## Known limits

- The ledger is append-only text under the kit log root. A writer who skips the verb and appends a raw `START-AMEND` or `review ran` line still wins. Both checks raise the cost; neither signs anything. The README says so.
- A legitimate "Verdict after fixes: SHIP" edit to the spec, without a re-review, now blocks when the ledger holds `FIX THEN SHIP`. The fix is the re-review the command docs already ask for.
