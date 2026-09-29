# Spec: lanes as data and a light default lane
Generated: 2026-09-29
Status: DRAFT
Lane: full
References: `lib/gate/gate-policy.sh:40-52` (imitate its committed-and-clean rule for a project file that weakens a gate); `lib/classify/lane-classify.sh:86-102` (imitate its file-fact check for the new hard-path floor); `docs/research/2026-09-29-openrig-absorption.md:99-105,206-213` (designs D1 and D8 step one). The depth line (D2) moved to SPEC-372.

## Problem

The kit sizes most work heavier than it needs, and the lane rules live in prose and regex, so changing them means rewriting prose.

| Symptom | Evidence |
|---|---|
| The rule says "When in doubt between two lanes, take the heavier one" | `docs/WORKFLOW.md:62-63`, repeated at `AGENTS.md:66-67`, `examples/hello-spec/AGENTS.md:38`, `commands/assign.md:112` |
| One keyword turns a task into the full lane automatically | `lib/classify/lane-classify.sh:147-168`: any hard-flag regex hit returns `full` |
| Four known false hits | Measured today: "add token count column" = full (flag `audit-security`, word `token`, `lane-classify.sh:56`); "add queue timeout" = full (`external-provider`, `\bqueue(s)?\b`, `:57`); "add webhook retry log line" = full (`external-provider`, `webhook`, `:57`); "add user role label" = full (`auth`, `\brole(s)?\b`, `:54`) |
| Full-lane phases get overridden, not run | Research record: think / reflect / design phases overridden 17 / 11 / 11 / 10 times across about 108 run ledgers (`docs/research/2026-09-29-openrig-absorption.md:64`). Recount today across 149 ledgers: think 21, reflect 14, design 15, design-critique 14, test-plan 6 (command in `## Grounding`) |
| The spec-to-build step also escalates on keywords | `lib/classify/lane-classify.sh:254-277` (`escalate`), acted on at `commands/execute.md:36-41` |
| Lanes are prose, not data | `lib/gate/gate-ledger.sh:128-145` parses the markdown table in `docs/WORKFLOW.md:420-435` at run time; no repo can change a lane without editing kit prose |

The principle: lighten the middle, keep the edges. The fresh-context spec validator caught a problem in 19 of 35 runs (`docs/research/2026-09-29-openrig-absorption.md:57`) and the security review lens caught a leak three other stages missed (`:59`). Both stay, and on the normal lane they become required.

Premise corrections found while checking the brief:

1. The ship-gate has no auth, migration, secret, or data-loss diff paths today. It checks only the lane the spec declares (`hooks/ship-gate.sh:250,282`). The diff-keyed check that exists is the proof gate's `stateful` class (`lib/gate/proof-ledger.sh:112`), and it asks for a proof record, not full-lane gates. Today the only thing that puts a migration on the full lane is the keyword classifier at intake. This spec therefore builds a diff-keyed hard-path floor in the same change that turns keyword escalation into a suggestion.
2. The lane gate is opt-in: `lane_gates = false` at the kit root (`kit.toml:113`). It is on for this operator through the overlay (`~/.config/dwarves-kit/kit.toml [gate] lane_gates = true`). The floor follows the same switch.
3. `kit_config_get` splits a key at the FIRST dot (`lib/config/kit-config.sh:65,84`), so `lane.normal.phases` resolves as section `lane`, key `normal.phases`, and misses. No caller passes a three-part key today (checked by grep), so a last-dot split is safe.

### What the diff floor catches, and what it does not

The full-lane triggers are listed at `docs/WORKFLOW.md:58`. The floor sees file paths and added lines, so it catches only triggers that leave a path or a line signature.

| Trigger (`WORKFLOW.md:58`) | Caught by the diff floor? |
|---|---|
| migration | Yes: migration folders, alembic, drizzle, Liquibase changelogs, schema files |
| data loss | Partly: added destructive SQL lines and `deleteMany({})` in code files |
| data model | Partly: through migration and schema files. An ORM model edit with no migration is human-only |
| auth | Partly: auth, session, login, password, and jwt paths |
| audit/security | Partly: secret files only (`.env`, keys, credentials) |
| hooks | Partly: `.github/workflows/` and `.kit.toml` everywhere; the kit's own enforcement code through its `extra_hard_paths`. Hook code in adopted repos is human-only |
| authz | Human-only: role and permission checks live in ordinary handlers |
| API contract | Human-only |
| external provider | Human-only |
| weakens validation | Human-only |

The net for the human-only rows: on the normal lane, `validate` (a fresh-context reader of the spec) and `review` become required, and a keyword suggestion leaves a ledger line that the ship-gate repeats as an advisory when the run did not take it. Repos with `lane_gates = false` lose both the automatic full lane (keywords no longer escalate) and the floor. They keep the proof gate and the safety gates, nothing more.

## Solution

### Approaches considered

| # | Approach | Tradeoff |
|---|---|---|
| A | Keep the WORKFLOW.md matrix as the source and teach readers to also read per-repo overrides from `.kit.toml` | Two sources for one fact; the override patches a markdown table parse |
| B | Move the lane-to-phase map into `kit.toml` as `[lane.<name>]` data, read by the one reader that already owns it (`gate-ledger.sh`), keep the WORKFLOW.md matrix as a human view pinned equal by a test | One source; the prose table can drift, so a test pins it |
| C | Generate the WORKFLOW.md matrix from `kit.toml` at build time | No drift, but adds a generator step to a doc people read, and the kit already pins projections by check |

