# Spec: lanes as data, a light default lane, and a depth line
Generated: 2026-09-29
Status: DRAFT
Lane: full
Depth: standard (no outside unknown: every reader this spec changes is in this repo and cited below; the failure modes are listed in Failure modes)
References: `lib/gate/gate-policy.sh:40-52` (imitate its committed-and-clean rule for a project file that weakens a gate); `lib/classify/lane-classify.sh:86-102` (imitate its file-fact check for the new hard-path floor); `docs/research/2026-09-29-openrig-absorption.md:99-112,206-213` (designs D1, D2, D8).

## Problem

The kit sizes most work heavier than it needs, and the lane rules live in prose and regex, so changing them means rewriting prose.

| Symptom | Evidence |
|---|---|
| The rule says "When in doubt between two lanes, take the heavier one" | `docs/WORKFLOW.md:62-63`, repeated at `AGENTS.md:66-67`, `examples/hello-spec/AGENTS.md:38`, `commands/assign.md:112` |
| One keyword turns a task into the full lane automatically | `lib/classify/lane-classify.sh:147-168`: any hard-flag regex hit returns `full` |
| Four known false hits | Measured today: "add token count column" = full (flag `audit-security`, word `token`, `lane-classify.sh:56`); "add queue timeout" = full (`external-provider`, `\bqueue(s)?\b`, `:57`); "add webhook retry log line" = full (`external-provider`, `webhook`, `:57`); "add user role label" = full (`auth`, `\brole(s)?\b`, `:54`) |
| Full-lane phases get overridden, not run | Research record: think / reflect / design phases overridden 17 / 11 / 11 / 10 times across about 108 run ledgers (`docs/research/2026-09-29-openrig-absorption.md:64`). Recount today across 149 ledgers: think 21, reflect 14, design 15, design-critique 14, test-plan 6 (command in `## Grounding`) |
| The spec-to-build step also escalates on keywords | `lib/classify/lane-classify.sh:254-277` (`escalate`), acted on at `commands/execute.md:36-41` |
| Deeper planning runs by topic, not by need | `/kit:spec` sends 4 research agents on every brownfield spec (`commands/spec.md:21-34`); `/kit:test-write` refuses to run without a test-plan review team verdict (`commands/test-write.md:16-31`) |
| Lanes are prose, not data | `lib/gate/gate-ledger.sh:128-145` parses the markdown table in `docs/WORKFLOW.md:420-435` at run time; no repo can change a lane without editing kit prose |

What stays load-bearing and must not weaken: the fresh-context spec validator caught a problem in 19 of 35 runs (`docs/research/2026-09-29-openrig-absorption.md:57`). This spec keeps it on every spec.

Premise corrections found while checking the brief:

1. The ship-gate has no auth, migration, secret, or data-loss diff paths today. It checks only the lane the spec declares (`hooks/ship-gate.sh:250,282`). The diff-keyed check that exists is the proof gate's `stateful` class (`lib/gate/proof-ledger.sh:112`), and it asks for a proof record, not full-lane gates. Today the only thing that puts a migration on the full lane is the keyword classifier at intake. This spec therefore builds a new diff-keyed hard-path floor before it turns the keyword escalation into a suggestion.
2. The lane gate is opt-in: `lane_gates = false` at the kit root (`kit.toml:113`). It is on for this operator through the overlay (`~/.config/dwarves-kit/kit.toml [gate] lane_gates = true`). The hard-path floor rides the same switch (open question 1).
3. The research agents map the repo (`commands/spec.md:31-34`); they do not read outside docs. "An unknown only research can close" is defined below to cover both an unfamiliar area of the repo and an outside fact.

## Solution

### Approaches considered

| # | Approach | Tradeoff |
|---|---|---|
| A | Keep the WORKFLOW.md matrix as the source and teach readers to also read per-repo overrides from `.kit.toml` | Two sources for one fact; the override would patch a markdown table parse |
| B | Move the lane-to-phase map into `kit.toml` as `[lane.<name>]` data, read by the one reader that already owns it (`gate-ledger.sh`), keep the WORKFLOW.md matrix as a human view pinned equal by a test | One source; the prose table can drift, so a test pins it |
| C | Generate the WORKFLOW.md matrix from `kit.toml` at build time | No drift, but adds a generator step to a doc that is read by people, and `test-meta.sh` already pins projections by check, not by generation |

For the light default, two approaches:

| # | Approach | Tradeoff |
|---|---|---|
| D | `classify` keeps returning `full`, and each caller decides whether to treat it as a suggestion | Every caller (assign, dispatch, execute) changes; easy to miss one |
| E | `classify` returns the default lane and prints a one-line `LANE-SUGGEST` on stderr; a separate `floor` verb returns `full` only from diff paths | Callers keep parsing one word on stdout; the tests that pin `full` for keyword text change on purpose |

