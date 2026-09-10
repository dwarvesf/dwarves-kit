# Proof of done: repohygiene + kit:repo-hygiene

Spec: `docs/specs/SPEC-256-repo-hygiene.md`. Run id: `repo-hygiene-audit`. Lane: full.
Type: reconcile. Contract owed (`lib/gate/proof-gate.sh contract`): an inventory with a
verdict per item plus a reference-fix diff, a seeded drifted item caught, and a behavioral
run of the REAL primary flow with a negative control.

## 1. Test suite

| # | Command | Result |
|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 51/51 passed, 0 failed |
| 2 | `bash tests/test-meta.sh` | All meta tests passed (master baseline: same) |
| 3 | `bash tests/test-audit-scanner-contract.sh` | All audit-scanner-contract tests passed |
| 4 | `bash tests/test-kit-contract.sh` | 25 passed, 0 failed (master baseline: 25/0) |
| 5 | `bash tests/run-all.sh` | 134 suites run, 1 skipped; the only failures are `test-orchestrate-gate-dispatch` (rc=5) and `test-orchestrate-wavefront` (rc=1), both of which fail identically on master with the same exit codes and touch nothing this branch changes |

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
twice, once at the default and once at `--stale-days 0`.

```
git -C <ops-toolkit> worktree add --detach <tmp> c2e7ae56^
bash lib/repohygiene/repohygiene.sh scan --repo <tmp> --detectors 1                        # 0 findings, 8s
bash lib/repohygiene/repohygiene.sh scan --repo <tmp> --detectors 1 --stale-days 0 \
     --max-candidates 5000                                                                 # 93 findings, ~9min
```

The wide run is where the map appears, at line 3 of the 95-line output: a header row, 93
findings, and a `SUMMARY` row. The cost is why `--max-candidates` exists: the reference grep
is one pass per candidate, because that grep IS the evidence.

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

Run after the build commit `d66b16e`, against the two invariants that carry the real cost if
they break: the detector-3 majority rule (a wrong owner moves someone's record to the wrong
place) and the detector-5 report-only verdict (a `REMOVE` on a gitignored path is a deletion
proposal the contract forbids).

```
=== NC-1: break the detector-3 majority rule ===
 lib/repohygiene/repohygiene.sh | 2 +-
  FAIL a minority owner scope does not claim the file
40/41 passed, 1 failed

=== NC-2: break the detector-5 report-only verdict ===
 lib/repohygiene/repohygiene.sh | 2 +-
  FAIL flags the large cold ignored dir as UNSURE
  FAIL every detector-5 finding is UNSURE, never FIX or REMOVE
39/41 passed, 2 failed

=== restored, green again ===
41/41 passed, 0 failed
```

NC-1 replaced the majority guard with a bare single-owner test. NC-2 changed detector 5's
`emit 5 UNSURE` to `emit 5 REMOVE`. Both were restored with `git checkout --` and the suite
returned to green. The transcript reads 41 assertions because it predates section 5, which
added ten.

The first NC-2 run failed only ONE assertion. The detector-5 warm-dir case earlier in the
suite left the fixture fresh, so the contract case had no detector-5 finding to judge. The
contract case now asserts a finding exists before judging it, which is what turned NC-2 into
two failures.

## 5. Review findings applied

Two adversarial lenses ran against the frozen build commit. Nine defects came back with a
live reproduction attached; all nine are fixed and each carries a regression case in the
`hostile input` block of `tests/test-repohygiene.sh`. The full invariant list is
`lib/repohygiene/SPEC.md`. The suite went from 41 to 51 assertions.

