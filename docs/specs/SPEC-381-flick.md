# Spec: flick, a fast decision CLI for kit steps
Generated: 2026-10-01
Status: DRAFT
Lane: full (external provider, new component, egress)
Depth: research (outside: the OpenAI Decisions API shape is preview-only and unpublished)
References: `docs/research/2026-09-23-jev-absorption.md` (never-use list and "Security / trust screens" bind this spec); `lib/config/kit-config.sh` `kit_config_get_root` (root-only read to imitate); `lib/telemetry/kit-log-dir.sh` (log dir resolver to reuse)

## Problem
A kit step that needs a "pick one of N" judgment pays 20 to 60 s for an in-session model call. Decision APIs answer in about 0.5 s. A Python client loses 0.22 to 0.38 s to interpreter start and 0.23 to 0.49 s to a TLS handshake before the first byte, so a script cannot reach sub-second. The kit has no way to measure whether an API decider matches the in-session judgment, so the swap is untested.

## Contract
`flick` reads JSON on stdin and writes one JSON object on stdout. It always exits 0.

```
stdin : {"point":"wrap-7b","questions":[{"id":"q1","question":"...","choices":["covers","partial","unrelated"],"context":"","existing":"partial"}]}
stdout: {"backend":"jev","model":"jev-1.13.0","latency_ms":412,"mode":"shadow",
         "answers":{"q1":{"choice":"covers","probs":{"covers":0.7,"partial":0.2,"unrelated":0.1},"margin":0.5}},"error":""}
```

- `existing` is optional. In shadow mode the caller passes its own choice so the log can pair the two.
- Fail-open: any failure prints `"answers":{}` and a reason in `error`, exit 0. The caller keeps its current path. A refused question gets `answers.<id> = {"choice":"","error":"<reason>"}` and the others still run.
- `error` is a closed set: `backend_none`, `no_go`, `no_binary`, `build_failed`, `no_token`, `timeout`, `http_<status>`, `network`, `malformed`, `bad_probs`, `egress_denied`, `point_disabled`, `bad_input`, `unsupported`.
- Config, read root-only with `kit_config_get_root` (operator file or kit root, never a project `.kit.toml`, because the block names a credential source and authorizes egress):

| Key | Default | Meaning |
|---|---|---|
| `decide.backend` | `"none"` | `jev`, `openai`, or `none`. `none` leaves kit behaviour unchanged |
| `decide.model` | per backend | Pinned, never a `latest` alias. Jev default `jev-1.13.0` |
| `decide.timeout_ms` | `1500` | Floor 1500: lower values clamp up (research doc screen) |
| `decide.mode` | `"shadow"` | `shadow` logs beside the existing decision and never acts. `decide` returns the answer for the caller to use |
| `decide.points` | `[]` | Enabled decision points. Empty means nothing leaves the host |
| `decide.token_env.<backend>` | `JEV_API_TOKEN`, `OPENAI_API_KEY` | Env var NAME only. The token never sits in a file, argv, a log, or stdout |
| `decide.allow_names` | `[]` | Extra public tool names the egress guard accepts |

## Picture
```
 /kit:wrap 7b --(decide.points has wrap-7b?)--> no: unchanged, nothing runs
       | yes
       v
  bin/flick (bash) --reads [decide] root-only--> flags + env var NAME
       | cached binary for source hash?   no Go / no binary / backend none -> empty answer, exit 0
       v
  flick (Go) --egress guard--> denied: log, no request
       | allowed
       v
  Backend{jev | openai} --one HTTP/2 request, all questions--> provider
       | validate probs sum ~1, choice == argmax, compute margin
       v
  stdout JSON  +  <log dir>/decide.jsonl line (no question text, no token)
```

## Design
**Layout.** `cmd/flick/` holds a stdlib-only Go module (`go.mod`, no dependencies): `main.go` (I/O contract, fail-open), `egress.go` (points and allowlist), `backend.go` (interface), `jev.go`, `openai.go`, `log.go`, and `_test.go` files. `bin/flick` is the bash wrapper, bash 3.2 safe. The repo has no Go today, so this adds the first compiled component.

**Wrapper.** It reads `[decide]` through `lib/config/kit-config.sh`, exits with `backend_none` when the backend is `none`, and passes values to the binary as flags (the token env NAME, never its value). The binary lives in `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/bin/flick-<sourcehash>`, the same XDG root as the run logs. Source hash is `shasum` over `cmd/flick/`. On a miss with Go present, the wrapper starts a locked background `go build` and answers `no_binary` now, so a call never blocks on a compile. `bin/flick build` builds in the foreground for install and tests. No Go means `no_go`.

**Backends.** Both implement `Decide(ctx, []Question) (map[id]Answer, error)`. Jev takes many questions in one request (a `questions` object keyed by id, each a `choice` with `criteria` as a choice-to-description dict and `instructions` as the question), so a batch is one call. The state field is a fixed per-point preamble, because all questions of a request share it. The OpenAI backend ships as the same interface with an adapter written against an assumed shape. Until a key and a real sample exist, its answers that do not parse return `malformed`. Backends with no batch API get concurrent requests over one `http.Client`.