### Chosen approach + why

B and E. B keeps one reader (`gate-ledger.sh`) and one source (`kit.toml`), and the test pin gives the prose table the same guard the kit already uses for doc projections. E moves the safety from words in a task title to files in the diff, which is where the risk is. A spec that says "normal" but ships a migration still meets full-lane gates at push.

Rejected: A keeps the markdown parse as the source of truth. C adds a build step nobody runs by hand. D spreads one decision across three callers.

### Extensibility & boundaries

- Load-bearing dimension: the number of lanes and phases. A new phase is one name added to the lane arrays and one row in the WORKFLOW.md view. A new lane name stays with the existing `lanes.d` drop-in (`lib/gate/gate-ledger.sh:495-505`); this spec does not let a repo invent lanes.
- Units: (1) the lane reader in `gate-ledger.sh`, (2) the suggestion and floor in `lane-classify.sh`, (3) the floor call in `hooks/ship-gate.sh`, (4) the depth reader `lib/spec/spec-depth.sh`, (5) prose that asks "does this phase run" instead of "is this the full lane".

## Picture

```
 task text ----> lane-classify classify ----> stdout: tiny|normal|bug|backfill
                         |                     (never full from words alone)
                         +--> stderr: LANE-SUGGEST: full (<flags>)
                                   |
                                   v
                   operator assigns full? --yes--> gate-ledger start --amend <rid> full
                                   | no
                                   v
                         run continues on the lighter lane

 kit.toml [lane.<name>]      (kit root, then operator overlay)
 .kit.toml [lane.<name>]     (project; applies only when committed and clean)
          \                   /
           v                 v
        gate-ledger.sh lane reader  ----> required / plan / check / progress / descent / plan-record
          |                                     ^
          | dropped phases -> "skipped" GATE    |
          v   lines at `start`                  |
        run ledger                              |
                                                |
 push -> hooks/ship-gate.sh --> check <spec Lane> <rid>  (as today)
                  |
                  +--> lane-classify floor <root> <base>   (diff paths + added lines)
                          | hit: migration | auth | secret | data loss
                          v
                    gate-ledger check full <rid> --kit-lanes   (project overrides ignored)
                          | missing gate -> exit 2 (BLOCKED)

 spec header "Depth: <level> (<reason>)" --> spec-depth.sh level|check
      standard   : 0 research agents, no test-plan review team
      research   : /kit:spec step 2 sends the research agents
      blind-spot : /kit:test-plan-review-team runs; /kit:test-write needs SOLID
      spec-validate Reviewer 4: deeper level with no named reason = CRITICAL
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Data model (decided first, hardest to change later)

Lane data in `kit.toml`, one-line arrays only, phase keys as `normalize_phase` prints them (`lib/gate/gate-ledger.sh:109-124`):

```toml
[lane.tiny]
phases = ["build", "review"]
light  = ["build", "review"]

[lane.normal]
phases = ["think", "spec", "validate", "design-record", "test-plan", "build", "review", "docs", "ship"]
light  = ["think", "validate", "design-record", "test-plan", "review", "docs"]

[lane.full]
phases = ["think", "design", "design-critique", "ui-design", "spec", "validate", "design-record", "test-plan", "build", "review", "docs", "ship", "reflect"]
light  = ["ui-design"]

[lane.bug]
phases = ["test-plan", "build", "review", "ship", "debug"]
light  = ["test-plan", "ship"]

[lane.backfill]
phases = ["think", "spec", "validate", "review", "docs"]
light  = ["think", "spec", "validate", "review"]

[lanes]
default          = "normal"   # the lane classify returns when no rule picks another
extra_hard_paths = ""         # ERE over changed paths; ADDS to the built-in hard paths, never removes
```

Meaning: a phase in `phases` and not in `light` is required (today's `measure-twice`); in both is light (`run-lite`); absent is skipped. Array order is the plan order. These values reproduce `docs/WORKFLOW.md:420-435` exactly (baseline in `## Grounding`).

Depth line in the spec header, directly under `Lane:`:

```
Depth: <standard|research|blind-spot|research+blind-spot> (<reason>)
```

- `research` needs the reason to name the unknown: a fact the author cannot settle by reading the code in front of them or running one command.
- `blind-spot` needs the reason to name a failure mode the author expects not to see alone.
- "Importance is not the test." A reason that only says the work matters (important, critical, risky, core, complex) does not earn a deeper level.

### Diagram

See `## Picture`.

### ADR link(s)

This reverses the "when in doubt, heavier" posture that `docs/WORKFLOW.md:62-69` and ADR-0024 (`docs/decisions/0024-gate-ledger-and-ship-enforcement.md`) assume. TASK-8 writes the next ADR (0037 today; take the next free number at build time) recording the reversal and the diff-keyed floor that replaces keyword escalation.

