# Proof of done: clef backend for flick (Cloudflare Workers AI)

Scope: `lib/decide/flick.sh` gains a third live backend, `clef`, selectable with
`[decide] backend = "clef"`. Jev stays the default; `backend = "jev"` and `backend = "none"`
are unchanged. The Cloudflare envelope is unwrapped (`.result`) before the existing answer
validation, so `FINAL_PROG` sees the same shape Jev returns. The word gate, allowlist,
`deny_words` and every egress check sit in front of the clef call exactly as they do for Jev.

## Green run

Command: `bash tests/test-flick.sh`
Exit: 0
Output:

```
  ok: nothing was sent without an account
  ok: an empty CLOUDFLARE_API_TOKEN: no_token (the Jev env var does not substitute)
  ok: nothing was sent without a token either
  ok: clef_token_cmd supplies the token when the env is empty
  ok: the stub saw the command's clef token
  ok: clef timeout: the 4 s stub is cut
  ok: the clef default timeout is about 3000 ms, not jev's 1500
  ok: an explicit timeout_ms still wins for clef
  ok: the explicit 1500 fired at about 1.5 s
-- backend jev is byte-for-byte the same run --
  ok: jev: the TASK-6 assertions, unchanged
  ok: jev: the request body, unchanged
  ok: jev: flick body output, unchanged

flick: 326 passed, 0 failed
```

Verdict: PASS

## Live run (real Cloudflare Workers AI call)

One real call through `bin/flick decide` with `backend = "clef"`. The config lived in a
throwaway `mktemp -d` directory pointed at by `KIT_CONFIG_OPERATOR` / `KIT_CONFIG_ROOT`
under `FLICK_TEST=1`; the operator's real file was never read or written. `clef_account`
was `op://Toolkit/kit-proof-assets/account_tieubao`, resolved through `secret-cache-read`
(cache name `FLICK_CLEF_ACCT_<sha8 of ref>`); the token came from `CLOUDFLARE_API_TOKEN`.
No token and no account id appear here or in any log: the URL rides curl's stdin config,
so it never reaches argv either.

Input: `{"point":"wrap-7b","questions":[{"id":"q1","candidate":"board-sync","hit":"board","existing":"enhance"}]}`

Output:

```
{"backend":"clef","model":"clef","latency_ms":1480,"mode":"shadow","answers":{"q1":{"choice":"enhance","probs":{"enhance":0.6271,"new":0.2878,"none":0.0851},"margin":0.3393}},"error":"","counts":{"answered":1,"denied":0,"error":0}}
```

The decision log line for the same call (throwaway log dir, no token, no account id):

```
{"ts":"2026-10-04T04:13:25Z","backend":"clef","model":"clef","point":"wrap-7b","index":0,"latency_ms":1480,"candidate":"board-sync","hit":"board","chosen":"enhance","existing":"enhance","margin":0.3393,"error":"","mode":"shadow","mode_downgraded":false}
```

## NEGATIVE CONTROL

`tests/test-flick.sh` (with the new clef section) run against `origin/master`'s
`lib/decide/flick.sh`, placed in a `rsync`ed temp copy of the worktree; the worktree itself
was never touched. `origin/master` does not recognise `clef`, so every clef assertion fell
back to `backend_none`.

Output tail:

```
flick: 304 passed, 22 failed
```

All 22 failures are in the new `== clef backend ==` section (every one reporting
`"error":"backend_none"`); every pre-existing section, including the Jev byte-compat
assertions, stayed green.

Result: RED as expected

Verdict: PASS
