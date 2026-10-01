# Spec: flick, a fast decision CLI for kit steps
Generated: 2026-10-01
Status: DRAFT
Lane: full (external provider, new component, egress)
Depth: research (outside: the OpenAI Decisions API shape is preview-only and unpublished)
References: `docs/research/2026-09-23-jev-absorption.md` (never-use list and "Security / trust screens" bind this spec); `lib/config/kit-config.sh` `kit_config_get_root` (root-only read to imitate); `lib/telemetry/kit-log-dir.sh` (log dir resolver to reuse); `bin/spec` and `lib/spec/spec.sh` (the `<subsystem> <verb>` forwarder shape to match)

## Problem
A kit step that needs a "pick one of N" judgment pays 20 to 60 s for an in-session model call. A decision API answers in about 0.5 s. The kit cannot yet measure whether an API decider matches the in-session judgment, so the swap is untested. A script with no interpreter start and one network call per batch reaches sub-second.

## Contract
`flick` reads JSON on stdin and writes one JSON object on stdout. It always exits 0.

```
stdin : {"point":"wrap-7b","questions":[{"id":"q1","question":"...","choices":["covers","partial","unrelated"],"context":"","existing":"partial"}]}
stdout: {"backend":"jev","model":"jev-1.13.0","latency_ms":412,"mode":"shadow",
         "answers":{"q1":{"choice":"covers","probs":{"covers":0.7,"partial":0.2,"unrelated":0.1},"margin":0.5}},"error":""}
```

- `existing` is optional. In shadow mode the caller passes its own choice so the log can pair the two.
- Fail-open: any failure prints `"answers":{}` and a reason in `error`, exit 0. The caller keeps its current path. A refused question gets `answers.<id> = {"choice":"","error":"<reason>"}` and the others still run.
- `error` is a closed set: `backend_none`, `missing_dep`, `no_token`, `timeout`, `http_<status>`, `network`, `malformed`, `bad_probs`, `egress_denied`, `point_disabled`, `bad_input`, `unsupported`.
- Config, read root-only with `kit_config_get_root` (operator file or kit root, never a project `.kit.toml`, because the block names a credential source and authorizes egress). The kit reader handles single-line scalars, so lists are space-separated strings, as in `wrap.build_lanes`:

| Key | Default | Meaning |
|---|---|---|
| `decide.backend` | `"none"` | `jev`, `openai`, or `none`. `none` leaves kit behaviour unchanged |
| `decide.jev_model`, `decide.openai_model` | `jev-1.13.0`, `""` | Pinned, never a `latest` alias |
| `decide.timeout_ms` | `1500` | Floor 1500: lower values clamp up (research doc screen) |
| `decide.mode` | `"shadow"` | `shadow` logs beside the existing decision and never acts. `decide` returns the answer for the caller to use |
| `decide.points` | `""` | Space-separated enabled decision points. Empty means nothing leaves the host |
| `decide.jev_token_env`, `decide.openai_token_env` | `JEV_API_TOKEN`, `OPENAI_API_KEY` | Env var NAME only. The token never sits in a file, argv, a log, or stdout |
| `decide.allow_names` | `""` | Extra public tool names the egress guard accepts |

## Picture
```
 /kit:wrap 7b --(decide.points has wrap-7b?)--> no: unchanged, flick never runs
       | yes
       v
  bin/flick --> lib/decide/flick.sh   (command layer; hooks/ never call it)
       | reads [decide] root-only; backend none / no curl / no jq -> empty answer, exit 0
       v
  egress guard --denied--> log line, no request
       | allowed
       v
  jq builds ONE body for the batch --> curl --max-time, HTTP/2 if supported --> provider
       |   token: curl config on stdin, never argv
       v  jq validates probs sum ~1, choice == argmax, margin
  stdout JSON  +  <log dir>/decide.jsonl line (no question text, no token)
```

