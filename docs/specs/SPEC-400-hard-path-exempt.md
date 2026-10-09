# Spec: per-repo hard-path exemption, read at the merge base
Generated: 2026-10-09
Status: DRAFT
Lane: full
Depth: blind-spot (failure: an exemption that a PR can use to lower its own floor, or that hides a real auth path)
References: `lib/gate/gate-policy.sh:25-51` (imitate `--at <base>`: read the project layer from `git show <base>:.kit.toml`, never the PR head); `lib/gate/lane-data.sh:180-197` (imitate the ERE validation of `extra_hard_paths`); `lib/config/kit-config.sh:105` (`kit_config_show_at`, reuse as is).

## Problem

Observed in a consumer repo: the ship-gate classified `experiments/qa-runner/cases/oracle/sd-login-locked.mjs` as an auth hard path because the file name contains "login". It then demanded every full-lane gate: twelve overrides, each needing a unique reason. The file is a test oracle. It checks the login page of a public practice website and contains no auth code.

The auth pattern has two branches (`lib/classify/lane-classify.sh:106`). The first matches auth-shaped directory or file stems (`src/auth/`, `lib/session.ts`). The second matches any basename that contains `login`, `password`, `passwd` or `jwt`. The second branch fired here (see `## Grounding`). SPEC-368 predicted this class ("Hard-path list over-fires", its Failure modes row) and offered only overrides as the interim fix.

The hard-path floor exists to force review of real auth, money and data-model changes. A fix must not weaken that. In particular, no PR may lower its own floor (SPEC-368 invariant, `lib/gate/ship-rules.sh:98-101`), and no exemption may hide `src/auth/login.ts` or `lib/session.ts`.

## Terms

- `hard_path_exempt`: a `[lanes]` key in a repo's committed `.kit.toml`, a list of EREs over changed paths. A path that matches an entry, as read at the merge base, skips the built-in path kinds except `kit-config`. The repo keeps no `CONTEXT.md`; the canonical definition is the commented key in `kit.toml` plus the rule line in `docs/WORKFLOW.md` (TASK-4).

## Solution

### Approaches considered

1. **Built-in exemption for test-fixture paths.** Skip a path under `cases/`, `fixtures/`, `oracle/` or `test/` below `experiments/` or `tests/`. Tradeoff: zero config for the observed case, but it narrows a hard path for every adopter at once. A PR can also steer it by choosing a directory name. Auth tests stop reaching the floor too, and deleting an auth test is the `weaken-validation` trigger. The next false positive (`scripts/login-smoke.sh`) would grow the list.
2. **Content check.** Skip a path whose file does not import or define auth code. Tradeoff: the PR author controls the content the check reads. The heuristic is per language, in bash, inside a hook whose timeout fails open. "Contains no auth code" is the judgment the review gate exists to make, so a regex cannot replace it.
3. **Per-repo allowlist in `.kit.toml`.** A committed `[lanes] hard_path_exempt` list, read only from the merge base. Tradeoff: it reverses SPEC-368's "a config file only adds" rule, and the repo pays one full-lane PR to add the entry. In return the exemption is narrow, reviewed by a human, and audited.
4. **Narrow the built-in regex** (drop the basename-substring branch). Tradeoff: loses real hits such as `src/LoginForm.tsx` and `utils/password_hash.py`. Rejected outright.

### Chosen approach + why

Approach 3, with these guards:

- Read the key from the project file at the merge base only. No working tree, no HEAD, no operator overlay, no kit root. A PR that adds an entry cannot use it for its own push.
- Adding or changing the entry edits `.kit.toml`, which is the `kit-config` hard path. So creating an exemption costs one full-lane PR. A human reviews it once, and later commits ride it.
- `kit-config` is never exempt. Every later change to the exemption list also meets the floor.
- An entry that matches the empty string is rejected (it would exempt every path). An invalid ERE is rejected. Both reject with one stderr line and fall back to strict.
- The match is case-sensitive: narrower than the case-insensitive kind patterns.
- The exemption covers the built-in path kinds only. Added-line data-loss signatures, submodules and `extra_hard_paths` still apply to an exempt path.
- Every exempted hit leaves a ship-gate log line, so an exemption is never silent.

