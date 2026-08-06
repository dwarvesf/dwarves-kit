# Proof of done: gauntlet rounds 2-3, remote runner, doorway SOLID

Behavioral claims: the remote runner executes a full round on another host,
and the kit's doorway contributor surface passes the gauntlet twice, unaided.

## Recorded runs (gate format)

Command: GAUNTLET_RUNNER_HOST=mini-tieubao bash tests/gauntlet/cleanroom/run-remote.sh user doorway <round-2 out>
Exit: 0
Verdict: PASS (room built on the Mini, probe ran headless, record pulled back)

Command: KIT_ROOT=$PWD bash <round-2>/checks/check-submission-user.sh <round-2 fixture>
Exit: 0
Verdict: PASS (SUBMISSION: GREEN, 6/6)

Command: GAUNTLET_RUNNER_HOST=mini-tieubao bash tests/gauntlet/cleanroom/run-remote.sh user doorway <round-3 out>
Exit: 0
Verdict: PASS

Command: KIT_ROOT=$PWD bash <round-3>/checks/check-submission-user.sh <round-3 fixture>
Exit: 0
Verdict: PASS (SUBMISSION: GREEN, 6/6) -- two consecutive clean passes, rule 9 satisfied

Command: PROBE_CMD='<mixed-quote probe>' RUN_OUT=/tmp/gauntlet-prompttest bash tests/gauntlet/cleanroom/run.sh user doorway
Exit: 0
Verdict: PASS (negative-control style check for the quoting class: a prompt with an apostrophe reaches the room intact, 29 words)

Command: grep -c 'sk-ant' <round-2 transcript> ; same for round 3
Exit: 1 (no match), both
Verdict: PASS (rule 8: no credential in either persisted record)

Command: bash tests/gauntlet/tier1.sh
Exit: 0
Verdict: PASS (TIER1: GREEN)

Rollback note: changes are five harness fixes to two runner scripts plus
additive round records. Reverting the commits restores the prior runner; the
only host state touched is a colima instance on the Mini (idempotent; `colima
stop` reverses it) and per-round workdirs under ~/.cache/kit-gauntlet.

## Caveat

Rounds used the shared Toolkit Anthropic key, not a dedicated spend-capped
probe item; mint that before any unattended scheduled campaign.

## Negative controls (the GREEN can go RED)

Command: KIT_ROOT=$PWD bash <round-3>/checks/check-submission-user.sh <bare git init dir>
Exit: 1
Verdict: PASS as negative control (SUBMISSION: RED; the checker is not vacuously green)

Command: cp the ROUND-3 GREEN fixture, remove PR.md only, re-run the same checker
Exit: 1
Verdict: PASS as negative control (SUBMISSION: RED; removing one required artifact from a passing submission flips it, so the GREEN verdict tracks the probe's actual work)
