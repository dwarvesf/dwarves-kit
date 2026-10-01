# Spec: flick, a fast decision CLI for kit steps
Generated: 2026-10-01
Status: VALIDATED
Lane: full (external provider, new component, egress)
Depth: research (outside: the OpenAI Decisions API shape is preview-only and unpublished)
References: `docs/research/2026-09-23-jev-absorption.md` (never-use list and "Security / trust screens" bind this spec); `lib/config/kit-config.sh` `kit_config_get_root` (root-only read to imitate); `lib/telemetry/kit-log-dir.sh` (log dir precedence to mirror, minus its project overlay); `bin/spec` and `lib/spec/spec.sh` (the `<subsystem> <verb>` forwarder shape to match)

## Problem
A kit step that needs a "pick one of N" judgment pays 20 to 60 s for an in-session model call. A decision API answers in about 0.5 s. The kit cannot yet measure whether an API decider matches the in-session judgment, so the swap is untested. A script with no interpreter start and one network call per batch reaches sub-second.

## Contract
`flick` reads JSON on stdin and writes one JSON object on stdout. It always exits 0. A decision point defines its own slots, so a caller never supplies free question text.

```
stdin : {"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board","existing":"enhance"}]}
stdout: {"backend":"jev","model":"jev-1.13.0","latency_ms":412,"mode":"shadow",
         "answers":{"p1":{"choice":"enhance","probs":{"enhance":0.7,"new":0.2,"none":0.1},"margin":0.5}},"error":"",
         "counts":{"answered":1,"denied":0,"error":0}}
```

- Caller fields: `id` matches `^[A-Za-z0-9_-]{1,40}$` and is echoed on stdout only. flick sends `q1..qN` to the provider and maps back. `existing` is optional and kept only when it is one of the point's choices, else treated as empty. Any other stdin field is `bad_input`. Control characters and newlines in any value are `bad_input`.
- `counts` covers every question that parsed: `answered + denied + error` equals that number. Denied questions count as `denied` before any request. When the whole call fails (timeout, HTTP error, malformed, `bad_probs`, `no_token`, `unsupported`, `backend_none`), every non-denied question counts as `error`. On `bad_input` nothing parsed, so all three are 0.
- Fail-open: any failure prints `"answers":{}` and a reason in `error`, exit 0. An EXIT trap guarantees valid empty-answer JSON and exit 0 even on a crash or garbage config. A refused question gets `answers.<id> = {"choice":"","error":"egress_denied"}` and the rest still run.
- `error` is a closed set: `backend_none`, `missing_dep`, `no_token`, `timeout`, `http_<status>`, `network`, `malformed`, `bad_probs`, `egress_denied`, `point_disabled`, `bad_input`, `unsupported`.
- Config, read root-only with `kit_config_get_root` (operator file or kit root, never a project `.kit.toml`, because the block names a credential source and authorizes egress). The kit reader returns single-line scalars, so lists are space-separated strings, as in `wrap.build_lanes`:

