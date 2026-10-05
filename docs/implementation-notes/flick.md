# Impl notes: flick (SPEC-381)

Delta from the spec. Only off-spec calls and review warnings live here. The builder reads this before TASK-1.

## Warnings from validation round 1 (tests or the builder catch these)

| Warning | Call |
|---|---|
| Log rotation | `decide.jsonl` is append-only and unrotated. One line per question and one call per wrap keeps growth small. Add rotation when the file passes a size the operator notices. |
| Token rotation or expiry | A rotated or expired token shows as repeated `http_401` in the log. Add a count of consecutive `http_401` to the wrap FYI row only if it happens. |
| Recorded live Jev sample | The spec has no live sample. When a token exists, TASK-12 records one real response (probabilities only, no token) in this file and compares it with the Grounding shape. |
| Runner tool availability | `curl`, `jq` and `python3` on the hosted images are believed present and unverified. The test skips with a printed reason when one is missing. No workflow change. |
| Approaches considered | Two alternatives were not built. A Haiku subagent arm would answer in seconds at a small cost and needs no egress, so it is the fair comparison arm for the shadow log. Doing nothing keeps the 20 to 60 s judgment. The operator chose the API path to measure it. |
| `mode = "decide"` has no consumer | `wrap-7b` runs as shadow only, so `decide` mode returns answers nothing reads. It exists for a later point. |

## Builder notes from the second fold-diff check

| Note | What the build did |
|---|---|
| `counts` for `missing_dep`, `point_disabled`, `network` | Every post-parse whole-call failure counts each non-denied question as `error`. Tests pin `missing_dep` (curl absent), `point_disabled`, `network` (connection refused), `no_token`, `unsupported`, `timeout`, `http_*`, `malformed` and `bad_probs`. A run with no jq cannot parse, so it reports all zeros. |
| `flick body` ownership | TASK-2 owns the verb. The `jq -n` body builder landed with TASK-3, so TASK-3 and TASK-4 assert on `flick body` output. |
| "absent from the log" assertions | They run in the TASK-8 section, after the log exists. |
| Canary `.curlrc` | The test unsets `CURL_HOME` and `XDG_CONFIG_HOME`. It first proves the canary `trace` directive fires for a plain curl, so the later "no effect" check is not vacuous. |
| `flick body` with a token in the environment | One assertion: no token in the output and zero stub requests. |

## Entries

- Post-build review fold (see DEC-12): descriptions come from builtin reads (`first_comment`, `fm_description`), so a described hit adds no process spawn. When a description runs past 160 characters it ends at the last whole sentence that fits, else the last word. A denied log line gained a `reason` field. `FLICK_URL` without `FLICK_TEST=1` is ignored, not `bad_input`, so a stray variable cannot break production calls; the test pins that with a dead HTTPS proxy so nothing leaves the host. The ps-in-flight test now polls for curl instead of sleeping 1 s, because curl starts late on a slow host.

- Deviation: config is read in one builtin pass (`load_decide_block`) instead of ten `kit_config_get_root` calls. A process spawn costs several milliseconds on a hardened macOS host, and ten awk runs would break the overhead budget. It follows the same rules as `_kit_toml_get` (section header, `#` comments, one quote layer, first match wins, empty is unset) and reads only the operator file, then the kit-root file, never the project `.kit.toml`. A test pins that.
- Deviation: the log carries `mode_downgraded` (true when `decide.mode` is `decide`) as its own field, while `mode` stays `shadow`.
- Deviation: `decide.timeout_ms` also clamps at 10000, so a typo cannot hang a wrap. The spec set only the floor.
- The Jev request shape comes from the spec's Grounding (a harness's code), not a live call.

## Latency (TASK-12): flick's own overhead against the local stub

Method: wall time of `env -i ... bin/flick decide` minus curl `time_total` (the `latency_ms` field), median of 9 runs per row, stub on loopback over plain HTTP (no TLS, no HTTP/2). Host: a hardened macOS laptop where a bare process spawn is slow and noisy (`env -i bash -c :` 130 to 160 ms, `curl --version` 35 to 220 ms, `jq -n 1` 10 to 90 ms), measured while other suites ran.

| Questions per batch | Median overhead | Samples (ms) |
|---|---|---|
| 1 | 1002 | 665 1002 1070 984 969 893 1382 1153 1145 |
| 5 | 1135 | 1135 1406 1058 1259 1181 869 1104 1158 953 |
| 20 | 1112 | 1056 1198 1112 858 1049 1169 1022 1218 1346 |
| Floor: three `jq`, one `curl --version`, one `bash -c :` back to back | 381 | 440 577 89 258 681 381 299 328 424 |

Result: the spec's target of under 50 ms is NOT met on this host. Overhead does not grow with batch size, so it is fixed process cost: an interpreter start, three `jq` runs (parse, body, final), one `curl`, the log-dir resolver, and several `$(...)` forks. The floor row shows the host spends roughly 380 ms on five bare spawns, so about 60 ms per exec at the median here against a few ms on an ordinary machine. One call is still about 1.5 s end to end with a 0.5 s provider answer, against 20 to 60 s for the in-session judgment. Cuts already made: one `jq` for the envelope and the log together, one builtin config pass instead of ten `awk` runs, the forwarder `exec`s the engine directly. If the fixed cost matters once the shadow log shows value, the next cut is folding the parse and body `jq` passes into one and skipping the log-dir resolver's config reads when the ledger env var is set.

Live Jev call: SKIPPED. `JEV_API_TOKEN` was not set in the build environment, so the request shape in the spec's Grounding is unconfirmed against the live API and no live latency exists. Run `bin/flick` with a token once to record one.

## Delta: the step 7b call became a verb (root cause of an empty shadow log)

Five days after shadow went live, `decide.jsonl` held only the 32 smoke rows from the build session. Evidence: of the wrap reports printed after `commands/wrap.md` gained the paragraph, none but the build session ran `bin/config get decide.points` or `bin/flick`, and none carried a `flick wrap-7b:` STATE row. Config was read correctly (`bin/config get decide.points` prints `wrap-7b`), the log path was right (the smoke rows landed there), and the plugin cache resolves to the live checkout, so the paragraph reached every session. The call was an optional-looking prose paragraph buried mid step 7b; sessions skipped it and nothing in the report showed the skip.

Fix: `bin/wrap flick-7b` (`lib/wrap/wrap-flick.sh`) is the one command step 7b runs. It reads the config, makes the single flick call and prints the STATE row. `report-lint.sh` fails a report with no `flick wrap-7b:` row while `decide.points` lists `wrap-7b`, so a skip is a visible finding at step 9. Tests: `tests/test-wrap-flick7b.sh` and the flick cases in `tests/test-wrap-report-lint.sh`.