## Design
**Layout.** `lib/decide/flick.sh` is the engine and owns the verbs (`flick decide`, `flick --help`). `bin/flick` is the stable forwarder, the same shape as `bin/spec`. Bash 3.2 safe. Dependencies are `curl` and `jq` only. A missing one gives `missing_dep`. No compiled code, no build step.

**JSON and secrets.** Every JSON value is built with `jq -n --arg` or `--argjson`, never string concatenation. The batch body goes to a `mktemp` file (it holds no secret) sent with `--data-binary @file`. The token reaches curl through `curl --config -` on stdin: `printf 'header = "Authorization: Bearer %s"\n' "$TOKEN"` with `printf` as a builtin, so `ps` never shows it. The URL is fixed per backend. `FLICK_URL` overrides it only when the host is `127.0.0.1` or `localhost`, for the test stub; any other host is ignored.

**Request.** One `curl` call per batch, `--max-time` from `timeout_ms` (floor 1500), `--http2` when `curl -V` lists HTTP2, and the HTTP status is read with `-w '%{http_code}'`. Timestamps use `perl -MTime::HiRes` with a whole-second `date` fallback.

**Backends.** Jev takes many questions in one request (a `questions` object keyed by id, each a `choice` with `criteria` as a choice-to-description dict and `instructions` as the question), so a batch is one call. The state field is a fixed per-point preamble, because all questions of a request share it. The OpenAI backend is a stub: it returns `unsupported` and sends nothing until OpenAI publishes the Decisions API request shape. No assumed shape is coded.

**Validation (jq).** Each answer needs a probability per choice, a sum within 0.03 of 1, and a choice equal to the argmax. `margin` is top minus second. Callers and the log see the distribution and margin, never the provider's single `confidence` field (it scored 0.66 on gibberish in a shipped integration, per the research doc).

**Egress guard.** A point is a closed entry in `flick.sh`: a question regex, a fixed choice set, the allowed modes, and a rule that `context` is empty. `wrap-7b` allows only `Does the existing tool <A> cover the job of <B>?` with the choices `covers`, `partial`, `unrelated`. A token `<A>` or `<B>` passes only when it is a public name: a basename under this repo's `bin/`, `commands/`, `skills/` or `agents/`, or listed in `decide.allow_names`. Anything else is `egress_denied`, nothing is sent, and the log records the denial without the text. A new point needs its own spec.

**Never-use.** The never-use list in `docs/research/2026-09-23-jev-absorption.md` ("Where Jev must NOT be used") applies to every backend by reference: no fail-closed gate (ship-gate, secret-guard, safety or money gates), no client, NDA, family or secret text. The registry has no point for any of them. flick is a command-layer tool called from `commands/wrap.md` in shadow mode. It is not a hook, so "No LLM API calls in v1 hooks" is untouched, and a test fails if anything under `hooks/` references it.

**Mode.** `wrap-7b` supports `shadow` only. With `mode = "decide"` it runs as shadow and the log records `mode_downgraded`. Nothing here writes a decision into a live gate.

**Decision log.** One JSON line per question in `$(kit_resolve_log_dir)/decide.jsonl`: `ts, backend, model, point, id, latency_ms, net_ms, chosen, existing, margin, error, mode`. No question text, no token. A log write failure never changes the answer.

**`/kit:wrap` step 7b.** After the session has judged a precedent hit, and only when `kit_config_get_root decide.points` lists `wrap-7b`, wrap pipes each (candidate, hit) pair to `bin/flick` with `existing` set to its own verdict and ignores the answer except for one FYI `STATE` row naming the backend and call count. When the point is absent, step 7b is byte-for-byte today's behaviour and `bin/flick` never runs.

