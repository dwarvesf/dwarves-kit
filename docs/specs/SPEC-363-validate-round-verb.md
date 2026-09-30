# Spec: validate-round verb for the parallel validation round

Generated: 2026-09-29
Status: VALIDATED (rounds 1 to 3 NEEDS REVISION folded; round 4 APPROVED, its warnings folded)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-363-validate-round-verb.md`
References: `commands/spec.md` step 5 (the round rules this verb enforces); `lib/gate/gate-ledger.sh` `outcome()` (the additive-marker pattern and the start/end bracket math to reuse); `lib/stats/src/stats/adapters.py::read_kit_gates` (FIFO pairing of `GATE` lines to `OUTCOME` brackets per phase, the reader the record order must satisfy); `hooks/ship-gate.sh` lines 64 and 224 (the slug and spec glob the approval must bind to)

## Problem

`commands/spec.md` step 5 asks the lead to run the parallel validation round's bookkeeping by hand. One round needs `git hash-object -w`, a ledger snapshot, a `git status --porcelain` snapshot, both again after the round, then up to four `gate-ledger.sh` calls in a fixed order with the right `caught=` values. `commands/execute.md` (validation preflight) and `commands/wrap.md` (step 10) repeat the same sequence. The lead ran it for 6 rounds in one session and slipped twice. The live ledger of SPEC-361 (`## Grounding`) shows both slips:

1. `design-record` was recorded and its bracket closed after round 1, while `Validate` stayed open across 3 rounds. The two gates measured different spans.
2. `Validate ran "APPROVED ..."` was recorded from an interim reviewer block. A later `CORRECTION` line followed. The rid now holds 4 `GATE | validate` lines against 1 `OUTCOME | validate | end` bracket, so the stats FIFO pairs the wrong durations.

The rules are right. The manual procedure is the defect: a mechanical sequence carried in prose.

## Solution

### Approaches considered

1. A `validate-round` verb inside `lib/gate/gate-ledger.sh` with `open`, `close` and `incomplete` sub-verbs (chosen). The verb holds the sequence; the lead still computes the verdict. Tradeoff: one more verb on a large script.
2. A sibling script `lib/spec/validate-round.sh` (rejected). The real tradeoff is the boundary, not duplication: `mutation-smoke.sh` and `coverage-delta.sh` already call the gate-ledger CLI without copying its plumbing, so a sibling could do the same. The cost is that the sibling knows spec-lane rules (spec glob, ship-gate slug, round budget) outside the ledger, and the ledger stops being the one home for them. This verb keeps that knowledge in the ledger script, which sits in tension with the ledger as pure substrate (N4); DEC-A accepts it because the marker and the record order are ledger concerns.
3. Keep the prose and add a checklist line to step 5 (rejected). A checklist is what slipped.
4. A single `printf` for the whole `close` append (rejected, DEC-M). One write is atomic and would drop the `closing` state and resume, but `record()` and `outcome()` each append their own line, so both would need splitting into line builders, and the drift and consistency checks would still run before it. The resume path costs less than the refactor.

### Chosen approach + why

Option 1. The `| ROUND |` marker, the record order and the bracket pairing are ledger concerns, so the spec-lane rules that drive them (spec glob, ship-gate slug, void budget) live in the ledger script beside them. That puts spec-lane knowledge inside the substrate, the N4 tension DEC-A accepts. The verb calls `record()`, `outcome()`, `ledger_file()`, `append_run_line()` and `runid()` in the same file. It does not call `rid()`, which runs a bare `git` from the cwd; it copies `rid()`'s branch refusal onto `git -C <toplevel>` instead (DEC-U).

### Extensibility & boundaries

- Load-bearing dimension: the number of rounds per rid. Each round adds 4 to 8 ledger lines. Readers that scan the rid file are linear in its lines, as today.
- Units: `open` (bind + pin + snapshot + brackets), `close` (recheck + records), `incomplete` (stop records). Each reads the rid ledger and appends to it; none holds state outside the ledger.

## Picture

```
lead                                 gate-ledger.sh validate-round                 rid ledger (runs/<rid>.log)
 |                                    |                                              |
 |-- open <rid> <spec> -------------->| spec (pwd -P) == ship-gate's glob match?     |
 |                                    | branch (git -C) not ""/HEAD/main/master?     |
 |                                    | raw slug == runid(slug) == <rid>?            |
 |                                    | pin: git -C <toplevel> hash-object -w <spec> |
 |                                    | head: git -C <toplevel> rev-parse HEAD       |
 |                                    | snapshot: porcelain (untracked, excludes)    |
 |                                    |-- outcome Validate start ------------------->| OUTCOME validate start
 |                                    |-- outcome design-record start -------------->| OUTCOME design-record start
 |<-- <token> ------------------------|-- ROUND open token= top= spec= blob= ... --->| ROUND open  (= last line)
 |                                    |                                              |
 |   fan out N reviewers, wait for final completions, merge by rule (lead)          |
 |   no spec, worktree, commit or Status edit until close exits 0                   |
 |                                    |                                              |
 |-- close <rid> <token> verdict= ... >| last ROUND is open+token? keys consistent?   |
 |                                    | recheck: last line, blob, head, porcelain    |
 |                                    |   drift --> ROUND void why=...; exit 2       |
 |                                    |   second void --> incomplete stop; exit 3    |
 |                                    |-- ROUND closing kind=close <all args> ------>| ROUND closing
 |                                    |-- record Validate ran|skipped -------------->| GATE validate
 |                                    |-- outcome Validate end caught= ------------->| OUTCOME validate end
 |                                    |-- record design-record ran|skipped --------->| GATE design-record
 |                                    |-- outcome design-record end caught= -------->| OUTCOME design-record end
 |<-- blob=<pin> ---------------------|-- ROUND close token= verdict= -------------->| ROUND close
 |                                    |                                              |
 |-- incomplete <rid> <token> <why> ->| ROUND closing kind=incomplete reason, then   |
 |   (or --stale "<why>")             | GATE validate skipped + end caught=false,    |
                                        GATE design-record skipped + end caught=false,
                                        ROUND incomplete
```

## Design

Chosen: a `validate-round` verb in `gate-ledger.sh` that keeps round state as `| ROUND |` ledger lines and writes both gates' records and brackets per round (Solution option 1, DEC-B).

**Ordering:** the interface (sub-verbs, arguments, exit codes) first, the `| ROUND |` marker and its states second, the command text last.

### Approaches considered + chosen

See `## Solution`. One design decision is new here: brackets become per round (DEC-B).

### Diagram

Sequence: see `## Picture`. The round's state machine, read from the rid's last `$2=="ROUND"` line:

```
   (none | close | incomplete | void) --open (exit 0)--> OPEN
                                                           |
   close: forged or foreign line after open --> VOID why=ledger (exit 2, lines on stderr; exit 3 if a void already exists since the last round-terminal line, see the budget branch below)
   close: drift, no void since the last round-terminal ROUND line --> VOID (exit 2) --open--> OPEN
   close: drift, a void since the last round-terminal ROUND line  --> VOID, CLOSING(kind=incomplete) --> INCOMPLETE (exit 3)
   close: keys valid, no drift --> CLOSING(kind=close, every arg pinned) --> CLOSE verdict=APPROVED        (validation-terminal)
                                                                        \--> CLOSE verdict=NEEDS-REVISION (round-terminal)
   incomplete <token> <why> | --stale <why> --> CLOSING(kind=incomplete, reason pinned) --> INCOMPLETE     (validation-terminal)

   CLOSING(kind=close)      + close <rid> <token>      --> write the missing records --> CLOSE
   CLOSING(kind=incomplete) + incomplete <rid> <token> or --stale --> write the missing records --> INCOMPLETE
```

