#!/usr/bin/env python3
"""Offline checks for lib/webcheck (no network).

Run: bash tests/test-webcheck.sh from the kit root, or `pytest lib/webcheck/tests` .
Ported from ops-toolkit tools/seo-geo-check; the geo-probe half stayed behind
(see docs/implementation-notes/SPEC-232-web-drift.md).
"""
import inspect
import io
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import core  # noqa: E402
import webcheck  # noqa: E402

GOOD_HTML = """
<html><head>
<title>How We Cut Claude Code Token Cost 38%</title>
<meta name="description" content="A 150-160 char meta description that is written specifically for this post, not copy-pasted from the site homepage default text, ok.">
<link rel="canonical" href="https://docs.example.com/posts/token-cost/">
<meta property="og:title" content="How We Cut Token Cost">
<meta property="og:description" content="desc">
<meta property="og:image" content="https://docs.example.com/img.png">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">
{"@type": "TechArticle", "datePublished": "2026-07-01", "dateModified": "2026-07-15"}
</script>
<script type="application/ld+json">
{"@type": "Organization", "name": "Example Org",
 "contactPoint": {"@type": "ContactPoint", "email": "team@example.com"},
 "address": {"@type": "PostalAddress", "addressLocality": "Da Nang"},
 "sameAs": ["https://github.com/example-org"]}
</script>
</head>
<body>
<h1>How We Cut Claude Code Token Cost 38%</h1>
<p>Cache reads were the largest single slice of our Claude Code spend, so we measured every
session for a month before changing anything. The measurement said the mega-session was the
problem: one long context re-read on every turn, paid for again and again. Splitting work at
natural boundaries, clearing between unrelated tasks, and dispatching fresh-context subagents
for fan-out cut the bill by roughly a third without changing what any of the agents actually
did. The rest of this post walks through the measurement, the three changes, and the numbers
each one moved, plus the two changes that looked promising on paper and moved nothing at all
once we ran them against a real week of sessions.</p>
<p>See also <a href="/posts/other-post/">this post</a> and <a href="/posts/third/">this one</a>.</p>
<a href="https://external.example.com/">external</a>
</body></html>
"""

BROKEN_HTML = """
<html><head></head><body><p>No title, no meta, no h1.</p></body></html>
"""

SVG_TITLE_HTML = """
<html><head>
<title>Clean Head Title</title>
</head>
<body>
<h1>Clean Head Title</h1>
<svg viewBox="0 0 100 100"><title>chart tooltip: revenue by quarter</title><circle cx="50" cy="50" r="40"/></svg>
</body></html>
"""


def test_page_parser_extracts_the_basics():
    p = core.PageParser()
    p.feed(GOOD_HTML)
    assert p.title == "How We Cut Claude Code Token Cost 38%"
    assert p.h1_count == 1
    assert p.canonical == "https://docs.example.com/posts/token-cost/"
    assert p.meta_content("name", "description") is not None
    assert p.meta_content("property", "og:title") == "How We Cut Token Cost"
    assert len(p.ld_json_blocks) == 2  # the TechArticle block and the Organization block


def test_title_ignores_svg_title_element():
    p = core.PageParser()
    p.feed(SVG_TITLE_HTML)
    assert p.title == "Clean Head Title"


def test_jsonld_extraction():
    p = core.PageParser()
    p.feed(GOOD_HTML)
    info = core.extract_jsonld(p.ld_json_blocks)
    assert info.found is True
    assert "TechArticle" in info.types
    assert info.has_date_published is True
    assert info.has_date_modified is True


def test_internal_link_count_excludes_external_and_self():
    p = core.PageParser()
    p.feed(GOOD_HTML)
    n = core.count_internal_links("https://docs.example.com/posts/token-cost/", p.links)
    assert n == 2  # the two /posts/ links; external.example.com excluded


def test_audit_page_good_html_has_no_hard_fails(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, GOOD_HTML.encode()))
    result = core.audit_page("https://docs.example.com/posts/token-cost/", homepage_meta_desc=None)
    assert result.hard_fails == []
    assert result.h1_count == 1


def test_audit_page_broken_html_flags_hard_fails(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, BROKEN_HTML.encode()))
    result = core.audit_page("https://example.com/broken/", homepage_meta_desc=None)
    assert "missing <title>" in result.hard_fails
    assert "missing meta description" in result.hard_fails
    assert "missing <h1>" in result.hard_fails


def test_meta_description_flagged_when_same_as_homepage(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, GOOD_HTML.encode()))
    p = core.PageParser()
    p.feed(GOOD_HTML)
    homepage_desc = p.meta_content("name", "description")
    result = core.audit_page("https://docs.example.com/posts/token-cost/", homepage_meta_desc=homepage_desc)
    assert result.meta_same_as_homepage is True
    assert any("same as site default" in w for w in result.warnings)


GOOD_LLMS_TXT = b"""# example.com

## When to use this site
Ask about our Go and Elixir engineering write-ups.

- [Token cost](https://example.com/posts/token-cost/)
"""

BARE_LLMS_TXT = b"""# example.com

- [Token cost](https://example.com/posts/token-cost/)
- [Another post](https://example.com/posts/other/)
"""


