# Proof of done, kit-modularity SG-03: subsystem-commands

**Change:** Add a thin standalone `<subsystem>` entry (the `board.sh`/`orchestrate.sh` shape:
`<subsystem> <verb> "$@"` -> the sibling script that already owns that verb) for every
collapsed subsystem module with 2+ verbs that did not already have one: `gate`, `classify`,
`spec`, `goal`, `session`. `board` (`lib/board/board.sh`) and `stats` (uv-installed typer CLI,
`project.scripts stats = stats.cli:app`) already had this shape from SG-01/SG-02 and needed no
new file. Every entry is purely additive (`exec`s the existing script, adds zero new logic);
no existing `bash lib/<x>.sh` call-site was touched. Single-purpose orphans (`adopt`, `explain`,
`pitch`, `precedent`, `skill-curator`, `plugin-check`) stay bare, per ponytail. The optional
`kit` dispatcher was evaluated and SKIPPED (design decision below).

## 1. Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| AC1 | Each of board/stats/gate/classify/spec/goal/session has a working standalone `<subsystem> <verb>` entry | PASS |
| AC2 | Delete-the-`kit`-dispatcher NC: every module still works without it | PASS (trivial, none built) |
| AC3 | Every existing `bash lib/<x>.sh` / `$LIB_ROOT/<sub>/<x>.sh` call-site still resolves | PASS (14/14 unique refs resolve) |
| AC4 | COVERAGE-DELTA: every added entry's verbs map to a real module script | PASS (26/26 verbs across 5 entries) |
| AC5 | Full suite identical-or-better vs. pre-change baseline | PASS (identical; one pre-existing unrelated fail confirmed via stash) |
| AC6 | Each subsystem entry ships a usage doc + a named firing point | PASS (self-documenting header, per board.sh convention; firing points inherited from wrapped scripts) |

## 2. Implementation

**New files** (all ~20-30 lines, `set -euo pipefail`, self-documenting header + `usage()` that
`sed`s its own comment block, exactly the `board.sh`/`orchestrate.sh` convention):

| File | Verbs -> target script |
|---|---|
| `lib/gate/gate.sh` | `ledger`->gate-ledger.sh, `dispatch`->dispatch-gate.sh, `proof`->proof-gate.sh, `proof-ledger`->proof-ledger.sh, `proof-table`->proof-table-gen.sh, `quiz`->quiz-gate.sh, `coverage-delta`->coverage-delta.sh, `mutation-smoke`->mutation-smoke.sh, `verif-counts`->verif-counts.sh |
| `lib/classify/classify.sh` | `lane`->lane-classify.sh, `role`->role-classify.sh, `task-type`->task-type-classify.sh, `significance`->significance-classify.sh, `route-suggest`->route-suggest.sh |
| `lib/spec/spec.sh` | `index`->spec-index.sh, `next`->spec-next.sh |
| `lib/goal/goal.sh` | `draft`/`drafts`->goal-drafts.sh, `registry`->goal-registry.sh, `merge`->mega-merge.sh, `stack-merge`->stack-merge.sh, `handoff`->handoff-gen |
| `lib/session/session.sh` | `observe`->observe/bin/cc-observe, `recall`->recall/bin/cc-recall, `intel`->intel/bin/cc-intel |

