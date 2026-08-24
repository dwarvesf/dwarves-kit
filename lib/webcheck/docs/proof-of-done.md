# Proof of done: webcheck + kit:web-drift

Spec: `docs/specs/SPEC-232-web-drift.md`. Run id: `web-drift`. Lane: full.
Host: macOS 25.5, Python 3.13, `uv` for pytest. Date: 2026-08-24.

## Green run

| # | Claim | Command | Result |
|---|---|---|---|
| 1 | the suite passes under pytest | `bash tests/test-webcheck.sh` | `81 passed in 0.24s`, exit 0 |
| 2 | the same suite passes standalone with no pytest installed | `python3 lib/webcheck/tests/test_webcheck.py` | `PASSED 81/81`, exit 0 |
| 3 | 61 of the origin's 71 tests ported; the 10 geo tests stayed | origin `grep -c '^def test_'` = 71, of which 10 import `geo` | 81 = 61 ported + 5 resolver + 15 hardening regressions |
| 4 | `sites` is inert and green when the knob is unset | `env -u WEB_DRIFT_SITES python3 lib/webcheck/webcheck.py sites` | prints the documented message, exit 0, no URL |
| 5 | `sites` lists what the consumer declared | `WEB_DRIFT_SITES='https://example.com, https://docs.example.com' python3 lib/webcheck/webcheck.py sites` | two lines, one URL each, exit 0 |
| 6 | a live site with all three tiers clean audits clean | `python3 lib/webcheck/webcheck.py audit https://memo.d.foundation --limit 1` | groundwork ok, api tier ok, 0 hard fails, 5 warnings, exit 0 |
| 7 | a live site with no API surface reports the tier not-applicable rather than failing | `python3 lib/webcheck/webcheck.py audit https://dwarves.foundation --limit 1` | groundwork ok, api tier n/a, 0 hard fails, 4 warnings, exit 0 |
| 8 | the branch adds no new kit-contract offender | `bash tests/test-kit-contract.sh` | C3/C4 offenders are `lib/bench/SPEC` and `lib/bench`, identical to the pre-branch baseline |
| 9 | the branch adds no new meta failure and closes one | `bash tests/test-meta.sh` | baseline 807/814 with 7 failures; after 809/815 with 6. `docs/FEATURES.md is fresh` went green; nothing new went red |
| 10 | no operator path or hostname ships | `bash tests/test-no-personal-paths.sh` | `Passed: 3 / 3`, exit 0 |
| 11 | the SSRF the port inherited is closed | reviewer's two-loopback-server repro (`scratchpad/ssrf_demo.py`), before and after | before: `paths reached on the INTERNAL host: ['/internal/robots.txt', '/internal/sitemap.xml', '/internal/llms.txt', '/internal/', '/internal/', '/internal/openapi.json']` and the internal banner printed as `info.title`. After: `paths reached on the INTERNAL host: []`, every tier reporting the refused `302`. |
| 12 | no tenant hostname ships inside the module | `grep -rn 'd\.foundation' lib/webcheck skills/web-drift` | only `docs/proof-of-done.md`, which is the recorded live-run evidence |

### Run 6 transcript (memo.d.foundation)

```
=== groundwork: memo.d.foundation ===
  robots.txt      : 200 (Sitemap: directive=yes)
  sitemap.xml     : 200
  llms.txt        : 200 (agent guidance=yes)
  unknown path    : 404 (points agent somewhere=yes) https://memo.d.foundation/573621fbdc5a-does-not-exist-573621fbdc5a
  markdown accept : text/markdown; charset=utf-8 (markdown=yes, Vary=accept)

=== api tier: memo.d.foundation ===
  openapi.json    : 200 version=3.1.0 title='Dwarves Memo API' paths=13
  servers         : ['https://memo.d.foundation/api/v1', 'https://memo.d.foundation/api']
  base            : https://memo.d.foundation/api/v1 (from openapi servers[0])
  reachability    : 200 https://memo.d.foundation/api/v1/memos
  json errors     : 404 json=True error field=error https://memo.d.foundation/api/v1/nope-9ea02983
  rate limit      : ratelimit, ratelimit-limit, ratelimit-policy, ratelimit-remaining, ratelimit-reset
  versioned base  : True (deprecation policy documented=True)
  llms developer  : True

=== https://memo.d.foundation ===
  title           : 'Dwarves Memo - Home' (len=19)
  meta description: 'Knowledge sharing platform for Dwarves Foundation' (len=49)
  h1 count        : 1
  visible text    : 2445 chars (no JavaScript)
  canonical       : https://memo.d.foundation/
  og missing      : none
  twitter missing : ['twitter:card']
  json-ld         : found=True types=['Organization'] datePublished=False dateModified=False
  organization    : found=True missing=[]
  internal links  : 61
  warn            : meta description length 49 outside 150-160
  warn            : meta description same as site default (homepage)
  warn            : missing Twitter card tags: twitter:card
  warn            : JSON-LD @type ['Organization'] not Article-shaped
  warn            : JSON-LD missing datePublished

SUMMARY: 1 URL(s) audited, 0 page hard fail(s), 5 warning(s), groundwork ok, api tier ok.
EXIT=0
```