For the light default:

| # | Approach | Tradeoff |
|---|---|---|
| D | `classify` keeps returning `full`, and each caller decides whether to treat it as a suggestion | Every caller (assign, dispatch, execute) changes; easy to miss one |
| E | `classify` returns the default lane and prints a one-line `LANE-SUGGEST`; a separate `floor` verb returns `full` only from diff paths | Callers keep parsing one word on stdout; the tests that pin `full` for keyword text change on purpose |

### Chosen approach + why

B and E. B keeps one reader and one source, and the test pin gives the prose table the same guard the kit uses for other doc projections. E moves the safety from words in a task title to files in the diff, where the risk is. Required validate and review on normal cover the triggers the diff cannot see.

Rejected: A keeps the markdown parse as the source of truth. C adds a build step nobody runs by hand. D spreads one decision across three callers.

### Extensibility & boundaries

- Load-bearing dimension: the number of lanes and phases. A new phase is one name in the lane arrays and one row in the WORKFLOW.md view. New lane names stay with the `lanes.d` drop-in (`lib/gate/gate-ledger.sh:495-505`); a repo cannot invent lanes here.
- Units: (1) the lane reader in `gate-ledger.sh`, (2) the suggestion and `floor` in `lane-classify.sh`, (3) the floor call and suggestion advisory in `hooks/ship-gate.sh`, (4) the last-dot fix in `lib/config/kit-config.sh`, (5) prose that asks "is this phase in the lane's plan" instead of "is this the full lane".

## Picture

```
 task text --> lane-classify classify [--rid] --> stdout: tiny|normal|bug|backfill
                        |                           (never full from words alone)
                        +--> stderr: LANE-SUGGEST: full (<flags>)
                        +--> ledger: | ACTION | lane-suggest full flags=<f>
                                  |
                  operator assigns full? --yes--> gate-ledger start --amend <rid> full
                                  | no
                                  v
                        run continues on the lighter lane
                        (normal: validate + review required)

 $KIT_ROOT/kit.toml [lane.*]        kit root (pinned to the install)
 ~/.config/dwarves-kit/kit.toml     operator overlay
 <repo>/.kit.toml [lane.*]          project; applies only when committed and clean
          \          |          /
           v         v         v
        gate-ledger.sh lane reader --> required / plan / check / progress / descent / plan-record
                 |
                 +--> `start`: dropped phases -> | GATE | <p> | skipped | repo lane override

 push --> hooks/ship-gate.sh
            |-- no spec: floor hit -> [advisory] only (no lane to compare)
            |-- check <spec Lane> <rid>                        (as today)
            |-- floor <root> <base> hit (migration|auth|secret|ci|kit-config|data-loss|extra)
            |        -> check full <rid> --kit-lanes  -> gap: exit 2 BLOCKED
            '-- ledger has lane-suggest full, lane != full -> [advisory] suggestion not taken
            (all of it under [gate] lane_gates; off = none of it)
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
light  = ["think", "design-record", "test-plan", "docs"]

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

Meaning: a phase in `phases` and not in `light` is required (today's `measure-twice`); in both is light (`run-lite`); absent is skipped. Array order is the plan order. An override that sets `phases` and omits `light` has no light phases: every listed phase is required. `light` names not in `phases` are ignored.

Every value above reproduces `docs/WORKFLOW.md:420-435` exactly, except two deliberate cells: normal `validate` and normal `review` move from light to required. TASK-2 lands the reader with those two still light (a pure refactor, byte-identical output), and TASK-3 flips them in a separate commit.

### Diagram

See `## Picture`.

### ADR link(s)

This reverses the "when in doubt, heavier" posture that `docs/WORKFLOW.md:62-69` and ADR-0024 (`docs/decisions/0024-gate-ledger-and-ship-enforcement.md`) assume, and reverses the "Validate / normal = run-lite" call at `docs/WORKFLOW.md:451-457`. TASK-9 writes the next ADR (0037 today; take the next free number at build time).

### Boundaries & failure modes

Out of bounds: the proof gate's `stateful` class (`lib/gate/proof-ledger.sh:77-116`), which has its own over-fire problem (108 overrides in 4.5 days, `docs/research/2026-09-29-openrig-absorption.md:58`); model tiers and review round counts inside a phase (`commands/spec.md:294`, `commands/review-team.md:355`); the spec depth line (SPEC-372). See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

