# Proof of done: kit-pitch (SPEC-140, kit-run-integrity mega-goal sub-goal 06, ID-250)

## 1. Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | Real sample: `lib/pitch.sh render <rid>` against a REAL recently-shipped rid produces all 5 sections, each grounded in a real file/ledger line. The two checks needing machine-local ledger content (PR link, grill-skip reason) assert against a frozen, committed snapshot of that same content (`tests/fixtures/pitch/real-sample/`) so the proof is CI-portable | PASS | `docs/verification/pitch-command/sample-pitch.md` (rendered against `kit-emit-sweep`, PR #168); `tests/fixtures/pitch/real-sample/`; `tests/test-pitch.sh` AC1 block |
| AC2 | NEGATIVE CONTROL (load-bearing): a rid with NO grill record prints the literal `no grill record for this run`, never a fabricated grill answer | PASS | `tests/fixtures/pitch/no-grill/`; `tests/test-pitch.sh` AC2 block |
| AC3 | NEGATIVE CONTROL (load-bearing): a rid with NO `docs/implementation-notes/<rid>.md` prints the literal `no implementation-notes file for this run`, never a fabricated deviation | PASS | `tests/fixtures/pitch/no-implnotes/`; `tests/test-pitch.sh` AC3 block |
| AC4 | Contrastive: the SAME two checks against the `full` fixture (both sources present) do NOT print the absence lines, and DO print the real content (both grill + both deviation entries + the NC + the AC table + the Out-of-Scope block) | PASS | `tests/fixtures/pitch/full/`; `tests/test-pitch.sh` AC4a/AC4b/AC4c |
| AC5 | NEVER-AUTO-POST (load-bearing): zero `gh pr/issue comment`, `discord`, `slack`, or `curl` in the EXECUTABLE surface (lib/pitch.sh's code lines, commands/pitch.md's bash blocks) | PASS | `tests/test-pitch.sh` AC5 block |
| AC6 | `commands/ship.md` Step 8 gains exactly one new advisory bullet, wired to the real `gate-ledger.sh show \| grep DEBT` + `pitch.sh team-shared` commands; its condition (significance=high AND team-shared) fires/doesn't fire correctly against real ledger fixtures + a stubbed `gh` | PASS | `tests/test-pitch.sh` AC6 block (grep-F wiring + 3 behavioral cases) |
| AC7 | `team-shared` is fail-safe: an unavailable/erroring `gh` returns "not team-shared" (exit 1), never throws | PASS | `tests/test-pitch.sh` AC7 block (3 stub modes: org/user/fail) |
| AC8 | The no-orphan command-emit sweep stays green with `commands/pitch.md` added (30 commands, a real emitter) | PASS (19/19) | `tests/test-command-emit-sweep.sh` (count pin 29->30) |

**Total: 29/29 PASS in `tests/test-pitch.sh`, 19/19 PASS in `tests/test-command-emit-sweep.sh`, 0 FAIL.**

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `lib/pitch.sh` (new engine: `outcome`/`unknowns`/`evidence`/`cost`/`ask`/`render`/`team-shared`), `commands/pitch.md` (new, thin wrapper), one advisory bullet in `commands/ship.md` Step 8 |
| Where | `lib/pitch.sh`, `commands/pitch.md`, `commands/ship.md` (Step 8), `tests/test-pitch.sh`, `tests/fixtures/pitch/{full,no-grill,no-implnotes}/` (12 committed fixture files), `tests/test-command-emit-sweep.sh` (count pin), `.github/workflows/test.yml` (+1 CI step), `README.md` + `docs/architecture.md` (+1 row each) |
| How it runs | On demand: `/kit:pitch <rid>` runs `bash lib/pitch.sh render <rid> [--out F]`, a pure read-only bash engine grounded in the spec / proof-of-done / implementation-notes / gate ledger. Ship-time: `commands/ship.md` Step 8 reads back the just-recorded DEBT verdict and offers the command only when `significance=high` AND `bash lib/pitch.sh team-shared` (a single `gh api repos/{owner}/{repo} --jq '.owner.type'` call) says the repo is org-owned |
| Reversibility | Purely additive; `lib/pitch.sh` and `commands/pitch.md` are new files with no callers elsewhere in the kit except the one new ship.md bullet, which is itself advisory (exit-0, never blocks). Reverting the diff removes `/kit:pitch` entirely with no residue (confirmed by the negative control below) |

## 3. Confirmation (runs)