**Validation.** The answer must carry a probability per choice, the sum must be within 0.03 of 1, and the choice must be the argmax. `margin` is top minus second. The log and the caller see the distribution and margin, never the provider's single `confidence` field (it scored 0.66 on gibberish in a shipped integration, per the research doc).

**Egress guard.** A point is a closed Go registry entry: a question regex, a fixed choice set, the allowed modes, and a rule that `context` is empty. `wrap-7b` allows only `Does the existing tool <A> cover the job of <B>?` with `<A>` and `<B>` as tool-name tokens, and the choices `covers`, `partial`, `unrelated`. A token passes only when it is a public name: a basename under this repo's `bin/`, `commands/`, `skills/` or `agents/`, or listed in `decide.allow_names`. Anything else is `egress_denied`, nothing is sent, and the log records the denial without the text. A new point needs its own spec. Hooks never call flick (hook budget, and the no-runtime-config-read lint).

**Never-use.** The never-use list in `docs/research/2026-09-23-jev-absorption.md` ("Where Jev must NOT be used") applies to every backend by reference. No fail-closed gate (ship-gate, secret-guard, safety or money gates), no client, NDA, family or secret text. The registry has no point for any of them.

**Mode.** `wrap-7b` supports `shadow` only. With `mode = "decide"` it runs as shadow and the log records `mode_downgraded`. Nothing here writes a decision into a live gate.

**Decision log.** One JSON line per question in `$(kit_resolve_log_dir)/decide.jsonl`: `ts, backend, model, point, id, latency_ms, chosen, existing, margin, error, mode`. No question text, no token. A log write failure never changes the answer.

**`/kit:wrap` step 7b.** After the session has judged a precedent hit, and only when `kit_config_get_root decide.points` lists `wrap-7b`, wrap pipes each (candidate, hit) pair to `bin/flick` with `existing` set to its own verdict (`covers`, `partial`, or `unrelated`) and ignores the answer except for one FYI `STATE` row naming the backend and call count. When the point is absent, step 7b is byte-for-byte today's behaviour and `bin/flick` never runs.

## Task Breakdown
### Phase 1: Foundation
- [ ] TASK-1: ADR in `docs/decisions/` plus a named carve-out in `docs/PHILOSOPHY.md` hard limits ("No compiled binaries", "No LLM API calls"): optional module, source ships, binary is a local cache, never in a hook. Done when both files cite each other and `bash tests/test-meta.sh` passes.
- [ ] TASK-2: `cmd/flick/` module with `main.go`: stdin parse, stdout contract, closed error set, always-exit-0. Done when `go test ./...` passes the bad-input and empty-stdin cases.
- [ ] TASK-3: `egress.go` point registry with `wrap-7b` and the public-name allowlist. Done when a client-style token, a non-empty `context`, and a free-text question each return `egress_denied` with zero requests to the stub.
### Phase 2: Core
- [ ] TASK-4: `jev.go` batched request, response validation, margin. Done when the stub tests cover happy path, a 3-question batch in one request, timeout, 401, 5xx, malformed JSON, and probabilities off by more than 0.03.
- [ ] TASK-5: `openai.go` behind the same interface, concurrent-over-one-client fallback, same failure tests against an assumed-shape stub. Done when each failure maps to the closed error set.
- [ ] TASK-6: `log.go` decision log. Done when a test greps the log and stdout for the stub token and a question string and finds neither.
- [ ] TASK-7: `bin/flick` wrapper: config read, source-hash cache, background build, fail-open. Done when `tests/test-flick-wrapper.sh` covers no Go, no binary, no token, backend `none`, and a project `.kit.toml` with `[decide]` being ignored.
- [ ] TASK-8: `[decide]` block in `kit.toml` with status tags, `install.sh` and plugin packaging carrying `cmd/flick/`, `tool.toml`/FEATURES entry. Done when `bash tests/test-meta.sh` and `bash tests/test-bin-forwarders.sh` pass.
### Phase 3: Polish
- [ ] TASK-9: `commands/wrap.md` step 7b paragraph for `wrap-7b`, with the "absent means unchanged" sentence. Done when the wrap lint passes with the key unset and set.
- [ ] TASK-10: latency table against the stub (process start, 1/5/20 questions) in `docs/implementation-notes/flick.md`, plus one live Jev call when the token env var is set at build time, skipped otherwise. Done when the table holds real measured numbers.

## After state
- [ ] `bin/flick` with `decide.backend = "none"` prints an empty answer and exits 0, and no step of any kit command changes. (Today: no decision CLI exists.)
- [ ] With `backend = "jev"`, `points = ["wrap-7b"]` and a token, a public-name question returns a validated answer in under 1 s and appends one line to `decide.jsonl`. (Today: step 7b judges in-session, 20 to 60 s.)
- [ ] A project `.kit.toml` carrying `[decide]` changes nothing, checked by `tests/test-flick-wrapper.sh`.
- [ ] Every failure path in the closed error set exits 0 with `answers` empty.