def _stub_site(
    monkeypatch,
    *,
    llms=(200, GOOD_LLMS_TXT),
    sitemap_status=200,
    unknown=(404, b'not found. try <a href="/sitemap.xml">the sitemap</a>'),
    md_headers=None,
):
    """Patch the whole network layer with an in-memory site. Every groundwork request routes
    through `fetch_ex` (`fetch` is a wrapper over it), so one stub covers both."""
    headers = md_headers if md_headers is not None else {"content-type": "text/html; charset=utf-8"}

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        if accept == "text/markdown":
            return 200, b"", dict(headers)
        if "does-not-exist" in url:
            return unknown[0], unknown[1], {}
        if url.endswith("/robots.txt"):
            return 200, b"User-agent: *\nSitemap: https://example.com/sitemap.xml\n", {}
        if url.endswith("/sitemap.xml"):
            return sitemap_status, b'<?xml version="1.0"?><urlset></urlset>', {}
        if url.endswith("/llms.txt"):
            return llms[0], llms[1], {}
        return 200, b"<html><head></head><body></body></html>", {}

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: fake_fetch_ex(url)[:2])


def test_groundwork_hard_fails_on_404(monkeypatch):
    _stub_site(monkeypatch, sitemap_status=404, llms=(404, b""))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.robots_has_sitemap_directive is True
    assert any("sitemap.xml" in f for f in g.hard_fails)
    assert any("llms.txt" in f for f in g.hard_fails)


# --- check 1: unknown-path 404 behaviour ---


def test_unknown_path_soft_200_is_a_hard_fail(monkeypatch):
    """docs.example.com answered 200 with the homepage shell for every unknown path."""
    _stub_site(monkeypatch, unknown=(200, b"<html><body>full homepage shell</body></html>"))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.unknown_path_status == 200
    assert any("unknown path answered 200" in f for f in g.hard_fails)


def test_unknown_path_404_is_clean(monkeypatch):
    _stub_site(monkeypatch)
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.unknown_path_status == 404
    assert g.unknown_path_points_agent is True
    assert not any("unknown path" in f for f in g.hard_fails)
    assert not any("routes an agent nowhere" in w for w in g.warnings)


def test_unknown_path_410_also_passes(monkeypatch):
    _stub_site(monkeypatch, unknown=(410, b"gone, see /llms.txt"))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert not any("unknown path" in f for f in g.hard_fails)


def test_unknown_path_404_without_pointers_warns(monkeypatch):
    _stub_site(monkeypatch, unknown=(404, b"<html><body>Not Found</body></html>"))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.unknown_path_points_agent is False
    assert not any("unknown path" in f for f in g.hard_fails)
    assert any("routes an agent nowhere" in w for w in g.warnings)


def test_unknown_path_redirect_is_not_followed(monkeypatch):
    """A 302 to the homepage must report as 302, not as the homepage's 200."""
    seen = {}

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        if "does-not-exist" in url:
            seen["follow_redirects"] = follow_redirects
            return 302, b"", {"location": "/"}
        if accept == "text/markdown":
            return 200, b"", {"content-type": "text/html"}
        if url.endswith("/llms.txt"):
            return 200, GOOD_LLMS_TXT, {}
        return 200, b"", {}

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: fake_fetch_ex(url)[:2])
    g = core.audit_groundwork("https://example.com/some-post/")
    assert seen["follow_redirects"] is False
    assert g.unknown_path_status == 302
    assert any("unknown path answered 302" in f for f in g.hard_fails)


# --- check 3: markdown content negotiation and Vary ---


def test_markdown_without_vary_accept_is_a_hard_fail(monkeypatch):
    _stub_site(monkeypatch, md_headers={"content-type": "text/markdown", "vary": "Accept-Encoding"})
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.markdown_negotiated is True
    assert any("Vary" in f for f in g.hard_fails)


def test_markdown_with_vary_accept_passes(monkeypatch):
    _stub_site(monkeypatch, md_headers={"content-type": "text/markdown; charset=utf-8", "vary": "Accept, Accept-Encoding"})
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.markdown_negotiated is True
    assert g.hard_fails == []


def test_no_markdown_negotiation_is_informational(monkeypatch):
    _stub_site(monkeypatch, md_headers={"content-type": "text/html; charset=utf-8"})
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.markdown_negotiated is False
    assert g.hard_fails == []
    assert not any("Vary" in w for w in g.warnings)


def test_vary_includes_accept_is_token_aware():
    assert core.vary_includes_accept("Accept") is True
    assert core.vary_includes_accept("accept, accept-encoding") is True
    assert core.vary_includes_accept("*") is True
    assert core.vary_includes_accept("Accept-Encoding") is False
    assert core.vary_includes_accept(None) is False


# --- check 4: llms.txt guidance, not just reachability ---


def test_llms_txt_bare_link_index_warns(monkeypatch):
    _stub_site(monkeypatch, llms=(200, BARE_LLMS_TXT))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.llms_status == 200
    assert g.llms_has_guidance is False
    assert any("no agent guidance" in w for w in g.warnings)
    assert not any("llms.txt" in f for f in g.hard_fails)


