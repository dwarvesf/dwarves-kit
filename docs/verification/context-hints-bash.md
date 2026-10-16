# Verification: context-hints runs as bash plus jq

Verdict: PASS

Spec: `docs/specs/SPEC-406-context-hints-bash.md` (VALIDATED, revision 3). Change: `hooks/context-hints.sh` (port), `hooks/context-hints.py` (removed), `tests/lib/hook-parity.sh` (seed, read, tokens, bash 3.2). The orchestrator wrote the spec, the goldens, the port, and the harness; one fresh Opus reviewer attacked the spec and fuzzed the port against the Python (round 1, NEEDS REVISION, no critical finding on Claude Code's real payload shape), and its findings are folded into revision 3.

## Green run

```
Command: bash tests/test-context-hints-parity.sh
Exit: 0
Output:
context-hints parity: 137 passed, 0 failed
  PASS 1 MB prompt, 50 keywords: checked in 384 ms
  PASS jq missing: exit 0, one stderr line
  PASS hook names no python
  PASS symlinked hook reads the map beside the real file
Verdict: PASS
```

## Checks

| Check | Command | Result |
|---|---|---|
| Parity, every golden, UTF-8 locale | `bash tests/test-context-hints-parity.sh` | `137 passed, 0 failed` (goldens generated from the Python at `b9306b37` through its shim) |
| Parity under the macOS system tools | the same test with `/bin/bash` (3.2.57) and `/usr/bin/jq` (1.7.1) first on PATH | `137 passed, 0 failed` |
| Latency | the 1 MB prompt, 50-keyword check inside the test | 209 to 689 ms on a loaded machine (load average 25 to 75); the hook timeout is 5 s |
| Real prompts | 1,266 user prompts from real transcripts on this machine, the installed Python hook's real state files, a map of skill names, common words, Vietnamese and regex-hostile keys; Python behind its shim against the port | 1,266 identical (stdout, exit code, state), 125 with a temporal line, 1,099 with skill hints |
| Fresh review | one Opus reviewer: 692 hand-picked and random inputs, spec rows against the Python source | NEEDS REVISION; 0 critical on realistic input; 7 warnings and 8 nits, folded into revision 3 with 17 new goldens |
| Harness self-test | `bash tests/test-hook-parity-lib.sh` | `17 passed, 0 failed` |
| Foldin suite | `bash tests/test-kit-foldin-hooks.sh` | green inside `run-all --changed` |
| Config registry | `bash tests/test-config-registry.sh` | green inside `run-all --changed` (175 s, over the 90 s default ceiling; run with `RUN_ALL_TIMEOUT_SECS=900`) |
| Docs registry | `bash tests/test-meta-docs-registry.sh` | `120 / 120` after `feature-registry.sh check --fix` |
| No Python | `grep -c python hooks/context-hints.sh` | `0` (the parity test asserts it) |
| Changed suites | `bash tests/run-all.sh --changed --time` | 25 suites, 24 ok and one stale `docs/FEATURES.md`, regenerated and re-run green (above) |

## Negative controls

Each ran through `lib/gate/negctl.sh` in a scratch clone of the final head, with the parity test as the test command: commit first, mutate, parity red, restore with `git checkout HEAD --`, parity green.

| # | Mutation | Under mutation | Verdict |
|---|---|---|---|
| NC1 | drop the state write that precedes a crash (the prompt is not a string, the map is not an object) | 6 of 137 cases red | PASS |
| NC2 | treat a map that is not an object as no map | 3 of 137 cases red | PASS |
| NC3 | compare the nudge threshold with `>=` instead of `>` | 1 of 137 cases red | PASS |
| NC4 | drop the boundary test on the character after the key | 7 of 137 cases red | PASS |
| NC5 | drop the case-insensitive flag | 6 of 137 cases red | PASS |

One block as `lib/gate/negctl.sh` printed it (NC3):

```
## Negative control (negctl)
Command: bash tests/test-context-hints-parity.sh
Exit: 0 (green before mutation)
Output:
  context-hints parity: 137 passed, 0 failed
    PASS 1 MB prompt, 50 keywords: checked in 921 ms
    PASS jq missing: exit 0, one stderr line
    PASS hook names no python
    PASS symlinked hook reads the map beside the real file

Mutation: bash <scratch>/ch-nc.sh 3
Changed: hooks/context-hints.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL nudge-at-threshold
      want: {"name":"nudge-at-threshold","rc":0,"stdout":"Session time: 6h00m elapsed, 10m00s since your last prompt.","stderr":"","log":"","stray":"home/st/s1.json","files":{"home/st/s1.json":"{\"last\":22600,\"start\":1000}"}}
      got:  {"name":"nudge-at-threshold","rc":0,"stdout":"Session time: 6h00m elapsed, 10m00s since your last prompt.\nconsider /clear or /dcompact (cache-hygiene rule)","stderr":"","log":"","stray":"home/st/s1.json","files":{"home/st/s1.json":"{\"last\":22600,\"start\":1000}"}}
  context-hints parity: 136 passed, 1 failed
    PASS 1 MB prompt, 50 keywords: checked in 492 ms
    PASS jq missing: exit 0, one stderr line
    PASS hook names no python
    PASS symlinked hook reads the map beside the real file

Restore: git checkout HEAD -- hooks/context-hints.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- The 120 to 137 corpus pins what the Python does for the shapes someone thought of. The recorded divergences (spec, Failure modes) are the ones known and judged unrealistic: NaN, deep nesting, a NUL byte, special case folds.
- jq 1.6 is untested; the floor is the two versions run here.
- A real Claude Code `UserPromptSubmit` payload was not captured live; the real prompts above were wrapped in the documented payload shape.
