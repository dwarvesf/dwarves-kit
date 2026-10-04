# Spec: master green

Generated: 2026-10-04
Status: VALIDATED (design: obvious, one data file regenerated; no validation fan-out run)
Lane: full (`hooks/` and `lib/` are hard paths for the sub-goal; the shipped diff is one data file under `lib/adopt/`)
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 01. The goal listed five suites red on a master export measured on 2026-10-01 and asked for every red suite to pass on a clean export of the branch head.

## Problem

A list of five red suites went stale. The goal named `test-gate-opt-out`, `test-gate-validate-round` C12, `test-config-registry` AC10, `test-install-contract` and `test-research-arch-contract` row 7. Later merges (#875, #886, #887, #901) fixed them. Re-measured on master 144c2279, all five exit 0.

The re-measure found one suite that is red for a real reason: `tests/test-adopt.sh` assertion "known list complete against git log". `lib/adopt/agents-known.sha256` must hold the sha256 of every committed `AGENTS.md` version, so `adopt` can tell an unmodified old kit copy from an operator edit. Three `AGENTS.md` edits (#890, #892, #894) landed without regenerating the list. The test is the only guard, and CI runs on demand only, so the gap went unseen.

Two more findings are host or environment effects, not code bugs (see `## Design`).

## Solution

### Approaches considered

1. **Regenerate the list with `lib/adopt/known-hashes.sh`.** The script is the documented producer. One data file changes.
2. **Make the test skip or warn when the list lags.** Hides the very drift the test exists to catch. Rejected by the sub-goal rule: never weaken an assertion to go green.
3. **Add a hook that regenerates the list whenever `AGENTS.md` changes.** Removes the recurrence. Out of scope for a master-green sub-goal and a new moving part; filed as a follow-up in the implementation note.

### Chosen approach + why

Approach 1. The code is right and the data is stale, so the fix is the data. Approach 3 is a real option for the lead to weigh; it is not needed to turn master green.

### Extensibility & boundaries

The list grows by one line per `AGENTS.md` version. It stays correct only while someone regenerates it after each `AGENTS.md` change. This spec does not change that contract.

## Picture

```
 git log -- AGENTS.md          lib/adopt/agents-known.sha256
 ┌──────────────────┐          ┌───────────────────────────┐
 │ every version    │ must be  │ list lacks 3 versions     │  before
 └──────────────────┘ subset   └───────────────────────────┘
          │                                  ▲
          │ lib/adopt/known-hashes.sh        │
          └──────────────────────────────────┘
                     regenerate                                after: list covers all
 tests/test-adopt.sh T5 walks the log, greps each hash in the list, counts misses
```

## Design

### Approaches considered + chosen

See `## Solution`. Chosen: regenerate the list.

### Diagram

See `## Picture`.

### Re-measure result (the decision record)

| Suite | master export (git archive, no .git) | master clone (CI shape, full history) | Verdict |
|---|---|---|---|
| test-gate-opt-out | 0 | 0 | already green, one recorded run, no change |
| test-gate-validate-round | 0 | 0 | already green |
| test-config-registry | 0 | 0 | already green |
| test-install-contract | 0 | 0 | already green |
| test-research-arch-contract | 0 | 0 | already green |
| test-adopt | 1 | 1 | real: stale known-hash list, fixed here |
| test-gauntlet-proof-audit, test-gitattributes-union, test-hooks, test-ledger-durability, test-lint-scattered-ids, test-proof-contract-visual, test-run-all-time | 1 | 0 | environment: a `git archive` export has no `.git`; each suite reads git state (tracked files, `origin/master`, `git status`, a git log). Green on a full-history clone, which is what CI checks out. Not changed. |
| test-codex-hooks | timeout at 300 s | timeout at 300 s | host: the installed `codex` binary hangs on `codex --version` and `codex --help` on this host, and the suite calls it with no time bound. Not changed. |

### ADR link(s)

None. A data regeneration with no design choice to record.

### Boundaries & failure modes

- A shallow clone cannot judge the list; `known-hashes.sh` and the test both refuse or skip there. Unchanged.
- The regenerated file must be a superset of the old one. The diff is three added lines, no removals.

## Technical Design

### Interfaces (I/O contract)

`bash lib/adopt/known-hashes.sh` rewrites `lib/adopt/agents-known.sha256`: one `<sha256> <label>:<commit12>` line per distinct AGENTS.md and pointer-template version, sorted. No interface changes.

### Data model, API, UI, infrastructure changes

Three added lines in `lib/adopt/agents-known.sha256`. Nothing else in the shipped tree changes.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-1: Re-measure the five named suites and the full suite list on a master export and on a full-history clone; classify each red suite. AC: the table in `## Design` exists with a real exit code per cell.

### Phase 2: Core
- [x] TASK-2: Regenerate `lib/adopt/agents-known.sha256`. AC: `bash tests/test-adopt.sh` exits 0 on a full-history clone of the branch head; the diff against the previous list has no removed line.

### Phase 3: Polish
- [x] TASK-3: Implementation note with one root-cause line per red suite; proof of done with a recorded run per suite and a negative control for the fixed suite. AC: `docs/verification/master-green.md` carries a `## Recorded run` section and a negative control block.

## After state

- [x] `bash tests/test-adopt.sh` exits 0 on a full-history clone of the branch head. (Before: exit 1, "3 missing".)
- [x] The five named suites exit 0 on a clean export of the branch head. (Before: already 0.)
- [x] Restoring the old list turns `tests/test-adopt.sh` red again (negative control).

## Acceptance Criteria (global)

- [x] All tasks pass their individual acceptance criteria.
- [x] No assertion deleted or weakened.
- [x] No regressions: the full suite list on a full-history clone of the branch head shows only the host-hang suite `test-codex-hooks`.

## Verification

```bash
bash tests/test-adopt.sh
bash tests/test-gate-opt-out.sh
bash tests/test-gate-validate-round.sh
bash tests/test-config-registry.sh
bash tests/test-install-contract.sh
bash tests/test-research-arch-contract.sh
bash tests/run-all.sh --all
```

## Edge Cases

1. A full-history checkout whose `AGENTS.md` changes again: the list lags again until someone reruns `known-hashes.sh`. Known; recorded as a follow-up.
2. A shallow clone: `test-adopt` prints SKIP for the list check. Unchanged.
3. A `git archive` export: no `.git`, so the list check cannot run and seven more suites that read git state fail by construction. Documented in the re-measure table.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| List lags a new AGENTS.md edit | `test-adopt` "known list complete against git log" | rerun `lib/adopt/known-hashes.sh`, commit the list |
| Host binary hangs inside a suite | per-suite ceiling in `tests/run-all.sh` reports TIMED OUT, not FAIL | fix the host; the runner already labels it as a ceiling, not an assertion |

## Out of Scope

- A hook or CI step that regenerates the list on every `AGENTS.md` change.
- A time bound or a skip for the `codex` loader probe in `tests/test-codex-hooks.sh`. The hang is a host fault today; whether the suite should bound its own probe is the lead's call.
- Making the seven git-reading suites pass on a `.git`-less export. They test git behavior; an export cannot satisfy them.
- Splitting `test-meta` and any speed work (later sub-goals).

## Touches

- lib/adopt/**
- tests/**
- docs/specs/**
- docs/implementation-notes/**
- docs/verification/**

## Decision Log

- DEC-1: regenerate the list, never relax the assertion. The test guards a real contract: a missing version reads as "edited" and is never swapped.
- DEC-2: leave the seven `.git`-dependent suites alone. They are correct; the export is the wrong shape for them. The proof records both shapes.
- DEC-3: report `test-codex-hooks` rather than patch it. The failure is a hung host binary, and a skip would hide a broken host.

## Grounding

- Environment proof: the same four suites (`test-ledger-durability`, `test-lint-scattered-ids`, `test-gauntlet-proof-audit`, `test-gitattributes-union`) exit 0 on the export after `git init` and one commit.
- Re-measure commands and exits: `docs/verification/master-green.md`, `## Recorded run`.
- Missing versions: `bash tests/test-adopt.sh` on a clone of 144c2279 printed `missing from list: e2d9133927bc943a9ae1f21700264f35ff91f895`, `1b449c068821bad13717f01e7ecf09616f517f7e`, `f215bf115f4b83d0897caf29c45b66704de2d9ae`.
- Hang evidence: `timeout 15 codex --version` exits 124 on this host, with or without the sandbox and with a fresh `CODEX_HOME`.

## Test plan

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Known list covers every committed AGENTS.md version | regression | After state 1 | `bash tests/test-adopt.sh` exits 0 on a full-history clone |
| 2 | Five named suites still green | regression | After state 2 | each `bash tests/<suite>.sh` exits 0 on an export |
| 3 | Old list turns the suite red | negative control | After state 3 | copy the saved old list in, `bash tests/test-adopt.sh` exits 1, copy the fixed list back |
| 4 | Full list shows no new red | regression | global AC 3 | `bash tests/run-all.sh --all` on a clone |
