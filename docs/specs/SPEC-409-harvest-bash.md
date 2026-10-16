# SPEC-409: harvest runs as bash plus jq

**Status:** VALIDATED
Lane: full
Type: spec-refactor
**Proof:** `docs/verification/harvest-bash.md`; `tests/test-harvest-parity.sh`, `tests/test-kit-foldin-hooks.sh`, `tests/test-harvest-sweep.sh`, `tests/test-hook-util.sh`.
References: `hooks/harvest.py` and its shim at `b9306b37` (the behavior to reproduce); `docs/specs/SPEC-407-intake-sweep-bash.md` and `docs/specs/SPEC-408-backlog-stage-bash.md` (the jq grammar twin, the shlex splitter, and the helpers this port reuses); `tests/lib/hook-parity.sh`.

## Problem

`hooks/harvest.sh` is a shim around `hooks/harvest.py`. `docs/PHILOSOPHY.md` rules out Python in hooks, and the operator decided on 2026-09-28 to port the Python hooks to bash plus jq, one PR per hook. harvest is the last hook left. `hooks/harvest_sweep.py` (the scheduled sweep, a LaunchAgent job and not a hook) imports its state-dir resolver, slug rules, ledger locks and stager from `harvest.py`.

## Contract

`hooks/harvest.sh` does the hook's whole job in bash and jq: the PreCompact and SessionEnd harvest, `--lab-log`, and the opt-in `--stop-trigger`. It reproduces the Python hook's observable behavior: stdout, stderr, exit code, the ledger, the lab-log draft, the debounce stamps and turn counters, and the exact prompt the model receives.

| Observable | Rule |
|---|---|
| Exit code | always 0. A shape the Python crashed on stages nothing and prints nothing; whatever the Python had already written stays |
| Sweep gate | the auto modes (no flag, `--lab-log`, `--stop-trigger`) exit 0 when `HARVEST_SWEEP_CHILD=1`, or when the sweep is active on the host and `harvest.hook_when_sweep_on` is not true. Explicit verbs are never gated |
| Verbs | `--cleanup`, `--flush-list`, `--mark-flushed` and `--sweep`, `--dry-run`, `--status` run in `hooks/harvest_sweep.py` (they share per-ledger flock(2) locks with the sweep). Every other mode runs in bash |
| Detach | the default path hands the work to a child (`--harvest-run`, `--lab-log-run`, `--stop-harvest`) in its own process group, with the payload in a file under the state dir that the child always removes. `HARVEST_SYNC=1` and `HARVEST_STOP_SYNC=1` run inline |
| Debounce | `HARVEST_MIN_INTERVAL` (default 3600, zero or less turns it off): one `last-ledger` and one `last-lablog` stamp under the state dir, written before the payload is read |
| Transcript text | the text blocks of every `user` and `assistant` entry, newline-joined, the last `HARVEST_MAXCHARS` characters; the same walk and crash shapes as backlog-stage |
| Extractor | `HARVEST_EXTRACTOR` split like `shlex`, never through a shell, prompt on stdin, 120 s, stdout kept whatever the exit status except after a timeout |
| Dedup | slugs of the ledger's dated rows and of the glossary headings (`##` to `####`), the per-batch set, and the optional `HARVEST_FUZZY_THRESHOLD` Levenshtein distance; the dedup and the append run under the ledger's lock |
| Stop trigger | opt-in (`HARVEST_STOP_TRIGGER`), every `HARVEST_STOP_N` turns per session, one harvest in flight at a time |

## Picture

```
 PreCompact / SessionEnd --> harvest.sh
                               |  sweep gate, debounce stamp, transcript path
                               v
              payload-<pid>.json --> detached child: harvest.sh --harvest-run <file>
                                        |  extractor (stdin prompt, 120 s) --> first [...] --> candidates
                                        |  lock ledger.lock --> dedup (ledger, glossaries, batch, fuzzy) --> append
                                        v
                                  _meta/learned-ledger.md  (rows `queued`; a human flushes)

 --cleanup | --flush-list | --mark-flushed | --sweep | --dry-run | --status --> hooks/harvest_sweep.py
```

## Design

The detach, the transcript walk, the bracket scan, and the shlex splitter are the ones backlog-stage uses. The dedup and the append run in a second invocation (`--stage-locked`) under `flock(1)` or, on macOS, `lockf(1)`; both take flock(2), so they exclude the Python verbs that take the same lock. The slug, the kind and home normalization, and the Levenshtein walk are jq and awk over files, not arguments, so a large transcript never meets the OS argument limit.