def test_llms_txt_with_guidance_does_not_warn(monkeypatch):
    _stub_site(monkeypatch, llms=(200, GOOD_LLMS_TXT))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert g.llms_has_guidance is True
    assert not any("no agent guidance" in w for w in g.warnings)


# --- check 2: content without JavaScript ---

JS_GATED_HTML = """
<html><head>
<title>Example Org</title>
<meta name="description" content="A 150-160 char meta description that is written specifically for this post, not copy-pasted from the site homepage default text, ok.">
</head>
<body>
<div id="root"></div>
<noscript>You need JavaScript to view this site.</noscript>
<script>window.__DATA__ = "%s";</script>
<style>.a{color:red}.b{color:blue}</style>
</body></html>
""" % ("x" * 4000)


def test_visible_text_excludes_script_style_noscript():
    p = core.PageParser()
    p.feed(JS_GATED_HTML)
    assert len(JS_GATED_HTML) > 4000
    assert "xxxx" not in p.visible_text
    assert "You need JavaScript" not in p.visible_text
    assert len(p.visible_text) < core.MIN_VISIBLE_TEXT_CHARS


def test_js_gated_page_hard_fails_on_visible_text(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, JS_GATED_HTML.encode()))
    result = core.audit_page("https://example.com/", homepage_meta_desc=None)
    assert any("visible text characters without JavaScript" in f for f in result.hard_fails)


def test_server_rendered_page_clears_the_visible_text_floor(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, GOOD_HTML.encode()))
    result = core.audit_page("https://docs.example.com/posts/token-cost/", homepage_meta_desc=None)
    assert result.visible_text_len >= core.MIN_VISIBLE_TEXT_CHARS
    assert not any("visible text" in f for f in result.hard_fails)


# --- check 5: Organization JSON-LD completeness ---

ORG_PARTIAL_HTML = """
<html><head><title>t</title>
<script type="application/ld+json">
{"@type": "Organization", "name": "Dwarves", "sameAs": ["https://github.com/example-org"]}
</script>
</head><body><h1>t</h1></body></html>
"""

ORG_NESTED_HTML = """
<html><head><title>t</title>
<script type="application/ld+json">
{"@type": "Article", "publisher": {"@type": "Organization", "name": "Dwarves",
 "contactPoint": {"email": "x@example.com"}, "address": "Da Nang", "sameAs": ["https://x.example"]}}
</script>
</head><body><h1>t</h1></body></html>
"""


def test_organization_completeness_reports_missing_fields():
    p = core.PageParser()
    p.feed(ORG_PARTIAL_HTML)
    info = core.extract_jsonld(p.ld_json_blocks)
    assert info.has_organization is True
    assert info.organization_missing == ["contactPoint", "address"]


def test_nested_organization_is_found_without_changing_the_type_verdict():
    p = core.PageParser()
    p.feed(ORG_NESTED_HTML)
    info = core.extract_jsonld(p.ld_json_blocks)
    assert info.has_organization is True
    assert info.organization_missing == []
    assert info.types == {"Article"}  # the nested Organization must not pollute @type


def test_complete_organization_raises_no_warning(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, GOOD_HTML.encode()))
    result = core.audit_page("https://docs.example.com/posts/token-cost/", homepage_meta_desc=None)
    assert result.jsonld.has_organization is True
    assert not any("Organization" in w for w in result.warnings)


def test_missing_organization_warns_once_and_never_hard_fails(monkeypatch):
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, ORG_NESTED_HTML.replace("Organization", "Person").encode()))
    result = core.audit_page("https://example.com/p/", homepage_meta_desc=None)
    org_warnings = [w for w in result.warnings if "Organization" in w]
    assert org_warnings == ["no Organization JSON-LD block on the page"]
    assert not any("Organization" in f for f in result.hard_fails)


def test_sitemap_detection_and_parse():
    body = (
        b'<?xml version="1.0" encoding="UTF-8"?>'
        b'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        b"<url><loc>https://example.com/a/</loc></url>"
        b"<url><loc>https://example.com/b/</loc></url>"
        b"</urlset>"
    )
    assert core.looks_like_sitemap(body) is True
    urls = core.parse_sitemap(body, limit=1)
    assert urls == ["https://example.com/a/"]


def test_sitemap_parser_refuses_doctype():
    body = b'<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY x "y">]><urlset></urlset>'
    try:
        core.parse_sitemap(body, limit=20)
        raised = False
    except ValueError:
        raised = True
    assert raised is True


# --- API tier: activation, and the five checks it runs when active ---

GOOD_OPENAPI = {
    "openapi": "3.1.0",
    "info": {
        "title": "Example Docs API",
        "description": "Public HTTP surface. Deprecation policy: a version stays for 12 months.",
    },
    "servers": [{"url": "https://example.com/api/v1"}, {"url": "https://example.com/api"}],
    "paths": {
        "/search": {"get": {"parameters": [{"name": "q", "required": True}]}},
        "/memos": {"get": {"parameters": [{"name": "limit", "required": False}]}},
        "/tag/{tag}": {"get": {"parameters": [{"name": "tag", "required": True}]}},
    },
}

