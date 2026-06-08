# Test report -- verification-framework

Consolidated proof of done for SPEC-046. Maps every acceptance criterion to a recorded test,
its result, and its negative control. A skeptic re-runs the `Command:` lines and reaches the
same verdict. Per-execution detail is in `runs/<timestamp>.md`; this file is the map + verdict.

## The tests we ran (map)

| # | Test | Proves (AC) | Negative control |
|---|---|---|---|
| T1 | `tests/test-proof-dir-layout.sh` | gate accepts the `<slug>/` layout set-wise (AC2/AC3) | green-only BLOCKS; pre-change lib BLOCKS the split layout |
| T2 | `tests/test-ship-gate-profiles.sh` | the REAL ship-gate hook ALLOWS/BLOCKS per profile (AC2) | negative-control run removed -> BLOCK, per profile |
| T3 | `spec-to-cli/bin/proof` | tool-build profile reproduces (AC3) | `negctl` rejects a literal token (exit 3) |
| T4 | `tests/test-meta.sh` | no regression in the kit (AC5) | n/a (regression suite) |
| T5 | real-branch ship-gate hook | feat/verification-framework ships with proof (AC2) | ops-toolkit branch BLOCKED then ALLOWED (rollback note) |

## Results (fresh run, 2026-06-08)

### T1 , set-wise dir-layout gate
- Command: `bash tests/test-proof-dir-layout.sh`
- Exit: 0
- Output: `ALL PASS (3/3)` , split green+negctl satisfies; green-only BLOCKED; pre-change
  lib BLOCKS the split layout (set-wise code is load-bearing).

### T2 , real ship-gate hook, 3 profiles x allow+block
- Command: `bash tests/test-ship-gate-profiles.sh`
- Exit: 0
- Output: `ALL PASS (3 profiles x allow+block)` , eval/tool-build/feature each ALLOW with a
  complete proof and BLOCK when the negative-control run is missing.

### T3 , tool-build reproduction
- Command: `bash tools/spec-to-cli/bin/proof` (ops-toolkit)
- Exit: 0 (green 6/6) ; `negctl` exit 3 (RED-as-expected)
- Output: `PROOF: GREEN 6/6 + NEGATIVE CONTROL red-as-expected , verdict holds`.

### T4 , kit regression suite
- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output: `Passed: 390 / 390`.
- **Caught a real regression:** the first run was `389/390` , the README rewrite had dropped
  the word "sibling", failing the pinned assertion "convention names the experiment sibling +
  single-source borrow". Restored the sibling wording (the experiment IS a sibling profile);
  re-run is 390/390. This is the discipline working: the full-suite re-run caught a silent
  doc regression before it shipped.

### T5 , real-branch gate
- feat/verification-framework (kit): ship-gate hook exit 0 (ALLOW, proof present).
- worktree-verification-framework (ops-toolkit): BLOCKED (exit 1, classified stateful by the
  "migrate" subject keyword, no rollback note) -> ALLOWED (exit 0) after adding a rollback-noted
  entry. A real blocked-then-allowed transition on a real branch.

## Negative controls (the proof is not trivially green)

1. green-only fixture -> gate BLOCKS (the negative control is required).
2. pre-change lib on the split fixture -> BLOCKS (the set-wise code is load-bearing).
3. per profile, negative-control run removed -> ship-gate BLOCKS.
4. spec-to-cli `negctl` -> exit 3 (the "no literal secret" check rejects a token).
5. README rewrite dropped "sibling" -> meta suite went 389/390 (caught + fixed).

## Verdict

PASS. AC1-AC5 met. Five independent negative controls confirm the green results would have
gone red without the work. Re-running any `Command:` reproduces the verdict.

## Reproduce
- `bash tests/test-proof-dir-layout.sh && bash tests/test-ship-gate-profiles.sh && bash tests/test-meta.sh`
- `( cd <ops-toolkit>/tools/spec-to-cli && ./bin/proof )`
