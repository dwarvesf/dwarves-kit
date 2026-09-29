# Spec: validate-round verb for the parallel validation round

Generated: 2026-09-29
Status: APPROVED (lead brief; fresh-context validation pending)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-363-validate-round-verb.md`
References: `commands/spec.md` step 5 (the round rules this verb enforces); `lib/gate/gate-ledger.sh` `outcome()` (the additive-marker pattern and the start/end bracket math to reuse); `lib/stats/src/stats/adapters.py::read_kit_gates` (FIFO pairing of `GATE` lines to `OUTCOME` brackets per phase, the reader the record order must satisfy)

## Problem

`commands/spec.md` step 5 asks the lead to run the parallel validation round's bookkeeping by hand. One round needs `git hash-object -w`, a ledger snapshot, a `git status --porcelain` snapshot, both again after the round, then up to four `gate-ledger.sh` calls in a fixed order with the right `caught=` values. The lead ran this for 6 rounds in one session and slipped twice. The live ledger of SPEC-361 (`## Grounding`) shows both slips:

1. `design-record` was recorded and its bracket closed after round 1, while `Validate` stayed open across 3 rounds. The two gates measured different spans.
2. `Validate ran "APPROVED ..."` was recorded from an interim reviewer block. A later `CORRECTION` line followed. The rid now holds 4 `GATE | validate` lines against 1 `OUTCOME | validate | end` bracket, so the stats FIFO pairs the wrong durations.

The rules are right. The manual procedure is the defect: a mechanical sequence carried in prose.

## Solution

### Approaches considered

1. A `validate-round` verb inside `lib/gate/gate-ledger.sh` with `open`, `close` and `incomplete` sub-verbs (chosen). The verb holds the sequence; the lead still computes the verdict. Tradeoff: one more verb on a large script.
2. A sibling script `lib/spec/validate-round.sh` (rejected). It would re-source the ledger substrate and duplicate `ledger_file`, `append_run_line` and `outcome`. The brief names gate-ledger.sh as the precedent.
3. Keep the prose and add a checklist line to step 5 (rejected). A checklist is what slipped.

### Chosen approach + why

Option 1. The verb reuses `record()`, `outcome()`, `ledger_file()` and `append_run_line()` in the same file. The rejected sibling traded a smaller file for a second copy of the ledger plumbing.

### Extensibility & boundaries

- Load-bearing dimension: the number of rounds per rid. Each round adds 3 to 6 ledger lines. Readers that scan the rid file are linear in its lines, as today.
- Units: `open` (pin + snapshot + brackets), `close` (recheck + records), `incomplete` (stop records). Each reads the rid ledger and appends to it; none holds state outside the ledger.

## Picture

```
lead                                 gate-ledger.sh validate-round                 rid ledger (runs/<rid>.log)
 |                                    |                                              |
 |-- open <rid> <spec> -------------->| rid == branch slug of the spec worktree?     |
 |                                    |-- outcome Validate start ------------------->| OUTCOME validate start
 |                                    |-- outcome design-record start -------------->| OUTCOME design-record start
 |                                    |   pin: git hash-object -w <spec>             |
 |                                    |   snapshot: ledger lines + hash, porcelain   |
 |<-- <token> ------------------------|-- ROUND open token= blob= lines= ... ------->| ROUND open
 |                                    |                                              |
 |   fan out N reviewers, wait for final completions, merge by rule (lead)          |
 |                                    |                                              |
 |-- close <rid> <token> <verdict> .. >| token == last open round?  args consistent? |
 |                                    | recheck blob, ledger, porcelain              |
 |                                    |   drift --> ROUND void why=...; exit 2       |
 |                                    |   second void --> incomplete stop; exit 3    |
 |                                    |-- record Validate ran|skipped -------------->| GATE validate
 |                                    |-- outcome Validate end caught= ------------->| OUTCOME validate end
 |                                    |-- record design-record ran|skipped --------->| GATE design-record
 |                                    |-- outcome design-record end caught= -------->| OUTCOME design-record end
 |<-- blob=<pin> ---------------------|-- ROUND close token= verdict= -------------->| ROUND close
 |                                    |                                              |
 |-- incomplete <rid> <token> <why> ->| Validate skipped "incomplete: <why>",        |
                                        both ends caught=false, ROUND incomplete
```

