# Proof of done: co-located + table-first proof convention (ADR-0026)

| | |
|---|---|
| **Profile** | feature (convention/docs) |
| **Proof class** | inert (docs-only: ADR + canonical README + implementation-notes) , but regression-checked |
| **Canonical** | this file (dogfoods the new table-first layout) |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | Change is additive: every prior proof shape + the gate markers still validate | PASS | R1, R2 |
| AC2 | Editing the canonical README does not break the meta-pin (prior lesson) | PASS | R1 |
| AC3 | The gate's set-wise + per-file validation is unchanged | PASS | R2, R3 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | ADR-0026 + additive README section blessing co-located `proof-of-done.md` + the table-first layout + work-type dialects |
| Where | `docs/decisions/0026-colocated-table-first-proof.md`, `docs/verification/README.md` |
| How it runs | docs only; no code, no gate change, no marker change |
| Reversibility | revert the docs; no consumer proof is invalidated either way |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 meta | 2026-06-09 | `bash tests/test-meta.sh` | 0 | PASS (390/390) |
| R2 proof layout | 2026-06-09 | `bash tests/test-proof-dir-layout.sh` | 0 | PASS (3/3) |
| R3 ship-gate profiles | 2026-06-09 | `bash tests/test-ship-gate-profiles.sh` | 0 | PASS (6/6) |

## 4. Run detail

### R1 GREEN, meta-pin intact after the README edit
- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output (excerpt): `Passed: 390 / 390 ... All meta tests passed.`
- Verdict: PASS. The additive section did not drop a pinned token (the prior README-edit regression class).

### R2, proof-dir-layout (carries its own NEGATIVE CONTROL)
- Command: `bash tests/test-proof-dir-layout.sh`
- Exit: 0
- Output (excerpt):
  ```
  PASS green-only correctly BLOCKED (negative control is required)
  PASS set-wise-stripped lib BLOCKS the split layout (the set-wise code is load-bearing)
  ```
- Verdict: PASS. The gate's required-negative-control + set-wise behavior are unchanged by this docs change , these are the in-suite negative controls.

### R3, ship-gate profiles (allow + block)
- Command: `bash tests/test-ship-gate-profiles.sh`
- Exit: 0
- Output (excerpt): `PASS [tool-build] negative-control run missing -> ship-gate BLOCKS the push`
- Verdict: PASS. Allow-on-proof and block-on-missing both hold.

## 5. Reproduce

```sh
bash tests/test-meta.sh && bash tests/test-proof-dir-layout.sh && bash tests/test-ship-gate-profiles.sh
```

Note: the change itself is inert (docs); these runs are the regression check that the canonical edit did not move the gate. The gate's RED-when-absent behavior is exercised by R2/R3's in-suite negative controls.
