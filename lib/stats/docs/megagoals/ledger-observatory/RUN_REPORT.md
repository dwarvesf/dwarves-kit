# RUN_REPORT , ledger-observatory

**Terminus reached:** build + 4 merged + the held final PR. convergence gate (formerly TIER-4; the whole-objective verification pass, `CG` in the gantt) clean (5/5 lenses, zero blockers).
**Run window:** 2026-07-03 → 2026-07-04, one `/goal` thin-conductor session (~2h40m wall).
**Outcome:** the scattered ledgers now have ONE agent-callable read-only observability surface: `tools/ledger-observatory/` (DuckDB lens over the files in place) + a render skill + a propose-only feedback loop. Files stay canonical (delete-and-rematerialize, proven).

## Timeline (sequential stack; convergence gate fans out)

```
      0        20        40        60        80       100       120       140      160m
      ├────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┤
prep  ⣿⣿                                                                              read contracts, preflight
01    ░░⣿⣿⣿                        sonnet  claude -p         → merged b4ff175e  #672
02a   ░░░░░⣶⣶⣶✗                    OPUS    claude -p  KILLED (auth/kill class) , recovered from git
02b   ░░░░░░░⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿           OPUS    subagent   41m    → merged e6ff875b  #673  [HIGH-1 read-only bypass caught+closed]
03    ░░░░░░░░░░░░░░░░░⣿⣿⣿⣿⣿        sonnet  subagent   23m    → merged 7f8f7e2c  #674  [SKILL.md YAML-load self-catch]
04    ░░░░░░░░░░░░░░░░░░░░░░⣿⣿⣿⣿⣿⣿  OPUS    subagent   29m    → merged a0806ff3  #675
CG    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░⣿⣿  convergence gate: 5 lenses ∥ ~5m wall → ALL CLEAN
05    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░⣿⣿⣿⣿ sonnet subagent 15m  → PR #676  HELD for Han
```

Ghost lane (wavefront projection): the only non-linearity was the `02a` kill. Without it the run finishes ~15m
earlier (`⣷` band above). Everything else is inherently sequential (02←01, 03←02, 04←02+03, 05←ALL), so the
stack's critical path ≈ the sum of worker durations; the conductor added no parallel slack to reclaim except
the convergence gate fan-out (5 lenses collapsed from ~17m serial to ~5m wall).

## Worker minutes by model

| Model | Productive | Wasted (kill) | Where |
|---|---:|---:|---|
| opus | ~77.5m | ~15m | 02b (41), 04 (29), CG-integration (2), CG-security (5); 02a killed |
| sonnet | ~62m | 0 | 01 (14), 03 (23), 05 (15), CG-arch (3), CG-testcov (3), CG-advisor (4) |
| **total** | **~140m** | **~15m** | wall ~160m (sequential stack + conductor verify/merge overhead) |

## Gate-coverage matrix (recorded per-gate via `gate-ledger.sh record`)

| SG | spec | validate | test-plan | build | review | docs | ship | other |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|---|
| 01 schema | ✓ | ✓ | ovr | ✓ | ✓ | ✓ | ✓ | think/design/critique/reflect ovr |
| 02 etl-cli | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | grill+design-record; ui-design skip |
| 03 render | ✓ | ✓ | n/a | ✓ | ✓ | ✓ | ✓ | |
| 04 feedback | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | think/design/critique/design-record/reflect |
| 05 docs | ✓ | ✓ | n/a | ✓ | n/a | ✓ | ✓ | |

Over-tested sub-goals (02, 04) carried a COVERAGE-DELTA row + every named negative control green.

## Test totals (independently re-run by the conductor before each merge)

| Suite | Cases | Load-bearing NCs (conductor-verified) |
|---|---:|---|
| schema-conform | 11 | malformed line REJECTED |
| ledger-cli | 26 | read-only (sha256 unchanged) · delete-and-rematerialize · HIGH-1 PRAGMA-bypass regression |
| render-skill | 30 | single-data-path · SKILL.md YAML-parse |
| feedback | 39 | false-positive proposes-nothing · proposal-not-autofile (board byte-identical) |
| docs-wiring | 19 | over-claim caught (fabricated `ledger zzz` flagged) |
| **total** | **125** | all green |

