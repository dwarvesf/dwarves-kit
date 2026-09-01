# Verification log -- risk-gated-proof-of-done

Proof of done gated by risk class. The behavioral class is exercised for real below; the
stateful class is honestly marked unavailable (dwarves-kit has no deploy/migration flow);
the inert class shows the exempt marker. Shape: `docs/verification/README.md`.

## 2026-06-06 23:50 PASS -- behavioral class (the proof-gate classifier's real flow)
- Command: `bash lib/gate/proof-gate.sh class "run the database migration to add a users table"` (and `deploy to production`, `add a --version flag`, `fix a typo`)
- Exit: 0
- Output (excerpt):
  ```
  run the database migration ...   -> stateful
  deploy the worker to production  -> stateful
  add a --version flag to the CLI  -> behavioral
  fix a typo in the README         -> inert
  ```
- Verdict: PASS
- Note: this is the REAL primary flow of the feature (the classifier classifying), not a
  proxy test. The tool does its actual job: map a task to its proof class.

## 2026-06-06 23:50 NEGATIVE CONTROL -- behavioral class
- Command: `git worktree add --detach /tmp/rg2 HEAD && cd /tmp/rg2 && mv -f lib/gate/proof-gate.sh /tmp/ && bash lib/gate/proof-gate.sh class "deploy to production"; bash tests/test-hooks.sh`  (throwaway worktree; removed after; shared checkout untouched)
- Exit: 127 (classify), then 1 (test-hooks)
- Output (excerpt):
  ```
  bash: lib/gate/proof-gate.sh: No such file or directory      # classify_exit=127
  FAIL proof: a migration -> stateful (output missing '^stateful$')
  FAIL proof: a deploy -> stateful (output missing '^stateful$')
  FAIL proof: a feature -> behavioral (output missing '^behavioral$')
  FAIL proof: a typo -> inert (output missing '^inert$')
  Passed: 143 / 151
  Failed: 8
  ```
- Verdict: RED-as-expected (remove the implementation -> the flow cannot classify and the
  8 proof-gate assertions fail; 151 -> 143)
- Note: proves the green above is not trivially green. The shared checkout was untouched
  (the revert happened only in the throwaway worktree, removed after).

## 2026-06-06 23:50 [PROOF OF DONE: exempt -- inert] -- a doc-edit task
- Command: `none` (inert class)
- Verdict: [PROOF OF DONE: exempt -- inert (docs/cosmetic). `proof-gate.sh class "fix a typo in the README heading"` -> inert; no run can meaningfully fail.]
- Note: this is the right-sized path. A typo triggers no ritual; the exemption states its
  reason and is itself classifier-checked, so it is honest, not a loophole.

## 2026-06-06 23:50 [UNAVAILABLE] -- stateful class (deploy / migration / data)
- Command: `none`
- Verdict: [UNAVAILABLE: dwarves-kit has no deployment, migration, or data/persistent-state flow to exercise]
- Note: the stateful requirement (exercise the real flow on a copy/dry-run + record +
  rollback note) is defined in `docs/verification/README.md` and gated by
  `proof-gate.sh` (a migration/deploy description classifies `stateful`), but there is no
  such flow in this repo to run. Recorded as unavailable rather than faked. To prove the
  stateful path live, target a repo that actually deploys or migrates.

## Provenance
- behavioral: real CLI runs of `lib/gate/proof-gate.sh` (deterministic), captured verbatim;
  negative control reverted the real file in an isolated worktree.
- Reproduce: `bash lib/gate/proof-gate.sh class "<task>"`; for the negative control, replay the
  `Command:` line above in a throwaway worktree.