## Acceptance Criteria (global)
- [ ] All tasks pass their own criteria; no regression in `bash tests/run-all.sh`
- [ ] No token, question text, or private name appears in any committed file or log fixture

## Verification
`cd cmd/flick && go vet ./... && go test ./...` then `bash tests/test-flick-wrapper.sh && bash tests/test-meta.sh && bash tests/run-all.sh`. The Go test skips with a printed reason when `go` is absent (`command -v go`). The live Jev call runs only when the token env var is set and prints `SKIP: no token` otherwise. Negative control: flip the egress regex to accept any text, and the denied-token test must go red.

## Grounding
- **Jev request/response shape** (sampled from a private evaluation harness's code, not a live call; request shape only, no token): POST `https://api.typesafe.ai/v1/systemone`, header `Authorization: Bearer <env token>`, body `{"model":"jev-1.13.0","state":"<text>","questions":{"<id>":{"type":"choice","criteria":{"<choice>":"<description>"},"instructions":"<question>"}}}`. Response `{"answers":{"<id>":{"type":"choice","choice":"<choice>","probabilities":{"<choice>":0.9}}}}`. `criteria` must be a dict; a list returns HTTP 422. The harness measured p50 0.50 s and p95 0.69 s per call. A live sample for this spec is unavailable until TASK-10 runs with a token.
- **OpenAI Decisions API:** limited preview, shape unpublished. Not sampleable. The adapter is written against an assumption and fails open on any mismatch.
- **Host start-up cost** (measured on the build host): Python 0.22 to 0.38 s, TLS handshake 0.23 to 0.49 s.
- **Go on CI runners:** `.github/workflows/test.yml` runs only on `workflow_dispatch` and `v*` tags, on `ubuntu-latest` and `macos-latest`. The hosted images are believed to ship Go, unverified here. The Go test must skip cleanly when `go` is missing or older than the `go.mod` directive (1.22). This spec adds no workflow, no runner, no new hosted spend. The local `bash tests/run-all.sh` is the check.
- **Negative-control dry trace:** mutation = make the `wrap-7b` regex `.*`. `TestEgressDeniesFreeText` reads a question holding a non-public token, expects `egress_denied` and zero stub hits, and goes red because the stub counter is 1.
- The stub (`httptest`) is plain HTTP, so its latency table excludes TLS and HTTP/2. Only the live call measures those.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Provider outage or auth failure | `http_5xx`, `http_401`, `timeout` in `error` | Empty answer, exit 0, caller keeps its path |
| Overconfident wrong answer | shadow log: `chosen` differs from `existing` at high margin | Stays shadow. No act path exists for `wrap-7b` |
| Private name leaves the host | none by design | Allowlist is deny-by-default and public-name only; the log stores no text |
| Stale cached binary | hash mismatch | New source hash selects a new file; the old one is never reused |
| Compile cost on a fresh machine | `no_binary` on first calls | Background build, then hits; `bin/flick build` forces it |
| Project PR sets `[decide]` | test case | Root-only read ignores it |
| Provider drifts from the pinned model | `model` field in the log differs from the pin | Pin in config; a drift shows in the log, never silently |

## Out of Scope
- Any hook, fail-closed gate, or hot path calling flick.
- Acting on an answer (`decide` mode for any real point). Phase 3 compares logs, then a later spec decides.
- A second decision point. Each one needs a spec.
- A checked-in prebuilt binary.

## Touches
- cmd/flick/**
- tests/**

## Decision Log
- DEC-1: Name `flick` for the tool; the kit.toml block stays `[decide]`. The block names the capability and two backends sit behind it, so a backend or the binary can change without a config rename.
- DEC-2: Go over Rust. Stdlib `net/http` needs no dependencies and builds in seconds on first use. Rust saves about 4 ms of start-up against a 300+ ms network call, and needs a heavy crate tree (reqwest, tokio, rustls) built on the operator's machine. Revisit if start-up ever matters.
- DEC-3: Source ships, binary is a per-machine cache. Keeps the "no compiled binaries" rule true for what the repo distributes, and needs the named carve-out in TASK-1.
- DEC-4: Call path never compiles in the foreground. Returning `no_binary` once beats a multi-second stall that defeats the speed goal.
- DEC-5: Egress is deny-by-default by name allowlist, not a regex over text. A regex passes a client-named script. Cost: low shadow coverage until `allow_names` grows.
- DEC-6: Timeout floor 1500 ms, from the research doc's screens, even though the call is meant to be sub-second.

## Open questions
- Allowlist strictness: strict public-name set (this spec) versus a plain tool-name regex. Strict is safer and yields few shadow samples at first.
- Should the OpenAI adapter ship now on an assumed shape, or as a stub returning `unsupported` until the API shape is published?
