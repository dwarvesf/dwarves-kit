# Proof of done , harness-loop SG-10 (front-door truth + mega close-out)

## Acceptance criteria

| # | Criterion (from `goals/10-front-door-truth.md`) | Met by |
|---|---|---|
| AC1 | README reorganized around the five legs (ADR-0034 decision 3), spanners stated honestly | README.md "five legs" section + mermaid |
| AC2 | Counts truth-matched AND parity-pinned so they cannot drift again | `tests/test-meta.sh` 698/698 |
| AC3 | Stale "v2 roadmap: SessionEnd knowledge capture" bullet struck (it shipped) | grep count = 0 |
| AC4 | `docs/architecture.md` stale "25 commands + 15 agents = 40" headline fixed | now "31 commands + 25 agents = 56 entries" |
| AC5 | `stats digest` folded into the weekly session-intel file as a scorecard section | `lib/session/intel/bin/session-intel` source list |
| AC6 | ONE weekly scheduler + declarative jobs list; per-job plist retired (decision 9) | `deploy/macos/` + `tests/test-kit-weekly.sh` 14/14 |
| AC7 | Mega close-out: RUN_REPORT + 2-3 visual proofs of the delivered surfaces | `_meta/megagoals/harness-loop/RUN_REPORT.md` + `proof/*.png` |

## Implementation

- `README.md`: five-leg narrative + mermaid, module->leg mapping, honest spanners (board, session),
  agent/skill/command tables truth-matched (25 agents, 3 skills, 31 commands).
- `docs/architecture.md`, `docs/MANUAL.md`: headline inventory corrected; MANUAL gains the leg index.
- `tests/test-meta.sh`: parity assertions pin every rendered count to the live file count.
- `deploy/macos/{kit-weekly,kit-weekly.plist.tmpl,jobs.txt,install,README.md}`: ONE weekly
  LaunchAgent + a dispatcher reading a declarative jobs list. BTM rules honored
  (`ProgramArguments[0]` = the launcher's own absolute path; no `.sh` extension).
  `lib/session/intel/deploy/macos/*` (the per-job plist) deleted.
- `tests/test-kit-weekly.sh`: new; covers dispatch, honest-skip on an unknown job, and a negative
  control that the retired per-job plist stays retired.
- `tests/lib/contract-lint.sh`: sweep gains `-I --exclude-dir=__pycache__` (a stray `.pyc` made
  grep emit "Binary file ... matches" INTO the token stream, producing a phantom ORPHAN).

## Confirmation run-table

| Check | Command | Exit: | Result |
|---|---|---|---|
| Parity pins (counts cannot drift) | `bash tests/test-meta.sh` | Exit: 0 | PASS 698/698 |
| One scheduler + jobs list | `bash tests/test-kit-weekly.sh` | Exit: 0 | PASS 14/14 |
| Config drift lint (with the .pyc present) | `bash tests/test-config-registry.sh` | Exit: 0 | PASS 19/19 |
| Learn leg intact after the fold | `bash tests/test-learn-propose.sh` | Exit: 0 | PASS 33/33 |
| Learn leg intact after the fold | `bash tests/test-learn-drain.sh` | Exit: 0 | PASS 23/23 |
| Full CI set (every workflow step) | loop over `.github/workflows/test.yml` steps | Exit: 0 | PASS, no nonzero suite |

## NEGATIVE CONTROL

1. **Parity pin actually falsifies.** The `test-meta.sh` count assertions are keyed to
   `ls agents/*.md | wc -l`; adding an agent file without updating the README table fails the suite
   (this is the mechanism that kills the agents-11-of-25 drift class permanently).
2. **The retired plist stays retired.** `test-kit-weekly.sh` asserts
   `lib/session/intel/deploy/macos/session-intel-weekly.plist.tmpl` does NOT exist; restoring it
   fails the test (ADR-0034 decision 9 is mechanically enforced, not just documented).
3. **Unknown job does not crash the week.** A jobs-list entry naming a missing command logs and
   skips (exit 0); it never aborts the remaining jobs.
4. **Drift lint still catches a real orphan.** `test-config-registry.sh` AC2 plants
   `KIT_TOTALLY_UNREGISTERED_PLANT` and requires exactly 1 orphan flagged , still PASS after the
   binary-exclusion fix, so the fix suppressed the phantom without blinding the lint.

## Reproduce

```bash
cd ~/workspace/tieubao/dwarves-kit
bash tests/test-meta.sh            # 698/698, the parity pins
bash tests/test-kit-weekly.sh      # 14/14, the one scheduler
bash tests/test-config-registry.sh # 19/19, lint + its negative control
open _meta/megagoals/harness-loop/proof/mega-review-dashboard.png
```

Verdict: PASS