## Task Breakdown
### Phase 1: Foundation
- [ ] TASK-1: `lib/decide/flick.sh` skeleton plus `bin/flick` forwarder: stdin parse, stdout contract, closed error set, always exit 0, `missing_dep`, `backend_none`. Done when `bash tests/test-flick.sh` passes the bad-input, backend-none and missing-dep cases, and `tests/test-bin-forwarders.sh` lists `flick`.
- [ ] TASK-2: Egress guard with the `wrap-7b` point and the public-name allowlist. Done when a client-style name, a non-empty `context`, and a free-text question each return `egress_denied` with zero requests to the stub.
### Phase 2: Core
- [ ] TASK-3: Jev backend: `jq -n` body, one `curl` per batch, token via curl config on stdin, validation and margin. Done when the stub tests cover happy path, a 3-question batch in one request, timeout, 401, 5xx, malformed JSON, and probabilities off by more than 0.03.
- [ ] TASK-4: OpenAI stub returning `unsupported`. Done when a test with `backend = "openai"` gets `unsupported` and the stub saw zero requests.
- [ ] TASK-5: Decision log. Done when a test greps the log, stdout and the process list during a slow stub call for the test token and a question string and finds none.
- [ ] TASK-6: `[decide]` block in `kit.toml` with status tags, install and plugin packaging for `lib/decide/` and `bin/flick`, `tool.toml` and FEATURES entry. Done when a project `.kit.toml` carrying `[decide]` is ignored and `bash tests/test-meta.sh` passes.
### Phase 3: Polish
- [ ] TASK-7: `commands/wrap.md` step 7b paragraph for `wrap-7b`, with the "absent means unchanged" sentence, and a test that `hooks/` never references flick. Done when the wrap lint passes with the key unset and set.
- [ ] TASK-8: Latency table of flick's own overhead (wall time minus curl `time_total`) against the stub for 1, 5 and 20 questions, in `docs/implementation-notes/flick.md`, plus one live Jev call when the token env var is set, skipped otherwise. Done when the table holds measured numbers with overhead under 50 ms.

## After state
- [ ] `bin/flick` with `decide.backend = "none"` prints an empty answer and exits 0, and no step of any kit command changes. (Today: no decision CLI exists.)
- [ ] With `backend = "jev"`, `points = "wrap-7b"` and a token, a public-name question returns a validated answer in under 1 s and appends one line to `decide.jsonl`. (Today: step 7b judges in-session, 20 to 60 s.)
- [ ] A project `.kit.toml` carrying `[decide]` changes nothing, checked by `bash tests/test-flick.sh`.
- [ ] Every failure path in the closed error set exits 0 with `answers` empty.
- [ ] `grep -r flick hooks/` finds nothing.

## Acceptance Criteria (global)
- [ ] All tasks pass their own criteria; no regression in `bash tests/run-all.sh`
- [ ] No token, question text, or private name appears in any committed file or log fixture

## Verification
`bash tests/test-flick.sh && bash tests/test-bin-forwarders.sh && bash tests/test-meta.sh && bash tests/run-all.sh`. The test starts `tests/lib/flick-stub.py` (test-only, python3, one file) on a free local port and points `FLICK_URL` at it; the suite prints `SKIP: <why>` when `curl`, `jq` or `python3` is missing. The live Jev call runs only when the token env var is set and prints `SKIP: no token` otherwise. Negative control: loosen the `wrap-7b` question check to accept any text, and the egress-denied test must go red.