### Boundaries & failure modes

Out of bounds: the proof gate's `stateful` class (`lib/gate/proof-ledger.sh:77-116`), which has its own over-fire problem (108 overrides in 4.5 days, `docs/research/2026-09-29-openrig-absorption.md:58`); model tiers and review round counts inside a phase (`commands/spec.md:294`, `commands/review-team.md:355`). See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

| Surface | Change |
|---|---|
| `gate-ledger.sh required\|plan\|check\|progress\|descent\|plan-record` | Read lane data from `kit.toml` layers instead of the WORKFLOW.md table. Output byte-identical for the five shipped lanes with no overrides |
| `gate-ledger.sh check <lane> <rid> --kit-lanes` | New flag: ignore the project `.kit.toml` layer (kit root and operator overlay only). Used by the hard-path floor |
| `gate-ledger.sh start <rid> <lane> ...` | Also writes one `\| GATE \| <phase> \| skipped \| repo lane override (.kit.toml)` line per phase the project override dropped from the kit lane |
| `lane-classify.sh classify\|explain\|check` | stdout: never `full` from text alone; default lane from `[lanes] default`. stderr: one `LANE-SUGGEST: full (<flags>)` line when a hard flag or 4+ soft flags hit. `explain` adds `suggest: full (<flags>)`. With `--files`, returns `full` when a file hits a hard path |
| `lane-classify.sh escalate <cur> <spec>` | Prints `HOLD <cur>` on stdout plus the stderr `LANE-SUGGEST` line when the spec text hits a full flag; still prints `ESCALATE tiny -> normal\|bug` when that applies. `commands/execute.md:42-45` already treats `HOLD` as "continue" |
| `lane-classify.sh floor <root> [<base>]` | New verb. Prints `full <kind>: <path>` for the first hard-path hit, else nothing. Exit 0 always. Kinds: `migration`, `auth`, `secret`, `data-loss`, `extra` |
| `lib/spec/spec-depth.sh level\|check <spec>` (+ `spec.sh depth` forwarder) | `level` prints the level (`standard` when the line is missing, with a stderr note). `check` exits 1 when a deeper level has an empty reason or a reason made only of importance words |

Built-in hard paths (case-insensitive ERE over changed paths, constants in `lane-classify.sh`, not config, so no file can remove them):

| Kind | Pattern |
|---|---|
| migration | `(^\|/)(migrations?\|migrate)/\|(^\|/)schema\.(sql\|rb\|prisma)$` |
| auth | `(^\|/)(auth\|oauth\|authn\|authz\|rbac\|permissions?\|sessions?)(/\|\.[a-z]+$)\|(^\|/)[^/]*(login\|password\|passwd\|jwt)[^/]*$` |
| secret | `(^\|/)\.env(\.(local\|dev\|development\|prod\|production\|staging\|test))?$\|(^\|/)secrets?/\|\.(pem\|key\|p12\|pfx)$\|(^\|/)[^/]*credentials?[^/]*$` |
| data-loss | an ADDED line in a non-doc file matching `drop (table\|column\|database\|schema)\|truncate table`, or `delete from` with no `where` on the same line |

Invariants:

- No project `.kit.toml` can lower the hard-path floor. The floor reads kit-root and operator lane data only (`--kit-lanes`), and `extra_hard_paths` only adds.
- A project lane override applies only when `.kit.toml` is tracked and has no diff against HEAD, the same rule as `lib/gate/gate-policy.sh:44-51`. Otherwise the reader ignores it and prints one stderr line.
- A project override naming an unknown phase is ignored for that lane (kit lane used) with one stderr line. A typo never drops a phase silently.
- A value that is not a one-line `[...]` array fails closed: the lane counts as unknown, and `check` refuses (`lib/gate/gate-ledger.sh:472-476`).
- `ship-gate.sh` stays a hook that never reads config itself. It calls `lane-classify.sh` and `gate-ledger.sh`, as it already calls `gate-policy.sh` (`hooks/ship-gate.sh:81-94`).

### Data model changes

`kit.toml` gains `[lane.tiny]` ... `[lane.backfill]` and `[lanes]`. The reader calls `_kit_toml_get <file> lane.<name> phases` directly, because `kit_config_get` splits the key at the first dot (`lib/config/kit-config.sh:63-73`) and cannot address `lane.normal.phases`. `lib/config/module-registry.md` gains rows for the new keys.

### API changes

None outside the verbs above.

### UI changes

Two new stderr lines: `LANE-SUGGEST: full (<flags>); default stays <lane>; the operator assigns full with: gate-ledger.sh start --amend <rid> full ...`, and the ship-gate block text `BLOCKED: ship-gate. This diff touches a hard path (<kind>: <path>); the full lane's gates apply whatever the spec's Lane says:`.

### Infrastructure changes

