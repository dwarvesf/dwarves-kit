# Spec: validate-round verb for the parallel validation round

Generated: 2026-09-29
Status: APPROVED (lead brief; round 1 NEEDS REVISION folded, re-validation pending)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-363-validate-round-verb.md`
References: `commands/spec.md` step 5 (the round rules this verb enforces); `lib/gate/gate-ledger.sh` `outcome()` (the additive-marker pattern and the start/end bracket math to reuse); `lib/stats/src/stats/adapters.py::read_kit_gates` (FIFO pairing of `GATE` lines to `OUTCOME` brackets per phase, the reader the record order must satisfy); `hooks/ship-gate.sh` line 224 (the spec glob the approval must bind to); `lib/queue/orchestrate.sh` `_lock` (the mkdir-lock precedent)

## Problem

`commands/spec.md` step 5 asks the lead to run the parallel validation round's bookkeeping by hand. One round needs `git hash-object -w`, a ledger snapshot, a `git status --porcelain` snapshot, both again after the round, then up to four `gate-ledger.sh` calls in a fixed order with the right `caught=` values. `commands/execute.md` (validation preflight) and `commands/wrap.md` (step 10) repeat the same sequence. The lead ran it for 6 rounds in one session and slipped twice. The live ledger of SPEC-361 (`## Grounding`) shows both slips:

1. `design-record` was recorded and its bracket closed after round 1, while `Validate` stayed open across 3 rounds. The two gates measured different spans.
2. `Validate ran "APPROVED ..."` was recorded from an interim reviewer block. A later `CORRECTION` line followed. The rid now holds 4 `GATE | validate` lines against 1 `OUTCOME | validate | end` bracket, so the stats FIFO pairs the wrong durations.

The rules are right. The manual procedure is the defect: a mechanical sequence carried in prose.

## Solution

### Approaches considered

1. A `validate-round` verb inside `lib/gate/gate-ledger.sh` with `open`, `close` and `incomplete` sub-verbs (chosen). The verb holds the sequence; the lead still computes the verdict. Tradeoff: one more verb on a large script.
2. A sibling script `lib/spec/validate-round.sh` (rejected). It would re-source the ledger substrate and duplicate `ledger_file`, `append_run_line` and `outcome`. The brief names gate-ledger.sh as the precedent.
3. Keep the prose and add a checklist line to step 5 (rejected). A checklist is what slipped.

### Chosen approach + why

Option 1. The verb reuses `record()`, `outcome()`, `ledger_file()`, `append_run_line()` and `rid()` in the same file. The rejected sibling traded a smaller file for a second copy of the ledger plumbing.

### Extensibility & boundaries

- Load-bearing dimension: the number of rounds per rid. Each round adds 4 to 8 ledger lines. Readers that scan the rid file are linear in its lines, as today.
- Units: `open` (bind + pin + snapshot + brackets), `close` (recheck + records), `incomplete` (stop records). Each reads the rid ledger and appends to it under a per-rid lock; none holds state outside the ledger.

## Picture

```
lead                                 gate-ledger.sh validate-round                 rid ledger (runs/<rid>.log)
 |                                    |  (every sub-verb holds runs/<rid>.vr-lock)   |
 |-- open <rid> <spec> -------------->| spec == ship-gate's SPEC-*-<rid>.md?        |
 |                                    | rid == branch slug of the spec's toplevel?   |
 |                                    | pin: git hash-object -w <spec>               |
 |                                    | snapshot: porcelain (excludes applied)       |
 |                                    |-- outcome Validate start ------------------->| OUTCOME validate start
 |                                    |-- outcome design-record start -------------->| OUTCOME design-record start
 |<-- <token> ------------------------|-- ROUND open token= spec= blob= porcelain= ->| ROUND open  (= last line)
 |                                    |                                              |
 |   fan out N reviewers, wait for final completions, merge by rule (lead)          |
 |   no spec, worktree or Status edit until close exits 0                           |
 |                                    |                                              |
 |-- close <rid> <token> verdict= ... >| last ROUND is open+token? keys consistent?   |
 |                                    | recheck: last line, blob, porcelain          |
 |                                    |   drift --> ROUND void why=...; exit 2       |
 |                                    |   second void --> incomplete stop; exit 3    |
 |                                    |   forged ran/override --> incomplete; exit 4 |
 |                                    |-- ROUND closing kind=close verdict= -------->| ROUND closing
 |                                    |-- record Validate ran|skipped -------------->| GATE validate
 |                                    |-- outcome Validate end caught= ------------->| OUTCOME validate end
 |                                    |-- record design-record ran|skipped --------->| GATE design-record
 |                                    |-- outcome design-record end caught= -------->| OUTCOME design-record end
 |<-- blob=<pin> ---------------------|-- ROUND close token= verdict= -------------->| ROUND close
 |                                    |                                              |
 |-- incomplete <rid> <token> <why> ->| ROUND closing kind=incomplete, then          |
 |   (or --stale "<why>")             | GATE validate skipped + end caught=false,    |
                                        GATE design-record skipped + end caught=false,
                                        ROUND incomplete
```

