# Proof of done , DAG-wavefront scheduling (SPEC-106 / board ID-084)

Canonical exit-criteria proof for the wavefront extension of `lib/queue/orchestrate.sh`. This is the
run-table the DAG-wavefront goal's `Done=` names. Per-phase build verification (task-verifier +
fresh-context re-audits) lives alongside in `docs/verification/dag-wavefront.md`; this file is the
five-control acceptance table.

- Branch: `feat/dag-wavefront` · base ref `9973f04`
- Suites: `bash tests/test-orchestrate-wavefront.sh` (wavefront, 89 assertions) + `bash tests/test-orchestrate.sh` (serial regression, 59)
- Host: macOS bash 3.2 (CI target) + bash 5.x; `shellcheck -s bash lib/queue/orchestrate.sh` clean
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
| `shellcheck -s bash lib/queue/orchestrate.sh` | 0 | clean |
| `grep -n "rm -rf\|wait -n\|declare -A" lib/queue/orchestrate.sh` | , | only comments (bash 3.2 safe, no destructive calls) |

## Negative control (revert-to-RED , proves the checks bite)

Disabled the mkdir-lock (`_lock` made a no-op) in a throwaway in-place edit, re-ran the wavefront
suite, restored via `git checkout`:

| Step | Command | Result |
|---|---|---|
| Break | neuter `_lock` (concurrent `cmd_flip` loses atomicity) | , |
| Run | `bash tests/test-orchestrate-wavefront.sh` | Exit 1 , **5 FAIL**: `parallel flip: some boxes lost`, `wave_run g: concurrency NOT proven`, `dispatch k: wave not taken`, `gate n: did not stop cleanly`, `gate n: independents did not complete` |
| Restore | `git checkout -- lib/queue/orchestrate.sh` | clean; suites green again (89/89, 59/59) |

The load-bearing concurrency primitive (the flip lock) is genuinely exercised: without it the
acceptance suite goes RED, so the green run is trustworthy, not vacuous.

## Real end-to-end wave run (de-risk , closes the "never actually run" gap)

The suite proves the machinery with mock sessions. To close the reviewers' concern that the wave path
had never spawned a real session, two throwaway end-to-end runs of the REAL orchestrator
(`orchestrate.sh run <demo> WAVE_CAP=2`, 2 disjoint-`## Touches` sub-goals):

| Run | Session | Result |
|---|---|---|
| Plumbing | scripted (non-LLM) | run exit 0; **both sessions started 5µs apart** (genuine overlap); each worked in its own worktree; each ran the injected `orchestrate.sh flip <abs-megadir> <id>` → both boxes `[x]` in the SHARED ROADMAP; driver reaped both, converge safe-skipped placeholders, clean exit |
| Real LLM | `claude -p` (v2.1.199) | run exit 0 (~42s); two real Claude sessions ran concurrently in separate worktrees, wrote the correct files (`alpha`/`beta`), and **each obeyed the injected flip contract** ("flipped SG-0N in the shared roadmap via the contract command") → both boxes `[x]`; driver advanced + completed |

This required implementing the **flip-contract injection** (a wave session is told to flip via the
lock-guarded CLI against the shared absolute ROADMAP, since its worktree copy is invisible to the
driver) , ID-090 item (b), now DONE + regression-guarded (`tests/test-orchestrate-wavefront.sh`,
`flip-injection` cases). Both proofs were on throwaway git repos; no repo state touched.

## Scope , ACTIVATED (ID-090, waves ON by default)

SPEC-106 first shipped Option B (waves dormant at `WAVE_CAP=1`). The ID-090 activation, folded into
this same PR, turned waves ON: all four deferrals are DONE , (a) `commands/mega.md` emits `## Touches`
per generated sub-goal + the schema is documented, (b) the `cmd_flip` prompt-injection into wave
sessions, (c) the real `mega-merge.sh merge <pr> <rid> <lane>` arity behind `WAVE_MERGE_CMD`, (d) the
dep-aware serial-fallback halt , and **`WAVE_CAP` now defaults to 2**, gated on a gate audit (no live
mega-goal ROADMAP relies on `gate`=global-stop) + a bare-`gate`-under-concurrency advisory.

Proven that waves fire BY DEFAULT: a real `claude -p` wave (above) plus a scripted run with NO
`WAVE_CAP` set + disjoint `## Touches` took the wave path (both sessions spawned concurrently, both
flipped the shared ROADMAP). The regression guarantee is preserved two ways in the suite: EXIT-CRITERION
5 pins `WAVE_CAP=1` (explicit serial opt-out is byte-identical even with Touches declared), and its
`[DEFAULT]` companion proves a Touches-LESS mega-goal serializes at the default (the flip is a no-op
for un-migrated mega-goals). `WAVE_CAP=1` forces the always-serial loop.

## Reproduce

```
cd ~/workspace/tieubao/dwarves-kit && git switch feat/dag-wavefront
bash tests/test-orchestrate-wavefront.sh   # 89/89, the five EXIT-CRITERION controls
bash tests/test-orchestrate.sh             # 59/59 serial regression (byte-identity)
```