| Surface | Change |
|---|---|
| `gate-ledger.sh required\|plan\|check\|progress\|descent\|plan-record` | Read lane data from the config layers instead of the WORKFLOW.md table |
| `gate-ledger.sh check <lane> <rid> --kit-lanes` | New flag: ignore the project layer (kit root and operator overlay only). Used by the floor |
| `gate-ledger.sh start <rid> <lane> ...` | Also writes one `\| GATE \| <phase> \| skipped \| repo lane override (.kit.toml)` line per phase the project override dropped |
| `lane-classify.sh classify\|explain\|check [--rid <rid>]` | stdout: never `full` from text alone; returns `[lanes] default`. On a hard flag or 4+ soft flags: one stderr `LANE-SUGGEST: full (<flags>)` line, and an `action <rid> "lane-suggest full flags=<flags>"` ledger line when `--rid` is given or `gate-ledger.sh rid` resolves (best effort, never fails the verb). `explain` adds `suggest: full (<flags>)`. With `--files`, returns `full` when a file hits a hard path |
| `lane-classify.sh escalate <cur> <spec>` | Prints `HOLD <cur>` plus the suggestion for text-only full hits; still prints `ESCALATE tiny -> normal\|bug` when that applies. `commands/execute.md:42-45` already treats `HOLD` as "continue" |
| `lane-classify.sh floor <root> [<base>]` | New verb. Prints `full <kind>: <path>` for the first hit, else nothing. Exit 0 always |
| `kit-config.sh kit_config_get\|kit_config_get_root` | Split the dotted key at the LAST dot, so `lane.normal.phases` reads section `lane.normal`, key `phases` |

Built-in hard paths (case-insensitive ERE over changed paths, constants in `lane-classify.sh`, so no config file can remove them):

| Kind | Pattern |
|---|---|
| migration | `(^\|/)(migrations?\|migrate)/\|(^\|/)alembic/versions/\|(^\|/)drizzle/\|(^\|/)schema\.(sql\|rb\|prisma)$\|(^\|/)[^/]*changelog[^/]*\.(xml\|ya?ml\|json\|sql)$` |
| auth | `(^\|/)(auth\|oauth\|authn\|authz\|rbac\|permissions?\|sessions?)(/\|\.[a-z]+$)\|(^\|/)[^/]*(login\|password\|passwd\|jwt)[^/]*$` |
| secret | `(^\|/)\.env(\.(local\|dev\|development\|prod\|production\|staging\|test))?$\|(^\|/)secrets?/\|\.(pem\|key\|p12\|pfx)$\|(^\|/)[^/]*credentials?[^/]*$` |
| ci | `(^\|/)\.github/workflows/` |
| kit-config | `(^\|/)\.kit\.toml$` |
| data-loss | an ADDED line in a non-doc file matching `drop (table\|column\|database\|schema)\|\btruncate\s+(table\s+)?[a-z_."]+\|deleteMany\(\s*\{\s*\}\s*\)`, or `delete from` with no `where` on the same line |

Paths are listed with `--no-renames`, so both sides of a rename count (same rule as `lib/gate/proof-ledger.sh:63-73`).

Config layers:

- Kit root is pinned to `$KIT_ROOT/kit.toml`, where `$KIT_ROOT` is the install the running script lives in (`lib/gate/gate-ledger.sh:52`). The reader sets `KIT_CONFIG_ROOT="$KIT_ROOT"` for its own calls, so a stray `DWARVES_KIT` or `KIT_CONFIG_ROOT` in the environment cannot point it at another file.
- Kit root and operator overlay go through `kit_config_get_root` (last-dot fixed). The project layer is read with per-file `_kit_toml_get` only because it needs the committed-and-clean test.
- `[lanes] default` and every `[lane.<name>]` value from the project layer apply only when `.kit.toml` is tracked and has no diff against HEAD (`lib/gate/gate-policy.sh:44-51`). Otherwise the reader ignores the project layer and prints one stderr line.
- `[lanes] extra_hard_paths` only adds, so the floor takes the union of every layer, including both the working-tree and the HEAD copy of the project file. A dirty edit that deletes an entry cannot drop it.

Invariants:

- No lane override can lower the floor. The floor checks `full` with `--kit-lanes`, and `extra_hard_paths` only adds. The one way to turn the floor off is `[gate] lane_gates = false`, which turns off every lane gate, under the committed-and-clean rule gate-policy already applies.
- A project override naming an unknown phase is ignored for that lane (kit lane used), with one stderr line. A typo never drops a phase silently.
- A value that is not a one-line `[...]` array fails closed: the lane counts as unknown, and `check` refuses (`lib/gate/gate-ledger.sh:472-476`).
- `ship-gate.sh` stays a hook that never reads config itself. It calls `lane-classify.sh` and `gate-ledger.sh`, as it already calls `gate-policy.sh` (`hooks/ship-gate.sh:81-94`).

### Data model changes

`kit.toml` gains `[lane.tiny]` ... `[lane.backfill]` and `[lanes]`; `lib/config/module-registry.md` gains rows for them.

### API changes

None outside the verbs above.

### UI changes

New operator-facing lines:

- `LANE-SUGGEST: full (<flags>); default stays <lane>; the operator assigns full with: gate-ledger.sh start --amend <rid> full ...`
- `BLOCKED: ship-gate. This diff touches a hard path (<kind>: <path>); the full lane's gates apply whatever the spec's Lane says:`
- `[advisory] run '<slug>': the classifier suggested full (<flags>) and the run ships as <lane>`
- `[advisory] no spec for '<slug>', and the diff touches a hard path (<kind>: <path>); write a spec with a Lane, or record why not`

### Infrastructure changes