| Key | Default | Meaning |
|---|---|---|
| `decide.backend` | `"none"` | `jev`, `openai`, or `none`. `none` leaves kit behaviour unchanged |
| `decide.jev_model`, `decide.openai_model` | `jev-1.13.0`, `""` | Pinned, never a `latest` alias |
| `decide.timeout_ms` | `1500` | Floor 1500: lower values clamp up (research doc screen) |
| `decide.mode` | `"shadow"` | `shadow` logs beside the existing decision and never acts. `decide` returns the answer for the caller to use |
| `decide.points` | `""` | Space-separated enabled decision points. Empty means nothing leaves the host |
| `decide.jev_token_env`, `decide.openai_token_env` | `JEV_API_TOKEN`, `OPENAI_API_KEY` | Env var NAME only, matching `^[A-Za-z_][A-Za-z0-9_]*$`. The token never sits in a file, argv, a log, or stdout |
| `decide.jev_token_cmd`, `decide.openai_token_cmd` | `""` | Optional second token source, used only when the env var named above is empty. A command line split on whitespace and run with no shell, no glob, no expansion; the first word must be an absolute path. stdin from `/dev/null`, stderr dropped, own process group killed (TERM, then KILL) at a 10 s limit, output capped at 4096 bytes. stdout minus one trailing newline is the token and takes the same shape check as an env token. Any failure, timeout, empty, oversized or malformed output is `no_token`. The output is never logged or printed. `openai_token_cmd` is reserved |
| `decide.allow_names` | `""` | Extra public tool names, exact match, added to the kit-public set |
| `decide.deny_words` | `""` | Space-separated words that block a candidate slug (client names, private repo names). While `wrap-7b` is enabled and this is empty, flick sends nothing: every question is `egress_denied` and the log reason is `deny_words_empty` |
| `decide.word_gate` | `"on"` | `on` or `off`. While on, each hyphen segment of a candidate must be a dictionary word, a built-in dev word, or a kit-public name; anything else is `egress_denied` with log reason `word_gate`. Any value but `off` counts as on |
| `decide.dict_file` | `/usr/share/dict/words` | Dictionary for the word gate, one word per line. Must be an absolute path to a regular file under 16 MB. Anything else (missing, unreadable, relative, oversize): every candidate is `egress_denied` (`word_gate_no_dict`), because egress fails closed |

## Picture
```
 /kit:wrap 7b --(decide.points has wrap-7b?)--> no: unchanged, flick never runs
       | yes: ALL pairs, ONE call
       v
  bin/flick --> lib/decide/flick.sh   (command layer; hooks/ never call it)
       | backend none / missing curl or jq -> empty answer, exit 0
       | backend openai -> error unsupported, no request
       v  (backend jev)
  egress guard: slots checked, text REBUILT from the template
       |-- denied questions dropped BEFORE the body is built (counted, logged without text)
       v
  jq builds ONE body (ids q1..qN, hit description from the kit root) --> curl -q --proto =https --max-time --> provider
       |   token: curl config on stdin, never argv
       v  jq validates key sets, probs sum ~1, argmax unique, margin
  stdout JSON  +  <log dir>/decide.jsonl line (sent slugs only, no token)
```

## Design
Diagram: see ## Picture.

**Layout.** `lib/decide/flick.sh` is the engine; `bin/flick` is the stable forwarder, the same shape as `bin/spec`. A second verb, `flick body`, reads the same stdin, runs the guard, and prints the provider request body it would send, with no token and no network, so the guard is testable before the transport exists. Bash 3.2 safe. Dependencies are `curl` and `jq` only, no perl, no compiled code, no build step. A missing one gives `missing_dep`.

**Kit root.** The engine derives `KIT_ROOT` from its own path (`dirname "${BASH_SOURCE[0]}"/../..`), never from the current directory. The public-name set is the basenames of `$KIT_ROOT/bin/*`, `commands/*.md`, `skills/*/` and `agents/*.md`, plus `decide.allow_names`.

**Matching and rebuild.** A name matches by exact fixed-string equality (`grep -Fx` against the set), never a regex or substring. flick rebuilds the question text from the point's template, the matched slots and the hit's public description, and never forwards caller text.

**Hit description.** A hit that passed the allowlist carries its own one-line description, read from the kit root and never the cwd. Sources in order: `bin/<hit>` (the header of the `lib/<subsystem>/*.sh` it forwards to, else its own first descriptive comment lines), then the `description:` frontmatter of `commands/<hit>.md`, `skills/<hit>/SKILL.md`, `agents/<hit>.md`. Comment lines are joined up to the first bare `#` line. Control characters are stripped and the text is capped at 160 characters, ending at the last whole sentence that fits. A hit with no readable description (an `allow_names` entry with no kit file) is sent with the plain template. Per-choice `criteria` text comes only from the point registry. A mixed batch drops each denied question before the request is built, so denied text never reaches the body.

