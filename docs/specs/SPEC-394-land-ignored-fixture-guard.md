# Spec: land refuses a branch whose touched paths hold ignored files
Generated: 2026-10-04
Status: DRAFT
Lane: full (`lib/wrap/` is kit machinery; the guard decides whether `wrap land` pushes and squash-merges onto a default branch)
Depth: standard (every git output shape this spec rests on was sampled live; see ## Grounding)
Type: spec-feature
File: `docs/specs/SPEC-394-land-ignored-fixture-guard.md`
References: `lib/wrap/wrap-land.sh` `cmd_land` (the pre-push refusals and their exit codes; the `st0` read at line 273 is the same `git status --porcelain --ignored=matching` shape this guard reads); `lib/gate/lane-data.sh` `lane_extra_hard_paths` (a list knob read as the union of layers, with `_kit_toml_get` per file); `lib/gate/gate-policy.sh` `--at` (a project knob that weakens a gate is read from a committed base, never the branch's working tree)

## Problem

A builder's tests read a fixture that matched a `.gitignore` pattern (`*.raw.json`). The file existed in the worktree, so the suite and the proof were green. Nobody committed it, so a clean checkout failed. The lead caught it only through a manual `git status --ignored --porcelain <tool>` check.

`wrap land` already refuses a dirty tree, but an ignored file is not "dirty" to git. Its own dirty check filters `!!` lines out on purpose (`wrap-land.sh:274`). So nothing on the landing path asks the one question that matters here: does the branch depend on a file a clean checkout will not have?

## Solution

### Approaches considered

1. **Guard inside `cmd_land`, before the push.** Read the ignored entries with `git status --porcelain -z --ignored=matching`. Keep the ones under the unit directories the branch's diff touches. Drop build output by an allowlist, and refuse when any remain. One function, one call site, zero network.
2. **Guard in `hooks/ship-gate.sh` on every push.** Covers a plain `git push` too, so wrap step 10's push path and a hand push would also be guarded. But hooks must not read `kit.toml` at runtime (the standing lint), so the repo knob cannot live there. It would also block every push in every adopted repo, a much larger blast radius than the incident asks for.
3. **Name-reference match.** Refuse only an ignored file whose basename appears in the diff's added lines. Precise when a test names its fixture, blind when it globs a directory (`fixtures/*.raw.json`) or builds the path. Rejected: it misses the common case.

### Chosen approach + why

Approach 1. It sits on the landing path the brief names, reuses the status shape `cmd_land` already reads, and costs one `git status` call. Approach 2 trades the repo knob and a small blast radius for coverage this incident does not need; it is recorded under Out of Scope.

### Which verbs get the guard

- `wrap land`: yes. It pushes a local worktree's branch, so the tree that ran the tests is right there.
- `wrap adopt`: yes, for free. It calls `cmd_land` (`wrap-adopt.sh:458`, `:460`).
- `wrap merge`: no. It merges a PR that GitHub already holds. It has no worktree contract: the branch may have no local worktree, or one at another commit. The push that carried the branch happened earlier, by `land` or by hand, so a guard here would judge an unrelated tree.

### Extensibility & boundaries

- The load-bearing dimension is the count of ignored entries in the worktree. `--ignored=matching` reports an ignored directory as one entry and git does not descend into it, so a huge `node_modules/` costs one line (measured: 50,001 files, 0.043 s).
- One helper, `_land_ignored_guard`, with one purpose: print the offending paths and return non-zero. It is testable through `wrap land` with the existing gh stub.

## Picture

```
 wrap land <wt>
   │
   ├─ dirty check (st0, `!!` lines filtered)      existing
   ├─ fetch origin/<def>, ahead > 0               existing
   ├─ open-PR lookup, already-landed path ──────► tidy, return   existing
   │
   ├─ _land_ignored_guard <wt> <base> <def>       NEW
   │     │
   │     ├─ git diff --name-only -z <base> HEAD ──► unit dirs (first 2 dir components;
   │     │                                            a root file scopes root children only)
   │     ├─ git status --porcelain -z --ignored=matching ──► `!!` entries
   │     ├─ keep entries under a unit dir
   │     ├─ drop entries matching the allowlist
   │     │     built-in ∪ operator kit.toml ∪ kit-root kit.toml
   │     │     ∪ project .kit.toml AS origin/<def> HOLDS IT
   │     └─ any left? ──► "LAND REFUSED", name each path, return 1
   │
   ├─ PR template check                            existing
   └─ push, PR, merge, tidy                        existing
```

## Design

### Approaches considered + chosen

See `## Solution`. Chosen: a pre-push guard inside `cmd_land`.

### Diagram

See `## Picture`.

### Decisions in order of cost to change

1. **The knob's trust model.** `[wrap] land_ignored_allow` weakens the guard, so a branch must not widen its own allowlist. The project layer is read from `git show refs/remotes/origin/<def>:.kit.toml`, never from the worktree. The operator `kit.toml` and the kit-root `kit.toml` are read as they are. The value is the union of every layer, as `lane_extra_hard_paths` does it. A repo that wants an entry lands the knob in its own PR first, or the operator sets it machine-wide.
2. **The scope rule.** A path the diff touches (added, modified, deleted, both sides of a rename via `--no-renames`) scopes its unit directory: its first two directory components, or fewer when the path is shallower. `tools/x/tests/test_x.py` scopes `tools/x`, `tests/test-x.sh` scopes `tests`. An ignored entry is in scope when its path starts with `<unit>/`. A file at the repo root scopes only the root's direct children (`fixture.raw.json`, `.env`), never the whole repo. Why two components: the incident's tool layout (`tools/<name>/`) and the kit's (`lib/<subsystem>/`) both put the unit there, and a fixture in a sibling directory (`tools/x/fixtures/` beside `tools/x/tests/`) is still caught.
3. **The allowlist match.** An entry without `/` is a glob matched against each path component (`dist`, `*.tsbuildinfo`). An entry with `/` is a glob matched against the whole repo-relative path or a leading part of it (`tools/circle/data`). The trailing `/` of a directory entry is stripped before matching.
4. **The built-in list.** The brief names `node_modules`, `.wrangler`, `dist`, `*.tsbuildinfo`. This spec adds `__pycache__`, `.pytest_cache`, `.venv`, `target` and `.DS_Store`, because the live sample shows the four alone would refuse almost every Python land. ops-toolkit has 45 `__pycache__/` and 11 `.venv/` entries; the kit has 10 `__pycache__/`, one `.venv/`, one `target/`. `.DS_Store` sits in the operator's global excludes and appears in touched directories. The lead may trim the list back to the brief's four (DEC-4).
5. **The exit.** Return 1, the code `cmd_land` uses for the other local-state refusals (dirty tree, detached HEAD). Nothing is pushed and no PR is opened or edited.

### ADR link(s)

None. The guard is reversible and adds one refusal to an existing verb.

### Boundaries & failure modes

See `## Failure modes`. Out of bounds: the push path outside `wrap land` (a hand `git push`, wrap step 10's in-worktree push), and the ship-gate hook.

## Technical Design

### Interfaces (I/O contract)

- Inputs: the worktree path, the merge base of `refs/remotes/origin/<def>` and the branch, the default branch name. It reads `git diff --name-only -z --no-renames <base> HEAD`, `git status --porcelain -z --ignored=matching`, the operator and kit-root `kit.toml` files, and `git show refs/remotes/origin/<def>:.kit.toml`.
- Output on refusal (stderr):
  ```
       LAND REFUSED: 2 ignored paths under what feat/x touches; a clean checkout will not have them
         tools/x/fixtures/a.raw.json
         tools/x/data/
       commit each one (git add -f), delete it, or allow it in [wrap] land_ignored_allow (operator kit.toml, or the project .kit.toml on origin/main)
  ```
  At most 20 paths, then `and <N> more`. A directory entry keeps its trailing `/`. Paths print raw (from `-z`), never git's C-quoted form.
- Exit: 0 when nothing in scope survives the allowlist; 1 on a refusal; 1 when the base is empty (no merge base), naming that the check could not be scoped.
- Invariants: the guard writes nothing; it runs only after the already-landed path; it runs before the PR-template check and the push.

### Data model changes

A new `kit.toml` key, `[wrap] land_ignored_allow = ""`: a space-separated list of globs, same shape as `wrap.roots` and `wrap.build_lanes`. A value cannot contain `#` (the resolver's line-oriented rule).

### API changes

`wrap land` gains one refusal. No new flag: an override goes through the knob, never a per-run bypass (AGENTS.md "Pause if": validation removal needs a human).

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-1: `_land_ignored_guard <wt> <base> <def>` in `lib/wrap/wrap-land.sh`, and its call in `cmd_land` after the already-landed block and before the PR-template check. AC: the four negative controls below go red when their mutation is applied, and green without it.

### Phase 2: Core
- [ ] TASK-2: the knob. Union of the built-in list, the operator file, the kit-root file, and the project file at `origin/<def>`; entries split without glob expansion against the cwd. A `[wrap] land_ignored_allow = ""` line in the kit-root `kit.toml`, and a `lib/config/module-registry.md` row. AC: Test plan rows 6 to 9 pass; `bash tests/test-config-registry.sh` exits 0.
- [ ] TASK-3: tests in a new `sec_ignored_guard` section of `tests/test-wrap-land.sh`, one case per Test plan row. AC: `LAND_ONLY=ignored bash tests/test-wrap-land.sh` exits 0.

### Phase 3: Polish
- [ ] TASK-4: docs. The `wrap land` paragraph in `commands/wrap.md` gains one sentence on the refusal and the knob; `MANUAL.md` too if it describes land's refusals. AC: `bash tests/run-all.sh --changed --time` shows no red suite.

## After state

- [ ] `wrap land` on a branch whose touched unit holds an ignored `*.raw.json` exits 1, prints `LAND REFUSED` and the path, and pushes nothing. (Today: it pushes and merges.)
- [ ] The same land with the fixture committed (`git add -f`) exits 0.
- [ ] An ignored `node_modules/` or `dist/` under a touched unit does not refuse.
- [ ] A `land_ignored_allow` entry the branch itself adds to `.kit.toml` does not allow anything; the same entry on `origin/<def>` does.
- [ ] `LAND_ONLY=ignored bash tests/test-wrap-land.sh` exits 0.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Tests cover the happy path and every Edge Case below.
- [ ] No regression: `bash tests/run-all.sh --changed --time` shows no red suite. The existing land fixtures keep an ignored `ignored.bin` at the worktree root while the branch touches `specs/` and `docs/`; those cases must stay green unchanged.

## Test plan

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Ignored `tools/x/fixtures/a.raw.json`, branch touches `tools/x/test_x.sh` | happy refusal | After state 1 | exit 1; output has `LAND REFUSED` and the path; bare origin has no `feat/land`; no `pr create` in the stub calls |
| 2 | Same fixture committed with `git add -f` | happy pass | After state 2 | exit 0, `merged #` line |
| 3 | Ignored `other/far.raw.json`, branch touches only `tools/x/` | edge: outside the diff | Edge 1 | exit 0 |
| 4 | Ignored `tools/x/node_modules/` with many files, plus `tools/x/dist/`, `tools/x/a.tsbuildinfo`, `tools/x/.wrangler/` | edge: build output | Edge 2, After state 3 | exit 0 |
| 5 | Nested `tools/x/.gitignore` ignores `secret.txt`; the file exists | edge: nested rule | Edge 3 | exit 1, names `tools/x/secret.txt` |
| 6 | A project `.kit.toml` on the branch adds `*.raw.json` | negative: self-widening | Edge 8, After state 4 | exit 1 |
| 7 | The same entry committed on origin's default branch | knob on base | After state 4 | exit 0 |
| 8 | An operator `kit.toml` (`KIT_CONFIG_OPERATOR`) allows `tools/x/fixtures` | knob, path entry | Decision 3 | exit 0 |
| 9 | An allow entry `*.json` while the cwd holds `a.json` | edge: no glob expansion | Edge 9 | the entry still matches by pattern; exit 0 for `x.raw.json` |
| 10 | Tracked-and-ignored file in a touched unit | edge | Edge 4 | exit 0 |
| 11 | Repo with no `.gitignore`, `.git/info/exclude` lists `fixture.bin` in a touched unit | edge | Edge 5 | exit 1, names it |
| 12 | Root file touched, ignored `.env` at root; ignored `deep/x.raw.json` | edge: root scope | Edge 6 | exit 1 names `.env` only, never `deep/x.raw.json` |
| 13 | Ignored path with a space | edge: quoting | Edge 7 | the refusal prints the raw path, no quotes |
| 14 | Branch already landed (squash on origin) with an ignored fixture | edge: order | Edge 10 | `already landed` path runs, no refusal |

## Verification

```bash
LAND_ONLY=ignored bash tests/test-wrap-land.sh
bash tests/test-config-registry.sh
bash tests/run-all.sh --changed --time
```

## Edge Cases

1. An ignored file outside every touched unit: passes. The guard is about what the branch could depend on, not the whole tree.
2. A huge `node_modules/`: one `!!` entry, matched by component, passes. Git does not descend, so the cost stays flat.
3. A nested `.gitignore`: git applies it, and the entry shows with its full path. Same rule as any other entry.
4. A file both tracked and matching an ignore pattern: git lists it as tracked, never `!!`. It is committed, so it passes.
5. A repo with no `.gitignore`: `.git/info/exclude` and the operator's global `core.excludesFile` still produce `!!` lines. They count the same: the file is still absent from a clean checkout.
6. A file at the repo root touched: only the root's direct children are in scope, so `CHANGELOG.md` never puts the whole repo in scope.
7. A path with spaces, quotes, or non-ASCII: read with `-z`, printed raw.
8. A branch that adds its own allow entry: ignored, because the project layer comes from `origin/<def>`. An absent `.kit.toml` on origin means no project layer.
9. An allow entry such as `*.json`: split without pathname expansion, so a file in the cwd never rewrites it.
10. A branch already on the default branch: the already-landed path runs first and tidies; the guard never runs.
11. No merge base: the guard cannot scope, so it refuses by name (exit 1). GitHub refuses a PR with no common history anyway.
12. An adopted PR (one already open for the branch): the guard runs before the re-push, so it refuses before the merge too.
13. An ignored directory entry such as `tools/x/data/`: named with its trailing `/`; an allow entry `data` or `tools/x/data` covers it.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| False positive: legitimate local state (a `.envrc`, a tool's `data/`) in a touched unit | `LAND REFUSED` naming that path | operator `kit.toml` entry now, or a project `.kit.toml` entry landed first |
| False negative: the fixture sits outside the unit dirs (a root-level test reading `testdata/x` at depth 2) | the clean-checkout failure the guard exists to stop | known ceiling of the two-component rule, written as a `ponytail:` comment at the scope code |
| `git status` fails | non-zero exit from the read | refuse (exit 1), naming the failed read; never treat an unreadable tree as clean |
| A wrong allow entry hides a real fixture | none at land time | entries are reviewed where they live: the operator's own file, or a PR to the default branch |

## Out of Scope

- A ship-gate hook version of the guard for every push. Hooks may not read `kit.toml`, and the blast radius is every adopted repo. Wrap step 10's in-worktree `git push` stays unguarded.
- `wrap merge` (see "Which verbs get the guard").
- Detecting whether a test actually reads a given file. The guard judges presence in scope, not use.
- A per-run bypass flag.

## Touches

- lib/wrap/**
- lib/config/**
- tests/**
- commands/**
- docs/specs/**
- docs/implementation-notes/**
- docs/verification/**

The kit-root `kit.toml` and `MANUAL.md` are single files at the root; the convergence step owns them if dispatched.

## Decision Log

- DEC-1: the guard lives in `cmd_land` only. `wrap adopt` inherits it; `wrap merge` has no local tree to judge. Rejected: a ship-gate hook (no knob in hooks, estate-wide blast radius).
- DEC-2: the project knob is read from `origin/<def>`, never the branch. A PR cannot widen its own allowlist. Precedent: `gate-policy.sh --at`.
- DEC-3: the scope is the first two directory components of each touched path, root files scoping root children only. Rejected: the parent directory alone (misses sibling `fixtures/` dirs); every ancestor (collapses to the whole repo).
- DEC-4: the built-in list adds `__pycache__`, `.pytest_cache`, `.venv`, `target`, `.DS_Store` to the brief's four. Flagged for the lead: grounded in the live counts, reversible by trimming one line.
- DEC-5: no bypass flag. The knob is the only way past, and it leaves a trace.

## Grounding

All samples are read-only. Scratch repos lived under the session scratchpad; the two real repos were read with `git status` only.

**`--ignored=matching` vs the traditional mode** (scratch repo `r1`; `.gitignore` = `*.raw.json`, `node_modules/`, `dist/`, `.wrangler/`, `*.tsbuildinfo`; nested `tools/y/.gitignore` = `secret.txt`):

```
$ git status --porcelain --ignored=matching
!! other/far.raw.json
!! tools/x/fixtures/a.raw.json
!! tools/x/node_modules/
!! tools/y/secret.txt
!! web/.wrangler/
!! web/app.tsbuildinfo
!! web/dist/
$ git status --porcelain --ignored
!! other/
!! tools/x/fixtures/a.raw.json
!! tools/x/node_modules/
!! tools/y/secret.txt
!! web/
```

The traditional mode collapses a directory whose contents are all ignored (`web/`), which hides which pattern matched. `matching` keeps the matched entry, so it is the mode the guard reads, as `cmd_land`'s `st0` already does. A nested `.gitignore` match shows with its full path (`tools/y/secret.txt`). `-uall` gave the same list as the default.

**Tracked and ignored:** `tools/x/fixtures/keep.raw.json` was force-added. It never appears as `!!`. `git check-ignore` exits 1 for it (tracked), and `git check-ignore --no-index` names `.gitignore:1:*.raw.json`.

**A tracked file inside an ignored directory:** after `git add -f tools/x/node_modules/pkg/lib/m.js`, status lists the untracked siblings at finer grain (`!! tools/x/node_modules/big/`), never the tracked file. The component rule still allows it.

**Huge `node_modules/`:** 50,001 files under `tools/x/node_modules/big/`. `git status --porcelain --ignored=matching` took 0.043 s total and printed one entry for it.

**No `.gitignore`** (scratch repo `r2`, one tracked `a.txt`, a root `.env`, and a `.kit/proof-assets/` cache with its self-written `*` rule):

```
$ git status --porcelain --ignored=matching
!! .env
!! .kit/proof-assets/.gitignore
!! .kit/proof-assets/s1/
$ git -c core.excludesFile=/dev/null status --porcelain --ignored=matching
?? .env
!! .kit/proof-assets/.gitignore
!! .kit/proof-assets/s1/
```

The operator's global excludes file (`~/.gitignore`, 14 patterns, among them `.DS_Store`, `.env`, `.env.*`, `.claude/worktrees/`) makes `.env` ignored with no repo `.gitignore` at all. The proof-asset manifest is committed at `docs/verification/<slug>/assets.json` (`lib/proof/asset.sh:9`), so a visual-proof diff scopes `docs/verification`, never `.kit/`.

**Quoting:** the non-`-z` form C-quotes a path with a space; `-z` does not.

```
$ git status --porcelain --ignored=matching -- tools/x/fixtures
!! tools/x/fixtures/a.raw.json
!! "tools/x/fixtures/with space.raw.json"
$ git status --porcelain -z --ignored=matching -- tools/x/fixtures | tr '\0' '\n'
!! tools/x/fixtures/a.raw.json
!! tools/x/fixtures/with space.raw.json
```

ops-toolkit's real list carries one such quoted entry (a `.nes` file name with spaces and brackets).

**Real estates, counted by basename** (`git status --porcelain --ignored=matching`, entries reduced to their last component):

- ops-toolkit, 170 entries: `__pycache__/` 45, `session-state/` 23, `.venv/` 11, `data/` 10, `node_modules/` 8, `.DS_Store` 5, `.wrangler/` 4, `.pytest_cache/` 2, `out/` 2, plus one-off state files (`*.sqlite`, `*.jsonl`, `*.bak`).
- dwarves-kit main checkout: `.claude/goals/`, `.claude/handoffs/`, `.claude/rules/`, `.claude/worktrees/`, `__pycache__/` in 10 places, `lib/stats/.venv/`, `lib/prose-rag/rust/target/`, and a built binary `lib/prose-rag/bin/prose-rag-rs`.
- this worktree, fresh from `wrap start`: no `!!` entry at all. A hand-made worktree starts empty of ignored files, so what the guard finds is what the session wrote.

**Negative controls, dry traced:**

1. Mutation: delete the `_land_ignored_guard` call in `cmd_land`. Fixture: Test plan row 1 (`LBRANCH` writes `tools/x/test_x.sh`; an ignored `tools/x/fixtures/a.raw.json` sits in the worktree). Path: the dirty check passes (only `!!` lines), the already-landed proof is empty, the template check passes, `git push` runs. Red: row 1's "bare origin has no feat/land" and "exit 1" asserts.
2. Mutation: drop `node_modules` from the built-in list. Fixture: row 4. Path: the `tools/x/node_modules/` entry is in scope (`tools/x`) and no longer allowed. Red: row 4's "exit 0" assert.
3. Mutation: read the project layer from the worktree's `.kit.toml` instead of `origin/<def>`. Fixture: row 6 (the branch commits `.kit.toml` with `land_ignored_allow = "*.raw.json"`). Path: the entry allows the fixture and the land pushes. Red: row 6's "exit 1" assert.
4. Mutation: scope every ignored entry (skip the unit filter). Fixture: row 3 (`other/far.raw.json`, branch touches `tools/x/`). Path: the out-of-scope entry survives and refuses. Red: row 3's "exit 0" assert. Row 12 goes red too (it would name `deep/x.raw.json`).

## Open questions

(none; the lead's call on DEC-4's built-in list is flagged above)
