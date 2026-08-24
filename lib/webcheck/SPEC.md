# webcheck: tool contract

What the tool guarantees to whoever edits `core.py`. The cycle spec that graduated it is
`docs/specs/SPEC-232-web-drift.md`; the skill that drives it is `skills/web-drift/SKILL.md`.

## Surface

```
python3 lib/webcheck/webcheck.py sites
python3 lib/webcheck/webcheck.py audit <url|sitemap-url> [--limit N] [--skip-groundwork]
```

`audit` exits 1 when any tier reports a hard fail, 0 otherwise. Warnings never move the exit
code: a warning is a judgment call the skill's verdict mapping resolves, not a failure.
`sites` always exits 0.

## Hard fail vs warning

A hard fail means an agent cannot do the job at all: the page did not answer, it carries no
title, no h1, or under 500 visible characters without JavaScript; robots, sitemap, or llms.txt
did not answer 200; an unknown path answered anything but 404 or 410; markdown was negotiated
without a `Vary` that includes `Accept`; a declared API surface serves a broken spec, an
unreachable canonical server, or a non-JSON error body.

A warning means an agent can proceed but reads less: metadata length, a duplicated site-default
meta description, more than one h1, a missing canonical, missing OG or Twitter tags, missing or
non-Article JSON-LD, a missing or incomplete Organization block, too few internal links, an
llms.txt that carries no orientation section, a missing rate-limit header, an unversioned API
base with no stated deprecation policy.

## The three tiers

| Tier | Entry | Applies |
|---|---|---|
| groundwork | `audit_groundwork(base_url)` | always, once per run, on the first URL |
| api | `audit_api(base_url, llms_text)` | only on evidence: `/openapi.json` answers 200 with JSON, or llms.txt names an API base. Otherwise it reports not-applicable and drops out of the denominator. |
| page | `audit_page(url, homepage_meta_desc, pin_host)` | once per audited URL |

Request budget: groundwork spends five (robots, sitemap, llms.txt, unknown path, markdown
negotiation) plus one for the homepage meta description. The API tier spends one when it does
not activate, at most three when it does. Each page spends one.

## SSRF invariants (do not weaken without a spec)

The tool follows URLs that arrive from remote content: sitemap `<loc>` entries, openapi
`servers[0]`, an API base named in llms.txt. Each of those is attacker-controlled if the audited
site is hostile, so each has a guard. Every guard has a named test in `tests/test_webcheck.py`.

| Invariant | Mechanism | Test |
|---|---|---|
| a sitemap-sourced page fetch never leaves its host | `_SameHostRedirectHandler` via `audit_page(pin_host=True)` | `test_pinned_page_fetch_refuses_offhost_redirect`, `test_same_host_redirect_handler_refuses_offhost` |
| a sitemap never fans out off the audited host | `same_host_urls` splits before the loop | `test_same_host_urls_splits_on_host` |
| the unknown-path probe reads the 3xx itself, never the target | `fetch_ex(follow_redirects=False)` | `test_unknown_path_redirect_is_not_followed` |
| the API reachability and error probes never follow a redirect | `fetch_ex(follow_redirects=False)` | `test_reach_probe_never_follows_redirects` |
| a derived API base off the audited host is recorded, never fetched | `_probe_allowed` | `test_off_host_server_is_recorded_but_never_fetched` |
| a non-http scheme in a derived base is never fetched | `_probe_allowed` scheme check | `test_non_http_scheme_base_is_never_fetched` |
| sitemap XML declaring a DOCTYPE or ENTITY is refused, never parsed | head scan in `parse_sitemap` | `test_sitemap_parser_refuses_doctype` |

The XML guard is a refusal rather than a hardened parser on purpose: stdlib `xml.etree` is
vulnerable to XXE and entity expansion, and `defusedxml` would add a dependency this module does
not carry. A real sitemap never declares a DOCTYPE.

## Constraints

- Stdlib only. No dependency, no packaging metadata, no virtualenv.
- Read-only. Every request is a GET. The tool sends no credential and writes nothing outside stdout.
- No tenant data. No hostname, no site list, no question bank ships in this module. `WEB_DRIFT_SITES` is the consumer's, with no default.

## Tests

`bash tests/test-webcheck.sh` from the kit root (pytest via uv), or `python3
lib/webcheck/tests/test_webcheck.py` standalone with no pytest installed. Both run the same
functions; the standalone runner derives its roster from the module's own `test_*` names, so a
new test needs no registration.
