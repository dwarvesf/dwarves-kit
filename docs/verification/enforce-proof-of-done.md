# Verification log -- enforce-proof-of-done

The proof-of-done ship gate (ADR-0025) proves itself with its own discipline: a green run,
a negative control, and a LIVE demonstration of the wall actually blocking then passing.
Shape: `docs/verification/README.md`.

## 2026-06-07 00:11 PASS -- enforce-proof-of-done [suites]
- Command: `bash tests/test-meta.sh && bash tests/test-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  meta: All meta tests passed.   (365)
  hooks: All tests passed.       (164)
  ```
- Verdict: PASS

## 2026-06-07 00:11 NEGATIVE CONTROL -- enforce-proof-of-done
- Command: `git worktree add --detach /tmp/eg HEAD && cd /tmp/eg && mv -f lib/gate/proof-ledger.sh /tmp/ && git checkout master -- hooks/ship-gate.sh && bash tests/test-hooks.sh`  (throwaway worktree; removed after; shared checkout untouched)
- Exit: 1
- Output (excerpt):
  ```
  FAIL ledger: stateful, [UNAVAILABLE] -> PASS (got 127)
  FAIL ledger: pre-override -> BLOCK (got 127)
  FAIL ledger: logged override -> PASS (got 127)
  FAIL ship-gate hook: behavioral + no proof + no spec -> BLOCK (exit 2) (got 0)
  Passed: 153 / 164
  Failed: 11
  ```
- Verdict: RED-as-expected (remove the gate -> 11 tests fail; the wall stops blocking,
  exit 2 -> 0)
- Note: proves the gate's blocking behavior depends on the implementation, not on luck.

## 2026-06-07 00:11 LIVE GATE -- the wall actually blocks, then passes
A real run of `hooks/ship-gate.sh` on a ship action (`git push`) in an opted-in, SPEC-LESS
repo (proves the wall AND the bridge: no spec, still gated):
- behavioral change, NO proof entry  -> hook exit **2** (BLOCKED), message names the class
  and exactly what proof is missing.
- add a green + NEGATIVE CONTROL entry -> hook exit **0** (PASS).
- a repo that never adopted the convention -> hook exit **0** (fail open, never gated).
- logged override turns a block into a pass and leaves a trace (proven in test-hooks:
  `pre-override -> BLOCK (exit 1)`, `logged override -> PASS (exit 0)`).

## 2026-06-07 00:30 DOGFOOD -- the gate run against its own branch
The real gate, run from the repo's own cwd against `feat/verify-by-execution` (the branch
that built it), over the whole session's work:
- `proof-ledger.sh classify . <merge-base master>` -> **behavioral**.
- the branch added 4 proof-of-done logs (`verify-by-execution.md`, `proof-of-done.md`,
  `risk-gated-proof-of-done.md`, `enforce-proof-of-done.md`), one per workflow shipped
  this session.
- `proof-ledger.sh check` -> **exit 0 (PASS)**; the real `ship-gate.sh` hook on a `git
  push` -> **exit 0 (PASS)**. Our own work clears its own wall.
- Dogfood negative control: in a throwaway worktree, remove the 4 proof logs (keep the
  convention README so it stays opted-in) -> `check` **exit 1**, hook **exit 2 (BLOCKED:
  proof of done. behavioral change ...)**. Worktree removed, shared checkout clean.
- Conclusion: the branch passes ONLY because the proofs exist; strip them and the gate
  blocks the very session that built it. Not a rubber stamp.

## Provenance
- The gate is the kit's own dogfood: this very branch is behavioral, so it carries this
  proof-of-done entry (green + negative control), which is exactly what the gate requires.
- Reproduce: `bash tests/test-hooks.sh` (the proof-ledger + ship-gate-hook cases); for the
  live wall, feed `{"tool_input":{"command":"git push"}}` to `hooks/ship-gate.sh` in an
  opted-in repo with and without a `docs/verification/<slug>.md` proof.
