# Proof of Done: cc-intel

**Feature:** weekly read-only intelligence digest (observe + sweep + synthesis + repeat-detect).
**Date:** 2026-06-15 · **Lane:** normal · **Host:** dev laptop (macOS 26.5) · **Mega-goal:** cc-elevation-r2 sub-goal 06 (folds #3 sweeps + #4 synthesis + #5 repeat-detect)

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

---

# Proof of Done: repeat-detect noise filter + ranked top-N digest

**Feature:** ID-226 (filter benign idioms out of repeat-detect) + ID-227 (rank + top-N the merge proposals).
**Date:** 2026-06-28 · **Lane:** normal · **Host:** dev laptop (macOS 26.5)

Deterministic (fixtures + `CC_INTEL_DATE`), so the smoke is the proof. Two new assertions added to `tests/smoke.sh` (now 8 total).

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| B1 | repeat-detect drops a benign idiom chain (`git add` -> `git commit` -> `git push`) | ID-226 |
| B2 | repeat-detect still flags a genuine non-benign chain (`make build` -> `make deploy` -> `curl`) | ID-226 negative control |
| B3 | pre-existing genuine chain (`git fetch` -> `git rebase` -> `pnpm test`) is NOT regressed by the filter | regression guard (test [3]) |
| B4 | merge proposals are ranked (higher match count first) | ID-227 |
| B5 | merge proposals are capped at top-10 with a truncation note stating how many were truncated | ID-227 |

## Implementation

| Piece | What | Where |
|---|---|---|
| Benign filter | `BENIGN_IDIOMS` chain whitelist + `BENIGN_SINGLES` navigation set; `_stem()` reduces each command to its verb stem; `_is_benign()` drops matching 3-grams | module top + `repeat_detect()` |
| Ranking | `_score_merge()` keys groups by (match count, exact>fuzzy, oldest ledger-row age); `synthesis()` sorts desc (stable, name-asc within ties) | `synthesis()` |
| Top-N | `_fmt_merges()` shows `MERGE_TOP_N` (=10) and appends `… N more … truncated (showing top 10 of M)` | `_fmt_merges()` |
| Tests | 2 new assertions ([7] benign filter, [8] rank+top-N) with negative controls | `tests/smoke.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Smoke (all) | `bash tests/smoke.sh` | `smoke: all 8 passed` | PASS |
| Benign drop + genuine keep (B1/B2) | item [7] | benign absent, `make build => make deploy => curl localhost` present | PASS |
| No regression (B3) | item [3] | `git fetch => git rebase => pnpm test` still flagged | PASS |
| Rank + top-N + note (B4/B5) | item [8] | 10 candidate lines, top is count-3 group, `3 more … truncated` note | PASS |

## Run detail

```
$ bash tests/smoke.sh | tail -3
[8] synthesis ranks by match count, caps at top-10, notes truncation (ID-227)
  ok: ranked top-10 + truncation note
smoke: all 8 passed

$ python3 bin/cc-intel repeat --transcripts <fixture> --min 3
- x3: `make build => make deploy => curl localhost`
# (the repeated `git add . => git commit -m wip => git push origin` chain is filtered out)

$ python3 bin/cc-intel synthesis --ledger <fixture: 13 dup groups> --glossaries <none>
- merge candidate: Top Concept (ledger); top-concept (ledger); TOP CONCEPT (ledger)
- merge candidate: Concept 01 (ledger); concept-01 (ledger)
- merge candidate: Concept 02 (ledger); concept-02 (ledger)
...
- _… 3 more merge candidate(s) truncated (showing top 10 of 13)._
```

## Negative control

- **Benign filter (B2)**: a genuine non-benign chain in the same fixture is still flagged, so the filter is not a blanket suppressor. Test [3] re-confirms the prior genuine chain is untouched (the whitelist is stem-exact, not a `git*` catch-all).
- **Rank/top-N (B4)**: the count-3 group ("Top Concept") sorts above the count-2 groups, proving the score actually orders; the truncation note's `of 13` proves nothing was silently dropped.

## Reproduce

```bash
cd tools/cc-intel
bash tests/smoke.sh        # -> smoke: all 8 passed
```