None. `install.sh` copies every `kit.toml` section except `[modules]` into the install (`kit.toml:9-12`).

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: Capture the baseline before any edit. `tests/test-lanes-data.sh baseline` writes `docs/verification/lanes-as-data/baseline.txt`: `plan` and `required` for all five lanes, plus `progress` and `descent` for each lane against a canned fixture ledger (fixed rid, a fixed set of `ran`, `skipped`, and one out-of-order record, under a temp `DWARVES_KIT_LOG_DIR`). Commit it. AC: the file exists in a commit older than any reader change.
- [ ] TASK-2: Fix `kit_config_get` and `kit_config_get_root` to split at the last dot (`lib/config/kit-config.sh:65,84`), add one selftest case (`lane.normal.phases`). Add the `[lane.*]` and `[lanes]` blocks to `kit.toml` with normal `validate` and `review` still light, plus the registry rows. Replace `matrix_for_lane` (`lib/gate/gate-ledger.sh:126-145`) with the lane-data reader (layers, pinned kit root, committed-and-clean, unknown-phase rejection, one-line-array check, `--kit-lanes`). `start` writes the skipped lines. Update the header comment (`:4-8`) and the unknown-lane messages. AC: `tests/test-lanes-data.sh parity` diffs empty against the baseline; `grep -c matrix_for_lane lib/gate/gate-ledger.sh` is 0; `bash lib/config/kit-config.sh selftest` passes.
- [ ] TASK-3: Flip normal `validate` and `review` to required in `kit.toml` and in the WORKFLOW.md matrix view; rewrite the non-obvious-call note (`docs/WORKFLOW.md:451-457`) and add a Review / normal note, both citing the coverage table in this spec. AC: `bash lib/gate/gate-ledger.sh required normal | tr '\n' ' '` prints `spec validate build review ship `; the parity diff shows exactly the two normal lines changed.

### Phase 2: Core

- [ ] TASK-4: Light default in `lib/classify/lane-classify.sh`. `classify_core` stops returning `full` from text; it sets the suggestion and returns `[lanes] default`. Add `--rid` and the ledger action line. Narrow four regexes: `token` to `(auth|access|refresh|api|bearer|session) token|token (leak|rotation|storage|refresh)`; drop the bare `\bqueue(s)?\b`; `\brole(s)?\b` to `role[s]? (check|permission|grant|assignment)|role-based|rbac`; `webhook` to `webhook (signature|secret|verif[a-z]*|auth[a-z]*|endpoint|handler)`. `escalate` prints `HOLD` plus the suggestion. Update the `lane_rank` comment (`:193-196`). AC: the four false hits classify `normal` and print no `LANE-SUGGEST` line; "add webhook signature check" prints `LANE-SUGGEST: full (external-provider)`.
- [ ] TASK-5: Add the `floor` verb with the built-in hard paths and the `extra_hard_paths` union. `--files` on `classify` uses the same test, replacing the `lib/|hooks/` rule (`:89-102`) as the path to `full`; a `lib/` or `hooks/` edit becomes a `kit-machinery` suggestion. AC: `floor` prints `full migration: alembic/versions/0001_users.py` on that fixture and nothing on a `src/`-only fixture.
- [ ] TASK-6: Wire `hooks/ship-gate.sh`. (a) Spec-less push (`:224-225`): if `floor` hits, print the no-spec advisory, then exit 0 as today. (b) After the lane check (`:279-296`): if `floor` hits, run `gate-ledger.sh check full "$SLUG" --kit-lanes` with the project root passed, block on a gap with the hard-path message, and log `BLOCKED | ship-gate | <slug> (hard-path <kind>)`. (c) If the ledger holds a `lane-suggest full` action and the spec lane is not `full`, print the not-taken advisory. All under `_gate_on lane_gates`; fail open on a missing lib, as today. AC: the migration fixture with only normal-lane gates recorded exits 2; the same fixture without the migration file exits 0.

### Phase 3: Polish

- [ ] TASK-7: Rule text. Replace `docs/WORKFLOW.md:62-69` with the rule below. Same rule, one-line form, at `AGENTS.md:66-67`, `examples/hello-spec/AGENTS.md:38`, `commands/assign.md:112,127`. Reword `AGENTS.md:179` to: "Risk-classification change: moving an assigned lane lighter, dropping a phase from a lane, or narrowing a hard path or a full-lane trigger. Staying on the default lane after a suggestion is not a lane change; the operator decides whether to assign the heavier one." `commands/assign.md` passes `--rid` to `classify` once the branch exists. AC: `grep -c 'take the heavier one'` over those four files is 0.
- [ ] TASK-8: Phase-applicability prose that names a lane instead of asking the lane data: `commands/assign.md:59,177,180,189` (a spec comes next when `plan <lane>` lists `spec`). WORKFLOW.md matrix (`:409-435`) becomes "the human view of `kit.toml [lane.*]`, pinned by `tests/test-lanes-data.sh workflow-view`"; the gate-ledger section (`:500-502`) names `kit.toml` as the source. AC: `bash tests/test-lanes-data.sh workflow-view` passes.
- [ ] TASK-9: The ADR for the reversal; the kit repo's own `.kit.toml` gets `[lanes] extra_hard_paths = "^hooks/|^lib/gate/|^lib/classify/|^lib/config/|^kit\.toml$"`; `docs/MANUAL.md` and `docs/architecture.md` rows the doc-projection check asks for; regenerate `docs/FEATURES.md`. AC: `bash lib/gate/doc-projection-check.sh .` and `bash lib/registry/feature-registry.sh check docs/FEATURES.md` pass.