None. `install.sh` already copies every `kit.toml` section except `[modules]` into the install (`kit.toml:9-12`).

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: Capture the baseline, then add the lane data. Before any edit, write `for l in tiny normal full bug backfill; do bash lib/gate/gate-ledger.sh plan $l; bash lib/gate/gate-ledger.sh required $l; done > docs/verification/lanes-as-data/plan-baseline.txt` and commit it. Add the `[lane.*]` and `[lanes]` blocks to `kit.toml` with status tags, and rows to `lib/config/module-registry.md`. AC: the baseline file exists in a commit older than the reader change; `bash tests/test-config-registry.sh` passes.
- [ ] TASK-2: Replace `matrix_for_lane` (`lib/gate/gate-ledger.sh:126-145`) with a lane-data reader over the three config layers, with the committed-and-clean rule, unknown-phase rejection, one-line-array check, and the `--kit-lanes` flag on `check`. `required`, `plan`, `check`, `progress`, `descent`, `plan-record` call it. `start` writes the skipped lines for dropped phases. Update the header comment (`:4-8`) and the unknown-lane messages that name the WORKFLOW matrix. AC: `diff` against the TASK-1 baseline is empty; `grep -c matrix_for_lane lib/gate/gate-ledger.sh` is 0.

### Phase 2: Core

- [ ] TASK-3: Light default in `lib/classify/lane-classify.sh`. `classify_core` stops returning `full` from text; it sets `SUGGEST` and returns `[lanes] default`. Narrow three regexes: `token` to `(auth|access|refresh|api|bearer|session) token|token (leak|rotation|storage|refresh)`; drop the bare `\bqueue(s)?\b`; `\brole(s)?\b` to `role[s]? (check|permission|grant|assignment)|role-based|rbac`. `escalate` prints `HOLD` plus the suggestion for text-only full hits. Update `lane_rank` comment (`:193-196`). AC: the four known false hits classify `normal`; "token count column", "queue timeout", and "user role label" print no suggestion; "webhook retry log line" prints `LANE-SUGGEST: full (external-provider)`.
- [ ] TASK-4: Add the `floor` verb with the built-in hard paths and `[lanes] extra_hard_paths`. `--files` on `classify` uses the same hard-path test, replacing the `lib/|hooks/` rule (`:89-102`) as the path to `full`; a `lib/` or `hooks/` edit becomes a `kit-machinery` suggestion. AC: `floor` prints `full migration: db/migrations/0001_users.sql` on a fixture; prints nothing on a `src/`-only fixture.
- [ ] TASK-5: Wire the floor into `hooks/ship-gate.sh` after the lane check (`:279-296`): when `floor` prints a hit, run `gate-ledger.sh check full "$SLUG" --kit-lanes` with the project root passed in, and block on a gap with the hard-path message. Log `BLOCKED | ship-gate | <slug> (hard-path <kind>)`. Same `lane_gates` switch; fail open on a missing lib, as today. AC: the migration fixture with only normal-lane gates recorded exits 2; the same fixture without the migration file exits 0.
- [ ] TASK-6: Depth. Add `lib/spec/spec-depth.sh` (`level`, `check`) and the `depth` forwarder in `lib/spec/spec.sh`. `commands/spec.md`: `Depth:` line in the template under `Lane:`; Step 1 decides the level; Step 2 sends the research agents only when the level includes `research`, and records `gate-ledger.sh action <rid> "depth=<level> research_agents=<N>"`. `commands/spec-validate.md` Reviewer 4: run `spec-depth.sh check`; exit 1 is CRITICAL; a missing `Depth:` line is a warning. `commands/test-plan.md`: point at `/kit:test-plan-review-team` only when the level includes `blind-spot`. `commands/test-write.md` Step 2: the SOLID requirement applies only when the level includes `blind-spot` or a critique section exists. AC: `spec-depth.sh check` exits 1 on `Depth: research ()` and on `Depth: research (this is important)`, 0 on `Depth: research (the provider's retry schedule is not documented anywhere we have)`.

### Phase 3: Polish

- [ ] TASK-7: Prose. Replace `docs/WORKFLOW.md:62-69` with the light-default rule (below). Same rule at `AGENTS.md:66-67`, `examples/hello-spec/AGENTS.md:38`, `commands/assign.md:112,127`. `commands/assign.md` records `gate-ledger.sh action <rid> "lane-suggest full flags=<flags> taken=<yes|no>"` when a suggestion printed. Phase-applicability lines that name a lane instead of asking the lane data: `commands/spec.md:274-281` (design pass runs when `plan <lane>` lists `design-critique`), `commands/assign.md:59,177,180,189` (spec comes next when `plan <lane>` lists `spec`). WORKFLOW.md: the matrix (`:409-435`) becomes "the human view of `kit.toml [lane.*]`, pinned by `tests/test-lanes-data.sh`"; the test-plan review row (`:339`) and cycle row (`:145`) say "when Depth includes blind-spot"; the gate-ledger section (`:500-502`) names `kit.toml` as the source. AC: `grep -c 'take the heavier one'` over those four files is 0.
- [ ] TASK-8: ADR for the reversal; the kit repo's own `.kit.toml` gets `[lanes] extra_hard_paths = "^hooks/|^lib/gate/"` so kit enforcement edits keep full-lane gates; `docs/MANUAL.md` and `docs/architecture.md` rows the doc-projection check asks for; regenerate `docs/FEATURES.md`. AC: `bash lib/gate/doc-projection-check.sh .` and `bash lib/registry/feature-registry.sh check docs/FEATURES.md` pass.

