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

**Every fetch pins to a host. There is no cross-host mode.** `fetch_ex` derives the pin from the
requested URL when the caller names none, so an unpinned fetch is not expressible; a caller that
handles remote content narrows the pin to the AUDITED host instead. A refused redirect surfaces
as its own 3xx, which is the finding.

This matters beyond the derived URLs. The audited site controls its own robots.txt, sitemap.xml,
llms.txt, homepage, and `/openapi.json` responses, so a 302 on any of them would otherwise walk
the auditor onto localhost or the LAN and print the response into the report. Every guard below
has a named test in `tests/test_webcheck.py`.

| Invariant | Mechanism | Test |
|---|---|---|
| every fetch pins, defaulting to the requested URL's own host | `fetch_ex` derives `pin` when `allowed_host` is None | `test_fetch_ex_defaults_the_pin_to_the_requested_host`, `test_fetch_ex_pin_can_be_narrowed_to_the_audited_host` |
| every groundwork and openapi fetch pins to the audited host | the same default, applied to the tier's own requests | `test_every_groundwork_fetch_pins_to_the_audited_host`, `test_openapi_spec_fetch_pins_to_the_audited_host` |
| a non-http(s) URL never reaches a request | `fetchable` gate at the top of `fetch_ex` | `test_fetch_ex_refuses_a_non_http_scheme_before_requesting`, `test_fetchable_predicate_covers_scheme_and_host` |
| a page fetch surfaces an off-host redirect instead of following it | `_SameHostRedirectHandler` | `test_page_fetch_surfaces_an_offhost_redirect_instead_of_following`, `test_same_host_redirect_handler_refuses_offhost` |
| a sitemap never fans out off the audited host, nor to a non-http scheme | `same_host_urls` splits on `fetchable` before the loop | `test_same_host_urls_splits_on_host`, `test_same_host_urls_refuses_a_non_http_scheme_on_the_right_host` |
| the unknown-path probe reads the 3xx itself, never the target | `fetch_ex(follow_redirects=False)` | `test_unknown_path_redirect_is_not_followed` |
| the API reachability and error probes never follow a redirect | `fetch_ex(follow_redirects=False)` | `test_reach_probe_never_follows_redirects` |
| a derived API base off the audited host is recorded, never fetched | `_probe_allowed` | `test_off_host_server_is_recorded_but_never_fetched` |
| a non-http scheme in a derived base is never fetched | `_probe_allowed` scheme check | `test_non_http_scheme_base_is_never_fetched` |
| sitemap XML declaring a DOCTYPE or ENTITY is refused, never parsed, wherever the declaration sits | whole-body scan in `parse_sitemap` | `test_sitemap_parser_refuses_doctype`, `test_sitemap_doctype_is_refused_even_behind_a_padded_prolog` |
| a derived API base that is empty or falsy cannot skip the guard | the guard is evaluated first, not `and`-ed after the value | `test_empty_servers_entry_does_not_skip_the_probe_guard` |
| a response body cannot exhaust the auditor | `resp.read(MAX_BODY_BYTES)` on both the success and the HTTPError path | `test_body_read_is_capped` |
| a URL carrying control characters returns a miss, never a traceback | `Request()` inside the try, `ValueError` and `HTTPException` caught | `test_fetch_ex_survives_a_url_with_control_characters` |
| a consumer-declared entry that is not an http(s) URL is refused, never fetched | `fetchable` in `declared_sites` | `test_declared_sites_refuses_a_non_http_entry`, `test_sites_verb_reports_a_refused_entry_and_stays_green` |
| the audited site cannot forge report lines | every remote-derived string prints through `!r` | `test_report_cannot_be_forged_by_a_canonical_carrying_a_newline` |

The XML guard is a refusal rather than a hardened parser on purpose: stdlib `xml.etree` is
vulnerable to XXE and entity expansion, and `defusedxml` would add a dependency this module does
not carry. A real sitemap never declares a DOCTYPE, so the scan covers the whole body rather
than a head window; a window is bypassable, because XML comments are legal in the prolog.

The report-forgery guard exists because the saved output is the evidence a Tier-2 scanner
judges. Titles, canonicals, server URLs, and error fields all come from the audited site, so
printing one raw would let that site write its own verdict line into its own audit.

## Constraints

- Stdlib only. No dependency, no packaging metadata, no virtualenv.
- Read-only. Every request is a GET. The tool sends no credential and writes nothing outside stdout.
- No tenant data. No hostname, no site list, no question bank ships in this module. `WEB_DRIFT_SITES` is the consumer's, with no default.

## Tests

`bash tests/test-webcheck.sh` from the kit root (pytest via uv), or `python3
lib/webcheck/tests/test_webcheck.py` standalone with no pytest installed. Both run the same
functions; the standalone runner derives its roster from the module's own `test_*` names, so a
new test needs no registration.
