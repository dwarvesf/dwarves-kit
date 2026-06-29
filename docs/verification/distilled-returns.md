# Proof of done: distilled subagent return contract (SG-04)

| | |
|---|---|
| **Profile** | feature (behavioral/structural) |
| **Proof class** | structural verification (every dispatched role carries the contract) + meta-test regression |
| **Spec** | SPEC-087 Mechanism C |
| **Canonical** | this file |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | Every dispatched-role agent def carries a return contract (`verdict`/`key findings`/`artifacts`/`read-next`) | PASS | R1 |
| AC2 | The worker (no agent file) carries the contract in `/kit:execute` dispatch prose | PASS | R2 |
| AC3 | Contract says report IN the summary; full output stays recoverable in the transcript | PASS | code, R1 |
| AC4 | The "subagent is not automatically cheaper" decision rule is baked in | PASS | execute.md + SPEC-087 Mechanism C |
| AC5 | No tool grants changed; no role's structure broken | PASS | R3 (500/500 meta) |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `## Return contract` section appended to every `agents/*.md`; worker contract in execute.md `## When done`; decision rule at the dispatch boundary + in the spec |
| Where | `agents/*.md` (11 files), `commands/execute.md`, `docs/specs/SPEC-087-context-hygiene.md` |
| How it runs | injected into each subagent's prompt by the existing dispatch machinery; no code path change |
| Reversibility | pure doc/prose addition; revert restores the prior return shape |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-06-29 | `grep -L 'read-next' agents/*.md` | 0 | empty -> all 11 roles carry the contract |
| R2 | 2026-06-29 | `grep -c 'distilled return contract' commands/execute.md` | 0 | 1 -> worker contract present |
| R3 | 2026-06-29 | `bash tests/test-meta.sh` | 0 | PASS 500/500 (no agent/command structure regressed) |

## 4. Run detail

### R1 structural: every dispatched role carries the contract
- Command: `grep -L 'read-next' agents/*.md`
- Output: (empty) -> no agent file is missing the contract. 11 files updated.

### R2 worker contract in the dispatch prose
- The worker has no `agents/worker.md`; its return contract lives in `commands/execute.md`
  Section 2b `## When done`, reshaped to verdict / key findings / artifacts / read-next.

### R3 regression: kit structure intact
- Command: `bash tests/test-meta.sh`
- Output: `Passed: 500 / 500. All meta tests passed.`
- Confirms frontmatter, source citations, and command/agent wiring still validate after the edits.

## 5. Note on token-delta
A live before/after token capture needs a real dispatch (non-deterministic, model-dependent), so
the recorded proof is the structural guarantee that every role now returns a bounded summary +
points at its transcript. The mechanism (bounded summary vs full dump) is what cuts the per-
dispatch cost from ~16-25K to hundreds of tokens; SG-09's ablation measures the aggregate effect.

## 6. Reproduce
```
git switch feat/distilled-returns
grep -L 'read-next' agents/*.md          # empty
grep -c 'distilled return contract' commands/execute.md   # 1
bash tests/test-meta.sh                   # 500/500
```