The new light-default rule text (WORKFLOW.md, and the one-line form elsewhere):

> Default to `normal`. The classifier prints a one-line suggestion when the task text matches a full-lane trigger; the agent may propose the full lane in one sentence and continues on the lighter lane until the operator assigns it. The ship-gate still applies the full lane's gates to any diff that touches a hard path (migrations, auth, secrets, data loss), whatever the spec's `Lane:` says. Moving an assigned lane down stays a Pause-if decision (`AGENTS.md:179`).

## After state

- [ ] `kit.toml` holds the five lanes as data. (Today: `docs/WORKFLOW.md:420-435` is parsed at run time.)
- [ ] `bash lib/classify/lane-classify.sh classify "add token count column"` prints `normal`. (Today: `full`.)
- [ ] A normal-lane spec whose diff adds `db/migrations/0001_users.sql` is blocked at push until full-lane gates are recorded. (Today: passes with normal-lane gates.)
- [ ] A committed `.kit.toml` that drops `review` from `normal` shows `| GATE | review | skipped | repo lane override (.kit.toml)` in the run ledger after `start`.
- [ ] A spec with `Depth: standard` gets zero research agents, checkable by the `depth=standard research_agents=0` action line.
- [ ] No kit doc says "take the heavier one".

## Acceptance Criteria (global)

Each criterion names its exact check. Fixture helpers live in `tests/test-lanes-data.sh` (new).

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | Shipped lane data reproduces today's matrix | `for l in tiny normal full bug backfill; do bash lib/gate/gate-ledger.sh plan $l; bash lib/gate/gate-ledger.sh required $l; done \| diff - docs/verification/lanes-as-data/plan-baseline.txt` | empty diff, exit 0 |
| AC2 | The reader no longer parses WORKFLOW.md | `grep -cE 'matrix_for_lane\|GATE_LEDGER_WORKFLOW' lib/gate/gate-ledger.sh` | `0` |
| AC3 | WORKFLOW.md view matches the data | `bash tests/test-lanes-data.sh workflow-view` | `PASS` |
| AC4 | Committed override drops a phase and the ledger shows it | `bash tests/test-lanes-data.sh override-drop-review` | plan has no `review`; ledger has the skipped line |
| AC5 | Uncommitted override is ignored | `bash tests/test-lanes-data.sh override-uncommitted` | plan still lists `review`; stderr names the rule |
| AC6 | Unknown phase in override is ignored | `bash tests/test-lanes-data.sh override-typo` | plan equals the kit lane; stderr names the phase |
| AC7 | Four false hits classify normal | `for t in "add token count column" "add queue timeout" "add webhook retry log line" "add user role label"; do bash lib/classify/lane-classify.sh classify "$t"; done 2>/dev/null \| sort -u` | `normal` |
| AC8 | Keyword hit is a suggestion only | `bash lib/classify/lane-classify.sh classify "add a users table migration" 2>&1 >/dev/null` | `LANE-SUGGEST: full (data-model)...`; stdout `normal` |
| AC9 | File fact still returns full | `bash lib/classify/lane-classify.sh classify --files "db/migrations/0001_users.sql" "add a users table migration"` | `full` |
| AC10 | Spec-to-build holds and suggests | `bash tests/test-lanes-data.sh escalate-suggest` | stdout `HOLD normal`; stderr `LANE-SUGGEST` |
| AC11 | Migration diff blocks at ship | `bash tests/test-lanes-data.sh ship-migration-blocks` | hook exit 2, stderr names `hard path (migration` |
| AC12 | Project cannot hollow full to pass the floor | `bash tests/test-lanes-data.sh ship-hollow-full-override` | hook exit 2 |
| AC13 | Data-loss line blocks; the same line in a doc does not | `bash tests/test-lanes-data.sh ship-data-loss` | code file: exit 2; `.md`: exit 0 |
| AC14 | Depth check | `bash tests/test-lanes-data.sh depth-check` | exit 1 empty reason, exit 1 importance-only, exit 0 named unknown, `standard` on missing line |
| AC15 | Rule text replaced | `grep -c 'take the heavier one' docs/WORKFLOW.md AGENTS.md examples/hello-spec/AGENTS.md commands/assign.md` | every count `0` |
| AC16 | No regressions | `bash tests/test-hooks.sh && bash tests/test-meta.sh && bash tests/test-lane-classify.sh && bash tests/test-lane-escalation.sh && bash tests/test-lane-deescalate.sh && bash tests/test-gate-ledger-plan-record.sh && bash tests/test-ship-gate-fail-closed.sh && bash tests/test-config-registry.sh && bash lib/config/kit-config.sh selftest` | all exit 0 |