**`wrap-7b` point.** Slots: `candidate` is a lead-written slug `^[a-z0-9-]{3,40}$` containing no `decide.deny_words` entry. The match is a case-folded substring test (both sides lowercased, so `Acme` blocks `acme-sync` and `sync-acme-x`), chosen over segment matching because it errs toward denial; `hit` must be an exact kit-public name, and any other hit is `egress_denied` and counted. Template: `Does the existing tool <hit> (described as: <description>) cover the job of the candidate <candidate>?`, with the parenthesis left out when the hit has no description. Choices map to wrap's own verdicts, and the registry's per-choice criteria say so: `enhance` (the existing tool already does, or could own, the job), `new` (the existing tool does an unrelated job), `none` (the names and description give no basis to decide). Context is not accepted. A live run on slugs alone answered `none` at margin 0.76 to 0.89 for two obvious matches, so the description and the criteria wording carry the accuracy fix.

**Word gate.** A deny list cannot be complete, so the candidate slot also has an allow rule. While `decide.word_gate` is on (the default), each hyphen-separated segment of a candidate must be a dictionary word, a built-in dev word, or a name in the kit-public set (whole-name equality, so a hyphenated public name never matches a segment). The dictionary match is case-insensitive and whole-line against `decide.dict_file`. The dev-word list is a constant in `lib/decide/flick.sh` (`pr ci cd api cli json yaml toml md sql db git gh repo env url http https ssh tls jwt oauth sdk ui ux pdf csv tsv cron kv llm ai id ids sha diff lint todo wip config auth regex stdin stdout async`). A segment under 3 characters passes only through the dev-word list or the public set, never through the dictionary, because a dictionary lists every letter and `z-o-r-b-i-x-sync` would pass. A slug with no word at all (`---`) is denied. A denied question is `egress_denied` with log reason `word_gate`, and it is dropped before the body exists, the same as a `deny_words` hit. `deny_words` still applies first, because it catches dictionary words such as a client called `loft`. A missing or unreadable dictionary denies every candidate with reason `word_gate_no_dict`: egress fails closed, while the rest of flick still fails open with exit 0 and valid JSON. Both keys are root-only. The gate reads the dictionary once per batch with one `awk` pass over every segment the dev-word and public sets did not cover. On macOS, `grep -Fixf` over the 236k-line system dictionary took over 500 ms, and `awk` took about 100 ms. `look` (binary search) is faster but needs a sorted file, so it stays a possible fast path.

**Word gate limit.** The gate cannot see a name that is itself an English word (stripe, notion, slack, linear, apple, loft). Such a name passes the dictionary check, so `decide.deny_words` still matters and must list them. The gate narrows the leak to dictionary-word names; it does not close it.

**Config location.** flick reads exactly two files: the kit root's own `kit.toml` (the root derived from the script path) and `$HOME/.config/dwarves-kit/kit.toml`. `KIT_CONFIG_ROOT`, `KIT_CONFIG_OPERATOR`, `XDG_CONFIG_HOME` and `DWARVES_KIT` do not move them, because a project shell or `.envrc` could otherwise point flick at a file that turns the gate off, edits `deny_words`, or names a token command. `KIT_CONFIG_OPERATOR` and `KIT_CONFIG_ROOT` are honoured only with `FLICK_TEST=1`, the same switch as `FLICK_URL`. The decision log location read follows the same two files.

**JSON and secrets.** Every JSON value is built with `jq -n --arg` or `--argjson`, never concatenation. The body goes to a `mktemp` file (no secret in it) via `--data-binary @file`. The token reaches curl through `curl --config -` on stdin (`printf` is a builtin, so `ps` never shows it). A token containing `"`, `\`, or a control character is `no_token`. Production calls use `--proto =https` and no `-L`, with `-q` as curl's FIRST argument (curl reads `-q` as "skip `~/.curlrc`" only in that position).

**`FLICK_URL`.** Read only when `FLICK_TEST=1` is also set, so a stray variable in an operator shell cannot move egress; without it the variable is ignored and production stays https. With it set, `FLICK_URL` must match `^http://(127\.0\.0\.1|localhost)(:[0-9]+)?(/|$)` with no userinfo, for the test stub. Any other value is `bad_input` with zero requests, never a fallback to production. A valid one switches to `--proto =http`.

