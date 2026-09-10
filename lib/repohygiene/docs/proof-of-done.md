# Proof of done: repohygiene + kit:repo-hygiene

Spec: `docs/specs/SPEC-256-repo-hygiene.md`. Run id: `repo-hygiene-audit`. Lane: full.
Type: reconcile. Contract owed (`lib/gate/proof-gate.sh contract`): an inventory with a
verdict per item plus a reference-fix diff, a seeded drifted item caught, and a behavioral
run of the REAL primary flow with a negative control.

## 1. Test suite

| # | Command | Result |
|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 40/40 passed, 0 failed |
| 2 | `bash tests/test-meta.sh` | All meta tests passed (master baseline: same) |
| 3 | `bash tests/test-audit-scanner-contract.sh` | All audit-scanner-contract tests passed |
| 4 | `bash tests/test-kit-contract.sh` | 25 passed, 0 failed (master baseline: 25/0) |

## 2. Acceptance: does it rediscover the hand pass?

The 2026-09-10 hand pass over `ops-toolkit` produced four groups of findings, all since
fixed. Each row below was re-run against the repo AT ITS PRE-FIX COMMIT, in a detached
worktree, with the shipped scanner.

Command, groups 1 and 3 and 4:

```
git -C <ops-toolkit> worktree add --detach <tmp> b2644f33^
bash lib/repohygiene/repohygiene.sh scan --repo <tmp> --detectors 3,4
```

| Hand-pass finding | Detector | Reproduced? | Evidence the scanner emitted |
|---|---|---|---|
| Kit research and brief files at fixed central paths, owners `tools/vps-mon` and `tools/alert-triage` | 3 | YES, 8 of 8 files. Six resolve to one owner (`FIX`), two to competing owners (`UNSURE`) | `3 FIX docs/research/architecture.md  owner tools/vps-mon in 1 of 1 commits touching it, by conventional-commit scope; latest: c05d7918 feat(vps-mon): macOS collector agent in Go, same wire envelope (#2292); co-locate to tools/vps-mon/docs/research/architecture.md` |
| The two files the hand pass split across both owners | 3 | YES, as `UNSURE`, which is the honest verdict | `3 UNSURE docs/briefs/DECISION-BRIEF.md  a central path reused across runs: 3 commits, 2 owners by commit scope (tools/vps-mon x1 tools/alert-triage x1 ); the operator splits it or names one owner` |
| A completed mega-goal still parked in `_meta/megagoals/` | 3 | YES, plus five more the hand pass did not reach | `3 UNSURE _meta/megagoals/zedra-select-scroll  closed mega-goal still in the control surface: "48e47456 chore(megagoal): close zedra-select-scroll (platform blocker)"; a completed mega-goal is a record and co-locates with its owner; no commit scope resolves an owner, so the operator names the destination` |
| `_meta/LAB_LOG.md` at ~4190 lines against a ~2000 threshold, 2026-08 at 611 against ~200 | 4 | YES, with the threshold's source quoted | `4 FIX _meta/LAB_LOG.md  total=4175 lines vs threshold 2000; busiest month 2026-08 at 638 vs per-month 200; source CLAUDE.md:29 "- **Trim when it crosses thresholds.** If LAB_LOG exceeds ~2000 lines or any single month occupies more than ~200 lines, run doc-compaction on it."; rotate or compact per the repo's own procedure, report only` |
| `_meta/NOTION-TOOLING-MAP.md` unreferenced anywhere | 1 | YES on the reference half, only with `--stale-days 0`. See the caveat below | `1 UNSURE _meta/NOTION-TOOLING-MAP.md  last touched 2026-09-06 (4d, threshold 0d); git grep -I -n -E '(^\|[^A-Za-z0-9_-])NOTION-TOOLING-MAP\.md' -- ':(exclude)_meta/NOTION-TOOLING-MAP.md' -> 0 hits outside itself` |
| Fourteen `_inbox` drops past 30 days, nine of them exact duplicates | 2 | NOT REPRODUCIBLE from history. See below | fixture-verified only |

Full scanner output, 17 findings, groups 1/3/4 at `b2644f33^`: the six `FIX` rows above plus
`desk-context.md`, `desk-thread-context.md`, `features.md`, `hermes-engine-tool.md`,
`stack.md`; the `UNSURE` rows for `pitfalls.md`, `CONTEXT.md`, `DECISION-BRIEF.md`, six
closed mega-goals, and `_meta/learned-ledger.md` (counts, no documented threshold).

### Caveat 1: detector 1 and the age gate

`_meta/NOTION-TOOLING-MAP.md` was FOUR DAYS OLD when the hand pass found it unreferenced. The
reference half of the contract reproduces exactly and the evidence grep returns zero hits at
`c2e7ae56^`, but at any sane `--stale-days` the age gate suppresses it. Age is a noise filter,
not part of the contract, so the skill instructs a first pass over a repo to run detector 1
twice, once at the default and once at `--stale-days 0`. The second run is what surfaces this
file. At the default 180 days, the same repo yields zero detector-1 findings in 8 seconds.

### Caveat 2: detector 2 cannot be validated against this history

`_inbox/` is gitignored in `ops-toolkit` (only `.gitignore` and `README.md` are tracked), so
the fourteen drops and their nine duplicates left NO git trail: no commit, no age, no content
to hash. A search of the history around 2026-09-10 for an `_inbox` purge found none, and the
directory's current contents are not consistent with fourteen stale drops having just been
cleared. This is not a detector gap, it is an evidence gap in the acceptance set, and it is
recorded here rather than papered over. Detector 2 is verified against a seeded fixture
instead (`tests/test-repohygiene.sh`, detector 2 block): a stale drop with a content-identical
copy elsewhere, one without, and a freshly touched one, asserting the duplicate's path, its
sha256, and the mtime-not-git basis.

### Detector 5, live run

```
bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit> --detectors 5 --cold-mb 20 --cold-days 30
```

Eight findings in 2 seconds, every one `UNSURE` and tagged `REPORT ONLY, gitignored, never a
deletion proposal`: five `.venv` trees, a seed-data render dir, a dictionary dir, and an
Xcode build dir. No deletion was proposed for any of them, which is the contract.

## 3. Seeded drifted item (the reconcile contract's own requirement)

Each detector's test block seeds exactly the decay it is meant to catch into a real throwaway
git repo and asserts both directions: the seeded item is flagged, and its clean sibling is
not. Detector 1 seeds an orphan note beside a referenced one; detector 2 a duplicated drop
beside a unique one; detector 3 an owned record beside the control surface's own log;
detector 4 an over-budget log beside a repo that documents no budget; detector 5 a large cold
ignored dir, then the same dir under the size threshold and warm.

## 4. Negative control

Recorded in section 5 below, after the build commit.

## 5. Negative control run
