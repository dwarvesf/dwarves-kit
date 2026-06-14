# Proof of Done: cc-intel

**Feature:** weekly read-only intelligence digest (observe + sweep + synthesis + repeat-detect).
**Date:** 2026-06-15 · **Lane:** normal · **Host:** Hans-Air-M4 (macOS 26.5) · **Mega-goal:** cc-elevation-r2 sub-goal 06 (folds #3 sweeps + #4 synthesis + #5 repeat-detect)

Deterministic (fixtures + stubbed observe/sweep + `CC_INTEL_DATE`), so the smoke is the proof. The live weekly plist load is a deploy check (runbook).

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `run` writes one dated digest with all 4 sections | sub-goal Done |
| A2 | observe/sweep are shelled out + degrade to `_unavailable_` when they fail | quality bar |
| A3 | synthesis flags a normalized duplicate concept (ledger + GLOSSARY) | #4 |
| A4 | synthesis stays silent on distinct items (no false merge) | negative control |
| A5 | repeat-detect flags a bash 3-gram repeated >= N | #5 |
| A6 | repeat-detect stays silent with no repeats (no false proposal) | negative control |
| A7 | Never writes durable homes (proposals only) | propose-don't-dispose |
| A8 | Weekly plist is BTM-friendly (ProgramArguments[0] = bare launcher) | repo plist rule |

## Implementation

| Piece | What | Where |
|---|---|---|
| Digest | shell cc-observe + repo-sweep, append synthesis + repeat, write dated file | `cmd_run()` |
| Synthesis | normalize (punct -> space) concept names from ledger rows + GLOSSARY headings; group; flag >1 | `synthesis()` |
| Repeat | bash-command 3-grams across recent transcripts; flag >= min | `repeat_detect()` |
| Schedule | LaunchAgent, weekly Mon 09:00, bare-name launcher | `deploy/macos/` |
| Tests | fixtures + stubbed observe/sweep, 6 assertions incl. 2 negative controls | `tests/smoke.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Smoke (all) | `bash tests/smoke.sh` | `smoke: all 6 passed` | PASS |
| synthesis dup (A3) | item 1 | merge candidate incl. same-origin | PASS |
| synthesis clean (A4) | item 2 | no merge candidates | PASS |
| repeat 3-gram (A5) | item 3 | `git fetch => rebase => test` flagged | PASS |
| repeat clean (A6) | item 4 | no repeated sequences | PASS |
| digest full (A1/A2) | item 5 | 4 sections + OBSERVE_STUB/SWEEP_STUB | PASS |
| degrade (A2) | item 6 | `_unavailable_` | PASS |
| plist BTM (A8) | `plutil -lint` + grep ProgramArguments | valid plist, [0] = `cc-intel-weekly` launcher | PASS |

## Run detail

```
$ bash tools/cc-intel/tests/smoke.sh | tail -1
smoke: all 6 passed

$ plutil -lint tools/cc-intel/deploy/macos/cc-intel-weekly.plist
tools/cc-intel/deploy/macos/cc-intel-weekly.plist: OK

$ python3 bin/cc-intel synthesis --ledger <fixture> --glossaries <fixture>
- merge candidate: Same Origin Policy (ledger); same-origin-policy (ledger); Same-Origin Policy (web/GLOSSARY.md)
```

## Negative control

- **synthesis**: a distinct-item ledger yields `(no merge candidates)` (A4); **repeat**: no-repeat transcripts yield `(no repeated sequences)` (A6). If grouping/threshold were broken, these would false-fire.
- **proposals-only**: `cmd_run` writes only the digest file; ledger/GLOSSARY fixtures are read-only opens and unchanged after a run. A7 holds by construction (no write path to durable homes).

## Deploy verification (not autonomously run)

Loading the weekly LaunchAgent (`launchctl bootstrap` + `kickstart`) schedules a real recurring job on the Air, an infra change left to deploy time (runbook). The on-demand `cc-intel run` is fully tested here. Not loaded autonomously per minimum-infra (do not schedule a recurring job without the operator).

## Reproduce

```bash
cd tools/cc-intel
bash tests/smoke.sh        # -> smoke: all 6 passed
plutil -lint deploy/macos/cc-intel-weekly.plist
```
