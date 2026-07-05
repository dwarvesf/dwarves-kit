# Proof of done: kit-foldin hooks-batch (4 cc-* guards landed as kit hooks)

VERDICT: PASS

Ports 4 deterministic `cc-*` guards from `ops-toolkit/tools/cc-{backlog,citation-guard,
context-hooks,harvest}/` into `dwarves-kit/hooks/` as function-named hooks
(`backlog-stage`, `citation-guard`, `context-hints`, `harvest`), wired into BOTH hook
manifests (`settings.json` = the real registration file; `hooks/hooks.json` = the plugin
manifest) in parity, plus a generalized `install.sh` skill-copy loop. Full design +
per-tool detail: co-located canonical at `docs/proof/kit-foldin-hooks.md`; this file is the
ship-gate run-table + negative control.

## Acceptance criteria

1. Each of the 4 hooks lives at `hooks/<function-name>.sh` and behaves identically to its
   ops-toolkit source (fail-open on empty/malformed stdin preserved; citation-guard strict
   mode still exits 2 only on a genuine unresolved ref).
2. `settings.json` AND `hooks/hooks.json` each register all 4 hooks, in parity.
3. `install.sh` materializes all 4 `.sh` + their `.py`/`.json` companions into a temp HOME,
   and its skill-copy step globs `skills/*/SKILL.md` (not a hardcoded single skill).
4. No `workspace/tieubao` path in any of the 9 new files.
5. The full kit test suite stays green.

## Implementation

`.sh` shims `exec python3` on a co-located `.py` (the source tools are Python). Personal
ops-toolkit paths become an opt-in `REPO_ROOT`/`_repo_root()` seam (mirrors `lib/board/board.sh`);
the context-hints skill map ships empty (`{}`). `install.sh`'s `hooks/*.sh` copy loop
extended to copy `*.py`/`*.json` companions (excluding `hooks.json`), and its skill copy
(install + uninstall) generalized to a `skills/*/SKILL.md` glob. Env vars renamed
`CC_BACKLOG_*`->`BACKLOG_STAGE_*`, `CC_CITATION_*`->`CITATION_GUARD_*`,
`CC_CONTEXT_*`->`CONTEXT_HINTS_*`, `CC_HARVEST_*`->`HARVEST_*`; `OPS_TOOLKIT` removed.

Rollback: pure hook + installer + test + doc change, no state/data migration; rollback is
`git revert` of the two feature commits (no restore procedure needed). [UNAVAILABLE: no
stateful rollback flow , not a deploy/data change.]

## Confirmation run-table (2026-07-05)

| # | Command | Exit | Output |
|---|---------|------|--------|
| 1 | `bash tests/test-kit-foldin-hooks.sh` | 0 | `Passed: 49 / 49` |
| 2 | `bash tests/test-meta.sh` | 0 | `Passed: 672 / 672` (incl. the settings.json<->hooks.json parity check) |
| 3 | `bash tests/test-hooks.sh` | 0 | `Passed: 452 / 452` (event-hook-count pin bumped 17->22) |
| 4 | per-hook fixtures: backlog-stage / citation-guard / context-hints / harvest | 0 | 4 fixture rows PASS (row 1-4 of suite 1) |
| 5 | NCs: empty stdin + malformed JSON (all 4) + harvest `--cleanup` missing ledger | 0 | 9 NC rows PASS, none crash |
| 6 | citation-guard `CITATION_GUARD_STRICT=1` on a genuine unresolved ref | 2 | `citation-guard: unresolved citations: foo.txt:99 (file has 3 lines)` |
| 7 | temp-HOME `install.sh`: 4 `.sh` + `.py` + skill-map wired at `~/.claude/dwarves-kit/hooks/` | 0 | 17 install rows PASS; `jq` confirms all 4 paths in the merged settings.json |
| 8 | skill-copy glob installs a fabricated 2nd skill | 0 | `skill-copy loop installs a SECOND, non-hardcoded skill (glob proof)` PASS |
| 9 | `grep -rn 'workspace/tieubao' hooks/<9 new files>` | 1 | (no match, done gate clean) |
| 10 | `kit:recheck-verifier` fresh-context Rung-3 re-run | 0 | reproduced 49/49 + 672/672 + 452/452; re-derived fail-open + no-shell-injection + grep-clean. VERDICT PASS |

## NEGATIVE CONTROL (revert -> RED -> restore)

The registration is the load-bearing, easy-to-desync part (a hook merely dropped in `hooks/`
is never wired). To prove the suite actually catches a desync:

- **Revert:** removed the `UserPromptSubmit` (context-hints) entry from `settings.json`,
  leaving `hooks/hooks.json` untouched (a realistic single-manifest drift).
- **RED:** `bash tests/test-kit-foldin-hooks.sh` -> `Passed: 47 / 49`, suite exit 1, with
  exactly the two registration-dependent rows flipping:
  ```
    FAIL settings.json registers context-hints (expected exit 0, got 1)
    FAIL temp-HOME settings.json wires context-hints (expected exit 0, got 1)
  ```
  (the parallel `hooks/hooks.json registers context-hints` row stayed PASS, confirming the
  test detects a one-sided drift, not just a total removal.)
- **Restore:** `git checkout -- settings.json` -> `bash tests/test-kit-foldin-hooks.sh`
  suite exit 0 (49/49), `git diff --quiet settings.json` clean vs HEAD.

This falsifies the "both manifests wired" claim on demand: break either manifest and the
suite goes RED on the exact hook that drifted.

## Reproduce

```
cd <dwarves-kit>/.claude/worktrees/kf-02   # or merged master
bash tests/test-kit-foldin-hooks.sh   # 49/49
bash tests/test-meta.sh               # 672/672
bash tests/test-hooks.sh              # 452/452
```