Approach 1 trades a global, PR-steerable narrowing for convenience. Approach 2 trades determinism for a content guess the author controls. The cost of approach 3 is one heavy PR per repo per exemption, which is the review this rule exists to buy.

### Extensibility & boundaries

- Growth dimension: the number of exempt entries per repo. Entries are joined into one `grep -f` filter, so the scan stays one pass, as `extra_hard_paths` does (`lane-classify.sh:526-532`).
- Units: (1) the reader `lane_hard_path_exempt <root> <rev>` in `lib/gate/lane-data.sh`; (2) the filter inside `_floor_scan` and `_path_kind` in `lane-classify.sh`; (3) the log line in `ship_rule_floor`. Each is testable alone.

### Architecture

See `## Design`.

## Picture

```
 push --> hooks/ship-gate.sh --> ship_rule_floor (lib/gate/ship-rules.sh)
                                      |
                                      v
                         lane-classify.sh floor <root> <base> <head>
                                      |
           changed paths ------------+------------------------------+
                                     |                              |
           NEW: lane_hard_path_exempt <root> <base>                 |
                (git show <base>:.kit.toml, project layer only)     |
                                     |                              |
                    exempt path? --yes--> skip built-in kinds       |
                         |                except kit-config;        |
                         no               stderr "floor: exempt ..."|
                         v                                          v
             built-in kinds + extras + submodule        added-line data-loss scan
                         |                                (unchanged, exempt or not)
                         v
                 "full <kind>: <path>"  --> check full --kit-lanes --> block or pass
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds one tradeoff: the floor's stdout contract (`full <kind>: <path>` or nothing) must not change, because `ship-rules.sh:112-113` and `lib/goal/mega-merge.sh` treat any stdout as a hit. The exemption notice therefore goes to stderr.

### Diagram

```
  .kit.toml at <base>            changed path
  [lanes] hard_path_exempt            |
          |                           v
          +--> valid, non-empty-matching EREs --> path matches (case-sensitive)?
                                                     |                 |
                                                    no                yes
                                                     |                 |
                                                     v                 v
                                          all kinds apply     kit-config still applies;
                                                              migration/auth/secret/ci/infra skipped;
                                                              extras, submodule, data-loss still apply