| Severity | Defect | Fix |
|---|---|---|
| CRITICAL | a newline in a staging filename forged an entire output row, and a detector-3 FIX row is the one verdict the loop acts on | `scrub` in `emit`, applied to all four fields |
| HIGH | a tab in a commit subject injected TSV columns into the evidence field | same |
| HIGH | detector 4 took the FIRST threshold source in path order, so a decoy doc claiming a 99999-line budget suppressed a real finding and the scan reported clean | read every source, take the strictest |
| HIGH | a tracked path named `COMMIT <ts>` parsed as a git-log header, poisoned the next file's timestamp, and the failed arithmetic dropped a real candidate | find the header by the blank line after it |
| HIGH | `stat -f %m` on GNU means `--file-system`, so every age on Linux was garbage and detector 2 silently found nothing | probe the format once at first use |
| HIGH | `core.quotePath` defaults on, so every non-ASCII path arrived C-quoted and dropped out of detectors 1, 3, and 4 | `-c core.quotePath=false` plus `-z` reads |
| MEDIUM | unquoted `$(git ls-files)` word-split a path with a space and dropped it | `-z` plus `read -r -d ''` |
| MEDIUM | a commit scope of `..` resolved as the owner `tools/..` and produced a FIX whose destination traversed out | scope charset and `..` rejection |
| MEDIUM | `--staging-dir` reached outside the repo, so it could put private-key filenames and hash prefixes into a PR body | `inside_repo` guard on every operator-supplied directory |

Three smaller ones landed with them: `find`'s exit status now decides coldness rather than its
output, every numeric flag is validated before arithmetic or a `find` argument sees it, and
`days_since` fails closed at `-1` so a poisoned timestamp keeps an item in the set.

## 6. Test plan coverage

Every row of SPEC-256's `## Test plan`, mapped to the run that covers it.

| Test-plan row | Covered by |
|---|---|
| Refusal, non-git target exits non-zero and names disk-reclaim | `tests/test-repohygiene.sh` refusal-guard block, 4 assertions |
| Detector 1, unreferenced flagged, referenced not | detector-1 block |
| Detector 1, young file below threshold | detector-1 block |
| Detector 1, regex metacharacters in a basename | detector-1 block |
| Detector 1, evidence carries the grep and its zero-hit result | detector-1 block |
| Detector 2, duplicate is REMOVE with path and sha | detector-2 block |
| Detector 2, no duplicate is UNSURE | detector-2 block |
| Detector 2, freshly touched drop leaves the set | detector-2 block |
| Detector 3, owned record is FIX with owner, evidence, destination | detector-3 block |
| Detector 3, control-surface log is never an owned record | detector-3 block |
| Detector 3, minority owner scope does not claim the file | detector-3 block |
| Detector 3, a mega-goal closed by its own marker with nothing open is FIX with a destination | mega-goal completion block |
| Detector 3, a commit keyword over open checklist items emits nothing | mega-goal completion block, one case per real misread |
| Detector 3, an unmarked mega-goal is UNSURE and never FIX | mega-goal completion block |
| Detector 3, a closed marker over open items is UNSURE, never FIX | mega-goal completion block |
| Detector 3, an open marker outranks a closing commit subject | mega-goal completion block |
| Detector 3, a checkbox inside a code span is not an open sub-goal | mega-goal completion block |
| Detector 3, a slug containing a closure keyword does not declare the goal closed | mega-goal completion block |
| Detector 4, over-budget log is FIX with counts and quoted source | detector-4 block |
| Detector 4, no documented budget yields UNSURE | detector-4 block |
| Detector 5, large cold ignored dir is UNSURE, REPORT ONLY | detector-5 block |
| Detector 5, under threshold or warm is not flagged | detector-5 block |
| Contract, no deletion verb in output or source | contract block |
| Contract, every detector-5 finding is UNSURE | contract block |
| Contract, every finding carries evidence | contract block |
| Wiring, dispatches audit-scanner, names the fallback, registered everywhere | wiring block, 5 assertions |
| Acceptance, rediscovers the hand-pass findings | section 2 above |
| Negative control | section 4 above |

Section 5's nine defects are covered beyond the test plan, in the `hostile input` block. The
test plan predates the review; the block is the review's own reproductions turned into
regressions.

## 7. Mega-goal completion precision (2026-09-11)

The first real run of this loop against `ops-toolkit` emitted five mega-goal findings. A human
then read each folder's own ROADMAP and found only TWO were finished. Every miss came from the
same cause: the detector decided a folder was complete by grepping the commits that touched it
for a closure keyword, and a commit subject describes one run, not the state of a roadmap.

