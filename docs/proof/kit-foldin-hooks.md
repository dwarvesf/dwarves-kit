# Proof of done: kit-foldin sub-goal 02 (hooks-batch)

Ports 4 deterministic `cc-*` guard tools from `ops-toolkit/tools/cc-{backlog,citation-guard,
context-hooks,harvest}/` into `dwarves-kit/hooks/` under function names (per the BINDING
design note `ops-toolkit/research/2026-07-05-cc-elevation-kit-foldin-design.md`), wires
them into both hook manifests, and generalizes `install.sh`'s skill-copy step.

## Acceptance criteria

1. Each of the 4 hooks lives at `hooks/<function-name>.sh` and behaves identically to its
   ops-toolkit source (fail-open/fail-closed posture preserved exactly).
2. Both `settings.json` (the real registration file) and `hooks/hooks.json` (the plugin
   manifest) register all 4 hooks, in parity (`tests/test-meta.sh`'s own parity check).
3. `install.sh`'s skill-copy step generalizes to a glob over `skills/*/SKILL.md`.
4. No hardcoded ops-toolkit path (`workspace/tieubao`) in any new file.
5. Full kit test suite stays green; a fresh-context recheck re-verifies the untrusted-input
   hooks (citation-guard, context-hints, harvest).

## Implementation

| Source (ops-toolkit) | Landed as | Event(s) |
|---|---|---|
| `tools/cc-backlog/bin/cc-backlog` | `hooks/backlog-stage.{sh,py}` | SessionEnd |
| `tools/cc-citation-guard/bin/cc-citation-guard` | `hooks/citation-guard.{sh,py}` | Stop |
| `tools/cc-context-hooks/bin/cc-context` (+ `skills-map.json`) | `hooks/context-hints.{sh,py}` (+ `hooks/context-hints-skills-map.json`, shipped `{}`) | UserPromptSubmit |
| `tools/cc-harvest/bin/cc-harvest` | `hooks/harvest.{sh,py}` | PreCompact, SessionEnd (`--lab-log`) |

Each `.sh` is a thin bash shim (`exec python3 "$HERE/<name>.py"`) since the source tools are
Python (the design-note inventory's "Lang: bash" was a labeling artifact of the flat-script
*shape*, not the interpreter). `install.sh`'s existing `hooks/*.sh` copy loop was extended
with a companion-file loop for `*.py`/`*.json` (excluding `hooks.json`, the plugin manifest),
so the .py logic + the skill-map data file land alongside their `.sh` shim at
`$HOME/.claude/dwarves-kit/hooks/`.

**Consumer seam (no ops-toolkit path).** `backlog-stage.py` and `harvest.py` no longer read
`OPS_TOOLKIT`; both resolve `_repo_root()` = `REPO_ROOT` env, else `git rev-parse
--show-toplevel`, else `$PWD` (mirroring `lib/board.sh`'s own `_default_repo_root`/
`_resolve_repo_root` precedent for the identical `_meta/BACKLOG.md` convention), then default
their ledger/staging/draft paths repo-relative under `_meta/`. `context-hints.py` ships an
**empty** `{}` skill map by default (the source `skills-map.json` was entirely ops-toolkit
personal-skill names; shipping it would be exactly the "no tenant assumption" violation the
design note forbids) , a consumer wires their own via `CONTEXT_HINTS_SKILLMAP`.

**Env var renames** (old cc- name -> new, function-named per Decision 1):

| Old (ops-toolkit) | New (kit) |
|---|---|
| `CC_BACKLOG_*` | `BACKLOG_STAGE_*` |
| `CC_CITATION_*` | `CITATION_GUARD_*` |
| `CC_CONTEXT_*` | `CONTEXT_HINTS_*` |
| `CC_HARVEST_*` | `HARVEST_*` |
| `OPS_TOOLKIT` (backlog-stage, harvest defaults) | removed; replaced by `REPO_ROOT` + repo-relative `_meta/` defaults |

**Registration.** `settings.json`: `backlog-stage.sh` added to a new `SessionEnd` array
(alongside `harvest.sh --lab-log`); `citation-guard.sh` added to the existing `Stop` array;
`context-hints.sh` registered under a new `UserPromptSubmit` array; `harvest.sh` (no args)
added to the existing `PreCompact` array. `hooks/hooks.json` mirrors all 4 with
`${CLAUDE_PLUGIN_ROOT}` paths. `install.sh`'s skill-copy step (install + uninstall) now loops
`skills/*/SKILL.md` instead of a hardcoded `get-api-docs` check.

**Not ported** (scope edges): `add-backlog` (the human-run promote CLI companion to
cc-backlog) is out of scope, this sub-goal ports only the SessionEnd staging hook itself.
`cc-harvest`'s `--stop-trigger`/`--cleanup` modes are kept in the ported file (same file as
the source) but not wired to any new event, matching the source tool's own opt-in posture.

