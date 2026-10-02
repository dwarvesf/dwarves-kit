# Spec: gate false-positive relief (a root-only hard-path exclusion, one audited lane-wide override)
Generated: 2026-10-02
Status: DRAFT (round 1 and round 2 NEEDS REVISION folded per the lead's binding briefs)
Lane: full
Type: spec-feature
Depth: blind-spot (failure: a hard-path exemption or a lane-wide override lets a real auth change, or a refused gate, ship without the full lane)
File: `docs/specs/SPEC-384-gate-false-positive-relief.md`
References: `docs/retro/RETRO-2026-10-02-observe-cost-dedup.md` (the two action items this spec closes); `lib/gate/lane-data.sh` (`lane_extra_hard_paths`: union of layers, "invalid entry: one stderr line, skip"); `lib/config/kit-config.sh` (`kit_config_operator`, `_kit_toml_get`); `lib/classify/lane-classify.sh` (`_path_kind`, `_floor_scan`, `explain`); `hooks/ship-gate.sh` (`_floor_hit`, `_floor_check`, the `OFF-BY-CONFIG` log line); `lib/gate/gate-ledger.sh` (`override`, `required`, `check`, `start`, `plan_record`'s refuse-before-write); `lib/telemetry/lane-telemetry.sh` (`report`, the `boardless runs` line); `tests/test-lanes-data.sh` (`mkrepo`, `mkrepo_remote`, `run_hook`, `case_floor_paths`); `tests/test-ledger-durability.sh` (AC6/AC7/S3, the override guard); `docs/implementation-notes/gate-false-positive-relief.md` (the builder-facing delta)

## Problem

PR #877 edited `lib/session/observe/bin/session-observe`, a transcript-session tool. Two gate behaviors turned a small fix into a slog.

1. **False positive.** `_HP_auth` lists `sessions?` as a bare path segment. The kit's own `lib/session/` module holds 93 tracked files, and every one hits the auth hard path. The ship-gate floor then demanded the full lane's required gates.
2. **Override cost.** Recovering needed one `gate-ledger.sh override <rid> <phase> "<reason>"` call per required gate. The ledger rejects a reason already used for a different gate (exit 65), so each call needed an invented suffix, and 11 first attempts failed.

## Solution

### Approaches considered

T1, the false positive:

- **A. Narrow `_HP_auth` by pattern** (round 1's design). Tradeoff: recall holes. Three reviewers reproduced misses that were full before (`src/session/authenticate.ts`, `acl.ts`, `SessionToken.ts`, `secure: false`, `maxAge`, a deleted `httpOnly`). No word list closes them.
- **B. An explicit, root-resolved exclusion list** `[lanes] not_hard_paths`: exact, host-qualified, repo-scoped directory prefixes removed from the auth kind only, every use audited. Tradeoff: the first config knob that subtracts from a hard path.
- **C. Do nothing in the classifier; rely on T2.** Tradeoff: every edit to `lib/session/` pays one override call forever, and the override trail fills with known noise.

T2, the override:

- **D. New verb `override-lane <rid> <lane> <reason>`.** One call writes one GATE override line per required gate, each reason tagged with the gate.
- **E. Magic phase `override <rid> all-lane <reason>`** (the retro's wording). Overloads the phase argument of an existing verb.
- **F. Reuse `plan-record --override`.** Needs every plan phase named and still enforces distinct reasons.

### Chosen approach + why

B for T1. It changes nothing for any path not listed, in any repo, so no recall hole opens. The list is never read from a project `.kit.toml`, so a PR cannot exempt its own diff. Each entry names one `host/owner/repo`, read from the repo's local git config with the git environment scrubbed, so the kit's own entry cannot exempt a consumer's `lib/session/`. Every exemption the ship-gate applies leaves an `EXEMPT` line in `ship-gate.log`. A was rejected for its recall holes (DEC-1); C leaves the cost in place.

D for T2. A dedicated verb leaves `override`'s contract and its 65 guard byte-identical, and makes a lane-wide override a distinct, greppable, counted event (DEC-5).

### Extensibility & boundaries

- T1 grows by entries, not code. A second known false positive is one more `host/owner/repo:prefix/` entry. It only ever touches the auth kind; a new kind would need a new spec (DEC-9).
- T2 reads `required <lane>`, so a lane that gains a gate is covered with no code change.
- Units, each testable alone:
  - `lane_not_hard_paths <root>` (lane-data.sh): resolve layers, validate, identify the repo, print prefixes. One purpose: answer "which auth prefixes are exempt in this repo".
  - The classifier consumes that list in `_path_kind` (one path) and `_floor_scan` (many paths) and reports each exemption on stderr.
  - The ship-gate turns floor's exemption lines into `EXEMPT` log lines.
  - `override_lane` (gate-ledger.sh) composes `required`, a ledger read, and `override`.
  - The telemetry counter reads tagged GATE lines only.

### Architecture

See `## Design`.

## Picture

```
 T1: the auth kind with a root-only, audited exclusion

   operator overlay kit.toml ──┐  (ignored when it lives inside <root>'s work tree
                               │   or is tracked by git)
   pinned kit root kit.toml ───┴─► UNION of [lanes] not_hard_paths entries
                                        │   (never the project .kit.toml)
                                        ▼
                           lane_not_hard_paths <root>   (loaded once per process)
                             validate entry ── bad ──► one stderr line, entry ignored
                             repo id = host/owner/repo from
                               env -u GIT_* git -C <root> config --local --get remote.origin.url
                             no origin / not a repo / unparseable ──► no exemptions
                             keep entries whose id == repo id
                                        │  literal prefixes, e.g. "lib/session/"
                                        ▼
   changed path ──► _HP_auth (unchanged) ── no ──► other kinds, extras (unchanged)
                          │ yes
                          ▼
                    path has an empty, "." or ".." segment? ── yes ──► full auth
                          │ no
                          ▼
                    path starts with an exempt prefix (literal, case-sensitive)?
                          │ no ──► full auth  (as today)
                          ▼ yes
                    auth kind skipped for this path; stderr:
                    "floor: excluded <path> by [lanes] not_hard_paths: <entry>"
                    (explain: "excluded: <path> by ...")
                          │
                          ▼
   hooks/ship-gate.sh _floor_hit ──► each "floor: excluded" line ──►
        ship-gate.log:  <ts> | EXEMPT | <rid> | <path> | <entry>


 T2: override-lane flowchart (gate-ledger.sh)

   override-lane <rid> <lane> "<reason>"
        │ rid normalizes empty, or the rid's ledger has no START line? ──► exit 64
        │ reason empty after trim? ──► exit 64
        │ lane unknown to BOTH project and kit-root `required`? ──► exit 64
        ▼
   gates = required(lane) ∪ (LANES_KIT_ONLY=1 required(lane) || empty)
        │
        │ any gate with a `skipped` line and no ran|override line, where the skip is
        │ not the exempt `.kit.toml` skip of a gate the project lane really dropped?
        │   ── yes ──► exit 64; per gate: name, recorded reason, and the remedy
        │              `override <rid> <phase> "<reason>"`; nothing written
        ▼
   for each gate g with no ran|override line:
        override(<rid>, g, "<reason> [lane-override lane=<lane> gate=<g>]")
        ▼
   ACTION: lane-override lane=<lane> gates=<n> written=<k> reason=<reason, = as :>
   stderr: LANE-OVERRIDE: <k> gate(s) of lane <lane> overridden for run <rid> ...
        ▼
   check(), check --kit-lanes, ship-gate, progress read the GATE lines as today;
   lane-telemetry report counts runs with a tagged GATE line
```

## Design

Design-bearing: yes. T1 adds the first config knob that subtracts from a hard path; T2 relaxes an audit guard on purpose.

### Approaches considered + chosen

See `## Solution`.

### Diagram

See `## Picture` (two flowcharts). ASCII by house rule.

### ADR link(s)

`docs/decisions/0024-gate-ledger-and-ship-enforcement.md` owns the override path; `docs/decisions/0037-lanes-as-data-light-default.md` describes `extra_hard_paths` as add-only. Each gains a one-line amendment note pointing at DEC-3 and DEC-10 of this spec (TASK-7). Both changes revert with one commit, and no ledger line format changes, so no new ADR.

### Boundaries & failure modes

Out of bounds: the `_HP_auth` regex itself (unchanged), every non-auth kind, `extra_hard_paths`, the task-text auth regex (SPEC-296), and `proof-ledger.sh override`. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**T1a, the knob: `[lanes] not_hard_paths` (read by `lib/gate/lane-data.sh`).**

- Value: one string of whitespace-separated entries, split with `set -f` so no entry globs. Entry form: `<host>/<owner>/<repo>:<prefix>`.
  - `<host>/<owner>/<repo>`: three components, each `[A-Za-z0-9._-]+`, compared lowercased (via `tr`, bash 3.2 safe). More or fewer components: rejected.
  - `<prefix>`: a repo-relative directory prefix of one or more plain segments, each `[A-Za-z0-9._-]+` and neither `.` nor `..`, ending in `/`. A one-segment prefix (`lib/`) is accepted with one warning line.
- Rejected entries: no `host/owner/repo:` scope; empty prefix; prefix `/` or starting with `/`; a `.`, `..` or empty segment; any glob or regex character (`*?[]{}()|^$\+`); no trailing `/`. Each prints `lane-data: not_hard_paths entry '<e>' rejected: <why>; ignored` once per process, then is skipped.
- Layers: the UNION of the operator overlay (`kit_config_operator`) and the kit root pinned by lane-data (`_ld_kit_file`), as `lane_extra_hard_paths` unions its layers. Never the project `.kit.toml`, in the working tree or at HEAD. `kit_config_root` is not used, because it follows `KIT_CONFIG_ROOT`/`DWARVES_KIT` from the environment. The union cannot widen another repo, because every entry is repo-scoped.
- The operator overlay is ignored, with one stderr line, when its real path (`cd "$(dirname f)" && pwd -P`) is inside `<root>`'s work tree or the file is tracked by any git repo. An agent cannot point `KIT_CONFIG_OPERATOR` at a file it commits.
- Repo id of `<root>`: `env -u GIT_DIR -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM git -C <root> config --local --get remote.origin.url`. No `insteadOf` rewriting (not `git remote get-url`). Normalize: strip a scheme (`https://`, `ssh://`, `git://`), userinfo (`user@`), and a `:port`; turn the scp form `host:owner/repo` into `host/owner/repo`; strip trailing `/` and `.git`; lowercase. The result must be exactly three components, else no id.
- Fail closed: not a repo, no origin, an unparseable URL, or any failing git call means no exemptions. Every new git call is guarded (`|| true`) so `set -euo pipefail` never aborts the caller.
- New reader `lane_not_hard_paths <root>`: prints `<prefix>\t<entry>` for each valid entry whose id equals the repo id.
- Kit root default: `kit.toml` `[lanes]` gains `not_hard_paths = "github.com/dwarvesf/dwarves-kit:lib/session/"`, commented as the kit's transcript tooling. `lib/config/module-registry.md` gains its row.
- Invariant: an empty or absent value, or no matching entry, changes nothing anywhere.

**T1b, the classifier: `lib/classify/lane-classify.sh`.**

- `_HP_auth` is unchanged, byte for byte.
- Root: `floor` uses its own `<root>` argument, never `KIT_PROJECT_ROOT` from the environment. `--files` verbs use `${KIT_PROJECT_ROOT:-$(git rev-parse --show-toplevel)}`.
- The exempt list is loaded and cached once per process in the parent shell (not inside a `$(...)` subshell, which would drop the cache and repeat the warnings), like `_load_extras`.
- Prefix compare is literal and case-sensitive: a path is under prefix `p` when its first `${#p}` characters equal `p` (`case "$path" in "$p"*)` with `p` quoted, or `index(path, p) == 1` in awk). Never a regex, so `.` in a prefix matches only `.`. `lib/Session/x.sh` is not under `lib/session/`.
- A `--files` path with an empty, `.` or `..` segment, or a leading `./` or `/`, is never exempt (fails closed to full). Floor paths come from git and are already canonical.
- `_path_kind <path>`: when the auth kind matches and the path is exempt, the auth kind does not count; the path still runs through the remaining kinds and `extra_hard_paths`.
- `explain --files`: one extra line `excluded: <path> by [lanes] not_hard_paths: <entry>` per exempted auth hit. `classify` and `risk` print their single word unchanged.
- `floor`: the auth pass takes the first auth hit, by original path-list line number, whose path is not exempt; one grep plus one awk filter keeps the line numbers. Each exempted auth hit prints `floor: excluded <path> by [lanes] not_hard_paths: <entry>` on stderr.
- Scope of the relief: it removes the auth hard path only. `classify`, `risk` and `explain` may still SUGGEST full for the same path through the kit-machinery flag (any `lib/` or `hooks/` file). The relief is for the ship-gate floor.
- Invariant: a path with no exempt prefix classifies exactly as today.

**T1c, the audit: `hooks/ship-gate.sh`.**

- `_floor_hit` captures floor's stderr instead of discarding it. Each `floor: excluded <path> by [lanes] not_hard_paths: <entry>` line becomes one `ship-gate.log` line `<ts> | EXEMPT | <rid> | <path> | <entry>`, written the way `OFF-BY-CONFIG` lines are (best effort, never changes the exit code). Every exempted path is logged, including one whose diff still went full through another path; the log is a superset of the exemptions that changed a result.
- No other ship-gate behavior changes. `proof-ledger.sh` keeps discarding floor stderr (it reads floor for the negative-control rule, not for enforcement; DEC-8).

**T2, `override-lane <rid> <lane> <reason...>` in `lib/gate/gate-ledger.sh`.**

- Refusals, all before any write, each exit 64 with nothing written:
  1. missing rid or lane; a rid that `runid` normalizes to empty; a rid whose ledger has no `START` line (a typo rid);
  2. a reason empty after `oneline` and whitespace trim;
  3. an unknown lane: the project-resolved `required <lane>` and the kit-root `LANES_KIT_ONLY=1 required <lane>` (the in-script prefix form, as `check()` uses; an exported value is reset at `gate-ledger.sh:69`) both fail;
  4. a recorded refusal: a gate in the set has a `skipped` line and no `ran` or `override` line. A gate counts as disposed when it has any `ran` or `override` line, whatever the order, exactly as `check()` reads it. The one exempt skip is `repo lane override (.kit.toml)` on a gate the project-resolved lane actually dropped (in the kit-root set, not in the project set); that string on any other gate is a refusal. The message names each refused gate, its recorded reason, and the remedy: `gate-ledger.sh override <rid> <phase> "<reason>"` per gate, then rerun. Rule 4 is a guard against careless use, not a security control: the single-gate `override` stays one call away.
- Gate set: the union of the project-resolved and kit-root lists, deduplicated, in kit plan order. A kit-root `required` that exits non-zero counts as an empty kit set, guarded against `set -e`.
- An exempt `.kit.toml` skip is not a refusal, and that gate still gets an override line, because `check --kit-lanes` counts only `ran`/`override` (Grounding S6).
- Gates with a `ran` or `override` line are skipped and named (`<phase> already-disposed`), never relabelled.
- Each remaining gate is written by the existing `override()` with reason `<reason> [lane-override lane=<lane> gate=<phase>]`. The tag makes each reason distinct, so the 65 guard passes by construction and still blocks a hand-typed single-gate `override` that reuses a tagged reason.
- Then one `ACTION` line: `lane-override lane=<lane> gates=<n> written=<k> reason=<reason>`, the reason through `tr '=' ':'` as `debt()` and `config` do (DEC-11).
- stdout: one `<phase> override` or `<phase> already-disposed` line per gate, then the `check` verdict as `plan-record` prints it. stderr: `LANE-OVERRIDE: <k> gate(s) of lane <lane> overridden for run <rid> with one reason; review with: gate-ledger.sh show <rid>`.
- Exit: 0 when the writes happened (k may be 0); 64 on any refusal; a non-zero from `override()` propagates with a message naming how many lines were written.
- Operator-run only (DEC-3): no kit command, skill, agent, hook, or other lib calls it.
- Invariants: no ledger line format changes; `override` and its 65 guard stay byte-identical; `check()`, `progress()`, `descent()` need no change.

**T3, the counter: `lib/telemetry/lane-telemetry.sh report`.** After the `boardless runs` line, print `lane-override runs: <n>` when n > 0. n counts run ledgers (one per rid) in the report's set holding at least one `| GATE | ... | override | ... [lane-override lane=` line, so a run whose ACTION line never landed (partial write) still counts. Silent at 0, so existing report pins hold. This counter is the DEC-3 mitigation.

### Data model changes

One config key (`[lanes] not_hard_paths`). `ship-gate.log` gains `EXEMPT` lines. The run ledger gains lines in the existing `GATE ... override` and `ACTION` shapes.

### API changes

One ledger verb (`override-lane`), in `gate-ledger.sh`'s usage line and header comment, reachable as `gate ledger override-lane` through `bin/gate`'s `ledger` forwarder.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

Numbering follows the build order. TASK-2 and TASK-4 are round 2's TASK-3a and TASK-3b. Dependencies: TASK-3 needs TASK-1; TASK-4 needs TASK-2; TASK-5 needs TASK-3; TASK-6 needs TASK-2; TASK-7 needs TASK-1 to TASK-6.

### Phase 1: Foundation

- [ ] TASK-1 (T1a, the knob): `lane_not_hard_paths <root>` in `lib/gate/lane-data.sh` (union, overlay-location guard, scrubbed repo id, validation); the `kit.toml` default entry; the `lib/config/module-registry.md` row; reader tests in `tests/test-lanes-data.sh`. Acceptance: AC1, AC2.
- [ ] TASK-2 (T2 core write path, was 3a): `override_lane` with its dispatch, usage and header lines in `lib/gate/gate-ledger.sh`: union gate set, tag, ACTION line, no-relabel; cases in `tests/test-ledger-durability.sh`. Acceptance: AC9, AC10, AC12.

### Phase 2: Core

- [ ] TASK-3 (T1b, the classifier): consume the list in `_path_kind`, `explain`, and `_floor_scan`; exemption and anchoring cases in `tests/test-lanes-data.sh`. Acceptance: AC3 to AC7.
- [ ] TASK-4 (T2 refusals and stderr, was 3b): refusal rules 1 to 4, the remedy message, the `LANE-OVERRIDE:` line; cases in `tests/test-ledger-durability.sh`; verification checks AC14 (forwarder), AC15 (guard unchanged), AC18 (operator-run only grep). Acceptance: AC11, AC13, AC16, AC14, AC15, AC18.

### Phase 3: Polish

- [ ] TASK-5 (T1c, the audit): capture floor stderr in `hooks/ship-gate.sh` `_floor_hit` and write `EXEMPT` lines; one `run_hook` case in `tests/test-lanes-data.sh`. Acceptance: AC8.
- [ ] TASK-6 (T3 counter): the `lane-override runs:` line in `lane-telemetry.sh report`; one case in `tests/test-lane-telemetry.sh`. Acceptance: AC17.
- [ ] TASK-7 (docs and stale claims): `lib/gate/README.md` (the lane-wide override, DEC-3's trade-off, the phrase "operator-run only", the remedy for a refused gate; a section "Exempting a hard path" for `not_hard_paths`, DEC-10); `docs/WORKFLOW.md` "## Gate ledger and ship enforcement" names `override-lane` next to `override`; fix the stale add-only claims at `lib/classify/lane-classify.sh` (the comment above `_HP_migration`), `kit.toml` (the `extra_hard_paths` comment), `lib/config/module-registry.md` (the `extra_hard_paths` row), and the kit repo's `.kit.toml` comment; one-line amendment notes in `docs/decisions/0037-lanes-as-data-light-default.md` and `docs/decisions/0024-gate-ledger-and-ship-enforcement.md` pointing at DEC-3 and DEC-10. Acceptance: AC19.

## After state

- [ ] `KIT_CONFIG_OPERATOR=/nonexistent lane-classify.sh floor <kit checkout> 5030a8cc^ 5030a8cc` prints nothing on stdout and `floor: excluded lib/session/observe/bin/session-observe by [lanes] not_hard_paths: github.com/dwarvesf/dwarves-kit:lib/session/` on stderr. (Today: `full auth: lib/session/observe/bin/session-observe`.)
- [ ] A ship-gate run over that kind of diff writes one `EXEMPT` line per exempted path to `ship-gate.log`. (Today: no such line exists.)
- [ ] In a fixture repo, `src/session/index.ts`, `src/session/authenticate.ts`, `middleware/session.js`, `x/lib/session/y.ts`, `lib/Session/x.sh` still hit the floor as `full auth`.
- [ ] A project `.kit.toml`, an in-repo operator overlay, or an origin read through injected git config exempts nothing.
- [ ] `gate-ledger.sh override-lane <rid> full "<reason>"` writes one tagged override line per gate of the union set, and `check full <rid>` and `check full <rid> --kit-lanes` both exit 0. (Today: one call per gate, each with an invented reason.)

## Acceptance Criteria (global)

Classifier and hook checks run with `KIT_CONFIG_OPERATOR` pointed at a fixture overlay outside the fixture repo (or `/nonexistent`), so Han's machine overlay never leaks in. Ledger checks run with an isolated `DWARVES_KIT_LOG_DIR`. Tests derive every expected gate count from `required full`; no literal counts. Fixture repos that need refs from a bare remote set `remote.origin.url` to the github form after the push; the refs stay.

- [ ] AC1 (reader: scope, validation, union): overlay `not_hard_paths = "github.com/acme/app:lib/session/ github.com/acme/app:../x/ github.com/acme/app:/ github.com/acme/app:src/* lib/session/ acme/app:lib/x/ github.com/acme/app:docs"` and the kit root's own entry. Fixture origin `git@github.com:acme/app.git`: `lane_not_hard_paths <fixture>` prints exactly `lib/session/` with its entry; stderr has one `rejected` line for each of the other six overlay entries, once even when the reader runs twice in one process. Fixture origin `https://github.com/other/app`: prints nothing. Origin `https://gitlab.com/group/sub/app.git` (four components): prints nothing. A fixture whose origin is `github.com/dwarvesf/dwarves-kit` gets the kit root entry through the union while the overlay is set.
- [ ] AC2 (reader: identity and location hardening): (a) fixture origin `git@github.com:acme/app.git` with `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=https://github.com/dwarvesf/dwarves-kit` in the environment and `KIT_CONFIG_OPERATOR=/nonexistent`: prints nothing (the kit entry does not apply). (b) `KIT_CONFIG_OPERATOR` pointed at a directory inside the fixture work tree holding an acme entry: prints nothing and one `ignored` stderr line. (c) Shipped entry: `KIT_CONFIG_OPERATOR=/nonexistent`, fixture origin `https://github.com/dwarvesf/dwarves-kit.git`, prints `lib/session/`. `grep -n 'not_hard_paths' kit.toml lib/config/module-registry.md` hits both.
- [ ] AC3 (exempt path): `mkrepo` fixture, origin acme, the AC1 overlay. Adding `lib/session/observe/bin/session-observe` makes `floor` print nothing on stdout and `floor: excluded lib/session/observe/bin/session-observe by [lanes] not_hard_paths: github.com/acme/app:lib/session/` on stderr. `explain --files lib/session/observe/bin/session-observe "add a flag"` run inside the fixture prints `normal` first and the `excluded:` line (a `suggest: full (kit-machinery)` line may also print).
- [ ] AC4 (everything else unchanged): same fixture. Each of `src/session/index.ts`, `src/session/authenticate.ts`, `middleware/session.js`, `lib/sessions/x.sh`, `lib/auth/session.sh` makes `floor` print `full auth: <path>`; `lib/session-tools/x.sh` prints nothing (never auth). `lib/session/x.sh` plus `src/auth/login.ts` prints `full auth: src/auth/login.ts`.
- [ ] AC5 (anchoring and literal match): same fixture. `x/lib/session/y.ts` prints `full auth: x/lib/session/y.ts` (prefix anchored at the repo root). `lib/Session/x.sh` prints `full auth: lib/Session/x.sh` (case-sensitive). With an extra overlay entry `github.com/acme/app:lib/session/v1.0/` and the base entry removed, `lib/session/v1.0/x.sh` prints nothing and `lib/session/v1x0/x.sh` prints `full auth: lib/session/v1x0/x.sh` (`.` is literal).
- [ ] AC6 (non-canonical `--files` paths fail closed): inside the AC3 fixture, `classify --files <p> "add a flag"` prints `full` for `lib/session/../auth/x.ts`, `./lib/session/x.sh`, `lib/session//x.sh`, and `/lib/session/x.sh` (all auth today); none prints an `excluded:` line.
- [ ] AC7 (root-only and fail-closed, negative controls): (a) `KIT_CONFIG_OPERATOR=/nonexistent`, origin acme, a COMMITTED project `.kit.toml` with `[lanes] not_hard_paths = "github.com/acme/app:lib/session/"`: adding `lib/session/x.sh` prints `full auth: lib/session/x.sh`; same with the entry only in the working tree. (b) The AC1 overlay and a fixture with no `origin` remote: `lib/session/x.sh` prints `full auth: lib/session/x.sh`, and `src/auth/x.ts` prints `full auth: src/auth/x.ts`. (c) `KIT_PROJECT_ROOT` exported to an acme fixture while `floor` runs on a no-origin fixture: still `full auth` (floor ignores the env root).
- [ ] AC8 (audit): `run_hook` fixture (origin rewritten to `github.com/acme/app` after the push, `HOOK_OPERATOR` set to the AC1 overlay), a normal-lane spec with its gates recorded, a diff adding `lib/session/x.sh`: the hook exits 0, and `ship-gate.log` holds `| EXEMPT | x | lib/session/x.sh | github.com/acme/app:lib/session/`. Without the overlay: exit 2 with `hard path (auth`, and no `EXEMPT` line.
- [ ] AC9 (one call, full lane): after `start r1 full full spec-feature` on an empty run, `override-lane r1 full "hard path false positive"` exits 0; `show r1` holds one `| GATE | <g> | override | hard path false positive [lane-override lane=full gate=<g>]` line per gate of `required full`, and one `| ACTION | lane-override lane=full gates=<n> written=<n> reason=hard path false positive` line; `check full r1` and `check full r1 --kit-lanes` exit 0.
- [ ] AC10 (kit-root union): a temp project with a committed `.kit.toml` whose `[lane.full]` drops `design-critique` and `reflect`, `KIT_PROJECT_ROOT` set to it: `start r10 full full spec-feature`, then `override-lane r10 full "fp"` exits 0; `check full r10 --kit-lanes` exits 0 and `show r10` holds override lines for `design-critique` and `reflect`.
- [ ] AC11 (refusals 1 to 3): `override-lane r11 full ""` and `override-lane r11 full "   "` (after `start r11 ...`), `override-lane r11 bogus "x"`, `override-lane r11 mega "x"`, `override-lane '@@@' full "x"` (normalizes empty; `///` becomes `---`, a valid rid), and `override-lane nostart full "x"` (no START line) each exit 64; `show r11` holds only its START line and `show nostart` reports no ledger.
- [ ] AC12 (no relabel): after `start r12 ...` and `record r12 build ran "built"`, `override-lane r12 full "fp"` writes one override line per gate of `required full` except `build`, and prints `build already-disposed`.
- [ ] AC13 (refusal 4): after `start r13 ...` and `record r13 design-record skipped "critical: missing invariant"`, `override-lane r13 full "fp"` exits 64; stderr names `design-record`, `critical: missing invariant`, and the remedy `override r13 design-record`; `show r13` holds only the two seeded lines. After `record r13 design-record ran "pass"`, the same call exits 0. A `skipped "repo lane override (.kit.toml)"` line seeded by hand on `build` (a gate the kit-root project lane did not drop) also exits 64.
- [ ] AC14 (forwarder, verification check): `bash bin/gate ledger override-lane r14 full "fp"` (after `start r14 ...`) exits 0 and `gate-ledger.sh check full r14` exits 0.
- [ ] AC15 (guard unchanged, verification check): after AC9, `override r1 design "hard path false positive [lane-override lane=full gate=spec]"` exits 65; the AC6/AC7/S3 rows already in `tests/test-ledger-durability.sh` stay green.
- [ ] AC16 (not silent): the AC9 call prints a `LANE-OVERRIDE:` stderr line naming `r1`, `full`, and the count.
- [ ] AC17 (counter): an isolated log dir holding the AC9 ledger, a ledger with tagged GATE lines but no ACTION line, and one plain ledger: `lane-telemetry.sh report` prints `lane-override runs: 2`; with only the plain ledger, no `lane-override` line.
- [ ] AC18 (operator-run only, static): `grep -rln 'override-lane' commands skills hooks agents lib` lists only files under `lib/gate/`.
- [ ] AC19 (docs and stale claims): `grep -n 'override-lane' lib/gate/README.md docs/WORKFLOW.md lib/gate/gate-ledger.sh` hits all three; `lib/gate/README.md` contains the phrases `operator-run only`, `one reason covers every gate of a lane`, and `not_hard_paths`; `grep -n 'not_hard_paths' docs/decisions/0037-lanes-as-data-light-default.md docs/decisions/0024-gate-ledger-and-ship-enforcement.md lib/classify/lane-classify.sh .kit.toml` hits all four; `grep -nE 'no config file can remove one|nothing here can remove one' lib/classify/lane-classify.sh .kit.toml` returns nothing, and the `kit.toml` and `module-registry.md` `extra_hard_paths` text names `not_hard_paths` as the one exception.
- [ ] AC20 (no regression): `bash tests/test-lane-classify.sh`, `bash tests/test-lanes-data.sh`, `bash tests/test-ledger-durability.sh`, `bash tests/test-lane-telemetry.sh`, `bash tests/test-config-registry.sh`, `bash tests/test-docs-wiring.sh`, `bash tests/test-meta.sh` all exit 0.

## Test plan

| Case | AC | Kind |
|---|---|---|
| reader: one valid host-scoped entry kept; six malformed entries rejected once each per process | AC1 | unit, negative |
| reader: other repo, four-component id, no origin yield nothing; union brings in the kit entry beside an overlay | AC1 | unit |
| reader: SSH scp, `ssh://`, HTTPS with userinfo and port, `.git`/no `.git`, mixed case normalize to one id | AC1 | unit, edge |
| reader: env-injected `remote.origin.url` does not change the id | AC2 | negative control |
| reader: in-repo operator overlay ignored with a stderr line | AC2 | negative control |
| reader: the shipped `kit.toml` entry resolves for a `dwarvesf/dwarves-kit` origin | AC2 | unit |
| floor + explain: exempt path, empty stdout, `excluded` stderr line | AC3 | unit (real git) |
| floor: five session-auth paths stay `full auth`; `lib/session-tools/` never auth; a real auth path wins over an exempt one | AC4 | unit (real git) |
| floor: nested `x/lib/session/y.ts` stays full | AC5 | negative control (anchoring) |
| floor: `lib/Session/x.sh` stays full | AC5 | edge (case) |
| floor: `v1.0/` prefix exempts `v1.0/` only, not `v1x0/` | AC5 | negative control (literal) |
| `--files` paths with `..`, `./`, `//` never exempt | AC6 | negative control |
| project `.kit.toml` entry (committed, dirty) exempts nothing | AC7 | negative control |
| no origin: no exemption, real auth still full; env `KIT_PROJECT_ROOT` ignored by floor | AC7 | negative control |
| ship-gate writes `EXEMPT` lines; without the overlay it blocks and logs none | AC8 | unit (hook, real git) |
| existing `case_floor_paths`, `floor-timing`, `floor-timing-30k`, `floor-non-ascii`, SPEC-296 block | AC20 | regression |
| `override-lane` happy path: tagged lines from the union set, ACTION line, both checks pass | AC9 | unit |
| project lane drops two phases; their `.kit.toml` skips still get override lines; `--kit-lanes` passes | AC10 | unit (real git) |
| six refusal shapes (rules 1 to 3) write nothing | AC11 | unit, negative |
| a ran gate is skipped, not relabelled | AC12 | unit |
| a `critical:` skip refuses with the remedy; a later `ran` clears it; a `.kit.toml` skip on an undropped gate refuses | AC13 | unit, negative |
| `bin/gate ledger override-lane` forwards | AC14 | verification |
| hand `override` reusing a tagged reason exits 65 | AC15 | regression |
| `LANE-OVERRIDE:` stderr line | AC16 | unit |
| report counts tagged runs, partial run included, silent at 0 | AC17 | unit |
| `override-lane` callers confined to `lib/gate/` | AC18 | static |
| docs, ADR notes, stale claims | AC19 | static |

Negative controls (each must turn a named row red; dry traces in `## Grounding`):

- NC-1: the reader also reads the project `.kit.toml`. AC7(a) goes red.
- NC-2: the reader ignores the repo id. AC1's other-repo row goes red.
- NC-3: the floor's auth pass ignores the exempt list. AC3 goes red.
- NC-4: the prefix compare becomes unanchored (substring anywhere in the path). AC5's nested `x/lib/session/y.ts` row goes red.
- NC-5: the prefix compare becomes a regex match. AC5's `v1x0` row goes red.
- NC-6: the repo id is read with `git remote get-url origin` (or without the env scrub). AC2(a) goes red.
- NC-7: `override-lane` uses only the project-resolved `required`. AC10 goes red.
- NC-8: `override-lane` treats every `skipped` line as disposed. AC13 goes red.
- NC-9: `override-lane` skips the lane validation. AC11's `bogus` and `mega` rows go red.
- NC-10: the tag is dropped from each reason. AC9 goes red at the second gate.
- NC-11: `_floor_hit` keeps `2>/dev/null`. AC8's `EXEMPT` line is missing.

## Verification

```bash
bash tests/test-lane-classify.sh
bash tests/test-lanes-data.sh
bash tests/test-ledger-durability.sh
bash tests/test-lane-telemetry.sh
bash tests/test-config-registry.sh
bash tests/test-docs-wiring.sh
bash tests/test-meta.sh
# Must print nothing on stdout AND one line on stderr:
#   floor: excluded lib/session/observe/bin/session-observe by [lanes] not_hard_paths: github.com/dwarvesf/dwarves-kit:lib/session/
KIT_CONFIG_OPERATOR=/nonexistent bash lib/classify/lane-classify.sh floor "$PWD" 5030a8cc^ 5030a8cc
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

Every auth-kind path in that diff is under `lib/session/`. None matches another kind or the kit's `.kit.toml` extras (`^hooks/|^lib/gate/|^lib/classify/|^lib/config/|^kit[.]toml$`).

**S2, fixture and anchoring paths today** (`explain --files <p> "add a flag"`, reason line, `KIT_PROJECT_ROOT=/nonexistent`):

```
src/session/index.ts           reason: hard path in --files (auth: src/session/index.ts)
src/session/authenticate.ts    reason: hard path in --files (auth: src/session/authenticate.ts)
middleware/session.js          reason: hard path in --files (auth: middleware/session.js)
lib/session/x.sh               reason: hard path in --files (auth: lib/session/x.sh)
x/lib/session/y.ts             reason: hard path in --files (auth: x/lib/session/y.ts)
lib/Session/x.sh               reason: hard path in --files (auth: lib/Session/x.sh)
lib/session/v1.0/x.sh          reason: hard path in --files (auth: lib/session/v1.0/x.sh)
lib/session/v1x0/x.sh          reason: hard path in --files (auth: lib/session/v1x0/x.sh)
lib/session/../auth/x.ts       reason: hard path in --files (auth: lib/session/../auth/x.ts)
./lib/session/x.sh             reason: hard path in --files (auth: ./lib/session/x.sh)
lib/session//x.sh              reason: hard path in --files (auth: lib/session//x.sh)
lib/sessions/x.sh              full
lib/session-tools/x.sh         normal
lib/auth/session.sh            full
```

`_HP_auth` matches case-insensitively, so `lib/Session/x.sh` is auth today; the case-sensitive prefix keeps it full. Every AC5 and AC6 row is full today and must stay full.

**S3, the population the kit entry exempts:** `git ls-files | grep -Ei <_HP_auth>` returns 93 paths, every one under `lib/session/` (round 1 sample). No other auth hit exists in the kit tree.

**S4, the repo id: spoofable reads vs the scrubbed read.** Fixture with origin `git@github.com:acme/app.git`:

```
$ git config --get remote.origin.url
git@github.com:acme/app.git
$ GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=https://github.com/dwarvesf/dwarves-kit \
    git config --get remote.origin.url
https://github.com/dwarvesf/dwarves-kit
$ GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=https://github.com/dwarvesf/dwarves-kit \
    env -u GIT_DIR -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM \
    git config --local --get remote.origin.url
git@github.com:acme/app.git
$ git -c url.https://github.com/dwarvesf/dwarves-kit.insteadOf=git@github.com:acme/app.git remote get-url origin
https://github.com/dwarvesf/dwarves-kit
```

The environment and `insteadOf` both spoof the plain reads; the scrubbed `--local` read does not. In this worktree the scrubbed read returns `git@github.com:dwarvesf/dwarves-kit.git` (a linked worktree reads the common config), and `git config --get-regexp 'url\..*insteadof'` finds nothing.

**S5, config layers today.**

```
$ source lib/config/kit-config.sh; _kit_toml_get kit.toml lanes not_hard_paths
(empty)
$ sed -n 31,33p lib/config/kit-config.sh
kit_config_root()     { printf '%s' "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml"; }
kit_config_operator() { printf '%s' "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml"; }
kit_config_project()  { printf '%s' "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml"; }
$ gate-ledger.sh required bogus; echo rc=$?     # and the same for mega
unknown lane 'bogus' (no valid [lane.bogus] data in kit.toml)
rc=1
```

Code-traced: `lane_resolve` (`lane-data.sh:86`) accepts only the five kit lane names, so a project `[lane.mega]` block never makes a lane.

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

**S7, the guard and fail-closed floor today** (isolated log dir; fixtures):

```
$ override demo think "false-positive hard path"; echo rc=$?
rc=0
$ override demo design "false-positive hard path"; echo rc=$?
override rejected: reason already used for another gate in run 'demo' -- each gate override needs its own reason
rc=65
$ floor <fixture, no origin, adds src/auth/x.ts> main
full auth: src/auth/x.ts
$ floor <non-repo dir> main
(nothing)
```

Code-traced: `gate-ledger.sh:69` sets `LANES_KIT_ONLY=""` at load; the kit-root list uses the in-script prefix form, as `check()` at `gate-ledger.sh:479`. `hooks/ship-gate.sh:186` runs floor with `2>/dev/null`, so today an exemption line could never reach a log; `:174` and `:198` show the `OFF-BY-CONFIG` line shape the `EXEMPT` line copies. `tests/test-lanes-data.sh` `run_hook` passes `KIT_CONFIG_OPERATOR="${HOOK_OPERATOR:-/nonexistent}"`, the seam AC8 uses.

**S8, baselines before any change:** `tests/test-lane-classify.sh` `38/38 passed`; `tests/test-lanes-data.sh` `PASS floor-paths`, `PASS floor-timing (180ms for 1000 paths)`, `PASS floor-timing-30k (1757ms for 30000 paths)`; `tests/test-ledger-durability.sh` `37/37 passed`.

**Dry traces of the negative controls.**

- NC-1. Mutation: the reader adds `kit_config_project`. Fixture: AC7(a). Path: `floor` -> `_floor_scan` -> auth grep hits `lib/session/x.sh` -> list now holds `lib/session/` -> hit dropped -> empty stdout. Red: AC7(a).
- NC-2. Mutation: no id comparison. Fixture: AC1, origin `other/app`. Path: the valid entry prints. Red: AC1's other-repo row.
- NC-3. Mutation: the auth pass uses the raw first grep hit. Fixture: AC3. Path: `full auth: lib/session/observe/bin/session-observe` printed. Red: AC3.
- NC-4. Mutation: `case "$path" in *"$p"*)`. Fixture: AC5, `x/lib/session/y.ts`. Path: `lib/session/` occurs inside the path, so the hit is dropped; empty stdout. Red: AC5 nested row.
- NC-5. Mutation: the compare uses `grep -E "^$p"`. Fixture: AC5 with entry `lib/session/v1.0/`. Path: `.` matches `x`, `lib/session/v1x0/x.sh` dropped. Red: AC5 `v1x0` row.
- NC-6. Mutation: the id comes from `git remote get-url origin` without the scrub. Fixture: AC2(a). Path: the injected value yields `github.com/dwarvesf/dwarves-kit`; the kit root entry matches; `lib/session/` prints. Red: AC2(a).
- NC-7. Mutation: the gate set is the project-resolved list only. Fixture: AC10. Path: no lines for `design-critique` and `reflect`; `check --kit-lanes` lists both (S6). Red: AC10.
- NC-8. Mutation: the refusal scan is removed. Fixture: AC13. Path: `design-record` gets an override line; exit 0. Red: AC13.
- NC-9. Mutation: `required` exit codes ignored. Fixture: `override-lane r11 bogus "x"`. Path: both lists empty, zero gates, ACTION line written, exit 0. Red: AC11.
- NC-10. Mutation: no tag. Fixture: AC9. Path: gate 2 hits `override()`'s guard, 65 propagates. Red: AC9.
- NC-11. Mutation: `_floor_hit` keeps `2>/dev/null`. Fixture: AC8. Path: the hook exits 0, but floor's stderr is dropped and no `EXEMPT` line lands. Red: AC8.

## Edge Cases

1. `lib/sessions/`: not the listed prefix, so it stays full. `lib/session-tools/` never matched `_HP_auth`.
2. An exempt path that is also an extra hard path: still full; the exemption covers the auth kind only.
3. A fork or mirror with a different origin: nothing exempt. Safe side.
4. A repo with no origin, or a non-github host the entry does not name: nothing exempt.
5. Layers are a union: Han's operator overlay adds entries beside the kit root's; it cannot remove the kit entry, and it does not need to restate it. Each entry still binds one repo.
6. A rename out of `lib/session/` into `src/auth/`: both sides are listed (`--no-renames`); the `src/auth/` side stays full.
7. `override-lane` where every gate already ran: writes no override line, writes the ACTION line with `written=0`, exits 0.
8. `override-lane` twice with the same reason: the second call finds every gate disposed and writes 0 gate lines.
9. A reason with ` | ` or a newline: `oneline` collapses newlines; the guard's `$5..NF` reconstruction handles ` | `.
10. `Validate skipped "incomplete: reviewer 3 dead"`: a refusal under rule 4; the remedy names `override <rid> validate`.
11. An agent rewrites `.git/config`'s origin to the kit's URL in a consumer repo: the kit entry applies there, and every exempted path lands as an `EXEMPT` line (DEC-10).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A real auth change under an exempt prefix ships without the full lane | Auth code lands in the kit's `lib/session/` | `EXEMPT` lines in `ship-gate.log`; the task-text auth flags still suggest full; review-team runs on `lib/` changes (AGENTS.md); one line removes the entry |
| A PR exempts its own diff | An entry in a project `.kit.toml` | Never read (AC7, NC-1) |
| The kit entry exempts a consumer's `lib/session/` | Consumer auth code under `lib/session/` ships normal | Entries are host/owner/repo scoped (AC1, NC-2) |
| Origin spoofed through git environment or `insteadOf` | A consumer resolves to the kit's id | Scrubbed `--local` read (AC2, NC-6) |
| Origin spoofed by editing `.git/config` | Same | Residual risk, stated in DEC-10; `EXEMPT` lines show it |
| `override-lane` used carelessly over a refused gate | A `critical:` skip later shows an override | Rule 4 refuses and names the single-gate remedy (AC13); a guard against careless use, not a control |
| `override-lane` becomes the default habit | `lane-override runs:` grows in `lane-telemetry report` | The counter (AC17) is the DEC-3 mitigation |
| A partial write mid-loop | Exit non-zero after k lines | The message names k; a re-run finds written gates disposed; the counter still counts the run |

## Out of Scope

- Any change to `_HP_auth`, other hard-path kinds, or `extra_hard_paths` matching.
- Exempting non-auth kinds (DEC-9).
- Advertising `override-lane` in the ship-gate's BLOCKED message (DEC-4).
- The task-text auth regex (SPEC-296), and the kit-machinery suggestion for `lib/` files.
- `middleware/session-store.js`: not a hard path today (implementation notes).

## Touches

Not dispatch-eligible: `gate_touches` cannot express the root files below as directory prefixes and marks them unprovable, so `/kit:dispatch` would serialize or reject this spec. Run it with `/kit:execute`.

- lib/classify/**
- lib/gate/**
- lib/config/**
- lib/telemetry/**
- tests/**
- hooks/ship-gate.sh
- kit.toml
- .kit.toml
- docs/WORKFLOW.md
- docs/decisions/0024-gate-ledger-and-ship-enforcement.md
- docs/decisions/0037-lanes-as-data-light-default.md

## Decision Log

- DEC-1: T1 is an explicit root-resolved exclusion, not a pattern narrowing. Rejected: round 1's path-meaning plus diff-signal rule, for its reproduced recall holes. The exclusion opens no hole outside the listed prefix.
- DEC-2: The list is the union of the operator overlay and the pinned kit root. A project `.kit.toml` (working tree or HEAD) is never read, because a PR can edit it. An operator overlay inside the repo, or tracked by git, is ignored, because an agent could commit it. `kit_config_root` is not used, because it follows `KIT_CONFIG_ROOT`/`DWARVES_KIT` from the environment.
- DEC-3 (security trade-off, stated plainly): `override-lane` lets ONE reason dispose every required gate of a lane. That deliberately relaxes the per-gate distinct-reason guard (exit 65), whose purpose is to stop one reason pasted across all gates. Bounds: the single-gate `override` keeps the guard; every gate gets its own tagged GATE line, read by `check()`, the ship-gate, `progress` and `lane-telemetry` as today; one ACTION line and one stderr line mark the event; a gate that ran is never relabelled. Rule 4 (refused gates) is a guard against careless use, not a control: the single-gate `override` is one call away. The mitigation is detection: the `lane-override runs:` counter (T3). Accepted risk: an agent that wants to skip a lane can now do it in one call instead of twelve; the 65 guard never stopped that, it made it tedious, and the tedium fell hardest on honest false positives. Autonomy: `override-lane` is operator-run only; no kit command, skill, agent, hook, or other lib calls it (AC18), and `lib/gate/README.md` says so. The round 1 autonomy finding (R4 W2) was weighed: an unattended loop can already call `override`, so the verb adds speed, not a capability.
- DEC-4: The ship-gate BLOCKED message keeps pointing at per-gate `override`. Advertising `override-lane` there would make the bypass the path of least resistance.
- DEC-5: New verb `override-lane`, not a magic `all-lane` phase (E) and not `plan-record` (F).
- DEC-6: The gate set is the union of the project-resolved and kit-root `required` lists. S6 shows the kit-root half is load-bearing for the floor's `--kit-lanes` check.
- DEC-7: Refusals exit 64 ("wrote nothing, correct the argument"), matching `plan-record` and `validate-round`; `check()` keeps exit 1.
- DEC-8: The kit entry also lowers the negative-control obligation for `lib/session/` edits under `[gate] negative_control = full`, because `proof-ledger.sh _negctl_required` reads the same floor. Intended: those paths were never auth. That caller keeps discarding floor stderr; the `EXEMPT` audit lives on the enforcement path (the ship-gate).
- DEC-9: The exclusion covers the auth kind only, with no per-entry kind field. The only observed false positive is auth.
- DEC-10 (security trade-off for T1, stated plainly): `not_hard_paths` is the first config that subtracts from a hard path. Bounds: never read from the project file; repo-scoped by `host/owner/repo`; identity from a scrubbed `--local` config read (no environment config, no `insteadOf`); literal, anchored, case-sensitive directory prefixes; non-canonical paths never exempt; auth kind only; fail closed without a usable origin; and every exemption on the enforcement path written as an `EXEMPT` line. Residual risk: `.git/config` is local and agent-writable. An agent that rewrites a consumer repo's origin to the kit's URL gets `lib/session/` exempted there. That gains nothing beyond what the hand-typed `override` already allows (one call per gate, with reasons), and each exempted path leaves an `EXEMPT` line.
- DEC-11: The ACTION line carries the reason with `=` mapped to `:`, as `debt()` and `config` do, not a hash. The full reason is already on every GATE line.
- DEC-12: The relief is floor-only. `classify`, `risk` and `explain` stop counting an exempt path as an auth hard path, but the kit-machinery flag still suggests full for any `lib/` or `hooks/` file. That flag is advisory and never blocks.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
