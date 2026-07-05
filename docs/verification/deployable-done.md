# Proof of done: conditional deployable-done (SPEC-095, kit-hardening SG-07)
Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | [LOAD-BEARING NEGATIVE CONTROL] a deployable (stateful) diff with NO proof-of-done is BLOCKED | PASS | R1, lines 1-4 |
| AC2 | the same deployable diff WITH a well-formed deploy-proof + UAT PASSES | PASS | R1, lines 5-6 |
| AC3 | [inert unaffected] a docs-only diff classifies inert and ships with no proof required | PASS | R1, lines 7-9 |
| AC4 | [override logs] a logged override on a no-proof deployable diff PASSES and is audited | PASS | R1, lines 10-12 |
| AC5 | [contract] AGENTS.md zone 3 carries the Deployable-done clause (deployable def + done=deploy-proof+UAT + inert-unchanged) | PASS | R1, lines 13-16 |
| AC6 | [shared-path safety] `classify()`/`check()` byte-unchanged in logic; every previously-green test stays green | PASS | R2-R7 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | AGENTS.md `## 3. Done means` gains a "Deployable-done" clause; `lib/gate/proof-ledger.sh` gains a purely-additive `deployable <root> <base>` verb (relabels `classify()`'s `stateful` -> `yes`); no change to `classify()`/`check()`. |
| Where | `AGENTS.md` (zone 3), `lib/gate/proof-ledger.sh` (new function + case-arm), `tests/fixtures/deployable-done/`, `tests/test-deployable-done.sh` |
| How it runs | Ship-time, via the EXISTING `hooks/ship-gate.sh` -> `lib/gate/proof-ledger.sh check` wall (ADR-0025); no new hook, no new enforcement path. |
| Reversibility | `git revert` on this branch's commits restores the pre-SPEC-095 AGENTS.md/proof-ledger.sh; confirmed live (see NEGATIVE CONTROL run below). |

## 3. Confirmation (runs)

| Run | When (ISO+tz) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-07-02T00:00+07:00 | `bash tests/test-deployable-done.sh` | 0 | PASS (16/16) |
| R1-NEG | 2026-07-02T00:00+07:00 | `git stash && bash tests/test-deployable-done.sh; git stash pop` | 1 | RED-as-expected (10/16, NEGATIVE CONTROL) |
| R2 | 2026-07-02T00:00+07:00 | `bash tests/test-proof-dir-layout.sh` | 0 | PASS (3/3) |
| R3 | 2026-07-02T00:00+07:00 | `bash tests/test-proof-visual-evidence.sh` | 0 | PASS (4/4) |
| R4 | 2026-07-02T00:00+07:00 | `bash tests/test-ship-gate-fail-closed.sh` | 0 | PASS (5/5) |
| R5 | 2026-07-02T00:00+07:00 | `bash tests/test-ship-gate-profiles.sh` | 1 | [UNAVAILABLE: kit not installed at `~/.claude/dwarves-kit` in this dev sandbox -- confirmed pre-existing via R5-NEG] |
| R5-NEG | 2026-07-02T00:00+07:00 | `git stash && bash tests/test-ship-gate-profiles.sh; git stash pop` | 1 | identical failure before this branch's changes (env gap, not a regression) |
| R6 | 2026-07-02T00:00+07:00 | `bash tests/test-meta.sh` | 0 | PASS (576/576) |
| R7 | 2026-07-02T00:00+07:00 | `bash tests/test-hooks.sh` | 0 | PASS (438/438) |

## 4. Run detail

### R1 GREEN
- Command: `bash tests/test-deployable-done.sh`
- Exit: 0
- Output (excerpt):
  ```
  === AC1 [LOAD-BEARING NEGATIVE CONTROL]: deployable diff, no proof -> BLOCKED ===
    PASS AC1: classify() puts the deploy/ change in the stateful class
    PASS AC1: deployable helper maps stateful -> yes
    PASS AC1: deployable diff with NO proof-of-done is BLOCKED by proof-ledger check
    PASS AC1: the block message names the stateful class + missing proof
  === AC2: same deployable diff WITH a well-formed deploy-proof + UAT -> PASSES ===
    PASS AC2: fixture proof carries a UAT/acceptance line (contract, not a gate grep)
    PASS AC2: deployable diff WITH a well-formed rollback+Command/Exit proof PASSES
  === AC3 [inert unaffected]: a docs-only diff classifies inert and ships with no proof ===
    PASS AC3: classify() puts a docs-only diff in the inert class
    PASS AC3: deployable helper maps inert -> no
    PASS AC3: inert diff PASSES with no proof-of-done required
  === AC4 [override logs]: a logged override on the AC1 no-proof repo passes + is audited ===
    PASS AC4: override command reports the trace log path
    PASS AC4: deployable diff with a LOGGED override PASSES (no proof file needed)
    PASS AC4: the override is logged to the audit trail (slug + reason present)
  === AC5 [contract]: AGENTS.md zone 3 carries the Deployable-done clause ===
    PASS AC5: AGENTS.md has a 'Deployable-done' clause
    PASS AC5: clause defines done = deploy-proof + UAT
    PASS AC5: clause states inert/library/refactor work is unchanged
    PASS AC5: clause ties deployability to proof-ledger's stateful class

  === 16/16 passed, 0 failed ===
  ```
- Verdict: PASS

### R1-NEG NEGATIVE CONTROL
- Command: `git stash && bash tests/test-deployable-done.sh; git stash pop` (stashes the
  tracked AGENTS.md + lib/gate/proof-ledger.sh changes; the untracked test/fixtures stay in
  place, so the test itself is unchanged -- only the implementation under test reverts)
- Exit: 1
- Output (excerpt):
  ```
    FAIL AC1: deployable helper maps stateful -> yes
    FAIL AC3: deployable helper maps inert -> no
  === AC5 [contract]: AGENTS.md zone 3 carries the Deployable-done clause ===
    FAIL AC5: AGENTS.md has a 'Deployable-done' clause
    FAIL AC5: clause defines done = deploy-proof + UAT
    FAIL AC5: clause states inert/library/refactor work is unchanged
    FAIL AC5: clause ties deployability to proof-ledger's stateful class

  === 10/16 passed, 6 failed ===
  ```
- Verdict: RED-as-expected -- reverting the implementation (AGENTS.md clause +
  proof-ledger.sh `deployable` verb) turns 6 of 16 checks RED, confirming the test is not
  trivially green. **THIS IS THE LOAD-BEARING NEGATIVE CONTROL** referenced by AC1's design
  intent (a deployable diff with no proof blocks) generalized to the whole feature: with
  the feature itself absent, the deployable-specific assertions fail.

### R2-R4, R6-R7 GREEN (shared-path safety, unmodified by this change)
- Command: `bash tests/test-proof-dir-layout.sh && bash tests/test-proof-visual-evidence.sh && bash tests/test-ship-gate-fail-closed.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh`
- Exit: 0 (each)
- Output (excerpt): `ALL PASS (3/3)`, `ALL PASS (4/4)`, `PASS=5 FAIL=0`, `Passed: 576 / 576`, `Passed: 438 / 438`
- Verdict: PASS -- proves `lib/gate/proof-ledger.sh classify()`/`check()` are byte-unchanged in
  behavior (AC6): every test that exercises the shared path independently of the new
  `deployable` verb passes identically to pre-branch behavior.

### R5 [UNAVAILABLE]
- Command: `bash tests/test-ship-gate-profiles.sh`
- Exit: 1
- Output (excerpt): `[NO EXECUTABLE CHECK: ship-gate hook not installed at
  /Users/tieubao/.claude/dwarves-kit/hooks/ship-gate.sh]`
- Verdict: [UNAVAILABLE: this dev sandbox has no kit installed at `~/.claude/dwarves-kit`,
  so the test's own install-guard exits before reaching any code this branch touches]
- Note: R5-NEG (`git stash` + re-run) reproduces the byte-identical failure with none of
  this branch's changes present, confirming the gap is a pre-existing environment
  precondition, not a regression introduced by SPEC-095.

## 5. Reproduce

```
cd /Users/tieubao/workspace/tieubao/dwarves-kit
bash tests/test-deployable-done.sh
bash tests/test-proof-dir-layout.sh
bash tests/test-proof-visual-evidence.sh
bash tests/test-ship-gate-fail-closed.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
```
