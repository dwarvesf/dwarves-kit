# Proof of done: ship-clean battery follow-ups

Date: 2026-09-01. Branch: fix/ship-clean-followups. Source: first cold /kit:battery run on merged #463.

## Recorded run

- Command: `bash -n tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 0
- Command: `shellcheck -S warning tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 0; clean
- Command: `grep -c 'gauntlet.probe_key_ref' tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 0; Output: `3` (the empty-key error now names the config key)
- Command: `grep -c 'op://Toolkit\|colima' tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 1; Output: `0` (no personal leak reintroduced)
- Verdict: PASS

## Negative control

The change is one error-message string plus a spec correction; the only behavioral surface is the empty-key branch's message. Pre-fix that branch printed "check the host's 1P session" (named no config key); post-fix it names `gauntlet.probe_key_ref` + `kit.toml`. The branch is reached only when the key resolves empty, which the grep confirms now routes the operator to the right knob. The runner_host=local exec path (line 36) is untouched, so no round path changed behavior.

## Rollback

Single-hunk message revert + spec text; no logic, no state.