## Verification

```bash
bash tests/test-lanes-data.sh
for l in tiny normal full bug backfill; do bash lib/gate/gate-ledger.sh plan $l; bash lib/gate/gate-ledger.sh required $l; done | diff - docs/verification/lanes-as-data/plan-baseline.txt
bash tests/test-hooks.sh && bash tests/test-meta.sh && bash tests/test-lane-classify.sh && bash tests/test-lane-escalation.sh && bash tests/test-lane-deescalate.sh && bash tests/test-gate-ledger-plan-record.sh && bash tests/test-ship-gate-fail-closed.sh && bash tests/test-config-registry.sh && bash lib/config/kit-config.sh selftest
```

## Test plan

Date: 2026-09-29

| Case | Kind | Covers | Proof |
|---|---|---|---|
| Parity: plan and required for all five lanes equal the baseline | positive | AC1 | AC1 command |
| "add token count column" classifies normal, no suggestion | negative control (the old wrong answer was full) | AC7 | `bash lib/classify/lane-classify.sh classify "add token count column" 2>&1` is exactly `normal` |
| Migration diff on a `Lane: normal` spec with spec, build, ship recorded | negative control (must still block) | AC11 | `ship-migration-blocks`: fixture repo, `docs/verification/README.md` marker, `lane_gates = true`, ledger with normal gates, `db/migrations/0001_users.sql` added; feed `{"tool_input":{"command":"git push -u origin feat/x"}}` to `hooks/ship-gate.sh`; expect exit 2 |
| Same fixture, then `gate-ledger.sh override` for each missing full gate | positive | AC11 | same hook call exits 0 |
| Same fixture without the migration file | positive (floor quiet) | AC11 | exit 0 |
| Committed `.kit.toml` drops `review` from `normal` | negative control (phase must show skipped) | AC4 | `override-drop-review`: `plan normal` has no `review`; after `start`, `show <rid>` has `\| GATE \| review \| skipped \| repo lane override (.kit.toml)` |
| Same override, uncommitted | negative control (must not apply) | AC5 | `plan normal` lists `review` |
| Override `phases = ["reveiw", ...]` | negative control (typo must not drop) | AC6 | `plan normal` equals the kit lane |
| Committed `.kit.toml [lane.full] phases = ["build"]` plus a migration diff | negative control (floor ignores project) | AC12 | hook exit 2 |
| `DROP TABLE users;` added to `app/cleanup.py` | negative control | AC13 | hook exit 2 |
| `DROP TABLE users;` added to `docs/notes.md` only | positive | AC13 | hook exit 0 |
| `.env.example` changed | positive (not a secret path) | AC11 | `floor` prints nothing |
| Spec with `Depth: standard` run through `/kit:spec` step 2 | negative control (zero research agents) | After state | ledger `action` line reads `depth=standard research_agents=0`; `ls docs/research/ \| grep -c <slug>` is `0` |
| `Depth: research ()` and `Depth: research (this is important)` | negative control | AC14 | `spec-depth.sh check` exit 1 |
| `lane_gates = false` committed in the fixture | positive (switch honored) | AC11 | hook exit 0, `OFF-BY-CONFIG` logged |
| Lane value `phases = ["spec",` with no closing bracket | negative control (fail closed) | Invariants | `check normal <rid>` exits 1 with "unknown lane" |

Dry trace for the key negative control (AC11): the fixture commits `db/migrations/0001_users.sql`; `ship-gate.sh` passes `:279`, `check normal` passes because spec, build, ship are recorded; the new block calls `lane-classify.sh floor <root> <base>`, whose changed-path list includes the file and matches the migration pattern; `gate-ledger.sh check full <rid> --kit-lanes` prints `MISSING-GATE: think` and others; the hook exits 2. Removing the new block turns this case green, which is the mutation that proves the test.

## Edge Cases

