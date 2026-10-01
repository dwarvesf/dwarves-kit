# Proof of done: flick, the fast decision CLI

Verdict: PASS for behavior; the 50 ms overhead target is NOT met on the build host (see Latency). Live Jev call: SKIPPED (no token in the environment).

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | `backend = "none"` prints an empty answer, exits 0, changes no kit step | `tests/test-flick.sh` TASK-2: default config gives `backend_none`, zero stub requests | PASS |
| AC2 | Every failure path exits 0 with `answers` empty and a closed-set error | TASK-2 fuzz (nine garbage shapes), TASK-5 and TASK-6 failure matrix, EXIT trap | PASS |
| AC3 | A project `.kit.toml` carrying `[decide]` changes nothing | TASK-9: project file cannot switch the backend on or off, widen `allow_names`, or add `deny_words` | PASS |
| AC4 | Egress: only exact public kit names leave the host; denied text never reaches a body | TASK-4: foreign-cwd plant, 16 hit variants, slug rule, case-folded `deny_words`, mixed batch | PASS |
| AC5 | Caller `id` and `existing` never reach the provider or the log | TASK-3 and TASK-8 canary strings | PASS |
| AC6 | Token never on argv, in a body, in stdout, or in the log; hostile `.curlrc` and `FLICK_URL` have no effect | TASK-5 `ps` check during a slow call, canary `.curlrc` (proven live first), three evil URLs with zero requests | PASS |
| AC7 | Provider answers validated: exact id and choice key sets, sum within 0.03, unique argmax matching the stated choice | TASK-6: malformed, no answers, bad sum, tie, missing key, extra key, extra probability, wrong choice | PASS |
| AC8 | `grep -r flick hooks/` finds nothing | `tests/test-hooks.sh` pin, with a planted-reference control | PASS |
| AC9 | One call per wrap, shadow only, step 7b unchanged when the point is unset | `commands/wrap.md` paragraph; the test suite has no acting path | PASS (prose, reviewed) |
| AC10 | Overhead under 50 ms excluding network | measured below: about 1.0 to 1.1 s here, fixed process cost | NOT MET on this host |

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-flick.sh` | 0 | 152 passed, 0 failed |
| `/bin/bash tests/test-flick.sh` (bash 3.2) | 0 | 152 passed, 0 failed |
| `bash tests/test-bin-forwarders.sh` | 0 | 48 passed, `flick` in the census |
| `bash tests/test-config-registry.sh` | 0 | 59/59 |
| `bash tests/test-meta.sh` | 0 | 902/902, FEATURES.md fresh |
| `bash tests/test-hooks.sh` | 0 | 826/826 (includes the flick pin) |
| `bin/test-affected --base origin/master` | 1 | 41 selected: 11 pass, 24 cached, 6 fail. `test-gate-opt-out` and `test-gate-validate-round` (C12) fail identically on a clean `origin/master` export. `test-hooks`, `test-lanes-data`, `test-meta` and `test-wrap-land` hit the tool's 300 s cap under load and each passes run alone (826/826, EXIT 0, 902/902, EXIT 0) |

## Negative controls (tests/test-flick.sh only; the code file was restored by copying a saved file back)

| Mutation | Test that went red |
|----------|--------------------|
| Hit check changed from whole-name match to substring | `hit 'boar' is not an exact public name`, `allow_names adds an exact name only` |
| `-q` removed as curl's first argument | `the canary .curlrc had no effect on flick`, `source pin: -q is the first curl argument` |
| Tie accepted as a valid argmax | `stub tie: bad_probs` |

## Latency (flick's own overhead: wall time minus curl `time_total`, against the local stub, median of 9)

| Questions | Median overhead (ms) |
|---|---|
| 1 | 1002 |
| 5 | 1135 |
| 20 | 1112 |
| Floor: five bare spawns | 381 |

Fixed process cost, not batch size. Method, samples and the cut list are in `docs/implementation-notes/flick.md`.

## Live Jev call

Skipped: `JEV_API_TOKEN` was not set in the build environment. The request shape is the one in the spec's Grounding section and has not been confirmed against the live API in this build.

## Follow-up: `decide.jev_token_cmd` (second, root-only token source)

Scope: when the env var named by `jev_token_env` is empty, flick runs the configured command (no shell, no expansion, stdin `/dev/null`, stderr dropped, 10 s limit) and uses its stdout as the token. Tests live in the `token_cmd` section of `tests/test-flick.sh`, each written red first.

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-flick.sh` | 0 | 213 passed, 0 failed |
| `/bin/bash tests/test-flick.sh` (bash 3.2) | 0 | 213 passed, 0 failed |
| `bash tests/test-meta.sh` | 0 | 902/902 |
| `bash tests/test-hooks.sh` | 0 | 826/826 |
| `bash tests/test-config-registry.sh` | 1 | 58/59: AC10 (`ledger.location` is a real `kit_config_get_root` call site in flick and is not in the Root-only keys table). Fails identically on a clean export of the base commit; the gap is already noted in the registry's known gaps. |

| Mutation (code file restored by copying a saved file back) | Test that went red |
|------------------------------------------------------------|--------------------|
| Env no longer wins over the command | `env set: the env token is used`, `env set: the command never runs` |
| Command run through `eval "$cmd"` | glob argv count, no command substitution or semicolon ran, slow command cut off |
| Time limit removed | `a slow command: no_token`, `cut off at about 10 s` |
| Shape check skipped | quote, newline and trailing-newline command outputs, plus the env-token shape tests |

Not controlled: the stdin test. flick has already read its own stdin to EOF before the command runs, so removing `</dev/null` changes nothing observable; the redirect stays as defense in depth. Limit: the kill reaches the command and its direct children, not deeper descendants that hold the output pipe open.
