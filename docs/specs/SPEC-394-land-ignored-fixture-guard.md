# Spec: land refuses a branch whose touched paths hold ignored files
Generated: 2026-10-04
Status: DRAFT (revision 1: validate round 1 NEEDS REVISION folded, 3 criticals + lead rulings a to k)
Lane: full (`lib/wrap/` is kit machinery; the guard decides whether `wrap land` pushes and squash-merges onto a default branch)
Depth: standard (every git output shape this spec rests on was sampled live; see ## Grounding)
Type: spec-feature
File: `docs/specs/SPEC-394-land-ignored-fixture-guard.md`
References: `lib/wrap/wrap-land.sh` `cmd_land` (the pre-push refusals and their exit codes; the `st0` read at line 273 is the same `--ignored=matching` shape this guard reads); `lib/config/kit-config.sh` `kit_config_get_root` (the root-only read path for a key a project file must never loosen); `lib/config/module-registry.md` "Root-only keys" (the table `tests/test-config-registry.sh` AC10 checks)

## Problem

A builder's tests read a fixture that matched a `.gitignore` pattern (`*.raw.json`). The file existed in the worktree, so the suite and the proof were green. Nobody committed it, so a clean checkout failed. The lead caught it only through a manual `git status --ignored --porcelain <tool>` check.

`wrap land` already refuses a dirty tree, but git does not count an ignored file as dirty. The dirty check filters `!!` lines out on purpose (`wrap-land.sh:274`). So nothing on the landing path asks the question that matters here: does the branch depend on a file that a clean checkout will not have?

This spec guards `wrap land` and `wrap adopt` (which calls `cmd_land`). It does not guard wrap step 10's in-worktree `git push`, a hand `git push`, or `wrap merge`.

## Solution

### Approaches considered

1. **Guard inside `cmd_land`, before the push.** Read the ignored entries under the unit directories the branch's diff touches. Drop build output and local config by an allowlist, and refuse when any remain. One function, one call site, no network call.
2. **Guard in `hooks/ship-gate.sh` on every push.** This also covers a plain `git push`. But hooks must not read `kit.toml` at runtime (a standing lint), so the knob cannot live there. It would also block every push in every adopted repo, a much larger blast radius than this incident needs.
3. **Name-reference match.** Refuse only an ignored file whose basename appears in the diff's added lines. That is precise when a test names its fixture, but blind when the test globs a directory (`fixtures/*.raw.json`) or builds the path. Rejected because it misses the common case.

### Chosen approach + why

Approach 1. It sits on the landing path, reuses the status shape `cmd_land` already reads, and costs one `git status` call. Approach 2 is recorded under Out of Scope.

### Which verbs get the guard

- `wrap land`: yes. It pushes a local worktree's branch, so the tree that ran the tests is right there.
- `wrap adopt`: yes, by construction. It calls `cmd_land` (`wrap-adopt.sh:458`, `:460`).
- `wrap merge`: no. It merges a PR that GitHub already holds. It has no worktree contract: the branch may have no local worktree, or one at another commit. The push that carried the branch happened earlier, so a guard here would judge an unrelated tree.

### Extensibility & boundaries

- The load-bearing dimension is the count of ignored entries. `--ignored=matching` reports a wholly ignored directory as one entry and git does not descend into it. A 50,001-file `node_modules/` cost one line and 0.043 s.
- One helper, `_land_ignored_guard`, with one purpose: print the offending paths and return non-zero. It is tested through `wrap land` with the existing gh stub.

## Picture

```
 wrap land <wt>
   │
   ├─ dirty check (st0, `!!` lines filtered)                existing
   ├─ fetch origin/<def>, ahead > 0                         existing
   ├─ open-PR lookup, already-landed path ─────► tidy, return   existing
   │
   ├─ _land_ignored_guard <wt> <base> <branch>              NEW
   │     │
   │     ├─ base empty? ───────────────────────────────► REFUSED, exit 1
   │     ├─ git diff --name-only -z --no-renames <base> HEAD
   │     │     rc != 0 ────────────────────────────────► REFUSED, exit 1
   │     │     each path ──► a scope:
   │     │        depth 0  (README.md)        root, direct children only
   │     │        depth 1  (_meta/LOG.md)     _meta, direct children only
   │     │        depth 2+ (tools/x/t/a.py)   tools/x, whole subtree
   │     ├─ git status --porcelain -z --ignored=matching
   │     │      --untracked-files=normal -- <scope pathspecs>
   │     │     rc != 0 ────────────────────────────────► REFUSED, exit 1
   │     ├─ keep `!!` entries inside a scope (literal prefix compare)
   │     ├─ drop entries the allowlist matches
   │     │     built-in list ∪ kit_config_get_root wrap.land_ignored_allow
   │     └─ any left? ──► "LAND REFUSED", name each path, exit 1
   │
   ├─ PR template check                                      existing
   └─ push, PR, merge, tidy                                  existing
```

## Design

### Approaches considered + chosen

See `## Solution`. Chosen: a pre-push guard inside `cmd_land`.

### Diagram

See `## Picture`.

### Decisions in order of cost to change

1. **The knob's trust model.** `[wrap] land_ignored_allow` loosens the guard. It is read with `kit_config_get_root`: the operator `kit.toml`, else the kit-root `kit.toml`. A project `.kit.toml` is never read, neither the branch's copy nor the default branch's. This is the registry fence: a key that loosens what a write accepts never reads a project file, because a project file rides inside a PR. The key joins the "Root-only keys" table. The built-in list always applies in code; the knob adds to it. The operator value replaces the kit-root value (that is how `kit_config_get_root` resolves), and the kit root ships an empty value.
2. **The scope rule.** Each path the diff touches (added, modified, deleted, both sides of a rename through `--no-renames`) gives one scope:
   - depth 0, a root file: the root, direct children only;
   - depth 1 (`_meta/LAB_LOG.md`, `.claude/x`): that directory, direct children only;
   - depth 2 or more (`tools/x/tests/t.py`): the first two components (`tools/x`), the whole subtree.
   A direct child is an entry whose path, relative to the scope directory, holds no `/` except an optional trailing one. Every ops-toolkit land touches `_meta/`, so a depth-1 touch must not put a whole top-level directory in scope. The subtree rule at depth 2 catches a fixture in a sibling directory (`tools/x/fixtures/` beside `tools/x/tests/`).
3. **The compare is literal.** Scope membership is a string prefix compare on `<scope>/`, never a glob or regex. The status call passes `:(literal)<dir>` pathspecs as a narrowing step: one per depth-1 and depth-2 scope, and none at all when a root scope exists, because the root's direct children cannot be named by a pathspec (a `:(glob)*` pathspec also returned deeper entries, see Grounding). The prefix filter is the authority either way.
4. **The allowlist match.** The trailing `/` of a directory entry is stripped first. There are three entry forms:
   - no `/`: a glob matched against the entry's last component only (a collapsed directory's name, or a file's basename), never an ancestor component. `dist` allows `tools/x/dist/` but never `tools/x/dist/fixtures/a.raw.json`;
   - ending in `/` (`.pytest_cache/`): the whole subtree under any directory of that name, at any depth. This is an explicit opt-in for caches that write their own `*` ignore rule, which makes git list their children one by one (Grounding);
   - any other entry with a `/` (`tools/circle/data`, `.claude/session-state`): a glob matched against the whole repo-relative path or a leading run of its components.
   The value is split on spaces under `set -f`, so an entry such as `*.json` never expands against the cwd.
5. **The built-in list.** `node_modules`, `.wrangler`, `dist`, `*.tsbuildinfo` (the brief's build output), `__pycache__`, `.venv`, `target`, `.pytest_cache/` (Python and Rust build output and caches), `.env`, `.env.*`, `.envrc`, `.dev.vars` (local config that must never be committed), `.DS_Store`, and `.claude/session-state` (written by the kit's own `hooks/session-state-save.sh`). Live samples show `__pycache__/`, `.pytest_cache/` children, `node_modules/`, and `.claude/session-state/` in real post-test worktrees (Grounding).
6. **The refusal text.** It prints one line per path. A path whose basename looks like a secret gets the marker `looks like a secret: never commit; move or delete it, or allow it`, and the commit hint never appears beside it. Secret-shaped means a case-insensitive basename match on `.env*`, `*.pem`, `*.key`, `*secret*`, `*credential*`, or `*token*`. When at least one path has no marker, a closing line asks a human to choose: commit, delete, or allow. Control bytes in a path print as `?`.
7. **The exit and the loop rule.** The guard returns 1, the code `cmd_land` uses for the other local-state refusals (dirty tree, detached HEAD). Nothing is pushed, and no PR is opened, edited, readied, or merged. An unattended loop (a wrap step 10 worker, a `/goal` loop, a mega-goal wave) must stop on this refusal and report it to a human. It must never retry, commit the file, delete it, or add an allow entry by itself. The `commands/wrap.md` land paragraph says so.
8. **Fail closed on every read.** A failed `git diff`, a failed `git status`, or an empty merge base refuses with exit 1 and a line naming the failed read. An unreadable tree is never treated as clean. The status call passes `--untracked-files=normal` explicitly, because `status.showUntrackedFiles=no` makes `--ignored=matching` fatal (rc 128).

### ADR link(s)

None. The guard is reversible and adds one refusal to an existing verb.

### Boundaries & failure modes

See `## Failure modes`. Out of bounds: the push paths outside `wrap land`, the ship-gate hook, and `wrap merge`.

## Technical Design

### Interfaces (I/O contract)

- Inputs: the worktree path, the merge base `cmd_land` already computes (`proof_base`), and the branch name. The guard reads `git diff --name-only -z --no-renames <base> HEAD`, `git status --porcelain -z --ignored=matching --untracked-files=normal -- <pathspecs>`, and `kit_config_get_root wrap.land_ignored_allow ""`. Every git call runs inside the worktree (`git -C <wt>`).
- Output on refusal (stderr), for example:
  ```
       LAND REFUSED: 3 ignored paths under what feat/x touches; a clean checkout will not have them
         tools/x/fixtures/a.raw.json
         tools/x/data/
         tools/x/api.key  (looks like a secret: never commit; move or delete it, or allow it)
       a human decides for each unmarked path: commit it (git add -f), delete it, or allow it in [wrap] land_ignored_allow in the operator kit.toml
  ```
  At most 20 paths print, then `and <N> more`. A directory entry keeps its trailing `/`. Paths come from `-z`, never git's C-quoted form.
- Output on a failed read: `     LAND REFUSED: the ignored-file check could not read <git status|git diff|the merge base>; nothing pushed`.
- Exit: 0 when nothing in scope survives the allowlist; 1 on any refusal.
- Invariants: the guard writes nothing. It runs after the already-landed path and before the PR-template check and the push.

### Data model changes

A new kit-root `kit.toml` line, `land_ignored_allow = ""`, under `[wrap]`. It holds a space-separated list of entries, the same shape as `wrap.roots`. A value cannot contain `#` (the resolver's line rule).

### API changes

`wrap land` gains one refusal. There is no new flag: the knob is the only way past, and it lives in a file the operator owns.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-1: the knob. Add the `land_ignored_allow = ""` line under `[wrap]` in the kit-root `kit.toml`, a `wrap.land_ignored_allow` row in `lib/config/module-registry.md`, and a row in its "Root-only keys" table. AC: `awk '/^\[wrap\]/{s=1;next} /^\[/{s=0} s && /^land_ignored_allow[[:space:]]*=/' kit.toml` prints exactly one line; `bash tests/test-config-registry.sh` exits 0.

### Phase 2: Core
- [ ] TASK-2 (depends on TASK-1): `_land_ignored_guard` in `lib/wrap/wrap-land.sh`, and its call in `cmd_land` after the already-landed block and before the PR-template check. It covers the scope rule, the literal compare, the three allow forms, the built-in list, the refusal text, and fail-closed reads. AC: Test plan rows 1 to 22 pass; each negative control goes red under its mutation.
- [ ] TASK-3: a `sec_ignored_guard` section in `tests/test-wrap-land.sh`, one case per Test plan row. It pins `GIT_CONFIG_GLOBAL` and `XDG_CONFIG_HOME` to fixture paths and runs `wrap land` from inside the worktree. The land-merge sections that plant `ignored.bin` run with an operator `kit.toml` that allows `ignored.bin` (see Acceptance Criteria). AC: `LAND_ONLY=ignored bash tests/test-wrap-land.sh` exits 0, and so does the full `bash tests/test-wrap-land.sh`.

### Phase 3: Polish
- [ ] TASK-4: docs. Add one sentence on the refusal, the knob, and the loop rule to the `wrap land` paragraph in `commands/wrap.md`, and the same to `MANUAL.md` where it lists land's refusals. AC: `bash tests/run-all.sh --changed --time` shows no red suite.

## After state

- [ ] `wrap land` on a branch whose touched unit holds an ignored `*.raw.json` exits 1, prints `LAND REFUSED` and the path, and pushes nothing. (Today: it pushes and merges.)
- [ ] The same land, with the fixture committed through `git add -f`, exits 0.
- [ ] An ignored `node_modules/`, `dist/`, `__pycache__/`, `.pytest_cache/` child, `.env`, or `.claude/session-state/` under a touched scope does not refuse.
- [ ] A failed `git status`, a failed `git diff`, or an empty merge base refuses with exit 1 and pushes nothing.
- [ ] `kit.toml` carries `land_ignored_allow = ""` under `[wrap]`, and the key sits in the registry's "Root-only keys" table.
- [ ] `LAND_ONLY=ignored bash tests/test-wrap-land.sh` exits 0.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Tests cover the happy path and every Edge Case below, except the adopt refusal (Edge 15), which is covered by construction plus a regression run.
- [ ] No regression: `bash tests/run-all.sh --changed --time` shows no red suite, and `bash tests/test-wrap-adopt.sh` exits 0.
- [ ] The existing land fixtures stay green. Four land-merge sections plant an ignored root `ignored.bin` (`utref` line 889, `ignx` line 1490, `ignr` line 1516, `igno` line 1542). By trace, two of them also touch a root file (`utref` and `ignr` edit `base.txt`), so the root scope reaches `ignored.bin`. The lead's count was three; the fix does not depend on the count. Fix: all four sections run with an operator `kit.toml` (`KIT_CONFIG_OPERATOR`) whose `[wrap] land_ignored_allow = "ignored.bin"`. That is an allow entry, not a moved file, because those tests prove that an operator-private ignored root file survives the merge cycle. Moving it would change what they prove.

## Test plan

Every row runs `wrap land` from inside the worktree with `GIT_CONFIG_GLOBAL` and `XDG_CONFIG_HOME` pinned to fixture paths. "No push" means the bare origin has no `feat/land` ref and the stub calls hold no `pr create`, `pr edit`, `pr ready`, or `pr merge`.

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Ignored `tools/x/fixtures/a.raw.json`; branch touches `tools/x/test_x.sh` | happy refusal | After state 1 | exit 1; `LAND REFUSED` and the path; the closing human-decides line; no push |
| 2 | Same fixture committed through `git add -f` | happy pass | After state 2 | exit 0, a `merged #` line |
| 3 | Ignored `other/far.raw.json`; branch touches only `tools/x/` | edge | Edge 1 | exit 0 |
| 4 | Under `tools/x/`: an ignored `node_modules/` with many files, `dist/`, `a.tsbuildinfo`, `.wrangler/`, `__pycache__/`, `.venv/`, `.pytest_cache/` with its own `*` rule, `.env`, `.env.local`, `.envrc`, `.dev.vars`, `.DS_Store` | edge: built-in list | Edge 2, After state 3 | exit 0 |
| 5 | Nested `tools/x/.gitignore` ignores `notes.txt`; the file exists | edge | Edge 3 | exit 1, names `tools/x/notes.txt` |
| 6 | Ignored `tools/x/dist/fixtures/a.raw.json` (dist not wholly ignored: the pattern matched the file) | negative: no ancestor match | Edge 9 | exit 1, names the path |
| 7 | Operator `kit.toml` allows `tools/x/fixtures` | knob, path form | Decision 4 | exit 0 |
| 8 | Operator `kit.toml` allows `*.json` while the cwd holds `a.json` | edge: no glob expansion | Edge 10 | exit 0 for `tools/x/fixtures/x.raw.json` |
| 9 | Kit-root `kit.toml` (`KIT_CONFIG_ROOT`) allows `*.raw.json`, no operator file | knob, root layer | Decision 1 | exit 0 |
| 10 | A project `.kit.toml`, committed on both the branch and origin's default branch, allows `*.raw.json` | negative: project layer never read | Decision 1 | exit 1 |
| 11 | Tracked-and-ignored file in a touched scope | edge | Edge 4 | exit 0 |
| 12 | No `.gitignore`; `.git/info/exclude` lists `fixture.bin`; `tools/x/fixture.bin` exists | edge | Edge 5 | exit 1, names it |
| 13 | Branch touches root `README.md`; ignored root `notes.raw.json` and ignored `deep/x.raw.json` | edge: root scope | Edge 6 | exit 1, names `notes.raw.json` only |
| 14 | Branch touches `_meta/LAB_LOG.md`; ignored `_meta/cache.raw.json` and `_meta/sub/y.raw.json` | edge: depth-1 scope | Edge 7 | exit 1, names `_meta/cache.raw.json` only |
| 15 | Ignored `tools/x/fixtures/with space.raw.json` and one with a tab in its name | edge: quoting, control bytes | Edge 8 | the space path prints raw and unquoted; the tab prints as `?` |
| 16 | Ignored `tools/x/api.key` and `tools/x/.env.prod.bak`, nothing else | secret hint | Decision 6 | both lines carry `looks like a secret: never commit`; the output has no `git add -f` |
| 17 | A `git` shim fails `status` | fail closed | Edge 11 | exit 1, names `git status`, no push |
| 18 | A `git` shim fails `diff --name-only` | fail closed | Edge 11 | exit 1, names `git diff`, no push |
| 19 | A `git` shim fails `merge-base`, so the base is empty | fail closed | Edge 12 | exit 1, names the merge base, no push |
| 20 | `status.showUntrackedFiles=no` in the repo config, ignored fixture present | edge | Decision 8 | exit 1, names the fixture (not a read failure) |
| 21 | An open PR already exists for the branch (adopted path), ignored fixture present | edge | Edge 13 | exit 1, no push, no `pr ready`/`pr edit`/`pr merge` |
| 22 | Ignored `tools/x/data/` (a collapsed directory) with no allow entry, then with an operator entry `tools/x/data` | edge | Edge 14 | first exit 1 naming `tools/x/data/`; then exit 0 |
| 23 | Branch already landed (a squash on origin), ignored fixture present | edge: order | Edge 16 | the `already landed` path runs, with no refusal |

## Verification

```bash
LAND_ONLY=ignored bash tests/test-wrap-land.sh
bash tests/test-wrap-land.sh
bash tests/test-config-registry.sh
bash tests/test-wrap-adopt.sh
bash tests/run-all.sh --changed --time
```

## Edge Cases

1. An ignored file outside every scope passes. The guard judges what the branch could depend on, not the whole tree.
2. A huge `node_modules/` shows as one `!!` entry, its last component matches, and it passes. Git does not descend into it, so the cost stays flat.
3. A nested `.gitignore` is applied by git, and the entry shows its full path. The same rule as any other entry.
4. A file both tracked and matching an ignore pattern is listed by git as tracked, never as `!!`. It is committed, so it passes.
5. A repo with no `.gitignore`: `.git/info/exclude` and the operator's global excludes still produce `!!` lines, and they count the same, because the file is still absent from a clean checkout.
6. A root file touched: only the root's direct children are in scope.
7. A depth-1 file touched (`_meta/LAB_LOG.md`): only that directory's direct children are in scope.
8. Spaces and quotes in a path: read with `-z`, printed raw. Control bytes print as `?`.
9. A slash-free allow entry never matches an ancestor: `tools/x/dist/fixtures/a.raw.json` refuses even though `dist` is built in.
10. An allow entry such as `*.json` is split under `set -f`, so a file in the cwd never rewrites it.
11. A failed `git status` or `git diff` refuses with exit 1. It is never read as "no ignored files".
12. An empty merge base refuses with exit 1. GitHub also refuses a PR with no common history.
13. An adopted PR (one already open for the branch): the guard runs before the re-push, so it refuses before the merge.
14. A collapsed ignored directory (`tools/x/data/`) is named with its trailing `/`. An allow entry `data` or `tools/x/data` covers it.
15. `wrap adopt` reaches the guard through `cmd_land`. No test plants a file in adopt's worktree, because the verb creates that worktree itself and offers no seam between start and land. Coverage is by construction, plus the `test-wrap-adopt.sh` regression run.
16. A branch already on the default branch takes the already-landed path, which tidies; the guard never runs.
17. A tracked file inside an ignored directory makes git list the untracked siblings one level down (`node_modules/big/`). Their last component is not `node_modules`, so the guard refuses. This is a known false positive, and a path-form entry (`tools/x/node_modules`) covers it.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| False positive: legitimate local state (a tool's `data/`, an experiment's `out`) in a scope | `LAND REFUSED` naming that path | a human chooses; for a standing case, an operator `kit.toml` entry |
| False negative: the fixture sits outside every scope (a root-level test reading `testdata/x`, or a depth-1 test reading a grandchild) | the clean-checkout failure the guard exists to stop | a known ceiling of the scope rule, written as a `ponytail:` comment at the scope code |
| A git read fails | non-zero exit from the read | refuse with exit 1 and name the read |
| A loop retries or self-allows | a second land attempt, or a knob edit by an agent | the loop rule in `commands/wrap.md`; the knob lives only in operator-owned files |
| A wrong allow entry hides a real fixture | none at land time | entries live in the operator's own file, reviewed where they are written |

## Out of Scope

- A ship-gate hook form of the guard for every push. Hooks may not read `kit.toml`, and the blast radius would be every adopted repo. Wrap step 10's in-worktree `git push` stays unguarded.
- `wrap merge` (see "Which verbs get the guard").
- A project-level knob. v1 reads only the operator and kit-root layers.
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
- kit.toml
- MANUAL.md

## Decision Log

- DEC-1: the guard lives in `cmd_land` only. `wrap adopt` inherits it; `wrap merge` has no local tree to judge. Rejected: a ship-gate hook (no knob in hooks, estate-wide blast radius).
- DEC-2 (lead ruling a, revision 1): v1 reads the knob with `kit_config_get_root` (operator, else kit root) and joins the "Root-only keys" table. The project layer is dropped, the `origin/<def>:.kit.toml` read included. Reason: the registry fence says a write-loosening knob never reads a project file, and the round-1 self-widening test could not fail against the at-base read. Replaced: revision 0's union with the project file at `origin/<def>`.
- DEC-3 (lead ruling b, revision 1): the scope is depth-aware. A root or depth-1 touch scopes direct children only; a depth-2-or-deeper touch scopes the first two components' subtree. Reason: every ops-toolkit land touches `_meta/`. Rejected: the parent directory alone (misses sibling `fixtures/`), and every ancestor (collapses to the whole repo).
- DEC-4 (lead rulings c and d, revision 1): a slash-free allow entry matches the last component only. Scope is a literal prefix compare, and entries split under `set -f`. A trailing-`/` entry is the one explicit subtree form, needed because `.pytest_cache/` writes its own `*` rule and git lists its children one by one.
- DEC-5 (critical 1, revision 1): the built-in list adds local config (`.env`, `.env.*`, `.envrc`, `.dev.vars`), `.DS_Store`, and the kit's own `.claude/session-state` to build output and caches. Secret-shaped names never get a commit hint.
- DEC-6: no bypass flag. The knob is the only way past, and it leaves a trace in an operator-owned file.
- DEC-7 (critical 2, revision 1): every read fails closed. `--untracked-files=normal` is passed explicitly.
- DEC-8 (lead ruling g, revision 1): the existing `ignored.bin` fixtures get an operator allow entry and are not moved.

## Grounding

All samples are read-only. Scratch repos lived under the session scratchpad; the real repos were read with `git status` only. Git 2.55.0.

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

The traditional mode collapses a directory whose contents are all ignored (`web/`), which hides which pattern matched. `matching` keeps the matched entry, so it is the mode the guard reads, as `cmd_land`'s `st0` already does. A nested `.gitignore` match shows its full path. `-uall` gave the same list as the default.

**`status.showUntrackedFiles=no` is fatal with `--ignored=matching`:**

```
$ git -c status.showUntrackedFiles=no status --porcelain --ignored=matching
fatal: Unsupported combination of ignored and untracked-files arguments
rc=128
$ git -c status.showUntrackedFiles=no status --porcelain --ignored=matching --untracked-files=normal
!! other/far.raw.json
!! tools/x/.DS_Store
rc=0
```

**Pathspecs:** `-- ':(literal)tools/x' ':(literal)web'` returned only entries under those two directories. `-- ':(glob)*'` returned `root.raw.json` but also `tools/x/node_modules/big/`, `web/.wrangler/` and `web/dist/`, so a glob pathspec cannot express "root direct children". The literal prefix filter is the authority.

**A failed merge base:** `git merge-base HEAD 0000…0000` printed `fatal: Not a valid commit name` with rc 128 and nothing on stdout. `cmd_land` reads it with `2>/dev/null`, so the guard sees an empty base.

**Tracked and ignored:** `tools/x/fixtures/keep.raw.json` was force-added. It never appears as `!!`. `git check-ignore` exits 1 for it (tracked), and `git check-ignore --no-index` names `.gitignore:1:*.raw.json`.

**A tracked file inside an ignored directory:** after `git add -f tools/x/node_modules/pkg/lib/m.js`, status lists the untracked siblings one level down (`!! tools/x/node_modules/big/`), never the tracked file. This is Edge 17's false positive.

**Huge `node_modules/`:** 50,001 files under `tools/x/node_modules/big/`. `git status --porcelain --ignored=matching` took 0.043 s total and printed one entry for it.

**No `.gitignore`, and the global excludes fallback** (scratch repo `r2`: one tracked `a.txt`, a root `.env`, a `.kit/proof-assets/` cache with its self-written `*` rule):

```
$ git status --porcelain --ignored=matching
!! .env
!! .kit/proof-assets/.gitignore
!! .kit/proof-assets/s1/
$ git -c core.excludesFile=/dev/null status --porcelain --ignored=matching
?? .env
!! .kit/proof-assets/.gitignore
!! .kit/proof-assets/s1/
$ GIT_CONFIG_GLOBAL=/dev/null XDG_CONFIG_HOME=<dir with git/ignore = .env> git status ...
!! .env
$ GIT_CONFIG_GLOBAL=/dev/null XDG_CONFIG_HOME=<empty dir> git status ...
?? .env
```

The operator's global excludes file (`~/.gitignore`, 14 patterns, among them `.DS_Store`, `.env`, `.env.*`, `.claude/worktrees/`) makes `.env` ignored with no repo `.gitignore`. Pinning `GIT_CONFIG_GLOBAL` alone does not stop git's `$XDG_CONFIG_HOME/git/ignore` fallback, so the tests pin both. The proof-asset manifest is committed at `docs/verification/<slug>/assets.json` (`lib/proof/asset.sh:9`), so a visual-proof diff scopes `docs/verification`, never `.kit/`.

**Quoting and control bytes:** the non-`-z` form C-quotes a path with a space; `-z` does not. A tab in a file name comes through `-z` as a raw `\t` byte (seen with `od -c`), which is why the printer maps control bytes to `?`.

```
$ git status --porcelain --ignored=matching -- tools/x/fixtures
!! tools/x/fixtures/a.raw.json
!! "tools/x/fixtures/with space.raw.json"
$ git status --porcelain -z --ignored=matching -- tools/x/fixtures | tr '\0' '\n'
!! tools/x/fixtures/a.raw.json
!! tools/x/fixtures/with space.raw.json
```

**Real post-test worktrees (ruling k)**, ops-toolkit `.claude/worktrees/*`, `git status --porcelain --ignored=matching`, hex ids masked:

```
== fix+alert-noise-oct4   (ran pytest and the worker's node tests)
!! .claude/session-state/
!! tools/vps-mon/hermes-errlog-shipper/.pytest_cache/.gitignore
!! tools/vps-mon/hermes-errlog-shipper/.pytest_cache/CACHEDIR.TAG
!! tools/vps-mon/hermes-errlog-shipper/.pytest_cache/README.md
!! tools/vps-mon/hermes-errlog-shipper/.pytest_cache/v/
!! tools/vps-mon/hermes-errlog-shipper/__pycache__/
!! tools/vps-mon/hermes-errlog-shipper/test/__pycache__/
!! tools/vps-mon/worker/node_modules/
== kunio-fuzz-s1027
!! experiments/kunio-web-port/node_modules
!! experiments/kunio-web-port/out
!! experiments/kunio-web-port/tools/__pycache__/
!! "experiments/nes-rom-anatomy/Nekketsu Kakutou Densetsu (Riki Kunio) (J) [T-Eng0.95].nes"
!! experiments/nes-rom-anatomy/code/__pycache__/
!! experiments/nes-rom-anatomy/out
== agent-<hex>            (watch-hub worker)
!! .claude/session-state/
!! tools/watch-hub/worker/node_modules/
== probe-oauth-primaries, neko-ip-kernel-v0
!! .claude/session-state/
```

What the sample settles:
- `.pytest_cache/` children come one by one, because pytest writes its own `*` rule. A last-component match on `.pytest_cache` would miss `README.md` and `v/`, which is why the subtree form `.pytest_cache/` exists (Decision 4).
- `node_modules` can show without a trailing slash (a symlink); the last-component match still allows it.
- `.claude/session-state/` sits in every sampled worktree. The kit's own `hooks/session-state-save.sh` writes it, so it is built in.
- What still refuses in this sample is `experiments/kunio-web-port/out` and the `.nes` ROM in `experiments/nes-rom-anatomy/`, when a branch touches those experiments. Both are genuine "a clean checkout lacks this" cases, and a human should decide on them.

**Real estates, counted by basename** (main checkouts):
- ops-toolkit, 170 entries: `__pycache__/` 45, `session-state/` 23, `.venv/` 11, `data/` 10, `node_modules/` 8, `.DS_Store` 5, `.wrangler/` 4, `.pytest_cache/` 2, `out/` 2, plus one-off state files (`*.sqlite`, `*.jsonl`, `*.bak`).
- dwarves-kit main checkout: `.claude/goals/`, `.claude/handoffs/`, `.claude/rules/`, `.claude/worktrees/`, `__pycache__/` in 10 places, `lib/stats/.venv/`, `lib/prose-rag/rust/target/`, and a built binary `lib/prose-rag/bin/prose-rag-rs`.
- This worktree, fresh from `wrap start`, had no `!!` entry before any test ran.

**Negative controls, dry traced:**

1. Mutation: delete the `_land_ignored_guard` call in `cmd_land`. Fixture: row 1 (`LBRANCH` writes `tools/x/test_x.sh`; an ignored `tools/x/fixtures/a.raw.json` sits in the worktree). Path: the dirty check passes (only `!!` lines), the already-landed proof is empty, the template check passes, and `git push` runs. Red: row 1's "exit 1" and "no push" asserts.
2. Mutation: drop `node_modules` from the built-in list. Fixture: row 4. Path: `tools/x/node_modules/` is in the `tools/x` scope and no longer allowed. Red: row 4's "exit 0".
3. Mutation: swallow the status read's rc (`st="$(git ... status ...)" || true`). Fixture: row 17 (the shim exits 128 on `status`). Path: `st` is empty, so no entry is in scope, the guard returns 0, and the land pushes. Red: row 17's "exit 1" and "no push".
4. Mutation: scope every ignored entry (skip the scope filter). Fixture: row 3 (`other/far.raw.json`, branch touches `tools/x/`). Path: the out-of-scope entry survives and refuses. Red: row 3's "exit 0". Rows 13 and 14 also go red (they would name `deep/x.raw.json` and `_meta/sub/y.raw.json`).
5. Mutation: match slash-free entries against every component. Fixture: row 6. Path: the `dist` component allows `tools/x/dist/fixtures/a.raw.json`, and the land pushes. Red: row 6's "exit 1".

## Open questions

(none)