## Design

**Ordering:** the interface (sub-verbs, arguments, exit codes) first, the `| ROUND |` marker second, the step 5 text last.

### Approaches considered + chosen

See `## Solution`. One design decision is new here: brackets become per round (DEC-B).

### Diagram

See `## Picture` (sequence).

### ADR link(s)

`docs/decisions/0024-gate-ledger-and-ship-enforcement.md` covers the ledger. The `| ROUND |` marker follows the additive-marker convention of `| OUTCOME |`, `| TOKENS |`, `| DEBT |` and `| MUTATION |`: every reader keys on its own marker in field 2 and skips the rest. No new ADR: the marker is additive and reversible.

### Boundaries & failure modes

The verb touches the audit ledger, so see `## Failure modes`. Out of bounds: computing the verdict, counting reviewer replies, judging interim versus final completions, and the round budget. The lead owns all four.

## Technical Design

### Interfaces (I/O contract)

`bash lib/gate/gate-ledger.sh validate-round <sub-verb> ...`

| Sub-verb | Arguments | Writes, in order | Stdout | Exit |
|---|---|---|---|---|
| `open` | `<rid> <spec>` | `OUTCOME validate start`, `OUTCOME design-record start`, `ROUND open` | `<token>` | 0; 1 on state refusal; 64 on bad input |
| `close` | `<rid> <token> <verdict> <critical-count> <warnings> <n-agents> <r6-line> [summary]` | `GATE validate`, `OUTCOME validate end`, `GATE design-record`, `OUTCOME design-record end`, `ROUND close` | `blob=<pin>` | 0; 1 state; 2 void; 3 void with budget spent; 64 bad input |
| `incomplete` | `<rid> <token> <reason>` | `GATE validate skipped "incomplete: <reason>"`, `OUTCOME validate end caught=false`, `OUTCOME design-record end caught=false`, `ROUND incomplete` | none | 0; 1 state; 64 bad input |

Inputs:

- `<spec>`: an existing file with no whitespace in its absolute path. The verb resolves the git toplevel of its directory.
- `<token>`: `<blob>.<epoch>`, printed by `open`. The lead reads the pin as `${token%%.*}`.
- `<verdict>`: `APPROVED` or `NEEDS-REVISION` (one word, no quoting).
- `<critical-count>`, `<warnings>`, `<n-agents>`: non-negative integers; `<n-agents>` at least 1.
- `<r6-line>`: Reviewer 6's line, `design-bearing=<yes|no> pass` or `design-bearing=<yes|no> critical: <finding>`.
- `[summary]`: optional criticals text for NEEDS-REVISION. Default: `<critical-count> critical`.

Consistency checks in `close` (refuse with 64, write nothing):

- `APPROVED` needs `critical-count` 0 and an R6 `pass`.
- `NEEDS-REVISION` needs `critical-count` at least 1.
- An R6 `critical:` needs `NEEDS-REVISION`.

State checks (refuse with 1, write nothing):

- `open`: the rid's last `ROUND` line must not be `open`. The rid must equal `gate-ledger.sh rid` run in the spec's toplevel, which is the step 5 rule "the rid of the branch the spec lives on".
- `close` and `incomplete`: the rid's last `ROUND` line must be `open` and carry this token.

Records written by `close` (the step 5 strings, unchanged):

| Case | GATE validate | validate `caught=` | GATE design-record | design-record `caught=` |
|---|---|---|---|---|
| APPROVED | `ran "APPROVED critical=0 warnings=<K> fresh agents=<N> parallel"` | false | `ran "design-bearing=<x> pass"` | false |
| NEEDS-REVISION, R6 pass | `skipped "NEEDS REVISION: <summary>"` | true | `ran "design-bearing=<x> pass"` | false |
| NEEDS-REVISION, R6 critical | `skipped "NEEDS REVISION: <summary>"` | true | `skipped "critical: <finding>"` | true |

Drift in `close`: the verb compares three things with the `ROUND open` line.

