# Test ledger isolation: proof

Five tests wrote fixture rids into the real run ledger (`~/.local/state/dwarves-kit/logs/runs`). Each now exports `DWARVES_KIT_LOG_DIR="$TMP/kitlogs"` right after its existing `trap ... EXIT`.

| Test | Leaked rids | Set LOG_DIR before | Result after fix |
|---|---|---|---|
| tests/test-orchestrate-hardening.sh | sg-* | no | green, no ledger touch |
| tests/test-orchestrate-gate-dispatch.sh | sg-one, sg-two | no | green, no ledger touch |
| tests/test-model-routing.sh | sg-* | no | green, no ledger touch |
| tests/test-turn-cap.sh | turncap-fixture | one call only | green, no ledger touch |
| tests/test-tier4-close.sh | tier4-fixture, tier4-fixture-2 | one call only | green, no ledger touch |

The first three matched the validator's list. The last two were extra: they set the var on a single call, so most runs still leaked.

| Check | Before | After |
|---|---|---|
| runs dir file count | 155 | 155 |
| sg-one.log mtime | unchanged | unchanged |
| tier4-fixture*.log, turncap-fixture.log mtime | unchanged | unchanged |

Negative control: with the export reverted in test-orchestrate-gate-dispatch.sh (`git checkout HEAD~1 -- <file>`), the test still passed but `sg-one.log` mtime moved 1790684503 to 1790694179 and `sg-two.log` to 1790694178 in the real ledger. Files already existed, so none was deleted. The export was then restored.

Note: a whole-dir digest can differ between runs because live sessions write their own logs; compare the fixture files instead.