The new rule text (WORKFLOW.md; a one-line form elsewhere):

> Default to `normal`. The classifier prints a one-line suggestion when the task text matches a full-lane trigger and records it in the run ledger. The agent may propose the full lane in one sentence and continues on the lighter lane until the operator assigns it. The normal lane requires a fresh-context validation and a review; those catch the triggers no diff can show (authz, API contract, external provider, weakened validation). The ship-gate applies the full lane's gates to any diff that touches a hard path (migrations, auth, secrets, CI workflows, kit config, data loss), whatever the spec's `Lane:` says. With `[gate] lane_gates = false` none of this runs. Moving an assigned lane lighter stays a Pause-if decision.

## After state

- [ ] `kit.toml` holds the five lanes as data. (Today: `docs/WORKFLOW.md:420-435` is parsed at run time.)
- [ ] `bash lib/gate/gate-ledger.sh required normal` prints `spec validate build review ship`. (Today: `spec build ship`.)
- [ ] `bash lib/classify/lane-classify.sh classify "add token count column"` prints `normal` and no suggestion. (Today: `full`.)
- [ ] A normal-lane spec whose diff adds `db/migrations/0001_users.sql` is blocked at push until full-lane gates are recorded. (Today: passes with normal-lane gates.)
- [ ] A committed `.kit.toml` that drops `review` from `normal` shows `| GATE | review | skipped | repo lane override (.kit.toml)` in the run ledger after `start`.
- [ ] No kit doc says "take the heavier one".

## Acceptance Criteria (global)

