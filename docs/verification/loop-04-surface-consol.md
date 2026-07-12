# Proof of done: SPEC-194 surface consolidation (harness-loop SG-04)

Date: 2026-07-12. Branch `feat/loop-04-surface-consol` (stacked on
`docs/loop-01-taxonomy`). Machine: Han's Air, worktree
`.claude/worktrees/agent-a84cc25818204d783`.

Rollback: `git revert` the branch's commits (pure regroup, no state migration; the
`git mv`s revert cleanly). Consumer side: re-run `install.sh --with <modules>` to
regenerate the PATH shims either way. Companion PRs (dotfiles `fix/kit-bin-repoint`,
ops-toolkit `fix/kit-bin-repoint`) revert independently.

## (a) `bin/learn debt` on the SPEC-126 fixture suite

```
Command: bash tests/test-weekend-batch.sh
Exit: 0
Tail:   TOTAL: 45   PASS: 45   FAIL: 0   SKIP: 0
```

Engine relocated `lib/queue/ -> lib/learn/` as a pure `git mv` (0 insertions, 0
deletions). Dispatch chain exercised end to end by the new census test:

```
Command: bash tests/test-bin-forwarders.sh   (learn section)
  ok: learn debt list exits 0 through bin/learn (empty ledger)
  ok: learn debt collect exits 0 through bin/learn
  ok: learn debt collect emits the digest header
  ok: learn debt mark-paid reaches the engine (engine's own no-ledger error, nonzero)
Exit: 0
```

Live read (real ledger, read-only):

```
Command: bin/learn debt collect --all-repos --days 60
Exit: 0
Head: # Weekend batch: debt paydown / Window: since 2026-05-12T21:47:16Z (all repos) / Items: 1 (0 waved, 1 deferred)
```

## (b) `bin/session <verb>` on each tool's existing smoke test

| Verb | Suite (deep behavior) | Result | Dispatcher route (test-bin-forwarders) |
|---|---|---|---|
| observe | `bash lib/session/observe/tests/smoke.sh` | `smoke: all 40 passed`, exit 0 | `ok: session observe reaches its tool` |
| semantic | same suite (SG-04 signals included) | included in the 40 | `ok: session semantic reaches its tool` |
| intel | `bash lib/session/intel/tests/smoke.sh` | `smoke: all 8 passed`, exit 0 | `ok: session intel reaches its tool` |
| report | `bash lib/session/observe/tests/test-vps-report.sh` | `vps-report: all 6 passed`, exit 0 | `ok: session report reaches its tool` |
| recall | `python3 lib/session/recall/tests/test_recall.py` | `Ran 7 tests ... OK`, exit 0 | `ok: session recall reaches its tool` |

## (c) `bin/board promote` on the add-backlog fixture

```
Command: bash tests/test-install-clis.sh
Exit: 0
Tail: test-install-clis: all 20 passed
  incl.: ok: board shim present via board module
         ok: board promote runs (empty repo -> no staged candidates)
```

Direct: `cd $(mktemp -d) && bin/board promote` -> `no staging file (...); nothing
staged.`, exit 0.

## (d) bin/ census, BEFORE -> AFTER

| BEFORE (11 entries, 3 grammars) | AFTER (12 entries, 2 classes) | ADR-0034 target |
|---|---|---|
| `add-backlog` (verb-first orphan) | -- retired -> `board promote` | match |
| `board` | `board` (+ `promote` verb) | match |
| `classify` | `classify` | match |
| `gate` | `gate` | match |
| `session-intel` | -- collapsed | match |
| `session-observe` | -- collapsed | match |
| `session-recall` | -- collapsed | match |
| `session-report` | -- collapsed | match |
| `session-semantic` | -- collapsed | match |
| -- | `session` (5 -> 1) | match |
| -- | `goal` (new) | match |
| -- | `learn` (new) | match |
| -- | `mega` (new) | match |
| -- | `queue` (new) | match |
| -- | `spec` (new) | match |
| -- | `stats` (new) | match |
| `prose-rag` (module CLI) | `prose-rag` | match (two-class rule) |
| `worktree-provision` (module CLI) | `worktree-provision` | match (two-class rule) |

`config` is deliberately absent (lands SG-08 per the ADR census). Enforced as a
standing set-equality check:

```
Command: bash tests/test-bin-forwarders.sh
Exit: 0
Tail: test-bin-forwarders: all 30 passed, 0 skipped
  incl.: ok: bin/ census matches (board classify gate goal learn mega prose-rag queue session spec stats worktree-provision)
```