### Run 7 transcript (dwarves.foundation)

```
=== groundwork: dwarves.foundation ===
  robots.txt      : 200 (Sitemap: directive=yes)
  sitemap.xml     : 200
  llms.txt        : 200 (agent guidance=yes)
  unknown path    : 404 (points agent somewhere=yes) https://dwarves.foundation/59d1f2ee0cca-does-not-exist-59d1f2ee0cca
  markdown accept : text/html; charset=utf-8 (markdown=no, Vary=n/a)

=== api tier: dwarves.foundation ===
  not applicable  : no JSON at /openapi.json (status=404) and no API base URL in llms.txt

=== https://dwarves.foundation ===
  title           : 'Dwarves Foundation - We build software with Go, React, K8s, Swift and Flutter' (len=77)
  meta description: 'A software development firm based in Asia. Helping tech startups, entrepreneurs and makers build world-class products since 2013.' (len=129)
  h1 count        : 1
  visible text    : 4054 chars (no JavaScript)
  canonical       : https://dwarves.foundation/
  og missing      : none
  twitter missing : none
  json-ld         : found=True types=['Organization'] datePublished=False dateModified=False
  organization    : found=True missing=[]
  internal links  : 52
  warn            : meta description length 129 outside 150-160
  warn            : meta description same as site default (homepage)
  warn            : JSON-LD @type ['Organization'] not Article-shaped
  warn            : JSON-LD missing datePublished

SUMMARY: 1 URL(s) audited, 0 page hard fail(s), 4 warning(s), groundwork ok, api tier n/a.
EXIT=0
```

Both runs exercise the API tier's two branches: memo activates it and passes every check,
dwarves.foundation has no API surface and the tier drops out of the denominator rather than
failing. That is the not-applicable rule working on live evidence, not a fixture.

## Negative control

Two controls, because the SSRF defense has two parts and each must be shown load-bearing on
its own. The branch is committed first, so a control run cannot lose the real code (`d0fc645`).

**Control A, the handler.** Replace the body of `_SameHostRedirectHandler.redirect_request`
with a bare `return super().redirect_request(...)`.

```
FAILED lib/webcheck/tests/test_webcheck.py::test_same_host_redirect_handler_refuses_offhost
1 failed, 80 passed in 0.35s
```

**Control B, the default pin.** This is the one that matters for the reported bug: the handler
class was always correct, the hole was that `fetch_ex` installed it only when a caller passed
`allowed_host`. Replace `pin = allowed_host or urlparse(url).netloc` with `pin = allowed_host`.

```
FAILED test_same_host_redirect_handler_refuses_offhost
FAILED test_every_groundwork_fetch_pins_to_the_audited_host
FAILED test_openapi_spec_fetch_pins_to_the_audited_host
FAILED test_fetch_ex_defaults_the_pin_to_the_requested_host
FAILED test_fetch_ex_survives_a_url_with_control_characters
FAILED test_body_read_is_capped
6 failed, 75 passed in 0.14s
```

Control B is the meaningful one: reverting only the default pin turns exactly the tests that
encode the fixed invariant red, and leaves the other 75 green. Control A alone would have
passed on the vulnerable code, which is why the pre-fix suite reported a green 66.

**Restore.** `git checkout -- lib/webcheck/core.py`, working tree clean, `81 passed in 0.24s`.

## Reproducible

```bash
cd <kit root>
bash tests/test-webcheck.sh
python3 lib/webcheck/tests/test_webcheck.py
env -u WEB_DRIFT_SITES python3 lib/webcheck/webcheck.py sites
python3 lib/webcheck/webcheck.py audit https://<your-site> --limit 1
```

Every test is offline: each fetch is monkeypatched, and the suite makes no network call. Only
the two live runs above touch the network, and both are read-only GETs.

## Not attempted

- No cadence run, no scheduled job. The skill is invoked, not scheduled.
- No site was fixed and no board row was filed. This branch ships the loop, not a run of it.
- `docs/architecture.md`'s inventory count, the `devops-triage` MANUAL gap, and the two config-registry orphans stay red exactly as they were on master. They belong to other work.