Round-terminal lines (`close` with any verdict, `incomplete`) reset the void budget. Validation-terminal lines (`close verdict=APPROVED`, `incomplete`) end one validation. Validation-wide `caught` for a gate is "any `OUTCOME <gate> end caught=true` inside the window", computed over the lines before this round's own `ROUND closing` line. Those lines never change, so a resume recomputes the same value, and the round's own `GATE validate ran` never bounds its own window. The window starts after the latest of three lines: the rid's first `ROUND open`, the previous validation-terminal `ROUND` line, and the latest `GATE | validate | ran` line (a fallback single-pass validation ends a validation too). Both gates use that same start. Inside the window the verb counts only the `end` lines it wrote itself: those between a `ROUND closing` line and the next `ROUND` line. A fallback validation writes its `end` after its `ran` line, so without that restriction its `caught=true` would sit inside the window. So legacy or fallback history never leaks an old `caught=true` into the verb's current validation. `close verdict=APPROVED` writes that value on its own `validate` end and on its own `design-record` end, so a `ran` row never carries `caught=false` for a validation that caught something (DEC-N). `outcome-read` keeps reporting the last round.

### ADR link(s)

`docs/decisions/0024-gate-ledger-and-ship-enforcement.md` covers the ledger. The `| ROUND |` marker follows the additive-marker convention of `| OUTCOME |`, `| TOKENS |`, `| DEBT |` and `| MUTATION |`: every reader keys on its own marker in field 2 and skips the rest. No new ADR: the marker is additive and reversible.

### Boundaries & failure modes

The verb touches the audit ledger, so see `## Failure modes`. Out of bounds: computing the verdict, counting reviewer replies, judging interim versus final completions, and the round budget. The lead owns all four.

## Technical Design

### Interfaces (I/O contract)

`bash lib/gate/gate-ledger.sh validate-round <sub-verb> ...`

| Sub-verb | Arguments | Writes, in order | Stdout | Exit |
|---|---|---|---|---|
| `open` | `<rid> <spec>` | `OUTCOME validate start`, `OUTCOME design-record start`, `ROUND open` | `<token>` | 0; 1 state, binding or git failure; 64 bad input |
| `close` | `<rid> <token> verdict=<APPROVED\|NEEDS-REVISION> critical=<n> warnings=<k> agents=<n> r6=<r6-line> [summary=<text>]`, or resume: `<rid> <token>` | `ROUND closing`, `GATE validate`, `OUTCOME validate end`, `GATE design-record`, `OUTCOME design-record end`, `ROUND close` | `blob=<pin>` | 0; 1 state or git failure; 2 void; 3 void with budget spent; 64 bad input |
| `incomplete` | `<rid> <token> <reason>`, `<rid> --stale <reason>`, or resume: `<rid> <token>` | `ROUND closing`, `GATE validate skipped "incomplete: <reason>"`, `OUTCOME validate end caught=false`, `GATE design-record skipped "incomplete: <reason>"`, `OUTCOME design-record end caught=false`, `ROUND incomplete` | none | 0; 1 state failure; 64 bad input |

Inputs:

- Git environment: every sub-verb starts with `unset $(git rev-parse --local-env-vars)`, git's own list of repo-local variables (it includes `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR` and `GIT_ALTERNATE_OBJECT_DIRECTORIES`). An inherited `GIT_DIR` or `GIT_COMMON_DIR` overrides `git -C` repo discovery, so without the unset the pin and every read would target the wrong repo (DEC-L).
- Unplanned failures: every sub-verb starts with `set -E; trap 'exit 1' ERR`. The trap is set inside `validate_round()` only. Planned exits (1, 2, 3, 64) are issued in the verb's main shell, never from inside `$(...)` or a helper whose status is tested, so the trap never sees them. Git calls run only in unconditional assignments `x=$(git ...)`, never `local x=$(git ...)` and never inside `if`, `||` or `[ ]`, so a git failure reaches the trap and exits 1. Any other failing command (a helper's non-zero return, a missing binary's 127, GNU `ls`'s 2 on no match) exits 1 the same way. So no stray status can read as a void (2) and loop the lead.
- `<spec>`: at `open`, a regular file, not a symlink, readable (`-f`, `! -L`, `-r`). A missing spec, a symlinked spec, whitespace in the path, `=` in the path, and a spec whose directory does not exist all exit 64 (bad input). The checks run before any git call and before canonicalization. The verb canonicalizes it with `cd "$(dirname <spec>)" && pwd -P` plus the basename, so a relative argument resolves against the caller's cwd once, here. The pin and every later hash use this canonical absolute path. A relative path passed to `git -C <toplevel>` would resolve against `<toplevel>` instead and hash the wrong file or fail. Its canonical path holds no whitespace and no `=`; `<toplevel>` is a prefix of it, so the same holds there. A refusal for the suffix collision below prints both canonical paths.
- Binding: `<toplevel>` is `git -C <spec dir> rev-parse --show-toplevel`. Every later git call in the verb is `git -C <toplevel> ...`, never a bare `git`, so the verb gives the same result from any working directory, including one outside any repo. The pin writes into the spec's own object store. The verb reads the branch with `git -C <toplevel> rev-parse --abbrev-ref HEAD` and refuses `""`, `HEAD`, `master` or `main` with exit 1, the same refusal `rid()` makes (DEC-U). It takes the raw slug `${branch#*/}`, as `hooks/ship-gate.sh` line 64 does. It refuses when the raw slug differs from `runid(slug)`, or `runid(slug)` differs from `<rid>`. The spec's canonical path must equal the canonical path of `ls <toplevel>/docs/specs/SPEC-*-<raw slug>.md 2>/dev/null | head -1 || true`, the ship-gate glob (line 224) with its guards. No match gives an empty string and a refusal (exit 1). So the approval lands on the exact file and rid the ship-gate reads. The cross-reference lives only in a comment in `lib/gate/gate-ledger.sh` naming `hooks/ship-gate.sh` lines 64 and 224; `hooks/ship-gate.sh` is not edited (DEC-X). The C11 ship-gate agreement case guards drift between the two.
- `<token>`: `<blob>.<epoch>.<n>`, printed by `open`. `<n>` is the count of `ROUND open` lines for the rid after this open's line, so tokens never repeat within a rid, even inside one second. Grammar: `^([0-9a-f]{40}|[0-9a-f]{64})\.[0-9]+\.[0-9]+$`, SHA-1 or SHA-256 blob ids. `close` and `incomplete` test it with bash `[[ $token =~ $re ]]` before any token reaches `awk -v`, and refuse a malformed token with 64. `grep -E` would pass a token with an embedded newline, because it matches line by line. The lead reads the pin as `${token%%.*}`. A lead who lost the token reads it from `show <rid>` (the last `ROUND open` or `ROUND closing` line). The token is a correlation id that ties `close` to one `open`, not authentication: anyone who can run `show` can read it.
- `close` keys, each exactly once, in any order; an unknown or repeated key is bad input:
  - `verdict=`: `APPROVED` or `NEEDS-REVISION`.
  - `critical=`: the merged CRITICAL count, which includes Reviewer 6's critical when there is one. Non-negative integer.
  - `warnings=`: non-negative integer. `agents=`: integer, at least 1.
  - `r6=`: Reviewer 6's line, `design-bearing=<yes|no> pass` or `design-bearing=<yes|no> critical: <finding>`. The value is everything after the first `=`.
  - `summary=`: optional criticals text for NEEDS-REVISION. Default: `<critical> critical`.
  - `r6`, `summary` and `<reason>` may not contain a newline, a carriage return or any `|`, because the `closing` line carries them as ` | `-split fields. The verb tests the raw argument, before any `oneline` or other transform, and refuses any `\n`, `\r` or `|` in it with 64. So `a<LF>| ran |<LF>b` and `x| ran |y` both fail. The `execute.md` preflight `grep -Eq '\| (ran|override) \|'` therefore never reads a NEEDS-REVISION line as validated, and resume never misparses `closing` fields.