## Confirmation run-table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | backlog-stage fixture (stage + repo-relative default) | `tests/test-kit-foldin-hooks.sh` "backlog-stage.sh" block | PASS |
| 2 | citation-guard fixture (log-only + strict-mode exit 2) | same file, "citation-guard.sh" block | PASS |
| 3 | context-hints fixture (keyword hint fires) | same file, "context-hints.sh" block | PASS |
| 4 | harvest fixture (ledger stage + `--lab-log` draft) | same file, "harvest.sh" block | PASS |
| 5 | NCs: empty stdin, malformed JSON (all 4 hooks) | same file, per-hook "NC:" rows | PASS (8/8) |
| 6 | NC: harvest `--cleanup` on a missing ledger dir | same file, "NC: --cleanup on missing ledger dir" | PASS |
| 7 | Manifest parity: both files name all 4 hooks | same file, "Registration parity" block | PASS (8/8) |
| 8 | Temp-HOME install wires all 4 + companions | same file, "Installer materializes..." block | PASS (17/17) |
| 9 | Skill-copy loop generalization (2nd fabricated skill) | same file, "Skill-copy loop generalization" block | PASS |
| 10 | Done gate: no `workspace/tieubao` in new files | same file, "Done gate" block | PASS |
| 11 | Full kit meta suite unaffected | `tests/test-meta.sh` | PASS 672/672 |
| 12 | Full kit hooks suite unaffected (count pin bumped 17->22) | `tests/test-hooks.sh` | PASS 452/452 |
| 13 | Rung-3 fresh-context recheck (citation-guard/context-hints/harvest) | `kit:recheck-verifier` dispatch, independent re-run + source re-read | see Run detail |

**COVERAGE-DELTA.** New coverage added: `tests/test-kit-foldin-hooks.sh` (49 assertions: 4
per-hook fixture rows, 8 NC rows incl. the harvest `--cleanup` missing-ledger case, 8
manifest-parity rows, 17 temp-HOME install rows, 2 skill-copy-glob rows, 1 grep-clean row).
Existing coverage touched: `tests/test-hooks.sh`'s hardcoded event-hook-count regression pin
(17 -> 22, a legitimate bump since the 4 new hooks add 5 new manifest entries:
backlog-stage, citation-guard, context-hints, harvest x2 for PreCompact+SessionEnd), and the
README.md/`docs/architecture.md` hook-inventory parity checks (both already existing
`test-meta.sh` assertions, now satisfied by the added rows/counts).

## Run detail

```
$ bash tests/test-kit-foldin-hooks.sh
Passed: 49 / 49
All kit-foldin hooks tests passed.

$ bash tests/test-meta.sh
Passed: 672 / 672
All meta tests passed.

$ bash tests/test-hooks.sh
Passed: 452 / 452
All tests passed.
```

Rung-3 fresh-context recheck: dispatched `kit:recheck-verifier` against this worktree
(branch `feat/kit-foldin-02-hooks`, post-commit) to independently re-run the 3 test suites
above AND re-derive from source (not from this doc's claims) that citation-guard.py,
context-hints.py, and harvest.py all fail open on empty/malformed stdin, that
`CITATION_GUARD_STRICT=1` only exits 2 on a genuinely unresolved ref, that harvest's
extractor subprocess call uses `shlex.split` (never `shell=True`), and that none of the 4
hooks' files contain `workspace/tieubao`. Verdict: **PASS** , the verifier reproduced all 3 suites by fresh
re-execution (49/49, 672/672, 452/452) and independently re-derived each safety property by
live-executing each hook with crafted stdin: citation-guard/context-hints/harvest all exit 0
on empty + malformed stdin (context-hints also on a non-dict `[1,2,3]` payload that would
raise on `.get`), `CITATION_GUARD_STRICT=1` exits 2 only on a genuine unresolved ref,
harvest's `run_extractor` uses `subprocess.run(shlex.split(cmd), ...)` with zero `shell=True`
hits (transcript text cannot reach a shell), and `rg` found no `workspace/tieubao` across all
9 files. Verifier note: the Rung-3 edge cases are covered by
`tests/test-kit-foldin-hooks.sh` (which it re-ran) but not by the two pre-existing suites; a
dedicated `test-hooks-security.sh` is a reasonable future hardening, filed as a follow-up
thought, not a blocker for this ship.

## Reproduce

```
cd dwarves-kit   # or the kf-02 worktree
bash tests/test-kit-foldin-hooks.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
```