- `blob`: `git hash-object` of the spec file now.
- `ledger`: the rid file has exactly `lines + 1` lines, and `git hash-object --stdin` of its first `lines` lines equals the stored hash. The extra line is the `ROUND open` line itself.
- `porcelain`: `git -C <toplevel> status --porcelain | git hash-object --stdin`.

On any mismatch it appends `ROUND void token=<t> why=<comma list>`. If a `ROUND void` already exists since the rid's last terminal `ROUND` line (`close verdict=APPROVED` or `incomplete`), it also writes the `incomplete` records with reason `restart budget spent` and exits 3. Otherwise it exits 2 and the lead re-runs `open`.

Outputs, the `| ROUND |` marker (one line each, space-separated `k=v`, no value holds a space):

```
<ts> | ROUND | open | token=<t> spec=<abs-path> blob=<sha> lines=<K> ledger=<sha> porcelain=<sha>
<ts> | ROUND | void | token=<t> why=<blob,ledger,porcelain subset>
<ts> | ROUND | close | token=<t> verdict=<APPROVED|NEEDS-REVISION>
<ts> | ROUND | incomplete | token=<t>
```

Invariants:

- Every `close` or `incomplete` writes exactly one `GATE validate` line and one `OUTCOME validate end`. Every `close` writes exactly one `GATE design-record` line and one `OUTCOME design-record end`. The stats FIFO therefore pairs one bracket per round.
- A void writes no `GATE` and no `end` line. The next `open` writes fresh start lines; `outcome()` and the stats reader both take the latest start.
- No reader other than the verb reads `ROUND`. `check`, `progress`, `descent`, `outcome-read`, `history`, `report` and `read_kit_gates` output is byte-identical with or without `ROUND` lines.

### Data model changes

One additive ledger marker, `| ROUND |`, as above.

### API changes

A new gate-ledger verb, `validate-round`, listed in the script header and the usage line.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] T1: `validate_round()` in `lib/gate/gate-ledger.sh` with `open`, `close`, `incomplete`, the dispatch line, the header entry and the usage string. AC: `tests/test-gate-validate-round.sh` cases C1 to C12 pass.
- [ ] T2 (with T1): `tests/test-gate-validate-round.sh`, isolated under a fresh `DWARVES_KIT_LOG_DIR` and a temp git repo. AC: the file runs under `bash tests/run-all.sh --all` by glob, exits 0, and C5 goes red under the negative control below.

### Phase 2: Core

- [ ] T3 (after T1): `commands/spec.md` step 5 points at the verb for the parallel round. The single-pass fallback keeps its manual records and brackets. Every string `tests/test-meta.sh` pins stays; `tests/test-outcome-emit-sweep.sh` stays green because the fallback keeps the literal `gate-ledger.sh outcome <rid> Validate start|end` and `design-record start|end` lines. AC: C13.

### Phase 3: Polish

- [ ] T4 (after T1 to T3): regenerate `docs/FEATURES.md` with `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` if `tests/test-meta.sh` reports it stale. AC: `tests/test-meta.sh` passes in full.

## After state