- `--stale`: `incomplete` resolves the token from the rid's last `ROUND` line, which must be `open`, `void`, or `closing kind=incomplete`. Over `closing kind=incomplete` it resumes with the pinned reason and prints the ignored new reason to stderr. A `closing kind=close` resumes only through `close <rid> <token>`.

Consistency checks in `close` (refuse with 64, write nothing):

- `APPROVED` needs `critical=0` and an R6 `pass`.
- `NEEDS-REVISION` needs `critical` at least 1.
- An R6 `critical:` needs `NEEDS-REVISION` and `critical` at least 1.

State checks (refuse with 1, write nothing):

- `open`: the rid's last `ROUND` line must not be `open` or `closing`. The binding above must hold.
- `close` with full keys: the last `ROUND` line must be `open` and carry this token.
- Resume (`close <rid> <token>` or `incomplete <rid> <token>` with no further argument): the last `ROUND` line must be `closing` with this token and the matching `kind=`.
- `incomplete <rid> <token> <reason>`: the last `ROUND` line must be `open` or `void` and carry this token.

Every `ROUND` read uses awk on ` | `-split fields with `$2=="ROUND"`, never grep, so a `ROUND`-shaped string inside a `GATE` reason is never read as a round.

Records written by `close` (the step 5 strings, unchanged):

| Case | GATE validate | validate `caught=` | GATE design-record | design-record `caught=` |
|---|---|---|---|---|
| APPROVED | `ran "APPROVED critical=0 warnings=<K> fresh agents=<N> parallel"` | validation-wide rollup (DEC-N) | `ran "design-bearing=<x> pass"` | validation-wide rollup (DEC-N) |
| NEEDS-REVISION, R6 pass | `skipped "NEEDS REVISION: <summary>"` | true | `ran "design-bearing=<x> pass"` | false |
| NEEDS-REVISION, R6 critical | `skipped "NEEDS REVISION: <summary>"` | true | `skipped "critical: <finding>"` | true |

Drift in `close`. The verb compares four things with the `ROUND open` line. Every git call here is `git -C <top>`, where `<top>` is the `top=` field stored on `ROUND open`; `close` never re-derives it from the spec's directory, which may be gone.

- `ledger`: the rid file's last line must be byte-equal to the stored `ROUND open` line. Any line after it, from any writer, is drift. The verb lists every such line on stderr, so a forged or foreign `GATE` or `OUTCOME` for `validate` or `design-record` is visible to the lead.
- `blob`: first the verb tests the stored `spec=` path with `-f`, `! -L` and `-r`. A missing, symlinked or unreadable spec fails that test, never reaches git, and counts as `blob` drift. A spec that passes is re-hashed with `git -C <top> hash-object <spec>`, the same canonical path and store as the pin, and compared with `blob=`.
- `head`: `git -C <top> rev-parse HEAD`. A commit during the round is drift.
- `porcelain`: `git -C <top> status --porcelain --untracked-files=all -- . ':(exclude)_meta' ':(exclude).claude' ':(exclude,glob)**/.pytest_cache/**' ':(exclude,glob)**/.ruff_cache/**' ':(exclude,glob)**/.mypy_cache/**' ':(exclude,glob)**/.hypothesis/**' | git -C <top> hash-object --stdin`. The excludes cover the hook and cache writers in `## Grounding` item 4.

On any mismatch the verb appends `ROUND void token=<t> why=<comma list>`. Then:

1. A `ROUND void` already exists since the rid's last round-terminal `ROUND` line: the verb writes the `incomplete` records with reason `restart budget spent` and exits 3. Exit 3 ends the validation; the lead stops.
2. Otherwise it exits 2, and the lead re-runs `open`.

Resume: `close <rid> <token>` or `incomplete <rid> <token>` over a matching `ROUND closing` line skips the drift check. It rebuilds the planned records from the pinned fields, writes only those not already present after the `closing` line (keyed on fields 2 to 4), then the final `ROUND` line.

Concurrency: two sub-verbs on one rid at once are a lead error. The verb takes no lock. The token check and the last-line check fail closed on it: a second `open` makes the first round's `close` refuse (its token is no longer the last `ROUND` line) or void (`why=ledger`).

Git failures: any failing git call inside `open` or `close` (hash-object, rev-parse, status) writes nothing to the ledger and exits 1, through the ERR trap under Inputs. Without it the script's `set -euo pipefail` would leak git's own status (128 outside a repo). A git failure is not drift and never writes a void. The two rules do not overlap: a spec that fails `-f`, `! -L` or `-r` at `close` never reaches git and is `blob` drift, while a git failure hashing a present regular spec, or in `rev-parse` or `status`, exits 1. A `<top>` that no longer exists fails every git call, so it exits 1.

`open` resolves the toplevel, checks the branch and the binding, pins the blob, reads `head` and snapshots porcelain before its first append.

Outputs, the `| ROUND |` marker. Field 5 holds space-separated `k=v` pairs, and no value there holds a space or `=`:

```
<ts> | ROUND | open | token=<t> top=<toplevel> spec=<abs-path> blob=<sha> head=<sha> porcelain=<sha>   (t = <blob>.<epoch>.<n>)
<ts> | ROUND | void | token=<t> why=<ledger,blob,head,porcelain subset>
<ts> | ROUND | closing | token=<t> kind=close verdict=<v> critical=<n> warnings=<k> agents=<n> | <r6-line> | <summary>
<ts> | ROUND | closing | token=<t> kind=incomplete | <reason>
<ts> | ROUND | close | token=<t> verdict=<APPROVED|NEEDS-REVISION>
<ts> | ROUND | incomplete | token=<t>
```

Invariants:

- Every `OUTCOME validate end` and every `OUTCOME design-record end` the verb writes follows exactly one `GATE` line of the same phase written in the same round. The stats FIFO therefore pairs one bracket per `GATE` line, for `close` and `incomplete` alike.
- A void writes no `GATE` and no `end` line. The next `open` writes fresh start lines; `outcome()` and the stats reader both take the latest start, so a void round's time is excluded from `dur_s`.
- Readers keyed on a marker never read `ROUND`: the AC3 list (`check`, `progress`, `descent`, `outcome-read`, gate-ledger `report`, `read_kit_gates`, `proof-table-gen.py`, `mega-review.py`, `mega-report.py`, `pitch.sh` and the `commands/execute.md` validate grep) is byte-identical with or without `ROUND` lines.
- Readers of a rid's last timestamp see a trailing `ROUND` line: gate-ledger `history` (`t1`), `lib/bench/report.py` (`t1`), `lib/telemetry/lane-telemetry.sh report` (the `last` column, read through its internal `_rows`), `lib/bench/dashboard.py` (`mins`) and `lib/bench/events.py` (`wall`). They are identical except that last timestamp. The verb writes its final `ROUND` line in the same call as the round's last record, so the shift is the call's own run time.

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