1. A rename out of `migrations/` (`git mv db/migrations/x.sql tests/`): the floor lists both sides (same `--no-renames` rule as `lib/gate/proof-ledger.sh:63-73`), so it hits.
2. A spec already on `Lane: full`: the floor check runs anyway with `--kit-lanes`, so a project override that hollowed `full` cannot pass.
3. A branch with no spec: the ship-gate exits before the lane check (`hooks/ship-gate.sh:224-225`); the floor does not run. The proof gate still covers stateful diffs there.
4. `classify` with no `[lanes] default` in any layer: code default `normal`.
5. A project `.kit.toml` that sets `[lanes] extra_hard_paths` to an invalid ERE: `grep -E` errors; the floor treats the extra list as absent and prints one stderr line. Built-ins still apply.
6. `lanes.d` drop-in lanes: unchanged; they answer `plan` only (`lib/gate/gate-ledger.sh:495-505`).
7. A spec with two `Depth:` lines: `spec-depth.sh` reads the first, `check` fails with "two Depth lines".
8. `LANE-SUGGEST` for a bug-lane task that also hits a full flag: bug stays the lane; the suggestion still prints.
9. Old ledgers with `classified=full` START lines: readers unchanged; lane telemetry misfire counts drop from the change date on.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Lane data and WORKFLOW.md view drift | `tests/test-lanes-data.sh workflow-view` red | The data is the source; fix the view |
| Hard-path list misses a real risky path (for example a `db/changes/` folder) | A risky change ships on normal-lane gates; SPEC-367's escape records | `extra_hard_paths` in that repo's `.kit.toml`; widen the built-in list when two repos need the same path |
| Hard-path list over-fires (for example `session` in a UI component name) | Overrides with reason "not auth" on the floor | Narrow the pattern; the override path (`gate-ledger.sh override`) unblocks meanwhile |
| An agent edits `.kit.toml` to drop a gate for its own run | The edit is uncommitted, so the reader ignores it; once committed it is in the PR diff | Committed-and-clean rule; reviewer sees the `.kit.toml` diff |
| Installed kit.toml lacks the lane blocks (partial install) | Every `check` refuses with "unknown lane" at push | Fail closed is deliberate; `bash install.sh` restores it. Named in the migration notes |
| Operators miss the suggestion line and under-size real risk | SPEC-367 counts `lane-suggest ... taken=no` against escapes | Diff floor is the backstop; tighten only on measured escapes |

## Migration notes (existing adopted repos)

- No action needed for today's behavior on the ledger side: kit-root lane data equals today's matrix, so `required`, `plan`, and `check` answer the same.
- Behavior that does change on the next kit update: keyword-only tasks come back `normal` with a suggestion line. Repos relying on auto-full from a title now rely on the diff floor at push. Pass the change note to operators with the release.
- Specs in flight keep their `Lane:` header. Specs without `Depth:` count as `standard`; the validator warns, it does not block.
- Adopted repos carry a copy of the old `AGENTS.md` text with the "heavier" rule (`lib/adopt.sh` copies it once). SPEC-371 replaces that copy with a pointer; until then the copy is stale advisory text, and the classifier behavior is what applies.
- A repo that wants a lane changed writes `[lane.<name>] phases = [...]` (and `light`) in `.kit.toml` and commits it. Only the five kit lane names are accepted.
- Partial installs: re-run `bash install.sh` so the installed `kit.toml` has the `[lane.*]` blocks. Without them every lane-gated push is refused.

## Out of Scope

- A per-spec or per-mission lane override. The spec file is agent-written, so a per-spec phase list would be a self-waiver; the per-phase `gate-ledger.sh override` with a logged reason already covers one-off cases.
- New lane names from `.kit.toml`. The `lanes.d` drop-in stays the path.
- The proof gate's `stateful` over-fire (`lib/gate/proof-ledger.sh:112`).
- Model tier and review-round rules keyed on lane names (`commands/spec.md:294,300`, `commands/review-team.md:355`). They tune depth inside a phase, not whether a phase runs.
- `commands/execute.md` (SPEC-369). The existing `HOLD` branch already continues the run; see Siblings.
- `[role.<name>]` (D8 step two) and starter templates (SPEC-371).
- A repo knob to bring back keyword auto-escalation.

## Touches

Single files (the dispatch gate cannot prove these disjoint by prefix, so it serializes against any sibling that lists them): `kit.toml`, `.kit.toml`, `hooks/ship-gate.sh`, `docs/WORKFLOW.md`, `AGENTS.md`, `examples/hello-spec/AGENTS.md`, `commands/spec.md`, `commands/spec-validate.md`, `commands/assign.md`, `commands/test-plan.md`, `commands/test-write.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/FEATURES.md`, `tests/test-lanes-data.sh`, `tests/test-lane-classify.sh`, `tests/test-lane-escalation.sh`, `lib/config/module-registry.md`.

