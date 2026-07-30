# Proof of done: detach the harvest/backlog-stage LLM call from SessionEnd

VERDICT: PASS

## Acceptance criteria

1. `harvest.py`'s no-arg mode, `harvest.py --lab-log`, and `backlog-stage.py`'s `main()`
   each return control to the invoking hook almost immediately, REGARDLESS of how long
   their `claude -p` extractor call takes.
2. The actual work (extractor call, dedup, file write) still happens and still lands in
   the right file -- it is deferred to a detached child, not skipped.
3. `HARVEST_SYNC=1` / `BACKLOG_STAGE_SYNC=1` preserve the old inline behavior exactly
   (test-fixture determinism; existing pre-fix assertions still pass unmodified in spirit).
4. Existing behavior is unaffected: the full `tests/test-kit-foldin-hooks.sh` suite, plus
   the sibling suites that exercise these two hooks indirectly, stay green.

## Implementation

See `hooks/harvest.py` (`_spawn_detached`, `cmd_lab_log_run`, `cmd_harvest_run`,
`_dispatch`) and `hooks/backlog-stage.py` (`stage_from_text`, `_spawn_detached`,
`cmd_staged_run`, `main`). Full rationale in the module docstrings and the PR description
(dwarvesf/dwarves-kit#298).

## Confirmation run-table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Full kit-foldin hooks suite | `bash tests/test-kit-foldin-hooks.sh` | **68/68 PASS** |
| 2 | backlog-stage detach mechanism (instant fake extractor) | rows "3b" in the suite | PASS |
| 3 | harvest detach mechanism, both modes (instant fake extractor) | rows "4c"/"4d" | PASS |
| 4 | **The actual bug**: hook stays fast under a 2s-SLOW extractor (backlog-stage) | row "3c" | PASS -- hook returns in 37ms, candidate lands ~2s later |
| 5 | **The actual bug**: hook stays fast under a 2s-slow extractor (harvest no-arg) | row "4e" | PASS -- hook returns in 39ms, ledger entry lands ~2s later |
| 6 | **The actual bug**: hook stays fast under a 2s-slow extractor (harvest --lab-log) | row "4f" | PASS -- hook returns in 44ms, draft lands ~2s later |
| 7 | ID-202 concurrent-harvest dedup regression (unrelated invariant, must still hold) | row "4c" (concurrency block) | PASS -- 8 concurrent harvests stage the insight exactly once |
| 8 | Sibling suites that also exercise these hooks | `test-install-modules.sh`, `test-intake-sweep.sh`, `test-learn-drain.sh`, `test-adopt.sh` | all green (37, 28, 23, 21 passed respectively) |

Rows 4/5/6 are the load-bearing ones: they run the hook with an extractor that
`sleep 2`s before answering (approximating a real `claude -p --model haiku` call) and
assert the hook itself returns in under 1 second regardless, then poll (up to 5s) for the
real output to land afterward. The earlier rows (3b/4c/4d) only prove the detach
mechanism doesn't break the ledger/staging-file writing path; they use an instant fake
extractor and would pass even without this fix, since the hook is fast either way when the
extractor is fast. Rows 3c/4e/4f are the ones that actually distinguish before/after.

## NEGATIVE CONTROL (revert -> RED -> restore)

To prove rows 3c/4e/4f actually detect the bug (not just green-no-matter-what):

- **Revert:** `git checkout origin/master -- hooks/harvest.py hooks/backlog-stage.py`
  (restores the pre-fix, fully-synchronous implementation), keeping the new
  `tests/test-kit-foldin-hooks.sh` (with the slow-extractor rows) as-is.
- **RED:** `bash tests/test-kit-foldin-hooks.sh` -> `Passed: 65 / 68`, suite exit 1, with
  exactly the three timing assertions this fix targets flipping (the exit-0 and
  eventual-file-content assertions in the same rows still pass -- the old code was never
  incorrect, only slow/blocking):
  ```
  FAIL row 3c: hook took 2199ms (expected <1000ms) -- hook is blocking on the slow extractor again
  FAIL row 4e: no-arg hook took 2229ms (expected <1000ms) -- hook is blocking on the slow extractor again
  FAIL row 4f: --lab-log hook took 2262ms (expected <1000ms) -- hook is blocking on the slow extractor again
  ```
- **Restore:** `git checkout HEAD -- hooks/harvest.py hooks/backlog-stage.py` ->
  `bash tests/test-kit-foldin-hooks.sh` -> suite exit 0, `Passed: 68 / 68`.

This falsifies the "the hook is fast regardless of extractor latency" claim on demand:
put the synchronous code back and the suite goes RED on exactly the three rows that
measure it, nothing else.

## Round 2: /kit:review-team findings, fixed

A 4-lens review (security, architecture, test-coverage, advisor) ran against this PR and
returned 12 findings (0 CRITICAL, 3 HIGH, 4 MEDIUM, 5 LOW). Six were fixed here; the rest
are advisory/low-priority and logged, not blocking:

| # | Finding | Fix |
|---|---|---|
| 1 | Corroborated 3x (security, test-coverage, advisor): a corrupt/truncated payload handoff file, or a `Popen` failure right after the file was written, leaked the payload file forever -- the `finally` cleanup only ran on the SECOND of two nested `try`s. | `harvest.py`: extracted `_read_and_run(pf, work)` wrapping the read + work in ONE outer `finally`, used by `cmd_stop_harvest`/`cmd_lab_log_run`/`cmd_harvest_run`. `backlog-stage.py`'s `cmd_staged_run` gets the same shape inline (only one such caller there). Both `_spawn_detached` variants also now remove the just-written payload file if `Popen` itself fails. |
| 2 | (advisor) The fix's actual SessionEnd-specific claim -- the detached child survives via `start_new_session=True` -- was never tested; every row only measured wall-clock elapsed + polled for eventual content. | New rows (`3e`, `4i`): verify via `ps -o pgid=` that the detached child's process group differs from the invoker's, proving real OS-level isolation (chosen over a kill/signal race, which would be flaky to time against process spawn). |
| 5 | (architecture) `_spawn_detached` had the same name in both files with a different arity (3-arg in harvest.py vs 2-arg in backlog-stage.py), silently breaking the house convention that duplicated helpers share identical signatures. | Renamed backlog-stage.py's copy to `_spawn_staged_detached`; updated its docstring and every call site/comment. |
| 6 | (test-coverage) `HARVEST_SYNC`/`BACKLOG_STAGE_SYNC` was proven to produce the same output, never proven to actually run INLINE -- a regression silently turning it into a no-op would still pass. | New rows (`3d`, `4g`, `4h`): SYNC + the slow extractor, assert elapsed >= ~1.8s (genuinely blocked). |
| 7 | (test-coverage) `stage_from_text()`, a newly-extracted pure function built to be independently testable, was only exercised indirectly, happy-path only. | New row (`3g`): direct unit test via `importlib.util` (mirrors the ID-202 race harness's own pattern), covering the dedup-skip and empty-candidates branches. |
| 9 | (advisor) Both `HARVEST_STATE_DIR`/`BACKLOG_STAGE_STATE_DIR` docstrings still described their old sole purpose (lock/throttle dir), not the new payload-handoff use this PR adds. | Updated both docstrings. |

Not fixed here (advisory/low-priority, logged for follow-up): `--stop-trigger` has zero
test coverage before or after this refactor (pre-existing gap, not introduced by this
PR); `backlog-stage.py`'s dedup+append has no lock equivalent to harvest.py's
`harvest.lock` (mitigated by the 1h `BACKLOG_STAGE_MIN_INTERVAL` throttle); detached
children fully silence stderr (by design, unchanged from the pre-existing
`--stop-trigger` posture); predictable payload filename + non-`O_EXCL` write (requires
attacker at the local user's own trust level to matter); small intra-file duplication in
`_dispatch`'s branches (below the rule-of-three).

### Round 2 run-table

| # | Check | Result |
|---|---|---|
| 1 | Full suite after all 6 fixes | **91/91 PASS** (was 68; +23 new rows: 3d/3e/3f/3g, 4g/4h/4i, 4j-4l x3) |
| 2 | Targeted negative control: revert JUST the `_read_and_run`/`cmd_staged_run` outer-`finally` fix (finding #1), keep everything else | rows `3f`/`4j-l` (all 4 detached entry points) go RED -- `exits 0` still PASS, `corrupt payload file was removed` FAILs on every one; restored, back to 91/91 |
| 3 | Process-group isolation (finding #2) | rows `3e`/`4i` PASS: detached child's pgid differs from the invoker's in both files |
| 4 | SYNC-seam genuinely blocks (finding #6) | rows `3d`/`4g`/`4h` PASS: elapsed >=1.8s under the 2s-slow extractor with SYNC=1 set |
| 5 | `stage_from_text` unit test (finding #7) | row `3g` PASS: dedup-skip and empty-candidates branches both covered |

## Round 3: real `claude -p` CLI runs (not just the bash test harness)

Everything above drives the hook scripts directly (hand-built payloads via
`bash -c "echo '{...}' | bash hooks/harvest.sh"`). That proves the code is correct, but
never exercised the actual mechanism this whole fix depends on: Claude Code's own
`SessionEnd` hook runner, its declared timeout, and real process teardown at real CLI
exit. Ran the real thing: two scratch clones (`origin/master` = pre-fix,
`origin/fix/hook-detach-sessionend` = fixed), a real git-init'd project dir, and
`claude -p "<prompt>" --model haiku --setting-sources project --settings <SessionEnd
wiring to the clone's hooks/*.sh>` -- an actual `claude` process, actually exiting,
actually firing `SessionEnd`, with `HARVEST_EXTRACTOR`/`BACKLOG_STAGE_EXTRACTOR`
swapped for a fake slow script (a real `claude -p --model haiku` extractor call was
correctly out of scope to fake around; the timing claim under test is about the HOOK
RUNNER, not the extractor itself).

### The four SPEC-126 components (per the `proof-capture` skill)

This change has no visual surface a human watches (a background hook, not a TUI/UI),
so per the skill's own decision ladder it owes a captured transcript, not a GIF/video.

| Component | Where |
|---|---|
| Viewable artifact | `hook-detach-sessionend-transcript.txt` (this dir) -- the exact, verbatim stdout/stderr from 4 real `claude -p` sessions, nothing paraphrased |
| Committed reproduce script | the shell commands embedded in that same transcript file, plus the condensed form below |
| Verified-content note | below |
| Negative control | scenes 2 and 3 in the transcript (pre-fix hooks, same extractors) -- the bug-present state, side by side with the fix |

| # | Scenario | Result |
|---|---|---|
| 1 | FIXED hooks, 2s-slow extractor, tool-free prompt | `claude -p` elapsed **3.79s**; both hooks logged `completed with status 0`; detached child's ledger/draft/staging output landed correctly afterward |
| 2 | PRE-FIX hooks, SAME 2s-slow extractor, same prompt | `claude -p` elapsed **5.87s** -- +2.08s, matching the extractor's sleep exactly; output landed too (pre-fix was never wrong, only blocking) |
| 3 | PRE-FIX hooks, extractor slowed to 33s (exceeds the hook's declared 30s timeout) | `claude -p` elapsed **34.1s**; printed, verbatim, the ORIGINAL reported bug: `SessionEnd hook [...harvest.sh --lab-log] failed: Hook cancelled` -- reproduced from a real CLI session, not inferred |
| 4 | FIXED hooks, the SAME 33s-slow extractor | `claude -p` elapsed **3.79s** (identical to the 2s case -- completely decoupled from extractor duration now); both hooks `completed with status 0`, no cancellation; the detached child's output landed correctly ~33s later, well after the CLI process had already exited |

Row 3 is the whole investigation's origin, reproduced on demand: the exact "Hook
cancelled" banner Han saw at real session exit, now understood precisely (the
synchronous extractor call exceeding the hook's own declared timeout) and triggerable
at will. Row 4 confirms the fix eliminates it -- not by getting faster, but by
structurally removing the coupling between extractor duration and hook-runner timeout.
No lingering processes were left behind by either scenario (`pgrep` confirmed clean
after each run).

## Verified-content note

- **Content**: every command and every output line in `hook-detach-sessionend-transcript.txt`
  is a direct copy of the real terminal output captured during this session -- no line was
  reconstructed, summarized, or retyped from memory.
- **Authenticity**: both the pre-fix and fixed sides ran the SAME fake slow extractor
  scripts and the SAME prompt, so the only variable between scenes 1-vs-2 and 3-vs-4 is
  which branch's `hooks/*.py` was checked out in the cloned repo the `--settings` JSON
  pointed at.
- **Privacy**: recorded from scratch clones + a scratch project dir under
  `/private/tmp/.../scratchpad/real-run/` (session-local, gitignored scratch, not
  committed); no leaked credentials, client data, or unrelated repo paths -- the only
  paths visible are this scratch directory's own name and the two clones' hook file
  paths, both already public in the PR itself.
- **Negative control**: scenes 2 and 3 ARE the negative control (bug-present state) --
  same inputs as scenes 1 and 4, only the code reverted to pre-fix `master`.

## Run detail

The load-bearing scene (round 3, scene 3 of `hook-detach-sessionend-transcript.txt`):

```
Command: HARVEST_EXTRACTOR=very-slow-lablog.sh HARVEST_MIN_INTERVAL=0 \
  claude -p "Just reply with exactly the word OK. Do not use any tools." \
  --model haiku --setting-sources project --settings settings-prefix.json \
  --debug-file timeout-debug.log
Exit: 0 (the claude process itself exits cleanly; the HOOK inside it is what gets cancelled)
Output: OK
         SessionEnd hook [bash .../kit-prefix/hooks/harvest.sh --lab-log] failed: Hook cancelled
Elapsed: 34.136220000s
```

And the fixed side, same extractor, same prompt (scene 4):

```
Command: HARVEST_EXTRACTOR=very-slow-lablog.sh HARVEST_MIN_INTERVAL=0 \
  claude -p "Just reply with exactly the word OK. Do not use any tools." \
  --model haiku --setting-sources project --settings settings-fixed.json \
  --debug-file fixtimeout-debug.log
Exit: 0
Output: OK
Elapsed: 3.788657000s (no cancellation; debug log shows both hooks "completed with status 0")
```

Full transcript, all 4 scenes: `hook-detach-sessionend-transcript.txt` (this dir).

Rollback: pure hook + test + doc change, no state/data migration; the only "state" this
PR touches is the payload-handoff files under `~/.claude/dwarves-kit/state/{harvest,
backlog-stage}/`, which are transient (written and removed within one hook invocation,
never a durable store). Rollback is `git revert` of the three feature commits (no
restore procedure needed, no migration to undo). [UNAVAILABLE: no stateful
rollback/migration flow exists here -- this is a behavior change to a hook script, not
a deploy or data change.]

## Reproduce

```
cd dwarves-kit   # this branch (fix/hook-detach-sessionend), or merged master
bash tests/test-kit-foldin-hooks.sh   # 91/91
```

Real-CLI reproduction (round 3): clone both `origin/master` and this branch, `git init`
a scratch project dir, write a `--settings` JSON wiring `SessionEnd` to
`hooks/backlog-stage.sh` + `hooks/harvest.sh --lab-log` at the clone's absolute path,
then run `HARVEST_EXTRACTOR=<a sleep-N-then-answer script> HARVEST_MIN_INTERVAL=0
claude -p "<tool-free prompt>" --model haiku --setting-sources project --settings
<file>` from inside the scratch project dir, timing the whole invocation.
