# Proof of done , DAG-wavefront scheduling (SPEC-106 / board ID-084)

Canonical exit-criteria proof for the wavefront extension of `lib/orchestrate.sh`. This is the
run-table the DAG-wavefront goal's `Done=` names. Per-phase build verification (task-verifier +
fresh-context re-audits) lives alongside in `docs/verification/dag-wavefront.md`; this file is the
five-control acceptance table.

- Branch: `feat/dag-wavefront` · base ref `9973f04`
- Suites: `bash tests/test-orchestrate-wavefront.sh` (wavefront, 89 assertions) + `bash tests/test-orchestrate.sh` (serial regression, 59)
- Host: macOS bash 3.2 (CI target) + bash 5.x; `shellcheck -s bash lib/orchestrate.sh` clean
- Default posture: `WAVE_CAP=1` => the wave subsystem is unreachable; the serial path is byte-identical. Waves activate at `WAVE_CAP>=2` on Touches-declaring sub-goals (opt-in, Option B).

## Acceptance criteria (the brief's five controls)

| # | Control | Test (grep `EXIT-CRITERION N`) | Result |
|---|---|---|---|
| 1 | Two dep-independent, Touches-disjoint sub-goals run CONCURRENTLY; both land | `wave_run g` mock-barrier fifo (bidirectional; a serial impl times out) | PASS |
| 2 | **[NEGATIVE]** Touches-OVERLAPPING pair is SERIALIZED by the gate (never concurrent) | `wave_gate b` | PASS (2nd deferred) |
| 3 | Kill mid-wave; restart recomputes ready set, never re-runs a checked sub-goal | `resume` two-phase runlog | PASS |
| 4 | A `gate` sub-goal holds only its chain while an independent branch completes | `gate n` (out-of-process, real git repo) | PASS |
| 5 | **[NEGATIVE / GOLDEN]** Linear no-deps mega-goal behaves IDENTICALLY to serial master | `golden` (no `[wave]` marker; serial fresh-session body; ROADMAP order) | PASS |
| + | **Option-B honesty control:** a Touches-less ready set => ALL defer (waves inert until opt-in) | `wave_gate c` | PASS |

## Confirmation run

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate-wavefront.sh` (x3, flake check) | 0 | 89/89 `ALL PASS`, no flake |
| `bash tests/test-orchestrate.sh` (serial regression) | 0 | 59/59 `ALL PASS` |
| `shellcheck -s bash lib/orchestrate.sh` | 0 | clean |
| `grep -n "rm -rf\|wait -n\|declare -A" lib/orchestrate.sh` | , | only comments (bash 3.2 safe, no destructive calls) |

## Negative control (revert-to-RED , proves the checks bite)

Disabled the mkdir-lock (`_lock` made a no-op) in a throwaway in-place edit, re-ran the wavefront
suite, restored via `git checkout`:

| Step | Command | Result |
|---|---|---|
| Break | neuter `_lock` (concurrent `cmd_flip` loses atomicity) | , |
| Run | `bash tests/test-orchestrate-wavefront.sh` | Exit 1 , **5 FAIL**: `parallel flip: some boxes lost`, `wave_run g: concurrency NOT proven`, `dispatch k: wave not taken`, `gate n: did not stop cleanly`, `gate n: independents did not complete` |
| Restore | `git checkout -- lib/orchestrate.sh` | clean; suites green again (89/89, 59/59) |

The load-bearing concurrency primitive (the flip lock) is genuinely exercised: without it the
acceptance suite goes RED, so the green run is trustworthy, not vacuous.

## Scope / deferral honesty

Waves are DORMANT at the shipped default (`WAVE_CAP=1`), and real-wave ACTIVATION is deferred to
**ID-090** (per Option B, ADR-0030): (a) a `## Touches` schema + sub-goal generator so real
mega-goals become wave-eligible, (b) the `cmd_flip` prompt-injection into wave sessions, (c) the real
`mega-merge.sh merge <pr> <rid> <lane>` signature behind `WAVE_MERGE_CMD`, (d) the dep-aware
serial-fallback pick when `_ready_set` is non-empty. What ships now is the full, tested machinery with
mock seams (`CLAUDE_CMD`, `WAVE_MERGE_CMD`) + the five exit criteria green + serial byte-identical.

## Reproduce

```
cd ~/workspace/tieubao/dwarves-kit && git switch feat/dag-wavefront
bash tests/test-orchestrate-wavefront.sh   # 89/89, the five EXIT-CRITERION controls
bash tests/test-orchestrate.sh             # 59/59 serial regression (byte-identity)
```
