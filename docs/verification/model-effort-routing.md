# Proof of done: per-sub-goal model/effort routing (SG-03)

| | |
|---|---|
| **Profile** | feature (behavioral) |
| **Proof class** | behavioral: real orchestrator flow + tests + negative control |
| **Spec** | SPEC-087 "Model / effort routing" section |
| **Canonical** | this file |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | `orchestrate.sh` reads `Model:`/`Effort:` from each sub-goal's goal file | PASS | R1, R2 |
| AC2 | Reads pass to the session as `claude -p --model <tier> --effort <level>` | PASS | R2 |
| AC3 | Default-when-absent: no flag emitted, session inherits its tier | PASS | R1, R2 |
| AC4 | `--dry-run` prints the chosen tier per sub-goal | PASS | R1, R3 |
| AC5 | `tests/test-orchestrate.sh` covers parse, dry-run display, default-when-absent | PASS | R1 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `_route()` reads `Model:`/`Effort:` from a goal file; the run path passes `--model`/`--effort`; `--dry-run` shows the resolved tier; absent -> inherit (no flag) |
| Where | `lib/orchestrate.sh` (`_goalfile`, `_route`, `cmd_run`), `tests/test-orchestrate.sh` (TEST 6-7), `docs/specs/SPEC-087-context-hygiene.md` (routing section) |
| How it runs | `bash lib/orchestrate.sh run <dir> [--dry-run]`; CLI flags `--model`/`--effort` verified present (`claude` 2.1.195) |
| Reversibility | pure additive; absent fields reproduce the prior inherit-everything behavior |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-06-29 | `bash tests/test-orchestrate.sh` | 0 | PASS (19/19, incl. 4 new routing + the box-not-flipped negative control) |
| R2 | 2026-06-29 | real run via arg-logging mock (`CLAUDE_CMD`) | 0 | hinted SG-01 got `--model sonnet --effort low`; inherit SG-02 got no `--model` |
| R3 | 2026-06-29 | `bash lib/orchestrate.sh run <mixed-tiers> --dry-run` | 0 | distinct tiers per sub-goal + inherit |

## 4. Run detail

### R1 GREEN, full suite incl. negative control
- Command: `bash tests/test-orchestrate.sh`
- Exit: 0
- Output (tail): `... PASS run passes no --model for inherit SG-02 / ---- / ALL PASS`
- Negative control (pre-existing, still green): a session that does not flip its ROADMAP box
  halts the loop nonzero ("did not check its ROADMAP box"). Confirms the harness can go RED.

### R2 real flow, routing flags reach the session
- The run path dispatches `claude -p $route_flags $CLAUDE_FLAGS "$prompt"`. A mock `claude`
  logged `<id>|<flags>` per call. Hinted SG-01 line: `SG-01|... --model sonnet --effort low`.
  Inherit SG-02 line carried no `--model`. (TEST 7.)

### R3 dry-run tier display
- Command: `bash lib/orchestrate.sh run <mixed-tiers fixture> --dry-run`
- Output:
  ```
    -> SG-01 (auto)  [model: haiku, effort: low]   ...
    -> SG-02 (auto)  [model: sonnet, effort: medium] ...
    -> SG-03 (auto)  [model: opus, effort: high]   ...
    -> SG-04 (gate)  [model: inherit, effort: inherit] ...
    == STOP at SG-04 (gate: human review) ==
  ```
- Verdict: PASS. Routing is auditable before any token is spent.

## 5. Reproduce
```
git switch feat/model-effort-routing
bash tests/test-orchestrate.sh        # 19/19 ALL PASS
# dry-run on any megagoal dir with Model:/Effort: goal files:
bash lib/orchestrate.sh run <megagoal-dir> --dry-run
```