Detector 3 is the one verdict this loop applies, so the folder's own record decides now, per
the precedence in `lib/repohygiene/SPEC.md`.

### Test suite

| # | Command | Result |
|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 63/63 passed, 0 failed (was 51 assertions; the mega-goal completion block added 12) |
| 2 | `bash tests/test-meta.sh` | 844/844 passed, all meta tests passed |
| 3 | `bash tests/test-kit-contract.sh` | 25 passed, 0 failed |

### Measurement

Both runs use the same frozen tree, `ops-toolkit` at `7be6151f`, which is the tree the first
live run saw. That commit is one before `ops-toolkit` PR #2550, which co-located two of the
five folders; freezing keeps that move out of the measurement.

```
git -C <ops-toolkit> worktree add --detach <snap> 7be6151f
bash lib/repohygiene/repohygiene.sh scan --repo <snap> --detectors 3
```

| | Findings | Mega-goal rows | True | False |
|---|---|---|---|---|
| Before | 6 | 5 | 2 | 3 |
| After | 2 | 1 | 1 | 0 |

The non-mega-goal row (`docs/briefs/CONTEXT.md`, a central path with three competing owners) is
unchanged in both runs, which is the negative half of the measurement: the file path of
detector 3 did not move.

### Per-folder outcome

| Folder | Human verdict | After | Why |
|---|---|---|---|
| `mochi-icy-simplify` | NOT complete, 4 open sub-goals and a "Blocked on Han" section, against a commit reading "mochi build complete, 08 shipped" | gone, fixed | 11 open checklist items, plus an open `State:` marker in HANDOFF.md |
| `vibe-dex-saas` | NOT complete, SG-08 is "BLOCKED-ON-ROUND-CAP, not completion" | gone, fixed | 2 open items, one of them the `- [~]` in-progress form |
| `hermes-multiplex-followups` | NOT complete, SG-03 half done and folded into another row | gone, fixed | 1 open item at `ROADMAP.md:44` |
| `icy-ops-enhancements` | complete | gone, fixed | 1 open item at `ROADMAP.md:20`, "06, final review ... PR #487 (OPEN, awaiting Han)", a box never flipped after the merge |
| `vibe-dex-showcase` | complete | gone, fixed | 1 open item at `ROADMAP.md:49`, "This roadmap reviewed by Han ... before SG-01 starts", a pre-flight box never flipped |
| `cluster-notify-wiring` | not reached by the hand pass | NEW, `UNSURE` | its own `## Status 2026-09-01: all four goals SHIPPED` and no open box anywhere |

The three false positives are gone. So are the two true ones, and that cost is deliberate:
both carried a stale unchecked box, so both folders' own records say they are unfinished. A
suppressed true positive costs one un-filed finding; a false FIX moves a live engine out of
the control surface. The loop takes the first cost.

Against the CURRENT tree (`ops-toolkit` at `1139120a`, after PR #2550) the same command
returns the same two findings, but the attribution differs per line: `icy-ops-enhancements` is
absent because #2550 moved it, and `vibe-dex-showcase` is absent for two reasons at once,
#2550 moved its documents and this fix's residue guard suppresses the empty directory the move
left behind. Before the fix, that empty shell still produced a finding, judged by the very
commit that emptied it.

### The archived corpus, as a control

`ops-toolkit` keeps seven already-archived mega-goals under `_meta/megagoals/_archive/`, every
one of them genuinely finished. All seven read as closed under the new test, with zero open
items each. That only holds because a box counts at the start of a line or of a table cell and
nowhere else: every `POINTER_PROMPT.md` in the estate spells the convention out mid-sentence as
`` `- [ ] NN-... PR #N` ``, and matching that instruction made all seven read as unfinished.

The first version of this fix also stripped code spans before counting, on the assumption that
the backticks were what excluded the boilerplate. Measured against all 31 mega-goal folders in
the corpus, stripping changed no count anywhere: the line anchor was already doing the work.
The negative control is what surfaced it, by breaking the stripping and watching the suite stay
green. The dead pass is gone and the comment now names the real mechanism.