**Request and time.** One `curl` per batch, `--max-time` from `timeout_ms`, `--http2` when `curl -V` lists HTTP2, status read with `-w '%{http_code}'`. `latency_ms` is curl `time_total` x 1000. Overhead is measured by the test with python3 (test-only) as wall time minus that figure.

**Validation (jq).** The provider's answer keys must equal the requested ids exactly, and each answer's probability keys must equal the choice set exactly. The sum is within 0.03 of 1 and the choice is the unique argmax. A tie, a missing key, or an extra key is `bad_probs`. `margin` is top minus second. Callers see the distribution and margin, never the provider's single `confidence` field (it scored 0.66 on gibberish in a shipped integration, per the research doc).

**OpenAI backend.** A stub that returns `unsupported` and sends nothing until OpenAI publishes the Decisions API request shape.

**Never-use.** The never-use list in `docs/research/2026-09-23-jev-absorption.md` ("Where Jev must NOT be used") applies to every backend by reference: no fail-closed gate (ship-gate, secret-guard, safety or money gates), no client, NDA, family or secret text. The registry has no point for any of them. flick is a command-layer tool called from `commands/wrap.md` in shadow mode, never a hook, and a test fails if anything under `hooks/` references it.

**Mode.** `wrap-7b` supports `shadow` only. With `mode = "decide"` it runs as shadow and the log records `mode_downgraded`. Nothing writes a decision into a live gate.

**Decision log.** One JSON line per question in `<log dir>/decide.jsonl` (a failure skips logging, never the answer): `ts, backend, model, point, index, latency_ms, candidate, hit, chosen, existing, margin, error, mode`. The file is created owner-only (`umask 077` around the append). The log dir follows `kit_resolve_log_dir`'s precedence (`KIT_LEDGER_DIR`, then `DWARVES_KIT_LOG_DIR`, then `[ledger] location`, then the XDG default), but the `[ledger] location` read is root-only (operator file or kit root), never a project `.kit.toml`: the log holds the slugs that left the host, so a project must not move it. Sent slugs are logged so an operator can audit what left the host. A denied question logs the index and a `reason` (`guard`, or `deny_words_empty`) only. Caller `id`, denied text, and the token never appear.

**`/kit:wrap` step 7b.** After the session judges its precedent hits, and only when `kit_config_get_root decide.points` lists `wrap-7b`, wrap sends ALL (candidate, hit) pairs in ONE `bin/flick` call, so an outage costs at most one timeout, with `existing` set to its own verdict. It ignores the answers except one FYI `STATE` row: `answered / denied / error` counts and the backend. With the point absent, step 7b is byte-for-byte today's behaviour.

**Exit criterion.** Shadow runs until 50 labelled `wrap-7b` pairs exist. Promotion to any acting mode needs agreement with the lead's verdict of at least 90% and zero private names in the log's sent slugs. A later spec decides promotion.