```

### ADR link(s)

This reverses the SPEC-368 rule "a config file can only add hard paths" (`lane-classify.sh:103-104`, `docs/decisions/0037-lanes-as-data-light-default.md`). TASK-4 writes the next ADR (0039 today; take the next free number at build time).

### Boundaries & failure modes

Out of bounds: content inspection, operator-overlay exemptions, any change to the built-in patterns. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `lane_hard_path_exempt <root> <rev>` (new, `lib/gate/lane-data.sh`): prints one valid ERE per line from `git show <rev>:.kit.toml` `[lanes] hard_path_exempt`, sorted unique. Prints nothing when the file or key is absent at `<rev>`. Rejects, with one stderr line each, an invalid ERE and an ERE that matches the empty string. Exit 0 always.
- `lane-classify.sh floor <root> [<base> [<head>]]`: stdout unchanged. A path that matches an exemption at `<base>` and would otherwise hit a built-in kind other than `kit-config` prints `floor: exempt <kind>: <path> ([lanes] hard_path_exempt at <base-short-sha>)` on stderr, once per exempted path.
- `lane-classify.sh classify|explain|check|risk --files ...`: the `--files` path test applies the same exemption, read at `HEAD` of `KIT_PROJECT_ROOT` (or the cwd's toplevel). The working tree is never read.
- `ship_rule_floor`: captures the floor's stderr and writes one `EXEMPT | floor | <rid> (<kind>: <path>)` line per exemption to `ship-gate.log`. The block message and exit codes are unchanged.
- Invariants: no entry can exempt `.kit.toml`; a PR's own `.kit.toml` never affects its own floor; the built-in pattern constants do not change.

### Data model changes

New optional config key `[lanes] hard_path_exempt` (string, ERE list in the same `|`-joined form as `extra_hard_paths`). Documented, commented out, in the kit's `kit.toml`.

### API changes

None beyond the interfaces above.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: Add `lane_hard_path_exempt <root> <rev>` to `lib/gate/lane-data.sh`, reusing `kit_config_show_at` and `_kit_toml_get`. Reject invalid EREs and EREs that match the empty string. AC: with `hard_path_exempt = "^experiments/qa-runner/cases/"` committed at `main`, it prints that ERE for `main` and nothing for a commit before it; an entry `|x` prints nothing plus one stderr line.

### Phase 2: Core

- [ ] TASK-2: Apply the exemption in `_floor_scan` (`lane-classify.sh:504-540`). Filter exempt paths out of the built-in kind greps except `kit-config`. Keep the `paths` line numbers intact, because the submodule index (`links`) refers to them. Leave extras, submodule and the data-loss scan unchanged. Emit the stderr notice. AC: AC1 to AC7 below.
- [ ] TASK-3: Apply the same exemption in `_path_kind` (`lane-classify.sh:137-148`), read at `HEAD`. AC: `classify --files experiments/qa-runner/cases/oracle/sd-login-locked.mjs "add a qa oracle case"` prints `normal` in a fixture repo whose HEAD carries the exemption, and `full` when the exemption exists only in the working tree.
- [ ] TASK-4: In `ship_rule_floor` (`lib/gate/ship-rules.sh:102-126`), log each stderr exemption line as `EXEMPT | floor | <rid> (<kind>: <path>)`. AC: AC8.

### Phase 3: Polish

- [ ] TASK-5: Docs and records. Add the commented key to `kit.toml` beside `extra_hard_paths`. Add one rule sentence to `docs/WORKFLOW.md` where the floor is described: an exemption is read at the merge base, never covers `.kit.toml`, and costs a full-lane PR. Write the ADR. Add the `docs/MANUAL.md` and `docs/architecture.md` rows the doc-projection check asks for, and regenerate `docs/FEATURES.md`. AC: `bash lib/gate/doc-projection-check.sh .` and `bash lib/registry/feature-registry.sh check docs/FEATURES.md` pass.
- [ ] TASK-6: Tests in `tests/test-lanes-data.sh` (new cases added to `ALL`) and `tests/test-lane-classify.sh`, one per AC row below. AC: the Verification command passes.

## After state

- [ ] A repo whose base `.kit.toml` sets `hard_path_exempt = "^experiments/qa-runner/cases/"` ships `experiments/qa-runner/cases/oracle/sd-login-locked.mjs` with no hard-path block. (Today: `full auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs`, see Grounding.)
- [ ] `src/auth/login.ts` and `lib/session.ts` still print `full auth: <path>` from `floor`, with or without that exemption. Checkable by `bash tests/test-lanes-data.sh floor-exempt-real-auth-still-hits`.
- [ ] A PR that adds the exemption and the oracle file in one diff still blocks. Checkable by `bash tests/test-lanes-data.sh ship-exempt-in-pr-blocks`.
- [ ] `ship-gate.log` carries one `EXEMPT | floor |` line per exempted path.

## Quality requirements

none (the repo keeps no `docs/QUALITY.md`; the security invariant is pinned by AC1 to AC7 instead).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality (`floor-paths` and every existing `ship-*` case stay green)

| AC | Claim | Check | Expect |
|---|---|---|---|
| AC1 | Exempt fixture path passes (positive) | `floor-exempt-fixture-quiet`: base commits the exemption; branch adds only the oracle file | `floor` stdout empty; stderr names `floor: exempt auth:` |
| AC2 | Real auth still hits, exemption present (negative control) | `floor-exempt-real-auth-still-hits`: base has the exemption; branch adds `src/auth/login.ts`, then separately `lib/session.ts` | `full auth: src/auth/login.ts`; `full auth: lib/session.ts` |
| AC3 | Real auth still hits, no exemption (negative control) | existing `floor-paths`, extended with `src/auth/login.ts`, `lib/session.ts` | both hit |
| AC4 | A PR cannot exempt its own push (negative control) | `ship-exempt-in-pr-blocks`: one branch adds the exemption to `.kit.toml` and the oracle file | hook exit 2; stderr names `hard path (kit-config: .kit.toml` |
| AC5 | Only the base counts at the floor (negative control) | `floor-exempt-working-tree-ignored`: (A) exemption only in a dirty `.kit.toml`; (B) exemption committed on the checked-out branch, floor run against another branch that adds only the oracle file | both print `full auth: experiments/...sd-login-locked.mjs` |
| AC6 | `.kit.toml` is never exempt (negative control) | `floor-exempt-never-kit-config`: base exemption `kit`; branch edits `.kit.toml` | `full kit-config: .kit.toml` |
| AC7 | An entry that matches the empty string is rejected (negative control) | `floor-exempt-empty-match-rejected`: base exemption `\|x`; branch adds `src/auth/login.ts` | `full auth: src/auth/login.ts`; one stderr rejection line |
| AC8 | Exemptions are logged | `ship-exempt-logged`: AC1 fixture through the hook with normal-lane gates recorded | hook exit 0; `ship-gate.log` has `EXEMPT \| floor \|` naming the oracle path |
| AC9 | Data loss inside an exempt path still hits | `floor-exempt-data-loss-still-hits`: AC1 fixture, file content `DROP TABLE users;` | `full data-loss: experiments/...sd-login-locked.mjs` |

## Verification

`bash tests/test-lanes-data.sh floor-paths floor-exempt-fixture-quiet floor-exempt-real-auth-still-hits floor-exempt-working-tree-ignored floor-exempt-never-kit-config floor-exempt-empty-match-rejected floor-exempt-data-loss-still-hits ship-exempt-in-pr-blocks ship-exempt-logged ship-no-spec-blocks ship-flip-gate-in-pr && bash tests/test-lane-classify.sh && bash tests/run-all.sh --changed origin/master`

## Edge Cases

1. The base has no `.kit.toml`: no exemption, every kind applies.
2. An exempt entry also matches a real auth file the repo later adds under the exempt directory: that file skips the floor. This is the accepted cost. The human approved the directory as non-auth in a full-lane PR, and the `EXEMPT` log line keeps the skip visible.
3. A rename of `src/auth/login.ts` into an exempt directory: both sides are listed (`--no-renames`), and the source side still hits `full auth`.
4. A diff touches both an exempt path and a non-exempt hard path: the non-exempt one hits (AC2 shape).
5. The exemption ERE matches `.github/`: CI paths skip the floor for that repo. Allowed; the full-lane PR that added it is the review.
6. An entry `.*` (matches the empty string): rejected by the empty-match rule. A repo that wants the floor off uses `[gate] lane_gates = false`, which already exists and is read at the merge base.
7. Paths with non-ASCII names or newlines: the filter reads the same `paths` file the kinds read, so the existing `floor-non-ascii` handling carries over.
8. `--files` with the exemption only in the working tree: not applied (read at HEAD), so the lane stays `full` until the exemption is committed.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Exemption too broad hides real auth | `EXEMPT \| floor \|` lines name a path that is real auth code | Narrow the entry in a full-lane PR; the log is the audit trail |
| Exemption read from the head instead of the base | AC4 and AC5 go green on a mutated reader | AC4, AC5 are the pinned negative controls |
| Filter shifts `paths` line numbers and breaks submodule detection | `floor-submodule` goes red | Filter into a separate list per kind; keep `paths` intact (TASK-2) |
| Stderr notice leaks into stdout and reads as a hit | `ship-exempt-logged` exits 2 instead of 0 | Notice on stderr only (Interfaces) |
| Reader slows the hook past its timeout | `floor-timing`, `floor-timing-30k` go red | One `git show` per floor call, one `grep -f` pass |

## Out of Scope

- The consumer repo's own `.kit.toml` edit adding `^experiments/qa-runner/cases/`. That ships in the consumer repo as its own full-lane PR after this lands.
- The override UX (twelve overrides, each needing a unique reason). A separate change if still wanted.
- Content inspection and any change to the built-in pattern constants.
- An operator-overlay exemption: invisible to reviewers, so excluded on purpose.

## Decision Log

- DEC-1: per-repo `hard_path_exempt` read at the merge base. Rationale: narrow, human-reviewed, cannot be used by the PR that adds it. Rejected: built-in fixture-dir exemption (global, PR-steerable), content check (author-controlled, slow, a judgment call), narrowing the regex (loses real hits).
- DEC-2: `kit-config` is never exempt. Rationale: keeps every edit of the exemption list itself on the floor.
- DEC-3: data-loss, submodule and `extra_hard_paths` ignore the exemption. Rationale: smallest change to the floor that fixes the observed class; fails strict.
- DEC-4: case-sensitive exemption match. Rationale: narrower than the case-insensitive kinds.

## Grounding

Live sample of the current matcher (`lib/classify/lane-classify.sh` at `origin/master`). One scratch repo per path, an empty commit on `main`, the path committed on `feat/x`, then `floor <repo> main` and `classify --files <path> "add a qa oracle case"`:

```
experiments/qa-runner/cases/oracle/sd-login-locked.mjs  floor => [full auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs]
experiments/qa-runner/cases/oracle/sd-login-locked.mjs  classify --files => full
src/auth/login.ts                                       floor => [full auth: src/auth/login.ts]
src/auth/login.ts                                       classify --files => full
lib/session.ts                                          floor => [full auth: lib/session.ts]
lib/session.ts                                          classify --files => full
tests/fixtures/login.json                               floor => [full auth: tests/fixtures/login.json]
tests/fixtures/login.json                               classify --files => full
e2e/login.spec.ts                                       floor => [full auth: e2e/login.spec.ts]
e2e/login.spec.ts                                       classify --files => full
src/app.ts                                              floor => []
src/app.ts                                              classify --files => normal
```

Which branch of `_HP_auth` fires (`grep -Eic` per branch):

```
experiments/qa-runner/cases/oracle/sd-login-locked.mjs dir/stem-branch=0 basename-substring-branch=1
src/auth/login.ts dir/stem-branch=1 basename-substring-branch=1
lib/session.ts dir/stem-branch=1 basename-substring-branch=0
```

The false positive comes only from the basename-substring branch. The real auth paths hit the dir/stem branch, and `src/auth/login.ts` hits both. The kit's own `.kit.toml` shows the config value form the new key copies: `extra_hard_paths = "^hooks/|^lib/gate/|^lib/classify/|^lib/config/|^kit[.]toml$"`.

Dry traces for the negative controls:

- AC2: mutation, the filter skips every path when any exemption exists. Fixture: base `.kit.toml` with `^experiments/qa-runner/cases/`, branch adds `src/auth/login.ts`. Path: `_floor_scan` builds `paths`, the filter drops `src/auth/login.ts`, no kind hits, stdout is empty. `floor-exempt-real-auth-still-hits` goes red.
- AC4: mutation, delete the ship-gate floor call. Fixture: one branch commits the exemption plus the oracle file. Path: no floor runs, the hook exits 0. `ship-exempt-in-pr-blocks` goes red. AC4 cannot catch a reader that reads the head instead of the base: any head-only exemption is a `.kit.toml` change, which hits `kit-config` either way. AC5 pins that mutation.
- AC5: mutation, the reader reads the working tree, or the checked-out `HEAD`, instead of `<base>`. Fixture A: the oracle file committed on `feat/x`, the exemption only in a dirty `.kit.toml`. Fixture B: `feat/cfg` commits the exemption; `feat/x` (off `main`) adds only the oracle file; `feat/cfg` is checked out and the call is `floor <root> main feat/x`, the shape of a push of a branch other than the checked-out one. Path: the mutated reader finds the exemption and drops the oracle path, stdout is empty. `floor-exempt-working-tree-ignored` goes red on either variant. TASK-6 builds both.
- AC6: mutation, `kit-config` joins the exempt kinds. Fixture: base exemption `kit`, branch edits `.kit.toml`. Path: the filter drops `.kit.toml`, stdout is empty. `floor-exempt-never-kit-config` goes red.
- AC7: mutation, the reader drops the empty-match check. Fixture: base exemption `|x`, branch adds `src/auth/login.ts`. Path: `|x` matches every path, the filter drops it, stdout is empty. `floor-exempt-empty-match-rejected` goes red.
- AC9: mutation, the data-loss awk skips exempt paths. Fixture: AC1 with `DROP TABLE users;`. Path: no added-line record, stdout is empty. `floor-exempt-data-loss-still-hits` goes red.

## Open questions

- Operator decision (AGENTS.md zone 4, "narrowing a hard path"): approve reversing SPEC-368's "config only adds" rule for this guarded, merge-base-only exemption. The build waits on this answer.
