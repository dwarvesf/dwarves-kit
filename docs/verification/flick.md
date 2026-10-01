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
| `bash tests/test-flick.sh` | 0 | 237 passed, 0 failed |
| `/bin/bash tests/test-flick.sh` (bash 3.2) | 0 | 237 passed, 0 failed |
| `bash tests/test-meta.sh` | 0 | 902/902 |
| `bash tests/test-hooks.sh` | 0 | 826/826 |
| `bash tests/test-config-registry.sh` | 1 | 58/59: AC10 (`ledger.location` is a real `kit_config_get_root` call site in flick and is not in the Root-only keys table). Fails identically on a clean export of the base commit; the gap is already noted in the registry's known gaps. |

| Mutation (code file restored by copying a saved file back) | Test that went red |
|------------------------------------------------------------|--------------------|
| Env no longer wins over the command | `env set: the env token is used`, `env set: the command never runs` |
| Command run through `eval "$cmd"` | glob argv count, no command substitution or semicolon ran, slow command cut off |
| Time limit removed | `a slow command: no_token`, `cut off at about 10 s` |
| Shape check skipped | quote, newline and trailing-newline command outputs, plus the env-token shape tests |

Security-lens fixes, same section of `tests/test-flick.sh` (the TERM-ignoring test hung forever on the old code):

| Fix | Mutation that went red |
|-----|------------------------|
| Config variables moved to a private `FLKC_` namespace cleared before load (env `OP_*`, `RT_*`, `SEEN_*` no longer inject `points`, `deny_words`, `allow_names`, `backend`, `jev_token_cmd`) | Namespace not cleared: the private-prefix env test |
| TERM to the group, then KILL after a 1 s grace; never a blocking `wait` on a live command | KILL branch removed: the TERM-ignoring command hangs flick (alarm fired) |
| Output goes to a file in a 0700 temp dir, removed on every path; the group is killed before the read | Group kill removed: `the descendant was killed with its group` |
| Output capped (`ulimit -f` on the command, `head -c 4097` on the read, over 4096 is `no_token`) | Length check removed: `oversized command output (bigfinite)` |
| First word must be an absolute path | Rule removed: bare-name and relative-path tests |

Not controlled: the stdin test. flick has already read its own stdin to EOF before the command runs, so removing `</dev/null` changes nothing observable; the redirect stays as defense in depth. Limit: a descendant that calls `setsid` or `setpgid` leaves the command's process group and survives the kill.

## Follow-up: `decide.word_gate` and `decide.dict_file` (allow-by-dictionary egress rule)

Scope: each hyphen segment of a `wrap-7b` candidate must be a dictionary word (case-insensitive, whole line), a built-in dev word, or a kit-public name, else the question is `egress_denied` with log reason `word_gate`. A missing or unreadable dictionary denies every candidate (`word_gate_no_dict`). `deny_words` still applies on top. Both keys are root-only; the gate is on by default.

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-flick.sh` (bash 5) | 0 | 270 passed, 0 failed |
| `/bin/bash tests/test-flick.sh` (bash 3.2) | 0 | 270 passed, 0 failed |
| `bash tests/test-meta.sh` | 0 | 902/902 |
| `bash tests/test-hooks.sh` | 0 | 826/826 |

New section in `tests/test-flick.sh` ("word gate"), red before the engine change (23 failures on the old code): generic slug passes; a made-up segment is denied with zero stub requests, absent from `flick body`, logged as `word_gate`; dev words pass; a kit-public name and an `allow_names` entry pass as segments; missing dictionary file and a directory in its place deny every candidate (`word_gate_no_dict`); an empty dictionary denies; `word_gate = "off"` restores the old behaviour; an unrecognised value counts as on; a project `.kit.toml` cannot turn the gate off or swap the dictionary; a mixed batch keeps the allowed question and drops the denied one (renumbered, counts right, per-question log reason); case-insensitive match against a capitalized fixture word; `deny_words` still blocks a dictionary word; a 50-question batch uses exactly one dictionary pass (an `awk` shim counts calls); `---` is denied; one test against the host dictionary, skipped when `/usr/share/dict/words` is absent. All other tests use a fixture dictionary, and the older sections run with `word_gate = "off"` so they stay host-independent.

| Mutation (code file restored by copying a saved file back) | Test that went red |
|------------------------------------------------------------|--------------------|
| Gate disabled | made-up segment denied, absent from body, zero requests, log reason, mixed batch, 50-question batch (about 23 word-gate tests) |
| Missing dictionary falls open | both `dict_file` unusable cases, `allow_names` segment test |
| Match made case-sensitive | `dictionary match is case-insensitive` |
| Dev-word list emptied | `built-in dev words pass without being in the dictionary` |
| Public set ignored for segments | `a kit-public name segment passes`, `allow_names` segment test |
| Unrecognised value treated as off | `an unrecognised word_gate value is treated as on`, 50-question batch |
| Per-question log reason lost | `the log reason is word_gate`, both `word_gate_no_dict` log checks |
| Zero-word slug allowed | `a slug with no word at all is denied` |
| `LC_ALL=C` prefix put back on the `awk` call | `a kit-public name segment passes` (macOS `awk` exited 139 on about 1 run in 10, which reads as `word_gate_no_dict`); the 25-run repeat test catches it with high probability |

The mutations ran in eight parallel copies of the kit tree, not by editing the worktree. Extra red lines about leftover token temp dirs and process groups in those runs come from sharing `/tmp` and `pgrep` across parallel runs; the serial runs above are clean.

Measured cost on the build host (macOS, 236k-line system dictionary, `flick body`, 20 questions, mean of 10): about 70 ms with the gate off, about 160 to 210 ms with it on, so the gate adds roughly 80 to 140 ms. The first design, one `grep -Fixf` pass, took over 500 ms on BSD grep, so the engine reads the dictionary with one `awk` pass. The 20 ms target is NOT met on macOS; on this host a bare process spawn already costs about 14 ms. A `look` binary-search fast path would fit the budget but needs a sorted dictionary file.