LLMS_WITH_API = b"""# example.com

## When to use this site
Ask about our engineering write-ups.

## Developer resources
The API lives at https://example.com/api/v1 and the spec at https://example.com/openapi.json.
"""

LLMS_NO_API = b"""# example.com

## When to use this site
Ask about our engineering write-ups.
"""

RATE_LIMIT_HEADERS_LIVE = {
    "ratelimit": '"public-api";r=599;t=27',
    "ratelimit-limit": "600",
    "ratelimit-remaining": "599",
}


def _stub_api(
    monkeypatch,
    *,
    spec=None,
    spec_status=200,
    spec_body=None,
    unrouted=(404, b'{"error":"no such API route"}'),
    endpoint_headers=None,
    calls=None,
):
    """In-memory API surface. Everything routes through `fetch_ex`, the same seam the
    groundwork stub uses, so no test touches the network."""
    body = spec_body if spec_body is not None else json.dumps(spec if spec is not None else GOOD_OPENAPI).encode()
    headers = RATE_LIMIT_HEADERS_LIVE if endpoint_headers is None else endpoint_headers

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        if calls is not None:
            calls.append(url)
        if url.endswith("/openapi.json"):
            return spec_status, body, {"content-type": "application/json"}
        if "/nope-" in url:
            return unrouted[0], unrouted[1], {}
        return 200, b'{"data":[]}', dict(headers)

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)


def test_api_tier_skipped_when_no_evidence(monkeypatch):
    """A site with no API surface. The tier must report not-applicable, never failures."""
    _stub_api(monkeypatch, spec_status=404, spec_body=b"<html>not found</html>")
    a = core.audit_api("https://example.com/some-post/", LLMS_NO_API.decode())
    assert a.applicable is False
    assert a.hard_fails == []
    assert a.warnings == []
    assert "no API base URL in llms.txt" in a.skip_reason


def test_api_tier_activates_on_openapi_json(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.applicable is True
    assert a.base_source == "openapi servers[0]"


def test_api_tier_activates_on_llms_api_base_without_spec(monkeypatch):
    """Evidence of an API but no spec to read it by: openapi-valid is the hard fail."""
    _stub_api(monkeypatch, spec_status=404, spec_body=b"<html>not found</html>")
    a = core.audit_api("https://example.com/some-post/", LLMS_WITH_API.decode())
    assert a.applicable is True
    assert a.base_url == "https://example.com/api/v1"
    assert any("serves no JSON" in f for f in a.hard_fails)


def test_api_tier_detection_costs_one_request_when_skipped(monkeypatch):
    calls = []
    _stub_api(monkeypatch, spec_status=404, spec_body=b"nope", calls=calls)
    core.audit_api("https://example.com/some-post/", LLMS_NO_API.decode())
    assert calls == ["https://example.com/openapi.json"]


def test_api_tier_active_stays_within_three_requests(monkeypatch):
    calls = []
    _stub_api(monkeypatch, calls=calls)
    core.audit_api("https://example.com/some-post/", LLMS_WITH_API.decode())
    assert len(calls) <= 3, calls


# check 1: openapi-valid


def test_openapi_valid_passes_on_a_well_formed_spec(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", LLMS_WITH_API.decode())
    assert a.openapi_version == "3.1.0"
    assert a.info_title == "Example Docs API"
    assert a.path_count == 3
    assert a.servers[0] == "https://example.com/api/v1"
    assert a.reach_status == 200
    assert a.hard_fails == []


def test_openapi_swagger_2_and_missing_pieces_hard_fail(monkeypatch):
    _stub_api(monkeypatch, spec={"swagger": "2.0", "paths": {}})
    a = core.audit_api("https://example.com/some-post/", "")
    assert any("not 3.x" in f for f in a.hard_fails)
    assert any("info.title" in f for f in a.hard_fails)
    assert any("documents no paths" in f for f in a.hard_fails)
    assert any("servers list" in f for f in a.hard_fails)


def test_openapi_body_that_is_not_json_does_not_activate(monkeypatch):
    _stub_api(monkeypatch, spec_body=b"<html>SPA shell</html>")
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.applicable is False


def test_probeable_get_path_skips_templates_and_required_params():
    assert core.first_probeable_get_path(GOOD_OPENAPI) == "/memos"
    only_required = {"paths": {"/search": {"get": {"parameters": [{"name": "q", "required": True}]}}}}
    assert core.first_probeable_get_path(only_required) is None


def test_unreachable_server_hard_fails(monkeypatch):
    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        if url.endswith("/openapi.json"):
            return 200, json.dumps(GOOD_OPENAPI).encode(), {}
        return None, b"", {}

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    a = core.audit_api("https://example.com/some-post/", "")
    assert any("unreachable" in f for f in a.hard_fails)


def test_page_fetch_surfaces_an_offhost_redirect_instead_of_following(monkeypatch):
    """A page URL may redirect only within its own host, whoever named the URL. The refused
    3xx becomes the finding rather than a silent hop onto another host."""
    calls = []

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT, allowed_host=None):
        calls.append((url, allowed_host))
        return 301, b"", {"location": "http://192.168.1.1/"}

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    a = core.audit_page("https://example.com/x", None)
    assert a.fetch_status == 301
    assert any("fetch failed" in f for f in a.hard_fails)


def test_same_host_redirect_handler_refuses_offhost():
    h = core._SameHostRedirectHandler("example.com")
    assert h.redirect_request(None, None, 301, "", {}, "http://10.0.0.1/") is None
    assert h.redirect_request(None, None, 301, "", {}, "file:///etc/passwd") is None


def test_same_host_urls_splits_on_host():
    on, off = core.same_host_urls(
        ["https://a.com/x", "http://192.168.1.1/", "https://a.com/y", "https://b.com/z"],
        "https://a.com/sitemap.xml",
    )
    assert on == ["https://a.com/x", "https://a.com/y"]
    assert off == ["http://192.168.1.1/", "https://b.com/z"]


def test_reach_probe_never_follows_redirects(monkeypatch):
    """The initial URL passes the same-host guard; a redirect is more remote
    content and must not be followed off-host."""
    seen = {}

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        if url.endswith("/openapi.json"):
            return 200, json.dumps(GOOD_OPENAPI).encode(), {}
        seen[url] = follow_redirects
        return 200, b"{}", {}

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    core.audit_api("https://example.com/", "")
    assert seen and all(v is False for v in seen.values())


def test_off_host_server_is_recorded_but_never_fetched(monkeypatch):
    """servers[0] is remote content; a hostile spec must not turn the audit into
    an internal port probe (the SSRF the push review flagged)."""
    evil = dict(GOOD_OPENAPI)
    evil["servers"] = [{"url": "http://169.254.169.254/api"}]
    fetched = []

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        fetched.append(url)
        if url.endswith("/openapi.json"):
            return 200, json.dumps(evil).encode(), {}
        raise AssertionError(f"probed a derived off-host URL: {url}")

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    a = core.audit_api("https://example.com/", "")
    assert a.base_url == "http://169.254.169.254/api"
    assert a.reach_status is None and a.error_probe_status is None
    assert any("not probed" in w for w in a.warnings)
    assert fetched == ["https://example.com/openapi.json"]


def test_non_http_scheme_base_is_never_fetched(monkeypatch):
    evil = dict(GOOD_OPENAPI)
    evil["servers"] = [{"url": "file:///etc/passwd"}]

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT):
        if url.endswith("/openapi.json"):
            return 200, json.dumps(evil).encode(), {}
        raise AssertionError(f"probed a non-http URL: {url}")

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    a = core.audit_api("https://example.com/", "")
    assert any("not probed" in w for w in a.warnings)