## Task Breakdown
Strict order: TASK-1 first (tests exist before code), then 2 to 12 in sequence. TASK-3 and TASK-4 assert on the output of `flick body` (the guarded request body, no network), so each step passes before the transport exists. TASK-5 builds the real request only from what that guard lets through and repeats the body assertions against the stub.
### Phase 1: Foundation
- [ ] TASK-1: Create `tests/lib/flick-stub.py` (test-only, python3, modes: ok, 401, 500, slow, malformed, badprobs, tie, extra-key, counts requests, records the last body) and the `tests/test-flick.sh` skeleton with `SKIP: <why>` when curl, jq or python3 is missing. Done when the skeleton runs and skips cleanly.
- [ ] TASK-2: `lib/decide/flick.sh` plus `bin/flick`: stdin parse, contract, closed error set, EXIT trap, `backend_none`, `missing_dep`, env-name and token-shape checks, `flick` added to `EXPECTED` in `tests/test-bin-forwarders.sh`. Done when tests cover backend none, no token, bad env name, a token with a quote, and a garbage-config and garbage-stdin fuzz case that always yields valid JSON and exit 0.
- [ ] TASK-3: Input contract: `id` remap to `q1..qN`, `existing` filtering, extra-field and control-character rejection. Done when a canary string in `id` and in `existing` is absent from the `flick body` output and from the log, and an extra field returns `bad_input`.
- [ ] TASK-4: Egress guard and `wrap-7b` registry: kit root from the script path, exact `-Fx` matching, template rebuild, `deny_words`, mixed-batch drop. Done when: a candidate matching a `deny_words` entry is `egress_denied` with zero requests and is absent from the `flick body` output, and the match is case-folded (`Acme` in `deny_words` blocks `acme-sync`); `counts` equal the real answered, denied and error numbers for a mixed batch; a foreign cwd whose `bin/` holds a client-style name is denied; a trailing-newline payload and a name containing a public name as a substring are denied; a mixed batch's `flick body` output holds only allowed ids and none of the denied text.
### Phase 2: Core
- [ ] TASK-5: Jev request and transport: `jq -n` body, one curl per batch, token on stdin, `-q --proto =https`, no `-L`, `FLICK_URL` rule, timeout and HTTP-status mapping. Done when the TASK-3 and TASK-4 body assertions also hold against the stub's received body; a test with `HOME` pointing at a temp dir whose `.curlrc` holds a canary `trace` directive shows the canary has no effect and no Bearer header reaches disk; `counts` read all-`error` for each whole-batch failure; `http://127.0.0.1@evil.example/`, `http://localhost.evil.example/` and `http://127.0.0.1.evil.example/` each yield `bad_input` and zero stub requests, and tests cover a 3-question single-request batch, timeout, 401 and 5xx.
- [ ] TASK-6: Jev response validation: exact key sets, sum, unique argmax, margin. Done when malformed JSON, probabilities off by more than 0.03, an argmax tie, a missing key and an extra key each map to `malformed` or `bad_probs`.
- [ ] TASK-7: OpenAI stub. Done when `backend = "openai"` returns `unsupported` and the stub saw zero requests.
- [ ] TASK-8: Decision log. Done when a test greps the log, stdout and the process list during a slow stub call and finds no token, no denied text and no caller id, and a failing `kit_resolve_log_dir` still returns the answer.
- [ ] TASK-9: `[decide]` block in `kit.toml` with status tags. Done when a project `.kit.toml` carrying `[decide]` changes nothing (root-only test).
- [ ] TASK-10: Packaging and registry: install and plugin packaging for `lib/decide/` and `bin/flick`, `tool.toml`, `docs/FEATURES.md`. Done when `bash tests/test-meta.sh` and `bash tests/test-bin-forwarders.sh` pass.
### Phase 3: Polish
- [ ] TASK-11: `commands/wrap.md` step 7b paragraph, plus a test that nothing under `hooks/` references flick. Done when the wrap lint passes with the key unset and set.
- [ ] TASK-12: Latency table (1, 5, 20 questions) against the stub in `docs/implementation-notes/flick.md`, plus one live Jev call when the token env var is set. Done when flick's own overhead, measured without perl, is under 50 ms.