## (e) three-repo grep-audit (live surfaces)

Audited patterns = the retired surfaces: `lib/queue/weekend-batch`, top-level
`bin/session-*` references, standalone `add-backlog` invocations. Scope = live
surfaces (lib, bin, hooks, commands, skills, tests, install.sh, README, MANUAL,
AGENTS/WORKFLOW, consumer-contract, CI). Dated records (docs/specs, docs/decisions,
docs/research, docs/verification history, `_meta/megagoals`) are archives and keep
their historical text by design; deep tool paths `lib/session/*/bin/session-*` and
the engine file `lib/board/bin/add-backlog` are NOT retired surfaces (ADR: "the bin
entry is a thin router, deep lib paths unchanged").

```
dwarves-kit:
Command: rg -n 'lib/queue/weekend-batch' <live scope>            -> ZERO
Command: rg -n '<top-level bin/session- forms>' <live scope>     -> ZERO (excl. lib/session deep paths)
dotfiles (fix/kit-bin-repoint):
Command: rg -n 'queue/weekend-batch|dwarves-kit/bin/session-|\.local/bin/session-|bin/add-backlog' --hidden -g '!.git'
Output:  CLEAN (zero hits)
ops-toolkit:
_meta/board + _meta/board-all: already exec the stable `bin/board` entrypoint (verified, unedited)
tools/vps-mon/session-intel-bridge/bridge: REAL HIT found (`~/.local/bin/session-report`)
  -> repointed to `~/.local/bin/session report` on branch fix/kit-bin-repoint (ADR-0034
     decision 7 names the vps-mon heartbeat in its consumer-repoint list; the goal file's
     "check only" yielded to the ADR per its own conflict rule)
```

One dormant reference recorded, not repointed: `lib/stats/tests/*` probe
`../cc-backlog/bin/add-backlog` (the long-retired ops-toolkit sibling) and SKIP when
absent; repointing them would change the check's env contract (CC_BACKLOG_* vs
BACKLOG_STAGE_*), a behavior change out of scope (impl-notes entry 14:10).

## NCs: every retired path is provably dead

```
Command: bash lib/queue/weekend-batch.sh list
Output:  bash: lib/queue/weekend-batch.sh: No such file or directory
Exit: 127

Command: ./bin/add-backlog        -> exit=127 (no such file)
Command: ./bin/session-intel      -> exit=127 (no such file)
Command: ./bin/session-observe    -> exit=127 (no such file)
Command: ./bin/session-recall     -> exit=127 (no such file)
Command: ./bin/session-report     -> exit=127 (no such file)
Command: ./bin/session-semantic   -> exit=127 (no such file)

Command: bin/learn propose   -> "learn propose: not yet implemented -- ships in SPEC-195", exit 1
Command: bin/learn drain     -> "learn drain: not yet implemented -- ships in SPEC-196", exit 1
```

Standing enforcement: the `test-bin-forwarders.sh` census NC asserts each retired
entry absent on every CI run. Machine PATH shims (`~/.local/bin/session-*`,
`~/.local/bin/add-backlog`) are install artifacts refreshed by re-running
`install.sh` after merge (deploy step, also re-copies the vps-mon bridge per its
README).

## Full suites

```
Command: bash tests/test-hooks.sh   -> Passed: 453 / 453, exit 0
Command: bash tests/test-meta.sh    -> Passed: 683 / 683, exit 0
Command: all 45 CI-listed tests/test-*.sh run locally -> PASS: 45  FAIL: 0
Command: (cd lib/stats && bash tests/test-docs-wiring.sh)  -> PASS=18 FAIL=0
Command: (cd lib/stats && bash tests/test-render-skill.sh) -> 30 passed, 0 failed
dotfiles: no test suite in that repo (checked: no tests/, no Makefile check target);
  the three skill edits were chezmoi-applied and re-grepped clean (above).
```

## Review

Multi-lens per SPEC-069 (lib/ touched): architecture lens returned zero findings
(10/10); test-coverage lens returned 4 MAJOR + 2 MINOR coverage gaps on the NEW
surfaces, all closed by adding `tests/test-bin-forwarders.sh` (census set-equality,
retired-entry NCs, full dispatch-chain smokes, propose/drain refusal NCs) and wiring
it into CI; its MEDIUM (this proof file missing) is closed by this file.