Beyond the suites, the conductor ran its OWN probes: a read-only checksum on a live kit ledger before/after
`rebuild`+`query` (byte-identical), and a `_meta/BACKLOG.md` checksum before/after `ledger anomalies`
(byte-identical). The read-only-by-contract and propose-not-autofile guarantees hold in reality, not just in test.

## Callable-stack tree (no orphans , every node has a live dispatch path)

```
ledger (CLI, uv entry)
├─ config        env-driven source roots
├─ adapters      4 formats: kit pipe-log (REUSES lane-telemetry _rows) · learned md · tide sqlite · tg json
├─ materialize   DuckDB LENS  ── read guard ×3: statement-guard + read_only=True + enable_external_access=False
│                              ── db is derivable+disposable (gitignored ~/.cache), rebuild = delete+recreate
├─ show / query / rebuild / tables       structured out (--json | --table)
├─ render        ↦ render.py (zero-I/O)  → terminal (bot-reply-formatting) | web Artifact   ← skill/SKILL.md fires here
└─ anomalies     3 detectors (debt / cost-spike / misfire) → --propose STAGES into cc-backlog buffer (never auto-files)
```

## Dogfood , the observatory observed its own construction

`ledger rebuild && ledger query` on `main` after 01-04 merged:

```
table              rows            kit_runs by repo      runs  ovr
kit_runs            79             ?                       35   21
learned             54             dwarves-kit            29   15
tg_dialogs         625             ops-toolkit             9    5
tide_moves           0  (no db)    dotfiles                3    0
tide_tier_b_calls    0  (no db)    agent-a3a2fcbe…(SG-03)  1    0
                                   agent-ae757e5f…(SG-05)  1    0
```

The lens sees this very run: the SG-03 and SG-05 worktree agents appear as their own `kit_runs` rows. The 4
source formats all read (pipe-log 79 + markdown 54 + json 625 + sqlite present-but-empty), confirming
cross-format correctness on live data.

## Lessons (durable)

1. **The `claude -p` kill class is real; subagent-delegate designs it out.** 02a (headless `claude -p`, opus) was
   killed ~15m in (the auth/kill class OPERATE codified 2026-07-03). Recovery worked because the worker
   committed-before-pushing: only a regenerable spec draft was lost. The conductor then switched the remaining
   workers to in-harness worktree subagents (OPERATE's field-proven default), which share the conductor's
   auth+lifecycle , the failure never recurred across 02b/03/04/05 + 5 convergence gate lenses. Same context-thinness
   (subagent output stays off the conductor's context), zero kill exposure.
2. **Over-test earns its keep.** SG-02's own review caught HIGH-1: a multi-statement PRAGMA path that could write
   the filesystem and clobber a source ledger , the exact read-only-contract violation the NC exists to catch.
   Fixed with three independent layers + a sha256 regression. The load-bearing NC was not ceremony.
3. **Docs-last + honesty gate caught real staleness.** convergence gate found the render SKILL.md still said the feedback
   loop was "not built yet"; SG-05 destaled it and documented four known tradeoffs plainly rather than
   over-claiming. The over-claim NC bites (a fabricated `ledger` command is flagged).
4. **The tool's own thesis turned inward:** the architecture lens flagged that the lens defines its table schema
   twice (adapters vs materialize), hand-synced , a silent-drift hole in a tool built to kill silent drift. Routed
   to NOTES as a cheap parity-assert follow-up. The observatory needs its own drift guard.

## Held

PR #676 (05-docs) is OPEN and HELD for Han's click. On merge: box 05 flips `[x] merged <sha>`, and the mega-goal
folder co-locates to `tools/ledger-observatory/docs/megagoals/ledger-observatory/` per the lifecycle rule.
```
grep -oE 'PR #[0-9]+' ROADMAP.md | ... gh pr view   # 672-675 MERGED · 676 OPEN/HELD (audited)
```