## After state
- [ ] `bin/flick` with `decide.backend = "none"` prints an empty answer and exits 0, and no kit step changes. (Today: no decision CLI exists.)
- [ ] With `backend = "jev"`, `points = "wrap-7b"` and a token, one batch of public-name pairs returns validated answers in under 1 s and appends log lines. (Today: step 7b judges in-session, 20 to 60 s.)
- [ ] A project `.kit.toml` carrying `[decide]` changes nothing, checked by `bash tests/test-flick.sh`.
- [ ] Every failure path in the closed error set exits 0 with `answers` empty.
- [ ] `grep -r flick hooks/` finds nothing.

## Acceptance Criteria (global)
- [ ] All tasks pass their own criteria; no regression in `bash tests/run-all.sh`
- [ ] No token, denied text, caller id, or private name appears in any committed file, log fixture, or request body

## Verification
`bash tests/test-flick.sh && bash tests/test-bin-forwarders.sh && bash tests/test-meta.sh && bash tests/run-all.sh`. The test starts `tests/lib/flick-stub.py` on a free local port and points `FLICK_URL` at it. The live Jev call runs only when the token env var is set and prints `SKIP: no token` otherwise. Negative control: replace the `grep -Fx` hit check with a substring match, and the substring-name test must go red.

## Grounding
- **Jev request/response shape** (sampled from a private evaluation harness's code, not a live call; shape only, no token): POST `https://api.typesafe.ai/v1/systemone`, header `Authorization: Bearer <env token>`, body `{"model":"jev-1.13.0","state":"<text>","questions":{"<id>":{"type":"choice","criteria":{"<choice>":"<description>"},"instructions":"<question>"}}}`. Response `{"answers":{"<id>":{"type":"choice","choice":"<choice>","probabilities":{"<choice>":0.9}}}}`. `criteria` must be a dict; a list returns HTTP 422. All questions of a request share `state`. A live sample is unavailable until TASK-12 runs with a token.
- **Jev latency** (two trials): browser-step suite p50 0.50 s and p95 0.69 s; general suite p50 0.68 s and p95 0.81 s. Both fit the 1500 ms floor.
- **OpenAI Decisions API:** limited preview, request shape unpublished. Not sampleable, so no adapter is coded.
- **Host cost** (measured on the build host): Python start-up 0.22 to 0.38 s and a TLS handshake 0.23 to 0.49 s, which rules out a Python client. A bash plus `curl` plus `jq` run measured about 30 ms of start-up against about 5 ms for a compiled binary, under 10% of a 300+ ms call.
- **Local curl:** 8.7.1 with nghttp2, so `curl -V` lists HTTP2 here. The stub is plain HTTP, so its latency excludes TLS and HTTP/2.
- **CI:** `.github/workflows/test.yml` runs only on `workflow_dispatch` and `v*` tags. This spec adds no workflow, no runner, no hosted spend.
- **Negative-control dry trace:** mutation = swap `grep -Fx` for a substring match in the hit check. The test sends a hit that contains a public name as a substring, expects `egress_denied` and a stub request count of 0, and goes red because the count is 1.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Provider outage or auth failure | `http_5xx`, `http_401`, `timeout` in `error` | Empty answer, exit 0; one call per wrap caps the cost at one timeout |
| Overconfident wrong answer | shadow log: `chosen` differs from `existing` at high margin | Stays shadow. No act path exists |
| Private name leaves the host | deny_words test (TASK-4) | Exact-match public hits, case-folded substring `deny_words` on candidates, guard drops before the body is built |
| cwd-planted name widens the allowlist | foreign-cwd test | Kit root comes from the script path |
| Caller text smuggled via `id` or `existing` | canary test | `q1..qN` to the provider, `existing` filtered to choices |
| Token visible to `ps` or logs | TASK-8 test | Curl config on stdin, env var name only |
| `FLICK_URL` or `~/.curlrc` redirects egress or traces the token | three-URL test, canary `.curlrc` test | Strict URL regex, `bad_input` not fallback, `-q` as first argument, `--proto =https` |
| Provider answers extra or missing keys | TASK-6 test | Exact key-set match, else `bad_probs` |
| Project PR sets `[decide]` | test case | Root-only read ignores it |

## Out of Scope
- Any hook, fail-closed gate, or hot path calling flick.
- Acting on an answer. The exit criterion above gates a later spec.
- A second decision point (each needs a spec), any compiled component, an OpenAI request shape before one is published.

## Touches
- lib/decide/**
- bin/**
- tests/**
- commands/**
- docs/implementation-notes/**
- Single files, outside the dispatch glob form: `kit.toml`, `commands/wrap.md`, `docs/FEATURES.md`, `tool.toml`, `install.sh` and plugin packaging, `docs/implementation-notes/flick.md`, `tests/test-bin-forwarders.sh` (`EXPECTED`).

## Decision Log
- DEC-1: Name `flick`; the kit.toml block stays `[decide]`. The block names the capability, so a backend or the implementation can change without a config rename.
- DEC-2: bash + curl + jq over Go or Rust. PHILOSOPHY says "No compiled binaries". Start-up is about 30 ms against about 5 ms, under 10% of a 300+ ms call, and there is no build step.
- DEC-3: flick is a command-layer tool called from `commands/wrap.md` in shadow mode, not a hook. "No LLM API calls in v1 hooks" is untouched, and it must never be called from `hooks/` (a test enforces it).
- DEC-4: Deny-by-default, exact-match public hit names, text rebuilt from a template. A regex or forwarded text passes a client-named script. Cost: low shadow coverage until `allow_names` grows.
- DEC-5: The OpenAI backend is an `unsupported` stub. An assumed request shape would be a guess dressed as code.
- DEC-6: Timeout floor 1500 ms, from the research doc's screens.
- DEC-7: List config is space-separated and token env names are flat keys, because the kit's TOML reader returns single-line scalars.
- DEC-8: `FLICK_URL` exists for the test stub only. A bad value is `bad_input`, never a production fallback.
- DEC-9: This spec opens one shadow point despite the standing SKIP verdict in the Jev absorption research, on the operator's 2026-10-01 approval. Shadow mode and the 50-pair exit criterion are the guard against that verdict being right.
- DEC-10: Points define slots instead of taking free question text, a deliberate change from the first interface sketch. Free text cannot be allowlisted; slots can.
- DEC-11: Latency comes from curl `time_total`, not a perl clock, to keep the dependency set at curl and jq.
- DEC-12: post-build review fold. (a) A live Jev run on slugs alone answered `none` for all three pairs, so the question text now carries the hit's public description from the kit root, and the criteria say `enhance` = the tool already does or could own the job. (b) No deny list, no egress: `deny_words_empty` denies every question. (c) The log dir is resolved root-only. (d) `FLICK_URL` needs `FLICK_TEST=1`; `timeout_ms` is read as base 10; `bin/flick` prints valid empty-answer JSON when the engine is missing; the log append runs under `umask 077`.
- DEC-13: `token_cmd` for hosts without ambient secrets. A host that keeps ops secrets out of the shell env never sets `JEV_API_TOKEN`, so flick always answered `no_token`. A root-only command key is the second source. It runs with no shell and no expansion so a config string cannot become more than one argv, and its output goes to a file in a private 0700 temp dir that flick removes before it returns. The config variables live in a private `FLKC_` namespace that flick clears before it loads any file, so an inherited env var such as `OP_points` cannot stand in for config.
- DEC-14: word gate: allow-by-dictionary over deny-by-list. On macOS, every hyphen segment of generic slugs (ship, own, hand, backlog, flip, script, merge, loop, helper, sync) is in `/usr/share/dict/words`, and client-style names are not. An allow rule fails closed on a name nobody thought to list, which a deny list cannot do. Limit: a name that is an English word still passes the gate, so `deny_words` stays. Cost: a legitimate slug with a coined word is denied until it joins the dictionary, the dev-word list, or `allow_names`; and the dictionary scan adds roughly 100 ms on macOS.

## Open questions
(none)