## Grounding
- **Jev request/response shape** (sampled from a private evaluation harness's code, not a live call; shape only, no token): POST `https://api.typesafe.ai/v1/systemone`, header `Authorization: Bearer <env token>`, body `{"model":"jev-1.13.0","state":"<text>","questions":{"<id>":{"type":"choice","criteria":{"<choice>":"<description>"},"instructions":"<question>"}}}`. Response `{"answers":{"<id>":{"type":"choice","choice":"<choice>","probabilities":{"<choice>":0.9}}}}`. `criteria` must be a dict; a list returns HTTP 422. The harness measured p50 0.50 s and p95 0.69 s. A live sample for this spec is unavailable until TASK-8 runs with a token.
- **OpenAI Decisions API:** limited preview, request shape unpublished. Not sampleable, so no adapter is coded.
- **Host cost** (measured on the build host): Python start-up 0.22 to 0.38 s and a TLS handshake 0.23 to 0.49 s, which rules out a Python client. A bash plus `curl` plus `jq` run measured about 30 ms of start-up against about 5 ms for a compiled binary, under 10% of a 300+ ms call.
- **Tools on runners:** `.github/workflows/test.yml` runs only on `workflow_dispatch` and `v*` tags, on `ubuntu-latest` and `macos-latest`. Those images are believed to ship `curl`, `jq` and `python3`, unverified here. The test skips with a printed reason when any is missing. This spec adds no workflow, no runner, no hosted spend. The local `bash tests/run-all.sh` is the check.
- **Local curl:** 8.7.1 with nghttp2, so `curl -V` lists HTTP2 here. The stub is plain HTTP, so its latency excludes TLS and HTTP/2. Only the live call measures those.
- **Negative-control dry trace:** mutation = make the `wrap-7b` question check accept `.*`. The egress test sends a question holding a non-public name, expects `egress_denied` and a stub request count of 0, and goes red because the count is 1.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Provider outage or auth failure | `http_5xx`, `http_401`, `timeout` in `error` | Empty answer, exit 0, caller keeps its path |
| Overconfident wrong answer | shadow log: `chosen` differs from `existing` at high margin | Stays shadow. No act path exists for `wrap-7b` |
| Private name leaves the host | none by design | Allowlist is deny-by-default and public-name only; the log stores no text |
| Token visible to `ps` or logs | TASK-5 test | Curl config on stdin, env var name only, no token in any log line |
| Hand-built JSON breaks on a quote | malformed stub case | `jq -n --arg` for every value, never concatenation |
| `FLICK_URL` redirects egress | test case | Honored only for `127.0.0.1` and `localhost` |
| Project PR sets `[decide]` | test case | Root-only read ignores it |
| Provider drifts from the pinned model | `model` in the log differs from the pin | Pin in config; drift shows in the log, never silently |

## Out of Scope
- Any hook, fail-closed gate, or hot path calling flick.
- Acting on an answer (`decide` mode for any real point). Phase 3 compares logs, then a later spec decides.
- A second decision point. Each one needs a spec.
- Any compiled component, and an OpenAI request shape before OpenAI publishes one.

## Touches
- lib/decide/**
- bin/**
- tests/**

## Decision Log
- DEC-1: Name `flick` for the tool; the kit.toml block stays `[decide]`. The block names the capability and two backends sit behind it, so a backend or the implementation can change without a config rename.
- DEC-2: bash + curl + jq over Go or Rust. PHILOSOPHY says "No compiled binaries". Measured start-up is about 30 ms against about 5 ms, under 10% of a 300+ ms call, and there is no build step. Revisit only if start-up ever dominates.
- DEC-3: flick is a command-layer tool called from `commands/wrap.md` in shadow mode, not a hook. "No LLM API calls in v1 hooks" is untouched, and it must never be called from `hooks/` (a test enforces it).
- DEC-4: Egress is deny-by-default by public-name allowlist, not a regex over text. A regex passes a client-named script. Cost: low shadow coverage until `allow_names` grows.
- DEC-5: The OpenAI backend ships as an `unsupported` stub. An assumed request shape would be a guess dressed as code.
- DEC-6: Timeout floor 1500 ms, from the research doc's screens, even though the call is meant to be sub-second.
- DEC-7: Config lists are space-separated strings and token env names are flat keys, because the kit's TOML reader returns single-line scalars.
- DEC-8: `FLICK_URL` exists for the test stub only and is ignored for any non-local host. The test stub is a one-file python3 script under `tests/lib/`, test-only.

## Open questions
(none)