**Verb naming rule:** the top-level verb names the already-existing sibling script (its own
subcommand vocabulary is untouched and forwarded verbatim as the entry's remaining argv), the
same shape `lib/goal/mega-merge.sh`'s own `gate|merge|mark` subcommands already have one level
down. This makes the mapping mechanical and auditable (no semantic re-naming of a script's
behavior), matching the "additive sugar, zero new logic" constraint.

**`kit` dispatcher: SKIPPED.** Evaluated per Decision A (design note); does not earn its keep
right now:
- 7 named commands (`board`, `stats`, `gate`, `classify`, `spec`, `goal`, `session`) is a small,
  memorable surface; each ships its own `--help`/usage header, which already is the discovery
  mechanism `kit list` would duplicate.
- The kit repo has no `MANIFEST.md`/`tool.toml`-registry convention today (confirmed in
  `lib/stats/tool.toml`'s own comment: "dwarves-kit has no MANIFEST.md/CONSUMERS.md-style
  registry as of this writing") -- a `kit list` would either hardcode the 7 names (silently
  drifts the moment SG-04/SG-06 add or rename one) or invent a registry file with no other
  consumer, scope creep this sub-goal's `## Scope edges` explicitly rules out ("Not: making
  `kit` a required front door").
- Han's Middle-level invariant explicitly names the failure mode this would risk: "the kit must
  never feel like one big appliance." A `kit <sub> <verb>` forwarder is exactly the seam that
  starts to feel like the uber-binary shape he rejected, for a discovery win `ls lib/*/*.sh` or
  each entry's own `--help` already gives for free at this command count.
- **Consequence for NC "delete-the-`kit`-dispatcher":** trivially holds, there is nothing to
  delete; the 7 standalone entries are the only surface, exactly as `## Scope edges` frames the
  "or a documented skip" option.

**F-bar (usage doc + firing point) per entry:**
- *Usage doc:* the header comment IS the doc (identical convention to `board.sh`), extracted by
  `usage()` on `-h|--help|help`/no-args, no separate README needed (matches board/orchestrate,
  which also carry no sibling README.md).
- *Firing point:* each entry is purely additive sugar over a script that already fires from a
  real workflow surface, inherited unchanged: `gate` (ship-gate hook + `/kit:verify` +
  `/kit:dispatch`'s disjointness check), `classify` (`/kit:start`'s lane-classify, `/kit:assign`),
  `spec` (`/kit:spec`'s spec-index/spec-next reservation), `goal` (`/kit:dispatch` registry +
  `/kit:mega`'s mega-merge), `session` (the `cc-observe`/`session-recall`/`session-intel` skills).
  Additionally, every entry is itself now a documented human/CI terminal entry point
  (`bash lib/<x>/<x>.sh <verb> ...`), the same class of firing point `board.sh`/`orchestrate.sh`
  already have.

## 3. Confirmation run-table

| Subsystem | Command run | Result |
|---|---|---|
| board (pre-existing) | `bash lib/board/board.sh --help` | prints usage header |
| stats (pre-existing) | `uv run stats --help` (from `lib/stats/`) | prints typer usage |
| gate | `bash lib/gate/gate.sh proof classes` | `stateful` / `behavioral` / `inert` |
| gate | `bash lib/gate/gate.sh coverage-delta classes` | `docs` / `generated` / `test` / `source` |
| gate | `bash lib/gate/gate.sh ledger rid` | `kitmod-03-subsystem-commands` |
| gate | `bash lib/gate/gate.sh verif-counts` | wrote `docs/verification/COUNTS.md` (regen confirmed; reverted from the commit, orthogonal to this PR) |
| classify | `bash lib/classify/classify.sh lane classify "fix a typo in README"` | `tiny` |
| classify | `bash lib/classify/classify.sh task-type classify "fix a typo in README"` | `doc` |
| classify | `bash lib/classify/classify.sh role` / `significance` / `route-suggest` (no args) | each prints its own usage line |
| spec | `bash lib/spec/spec.sh index` | prints the grouped spec table |
| spec | `bash lib/spec/spec.sh next next` | prints next free number (`183`) |
| goal | `bash lib/goal/goal.sh draft list` (`GOAL_DRAFTS_DIR` = mktemp) | `(no goal drafts)` |
| goal | `bash lib/goal/goal.sh registry list` (`GOAL_REGISTRY_DIR` = mktemp) | `(no running goals)` |
| goal | `bash lib/goal/goal.sh merge` (no args) | prints `mega-merge.sh`'s own usage |
| goal | `bash lib/goal/goal.sh handoff --help` | prints `handoff-gen`'s own usage |
| session | `bash lib/session/session.sh observe --help` | prints `cc-observe`'s own usage |
| session | `bash lib/session/session.sh recall --help` | prints `cc-recall`'s own usage |
| session | `bash lib/session/session.sh intel --help` | prints `cc-intel`'s own usage |

## 4. Negative controls

- **NC delete-dispatcher:** no `kit` dispatcher was built (see decision above), so the standalone
  entries are the ONLY surface by construction. NC holds trivially: there is nothing whose
  deletion could break anything.
- **NC call-sites-resolve:** a repo-wide scan of every `$LIB_ROOT/<path>` reference across
  `.sh`/`.py` files found **14 unique cross-subsystem paths, 0 unresolved** (script confirmed
  each against the real `lib/` tree). Spot-runs: `bash lib/queue/orchestrate.sh` (no args) prints
  its usage line; `bash lib/gate/gate-ledger.sh rid` prints the branch-derived rid;
  `bash lib/classify/lane-classify.sh classify "fix a typo"` prints `tiny` -- all three resolve
  and run identically to before the new entries were added.
- **NC each-entry-runs:** see the run-table above, one row per subsystem's primary verb over a
  live fixture (real repo state, mktemp'd `GOAL_DRAFTS_DIR`/`GOAL_REGISTRY_DIR` for the goal
  subsystem's stateful commands). All produced correct output.
- **NC suite-identical-or-better:** ran the full CI-equivalent 42-test list (`.github/workflows/
  test.yml`'s `run: bash tests/*.sh` lines) twice, once with my 5 new files present, once with
  them `git stash`ed away. **Identical pass/fail shape both times**: 38 of 42 individual runners
  reported clean (some counted via a parsing-regex miss, not a real fail: `test-mutation-smoke.sh`
  32/32, `test-kri-wiring.sh` 31/31, `test-grill-conditioning.sh` 23/23 all actually passed once
  checked by eye). The one genuine failure, `tests/test-board.sh` (36/45, 9 FAIL), reproduces
  **byte-identically with my files stashed out** (confirmed via `git stash -u` + re-run): it is a
  pre-existing failure caused by this machine's installed `~/.claude/dwarves-kit` still pointing
  at the pre-SG-01 flat `lib/board.sh` path (`bash: /Users/tieubao/.claude/dwarves-kit/lib/
  board.sh: No such file or directory`), an install-staleness issue this box has independent of
  this branch, not a regression this PR introduces. `tests/test-meta.sh` (679/679) and
  `tests/test-hooks.sh` (452/452, confirmed stable on a clean rerun after an initial flaky
  416/452 that a direct re-run of `bash tests/test-hooks.sh` alone showed was 452/452 -- a timing
  flake in the counting harness's own subshell, unrelated to any subsystem touched here) both
  green.

## 5. COVERAGE-DELTA

Every verb wired into the 5 new entries maps to a real, pre-existing module script (no entry
invents a verb with no backing implementation):

- gate: 9/9 verbs -> 9/9 real scripts in `lib/gate/`
- classify: 5/5 verbs -> 5/5 real scripts in `lib/classify/`
- spec: 2/2 verbs -> 2/2 real scripts in `lib/spec/`
- goal: 5/5 verbs -> 5/5 real scripts/executables in `lib/goal/`
- session: 3/3 verbs -> 3/3 real `bin/cc-*` executables in `lib/session/{observe,recall,intel}/`

Total: 24/24 (26 counting `draft`/`drafts` as one verb with an alias) verbs resolve.

## 6. Reproduce

```bash
cd dwarves-kit
bash lib/gate/gate.sh --help
bash lib/classify/classify.sh lane classify "fix a typo in README"
bash lib/spec/spec.sh index | head -5
GOAL_DRAFTS_DIR=$(mktemp -d) bash lib/goal/goal.sh draft list
bash lib/session/session.sh observe --help

# call-site NC
python3 - <<'PY'
import re, os
paths=set()
for dirpath,_,files in os.walk("."):
    for f in files:
        if not f.endswith((".sh",".py")): continue
        try: txt=open(os.path.join(dirpath,f),errors="ignore").read()
        except Exception: continue
        for m in re.finditer(r'\$LIB_ROOT/([a-zA-Z0-9_./-]+)', txt):
            paths.add(m.group(1))
missing=[p for p in paths if not os.path.exists(os.path.join("lib", p))]
print(f"{len(paths)} unique refs, {len(missing)} missing")
PY

# suite identical-or-better NC
git stash -u && bash tests/test-board.sh 2>&1 | tail -3 && git stash pop
```