## Design

**Ordering:** the interface (sub-verbs, arguments, exit codes) first, the `| ROUND |` marker and its states second, the command text last.

### Approaches considered + chosen

See `## Solution`. One design decision is new here: brackets become per round (DEC-B).

### Diagram

Sequence: see `## Picture`. The round's state machine, read from the rid's last `$2=="ROUND"` line:

```
                   open (exit 0)
   (none | close | incomplete | void) --------------------> OPEN
                                                              |
        close: keys valid, no drift  ----> CLOSING(kind=close) ---> CLOSE verdict=APPROVED         (validation-terminal)
                                                                \--> CLOSE verdict=NEEDS-REVISION  (round-terminal)
        incomplete [--stale]         ----> CLOSING(kind=incomplete) --> INCOMPLETE                 (validation-terminal)
        close: drift, no prior void  ----> VOID (exit 2) --open--> OPEN
        close: drift, prior void     ----> VOID, CLOSING(kind=incomplete) --> INCOMPLETE (exit 3)
        close: forged ran/override   ----> VOID, CLOSING(kind=incomplete) --> INCOMPLETE (exit 4)

   CLOSING with this token + a re-run of the same sub-verb: write only the records missing after
   the CLOSING line, then the final ROUND line (resume after a mid-write failure).
```

Round-terminal lines (`close` with any verdict, `incomplete`) reset the void budget. Validation-terminal lines (`close verdict=APPROVED`, `incomplete`) end one validation. Validation-wide `caught` is "any `OUTCOME validate end caught=true` after the previous validation-terminal `ROUND` line"; `outcome-read` keeps reporting the last round.

### ADR link(s)

`docs/decisions/0024-gate-ledger-and-ship-enforcement.md` covers the ledger. The `| ROUND |` marker follows the additive-marker convention of `| OUTCOME |`, `| TOKENS |`, `| DEBT |` and `| MUTATION |`: every reader keys on its own marker in field 2 and skips the rest. No new ADR: the marker is additive and reversible.

### Boundaries & failure modes

The verb touches the audit ledger, so see `## Failure modes`. Out of bounds: computing the verdict, counting reviewer replies, judging interim versus final completions, and the round budget. The lead owns all four.

## Technical Design

### Interfaces (I/O contract)

`bash lib/gate/gate-ledger.sh validate-round <sub-verb> ...`

| Sub-verb | Arguments | Writes, in order | Stdout | Exit |
|---|---|---|---|---|
| `open` | `<rid> <spec>` | `OUTCOME validate start`, `OUTCOME design-record start`, `ROUND open` | `<token>` | 0; 1 state; 64 bad input |
| `close` | `<rid> <token> verdict=<APPROVED\|NEEDS-REVISION> critical=<n> warnings=<k> agents=<n> r6=<r6-line> [summary=<text>]` | `ROUND closing`, `GATE validate`, `OUTCOME validate end`, `GATE design-record`, `OUTCOME design-record end`, `ROUND close` | `blob=<pin>` | 0; 1 state; 2 void; 3 void with budget spent; 4 forged record; 64 bad input |
| `incomplete` | `<rid> <token> <reason>` or `<rid> --stale <reason>` | `ROUND closing`, `GATE validate skipped "incomplete: <reason>"`, `OUTCOME validate end caught=false`, `GATE design-record skipped "incomplete: <reason>"`, `OUTCOME design-record end caught=false`, `ROUND incomplete` | none | 0; 1 state; 64 bad input |

Inputs:

- `<spec>`: an existing, readable file. Its absolute path holds no whitespace and no `=`. It must equal the first match of ship-gate's glob, `ls <toplevel>/docs/specs/SPEC-*-<rid>.md | head -1` (`hooks/ship-gate.sh` line 224), where `<toplevel>` is the git toplevel of the spec's directory. So the approval lands on the exact file the ship-gate reads.
- `<token>`: `<blob>.<epoch>`, printed by `open`. The lead reads the pin as `${token%%.*}`.
- `close` keys, each exactly once, in any order; an unknown or repeated key is bad input:
  - `verdict=`: `APPROVED` or `NEEDS-REVISION`.
  - `critical=`: the merged CRITICAL count, which includes Reviewer 6's critical when there is one. Non-negative integer.
  - `warnings=`: non-negative integer. `agents=`: integer, at least 1.
  - `r6=`: Reviewer 6's line, `design-bearing=<yes|no> pass` or `design-bearing=<yes|no> critical: <finding>`. The value is everything after the first `=`.
  - `summary=`: optional criticals text for NEEDS-REVISION. Default: `<critical> critical`.
- `--stale`: `incomplete` resolves the token itself from the rid's last `ROUND` line, which must be `open` or `closing`. For a lead that lost the token.

Consistency checks in `close` (refuse with 64, write nothing):

- `APPROVED` needs `critical=0` and an R6 `pass`.
- `NEEDS-REVISION` needs `critical` at least 1.
- An R6 `critical:` needs `NEEDS-REVISION` and `critical` at least 1.

State checks (refuse with 1, write nothing):

- `open`: the rid's last `ROUND` line must not be `open` or `closing`. The rid must equal `rid()` run in the spec's toplevel, the step 5 rule "the rid of the branch the spec lives on". The spec must pass the ship-gate binding above.
- `close` and `incomplete`: the rid's last `ROUND` line must be `open` or `closing` and carry this token. A `closing` line must name the same sub-verb (`kind=`) and, for `close`, the same `verdict=`.

Every `ROUND` read uses awk on ` | `-split fields with `$2=="ROUND"`, never grep, so a `ROUND`-shaped string inside a `GATE` reason is never read as a round.

Records written by `close` (the step 5 strings, unchanged):

| Case | GATE validate | validate `caught=` | GATE design-record | design-record `caught=` |
|---|---|---|---|---|
| APPROVED | `ran "APPROVED critical=0 warnings=<K> fresh agents=<N> parallel"` | false | `ran "design-bearing=<x> pass"` | false |
| NEEDS-REVISION, R6 pass | `skipped "NEEDS REVISION: <summary>"` | true | `ran "design-bearing=<x> pass"` | false |
| NEEDS-REVISION, R6 critical | `skipped "NEEDS REVISION: <summary>"` | true | `skipped "critical: <finding>"` | true |

Drift in `close`. The verb compares three things with the `ROUND open` line:

- `ledger`: the rid file's last line must be byte-equal to the stored `ROUND open` line.
- `blob`: `git hash-object` of the spec file now. An unreadable or missing spec counts as `blob` drift.
- `porcelain`: `git -C <toplevel> status --porcelain -- . ':(exclude)_meta' ':(exclude).claude' ':(exclude).pytest_cache' ':(exclude).ruff_cache' ':(exclude)tests/.tmp' | git hash-object --stdin`. The excludes cover the hook and cache writers named in `## Grounding` item 4.

On any mismatch the verb appends `ROUND void token=<t> why=<comma list>`. On `why` holding `ledger`, it prints every line after the `ROUND open` line to stderr. Then, in this order:

1. Any line after `ROUND open` with `$2=="GATE"`, `$3` in `validate`/`design-record`, and `$4` in `ran`/`override`: forged record. The verb writes the `incomplete` records with reason `forged record after open` and exits 4.
2. A `ROUND void` already exists since the rid's last round-terminal `ROUND` line: the verb writes the `incomplete` records with reason `restart budget spent` and exits 3. Exit 3 ends the validation; the lead stops.
3. Otherwise it exits 2, and the lead re-runs `open`.

Resume: a re-run of `close` or `incomplete` whose token matches a `ROUND closing` line skips the drift check. It writes only the planned records not already present after that line, keyed on fields 2 to 4 (`GATE validate`, `OUTCOME validate end`, and the design-record pair), then the final `ROUND` line.