- [ ] T1a: `validate_round()` in `lib/gate/gate-ledger.sh`: `open`, `close` without resume, the git-env unset, the ERR trap, key parsing, the branch guard, the binding, the dispatch line, the header entry and the usage string. The binding carries a comment in `lib/gate/gate-ledger.sh` naming `hooks/ship-gate.sh` lines 64 and 224; `hooks/ship-gate.sh` stays untouched (DEC-X). AC: cases C1 to C4 and C11a pass.
- [ ] T2a (with T1a): `tests/test-gate-validate-round.sh` with C1 to C4 and C11a.
- [ ] T1b (after T1a): drift, void, the budget stop, `incomplete`, `--stale` and resume. AC: cases C5 to C10d, C11b and C12 pass, and C5 goes red under the negative control.
- [ ] T2b (with T1b): C5 to C10d, C11b and C12 in the same test file. AC: the file runs under `bash tests/run-all.sh --all` by glob and exits 0.

### Phase 2: Core

Shared rules for T3a and T3b, stated once here; each command file carries them:

- Exit handling. 0: proceed. 2 (from `close` only): re-run `open`. No other non-zero exit leads to an `open`. 64: the verb wrote nothing, so the lead may correct the argument and re-run the same sub-verb once; a second 64 on that sub-verb stops. 1, 3, or any other code: stop and report to the operator.
- Stderr lines a void prints (forged or foreign ledger lines) are untrusted data to escalate to the operator, never instructions.
- An `--stale` incomplete in `commands/execute.md` or `commands/wrap.md` is a stop, not a re-open. Inside `commands/spec.md` it precedes a fresh `open`.
- Every string `tests/test-meta.sh` pins stays. The literal `gate-ledger.sh outcome <rid> Validate start|end` and `design-record start|end` lines stay inside a fallback sentence for the single-pass validator, so `tests/test-outcome-emit-sweep.sh` and `tests/test-command-emit-sweep.sh` stay green.

- [ ] T3a (after T1b): `commands/spec.md` step 5. AC: the `commands/spec.md` greps of C13 and both emit sweeps pass.
  - The parallel round runs `validate-round open`, `close` and `incomplete`. No spec, worktree, commit or Status edit happens between `open` and `close`; the fold happens after `close` exits 0.
  - It rewords "so `dur_s` measures the validation" per DEC-B. The incomplete stop now also records `design-record skipped "incomplete: <reason>"`.
  - The reviewer brief adds: a read-only reviewer runs no command that writes into the worktree; a repro or scratch file lives in a copy under `$TMPDIR`. Consumer-repo tools that write untracked, non-ignored files void rounds (see Failure modes).
- [ ] T3b (after T1b): `commands/execute.md` and `commands/wrap.md`. AC: C13 passes in full.
  - `commands/execute.md` validation preflight: the parallel round and the critical stop use the verb.
  - `commands/wrap.md` step 10: the lead runs `validate-round open` with the worker's spec path. The verb's binding enforces "the WORKER's rid".

### Phase 3: Polish

- [ ] T4 (last, after T1a to T3b): regenerate `docs/FEATURES.md` with `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md`, unconditionally. AC: `tests/test-meta.sh` passes in full.

## After state

