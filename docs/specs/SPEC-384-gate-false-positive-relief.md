# Spec: gate false-positive relief (a root-only hard-path exclusion, one audited lane-wide override)
Generated: 2026-10-02
Status: DRAFT (round 1 NEEDS REVISION folded; T1 redesigned per the lead's fold brief)
Lane: full
Type: spec-feature
Depth: blind-spot (failure: a hard-path exemption or a lane-wide override lets a real auth change, or a refused gate, ship without the full lane)
File: `docs/specs/SPEC-384-gate-false-positive-relief.md`
References: `docs/retro/RETRO-2026-10-02-observe-cost-dedup.md` (the two action items this spec closes); `lib/gate/lane-data.sh` (`lane_extra_hard_paths`, the one lane-data reader; imitate its layer reads and its "invalid entry: one stderr line, skip" habit); `lib/config/kit-config.sh` (`kit_config_get_root`: operator overlay first, then the kit root, never the project file); `lib/classify/lane-classify.sh` (`_path_kind`, `_floor_scan`, `explain`); `lib/gate/gate-ledger.sh` (`override`, `required`, `check`, `start`, `plan_record`'s refuse-before-write); `lib/telemetry/lane-telemetry.sh` (`report`, the `boardless runs` line); `tests/test-lanes-data.sh` (`mkrepo`, `case_floor_paths`); `tests/test-ledger-durability.sh` (AC6/AC7/S3, the override guard); `docs/implementation-notes/gate-false-positive-relief.md` (the builder-facing delta)

## Problem

PR #877 edited `lib/session/observe/bin/session-observe`, a transcript-session tool. Two gate behaviors turned a small fix into a slog.

1. **False positive.** `_HP_auth` lists `sessions?` as a bare path segment. The kit's own `lib/session/` module holds 93 tracked files, and every one hits the auth hard path. The ship-gate floor then demanded the full lane's required gates.
2. **Override cost.** Recovering needed one `gate-ledger.sh override <rid> <phase> "<reason>"` call per required gate. The ledger rejects a reason already used for a different gate (exit 65), so each call needed an invented suffix, and 11 first attempts failed.

## Solution

### Approaches considered

T1, the false positive:

- **A. Narrow `_HP_auth` by pattern** (round 1's design): a session path counts only when its path or its added lines carry an auth word. Tradeoff: recall holes. Round 1 reviewers found three independent sets of misses (`src/session/authenticate.ts`, `acl.ts`, `SessionToken.ts`, `secure: false`, `maxAge`, any deleted `httpOnly`), all full today. No word list closes them.
- **B. An explicit, root-resolved exclusion list** `[lanes] not_hard_paths`: exact repo-scoped directory prefixes removed from the auth kind only. Tradeoff: a config knob that subtracts from a hard path, which today no config can do.
- **C. Do nothing in the classifier; rely on T2.** Tradeoff: every edit to `lib/session/` pays one override call forever, and the override trail fills with known noise.

T2, the override:

- **D. New verb `override-lane <rid> <lane> <reason>`.** One call writes one GATE override line per required gate, each reason tagged with the gate.
- **E. Magic phase `override <rid> all-lane <reason>`** (the retro's wording). Overloads the phase argument of an existing verb.
- **F. Reuse `plan-record --override`.** Needs every plan phase named and still enforces distinct reasons.

### Chosen approach + why

B for T1. It changes nothing for any path not listed, in any repo: every other `session/` path stays full exactly as today, so no recall hole opens. The list is read only from the operator overlay and the pinned kit root, never from a project `.kit.toml`, so a PR cannot exempt its own diff. Each entry names one repo, so the kit's own entry cannot exempt a consumer's `lib/session/`. A was rejected for its recall holes (DEC-1); C leaves the cost in place.

D for T2. A dedicated verb leaves `override`'s contract and its 65 guard byte-identical, and makes a lane-wide override a distinct, greppable, counted event (DEC-5).

### Extensibility & boundaries

- T1 grows by entries, not code. A second known false positive is one more `owner/repo:prefix/` entry in the operator overlay or the kit root. It only ever touches the auth kind; a new kind would need a new spec (DEC-9).
- T2 reads `required <lane>`, so a lane that gains a gate is covered with no code change.
- Units, each testable alone:
  - `lane_not_hard_paths <root>` (lane-data.sh): resolve, validate, repo-filter, print prefixes. One purpose: answer "which auth prefixes are exempt in this repo".
  - The classifier consumes that list in two places (`_path_kind` for one path, `_floor_scan` for many) and reports exemptions.
  - `override_lane` (gate-ledger.sh) composes `required`, the ledger read, and `override`.
  - The telemetry counter reads ACTION lines only.

### Architecture

See `## Design`.

## Picture

```
 T1: the auth kind with a root-only exclusion (lane-classify.sh + lane-data.sh)

   operator overlay kit.toml ─┐   (first non-empty value wins, as kit_config_get_root;
   pinned kit root kit.toml ──┴─► [lanes] not_hard_paths   never the project .kit.toml)
                                        │
                                        ▼
                           lane_not_hard_paths <root>
                             validate each entry ── bad ──► stderr line, entry ignored
                             keep entries whose owner/repo == origin of <root>
                                        │  prefixes, e.g. "lib/session/"
                                        ▼
   changed path ──► auth regex (unchanged _HP_auth) ── no ──► other kinds, extras (unchanged)
                          │ yes
                          ▼
                    path starts with an exempt prefix?
                          │ no ──► full auth  (as today)
                          ▼ yes
                    not an auth hit; explain prints
                    "excluded by [lanes] not_hard_paths: <entry>";
                    other kinds and extra_hard_paths still apply


 T2: override-lane flowchart (gate-ledger.sh)

   override-lane <rid> <lane> "<reason>"
        │ rid normalizes empty? reason empty after trim? ──► exit 64, nothing written
        │ lane unknown to BOTH project and kit-root `required`? ──► exit 64
        ▼
   gates = required(lane) ∪ (LANES_KIT_ONLY=1 required(lane) || empty)
        │
        │ any gate with a refusal `skipped` line and no ran|override line?
        │   (exempt reason: exactly "repo lane override (.kit.toml)")
        │   ── yes ──► exit 64, names each gate + recorded reason, nothing written
        ▼
   for each gate g with no ran|override line:
        override(<rid>, g, "<reason> [lane-override lane=<lane> gate=<g>]")
        ▼
   ACTION: lane-override lane=<lane> gates=<n> written=<k> reason=<reason with = as :>
   stderr: LANE-OVERRIDE: <k> gate(s) of lane <lane> overridden for run <rid> ...
        ▼
   check(), check --kit-lanes, ship-gate, progress read the GATE lines as today;
   lane-telemetry report counts runs carrying a lane-override ACTION
```

## Design

Design-bearing: yes. T1 adds the first config knob that subtracts from a hard path; T2 relaxes an audit guard on purpose.

### Approaches considered + chosen

See `## Solution`. The fold replaced round 1's pattern narrowing with B.

### Diagram

See `## Picture` (two flowcharts). ASCII by house rule.

### ADR link(s)

`docs/decisions/0024-gate-ledger-and-ship-enforcement.md` owns the override path and the floor. Both changes revert with one commit, and no ledger line format changes. No new ADR; the trade-offs are DEC-3 and DEC-10, and `lib/gate/README.md` gains them in prose.

### Boundaries & failure modes

Out of bounds: the `_HP_auth` regex itself (unchanged), every non-auth kind, `extra_hard_paths`, the task-text auth regex (SPEC-296), `proof-ledger.sh override`, and `hooks/ship-gate.sh`. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**T1a, the knob: `[lanes] not_hard_paths` (read by `lib/gate/lane-data.sh`).**

- Value: one string of whitespace-separated entries. Entry form: `<owner>/<repo>:<prefix>`.
  - `<owner>/<repo>`: `[A-Za-z0-9._-]+/[A-Za-z0-9._-]+`, compared case-insensitively.
  - `<prefix>`: a repo-relative directory prefix of one or more plain segments, each `[A-Za-z0-9._-]+`, ending in `/`.
- Rejected entries (one stderr line `lane-data: not_hard_paths entry '<e>' rejected: <why>; ignored`, then skipped): no `owner/repo:` scope; empty prefix; prefix `/` or starting with `/`; a `.` or `..` segment; any glob or regex character (`*?[]{}()|^$\+`); no trailing `/`.
- Layers: the operator overlay (`kit_config_operator`), else the kit root PINNED by lane-data (`_ld_kit_file`), the same first-non-empty order as `kit_config_get_root`. Never the project `.kit.toml`, in the working tree or at HEAD. The pinned kit root is used instead of `kit_config_root`, because `kit_config_root` honors `KIT_CONFIG_ROOT`/`DWARVES_KIT` from the environment.
- New reader `lane_not_hard_paths <root>`: prints the prefixes of the valid entries whose `owner/repo` equals the repo id of `<root>`, one per line, each line `<prefix>\t<entry>`. Repo id: `git -C <root> remote get-url origin`, trailing `/` and `.git` stripped, the last two `/`- or `:`-separated components, lowercased. No origin: prints nothing.
- Kit root default: `kit.toml` `[lanes]` gains `not_hard_paths = "dwarvesf/dwarves-kit:lib/session/"`, with a comment naming it the kit's transcript tooling. `lib/config/module-registry.md` gains its row.
- Invariant: an empty or absent value changes nothing anywhere.

**T1b, the classifier: `lib/classify/lane-classify.sh`.**

- `_HP_auth` is unchanged, byte for byte.
- The project root for `--files` verbs is `${KIT_PROJECT_ROOT:-$(git rev-parse --show-toplevel)}`; for `floor` it is the `<root>` argument, as today.
- `_path_kind <path>`: when the auth kind matches and the path starts with an exempt prefix, the auth kind does not count. The path still runs through the remaining kinds and `extra_hard_paths`.
- `explain --files`: for each exempted auth hit, one extra line `excluded: <path> by [lanes] not_hard_paths: <entry>`. `classify` and `risk` print their single word unchanged.
- `floor`: the auth pass picks the first auth hit whose path is not under an exempt prefix. Each exempted path prints one stderr line `floor: excluded <path> by [lanes] not_hard_paths: <entry>` (the ship-gate discards floor stderr; a direct run shows it). Cost stays one grep plus one awk filter over the path list.
- Invariant: a path with no exempt prefix classifies exactly as today. An exempt path that hits a non-auth kind or an extra hard path is still full.

**T2, `override-lane <rid> <lane> <reason...>` in `lib/gate/gate-ledger.sh`.**

- Refusals, all before any write, each exit 64 with nothing written:
  1. missing rid or lane, or a rid that `runid` normalizes to empty;
  2. reason empty after `oneline` and whitespace trim;
  3. lane unknown: the project-resolved `required <lane>` and the kit-root `LANES_KIT_ONLY=1 required <lane>` (the in-script prefix form, as `check()` uses; an exported env var is reset at `gate-ledger.sh:69`) both fail;
  4. a recorded refusal: any gate in the set has a `| GATE | <g> | skipped |` line and no `ran` or `override` line, unless every such skipped reason is exactly `repo lane override (.kit.toml)`. The message names each refused gate and its recorded reason. Clearing one deliberately stays a single-gate `override`.
- Gate set: the union of the project-resolved list and the kit-root list, deduplicated, in kit plan order. A kit-root `required` that exits non-zero counts as an empty kit set (guarded so `set -e` does not abort). The union matters: the ship-gate floor runs `check full --kit-lanes`, the spec-lane check runs the project-resolved list, and one call must satisfy both.
- A `repo lane override (.kit.toml)` skip is not a refusal. That gate still gets an override line, because `check --kit-lanes` counts only `ran`/`override` (Grounding S6).
- Gates with an existing `ran` or `override` line are skipped and named (`<phase> already-disposed`), never relabelled.
- Each remaining gate is written by the existing `override()` with reason `<reason> [lane-override lane=<lane> gate=<phase>]`. The tag makes each reason distinct, so the 65 guard passes by construction and still blocks a hand-typed single-gate `override` that reuses a tagged reason.
- Then one `ACTION` line: `lane-override lane=<lane> gates=<n> written=<k> reason=<reason>`, the reason passed through `tr '=' ':'` as `debt()` and `config` do (DEC-11).
- stdout: one `<phase> override` or `<phase> already-disposed` line per gate, then the `check` verdict as `plan-record` prints it. stderr: `LANE-OVERRIDE: <k> gate(s) of lane <lane> overridden for run <rid> with one reason; review with: gate-ledger.sh show <rid>`.
- Exit: 0 when the writes happened (k may be 0); 64 on any refusal; a non-zero from `override()` propagates with a message naming how many lines were written.
- Operator-run only (DEC-3): no kit command, skill, or hook calls it; `lib/gate/README.md` says so.
- Invariants: no ledger line format changes; `override` and its 65 guard stay byte-identical; `check()`, `progress()`, `descent()` and the ship-gate need no change.

**T3, the counter: `lib/telemetry/lane-telemetry.sh report`.** After the `boardless runs` line, print `lane-override runs: <n>` when n > 0, where n is the number of run ledgers in the report's set holding a `| ACTION | lane-override ` line. Silent at 0, so existing report pins hold.

### Data model changes

One config key (`[lanes] not_hard_paths`). The ledger gains lines in the existing `GATE ... override` and `ACTION` shapes.

### API changes

One ledger verb (`override-lane`), listed in `gate-ledger.sh`'s usage line and header comment. It is reachable as `gate ledger override-lane` through `bin/gate`, which forwards any `ledger` verb; AC9 checks that.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

Dependencies: TASK-2 needs TASK-1; TASK-4 needs TASK-3; TASK-5 needs TASK-1 to TASK-4.

### Phase 1: Foundation

- [ ] TASK-1 (T1a, the knob): `lane_not_hard_paths <root>` in `lib/gate/lane-data.sh`; the `kit.toml` default entry; the `lib/config/module-registry.md` row; reader tests in `tests/test-lanes-data.sh`. Acceptance: AC1, AC2.
- [ ] TASK-3 (T2): `override_lane` with its dispatch, usage and header lines in `lib/gate/gate-ledger.sh`; cases in `tests/test-ledger-durability.sh`. Acceptance: AC6 to AC13.

### Phase 2: Core

- [ ] TASK-2 (T1b, the classifier): consume the list in `_path_kind`, `explain`, and `_floor_scan`; extend `case_floor_paths` and add exclusion cases in `tests/test-lanes-data.sh`. Acceptance: AC3 to AC5.
- [ ] TASK-4 (T3): the `lane-override runs:` line in `lane-telemetry.sh report`; one case in the telemetry suite. Acceptance: AC14.

### Phase 3: Polish

- [ ] TASK-5 (docs): `lib/gate/README.md` ("An override is not a skeleton key": the lane-wide override, DEC-3's trade-off, operator-run only; a short "Exempting a hard path" note for `not_hard_paths`, DEC-10); `docs/WORKFLOW.md` "## Gate ledger and ship enforcement" names `override-lane` next to `override`. Acceptance: AC15.

## After state

- [ ] `lane-classify.sh floor <kit checkout> 5030a8cc^ 5030a8cc` prints nothing on stdout. (Today: `full auth: lib/session/observe/bin/session-observe`.)
- [ ] In a fixture repo, `src/session/index.ts`, `src/session/authenticate.ts`, `middleware/session.js` still hit the floor as `full auth`. (Today: the same.)
- [ ] A project `.kit.toml` that sets `not_hard_paths` exempts nothing.
- [ ] `gate-ledger.sh override-lane <rid> full "<reason>"` writes one tagged override line per gate of `required full`, and `check full <rid>` and `check full <rid> --kit-lanes` both exit 0. (Today: one call per gate, each with an invented reason.)
- [ ] `override-lane` refuses (exit 64, nothing written) on an empty reason, an unknown lane, an empty-normalizing rid, or a gate carrying a recorded refusal.

## Acceptance Criteria (global)

Classifier checks run with `KIT_CONFIG_OPERATOR` pointed at a fixture overlay (or `/nonexistent`) so Han's machine overlay never leaks in. Ledger checks run with an isolated `DWARVES_KIT_LOG_DIR`. Tests derive every expected gate count from `required full`; no literal counts.

- [ ] AC1 (reader, scope and validation): with an overlay `not_hard_paths = "acme/app:lib/session/ acme/app:../x/ acme/app:/ acme/app:src/* lib/session/ acme/app:docs"` and a fixture repo whose origin is `git@github.com:acme/app.git`, `lane_not_hard_paths <fixture>` prints exactly `lib/session/` (with its entry), and stderr carries one `rejected` line for each of the other five entries. With origin `https://github.com/other/app`, it prints nothing.
- [ ] AC2 (the shipped entry): with `KIT_CONFIG_OPERATOR=/nonexistent` and a fixture repo whose origin is `https://github.com/dwarvesf/dwarves-kit.git`, `lane_not_hard_paths` prints `lib/session/`. `grep -n 'not_hard_paths' kit.toml lib/config/module-registry.md` hits both files.
- [ ] AC3 (exempt path at the floor): in the `mkrepo` harness with origin `acme/app` and the AC1 overlay, adding `lib/session/observe/bin/session-observe` makes `floor` print nothing on stdout and `floor: excluded lib/session/observe/bin/session-observe by [lanes] not_hard_paths: acme/app:lib/session/` on stderr. `explain --files lib/session/observe/bin/session-observe "add a flag"` (run inside the fixture) prints `normal` and the `excluded:` line.
- [ ] AC4 (everything else unchanged): in the same fixture, each of `src/session/index.ts`, `src/session/authenticate.ts`, `middleware/session.js`, `lib/sessions/x.sh` (plural is not the listed prefix), `lib/auth/session.sh` makes `floor` print `full auth: <path>`. `lib/session-tools/x.sh` prints nothing, as today (it never matched `_HP_auth`). Adding `lib/session/x.sh` together with `src/auth/login.ts` prints `full auth: src/auth/login.ts`.
- [ ] AC5 (root-only, the negative control): a fixture with `KIT_CONFIG_OPERATOR=/nonexistent`, origin `acme/app`, and a COMMITTED project `.kit.toml` holding `[lanes] not_hard_paths = "acme/app:lib/session/"`: adding `lib/session/x.sh` makes `floor` print `full auth: lib/session/x.sh`. Same result with the entry only in the working-tree copy.
- [ ] AC6 (one call, full lane): on an empty run, `override-lane r1 full "hard path false positive"` exits 0; `show r1` holds one `| GATE | <g> | override | hard path false positive [lane-override lane=full gate=<g>]` line per gate of `required full`, and one `| ACTION | lane-override lane=full gates=<n> written=<n> reason=hard path false positive` line; `check full r1` and `check full r1 --kit-lanes` exit 0.
- [ ] AC7 (kit-root union, live gap): a temp project with a committed `.kit.toml` whose `[lane.full]` drops `design-critique` and `reflect`, `KIT_PROJECT_ROOT` set to it: `start r7 full full spec-feature`, then `override-lane r7 full "fp"`; `check full r7 --kit-lanes` exits 0 and `show r7` holds override lines for `design-critique` and `reflect`.
- [ ] AC8 (refusals): `override-lane r8 full ""`, `override-lane r8 full "   "`, `override-lane r8 bogus "x"`, `override-lane r8 mega "x"` (a lane only a project block could name), and `override-lane '@@@' full "x"` (normalizes to an empty rid; `///` does not, it becomes `---`) each exit 64, and no ledger file exists for `r8` afterward.
- [ ] AC9 (forwarder): `bash bin/gate ledger override-lane r9 full "fp"` exits 0 and `bash lib/gate/gate-ledger.sh check full r9` exits 0.
- [ ] AC10 (no relabel): with `record r10 build ran "built"` first, `override-lane r10 full "fp"` writes one override line per gate of `required full` except `build`, and prints `build already-disposed`.
- [ ] AC11 (recorded refusal blocks): with `record r11 design-record skipped "critical: missing invariant"` first, `override-lane r11 full "fp"` exits 64, stderr names `design-record` and `critical: missing invariant`, and `show r11` holds only the seeded line. With `record r11 design-record ran "pass"` added after it, the same call exits 0.
- [ ] AC12 (guard unchanged): after AC6, `override r1 design "hard path false positive [lane-override lane=full gate=spec]"` exits 65; the AC6/AC7/S3 rows already in `tests/test-ledger-durability.sh` stay green.
- [ ] AC13 (not silent): the AC6 call prints a `LANE-OVERRIDE:` stderr line naming `r1`, `full`, and the count.
- [ ] AC14 (counter): with an isolated log dir holding the AC6 ledger and one plain ledger, `lane-telemetry.sh report` prints `lane-override runs: 1`; with only the plain ledger, no `lane-override` line.
- [ ] AC15 (docs): `grep -n "override-lane" lib/gate/README.md docs/WORKFLOW.md lib/gate/gate-ledger.sh` hits all three; `grep -n "not_hard_paths" lib/gate/README.md` hits; the README names the trade-off (one reason covers every gate of a lane) and says operator-run only.
- [ ] AC16 (no regression): `bash tests/test-lane-classify.sh`, `bash tests/test-lanes-data.sh`, `bash tests/test-ledger-durability.sh`, `bash tests/test-lane-telemetry.sh`, `bash tests/test-meta.sh` all exit 0.

## Test plan

| Case | AC | Kind |
|---|---|---|
| reader: one valid scoped entry kept; five malformed entries rejected with one stderr line each | AC1 | unit, negative |
| reader: origin of another repo, and no origin at all, yield nothing | AC1 | unit, negative |
| reader: SSH, HTTPS, `.git`/no `.git`, mixed-case origin forms normalize to the same id | AC1 | unit, edge |
| reader: the shipped `kit.toml` entry resolves for a `dwarvesf/dwarves-kit` origin | AC2 | unit |
| floor + explain: exempt path prints nothing (stdout) and the `excluded` line | AC3 | unit (real git) |
| floor: `src/session/index.ts`, `src/session/authenticate.ts`, `middleware/session.js`, `lib/sessions/x.sh`, `lib/auth/session.sh` stay `full auth`; `lib/session-tools/x.sh` stays not hard | AC4 | unit (real git) |
| floor: exempt path plus a real auth path reports the real one | AC4 | unit (real git) |
| floor: committed and working-tree project `.kit.toml` entries exempt nothing | AC5 | negative control |
| existing `case_floor_paths`, `floor-timing`, `floor-timing-30k`, `floor-non-ascii`, SPEC-296 block | AC16 | regression |
| `override-lane` on an empty run: one tagged line per gate, one ACTION line, both checks pass | AC6 | unit |
| project lane drops two phases, `start` writes their skips, `override-lane` still covers them, `--kit-lanes` check passes | AC7 | unit (real git) |
| five refusal shapes exit 64 and write nothing | AC8 | unit, negative |
| `bin/gate ledger override-lane` forwards | AC9 | unit |
| a ran gate is skipped, not relabelled | AC10 | unit |
| a `skipped "critical: ..."` gate refuses the call; a later `ran` clears it | AC11 | unit, negative |
| hand `override` reusing a tagged reason on another gate exits 65 | AC12 | regression |
| `LANE-OVERRIDE:` stderr line | AC13 | unit |
| report counts lane-override runs, silent at 0 | AC14 | unit |
| docs greps | AC15 | static |

Negative controls (each must turn a named row red; dry traces in `## Grounding`):

- NC-1: the reader also reads the project `.kit.toml`. AC5 goes red.
- NC-2: the reader ignores the `owner/repo` scope. AC1's other-origin row goes red.
- NC-3: the floor's auth pass ignores the exempt list. AC3 goes red.
- NC-4: `override-lane` uses only the project-resolved `required`. AC7 goes red.
- NC-5: `override-lane` treats every `skipped` line as disposed. AC11 goes red.
- NC-6: `override-lane` skips the lane validation. AC8's `bogus` and `mega` rows go red.
- NC-7: the tag is dropped from each reason. AC6 goes red at the second gate.

## Verification

```bash
bash tests/test-lane-classify.sh
bash tests/test-lanes-data.sh
bash tests/test-ledger-durability.sh
bash tests/test-lane-telemetry.sh
bash tests/test-meta.sh
KIT_CONFIG_OPERATOR=/nonexistent bash lib/classify/lane-classify.sh floor "$PWD" 5030a8cc^ 5030a8cc   # prints nothing on stdout, one excluded line on stderr
```

## Grounding

Live samples, run 2026-10-02 in this worktree unless marked code-traced.

**S1, the retro diff at the floor today.**

```
$ git show --stat --format= 5030a8cc
 docs/verification/observe-cost-dedup.md            | 45 +++++++++++
 lib/session/observe/bin/session-observe            | 89 ++++++++++++++++------
 .../dddddddd-0000-0000-0000-000000000000.jsonl     |  4 +
 .../subagents/agent-a.jsonl                        |  3 +
 lib/session/observe/tests/smoke.sh                 | 20 +++++
$ KIT_PROJECT_ROOT=/nonexistent lane-classify.sh floor "$PWD" 5030a8cc^ 5030a8cc
full auth: lib/session/observe/bin/session-observe
```

Every auth-kind path in that diff is under `lib/session/`, so the exemption empties the auth pass. No path in it matches another kind or the kit's own `extra_hard_paths` (`^hooks/|^lib/gate/|^lib/classify/|^lib/config/|^kit[.]toml$`).

**S2, the fixture paths today** (`explain --files <p> "add a flag"`, reason line, `KIT_PROJECT_ROOT=/nonexistent`):

```
src/session/index.ts           reason: hard path in --files (auth: src/session/index.ts)
src/session/authenticate.ts    reason: hard path in --files (auth: src/session/authenticate.ts)
middleware/session.js          reason: hard path in --files (auth: middleware/session.js)
lib/session/x.sh               reason: hard path in --files (auth: lib/session/x.sh)
```

A fixture repo adding all four, `floor <fixture> main`: `full auth: lib/session/x.sh` (first by line order). After the change, the AC1 overlay exempts only `lib/session/x.sh`, and the floor reports the next auth hit.

**S3, the population the kit entry exempts:** `git ls-files | grep -Ei <_HP_auth>` returns 93 paths, every one under `lib/session/` (round 1 Grounding S3). No other auth hit exists in the kit tree, so `dwarvesf/dwarves-kit:lib/session/` is the whole list.

**S4, the knob and the repo id today.**

```
$ source lib/config/kit-config.sh; _kit_toml_get kit.toml lanes not_hard_paths
(empty)
$ git remote get-url origin
git@github.com:dwarvesf/dwarves-kit.git
$ sed -n 31,33p lib/config/kit-config.sh
kit_config_root()     { printf '%s' "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml"; }
kit_config_operator() { printf '%s' "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml"; }
kit_config_project()  { printf '%s' "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml"; }
```

`kit_config_root` follows the environment; `lane-data.sh`'s `_ld_kit_file` is pinned to the install. Hence the reader uses `_ld_kit_file` with `kit_config_get_root`'s order.

**S5, unknown and project-only lanes today.**

```
$ gate-ledger.sh required bogus; echo rc=$?
unknown lane 'bogus' (no valid [lane.bogus] data in kit.toml)
rc=1
$ gate-ledger.sh required mega; echo rc=$?
unknown lane 'mega' (no valid [lane.mega] data in kit.toml)
rc=1
```

Code-traced: `lane_resolve` (`lane-data.sh:86`) accepts only the five kit lane names, so a project `[lane.mega]` block never makes a lane. The kit-root half of the union can fail only on malformed kit data; it then counts as empty.

**S6, the kit-root gap, live.** Temp repo, committed `.kit.toml` with `[lane.full] phases` minus `design-critique`, `ui-design`, `reflect`; `KIT_PROJECT_ROOT` set to it; isolated log dir:

```
$ gate-ledger.sh required full
think design spec validate design-record test-plan build review docs ship
$ gate-ledger.sh start pr1 full full spec-feature; gate-ledger.sh show pr1
... | START | lane=full classified=full type=spec-feature repo=gate-false-positive-relief
... | GATE | design-critique | skipped | repo lane override (.kit.toml)
... | GATE | ui-design | skipped | repo lane override (.kit.toml)
... | GATE | reflect | skipped | repo lane override (.kit.toml)
$ for g in $(required full); do override pr1 $g "fp $g"; done
$ check full pr1; echo rc=$?
rc=0
$ check full pr1 --kit-lanes; echo rc=$?
MISSING-GATE: design-critique (required for lane 'full'; no ran/override entry in the ledger)
MISSING-GATE: reflect (required for lane 'full'; no ran/override entry in the ledger)
rc=1
```

This is the gap AC7 pins. It also shows why a `repo lane override (.kit.toml)` skip must not be a refusal AND must still get an override line.

**S7, the guard today** (isolated log dir):

```
$ override demo think "false-positive hard path"; echo rc=$?
rc=0
$ override demo design "false-positive hard path"; echo rc=$?
override rejected: reason already used for another gate in run 'demo' -- each gate override needs its own reason
rc=65
```

Code-traced, not sampled: `gate-ledger.sh:69` sets `LANES_KIT_ONLY=""` at load, so an exported `LANES_KIT_ONLY=1` does not reach `required`; the kit-root list is read with the in-script prefix form `LANES_KIT_ONLY=1 required`, as `check()` does at `gate-ledger.sh:479`. Round 1's S5 claim of a live kit-only count was not a live sample and is withdrawn.

**S8, baselines before any change:** `tests/test-lane-classify.sh` `38/38 passed`; `tests/test-lanes-data.sh` `PASS floor-paths`, `PASS floor-timing (180ms for 1000 paths)`, `PASS floor-timing-30k (1757ms for 30000 paths)`; `tests/test-ledger-durability.sh` `37/37 passed`.

**Dry traces of the negative controls.**

- NC-1. Mutation: `lane_not_hard_paths` adds `kit_config_project` to its layers. Fixture: AC5 (committed project entry `acme/app:lib/session/`, origin `acme/app`, operator `/nonexistent`). Path: `floor` -> `_floor_scan` -> auth grep hits `lib/session/x.sh` -> exempt list now holds `lib/session/` -> hit dropped -> stdout empty. Red: AC5 (`expected 'full auth: lib/session/x.sh', got ''`).
- NC-2. Mutation: the reader skips the origin comparison. Fixture: AC1 with origin `other/app`. Path: the valid entry passes validation, the scope check is gone, `lib/session/` prints. Red: AC1's other-origin row (`expected no output`).
- NC-3. Mutation: `_floor_scan`'s auth pass uses the raw first grep hit. Fixture: AC3. Path: auth grep hits `lib/session/observe/bin/session-observe`, no filter, `full auth: ...` printed. Red: AC3 (`expected empty stdout`).
- NC-4. Mutation: the gate set is the project-resolved `required` only. Fixture: AC7. Path: the set lacks `design-critique` and `reflect` (S6), no lines written for them, `check --kit-lanes` lists both. Red: AC7 (`expected rc=0, got 1`).
- NC-5. Mutation: the refusal scan is removed. Fixture: AC11's seeded `design-record skipped "critical: missing invariant"`. Path: `design-record` has no ran/override, so it gets an override line; exit 0. Red: AC11 (`expected exit 64 and one ledger line`).
- NC-6. Mutation: the `required` exit codes are ignored. Fixture: `override-lane r8 bogus "x"`. Path: both lists empty, zero gates, the ACTION line is written, exit 0. Red: AC8 (`expected 64, ledger r8 exists`).
- NC-7. Mutation: no tag. Fixture: AC6. Path: gate 1 writes; gate 2 reaches `override()`'s guard, which finds the same reason on gate 1 and returns 65; the verb propagates it. Red: AC6 (`expected exit 0, got 65`).

## Edge Cases

1. `lib/sessions/`: not the listed prefix, so it stays full (prefix compare is literal and ends at `/`). `lib/session-tools/` never matched `_HP_auth` and stays not hard.
2. An exempt path that is also an extra hard path (a kit `.kit.toml` entry like `^lib/session/`): still full; the exemption covers the auth kind only.
3. A fork or mirror with a different origin: nothing exempt; the fork pays the override path. Safe side.
4. A repo with no `origin` remote: nothing exempt.
5. Han's operator overlay sets `not_hard_paths`: it replaces the kit root value (first non-empty layer wins), so the overlay must restate the kit entry to keep it. The README says so.
6. A diff that both deletes and adds under `lib/session/`: renames list both sides (existing `--no-renames` behavior); both sides are exempt or not by the same prefix test.
7. `override-lane` where every gate already ran: writes no override line, writes the ACTION line with `written=0`, exits 0.
8. `override-lane` twice with the same reason: the second call finds every gate disposed and writes 0 gate lines.
9. A reason with ` | ` or a newline: `oneline` collapses newlines; the guard's `$5..NF` reconstruction handles ` | ` (S3 row).
10. A `Validate skipped "incomplete: reviewer 3 dead"` line: a refusal under the rule (any skip other than the `.kit.toml` one). The operator re-runs validation or overrides that gate by hand.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A real auth change under an exempt prefix ships without the full lane | Someone adds auth code to `lib/session/` in the kit | The prefix is one repo's transcript tooling; the task-text auth flags still suggest full; review-team runs on `lib/` changes (AGENTS.md); the entry is one line to remove |
| A PR exempts its own diff | A `not_hard_paths` entry in a project `.kit.toml` | The reader never reads the project file (AC5, NC-1) |
| The kit's entry exempts a consumer's `lib/session/` | Consumer auth code under `lib/session/` ships normal | Entries are repo-scoped by origin (AC1, NC-2) |
| `override-lane` papers over a refused gate | A `skipped "critical: ..."` gate later shows an override | Refusal rule 4 (AC11, NC-5) |
| `override-lane` becomes the default habit | `lane-override runs:` grows in `lane-telemetry report` | The counter (AC14); every use leaves an ACTION line and tagged GATE lines |
| A partial write mid-loop | Exit non-zero after k lines | The message names k; a re-run finds written gates disposed |

## Out of Scope

- Any change to `_HP_auth`, other hard-path kinds, or `extra_hard_paths`.
- Exempting non-auth kinds (DEC-9).
- Advertising `override-lane` in the ship-gate's BLOCKED message (DEC-4).
- The task-text auth regex (SPEC-296).
- `middleware/session-store.js`: not a hard path today; making it one is a widening (round 1 DEC-2, kept in the implementation notes).

## Touches

- lib/classify/**
- lib/gate/**
- lib/config/**
- lib/telemetry/**
- tests/**
- docs/WORKFLOW.md

## Decision Log

- DEC-1: T1 is an explicit root-resolved exclusion, not a pattern narrowing. Rejected: round 1's path-meaning plus diff-signal rule. Three reviewers reproduced misses that were full before (`authenticate.ts`, `acl.ts`, `SessionToken.ts`, `secure: false`, `maxAge`, a deleted `httpOnly`). A word list cannot be complete, and every hole is a security regression. The exclusion opens no hole outside the listed prefix.
- DEC-2: The list is read from the operator overlay and the pinned kit root only. A project `.kit.toml` (working tree or HEAD) is never read, because a PR can edit it. `kit_config_root` is not used, because it follows `KIT_CONFIG_ROOT`/`DWARVES_KIT` from the environment.
- DEC-3 (security trade-off, stated plainly): `override-lane` lets ONE reason dispose every required gate of a lane. That deliberately relaxes the per-gate distinct-reason guard (exit 65), whose purpose is to stop one reason pasted across all gates. Bounds: the single-gate `override` keeps the guard; every gate gets its own tagged GATE line, read by `check()`, the ship-gate, `progress` and `lane-telemetry` as today; one ACTION line, one stderr line, and the telemetry counter mark the event; a gate that ran is never relabelled; a gate with a recorded refusal blocks the call. Accepted risk: an agent that wants to skip a lane can now do it in one call instead of twelve. The guard never stopped that; it made it tedious, and the tedium fell hardest on honest false positives. Autonomy: `override-lane` is operator-run only. No kit command, skill, or hook invokes it, and `lib/gate/README.md` says so. The round 1 autonomy-gate finding (R4 W2) was weighed: an unattended loop already can call `override`, so the verb adds speed, not a new capability. The counter is the detection.
- DEC-4: The ship-gate BLOCKED message keeps pointing at per-gate `override`. Advertising `override-lane` at the block point would make the bypass the path of least resistance.
- DEC-5: New verb `override-lane`, not a magic `all-lane` phase (E) and not `plan-record` (F).
- DEC-6: The gate set is the union of the project-resolved and kit-root `required` lists. S6 shows the kit-root half is load-bearing for the floor's `--kit-lanes` check.
- DEC-7: Refusals exit 64 ("wrote nothing, correct the argument"), matching `plan-record` and `validate-round`; `check()` keeps exit 1.
- DEC-8: The kit entry also lowers the negative-control obligation for `lib/session/` edits under `[gate] negative_control = full`, because `proof-ledger.sh _negctl_required` reads the same floor. Intended: those paths were never auth.
- DEC-9: The exclusion covers the auth kind only, with no per-entry kind field. The only observed false positive is auth; migration, secret, ci, infra and kit-config hits carry no known false positive. A kind field would be unused configuration.
- DEC-10 (security trade-off for T1): `not_hard_paths` is the first config that subtracts from a hard path. Bounds: root-only read (DEC-2), repo-scoped entries, literal directory prefixes, auth kind only, and every exemption printed by `explain` and the direct `floor` run.
- DEC-11: The ACTION line carries the reason with `=` mapped to `:` (`tr '=' ':'`), as `debt()` and `config` do, not a hash. The same reason is already in full on every GATE line, so a hash would hide nothing; the mapping keeps the ACTION line's `key=value` fields unforgeable and the line readable in `show`.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