Lock: each sub-verb takes `mkdir runs/<rid>.vr-lock` with its PID inside, retries for up to 10 seconds, reclaims a lock whose PID fails `kill -0`, and releases it on exit by trap. On timeout it refuses with 1. `open` resolves the toplevel, checks the binding, pins the blob and snapshots porcelain before its first append.

Outputs, the `| ROUND |` marker (one line each, space-separated `k=v`, no value holds a space or `=`):

```
<ts> | ROUND | open | token=<t> spec=<abs-path> blob=<sha> porcelain=<sha>
<ts> | ROUND | void | token=<t> why=<blob,ledger,porcelain subset>
<ts> | ROUND | closing | token=<t> kind=<close|incomplete> verdict=<APPROVED|NEEDS-REVISION|none>
<ts> | ROUND | close | token=<t> verdict=<APPROVED|NEEDS-REVISION>
<ts> | ROUND | incomplete | token=<t>
```

Invariants:

- Every `OUTCOME validate end` and every `OUTCOME design-record end` the verb writes follows exactly one `GATE` line of the same phase written in the same call. The stats FIFO therefore pairs one bracket per `GATE` line, for `close` and `incomplete` alike.
- A void writes no `GATE` and no `end` line. The next `open` writes fresh start lines; `outcome()` and the stats reader both take the latest start, so a void round's time is excluded from `dur_s`.
- Readers keyed on a marker never read `ROUND`. `check`, `progress`, `descent`, `outcome-read`, `history`, `report` and `read_kit_gates` output is byte-identical with or without `ROUND` lines. `lib/bench/events.py` is identical modulo its `wall` value, which reads the first and last timestamp of any line.

### Data model changes

One additive ledger marker, `| ROUND |`, as above, and one lock directory per rid under `runs/` while a sub-verb runs.

### API changes

A new gate-ledger verb, `validate-round`, listed in the script header and the usage line.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] T1: `validate_round()` in `lib/gate/gate-ledger.sh` with `open`, `close`, `incomplete`, the lock, the dispatch line, the header entry and the usage string. AC: `tests/test-gate-validate-round.sh` cases C1 to C12 pass.
- [ ] T2 (with T1): `tests/test-gate-validate-round.sh`, isolated under a fresh `DWARVES_KIT_LOG_DIR` and temp git repos. AC: the file runs under `bash tests/run-all.sh --all` by glob, exits 0, and C5 goes red under the negative control below.

### Phase 2: Core

- [ ] T3 (after T1): point the three entry points at the verb. AC: C13.
  - `commands/spec.md` step 5: the parallel round runs `validate-round open`, `close` and `incomplete`. It states that no spec, worktree or Status edit happens between `open` and `close`, and that the fold happens after `close` exits 0. It rewords "so `dur_s` measures the validation" per DEC-B, and the incomplete stop now also records `design-record skipped "incomplete: <reason>"`.
  - `commands/execute.md` validation preflight: the parallel round and the critical stop use the verb.
  - `commands/wrap.md` step 10: the lead runs `validate-round open` with the worker's spec path. The verb's rid check enforces "the WORKER's rid".
  - In all three files, every string `tests/test-meta.sh` pins stays. The literal `gate-ledger.sh outcome <rid> Validate start|end` and `design-record start|end` lines stay inside a fallback sentence for the single-pass validator, so `tests/test-outcome-emit-sweep.sh` and `tests/test-command-emit-sweep.sh` stay green.

### Phase 3: Polish

- [ ] T4 (last, after T1 to T3): regenerate `docs/FEATURES.md` with `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md`, unconditionally. AC: `tests/test-meta.sh` passes in full.

## After state

