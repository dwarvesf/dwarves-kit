# Verification -- retire the wavefront and pane-viewer suites

`tests/test-orchestrate-wavefront.sh` and `tests/test-pane-viewer.sh` are removed. Both hit the 300s per-suite ceiling in the 2026-09-16 test-value audit (`docs/test-value-audit.md`), under the 4-way parallel pass and again standalone on an otherwise idle Air. The wavefront suite's header states that its barrier flakes under load; pane-viewer is fully mocked (VIEWER_CMD, TMUX_CMD) and hangs anyway, which is a harness fault, not a slow test. The operator chose retirement over repair.

Coverage that remains: wave scheduling through `test-orchestrate.sh` and `test-orchestrate-hardening.sh`; the pane viewer through `test-subagent-panes.sh` and `test-multiplexer.sh`, which use the same mocked fixture shape. Board row ID-834 (the wavefront flake) is flipped to dropped in the same commit.

## Green run

```
Command: bash tests/run-all.sh
Output: run-all: --changed against 8561cb7: 3 changed files -> 6 suites (1 named, the rest always-on)
        run-all: all 6 suites passed, 0 skipped for missing tooling
Exit: 0
Wall clock: 53s
Verdict: PASS
```

`docs/FEATURES.md` regenerated for the removed suites; `test-meta` (in the always-on set above) confirms the registry pin holds.

## Negative control

The control is the suites themselves, run standalone with the files restored, as the audit agent did this session after the parallel pass:

```
Command: timeout 300 bash tests/test-orchestrate-wavefront.sh   (files restored from 8561cb7, idle box)
Exit: 124
Command: timeout 300 bash tests/test-pane-viewer.sh              (files restored from 8561cb7, idle box)
Exit: 124
Verdict: RED both times, the same result as under parallel load, so the ceiling hit is the suite, not contention
```

Restoring the two files reintroduces two 300s timeouts to every full glob; removing them takes the glob from about 1950s to about 1350s and changes nothing in the bare run, which never picked either.

## Not proven

- Whether the pane-viewer hang is a bug in `lib/` code the retired suite alone exercised. The remaining pane suites are green, which bounds the risk but does not close it.
- Wave concurrency under real load. The retired suite was the only one that tried to prove it, and it could not do so reliably.