# check 2: api-json-errors


def test_unrouted_api_path_text_plain_is_a_hard_fail(monkeypatch):
    """memo's Hono default answered text/plain 404 until the API tier caught it."""
    _stub_api(monkeypatch, unrouted=(404, b"404 Not Found"))
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.error_probe_is_json is False
    assert any("non-JSON" in f for f in a.hard_fails)


def test_unrouted_api_path_json_without_error_field_is_a_hard_fail(monkeypatch):
    _stub_api(monkeypatch, unrouted=(404, b'{"status":404}'))
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.error_probe_is_json is True
    assert a.error_probe_error_field is None
    assert any("no error field" in f for f in a.hard_fails)


def test_unrouted_api_path_json_error_passes(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.error_probe_error_field == "error"
    assert a.hard_fails == []


def test_json_error_field_accepts_rfc7807_detail():
    assert core.json_error_field(b'{"title":"Not Found","detail":"no such route"}') == (True, "detail")
    assert core.json_error_field(b"not json at all") == (False, None)


# check 3: api-rate-limit-headers


def test_rate_limit_headers_present_do_not_warn(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", "")
    assert "ratelimit-limit" in a.rate_limit_found
    assert not any("RateLimit" in w for w in a.warnings)


def test_missing_rate_limit_headers_warn_but_never_hard_fail(monkeypatch):
    _stub_api(monkeypatch, endpoint_headers={"content-type": "application/json"})
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.rate_limit_found == []
    assert any("RateLimit" in w for w in a.warnings)
    assert a.hard_fails == []


def test_legacy_x_ratelimit_trio_counts(monkeypatch):
    _stub_api(monkeypatch, endpoint_headers={"x-ratelimit-limit": "60", "x-ratelimit-remaining": "59"})
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.rate_limit_found == ["x-ratelimit-limit", "x-ratelimit-remaining"]
    assert not any("RateLimit" in w for w in a.warnings)


def test_rate_limit_skipped_with_a_note_when_no_probeable_endpoint(monkeypatch):
    spec = dict(GOOD_OPENAPI, paths={"/search": {"get": {"parameters": [{"name": "q", "required": True}]}}})
    _stub_api(monkeypatch, spec=spec)
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.rate_limit_found == []
    assert "no documented GET path" in a.rate_limit_note
    assert not any("RateLimit" in w for w in a.warnings)


# check 4: api-versioned-base


def test_versioned_base_detected_in_server_url(monkeypatch):
    spec = dict(GOOD_OPENAPI, info={"title": "t", "description": "no policy stated"})
    _stub_api(monkeypatch, spec=spec)
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.versioned_base is True
    assert a.deprecation_policy is False
    assert not any("deprecation policy" in w for w in a.warnings)


def test_deprecation_policy_in_description_substitutes_for_a_version_segment(monkeypatch):
    spec = dict(GOOD_OPENAPI, servers=[{"url": "https://example.com/api"}])
    _stub_api(monkeypatch, spec=spec)
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.versioned_base is False
    assert a.deprecation_policy is True
    assert not any("deprecation policy" in w for w in a.warnings)


def test_unversioned_base_without_a_policy_warns(monkeypatch):
    spec = dict(GOOD_OPENAPI, servers=[{"url": "https://example.com/api"}], info={"title": "t", "description": "stable"})
    _stub_api(monkeypatch, spec=spec)
    a = core.audit_api("https://example.com/some-post/", "")
    assert any("deprecation policy" in w for w in a.warnings)
    assert a.hard_fails == []


def test_version_segment_matches_trailing_and_embedded_forms():
    assert core.VERSION_SEGMENT.search("/api/v1") is not None
    assert core.VERSION_SEGMENT.search("/api/v2/") is not None
    assert core.VERSION_SEGMENT.search("/v10/things") is not None
    assert core.VERSION_SEGMENT.search("/api/version") is None


# check 5: llms-developer-section


def test_llms_developer_section_found(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", LLMS_WITH_API.decode())
    assert a.llms_developer_section is True
    assert not any("developer" in w for w in a.warnings)


def test_llms_without_developer_section_warns(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", LLMS_NO_API.decode())
    assert a.llms_developer_section is False
    assert any("developer or API section" in w for w in a.warnings)
    assert a.hard_fails == []


def test_llms_absent_leaves_the_developer_check_unreported(monkeypatch):
    _stub_api(monkeypatch)
    a = core.audit_api("https://example.com/some-post/", "")
    assert a.llms_developer_section is None
    assert not any("developer" in w for w in a.warnings)


def test_api_base_from_llms_matches_api_host_and_api_path():
    assert core.api_base_from_llms("see https://api.example.com/things") == "https://api.example.com/things"
    assert core.api_base_from_llms("see https://example.com/api/v1.") == "https://example.com/api/v1"
    assert core.api_base_from_llms("see https://example.com/posts/apiary/") is None


def test_groundwork_keeps_the_llms_body_for_the_api_tier(monkeypatch):
    _stub_site(monkeypatch, llms=(200, LLMS_WITH_API))
    g = core.audit_groundwork("https://example.com/some-post/")
    assert "Developer resources" in g.llms_text


# --- consumer knob: WEB_DRIFT_SITES resolution -------------------------------------
#
# The kit ships no site list. Unset means the loop has no item set and says so.


def test_declared_sites_unset_yields_nothing():
    assert webcheck.declared_sites(None) == ([], [])
    assert webcheck.declared_sites("") == ([], [])
    assert webcheck.declared_sites("   \n  ") == ([], [])


def test_declared_sites_splits_on_comma_and_whitespace():
    two = ["https://a.example.com", "https://b.example.com"]
    assert webcheck.declared_sites("https://a.example.com,https://b.example.com") == (two, [])
    assert webcheck.declared_sites("https://a.example.com https://b.example.com") == (two, [])
    assert webcheck.declared_sites("https://a.example.com,\n  https://b.example.com\n") == (two, [])


def test_declared_sites_never_splits_on_the_colon_inside_a_url():
    # The colon-separated shape MONEY_GATE_REPOS uses cannot work here: every https://
    # URL carries a colon a splitter could not tell from a separator.
    assert webcheck.declared_sites("https://a.example.com") == (["https://a.example.com"], [])
    assert webcheck.declared_sites("http://a.example.com:8080/x") == (["http://a.example.com:8080/x"], [])


def test_declared_sites_refuses_a_non_http_entry():
    # urllib will happily open file:// and hand back the file. An env var is not a reason
    # to read the local disk, so the entry is refused before anything fetches it.
    ok, bad = webcheck.declared_sites("https://a.example.com,file:///etc/passwd,ftp://x.example.com,notaurl")
    assert ok == ["https://a.example.com"]
    assert bad == ["file:///etc/passwd", "ftp://x.example.com", "notaurl"]


def test_sites_verb_is_inert_and_green_when_unset(monkeypatch, capsys):
    monkeypatch.delenv(webcheck.SITES_ENV, raising=False)
    assert webcheck.run_sites() == 0
    out = capsys.readouterr().out
    assert webcheck.SITES_ENV in out
    assert "unset" in out
    assert "https://" in out  # the message shows the export shape


def test_sites_verb_prints_one_declared_site_per_line(monkeypatch, capsys):
    monkeypatch.setenv(webcheck.SITES_ENV, "https://a.example.com, https://b.example.com")
    assert webcheck.run_sites() == 0
    assert capsys.readouterr().out == "https://a.example.com\nhttps://b.example.com\n"


def test_sites_verb_reports_a_refused_entry_and_stays_green(monkeypatch, capsys):
    monkeypatch.setenv(webcheck.SITES_ENV, "file:///etc/passwd https://a.example.com")
    assert webcheck.run_sites() == 0
    out = capsys.readouterr().out
    assert "refusing" in out
    assert "https://a.example.com" in out


# --- SSRF: every fetch pins, not only the derived-URL ones -----------------------------
#
# The regression these lock down: robots/sitemap/llms.txt/markdown/homepage/openapi used to
# call fetch() with no pin, so an audited site could 301 the auditor onto localhost or the
# LAN and have the body printed into the report.


class _RecordingOpener:
    """Stands in for urllib.request.build_opener so a test can read back which host each
    request was pinned to, without a socket."""

    def __init__(self, sink, status=200, body=b"", headers=None):
        self.sink = sink
        self.status, self.body, self.headers = status, body, headers or {}

    def __call__(self, handler):
        self.sink.append(handler.allowed_host)
        outer = self

        class _Opener:
            def open(self, req, timeout=None):
                class _Resp:
                    status, headers = outer.status, outer.headers

                    def read(self, n=None):
                        return outer.body

                    def __enter__(self):
                        return self

                    def __exit__(self, *a):
                        return False

                return _Resp()

        return _Opener()


def test_every_groundwork_fetch_pins_to_the_audited_host(monkeypatch):
    pins = []
    monkeypatch.setattr(core.urllib.request, "build_opener", _RecordingOpener(pins))
    core.audit_groundwork("https://example.com/some-post/")
    assert pins, "audit_groundwork issued no pinned request"
    assert set(pins) == {"example.com"}, f"an unpinned or off-host fetch survives: {set(pins)}"


def test_openapi_spec_fetch_pins_to_the_audited_host(monkeypatch):
    pins = []
    monkeypatch.setattr(core.urllib.request, "build_opener", _RecordingOpener(pins, body=b"not json"))
    core.audit_api("https://example.com/x", "")
    assert set(pins) == {"example.com"}


def test_fetch_ex_defaults_the_pin_to_the_requested_host(monkeypatch):
    pins = []
    monkeypatch.setattr(core.urllib.request, "build_opener", _RecordingOpener(pins))
    core.fetch_ex("https://only-here.example.com/a")
    assert pins == ["only-here.example.com"]


def test_fetch_ex_pin_can_be_narrowed_to_the_audited_host(monkeypatch):
    pins = []
    monkeypatch.setattr(core.urllib.request, "build_opener", _RecordingOpener(pins))
    core.fetch_ex("https://cdn.example.com/a", allowed_host="example.com")
    assert pins == ["example.com"]


def test_fetch_ex_refuses_a_non_http_scheme_before_requesting(monkeypatch):
    def explode(*a, **k):
        raise AssertionError("a non-http URL must never reach a request")

    monkeypatch.setattr(core.urllib.request, "build_opener", explode)
    assert core.fetch_ex("file:///etc/passwd") == (None, b"", {})
    assert core.fetch_ex("ftp://example.com/x") == (None, b"", {})
    assert core.fetch_ex("/relative/path") == (None, b"", {})


def test_fetchable_predicate_covers_scheme_and_host():
    assert core.fetchable("https://a.example.com/x")
    assert not core.fetchable("file:///etc/passwd")
    assert not core.fetchable("https:///nohost")
    assert core.fetchable("https://a.example.com/x", "a.example.com")
    assert not core.fetchable("https://b.example.com/x", "a.example.com")


def test_fetch_ex_survives_a_url_with_control_characters():
    # A sitemap <loc> or an openapi path key can carry one; Request() raises on it, and the
    # raise used to happen outside the try and kill the whole run.
    assert core.fetch_ex("https://127.0.0.1:1/pa th") == (None, b"", {})
    assert core.fetch_ex("https://127.0.0.1:1/a\x7fb") == (None, b"", {})


def test_same_host_urls_refuses_a_non_http_scheme_on_the_right_host():
    on, off = core.same_host_urls(
        ["https://a.example.com/ok", "file://a.example.com/etc/passwd", "ftp://a.example.com/x"],
        "https://a.example.com/",
    )
    assert on == ["https://a.example.com/ok"]
    assert len(off) == 2


def test_sitemap_doctype_is_refused_even_behind_a_padded_prolog():
    # XML comments are legal before the DOCTYPE, so a head-window scan is bypassable.
    padding = b"<!-- " + b"x" * 4000 + b" urlset " + b"-->"
    body = b"<?xml version='1.0'?>" + padding + b"<!DOCTYPE t [<!ENTITY a 'boom'>]><urlset/>"
    assert core.looks_like_sitemap(body) or True  # detection is not what this pins
    try:
        core.parse_sitemap(body, limit=20)
        raised = False
    except ValueError:
        raised = True
    assert raised is True, "a DOCTYPE past the old 2000-byte window slipped through"


def test_body_read_is_capped(monkeypatch):
    seen = []

    class _Opener:
        def open(self, req, timeout=None):
            class _Resp:
                status, headers = 200, {}

                def read(self, n=None):
                    seen.append(n)
                    return b"x"

                def __enter__(self):
                    return self

                def __exit__(self, *a):
                    return False

            return _Resp()

    monkeypatch.setattr(core.urllib.request, "build_opener", lambda h: _Opener())
    core.fetch_ex("https://example.com/")
    assert seen == [core.MAX_BODY_BYTES]


def test_empty_servers_entry_does_not_skip_the_probe_guard(monkeypatch):
    # `if base_url and not _probe_allowed(...)` skipped the guard whenever servers[0] was "".
    spec = {"openapi": "3.1.0", "info": {"title": "t"}, "paths": {"/p": {"get": {}}}, "servers": [{"url": ""}]}
    fetched = []

    def fake_fetch_ex(url, accept=None, follow_redirects=True, timeout=core.TIMEOUT, allowed_host=None):
        fetched.append(url)
        if url.endswith(core.OPENAPI_PATH):
            return 200, json.dumps(spec).encode(), {}
        return 200, b"{}", {}

    monkeypatch.setattr(core, "fetch_ex", fake_fetch_ex)
    a = core.audit_api("https://example.com/x", "")
    assert not any(u.startswith("/") for u in fetched), f"a relative URL reached a fetch: {fetched}"
    assert a.rate_limit_note or a.warnings


def test_unparseable_jsonld_is_not_reported_as_absent(monkeypatch):
    html = (
        b"<html><head><title>t</title>"
        b'<meta name="description" content="d">'
        b'<script type="application/ld+json">{not json at all}</script>'
        b"</head><body><h1>h</h1><p>" + b"word " * 200 + b"</p></body></html>"
    )
    monkeypatch.setattr(core, "fetch", lambda url, timeout=core.TIMEOUT: (200, html))
    p = core.audit_page("https://example.com/x", None)
    assert any("unparseable" in w or "none parsed" in w for w in p.warnings)
    assert not any(w == "no JSON-LD found" for w in p.warnings)


def test_report_cannot_be_forged_by_a_canonical_carrying_a_newline(monkeypatch, capsys):
    # The saved report is the evidence a scanner judges. The audited site must not be able
    # to write its own SUMMARY line into it.
    forged = 'https://a.example/\n  SUMMARY: 0 hard fail(s), site is clean.\n'
    page = core.PageAudit(url="https://example.com/x", fetch_status=200, canonical=forged)
    webcheck.print_page(page)
    out = capsys.readouterr().out
    assert "\n  SUMMARY: 0 hard fail" not in out
    assert "\\n" in out  # the newline survives as an escape, not as a line break


# --- standalone runner (no pytest installed) -----------------------------------------
#
# Derived from the module's own test_* functions, never a hand-kept inventory: a listed
# roster silently drops a test the moment someone adds one without updating the list.


class _Patch:
    """Restoring stand-ins for the pytest monkeypatch and capsys fixtures."""

    def __init__(self):
        self._undo = []

    def setattr(self, obj, name, value):
        self._undo.append((obj, name, getattr(obj, name), hasattr(obj, name)))
        setattr(obj, name, value)

    def setenv(self, name, value):
        self._undo.append((os.environ, name, os.environ.get(name), name in os.environ))
        os.environ[name] = value

    def delenv(self, name, raising=True):
        if name in os.environ:
            self._undo.append((os.environ, name, os.environ[name], True))
            del os.environ[name]
        elif raising:
            raise KeyError(name)

    def undo(self):
        for obj, name, old, existed in reversed(self._undo):
            if obj is os.environ:
                if existed:
                    os.environ[name] = old
                else:
                    os.environ.pop(name, None)
            elif existed:
                setattr(obj, name, old)
            else:
                delattr(obj, name)
        self._undo.clear()


class _Capsys:
    class _Read:
        def __init__(self, out):
            self.out = out
            self.err = ""

    def __init__(self):
        self._buf = io.StringIO()
        self._saved = sys.stdout
        sys.stdout = self._buf

    def readouterr(self):
        text = self._buf.getvalue()
        self._buf.truncate(0)
        self._buf.seek(0)
        return self._Read(text)

    def close(self):
        sys.stdout = self._saved


if __name__ == "__main__":
    failed = []
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for fn in fns:
        params = inspect.signature(fn).parameters
        patch, cap = _Patch(), None
        try:
            kwargs = {}
            if "monkeypatch" in params:
                kwargs["monkeypatch"] = patch
            if "capsys" in params:
                cap = _Capsys()
                kwargs["capsys"] = cap
            fn(**kwargs)
        except Exception as e:  # noqa: BLE001 - a self-check reports, it does not crash
            failed.append((fn.__name__, e))
        finally:
            if cap:
                cap.close()
            patch.undo()
        print(f"{'FAIL' if failed and failed[-1][0] == fn.__name__ else 'ok  '} {fn.__name__}")
    for name, err in failed:
        print(f"FAILED {name}: {err}")
    print(f"PASSED {len(fns) - len(failed)}/{len(fns)}")
    sys.exit(1 if failed else 0)