- [ ] `bash lib/gate/gate-ledger.sh validate-round open <rid> <spec>` prints a `<blob>.<epoch>` token and writes both start brackets. (Today: the verb does not exist; the usage line lists no `validate-round`.)
- [ ] A mid-round spec commit makes `close` exit 2 with `ROUND | void | ... why=blob` and no `GATE | validate` line, checkable by `bash tests/test-gate-validate-round.sh`.
- [ ] `commands/spec.md` step 5 names `validate-round open`, `validate-round close` and `validate-round incomplete`. (Today: step 5 lists `git hash-object -w`, `show <rid>` and `status --porcelain` for the lead to run by hand.)
- [ ] One validation round writes one `GATE validate` line per `OUTCOME validate end`. (Today: SPEC-361's rid holds 4 against 1.)

## Acceptance Criteria (global)

- AC1: `open`, `close` and `incomplete` write exactly the lines and order in `## Technical Design`, and refuse bad input or wrong state with the named exit code and a byte-identical ledger.
- AC2: a spec change, a ledger append or a worktree change during the round voids it (exit 2); a second void in the episode writes the `restart budget spent` stop (exit 3).
- AC3: the existing readers are byte-identical with `ROUND` lines present versus stripped.
- AC4: `commands/spec.md` step 5 uses the verb; every string `tests/test-meta.sh` pins is unchanged; `tests/test-outcome-emit-sweep.sh` and `tests/test-command-emit-sweep.sh` pass.
- AC5: `tests/test-meta.sh` passes in full (baseline 879/879 on `917a2754`).

## Verification

```
bash tests/test-gate-validate-round.sh &&
bash tests/test-gate-outcome.sh &&
bash tests/test-outcome-emit-sweep.sh &&
bash tests/test-command-emit-sweep.sh &&
grep -q 'validate-round open <rid>' commands/spec.md &&
grep -q 'validate-round close <rid>' commands/spec.md &&
grep -q 'validate-round incomplete <rid>' commands/spec.md &&
bash tests/test-meta.sh
```

## Test plan

New file `tests/test-gate-validate-round.sh`. Each case runs under a fresh `DWARVES_KIT_LOG_DIR` and a temp git repo on branch `feat/vr-<case>` holding a committed `docs/specs/SPEC-001-x.md`. "Unchanged" means `cmp` of the ledger before and after.

| Case | Setup | Assert |
|---|---|---|
| C1 open | `open` | exit 0; stdout matches `^[0-9a-f]{40}\.[0-9]+$`; `git cat-file -e <blob>`; last 3 lines are the two start brackets then `ROUND open` |
| C2 close APPROVED | `open`; `close ... APPROVED 0 3 7 "design-bearing=yes pass"` | exit 0; next 5 lines equal the APPROVED row in order; stdout `blob=<pin>`; `outcome-read <rid> validate` says `caught=false` |
| C3 close NEEDS-REVISION, R6 pass | `close ... NEEDS-REVISION 2 1 7 "design-bearing=no pass" "stale fixture"` | `validate skipped NEEDS REVISION: stale fixture`, validate `caught=true`, design-record `ran`, `caught=false` |
| C4 close NEEDS-REVISION, R6 critical | r6 `design-bearing=yes critical: empty Design` | design-record `skipped critical: empty Design`, `caught=true` |
| C5 blob drift (negative control target) | `open`; edit the spec and `git commit -am`; `close` APPROVED | exit 2; last line `ROUND void` with `why=blob`; no `GATE | validate` line |
| C6 ledger drift | `open`; `gate-ledger.sh action <rid> x`; `close` | exit 2; `why=` contains `ledger` |
| C7 porcelain drift | `open`; create an untracked file; `close` | exit 2; `why=` contains `porcelain` |
| C8 budget spent | void once, `open` again, void again | exit 3; `validate skipped incomplete: restart budget spent`; both ends `caught=false`; `ROUND incomplete` |
| C9 restart then pass | void once, `open` again, `close` APPROVED | exit 0; `GATE validate` count equals `OUTCOME validate end` count |
| C10 incomplete | `open`; `incomplete <rid> <t> "reviewer 4 dead"` | `validate skipped incomplete: reviewer 4 dead`; two ends `caught=false`; no `GATE design-record` |
| C11 refusals | stale token; `close` with no open round; `open` over an open round; APPROVED with critical 2; APPROVED with an R6 critical; NEEDS-REVISION with critical 0; r6 line `yes ok`; warnings `x`; rid not the spec branch slug; missing spec | each exits 64 or 1 as specified; ledger unchanged |
| C12 additive equivalence | a ledger with rounds; a copy with `ROUND` lines stripped | `check full`, `progress <rid> full`, `descent <rid> full`, `outcome-read <rid>`, `history` identical across both |
| C13 docs | `commands/spec.md` | the three `validate-round` greps from `## Verification` pass; `tests/test-meta.sh` and both emit sweeps pass |

Negative control: see `## Grounding`, trace 2.

## Edge Cases

1. The lead crashes between `open` and `close`: the round stays open and the next `open` refuses. The lead runs `incomplete <rid> <token> "lead restarted"` (token from the last `ROUND open` line), then `open` again.
2. A rid whose earlier validation ended NEEDS-REVISION without a later APPROVED: a new void counts against the same episode's budget, because only APPROVED or `incomplete` is terminal. This fails closed.
3. The spec is uncommitted at `open`: porcelain holds ` M <spec>`. Drift still works; any further edit changes the blob.
4. `open` in a repo on `main`: `rid` refuses, so `open` refuses with 1.
5. Summary text with a newline: `record()` collapses it through `oneline`.
6. Two reviewer rounds in the same second: impossible for one rid, because `open` refuses over an open round.
7. The lead's own branch differs from the spec's branch: the rid check refuses. This is the step 5 rule about the rid of the branch the spec lives on.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A write fails midway through `close` | Nonzero exit from `append_run_line`; no `ROUND close` line | `set -e` stops the verb; the round stays open; the lead runs `incomplete`, which writes the missing `skipped` line. The partial lines stay, as with any append-only failure today. |
| A reader breaks on the new marker | C12 fails | Readers key on field 2; the marker is additive. |
| Another writer appends to the rid during a round | `ROUND void why=ledger` | Intended. Today the only hook writer is `ship-gate.sh` at push, never mid-round. |
| A forged `ROUND` line via free text | A reason with a newline | All free text goes through `oneline`; the verb writes `ROUND` lines only from validated fields. |
| The verb and step 5 prose drift apart | C13 greps; test-meta pins | Step 5 names the verb; the verb carries no prose of its own. |

## Out of Scope

- Computing the verdict, counting replies, detecting interim notices, or checking `<n-agents>` against the heading count. The lead owns these.
- The round budget (`operator_directed_build: true`). The verb does not count rounds.
- The single-pass fallback. It keeps its manual records and `fresh agent=<id>` form.
- The unpaired `design-record end` that step 5's incomplete stop writes (no matching `GATE design-record` line). The verb keeps step 5's records as they are.
- Rewriting SPEC-361's historical ledger lines.

## Touches

- lib/gate/**
- tests/**
- commands/**
- docs/specs/**
- docs/implementation-notes/**
- docs/FEATURES.md

## Decision Log

- DEC-A: extend `gate-ledger.sh`, no sibling script. Reason: reuse of `record()`, `outcome()` and the ledger plumbing; the brief names the precedent.
- DEC-B: brackets open and close per round, not per validation episode. Reason: the stats reader pairs `GATE` lines to brackets FIFO per phase, and the lead already writes one `GATE validate` line per round. Episode duration is the sum of rounds. Rejected: episode-wide brackets, which produced SPEC-361's 4-to-1 mismatch. This rewords step 5's "so `dur_s` measures the validation".
- DEC-C: round state lives in the rid ledger as `| ROUND |` lines, not a side file. Reason: append-only, auditable, and cleaned up with the ledger. Rejected: a state file under `runs/`, which can go stale apart from the ledger.
- DEC-D: the ledger snapshot is a line count plus a prefix hash. Reason: a hash of the whole file cannot hold its own `ROUND open` line.
- DEC-E: `close` checks verdict consistency (APPROVED needs 0 criticals and an R6 pass). Reason: input validation at the boundary, one `case` each; it computes nothing.
- DEC-F: `open` refuses when the rid is not the spec branch's slug. Reason: step 5 already requires that rid, and a wrong rid silently splits the audit trail.
- DEC-G: the second void writes the `incomplete` stop itself. Reason: the restart budget is part of the order the lead slipped on; the verb sees every void.

## Grounding

Sampled read-only on 2026-09-29 from worktree `validate-round-verb` at `917a2754`.

**1. What one real validation wrote.** `cat ~/.local/state/dwarves-kit/logs/runs/spec-validate-fast.log`, the validation lines of SPEC-361:

```
2026-09-29T11:48:16Z | OUTCOME | validate | start | at=1790682496
2026-09-29T11:48:16Z | OUTCOME | design-record | start | at=1790682496
2026-09-29T11:52:03Z | GATE | design-record | ran | design-bearing=yes pass
2026-09-29T11:52:04Z | OUTCOME | design-record | end | at=1790682724 caught=false dur_s=228
2026-09-29T11:52:04Z | GATE | validate | skipped | NEEDS REVISION round 1: 4 criticals, section cache can carry stale verdicts; ...
2026-09-29T11:55:13Z | GATE | validate | skipped | NEEDS REVISION round 2 (7 parallel reviewers, slowest 72s): ...
2026-09-29T12:00:13Z | GATE | validate | ran | APPROVED critical=0 warnings=22 fresh agents=7 parallel (round 3, operator-directed)
2026-09-29T12:00:13Z | OUTCOME | validate | end | at=1790683213 caught=true dur_s=717
2026-09-29T12:02:59Z | GATE | validate | ran | CORRECTION: R4 final block (after an interim one) raised 1 critical, ...
```

Counts: 4 `GATE | validate` lines against 1 `OUTCOME | validate | end`. `design-record` was closed after round 1 and not re-bracketed for rounds 2 and 3. No `ROUND`-shaped line exists, so nothing records the pin or snapshot the lead took.

**2. How the stats reader pairs them.** `sed -n 149,200p lib/stats/src/stats/adapters.py`: `pending_start[phase] = kv.get("at", "")` on each start (a later start replaces an earlier one), a bracket is appended only on `end`, and each `GATE` line pops `queue.pop(0)`. One bracket per `GATE` line is the only shape that pairs correctly. This grounds DEC-B and the void rule (no `end` on void).

**3. The hash forms.** In the worktree:

```
$ git status --porcelain | git hash-object --stdin
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391      (clean tree = the empty-blob id)
$ git hash-object commands/spec-validate.md
9e4265d1613cf75d719e11310c40589e76c4e01e
$ head -n 4 ~/.local/state/dwarves-kit/logs/runs/spec-validate-fast.log | git hash-object --stdin
53d28f9b0a61bc1b90e880cb076b45dd1d7fa77f
```

`git hash-object` is the one hash tool; no `shasum` versus `sha256sum` split between macOS and Ubuntu CI.

**4. Who else writes a rid ledger mid-round.** `grep -rn 'gate-ledger' hooks`: only `hooks/ship-gate.sh` (at push) and a message string in `hooks/batch-debt-warn.sh`. No hook appends during a validation round, so a ledger void means the lead or a reviewer wrote.

**5. Readers and markers.** `lib/bench/events.py` lines 211 to 226 branch on `START`, `GATE` and `OUTCOME` only; `read_kit_gates` on `GATE`, `OUTCOME` and `TOKENS`; gate-ledger's awk readers on `$2=="GATE"` or `$2=="OUTCOME"`. An unknown `ROUND` marker falls through every branch.

**6. The sweep constraint.** `tests/test-outcome-emit-sweep.sh` requires, for every `gate-ledger.sh record <rid> <phase> ran` in a command file, a literal `gate-ledger.sh outcome <rid> <phase> start` and `end` in the same file. `commands/spec.md` records `Validate ran` and `design-record ran`, so the literal bracket lines must stay (T3 keeps them in the fallback).

**7. Baseline.** `bash tests/test-meta.sh`: `Passed: 879 / 879`. `bash tests/test-outcome-emit-sweep.sh`: `51 / 51`. `bash tests/test-gate-outcome.sh`: `25/25 passed`.

### Negative control, dry trace

- Mutation: in `close`, delete the blob comparison, so drift checks only the ledger and porcelain.
- Fixture: case C5. A temp repo on `feat/vr-c5` with a committed spec. `open` pins blob B1. The test appends a line to the spec and runs `git commit -am`, so the spec blob becomes B2, and porcelain is clean again: its hash equals the one taken at `open`. The test writes nothing to the ledger.
- Code path: `close` passes the state check (last `ROUND` is `open` with this token). The mutated drift check sees ledger lines `K+1` with the same prefix hash, and the same porcelain hash. It finds no drift and writes `GATE validate ran APPROVED ...`, exiting 0.
- Red test: C5 in `tests/test-gate-validate-round.sh` asserts exit 2 and fails on exit 0. Its second assertion, no `GATE | validate` line, also fails.
- Why the commit matters: an uncommitted edit also changes porcelain, which would void the round through the porcelain check and hide the mutation. The commit isolates the blob check.

Not sampled: behavior when `git` is missing from `PATH`. The verb needs git for `rid` already, so it fails at `rid`.

## Open questions

(none)
