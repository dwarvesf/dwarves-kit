# Proof of done: gauntlet doorway round + runner-host config

Behavioral claims: (1) a gauntlet round runs headlessly end to end and persists
its record; (2) the runner-host knob resolves from kit.toml; (3) the round-1
revisions hold (tier1 green, lints clean, checker fix real).

## Recorded runs (gate format)

Command: RUN_OUT=... PROBE_CMD=... bash tests/gauntlet/cleanroom/run.sh user doorway
Exit: 0
Verdict: PASS (room built, probe ran 8m15s / 67 turns / $2.86, record persisted; probe-exit=0)

Command: bash docs/verification/gauntlet/2026-08-06-kit-user/round-1/room/checks/check-submission-user.sh <probe fixture>
Exit: 1
Verdict: RED in-room, diagnosed as harness defect F2; independently, bash lib/adopt.sh --check <fixture> Exit: 0 ("adopted"), so the probe's adoption was real

Command: KIT_CONFIG_ROOT=$PWD bash -c 'source lib/config/kit-config.sh && kit_config_get gauntlet.runner_host / gauntlet.probe_key_ref'
Exit: 0
Verdict: PASS (runner_host=local, key_ref=op://Toolkit/anthropic-api-key/credential; the first attempt without KIT_CONFIG_ROOT returned the default, proving the knob reads the file rather than a fallback)

Command: ssh <mini-host> 'colima start; docker info; docker run --rm curlimages/curl -o /dev/null -w %{http_code} https://api.anthropic.com/v1/models'
Exit: 0
Verdict: PASS (DOCKER-OK; 401 = endpoint reached from a Mini container, egress viable for remote rounds)

Command: bash tests/gauntlet/tier1.sh   (after the three round-1 revisions)
Exit: 0
Verdict: PASS (TIER1: GREEN)

Command: shellcheck -x tests/gauntlet/check-submission-user.sh tests/gauntlet/cleanroom/run.sh tests/gauntlet/cleanroom/run-remote.sh install.sh
Exit: 0 for the gauntlet scripts; install.sh reports one PRE-EXISTING SC2034 (unused KIT_MARKER), untouched by this branch
Verdict: PASS

Command: grep -c 'sk-ant' <round-1 transcript>
Exit: 1 (no match)
Verdict: PASS (rule 8: no credential in the persisted record)

Rollback note: revisions are three small edits (install.sh prereq loop, checker
root resolution, staging exclusion) plus additive files (run-remote.sh, deploy
skeleton, the round record). Reverting the commits restores prior behavior;
no host state was changed except starting colima on the Mini (idempotent, and
`colima stop` reverses it).

## Known caveat

Rounds so far use the shared Toolkit Anthropic key, not a dedicated
spend-capped probe item (B7). Mint the capped item before any unattended
scheduled campaign.