- lib/classify/**
- lib/gate/**
- lib/spec/**
- docs/decisions/**
- docs/verification/lanes-as-data/**

## Siblings

| Spec | Relation |
|---|---|
| SPEC-366 execution-view | Reads run ledgers and may call `gate-ledger.sh plan`; output is byte-identical with no overrides, so no dependency. With a repo override it sees the override's plan, which is correct |
| SPEC-367 ceremony-lens | Measures this change. It reads the new action lines `lane-suggest ... taken=` and `depth=<level> research_agents=<N>`. Both may touch `lib/gate/gate-ledger.sh`; this spec touches only the lane reader, `check`, and `start`. Land order: either, rebase the second |
| SPEC-369 whole-spec-dispatch | Owns `commands/execute.md`. Dependency named: `execute.md:24-45` should relay the new `LANE-SUGGEST` stderr line to the operator and drop the prose that says the spec-to-build step escalates on auth, data-model, or migration text. Until it does, `HOLD` keeps the run correct and only the prose is stale |
| SPEC-370 orca-mega-backend | No shared files. `lib/goal/mega-merge.sh` calls `gate-ledger.sh check`, whose signature only gains an optional flag |
| SPEC-371 adopt-pointer-onboarding | Consumer of `[lane.*]` for starter templates (`SPEC-371:78-80`). Its pointer text should say "default normal; the diff floor applies at push" instead of any heavier rule |

## Decision Log

- DEC-1: Hard paths are code constants plus an add-only config list, because the brief requires them to hold regardless of overrides. Rejected: a `kit.toml` list (a project layer could replace it).
- DEC-2: The floor runs `check full --kit-lanes`, ignoring the project layer. Rejected: using the resolved `full` lane (a committed override could hollow it).
- DEC-3: `light` is a second array next to `phases`, because the matrix has three states. Rejected: suffix markers inside one array (`"think:light"`), harder to read and to validate.
- DEC-4: The floor rides the `lane_gates` switch. Rejected for now: always on (see open question 1).
- DEC-5: `escalate` prints `HOLD` plus a suggestion instead of a new stdout word, so `commands/execute.md` needs no edit in this spec.
- DEC-6: Depth levels use plain words (`standard`, `research`, `blind-spot`), not the P0 to P4 scale in the research record.
- DEC-7: Keep the WORKFLOW.md matrix as a pinned human view. Rejected: deleting it (every doc link to it breaks) and generating it (a build step for prose).

## Grounding

- Baseline plans, run today in this worktree: `for l in tiny normal full bug backfill; do bash lib/gate/gate-ledger.sh plan $l; done`. Excerpt: normal = `grill intake; think lite; spec required; validate lite; design-record lite; test-plan lite; build required; review lite; docs lite; ship required`; full = 13 phases, all required except `ui-design lite`; bug = `test-plan lite; build required; review required; ship lite; debug required`; backfill = `think lite; spec lite; validate lite; review lite; docs required`; tiny = `build lite; review lite`. `required` prints: tiny none; normal `spec build ship`; full `think design design-critique spec validate design-record test-plan build review docs ship reflect`; bug `build review debug`; backfill `docs`. The `[lane.*]` arrays in `## Design` are written from this output.
- Classifier today: `bash lib/classify/lane-classify.sh explain "<t>"` for the four false hits returns `full` with flags `audit-security`, `external-provider`, `external-provider`, `auth`.
- Override recount: `D=$(bash -c 'source lib/telemetry/kit-log-dir.sh && kit_resolve_log_dir'); for p in think reflect design design-critique test-plan; do grep -h "| GATE | $p | override" "$D"/runs/*.log | wc -l; done` over 149 ledgers: 21, 14, 15, 14, 6.
- Config shape: `_kit_toml_get` strips brackets and spaces from a header (`lib/config/kit-config.sh:45-47`), so `[lane.normal]` reads as section `lane.normal`; it returns the raw one-line value, so `["a", "b"]` comes back intact.
- Gate switch on this machine: `bash lib/gate/gate-policy.sh enabled lane_gates .` exits 0 (operator overlay).
- This spec's own classification: `bash lib/classify/lane-classify.sh explain "<this spec's summary>"` returns `full`, flag `kit-machinery`. It edits `hooks/ship-gate.sh` and `lib/gate/`.

## Open questions

1. Should the hard-path floor run even where `lane_gates = false`? Today that switch is off at the kit root (`kit.toml:113`), so repos without the operator overlay get no floor. Running it always would make it a safety gate, which `lib/gate/gate-policy.sh:22-23` reserves for destructive git and credential leaks.
2. Should the floor also run on spec-less pushes (`hooks/ship-gate.sh:224-225` exits first)? Freeform work is where an unreviewed migration is most likely, but no lane exists to compare against.
3. Are `research` agents the right tool for an outside unknown? They read the repo (`commands/spec.md:31-34`). An outside fact (a provider's behavior) may need `/kit:get-api-docs` or a web pass instead.
4. `webhook` stays a full flag, so "add webhook retry log line" still prints a suggestion. Keep it (the provider surface is real), or narrow it like `token` and `queue`?