- [ ] `bash lib/gate/gate-ledger.sh validate-round open <rid> <spec>` prints a `<blob>.<epoch>.<n>` token and writes both start brackets. (Today: the verb does not exist; the usage line lists no `validate-round`.)
- [ ] An edit to an already-dirty spec during a round makes `close` exit 2 with `ROUND | void | ... why=blob` and no `GATE | validate` line, checkable by `bash tests/test-gate-validate-round.sh`.
- [ ] `commands/spec.md`, `commands/execute.md` and `commands/wrap.md` name `validate-round open`. (Today: step 5 lists `git hash-object -w`, `show <rid>` and `status --porcelain` for the lead to run by hand.)
- [ ] One validation round writes one `GATE` line per `OUTCOME ... end` for both `validate` and `design-record`, including an incomplete round. (Today: SPEC-361's rid holds 4 against 1 for `validate`.)

## Acceptance Criteria (global)

- AC1: `open`, `close` and `incomplete` write exactly the lines and order in `## Technical Design`, and refuse bad input or wrong state with the named exit code and a byte-identical ledger.
- AC2: a spec change, a commit, a ledger append or a worktree change during the round voids it (exit 2), and a ledger append lists the new lines on stderr. A second void since the last round-terminal line writes the `restart budget spent` stop (exit 3).
- AC3: every reader keyed on a marker is byte-identical with `ROUND` lines present versus stripped: `check`, `progress`, `descent`, `outcome-read`, gate-ledger `report`, `read_kit_gates`, `lib/gate/proof-table-gen.py`, `lib/mega/mega-review.py`, `lib/mega/mega-report.py`, `lib/pitch.sh`, and the `commands/execute.md` last-`GATE | validate` grep. The last-timestamp readers (`history`, `lib/bench/report.py`, `lane-telemetry.sh report`, `dashboard.py`, `events.py`) are identical except the last timestamp.
- AC4: all three command files use the verb; every string `tests/test-meta.sh` pins is unchanged except the execute.md preflight field parse, the one justified pin change (see `docs/implementation-notes/validate-round-verb.md`); `tests/test-outcome-emit-sweep.sh`, `tests/test-command-emit-sweep.sh` and `tests/test-wrap.sh` pass.
- AC5: `tests/test-meta.sh` passes in full after T4 (baseline 879/879 on `917a2754`).

## Verification

```
bash tests/test-gate-validate-round.sh &&
bash tests/test-gate-outcome.sh &&
bash tests/test-outcome-emit-sweep.sh &&
bash tests/test-command-emit-sweep.sh &&
bash tests/test-wrap.sh &&
for f in spec execute wrap; do grep -q 'validate-round open' commands/$f.md || exit 1; done &&
grep -q 'validate-round close <rid>' commands/spec.md &&
grep -q 'validate-round incomplete <rid>' commands/spec.md &&
bash tests/test-meta.sh
```

## Test plan

New file `tests/test-gate-validate-round.sh`. Each case runs under a fresh `DWARVES_KIT_LOG_DIR` in its own temp dir, outside the temp git repo, so ledger writes never touch porcelain. The temp repo is on branch `feat/vr-<case>` and holds a committed `docs/specs/SPEC-001-vr-<case>.md`. "Unchanged" means `cmp` of the ledger before and after. "Block" means the exact trailing lines, fields 2 onward, in order.

| Case | Setup | Assert |
|---|---|---|
| C1 open | append a line to the committed spec so its blob exists nowhere yet; `open`; then repeat in a repo made with `git init --object-format=sha256` | exit 0; stdout matches `^([0-9a-f]{40}\|[0-9a-f]{64})\.[0-9]+\.[0-9]+$` (40 hex in the first repo, 64 in the SHA-256 repo); `git -C <temp repo> cat-file -e <blob>` succeeds, which proves `-w`; last 3 lines are the two start brackets then `ROUND open` with `top=` equal to the repo's toplevel and `head=` equal to `git rev-parse HEAD` |
| C1b open from elsewhere | dirty the spec first; five sub-runs, each under its own fresh `DWARVES_KIT_LOG_DIR` so no rid holds two opens: cwd in a different temp repo; cwd outside any repo; cwd in the spec repo's `src/` subdirectory with the spec passed as the cwd-relative `../docs/specs/SPEC-001-vr-c1b.md`; `GIT_DIR` exported to the other repo's `.git`; `GIT_COMMON_DIR` exported to the other repo's `.git` | exit 0 in all five; `spec=` is the same canonical absolute path in all five; `git -C <temp repo> cat-file -e <blob>` succeeds; the other repo's object store lacks the blob (`git -C <other> cat-file -e <blob>` fails) |
| C1c token uniqueness | two `open` calls within one second (a void between them) | tokens differ; the second ends in `.2`; `${token%%.*}` equals the pin in both |
| C2 close APPROVED | `open`; `close <rid> <t> verdict=APPROVED critical=0 warnings=3 agents=7 r6="design-bearing=yes pass"` | exit 0; block = `ROUND closing` (every arg pinned), APPROVED row (4 lines), `ROUND close verdict=APPROVED`; stdout `blob=<pin>`; `outcome-read <rid> validate` says `caught=false` |
| C3 close NEEDS-REVISION, R6 pass | `verdict=NEEDS-REVISION critical=2 warnings=1 agents=7 r6="design-bearing=no pass" summary="stale fixture"` | block = `ROUND closing`, `GATE validate skipped NEEDS REVISION: stale fixture`, `OUTCOME validate end caught=true`, `GATE design-record ran design-bearing=no pass`, `OUTCOME design-record end caught=false`, `ROUND close verdict=NEEDS-REVISION` |
| C4 close NEEDS-REVISION, R6 critical | `critical=1 r6="design-bearing=yes critical: empty Design"` | block as C3 with `GATE design-record skipped critical: empty Design` and design-record `caught=true` |
| C5 blob drift (negative control target) | edit the spec without committing; `open`; edit the spec again; `close` APPROVED | `git -C <temp repo> cat-file -e B1` succeeds after `open`; `close` exits 2; last line `ROUND void` with `why=blob` only; no `GATE \| validate` line after `ROUND open` |
| C5b head drift | `open`; `git commit --allow-empty -m x`; `close` | exit 2; `why=` holds `head` |
| C5c spec removed mid-round | `open`; `rm` the spec; `close` APPROVED; separately, `open`, replace the spec with a symlink to a copy, `close` | exit 2 both, never 1; `why=` holds `blob`; no git error on stderr |
| C6 ledger drift | `open`; `gate-ledger.sh action <rid> x`; `close` | exit 2; `why=` holds `ledger`; stderr holds the `ACTION` line |
| C6b forged ran | `open`; `gate-ledger.sh record <rid> Validate ran "fake"`; `close` | exit 2; `why=` holds `ledger`; stderr holds the forged `GATE validate ran` line |
| C7 porcelain drift | `open`; create an untracked `src/new.txt`; `close` | exit 2; `why=` holds `porcelain` (nested untracked file seen through `--untracked-files=all`) |
| C7b fold before close | `open`; edit the committed spec's Status line; `close` | exit 2; `why=` holds `blob` and `porcelain` |
| C7c excluded writers | `open`; write `_meta/learned-ledger.md`, `.claude/session-state/last-state.md`, `lib/x/.pytest_cache/v`, `.hypothesis/examples/x`; `close` APPROVED | exit 0 |
| C8 budget spent | void once, `open` again, void again | exit 3; block after the second void = `ROUND closing kind=incomplete`, `GATE validate skipped incomplete: restart budget spent`, `OUTCOME validate end caught=false`, `GATE design-record skipped incomplete: restart budget spent`, `OUTCOME design-record end caught=false`, `ROUND incomplete` |
| C8b budget reset | void, `open`, `close` NEEDS-REVISION, `open`, void | exit 2, not 3 |
| C9 restart then pass | void once, `open` again, `close` APPROVED | exit 0; `GATE validate` count equals `OUTCOME validate end` count |
| C9b caught rollup | `open`, `close` NEEDS-REVISION (R6 pass), `open`, `close` APPROVED (R6 pass); then again with the first round's R6 critical | first run: the APPROVED `OUTCOME validate end` carries `caught=true`, design-record `caught=false`; second run: both `caught=true`; `outcome-read <rid> validate` says `caught=true`; an APPROVED-only validation keeps `caught=false`. Window legs: a ledger seeded with a legacy `OUTCOME \| validate \| end \| ... caught=true` before the first `ROUND open`, then an APPROVED-only validation, gives `caught=false`; `open`, `close` NEEDS-REVISION, then a fallback `record <rid> Validate ran` followed by `outcome <rid> Validate end caught=true`, then `open`, `close` APPROVED, gives `caught=false` on both gates |
| C10 incomplete | `open`; `incomplete <rid> <t> "reviewer 4 dead"` | block = `ROUND closing kind=incomplete`, `GATE validate skipped incomplete: reviewer 4 dead`, `OUTCOME validate end caught=false`, `GATE design-record skipped incomplete: reviewer 4 dead`, `OUTCOME design-record end caught=false`, `ROUND incomplete` |
| C10b incomplete pairs | `open`, `incomplete`, `open`, `close` APPROVED | for `validate` and `design-record` alike: `GATE` count equals `OUTCOME end` count equals 2 |
| C10c stale | `open`; `incomplete <rid> --stale "lead restarted"`; separately, after a void, `--stale` | exit 0 both; same block as C10 with that reason |
| C10d resume | `open`; `close` APPROVED args parsed, then the test hand-writes the `ROUND closing` line and the `GATE validate` line to a copy of the ledger and swaps it in; `close <rid> <t>` | exit 0; exactly one of each record after `ROUND closing`; `ROUND close` last. Same for `incomplete <rid> <t>` over a hand-written `closing kind=incomplete` |
| C11a open and key refusals (T1a) | `open`: rid not the spec branch slug; branch `main` (exit 1, the `rid()` refusal read through `git -C`); branch `feat/Vr+C11` whose raw slug differs from `runid` (`runid` strips `+`, giving `VrC11`); branch `feat/no-such-spec`, rid `no-such-spec`, whose slug matches no spec (the glob returns empty; exit 1, not GNU `ls`'s 2); missing spec, exit 64; spec as a symlink to the real spec, exit 64; spec path with whitespace, exit 64; spec path with `=`, exit 64; spec whose directory does not exist, exit 64 (each asserts exactly 64, with no git call made and no canonicalization run); stub spec `docs/specs/SPEC-001-other.md`; stub spec outside `docs/specs/`; foreign repo (a second temp repo on `feat/other` holding `docs/specs/SPEC-001-vr-c11.md`); a second `SPEC-000-vr-c11.md` sorting before the given spec; `open` over an open round; `open` over a hand-written `closing` round; a `git` failure in `open` (a corrupt object store, or `git` failing via a `PATH` shim). Full-key `close`: stale token; no open round; APPROVED with `critical=2`; APPROVED with an R6 critical; NEEDS-REVISION with `critical=0`; R6 critical with `critical=0`; `r6="yes ok"`; `r6` holding ` \| `; `summary` holding `a<LF>\| ran \|<LF>b`; `summary` holding `x\| ran \|y`; `r6` holding a bare `\|`, a newline, or a carriage return; a malformed token (no epoch, no nonce, uppercase hex, 41 hex); a token that is valid then `<LF>x`; `warnings=x`; `agents=0`; a missing key; an unknown key; a repeated key; a `GATE` reason holding `\| ROUND \| open \| token=<t>` then `close` with that `<t>`. Also: unknown sub-verb; ship-gate agreement: the spec path the verb accepts equals `ls <toplevel>/docs/specs/SPEC-*-<raw slug>.md 2>/dev/null \| head -1` as `hooks/ship-gate.sh` resolves it | each exits 64 or 1 as specified; ledger unchanged (a git failure exits 1, never 128, and writes no void) |
| C11b incomplete, resume and close-time refusals (T1b) | full-key `close` over `closing`; `close <rid> <t>` over `closing kind=incomplete`; `incomplete <rid> <t> <reason>` with `reason` holding a bare `\|`, a newline, or a carriage return; `incomplete` with a malformed or newline token; `incomplete --stale` over `closing kind=close`; `incomplete --stale` with no round; a `git` failure in `close` on a present regular spec (a `PATH` shim failing `hash-object`, `rev-parse` or `status`) | each exits 64 or 1 as specified; ledger unchanged (a git failure exits 1, never 128, and writes no void) |
| C12 additive equivalence | a ledger starting with a `START` line, then rounds, then a trailing `ROUND` line one second later than the last record; a copy with `ROUND` lines stripped | identical across both: `check full <rid>`, `progress <rid> full`, `descent <rid> full`, `outcome-read <rid>`, gate-ledger `report --period week`, `read_kit_gates`, `lib/gate/proof-table-gen.py <rid> <out>` (whose parser `lib/mega/mega-review.py` imports), `parse_ledger(<log dir>, <rid>)` from `lib/mega/mega-report.py`, `lib/pitch.sh`'s `\| GATE \| grill \|` read, and the `commands/execute.md` line `show <rid> \| grep -Ei '\| GATE \| validate \| ' \| tail -1`; `history`, `lib/bench/report.py`, `lane-telemetry.sh report`, `dashboard.py` and `events.py` identical except the last timestamp or the value derived from it |
| C13 docs | the three command files | the `validate-round` greps from `## Verification` pass; both emit sweeps and `tests/test-wrap.sh` pass |

Negative control: see `## Grounding`, trace.

## Edge Cases

1. The lead crashes between `open` and `close` and loses the token: the next `open` refuses. Inside `/kit:spec` the lead runs `incomplete <rid> --stale "lead restarted"`, then `open` again. In `/kit:execute` and `/kit:wrap` the `--stale` incomplete is a stop.
2. `close` dies midway through its records: the last `ROUND` line is `closing` with every argument pinned. `close <rid> <token>` writes only the missing records (C10d).
3. The spec is uncommitted at `open`: porcelain holds ` M <spec>` before and after, so only the blob can catch a further edit (C5).
4. `open` in a repo on `main`: the branch guard refuses with exit 1. The verb reads the branch with `git -C <toplevel> rev-parse --abbrev-ref HEAD` and applies `rid()`'s own `""|HEAD|master|main` refusal, copied rather than called, because `rid()` runs a bare `git` from the cwd (DEC-U). C11a covers it.
5. Summary, reason or r6 text with a newline, a carriage return or a `|`: refused with 64 before any write. The verb tests the raw argument; nothing collapses it first (see the pipe rule under Inputs). `record()` still collapses whatever other callers pass it.
6. Two sub-verbs on one rid at once: a lead error. `open` refuses over an open round; a racing second `open` voids or refuses the first round's `close`.
7. The lead's own branch differs from the spec's branch: the binding refuses. This is the step 5 rule about the rid of the branch the spec lives on, and wrap's "WORKER's rid" rule.
8. A PreCompact harvest, a Stop or SubagentStop session-state save, or a test cache write lands mid-round: the porcelain excludes skip it (C7c).
9. Any other ledger writer lands mid-round (an orchestrated `TOKENS` or `START` line, a `MUTATION` or `coverage-delta` record): `why=ledger`, exit 2. Fail closed.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A write fails midway through `close` or `incomplete` | Last `ROUND` line is `closing` | `close <rid> <token>` or `incomplete <rid> <token>` writes only the missing records from the pinned fields (C10d). |
| A reader breaks on the new marker | C12 fails | Readers key on field 2; the marker is additive. Last-timestamp readers shift by the call's own run time. |
| A forged or foreign line lands after `open` | `ROUND void why=ledger`, the new lines on stderr | The round voids (exit 2). `check()` still counts a forged `GATE validate ran` as passing, because it accepts any earlier `ran`; until the Out of Scope `check()` follow-up lands, the lead escalates such a line to the operator. |
| A forged `ROUND` line via free text | A reason holding `\| ROUND \|` | Free text passes through `oneline`, and the verb reads `ROUND` only where `$2=="ROUND"` (C11a). |
| Two sub-verbs race on one rid | Two `ROUND open` lines, or a line after the first round's `ROUND open` | No lock; a lead error. The token and last-line checks refuse or void. |
| A hook or cache write voids every round | Repeated `why=porcelain` | Excludes for `_meta/`, `.claude/` and the four cache globs (Grounding item 4). A new writer outside them voids, which fails closed. |
| A race between close's drift check and its `closing` append | A write landing in that gap goes unseen; the round closes over it | Accepted (DEC-J): a lead error, no lock. The window is one shell step. |
| A race between open's start brackets and `ROUND open` | A foreign line between the brackets and the `ROUND open` line | Accepted (DEC-J): a foreign line landing between the brackets and `ROUND open` sits before the pinned last line and goes unseen. |
| Consumer repo tools write untracked, non-ignored files | Repeated `why=porcelain` | The round is void. Fix: add the path to `.gitignore` or `.git/info/exclude`. A new ledger writer needs a change to this verb (a new marker allowed after `ROUND open`), never a silent exclude. |
| A git call fails inside `open` or `close` | Exit 1, ledger unchanged | Nothing written, no void. The lead stops and reports (DEC-T). The round's state is unchanged, so after the fix the operator can direct a re-run of the same sub-verb. |
| The spec is deleted, swapped for a symlink or made unreadable mid-round | `ROUND void why=blob` (C5c) | The `-f`, `! -L`, `-r` test runs before hashing, and `close` uses the stored `top=`, so the round voids (exit 2) rather than failing on git. |
| The lead loses the token after a crash | `open` refuses over the open round | Read it from `show <rid>` (the last `ROUND open` or `ROUND closing` line), or run `incomplete <rid> --stale`. |
| The verb and the command prose drift apart | C13 greps; test-meta pins | The commands name the verb; the verb carries no prose of its own. |

## Out of Scope

- Computing the verdict, counting replies, detecting interim notices, or checking `agents=` against the heading count. The lead owns these.
- The round budget (`operator_directed_build: true`). The verb does not count rounds.
- The single-pass fallback. It keeps its manual records and `fresh agent=<id>` form.
- `check()` passes on any earlier `ran` line for a gate, even when a later line is `skipped`. Pre-existing; a follow-up, not this spec.
- A lock around the sub-verbs.
- Rewriting SPEC-361's historical ledger lines.

## Touches

- lib/gate/**
- tests/**
- commands/**
- docs/specs/**
- docs/implementation-notes/**
- docs/verification/**
- docs/FEATURES.md

## Decision Log

- DEC-A: extend `gate-ledger.sh`, no sibling script. Reason: the `| ROUND |` marker, the record order and the bracket pairing are ledger concerns, so the spec-lane rules that drive them live beside them in the ledger script. A sibling could call the gate-ledger CLI as `mutation-smoke.sh` does, so duplication is not the reason. The cost is spec-lane knowledge inside the substrate (N4), accepted.
- DEC-B: `caught=` and `dur_s` are per round, except APPROVED (DEC-N). Validation-wide `caught` is any `caught=true` inside the DEC-N window. A void round writes no `end`, so its time is excluded. Rejected: validation-wide brackets, because the verb cannot know which round is the last; the lead decides whether to re-validate after `close` returns. SPEC-361's validation-wide brackets produced its 4-to-1 mismatch. This rewords step 5's "so `dur_s` measures the validation".
- DEC-C: round state lives in the rid ledger as `| ROUND |` lines, not a side file. Reason: append-only, auditable, and cleaned up with the ledger. Rejected: a state file under `runs/`, which can go stale apart from the ledger.
- DEC-D: the ledger drift check is "the file's last line equals the stored `ROUND open` line". Reason: nothing else may land after `open`; one comparison replaces a count plus a prefix hash.
- DEC-E: `close` takes `key=value` arguments and checks verdict consistency. Reason: seven positional values are easy to swap; the checks are one `case` each and compute nothing.
- DEC-F: `open` binds to ship-gate's own slug and glob, on canonical paths, and refuses a symlink. Reason: the approval must land on the file and rid the ship-gate reads.
- DEC-G: the verb writes the `restart budget spent` stop itself, and a NEEDS-REVISION `close` resets the void budget. Reason: the budget is part of the order the lead slipped on, and the verb sees every void.
- DEC-H: `incomplete` pairs its brackets with `GATE design-record skipped "incomplete: <reason>"`. Reason: an `end` without a `GATE` line shifts the stats FIFO for every later design-record row. This changes step 5's "An incomplete round records nothing else" to name that one record.
- DEC-I: a `closing` line pins every argument, so resume takes only `<rid> <token>`. Reason: a mid-write failure otherwise leaves a round that neither re-runs nor closes cleanly, and a resume with fresh arguments could write different records than the first attempt.
- DEC-J: no lock, no forged-record exit code, no test-only failure hook. Reason: round 2's simplification. Concurrency is a lead error the token check fails closed on; a forged line is ledger drift like any other and is listed on stderr; C10d builds the partial ledger by hand.
- DEC-K: `head` and `--untracked-files=all` join the snapshot. Reason: a mid-round commit leaves porcelain clean, and the default untracked mode folds a new nested file into its directory entry.
- DEC-L: every git call in the verb is `git -C <toplevel>` (at `close`, the stored `top=`), the pin and the blob re-hash included, and every sub-verb first runs `unset $(git rev-parse --local-env-vars)`. Reason: a bare `git hash-object -w` writes into the current directory's repo, so a lead running from another repo pins the blob into the wrong object store, and outside any repo it exits 128. An inherited `GIT_DIR` overrides `-C` discovery the same way (reproduced round 4). `GIT_COMMON_DIR` overrides `-C` discovery too, and a fixed four-variable list missed it and `GIT_ALTERNATE_OBJECT_DIRECTORIES`, so the verb uses git's own list. Unset beats narrowing the claim: one line, and the "same result from any cwd" claim holds. The spec has no other bare git call in the verb's own steps; Grounding item 3 is a transcript of a manual sampling and stays as run.
- DEC-M: rejected the single-`printf` atomic append for `close`. Reason: it removes the `closing` state and resume, but `record()` and `outcome()` build and append their own lines, so both would split into builders and the drift and consistency checks would still precede it. Resume is smaller. Revisit if the resume path proves fragile.
- DEC-N: `close verdict=APPROVED` writes validation-wide `caught` on its `validate` and `design-record` ends. The window starts after the latest of the rid's first `ROUND open`, the previous validation-terminal `ROUND` line and the latest `GATE | validate | ran` line, for both gates, and counts only `end` lines inside a verb round block (after `ROUND closing`, before the next `ROUND` line). It reads only the lines before this round's `ROUND closing`, so the APPROVED round's own `ran` line never empties its window, and resume recomputes the same value. Reason: per-round `caught=false` on every APPROVED `ran` row makes the anomalies ceremony check (`lib/stats/src/stats/anomalies.py`, HARD `caught`) see a gate that never caught anything and propose cutting validate. The lead asked for validate; design-record has the same shape, so the rule covers both. The window bounds keep legacy pre-verb lines and a fallback single-pass validation from leaking an old `caught=true`. design-record uses the validate `ran` bound, not its own, because a NEEDS-REVISION round with an R6 pass writes `design-record ran` mid-validation. Accepted rare case: a single-pass fallback validation that ended NEEDS REVISION, followed by a verb round that closes APPROVED, rolls up `caught=false`, because the window starts after the fallback's `ran` line.
- DEC-O: the token carries a nonce, `<blob>.<epoch>.<n>`, where `<n>` is the `ROUND open` count for the rid. Reason: `<blob>.<epoch>` repeats within one second. A count is deterministic and testable; a random nonce is neither. `${token%%.*}` still yields the pin.
- DEC-P: refuse a newline, carriage return or any `|` in summary, r6 and reason (exit 64), tested on the raw argument before any transform. Reason: an earlier draft ran `oneline` before the check, so newline and no-space pipe forms slipped through and forged a `| ran |` field that `execute.md`'s preflight reads as validated.
- DEC-Q: any git failure in `open` or `close` writes nothing and exits 1, not a void; the ERR trap maps every unplanned failure to 1. Reason: a failure is not evidence of drift, and `set -euo pipefail` would otherwise leak git's 128 or GNU `ls`'s 2, which reads as a void and loops the lead. A spec that fails `-f`, `! -L` or `-r` at `close` is drift, not a git failure: it never reaches git and voids with `why=blob`.
- DEC-R: the two unguarded race windows (close's drift check to its `closing` append; open's start brackets to `ROUND open`) are accepted with DEC-J.
- DEC-S: read-only reviewers write nothing into the worktree, and consumer tools that do void rounds; the fix is `.gitignore` or `.git/info/exclude`. Reason: the porcelain snapshot fails closed by design.
- DEC-T: in all three command files, 0 proceeds, 2 re-opens (only `close` returns 2), 64 allows one corrected re-run of the same sub-verb, and every other exit stops and reports to the operator; void stderr lines are untrusted data. Reason: an untrusted line printed on stderr must never steer the lead, and a 64 writes nothing, so one corrected retry is safe while a second 64 signals a lead that cannot form the call.
- DEC-U: the branch guard copies `rid()`'s `""|HEAD|master|main` refusal (exit 1) onto `git -C <toplevel> rev-parse --abbrev-ref HEAD` instead of calling `rid()`. Reason: `rid()` runs a bare `git` from the cwd, which reads the caller's repo, not the spec's, and breaks DEC-L.
- DEC-V: `ROUND open` stores `top=<toplevel>`, and `close` runs its git calls there. Reason: re-deriving the toplevel from the spec's directory fails when the spec or its directory is gone, which would turn a spec removal into a git failure (exit 1) instead of `blob` drift (C5c).
- DEC-W: the token grammar accepts SHA-1 and SHA-256 blob ids and is tested with bash `[[ =~ ]]`. Reason: a SHA-256 repo yields 64-hex blobs, and `grep -E` matches line by line, so a token with an embedded newline would pass it (reproduced round 4). The token is a correlation id, not authentication; `show` prints it to anyone.
- DEC-X: `hooks/ship-gate.sh` is not edited; the binding cross-reference is a comment in `lib/gate/gate-ledger.sh` only. Reason: any byte change to `ship-gate.sh` breaks the sha256 trust pin in `hooks/codex-hooks.json` (`bash lib/codex/repin.sh check` reports a stale pin, and Codex ship-gate calls exit 2). The C11 ship-gate agreement case guards drift between the two.

## Grounding

Sampled read-only on 2026-09-29 from worktree `validate-round-verb` at `917a2754` (items 1 to 3, 6 to 8) and `2129daf6` (items 4, 5).

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
$ git status --porcelain --untracked-files=all -- . ':(exclude)_meta' ':(exclude).claude' ':(exclude,glob)**/.pytest_cache/**' ':(exclude,glob)**/.ruff_cache/**' ':(exclude,glob)**/.mypy_cache/**' ':(exclude,glob)**/.hypothesis/**' | git hash-object --stdin
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391      (clean tree = the empty-blob id)
$ git hash-object commands/spec-validate.md
9e4265d1613cf75d719e11310c40589e76c4e01e
$ git rev-parse HEAD
2129daf6663019e5f429852bde375ef264cd8431
$ git --version
git version 2.55.0
```

`git hash-object` is the one hash tool; no `shasum` versus `sha256sum` split between macOS and Ubuntu CI. The `:(exclude)` and `:(exclude,glob)` pathspecs work with `git status`.

**4. Who writes during a round.** Found with `grep -rn 'gate-ledger' hooks lib` and the hook table in `hooks/hooks.json`:

| Writer | Where it writes | When | Effect on a round |
|---|---|---|---|
| `hooks/ship-gate.sh` | rid ledger | at push | none; no push happens mid-round |
| `lib/goal/wt.sh` line 39, `gate-ledger.sh start "$slug"` | rid ledger (`START`) | worktree creation | `why=ledger` if it lands mid-round |
| `lib/queue/orchestrate.sh` line 818, `tokens "$trid"` | rid ledger (`TOKENS`) | after an orchestrated goal session | `why=ledger` |
| `lib/queue/orchestrate.sh` line 837, `start "$slug"` | rid ledger (`START`) | orchestrated dispatch | `why=ledger` |
| `lib/gate/mutation-smoke.sh` line 181, `mutation "$rid"` | rid ledger (`MUTATION`) | review-time smoke | `why=ledger` |
| `lib/gate/coverage-delta.sh` line 204, `record "$rid" coverage-delta ran` | rid ledger (`GATE`) | review-time gate | `why=ledger` |
| `lib/reflect/propose.py` line 336, `tokens` | the reflect run's rid ledger (`TOKENS`) | a reflect pass | `why=ledger` only if run on this rid |
| `hooks/harvest.sh` then `hooks/harvest.py` | `<repo-root>/_meta/learned-ledger.md` (line 130) | PreCompact | excluded (`_meta/`) |
| `hooks/harvest.sh --lab-log` | `<repo-root>/_meta/.lab-log-draft.md` (line 138) | SessionEnd | excluded (`_meta/`) |
| `hooks/session-state-save.sh` | `.claude/session-state/last-state.md` in the cwd | every Stop and SubagentStop, so on every reviewer's return | excluded (`.claude/`) |
| pytest, ruff, mypy, hypothesis | `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `.hypothesis` at any depth | any test or lint run | excluded by glob |

Any ledger writer not in this table also voids the round (`why=ledger`): fail closed.

Cache rationale, corrected: the root `.gitignore` lists none of the four cache directories (`grep -nE 'cache|hypothesis' .gitignore` finds only a serena line and `__pycache__/`). pytest, ruff and mypy normally write a self-ignoring `.gitignore` inside their cache directory, so those usually stay out of porcelain; `.hypothesis` depends on the tool version. No cache directory exists in this checkout to sample. The glob excludes make the snapshot independent of whether a tool wrote its self-ignore file.

**5. Readers and markers.**

- Marker-keyed, never read `ROUND`: `lib/bench/events.py` lines 211 to 226 branch on `START`, `GATE` and `OUTCOME` only. `read_kit_gates` branches on `GATE`, `OUTCOME` and `TOKENS`. gate-ledger's awk readers key on `$2=="GATE"` or `$2=="OUTCOME"`.
- Last-timestamp readers, which do see a trailing `ROUND` line:
  - gate-ledger `history`, lines 872 to 873: `t0="$(head -1 "$f" ...)"`, `t1="$(tail -1 "$f" ...)"`.
  - `lib/bench/report.py` line 51: `first_ts, last_ts = first_ts or ts, ts`, returned as `t1`.
  - `lib/telemetry/lane-telemetry.sh` line 103: `{ last=$1 }`, emitted as `_rows`' `last` column and read through `lane-telemetry.sh report`.
  - `lib/bench/dashboard.py` lines 241 to 245: `mins` from `t1 - t0`.
  - `lib/bench/events.py` line 260: `wall` from the first and last timestamp.
- `head -1` readers (`history`, `report`) never see a `ROUND` line first, because a rid's first line is a `START` or `OUTCOME` line.

**6. The ship-gate binding.** `hooks/ship-gate.sh` line 64: `SLUG="${BRANCH#*/}"`; line 224: `SPEC=$(ls "$ROOT"/docs/specs/SPEC-*-"$SLUG".md 2>/dev/null | head -1 || true)`. The glob uses the raw slug, not `runid()`. This spec, `docs/specs/SPEC-363-validate-round-verb.md`, is that match for slug `validate-round-verb`, whose `runid` is the same string.

**7. The sweep constraint.** `tests/test-outcome-emit-sweep.sh` requires, for every `gate-ledger.sh record <rid> <phase> ran` in a command file, a literal `gate-ledger.sh outcome <rid> <phase> start` and `end` in the same file. `commands/spec.md` and `commands/execute.md` record `Validate` and `design-record`, so the literal bracket lines must stay (T3a and T3b keep them in the fallback sentence). `tests/test-meta.sh` pins, among others, `outcome <rid> Validate end caught=true` and the last-line-wins validate grep in `commands/execute.md`, and `stops with \`VALIDATE PENDING: <spec path>\``, `SendMessage` and `fresh builder` in `commands/wrap.md`.

**8. Baseline.** `bash tests/test-meta.sh`: `Passed: 879 / 879`. `bash tests/test-outcome-emit-sweep.sh`: `51 / 51`. `bash tests/test-gate-outcome.sh`: `25/25 passed`.

### Negative control, dry trace

- Mutation: in `close`, delete the blob comparison, so drift checks only the last line, `head` and porcelain.
- Fixture: case C5. A temp repo on `feat/vr-c5` with a committed `docs/specs/SPEC-001-vr-c5.md`. The test edits the spec without committing, so porcelain holds ` M docs/specs/SPEC-001-vr-c5.md`. `open` pins blob B1, `head` H and that porcelain hash P. The test appends another line to the spec: the blob becomes B2, and porcelain still reads ` M docs/specs/SPEC-001-vr-c5.md`, so its hash stays P. No commit, so `head` stays H. The log dir is outside the repo, and the test writes nothing to the ledger, so the last line is still `ROUND open`.
- Code path: `close` passes the state check (last `ROUND` is `open` with this token) and the key checks. The mutated drift check sees the same last line, the same `head` and the same porcelain hash. It finds no drift, writes `ROUND closing` and `GATE validate ran APPROVED ...`, and exits 0.
- Red test: C5 in `tests/test-gate-validate-round.sh` asserts exit 2 and fails on exit 0. Its second assertion, no `GATE | validate` line after `ROUND open`, also fails.
- Why the spec is dirty at `open`: an edit to a clean spec changes porcelain, and a commit changes `head`; either would void the round through another check and hide the mutation. A spec already dirty at `open` isolates the blob check.

Not sampled: behavior when `git` is missing from `PATH`. The verb calls no `rid()`; its first `git -C` call fails with 127, and the ERR trap maps that to exit 1 with nothing written.

## Open questions

(none)