`hooks/harvest.py` is split, not just deleted. What `hooks/harvest_sweep.py` imports as a library (state-dir resolver, slug rules, ledger locks, the stager) and the three operator verbs move to `hooks/harvest_lib.py`; the sweep imports it as `harvest` and its entry runs the verbs. That module is not a hook, and it stays Python because the sweep it serves is a 2,100-line Python job that is out of scope here.

## Failure modes

| Class | Mitigation |
|---|---|
| A rule differs from Python | the parity corpus (goldens from Python, including the exact prompt) fails |
| Not a new session | the detached child shares the hook's session, with its own process group; macOS has no `setsid` |
| Out of parity, no realistic input | invalid UTF-8 in the model output that is not caught, `NaN` in a JSON line, a candidate field that is a list or object, a `\r` alone as a line break in a jsonl file |
| A verb's usage line | now names `harvest_sweep.py`, where the operator verbs run |
| A Python crash | the Python printed a traceback through the shim; the port exits 0 silently. The goldens keep the crash as a silent exit 0 and every file the Python had written |
| `flock` and `lockf` both missing | the append runs unlocked, as a host with neither tool; the duplicate-append race is then possible |
| jq missing | exits 0 and names the missing tool on stderr |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: harness | `tests/lib/hook-parity.sh`, `tests/test-hook-parity-lib.sh` | a stamp the hook just wrote folds to `@NOW@` |
| T2: goldens | `tests/fixtures/harvest-parity/` | cases and goldens generated from the Python at `b9306b37` before the port |
| T3: port | `hooks/harvest.sh`, `hooks/harvest_lib.py`; delete `hooks/harvest.py` | `bash tests/test-harvest-parity.sh` passes; no `python` call in the hook outside the sweep routes |
| T4: references | `docs/hooks.md`, `docs/MANUAL.md`, `README.md`, `docs/architecture.md`, `tests/test-harvest-sweep.sh`, `tests/test-kit-foldin-hooks.sh` | no live doc or test names `harvest.py` as current code |
| T5: records | `docs/CHANGELOG.md`, `docs/verification/harvest-bash.md`, `docs/implementation-notes/harvest-bash.md`, `docs/retro/`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-harvest-parity.sh` | every case passes, `0 failed` |
| P2 | `bash tests/test-kit-foldin-hooks.sh`, `bash tests/test-harvest-sweep.sh`, `bash tests/test-hook-util.sh`, `bash tests/test-hook-parity-lib.sh` | exit 0 |
| P3 | P1 under `/bin/bash` (3.2) and `/usr/bin/jq` (1.7.1) | pass |
| P4 | `grep -c python hooks/harvest.sh` | only the two sweep-verb routes |

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command (NC1 uses the concurrency row of `tests/test-kit-foldin-hooks.sh`):

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | take no lock around the dedup and the append | `row 4c: 8 concurrent harvests ... stage exactly once` |
| NC2 | never apply the fuzzy threshold | the `fuzzy-*` cases |
| NC3 | ignore the glossary files | the `dedup-glossary-*` cases |
| NC4 | let one batch stage the same slug twice | `dedup-within-batch` |
| NC5 | keep the payload file after a detached child | the `detached-*` and `stop-detached-fire` cases |
| NC6 | fire the stop-trigger on every turn | the `stop-*` cases |
| NC7 | keep a timed-out extractor's stdout | `extractor-timeout-discards-stdout` |
| NC8 | drop the sweep-child recursion guard | `sweep-child-marker-exits` |
| NC9 | append to a ledger that is not valid UTF-8 | `crash-ledger-invalid-utf8` |

## Verification

P1 to P4 hold and NC1 to NC9 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

No hook runs Python. harvest stages with the same ledger rows, stderr lines, stamps, and prompt as before. The sweep keeps `hooks/harvest_lib.py` and `hooks/harvest_sweep.py` as Python; porting the sweep is a separate decision.

## Decision Log

- Goldens come from the Python hook at `b9306b37`, run through that revision's shim, before the port was written. They include the exact prompt the model was sent.
- The Python's tracebacks carry the scratch path of the run. The goldens keep each crash as a silent exit 0 with the files the Python had written, and rename the verbs' usage line.
- A recorded stamp is an epoch within a day of now; the harness folds it to `@NOW@` so a golden does not rot.
- `hooks/harvest.py` is split, not kept: the library the sweep needs moves to `hooks/harvest_lib.py`, so no file named like a hook is Python.