Fixture helpers live in `tests/test-lanes-data.sh` (new). Each case prints `PASS <name>` or `FAIL <name>: <why>` and the file exits nonzero on any FAIL.

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | Reader refactor is byte-identical: plan, required, progress, descent for all five lanes, before the normal flip | `bash tests/test-lanes-data.sh parity` (run at TASK-2's commit) | empty diff against `docs/verification/lanes-as-data/baseline.txt` |
| AC2 | After the flip, only the two normal cells differ | `bash tests/test-lanes-data.sh parity-after-flip` | diff lines are exactly normal `validate` and `review`, lite to required |
| AC3 | The reader no longer parses WORKFLOW.md | `grep -cE 'matrix_for_lane\|GATE_LEDGER_WORKFLOW' lib/gate/gate-ledger.sh` | `0` |
| AC4 | WORKFLOW.md view matches the data | `bash tests/test-lanes-data.sh workflow-view` | `PASS` |
| AC5 | Committed override drops a phase; the ledger shows it | `bash tests/test-lanes-data.sh override-drop-review` | plan has no `review`; ledger has the skipped line |
| AC6 | Uncommitted override and uncommitted `[lanes] default` are ignored | `bash tests/test-lanes-data.sh override-uncommitted` | plan still lists `review`; classify still prints `normal`; stderr names the rule |
| AC7 | Unknown phase in an override is ignored | `bash tests/test-lanes-data.sh override-typo` | plan equals the kit lane; stderr names the phase |
| AC8 | `phases` without `light` means all required | `bash tests/test-lanes-data.sh override-no-light` | `required normal` equals the override's `phases` |
| AC9 | Kit root pinned to the install | `bash tests/test-lanes-data.sh pinned-root` | `KIT_CONFIG_ROOT=/tmp/evil DWARVES_KIT=/tmp/evil bash lib/gate/gate-ledger.sh required normal` still prints the install's lane |
| AC10 | Last-dot split | `bash lib/config/kit-config.sh selftest` | includes and passes the `lane.normal.phases` case |
| AC11 | Four false hits: normal, no suggestion | `for t in "add token count column" "add queue timeout" "add webhook retry log line" "add user role label"; do bash lib/classify/lane-classify.sh classify "$t" 2>&1; done \| sort -u` | exactly `normal` |
| AC12 | Keyword hit is a suggestion plus a ledger line | `bash tests/test-lanes-data.sh suggest-records` | stdout `normal`; stderr `LANE-SUGGEST: full (data-model)`; ledger `\| ACTION \| lane-suggest full flags=data-model` |
| AC13 | File fact still returns full | `bash lib/classify/lane-classify.sh classify --files "db/migrations/0001_users.sql" "add a users table migration" 2>/dev/null` | `full` |
| AC14 | Spec-to-build holds and suggests | `bash tests/test-lanes-data.sh escalate-suggest` | stdout `HOLD normal`; stderr `LANE-SUGGEST` |
| AC15 | Migration diff blocks at ship | `bash tests/test-lanes-data.sh ship-migration-blocks` | hook exit 2; stderr names `hard path (migration` |
| AC16 | A project cannot hollow full to pass the floor | `bash tests/test-lanes-data.sh ship-hollow-full-override` | hook exit 2 |
| AC17 | Data-loss lines block; the same line in a doc does not | `bash tests/test-lanes-data.sh ship-data-loss` | `DROP TABLE`, `TRUNCATE users`, `deleteMany({})` in code: exit 2; in `.md`: exit 0 |
| AC18 | Widened hard paths | `bash tests/test-lanes-data.sh floor-paths` | hits for `alembic/versions/x.py`, `drizzle/0001.sql`, `db/changelog/db.changelog-master.xml`, `.github/workflows/ci.yml`, `.kit.toml`; no hit for `.env.example`, `CHANGELOG.md` |
| AC19 | Spec-less push warns, never blocks | `bash tests/test-lanes-data.sh ship-no-spec-advisory` | exit 0; stderr has the no-spec advisory |
| AC20 | Not-taken suggestion advisory | `bash tests/test-lanes-data.sh ship-suggest-advisory` | exit 0 (gates recorded); stderr has the not-taken advisory |
| AC21 | Rule text replaced | `grep -c 'take the heavier one' docs/WORKFLOW.md AGENTS.md examples/hello-spec/AGENTS.md commands/assign.md` | every count `0` |
| AC22 | No regressions | `bash tests/test-hooks.sh && bash tests/test-meta.sh && bash tests/test-lane-classify.sh && bash tests/test-lane-escalation.sh && bash tests/test-lane-deescalate.sh && bash tests/test-gate-ledger-plan-record.sh && bash tests/test-ship-gate-fail-closed.sh && bash tests/test-config-registry.sh && bash tests/test-config.sh` | all exit 0 |

`tests/test-lane-classify.sh` and `tests/test-lane-escalation.sh` pin `full` for keyword text today (35 and 12 lines mention `full`). They change on purpose: each keyword case asserts stdout `normal` plus the `suggest:` line from `explain`, so every flag regex stays covered.

## Verification

```bash
bash tests/test-lanes-data.sh
bash lib/config/kit-config.sh selftest
bash tests/test-hooks.sh && bash tests/test-meta.sh && bash tests/test-lane-classify.sh && bash tests/test-lane-escalation.sh && bash tests/test-lane-deescalate.sh && bash tests/test-gate-ledger-plan-record.sh && bash tests/test-ship-gate-fail-closed.sh && bash tests/test-config-registry.sh && bash tests/test-config.sh
```

## Test plan

Date: 2026-09-29

| Case | Kind | Covers | Proof |
|---|---|---|---|
| Parity: plan, required, progress, descent equal the baseline at TASK-2 | positive | AC1 | `parity` |
| "add token count column" classifies normal, no suggestion | negative control (the old answer was full) | AC11 | `bash lib/classify/lane-classify.sh classify "add token count column" 2>&1` is exactly `normal` |
| Migration diff on a `Lane: normal` spec with every normal gate recorded | negative control (must still block) | AC15 | `ship-migration-blocks`: fixture repo, `docs/verification/README.md` marker, committed `.kit.toml [gate] lane_gates = true`, ledger with normal gates, `db/migrations/0001_users.sql` added; feed `{"tool_input":{"command":"git push -u origin feat/x"}}` to `hooks/ship-gate.sh`; expect exit 2 |
| Same fixture, then `gate-ledger.sh override` for each missing full gate | positive | AC15 | exit 0 |
| Same fixture without the migration file | positive (floor quiet) | AC15 | exit 0 |
| Same fixture with `lane_gates = false` committed | positive (switch honored, plainly lossy) | Invariants | exit 0, `OFF-BY-CONFIG` logged |
| Committed `.kit.toml` drops `review` from `normal` | negative control (phase must show skipped) | AC5 | `plan normal` has no `review`; after `start`, `show <rid>` has the skipped line |
| Same override, uncommitted | negative control (must not apply) | AC6 | `plan normal` lists `review` |
| Override `phases = ["reveiw", ...]` | negative control (typo must not drop) | AC7 | `plan normal` equals the kit lane |
| Committed `.kit.toml [lane.full] phases = ["build"]` plus a migration diff | negative control (floor ignores project) | AC16 | exit 2 |
| Dirty `.kit.toml` that deletes an `extra_hard_paths` entry, diff hits that entry | negative control (union with HEAD) | Config layers | exit 2 |
| `KIT_CONFIG_ROOT` pointed at a file whose `[lane.normal]` drops `ship` | negative control (pinned root) | AC9 | `required normal` still lists `ship` |
| `DROP TABLE users;`, `TRUNCATE users;`, `await db.users.deleteMany({})` in code | negative control | AC17 | exit 2 each |
| Same lines in `docs/notes.md` only | positive | AC17 | exit 0 |
| `.env.example`, `CHANGELOG.md` changed | positive (not hard paths) | AC18 | `floor` prints nothing |
| Spec-less push with a migration file | positive (warn, no block) | AC19 | exit 0 plus the advisory |
| Lane value `phases = ["spec",` with no closing bracket | negative control (fail closed) | Invariants | `check normal <rid>` exits 1 with "unknown lane" |

Dry trace for the key negative control (AC15): the fixture commits `db/migrations/0001_users.sql`; `ship-gate.sh` passes `:279`; `check normal` passes because every normal gate is recorded; the new block calls `lane-classify.sh floor <root> <base>`, whose changed-path list includes the file and matches the migration pattern; `gate-ledger.sh check full <rid> --kit-lanes` prints `MISSING-GATE: think` and others; the hook exits 2. Deleting the new block turns this case green, which is the mutation that proves the test.

## Edge Cases

1. A rename out of `migrations/` (`git mv db/migrations/x.sql tests/`): both sides are listed (`--no-renames`), so the floor hits.
2. A spec already on `Lane: full`: the floor still runs `check full --kit-lanes`, so a project override that hollowed `full` cannot pass.
3. A branch with no spec: no lane exists to compare, so the ship-gate cannot block on lane gates. When the floor hits it prints the no-spec advisory, then exits 0 as today (`hooks/ship-gate.sh:224-225`). The proof gate still blocks stateful diffs there in adopted repos.
4. No `[lanes] default` in any layer: code default `normal`.
5. An invalid ERE in `extra_hard_paths`: `grep -E` errors; that layer's extras count as absent, with one stderr line. Built-ins still apply.
6. `lanes.d` drop-in lanes: unchanged; they answer `plan` only (`lib/gate/gate-ledger.sh:495-505`).
7. A bug-lane task that also hits a full flag: bug stays the lane; the suggestion still prints and records.
8. Old ledgers with `classified=full` START lines: readers unchanged; lane telemetry misfire counts drop from the change date on.
9. A `.kit.toml` edit in the diff (for example a lane override) is itself a hard path, so changing a repo's gates needs full-lane gates in that PR.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Lane data and WORKFLOW.md view drift | `workflow-view` red | The data is the source; fix the view |
| Hard-path list misses a real risky path | A risky change ships on normal-lane gates; SPEC-367 escape records | `extra_hard_paths` in that repo; widen the built-ins when two repos need the same path |
| Hard-path list over-fires (for example `session` in a UI component name) | Overrides with reason "not auth" on the floor | Narrow the pattern; `gate-ledger.sh override` unblocks meanwhile |
| A PR commits `[gate] lane_gates = false` and ships under it | `OFF-BY-CONFIG` line in `ship-gate.log`; the `.kit.toml` diff in the PR | Pre-existing gate-policy behavior (`lib/gate/gate-policy.sh:44-51`), not changed here; open question 1 |
| Repos with `lane_gates = false` under-size real risk | No floor, no suggestion advisory at push | Stated plainly in the rule text; the proof gate and safety gates remain |
| Installed `kit.toml` lacks the lane blocks (partial install) | Every lane-gated push refuses with "unknown lane" | Fail closed on purpose; `bash install.sh` restores it |
| Operators ignore the suggestion and under-size real risk | SPEC-367 counts `lane-suggest` against escapes; ship advisory | Required validate and review on normal; tighten only on measured escapes |

## Migration notes (existing adopted repos)

- Normal-lane runs now need `validate` and `review` recorded as `ran` or `override` before push. In-flight normal runs that skipped either get blocked at the next push: run the gate, or record `gate-ledger.sh override <rid> validate "<reason>"`. Reports that re-read old normal-lane ledgers against today's lane data (`progress`, `report`) may show those two gates missing on runs shipped before the change; that is a reading artifact, not a new failure.
- Keyword-only tasks come back `normal` with a suggestion line. Repos relying on auto-full from a title now rely on the diff floor at push, which runs only with `lane_gates = true`.
- Specs in flight keep their `Lane:` header.
- Adopted repos carry a copy of the old `AGENTS.md` text with the "heavier" rule (`lib/adopt.sh` copies it once). SPEC-371 replaces that copy with a pointer; until then the copy is stale advisory text.
- A repo that wants a lane changed writes `[lane.<name>] phases = [...]` (and `light`) in `.kit.toml` and commits it; that PR itself meets full-lane gates (edge case 9). Only the five kit lane names are accepted.
- Partial installs: re-run `bash install.sh` so the installed `kit.toml` has the `[lane.*]` blocks.

## Out of Scope

- The spec depth line (D2): SPEC-372.
- A per-spec or per-mission lane override. The spec file is agent-written, so a per-spec phase list would be a self-waiver; the per-phase `gate-ledger.sh override` with a logged reason covers one-off cases.
- New lane names from `.kit.toml`; the `lanes.d` drop-in stays the path.
- The proof gate's `stateful` over-fire (`lib/gate/proof-ledger.sh:112`).
- Model tier and review-round rules keyed on lane names (`commands/spec.md:294,300`, `commands/review-team.md:355`). They tune depth inside a phase, not whether a phase runs. `commands/spec.md:274` (the design pass on the full lane) moves to lane data in SPEC-372, which owns `commands/spec.md`.
- `commands/execute.md` (SPEC-369).
- `[role.<name>]` (D8 step two) and starter templates (SPEC-371).
- A repo knob to bring back keyword auto-escalation.

## Touches

Single files (the dispatch gate cannot prove these disjoint by prefix, so it serializes against any sibling that lists them): `kit.toml`, `.kit.toml`, `hooks/ship-gate.sh`, `docs/WORKFLOW.md`, `AGENTS.md`, `examples/hello-spec/AGENTS.md`, `commands/assign.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/FEATURES.md`, `tests/test-lanes-data.sh`, `tests/test-lane-classify.sh`, `tests/test-lane-escalation.sh`.

- lib/classify/**
- lib/gate/**
- lib/config/**
- docs/decisions/**
- docs/verification/lanes-as-data/**

## Siblings

| Spec | Relation |
|---|---|
| SPEC-366 execution-view | May call `gate-ledger.sh plan`; output is unchanged except normal's two required cells. No dependency |
| SPEC-367 ceremony-lens | Measures this change. Reads the `lane-suggest full flags=` action lines and the ship advisory log. Both may touch `lib/gate/gate-ledger.sh`; this spec touches only the lane reader, `check`, and `start`. Land in either order, rebase the second |
| SPEC-369 whole-spec-dispatch | Owns `commands/execute.md`. Dependency: `execute.md:24-45` should relay the `LANE-SUGGEST` stderr line and drop the prose that says the spec-to-build step escalates on auth, data-model, or migration text. Until then `HOLD` keeps the run correct and only the prose is stale |
| SPEC-370 orca-mega-backend | No shared files. `lib/goal/mega-merge.sh` calls `gate-ledger.sh check`, which only gains an optional flag |
| SPEC-371 adopt-pointer-onboarding | Consumer of `[lane.*]` for starter templates (`SPEC-371:78-80`). Its pointer text should say "default normal; the diff floor applies at push; normal requires validate and review" |
| SPEC-372 spec-depth-line | Split out of this spec. Owns `commands/spec.md`, `spec-validate.md`, `test-plan*.md`, `test-write.md`, `lib/spec/**`. Depends on this spec for `docs/WORKFLOW.md` (both edit it; land this first) |

## Decision Log

- DEC-1: Hard paths are code constants plus an add-only config list, so they hold regardless of overrides. Rejected: a `kit.toml` list (a project layer could replace it).
- DEC-2: The floor runs `check full --kit-lanes`, ignoring the project layer. Rejected: the resolved `full` lane (a committed override could hollow it).
- DEC-3: `light` is a second array next to `phases`. Rejected: suffix markers inside one array (`"think:light"`), harder to read and to validate.
- DEC-4: The floor follows `lane_gates` (operator decision). Repos with the switch off get no floor and no automatic full lane; the rule text says so.
- DEC-5: `escalate` prints `HOLD` plus a suggestion instead of a new stdout word, so `commands/execute.md` needs no edit here.
- DEC-6: Keep the WORKFLOW.md matrix as a pinned human view. Rejected: deleting it (links break) and generating it (a build step for prose).
- DEC-7: Normal requires `validate` and `review` (operator decision: lighten the middle, keep the edges). This reverses `docs/WORKFLOW.md:451-457`; the refusal cost that note named is handled in the migration notes.
- DEC-8: Spec-less pushes warn on a floor hit, never block (operator decision).
- DEC-9: `webhook` narrowed with `token`, `queue`, and `role` (operator decision).
- DEC-10: Fix `kit_config_get` at the last dot rather than bypass it; keep per-file reads only for the project layer's committed-and-clean test.

## Grounding

- Baseline plans, run today in this worktree: `for l in tiny normal full bug backfill; do bash lib/gate/gate-ledger.sh plan $l; done`. Excerpt: normal = `grill intake; think lite; spec required; validate lite; design-record lite; test-plan lite; build required; review lite; docs lite; ship required`; full = 13 phases, all required except `ui-design lite`; bug = `test-plan lite; build required; review required; ship lite; debug required`; backfill = `think lite; spec lite; validate lite; review lite; docs required`; tiny = `build lite; review lite`. `required` prints: tiny none; normal `spec build ship`; full `think design design-critique spec validate design-record test-plan build review docs ship reflect`; bug `build review debug`; backfill `docs`.
- Classifier today: `bash lib/classify/lane-classify.sh explain "<t>"` for the four false hits returns `full` with flags `audit-security`, `external-provider`, `external-provider`, `auth`.
- Override recount: `D=$(bash -c 'source lib/telemetry/kit-log-dir.sh && kit_resolve_log_dir'); for p in think reflect design design-critique test-plan; do grep -h "| GATE | $p | override" "$D"/runs/*.log | wc -l; done` over 149 ledgers: 21, 14, 15, 14, 6.
- Three-part config keys in use today: `grep -rhoE 'kit_config_get(_root)? +"?[a-z_]+\.[a-z_.]+' lib hooks bin commands`, filtered to keys with two dots: none. The last-dot split changes no existing caller.
- Config shape: `_kit_toml_get` strips brackets and spaces from a header (`lib/config/kit-config.sh:45-47`), so `[lane.normal]` reads as section `lane.normal`; it returns the raw one-line value, so `["a", "b"]` comes back intact.
- Gate switch on this machine: `bash lib/gate/gate-policy.sh enabled lane_gates .` exits 0 (operator overlay).
- This spec's own classification: `explain` returns `full`, flag `kit-machinery`. It edits `hooks/ship-gate.sh` and `lib/gate/`.

## Open questions

1. `lane_gates` and `proof_of_done` switch off from a committed `.kit.toml` in the same PR that benefits (`lib/gate/gate-policy.sh:44-51`). The floor inherits that. Reading the switch as of the merge base would close it; it is a gate-policy change, so it is not in this spec.