| Run | When (UTC) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 GREEN | 2026-07-04 08:35 | `bash tests/test-pitch.sh` | 0 | PASS 29/29 |
| R2 GREEN | 2026-07-04 08:36 | `bash tests/test-command-emit-sweep.sh` | 0 | PASS 19/19 |
| R3 NEGATIVE CONTROL | 2026-07-04 08:38 | `git stash push -u -- lib/pitch.sh commands/pitch.md commands/ship.md tests/test-pitch.sh tests/test-command-emit-sweep.sh tests/fixtures/pitch README.md docs/architecture.md` then `bash tests/test-pitch.sh` | 127 | RED-as-expected: `/kit:pitch` vanishes entirely ("No such file or directory") |
| R4 RESTORE | 2026-07-04 08:39 | `git stash pop` then `bash tests/test-pitch.sh` | 0 | PASS 29/29 (restore-confirm) |
| R5 REGRESSION | 2026-07-04 08:40 | `bash tests/test-meta.sh` | 0 | PASS 669/669 (incl. the README/architecture doc-parity checks, now 30==30 and 54==54) |
| R6 REGRESSION | 2026-07-04 08:41 | `bash tests/test-hooks.sh && bash tests/test-understanding-wiring.sh && bash tests/test-kri-wiring.sh && bash tests/test-docs-wiring.sh && bash tests/test-significance-classify.sh && bash tests/test-quiz-gate.sh && bash tests/test-grill-conditioning.sh && bash tests/test-explain.sh && bash tests/test-references-field.sh` | 0 | 452/452, 19/19, 31/31, 22/22, 25/25, 29/29, 23/23, 14/14 (+15/15), all PASS |
| R7 CI-PORTABILITY FIX | 2026-07-04 15:25 | `env HOME="$(mktemp -d)" bash tests/test-pitch.sh` (scrubbed `HOME`, no `~/.local/state/dwarves-kit` ledger for `kit-emit-sweep`, mimicking CI's fresh checkout; reproduced the real CI failure first by re-running this exact command against the pre-fix AC1, which printed the same 27/29 with the same two FAILs CI reported, before moving the two ledger-content checks onto `tests/fixtures/pitch/real-sample/`) | 0 | PASS 29/29 (both PR-link and grill-reason checks now pass with zero local machine state) |

## 4. Run detail

### R1 GREEN

```
$ bash tests/test-pitch.sh
=== AC1: real sample -- render against a REAL recently-shipped rid (kit-emit-sweep) ===
  PASS AC1 sample-pitch.md was written
  PASS AC1 all 5 numbered sections present (got 5)
  PASS AC1 outcome section names the real spec (SPEC-139-kit-emit-sweep)
  PASS AC1 evidence section carries a real PR link (#168)
  PASS AC1 unknowns section surfaces the real grill skip (reason=operator-wave)
=== AC2 + AC4a: grill record -- NO-grill fixture (load-bearing) vs full fixture (contrast) ===
  PASS AC2 no-grill fixture prints the literal absence line
  PASS AC2 no-grill fixture never fabricates a grill answer (no 'branches resolved' text)
  PASS AC4a full fixture does NOT print the grill absence line
  PASS AC4a full fixture DOES surface its real grill content
=== AC3 + AC4b: implementation-notes -- NO-implnotes fixture (load-bearing) vs full fixture ===
  PASS AC3 no-implnotes fixture prints the literal absence line
  PASS AC3 no-implnotes fixture never fabricates a deviation (no 'fixture deviation' text)
  PASS AC4b full fixture does NOT print the implementation-notes absence line
  PASS AC4b full fixture DOES surface its real deviation entries (both of them)
=== AC4c: negative controls + evidence + cost sections, full fixture ===
  PASS AC4c unknowns section surfaces the proof's negative control
  PASS AC4c evidence section carries the verbatim acceptance-criteria table
  PASS AC4c cost section surfaces the spec's Out of Scope block
  PASS AC4c ask section is always emitted (pure template, no source to miss)
=== AC5: NEVER-AUTO-POST (load-bearing) -- grep negative control ===
  PASS AC5 zero auto-post CALLS in lib/pitch.sh's executable lines (found: 0)
  PASS AC5 zero auto-post CALLS in commands/pitch.md's bash code blocks (found: 0)
  PASS AC5 commands/pitch.md explicitly documents it never posts (prose, not code)
=== AC7: team-shared is fail-safe (stubbed gh, no network) ===
  PASS AC7 org owner -> prints 'yes', exit 0
  PASS AC7 user (solo) owner -> prints 'no', exit 1
  PASS AC7 gh failure -> fails SAFE ('no', exit 1), never throws
=== AC6: ship.md Step 8 advisory bullet -- wiring + behavioral condition ===
  PASS AC6 ship.md names the real read-back command (gate-ledger.sh show | grep DEBT)
  PASS AC6 ship.md names the real team-shared predicate (lib/pitch.sh team-shared)
  PASS AC6 ship.md states the bullet never blocks
  PASS AC6 high-significance + team-shared (org) -> offer fires
  PASS AC6 low-significance + team-shared (org) -> offer does NOT fire
  PASS AC6 high-significance + solo repo (user) -> offer does NOT fire

  ---------------------------------------------
  TOTAL: 29   PASS: 29   FAIL: 0
```

### R2 GREEN

```
$ bash tests/test-command-emit-sweep.sh
=== Results ===
Passed: 19 / 19
All command-emit-sweep tests passed.
```

### R3 NEGATIVE CONTROL (load-bearing)

```
$ git stash push -u -- lib/pitch.sh commands/pitch.md commands/ship.md tests/test-pitch.sh \
    tests/test-command-emit-sweep.sh tests/fixtures/pitch README.md docs/architecture.md
ok stashed

$ bash tests/test-pitch.sh
bash: tests/test-pitch.sh: No such file or directory
$ echo "exit=$?"
exit=127
```
Reverting the diff makes `/kit:pitch` disappear entirely (the whole feature, not a partial
degrade) -- as unambiguous a RED as a negative control gets. `test-command-emit-sweep.sh`
was ALSO reverted (both the new `commands/pitch.md` and the count-pin bump travel together in
the stash), so it stays internally consistent and green at 19/19 against the pre-change
29-count; it does not need its own separate RED here, since AC8's claim ("stays green WITH
pitch.md added") is proven by R2 above, not by this revert.

### R4 RESTORE

```
$ git stash pop
ok stash pop

$ bash tests/test-pitch.sh
  ---------------------------------------------
  TOTAL: 29   PASS: 29   FAIL: 0
```

### R5 + R6 REGRESSION

```
$ bash tests/test-meta.sh
Passed: 669 / 669
All meta tests passed.

$ bash tests/test-hooks.sh              # 452/452
$ bash tests/test-understanding-wiring.sh   # 19/19
$ bash tests/test-kri-wiring.sh          # 31/31
$ bash tests/test-docs-wiring.sh         # 22/22
$ bash tests/test-significance-classify.sh  # 25/25
$ bash tests/test-quiz-gate.sh           # 29/29
$ bash tests/test-grill-conditioning.sh  # 23/23
$ bash tests/test-explain.sh             # 14/14
$ bash tests/test-references-field.sh    # 15/15
```

## 5. Live captures (real ledger lines from the real run log, rid=`kit-pitch`)

```
$ bash lib/gate-ledger.sh show kit-pitch
2026-07-04T08:25:10Z | START | lane=full classified=full type=spec-feature ctype=spec-feature repo=dwarves-kit
2026-07-04T08:25:10Z | GATE | grill | skipped | reason=operator-wave: TIER1+3 framing done upstream ...
2026-07-04T08:25:15Z | GATE | think | override | TIER1+3 framing done by conductor; ...
2026-07-04T08:27:16Z | GATE | design | ran | SPEC-140 Design section: engine/command split ...
2026-07-04T08:27:16Z | GATE | spec | ran | docs/specs/SPEC-140-kit-pitch.md written ...
2026-07-04T08:27:16Z | GATE | validate | ran | self spec-validate, 6 lenses: no CRITICAL findings ...
2026-07-04T08:27:16Z | GATE | design-record | ran | SPEC-140 carries a non-empty ## Design block ...
2026-07-04T08:27:16Z | GATE | design-critique | override | single-agent autonomous sub-goal run ...
2026-07-04T08:27:16Z | GATE | test-plan | ran | SPEC-140 ## Test plan: 14-row coverage matrix ...
2026-07-04T08:35:05Z | GATE | build | ran | lib/pitch.sh (new engine, 8 subcommands...) ...
2026-07-04T08:35:05Z | GATE | review | ran | self-review: full regression ...
2026-07-04T08:35:05Z | GATE | docs | ran | README.md commands summary+table row ...
2026-07-04T08:35:05Z | GATE | reflect | override | narrow single-sub-goal wiring change ...
2026-07-04T08:35:59Z | GATE | verify | ran | PASS 29/29 test-pitch.sh + 19/19 test-command-emit-sweep.sh ...
```

All required `full`-lane gates (`think`, `design`, `design-critique`, `spec`, `validate`,
`design-record`, `test-plan`, `build`, `review`, `docs`, `reflect`) are recorded (ran or a
reasoned override); `ship` records at push time (Step 8). `grill` and `verify` are bonus
dogfooding (bespoke, non-required, same precedent as `kit-emit-sweep`).

## 6. Reproduce

```
cd dwarves-kit   # or the .claude/worktrees/kit-pitch worktree
bash tests/test-pitch.sh
bash tests/test-command-emit-sweep.sh
bash tests/test-meta.sh
```