- [ ] `bash lib/gate/gate-ledger.sh validate-round open <rid> <spec>` prints a `<blob>.<epoch>` token and writes both start brackets. (Today: the verb does not exist; the usage line lists no `validate-round`.)
- [ ] A mid-round spec commit makes `close` exit 2 with `ROUND | void | ... why=blob` and no `GATE | validate` line, checkable by `bash tests/test-gate-validate-round.sh`.
- [ ] `commands/spec.md`, `commands/execute.md` and `commands/wrap.md` name `validate-round open`. (Today: step 5 lists `git hash-object -w`, `show <rid>` and `status --porcelain` for the lead to run by hand.)
- [ ] One validation round writes one `GATE` line per `OUTCOME ... end` for both `validate` and `design-record`, including an incomplete round. (Today: SPEC-361's rid holds 4 against 1 for `validate`.)

## Acceptance Criteria (global)

- AC1: `open`, `close` and `incomplete` write exactly the lines and order in `## Technical Design`, and refuse bad input or wrong state with the named exit code and a byte-identical ledger.
- AC2: a spec change, a ledger append or a worktree change during the round voids it (exit 2); a second void since the last round-terminal line writes the `restart budget spent` stop (exit 3); a forged `ran` or `override` after `open` writes the forged stop (exit 4).
- AC3: the marker-keyed readers are byte-identical with `ROUND` lines present versus stripped; `events.py` differs at most in `wall`.
- AC4: all three command files use the verb; every string `tests/test-meta.sh` pins is unchanged; `tests/test-outcome-emit-sweep.sh` and `tests/test-command-emit-sweep.sh` pass.
- AC5: `tests/test-meta.sh` passes in full (baseline 879/879 on `917a2754`).

## Verification

```
bash tests/test-gate-validate-round.sh &&
bash tests/test-gate-outcome.sh &&
bash tests/test-outcome-emit-sweep.sh &&
bash tests/test-command-emit-sweep.sh &&
for f in spec execute wrap; do grep -q 'validate-round open' commands/$f.md || exit 1; done &&
grep -q 'validate-round close <rid>' commands/spec.md &&
grep -q 'validate-round incomplete <rid>' commands/spec.md &&
bash tests/test-meta.sh
```

## Test plan

New file `tests/test-gate-validate-round.sh`. Each case runs under a fresh `DWARVES_KIT_LOG_DIR` and a temp git repo on branch `feat/vr-<case>` holding a committed `docs/specs/SPEC-001-vr-<case>.md`. "Unchanged" means `cmp` of the ledger before and after. "Block" means the exact trailing lines, fields 2 onward, in order.

| Case | Setup | Assert |
|---|---|---|
| C1 open | `open` | exit 0; stdout matches `^[0-9a-f]{40}\.[0-9]+$`; `git cat-file -e <blob>`; last 3 lines are the two start brackets then `ROUND open` |
| C2 close APPROVED | `open`; `close <rid> <t> verdict=APPROVED critical=0 warnings=3 agents=7 r6="design-bearing=yes pass"` | exit 0; block = `ROUND closing`, APPROVED row (4 lines), `ROUND close verdict=APPROVED`; stdout `blob=<pin>`; `outcome-read <rid> validate` says `caught=false` |
| C3 close NEEDS-REVISION, R6 pass | `verdict=NEEDS-REVISION critical=2 warnings=1 agents=7 r6="design-bearing=no pass" summary="stale fixture"` | block = `ROUND closing`, `GATE validate skipped NEEDS REVISION: stale fixture`, `OUTCOME validate end caught=true`, `GATE design-record ran design-bearing=no pass`, `OUTCOME design-record end caught=false`, `ROUND close verdict=NEEDS-REVISION` |
| C4 close NEEDS-REVISION, R6 critical | `critical=1 r6="design-bearing=yes critical: empty Design"` | block as C3 with `GATE design-record skipped critical: empty Design` and design-record `caught=true` |
| C5 blob drift (negative control target) | `open`; edit the spec and `git commit -am`; `close` APPROVED | exit 2; last line `ROUND void` with `why=blob`; no `GATE \| validate` line |
| C6 ledger drift | `open`; `gate-ledger.sh action <rid> x`; `close` | exit 2; `why=` contains `ledger`; stderr holds the `ACTION` line |
| C6b forged ran | `open`; `gate-ledger.sh record <rid> Validate ran "fake"`; `close` | exit 4; block after the forged line = `ROUND void`, the incomplete stop with reason `forged record after open` |
| C7 porcelain drift | `open`; create an untracked `src.txt`; `close` | exit 2; `why=` contains `porcelain` |
| C7b fold before close | `open`; edit the spec's Status line, uncommitted; `close` | exit 2; `why=` holds `blob` and `porcelain` |
| C7c excluded writers | `open`; write `_meta/learned-ledger.md`, `.pytest_cache/x`, `tests/.tmp/x`; `close` APPROVED | exit 0 |
| C8 budget spent | void once, `open` again, void again | exit 3; block after the second void = `ROUND closing kind=incomplete`, `GATE validate skipped incomplete: restart budget spent`, `OUTCOME validate end caught=false`, `GATE design-record skipped incomplete: restart budget spent`, `OUTCOME design-record end caught=false`, `ROUND incomplete` |
| C8b budget reset | void, `open`, `close` NEEDS-REVISION, `open`, void | exit 2, not 3 |
| C9 restart then pass | void once, `open` again, `close` APPROVED | exit 0; `GATE validate` count equals `OUTCOME validate end` count |
| C10 incomplete | `open`; `incomplete <rid> <t> "reviewer 4 dead"` | block = `ROUND closing kind=incomplete`, `GATE validate skipped incomplete: reviewer 4 dead`, `OUTCOME validate end caught=false`, `GATE design-record skipped incomplete: reviewer 4 dead`, `OUTCOME design-record end caught=false`, `ROUND incomplete` |
| C10b incomplete pairs | `open`, `incomplete`, `open`, `close` APPROVED | for `validate` and `design-record` alike: `GATE` count equals `OUTCOME end` count equals 2 |
| C10c stale | `open`; `incomplete <rid> --stale "lead restarted"` | exit 0; same block as C10 with that reason |
| C10d resume | `open`; `close` with `append_run_line` made to fail after the `GATE validate` line (test hook: `GL_VR_FAIL_AFTER=2`); re-run the same `close` | second run exit 0; exactly one of each record after `ROUND closing`; `ROUND close` last |
| C11 refusals | stale token; `close` with no open round; `open` over an open round; `open` over a `closing` round; APPROVED with `critical=2`; APPROVED with an R6 critical; NEEDS-REVISION with `critical=0`; R6 critical with `critical=0`; `r6="yes ok"`; `warnings=x`; `agents=0`; a missing key; an unknown key; a repeated key; re-run `close` with a different verdict over `closing`; `incomplete --stale` with no open round; rid not the spec branch slug; missing spec; spec path with whitespace; spec path with `=`; stub spec `docs/specs/SPEC-001-other.md` for rid `vr-c11`; stub spec outside `docs/specs/`; foreign repo (a second temp repo on `feat/other` holding `docs/specs/SPEC-001-vr-c11.md`); a second `SPEC-000-vr-c11.md` sorting before the given spec; a `GATE` reason holding `\| ROUND \| open \| token=<t>` then `close` with that `<t>`; unknown sub-verb | each exits 64 or 1 as specified; ledger unchanged |
| C12 additive equivalence | a ledger with rounds, including a trailing `ROUND` line one second later than the last record; a copy with `ROUND` lines stripped | `check full`, `progress <rid> full`, `descent <rid> full`, `outcome-read <rid>`, `history`, `report --period week` and `read_kit_gates` identical across both; `events.py` identical except `wall` |
| C13 docs | the three command files | the `validate-round` greps from `## Verification` pass; `tests/test-meta.sh` and both emit sweeps pass |

Negative control: see `## Grounding`, trace.

## Edge Cases

1. The lead crashes between `open` and `close` and loses the token: the next `open` refuses. The lead runs `incomplete <rid> --stale "lead restarted"`, then `open` again.
2. `close` dies midway through its records: the last `ROUND` line is `closing`. A re-run of the same `close` writes only the missing records (C10d).
3. The spec is uncommitted at `open`: porcelain holds ` M <spec>`. Drift still works; any further edit changes the blob.
4. `open` in a repo on `main`: `rid` refuses, so `open` refuses with 1.
5. Summary or reason text with a newline: `record()` collapses it through `oneline`.
6. Two rounds for one rid in the same second: impossible, because `open` refuses over an open round, and the lock serializes callers.
7. The lead's own branch differs from the spec's branch: the rid check refuses. This is the step 5 rule about the rid of the branch the spec lives on, and wrap's "WORKER's rid" rule.
8. A PreCompact harvest or a test cache write lands mid-round: the porcelain excludes skip it (C7c).
9. An orchestrated goal on the same branch records `TOKENS` mid-round: `why=ledger`, exit 2. Fail closed.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A write fails midway through `close` or `incomplete` | Last `ROUND` line is `closing` | Re-run the same sub-verb; it writes only the missing records (C10d). |
| A reader breaks on the new marker | C12 fails | Readers key on field 2; the marker is additive. |
| Another writer appends to the rid during a round | `ROUND void why=ledger`, the new lines on stderr | Intended. A forged `ran` or `override` for validate or design-record exits 4 and writes the incomplete stop. |
| A forged `ROUND` line via free text | A reason holding `\| ROUND \|` | Free text passes through `oneline`, and the verb reads `ROUND` only where `$2=="ROUND"` (C11). |
| Two sub-verbs race on one rid | Interleaved lines | Per-rid mkdir lock; stale-PID reclaim; refuse with 1 after 10 seconds. |
| A hook or cache write voids every round | Repeated `why=porcelain` | Excludes for `_meta/`, `.claude/`, `.pytest_cache`, `.ruff_cache`, `tests/.tmp` (Grounding item 4). A new writer outside them voids, which fails closed. |
| The verb and the command prose drift apart | C13 greps; test-meta pins | The commands name the verb; the verb carries no prose of its own. |

## Out of Scope

- Computing the verdict, counting replies, detecting interim notices, or checking `agents=` against the heading count. The lead owns these.
- The round budget (`operator_directed_build: true`). The verb does not count rounds.
- The single-pass fallback. It keeps its manual records and `fresh agent=<id>` form.
- `check()` passes on any earlier `ran` line for a gate, even when a later line is `skipped`. Pre-existing; a follow-up, not this spec.
- Rewriting SPEC-361's historical ledger lines.

## Touches

- lib/gate/**
- tests/**
- commands/**
- docs/specs/**
- docs/implementation-notes/**
- docs/FEATURES.md

## Decision Log

- DEC-A: extend `gate-ledger.sh`, no sibling script. Reason: reuse of `record()`, `outcome()`, `rid()` and the ledger plumbing; the brief names the precedent.
- DEC-B: `caught=` and `dur_s` are per round. Validation-wide `caught` is any `caught=true` since the last validation-terminal `ROUND` line. A void round writes no `end`, so its time is excluded. Rejected: validation-wide brackets, because the verb cannot know which round is the last; the lead decides whether to re-validate after `close` returns. SPEC-361's validation-wide brackets produced its 4-to-1 mismatch. This rewords step 5's "so `dur_s` measures the validation".
- DEC-C: round state lives in the rid ledger as `| ROUND |` lines, not a side file. Reason: append-only, auditable, and cleaned up with the ledger. Rejected: a state file under `runs/`, which can go stale apart from the ledger.
- DEC-D: the ledger drift check is "the file's last line equals the stored `ROUND open` line". Reason: nothing else may land after `open`; one comparison replaces a count plus a prefix hash.
- DEC-E: `close` takes `key=value` arguments and checks verdict consistency. Reason: seven positional values are easy to swap; the checks are one `case` each and compute nothing.
- DEC-F: `open` refuses unless the rid is the spec branch's slug and the spec is ship-gate's glob match. Reason: the approval must land on the file and rid the ship-gate reads.
- DEC-G: the verb writes the `restart budget spent` and forged-record stops itself. A NEEDS-REVISION `close` resets the void budget. Reason: the budget is part of the order the lead slipped on, and the verb sees every void.
- DEC-H: `incomplete` pairs its brackets with `GATE design-record skipped "incomplete: <reason>"`. Reason: an `end` without a `GATE` line shifts the stats FIFO for every later design-record row. This changes step 5's "An incomplete round records nothing else" to name that one record.
- DEC-I: a `closing` line makes `close` and `incomplete` resumable. Reason: a mid-write failure otherwise leaves a round that neither re-runs nor closes cleanly.

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

**2. How the stats reader pairs them.** `sed -n 149,200p lib/stats/src/stats/adapters.py`: `pending_start[phase] = kv.get("at", "")` on each start (a later start replaces an earlier one), a bracket is appended only on `end`, and each `GATE` line pops `queue.pop(0)`. One bracket per `GATE` line is the only shape that pairs correctly. This grounds DEC-B, DEC-H and the void rule (no `end` on void).

**3. The hash forms.** In the worktree:

```
$ git status --porcelain | git hash-object --stdin
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391      (clean tree = the empty-blob id)
$ git status --porcelain -- . ':(exclude)_meta' ':(exclude).claude' ':(exclude).pytest_cache' ':(exclude).ruff_cache' ':(exclude)tests/.tmp' | git hash-object --stdin
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391
$ git hash-object commands/spec-validate.md
9e4265d1613cf75d719e11310c40589e76c4e01e
$ git --version
git version 2.55.0
```

`git hash-object` is the one hash tool; no `shasum` versus `sha256sum` split between macOS and Ubuntu CI. The `:(exclude)` pathspec works with `git status`.

**4. Who writes during a round.** Ledger writers and worktree writers, found with `grep -rn 'gate-ledger' hooks lib` and the hook table in `hooks/hooks.json`:

| Writer | Where it writes | When | Effect on a round |
|---|---|---|---|
| `hooks/ship-gate.sh` | rid ledger | at push | none; no push happens mid-round |
| `lib/queue/orchestrate.sh` line 818, `gate-ledger.sh tokens "$trid"` | rid ledger (`_rid_for` strips the goal file's Branch) | after an orchestrated goal session ends | `why=ledger` void, exit 2 (edge case 9) |
| `hooks/harvest.sh` then `hooks/harvest.py` | `<repo-root>/_meta/learned-ledger.md` (line 130) | PreCompact | excluded (`_meta/`) |
| `hooks/harvest.sh --lab-log` | `<repo-root>/_meta/.lab-log-draft.md` (line 138) | SessionEnd | excluded (`_meta/`) |
| test runs and linters | `.pytest_cache`, `.ruff_cache`, `tests/.tmp` | any test run | excluded |

`git check-ignore` in the worktree: `.pytest_cache/x`, `.ruff_cache/x`, `tests/.tmp/x` and `_meta/x` are not ignored, so each would show in porcelain without the excludes. `.claude/x` is ignored already; the exclude is kept for worktrees whose `.gitignore` differs.

**5. Readers and markers.** `lib/bench/events.py` lines 211 to 226 branch on `START`, `GATE` and `OUTCOME` only, and line 260 computes `wall` from the first and last timestamp of any line. `read_kit_gates` branches on `GATE`, `OUTCOME` and `TOKENS`. gate-ledger's awk readers key on `$2=="GATE"` or `$2=="OUTCOME"`; `report` reads `head -1` for its start time, and the first line of a rid is never a `ROUND` line. An unknown `ROUND` marker falls through every branch.

**6. The ship-gate binding.** `hooks/ship-gate.sh` line 224: `SPEC=$(ls "$ROOT"/docs/specs/SPEC-*-"$SLUG".md 2>/dev/null | head -1 || true)`. This spec, `docs/specs/SPEC-363-validate-round-verb.md`, is that match for rid `validate-round-verb`.

**7. The sweep constraint.** `tests/test-outcome-emit-sweep.sh` requires, for every `gate-ledger.sh record <rid> <phase> ran` in a command file, a literal `gate-ledger.sh outcome <rid> <phase> start` and `end` in the same file. `commands/spec.md` and `commands/execute.md` record `Validate` and `design-record`, so the literal bracket lines must stay (T3 keeps them in the fallback sentence). `tests/test-meta.sh` pins, among others, `outcome <rid> Validate end caught=true` and the last-line-wins validate grep in `commands/execute.md`, and `stops with \`VALIDATE PENDING: <spec path>\``, `SendMessage` and `fresh builder` in `commands/wrap.md`.

**8. Baseline.** `bash tests/test-meta.sh`: `Passed: 879 / 879`. `bash tests/test-outcome-emit-sweep.sh`: `51 / 51`. `bash tests/test-gate-outcome.sh`: `25/25 passed`.

### Negative control, dry trace

- Mutation: in `close`, delete the blob comparison, so drift checks only the last line and porcelain.
- Fixture: case C5. A temp repo on `feat/vr-c5` with a committed `docs/specs/SPEC-001-vr-c5.md`. `open` pins blob B1. The test appends a line to the spec and runs `git commit -am`, so the spec blob becomes B2, and porcelain is clean again: its hash equals the one taken at `open`. The test writes nothing to the ledger, so the last line is still `ROUND open`.
- Code path: `close` passes the state check (last `ROUND` is `open` with this token) and the key checks. The mutated drift check sees the same last line and the same porcelain hash. It finds no drift, writes `ROUND closing` and `GATE validate ran APPROVED ...`, and exits 0.
- Red test: C5 in `tests/test-gate-validate-round.sh` asserts exit 2 and fails on exit 0. Its second assertion, no `GATE | validate` line, also fails.
- Why the commit matters: an uncommitted edit also changes porcelain, which would void the round through the porcelain check and hide the mutation. The commit isolates the blob check.

Not sampled: behavior when `git` is missing from `PATH`. The verb needs git for `rid` already, so it fails at `rid`.

## Open questions

(none)
