# Proof of done: clef backend for flick (Cloudflare Workers AI)

Scope: `lib/decide/flick.sh` gains a third live backend, `clef`, selectable with
`[decide] backend = "clef"`. Jev stays the operator default; `backend = "jev"` and
`backend = "none"` are unchanged. The Cloudflare envelope is unwrapped only when
`success` is true and `.result` is an object, so the answer validation below sees
the same shape Jev returns and a `success:false` envelope is rejected, never
trusted. `clef_token_env` defaults to `FLICK_CLEF_TOKEN` (a token scoped to
Workers AI); the broad `CLOUDFLARE_API_TOKEN` is used only when an operator names
it explicitly. An `op://` `clef_account` resolves through `secret-cache-read`
found on PATH, else `~/.local/bin`, under the same bound a token command gets;
a missing or unresolvable account is `no_account`, distinct from `no_token`.
The word gate, allowlist, `deny_words` and every egress check sit in front of
the clef call exactly as they do for Jev.

## Green run

Command: `bash tests/test-flick.sh`
Exit: 0
Output:

```
  ok: no secret-cache-read on PATH or in ~/.local/bin: missing_dep
  ok: missing_dep sends nothing
  ok: a failing secret-cache-read: no_account, not no_token
  ok: a failed lookup sends nothing
  ok: a lookup that prints a non-account: no_account
  ok: a hanging secret-cache-read: no_account
  ok: the lookup is cut at the same bound a token command gets (about 10 s, not 40)
  ok: and a hung lookup sends nothing
  ok: clef_model clef-flash rides the envelope
  ok: and the request body
  ok: an unknown clef_model falls back to clef in the body
  ok: and in the envelope
  ok: no clef_account: no_account, the question counts as error
  ok: nothing was sent without an account
  ok: an empty FLICK_CLEF_TOKEN: no_token (the Jev env var does not substitute)
  ok: nothing was sent without a token either
  ok: clef_token_cmd supplies the token when the env is empty
  ok: the stub saw the command's clef token
  ok: clef_token_env can still name the ambient Cloudflare var
  ok: the override var's value was used
  ok: clef timeout: the 4 s stub is cut
  ok: the clef default timeout is about 3000 ms, not jev's 1500
  ok: an explicit timeout_ms still wins for clef
  ok: the explicit 1500 fired at about 1.5 s
-- backend jev is byte-for-byte the same run --
  ok: jev: the TASK-6 assertions, unchanged
  ok: jev: the request body, unchanged
  ok: jev: flick body output, unchanged

flick: 339 passed, 0 failed
```

Verdict: PASS

## Jev parity: master vs branch through the stub

`origin/master`'s `lib/decide/flick.sh` was dropped into an `rsync`ed temp copy of
the worktree; both engines ran the same `wrap-7b` question through the stub under
the same clean env (`FLICK_TEST=1`, `FLICK_URL` at the stub, canary token), then
`latency_ms` was masked. The stdout envelopes and the request bodies the stub
recorded are identical:

```
master (masked): {"backend":"jev","model":"jev-1.13.0","latency_ms":N,"mode":"shadow","answers":{"p1":{"choice":"enhance","probs":{"enhance":0.7,"new":0.15,"none":0.15},"margin":0.5499999999999999}},"error":"","counts":{"answered":1,"denied":0,"error":0}}
branch (masked): {"backend":"jev","model":"jev-1.13.0","latency_ms":N,"mode":"shadow","answers":{"p1":{"choice":"enhance","probs":{"enhance":0.7,"new":0.15,"none":0.15},"margin":0.5499999999999999}},"error":"","counts":{"answered":1,"denied":0,"error":0}}
RESULT: identical after latency masking
BODY: identical
```

`run_curl` changed for Jev too: the URL moved out of argv into curl's stdin config
(`-q` first arg keeps even a hostile `$HOME/.curlrc` from adding flags), so a clef
URL carrying the account id never reaches the process list. The curl-hygiene
checks cover this on the Jev path: `the canary .curlrc had no effect on flick (-q
is curl's first argument)`, `no Bearer header or token reached disk under that
HOME`, `source pin: -q is the first curl argument, production proto is =https, no
-L`, plus `the token is nowhere in the request body or stdout` and the
`ps shows no token while curl is in flight` pair.

`docs/FEATURES.md` also changed, by one generated cell (`/kit:battery` test
references `+6` to `+7`). The file is generated (`GENERATED, do not hand-edit`);
`tests/test-break-it.sh` landed on master after the registry was last
regenerated, so the checked-in copy undercounted and the `docs/FEATURES.md is
fresh` pin in `tests/test-meta.sh` failed on this branch until the file was
regenerated with `lib/registry/feature-registry.sh`.

## Live run (real Cloudflare Workers AI call)

One real call through `bin/flick decide` with `backend = "clef"`. The config lived
in a throwaway `mktemp -d` directory pointed at by `KIT_CONFIG_OPERATOR` /
`KIT_CONFIG_ROOT` under `FLICK_TEST=1`; the operator's real file was never read
or written. `clef_account` was `op://Toolkit/kit-proof-assets/account_tieubao`,
resolved through `secret-cache-read` (cache name `FLICK_CLEF_ACCT_<sha8 of ref>`);
the token came from `FLICK_CLEF_TOKEN`, handed the ambient Cloudflare token for
that one command only. No token and no account id appear here or in any log: the
URL rides curl's stdin config, so it never reaches argv either.

Input: `{"point":"wrap-7b","questions":[{"id":"q1","candidate":"board-sync","hit":"board","existing":"enhance"}]}`

Output:

```
{"backend":"clef","model":"clef","latency_ms":1347,"mode":"shadow","answers":{"q1":{"choice":"enhance","probs":{"enhance":0.6271,"new":0.2878,"none":0.0851},"margin":0.3393}},"error":"","counts":{"answered":1,"denied":0,"error":0}}
```

The decision log line for the same call (throwaway log dir, no token, no account id):

```
{"ts":"2026-10-04T04:47:03Z","backend":"clef","model":"clef","point":"wrap-7b","index":0,"latency_ms":1347,"candidate":"board-sync","hit":"board","chosen":"enhance","existing":"enhance","margin":0.3393,"error":"","mode":"shadow","mode_downgraded":false}
```

## NEGATIVE CONTROL

The current `tests/test-flick.sh` (with the clef section) run against
`origin/master`'s `lib/decide/flick.sh`, placed in an `rsync`ed temp copy of the
worktree; the worktree itself was never touched. `origin/master` does not
recognise `clef`, so the backend fell back to `none` and every check expecting a
clef behaviour went red.

Output tail:

```
flick: 307 passed, 32 failed
```

All 32 failures are in the `== clef backend ==` section and report
`"error":"backend_none"` (or its shadow assertions): the happy-path unwrap, the
one-request-per-batch check, the `FLICK_CLEF_TOKEN` preference, the `success:false`
rejections, HTTP 429/529, `bad_probs` after unwrap, the `op://` PATH and
`~/.local/bin` resolutions, `missing_dep`, the `no_account` cases, both
`clef_model` checks, `clef_token_cmd`, the `clef_token_env` override, and the
timeout checks. Green on master were the vacuous `sends nothing` companions, the
`a literal clef_account never calls secret-cache-read` check, and every
pre-existing section, including the Jev byte-compat assertions.

Result: RED as expected

Verdict: PASS
