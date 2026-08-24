"""Agent-readiness checks for a live public website. Stdlib only: urllib, html.parser,
json, xml.etree.

Three tiers, all read-only HTTP GETs: groundwork (robots, sitemap, llms.txt, unknown-path
status, markdown negotiation), page (title, meta, h1, JavaScript-free visible text, canonical,
OG, JSON-LD, internal links), and API (openapi spec, reachability, JSON errors, rate-limit
headers, versioning), which activates only on evidence of an API surface.

EVERY fetch is host-pinned. A redirect never leaves the requested URL's host, and a URL that
arrived from remote content (a sitemap entry, an openapi `servers[0]`, an llms.txt base) pins to
the AUDITED host rather than its own. There is no cross-host mode: the audited site is
untrusted, so following its redirect anywhere would turn this tool into an internal port probe
and an exfiltration channel. Non-http(s) schemes are refused before any request. See SPEC.md.

Contract: SPEC.md. Skill that drives it: skills/web-drift/SKILL.md.
"""
from __future__ import annotations

import http.client
import json
import re
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
from xml.etree import ElementTree

USER_AGENT = "dwarves-kit-webcheck/1.0 (+https://github.com/dwarvesf/dwarves-kit)"
TIMEOUT = 10
# A hostile or merely huge endpoint must not exhaust the auditor. Every body read stops here;
# no page this tool judges needs more, and a truncated body still answers every check.
MAX_BODY_BYTES = 5 * 1024 * 1024
ALLOWED_SCHEMES = ("http", "https")
GOOD_META_LEN = (150, 160)
MIN_INTERNAL_LINKS = 2
MIN_VISIBLE_TEXT_CHARS = 500
SITEMAP_NS = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
NOT_FOUND_STATUSES = (404, 410)
INVISIBLE_TAGS = frozenset({"script", "style", "noscript"})

# A 404 page that names none of these strands an agent: it cannot tell a dead URL from a
# real one, and it gets no route back to the site's own index.
NOT_FOUND_POINTERS = ("sitemap.xml", "llms.txt", 'href="/"', "href='/'")

# ponytail: phrase match, not comprehension. An llms.txt that is a bare link index carries
# none of these; one with an orientation section carries at least one. Swap for a real
# section parser only if the phrase list starts producing false verdicts.
LLMS_GUIDANCE_HINTS = (
    "when to use",
    "how to",
    "start here",
    "use this",
    "if you are",
    "instructions",
    "guidance",
    "for agents",
    "ask about",
)


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Surfaces a 3xx as the 3xx itself instead of transparently following it."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirectHandler)


class _SameHostRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Follows redirects only while they stay on one host. EVERY fetch this module makes
    installs one of these, because every response it reads comes from the audited site: a
    sitemap entry, an openapi `servers[0]`, but equally the site's own robots.txt or
    homepage. Refusing the off-host hop is what keeps the audit from reading internal
    services into the report."""

    def __init__(self, allowed_host: str):
        self.allowed_host = allowed_host.lower()

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        u = urlparse(newurl)
        if u.scheme not in ALLOWED_SCHEMES or u.netloc.lower() != self.allowed_host:
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetchable(url: str, allowed_host: str | None = None) -> bool:
    """True when this tool is willing to request `url` at all: an http(s) scheme, a real host,
    and (when given) that host. Every URL the tool did not construct itself passes through
    here, so a `file://`, `ftp://`, or schemeless entry never reaches a request."""
    u = urlparse(url)
    if u.scheme not in ALLOWED_SCHEMES or not u.netloc:
        return False
    return allowed_host is None or u.netloc.lower() == allowed_host.lower()


def fetch_ex(
    url: str,
    accept: str | None = None,
    follow_redirects: bool = True,
    timeout: int = TIMEOUT,
    allowed_host: str | None = None,
) -> tuple[int | None, bytes, dict[str, str]]:
    """GET a URL. Returns (status_code, body, lowercased-header-map); status is None on a
    network-level failure (DNS/timeout/refused) or on a URL this tool refuses to request.
    An HTTP error status still returns its body and headers. With follow_redirects=False a
    3xx comes back as that 3xx.

    A redirect NEVER leaves a host. `allowed_host` names which one, defaulting to the
    requested URL's own; a URL that arrived from remote content passes the AUDITED host so a
    hostile page cannot redirect the audit onto localhost or the LAN. Bodies stop at
    MAX_BODY_BYTES."""
    if not fetchable(url):
        return None, b"", {}
    req_headers = {"User-Agent": USER_AGENT}
    if accept:
        req_headers["Accept"] = accept
    pin = allowed_host or urlparse(url).netloc
    try:
        # Request() itself raises on a URL carrying control characters, which a sitemap
        # <loc> or an openapi path key can, so it is inside the try with the fetch.
        req = urllib.request.Request(url, headers=req_headers)
        if follow_redirects:
            opener = urllib.request.build_opener(_SameHostRedirectHandler(pin)).open
        else:
            opener = _NO_REDIRECT_OPENER.open
        with opener(req, timeout=timeout) as resp:
            return resp.status, resp.read(MAX_BODY_BYTES), _lower_headers(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(MAX_BODY_BYTES), _lower_headers(e.headers)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, http.client.HTTPException):
        return None, b"", {}


def _lower_headers(headers) -> dict[str, str]:
    return {k.lower(): v for k, v in headers.items()}


def fetch(url: str, timeout: int = TIMEOUT) -> tuple[int | None, bytes]:
    """GET a URL. Returns (status_code, body); status is None on a network-level failure
    (DNS/timeout/refused), body is empty in that case."""
    status, body, _ = fetch_ex(url, timeout=timeout)
    return status, body


class PageParser(HTMLParser):
    """Pulls the handful of tags the checklist cares about out of one HTML page."""

    def __init__(self) -> None:
        super().__init__()
        self.title_parts: list[str] = []
        self.meta: list[dict[str, str]] = []
        self.h1_count = 0
        self.canonical: str | None = None
        self.links: list[str] = []
        self.ld_json_blocks: list[str] = []
        self._in_title = False
        self._in_ldjson = False
        self._ldjson_buf: list[str] = []
        self._svg_depth = 0  # <svg><title> is an accessibility tooltip, not the page title
        self._text_parts: list[str] = []
        self._invisible_depth = 0

    def handle_starttag(self, tag: str, attrs_list) -> None:
        attrs = {k: (v or "") for k, v in attrs_list}
        if tag in INVISIBLE_TAGS:
            self._invisible_depth += 1
        if tag == "svg":
            self._svg_depth += 1
        elif tag == "title":
            if self._svg_depth == 0:
                self._in_title = True
        elif tag == "meta":
            self.meta.append(attrs)
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "link" and "canonical" in attrs.get("rel", "").split():
            self.canonical = attrs.get("href")
        elif tag == "a" and attrs.get("href"):
            self.links.append(attrs["href"])
        elif tag == "script" and attrs.get("type") == "application/ld+json":
            self._in_ldjson = True
            self._ldjson_buf = []

    def handle_endtag(self, tag: str) -> None:
        if tag in INVISIBLE_TAGS:
            self._invisible_depth = max(0, self._invisible_depth - 1)
        if tag == "svg":
            self._svg_depth = max(0, self._svg_depth - 1)
        elif tag == "title":
            self._in_title = False
        elif tag == "script" and self._in_ldjson:
            self._in_ldjson = False
            self.ld_json_blocks.append("".join(self._ldjson_buf))

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title_parts.append(data)
        if self._in_ldjson:
            self._ldjson_buf.append(data)
        if self._invisible_depth == 0:
            self._text_parts.append(data)

    @property
    def title(self) -> str | None:
        text = "".join(self.title_parts).strip()
        return text or None

    @property
    def visible_text(self) -> str:
        """Every text run outside <script>/<style>/<noscript> and outside tags, whitespace
        collapsed. This is what an agent that does not execute JavaScript actually reads."""
        return " ".join("".join(self._text_parts).split())

    def meta_content(self, key: str, value: str) -> str | None:
        low = value.lower()
        for m in self.meta:
            if m.get(key, "").lower() == low:
                return m.get("content") or None
        return None


ORGANIZATION_FIELDS = ("contactPoint", "address", "sameAs")


@dataclass
class JsonLdInfo:
    found: bool = False
    types: set[str] = field(default_factory=set)
    has_date_published: bool = False
    has_date_modified: bool = False
    parse_errors: int = 0
    has_organization: bool = False
    organization_fields: set[str] = field(default_factory=set)

    @property
    def organization_missing(self) -> list[str]:
        return [f for f in ORGANIZATION_FIELDS if f not in self.organization_fields]


def _node_types(node: dict) -> set[str]:
    t = node.get("@type")
    if isinstance(t, str):
        return {t}
    if isinstance(t, list):
        return {x for x in t if isinstance(x, str)}
    return set()


def _walk_jsonld(node, info: JsonLdInfo) -> None:
    if isinstance(node, list):
        for item in node:
            _walk_jsonld(item, info)
        return
    if not isinstance(node, dict):
        return
    info.found = True
    info.types.update(_node_types(node))
    if node.get("datePublished"):
        info.has_date_published = True
    if node.get("dateModified"):
        info.has_date_modified = True
    if "@graph" in node:
        _walk_jsonld(node["@graph"], info)


def _scan_organizations(node, info: JsonLdInfo) -> None:
    """Second, deeper pass for Organization only. Kept separate from `_walk_jsonld` so that
    a nested `publisher: {@type: Organization}` cannot alter the top-level @type verdict."""
    if isinstance(node, list):
        for item in node:
            _scan_organizations(item, info)
        return
    if not isinstance(node, dict):
        return
    if "Organization" in _node_types(node):
        info.has_organization = True
        info.organization_fields.update(f for f in ORGANIZATION_FIELDS if node.get(f))
    for value in node.values():
        _scan_organizations(value, info)


def extract_jsonld(blocks: list[str]) -> JsonLdInfo:
    info = JsonLdInfo()
    for raw in blocks:
        try:
            data = json.loads(raw.strip())
        except (json.JSONDecodeError, ValueError):
            info.parse_errors += 1
            continue
        _walk_jsonld(data, info)
        _scan_organizations(data, info)
    return info


def count_internal_links(page_url: str, hrefs: list[str]) -> int:
    page = urlparse(page_url)
    page_netloc = page.netloc.removeprefix("www.")
    count = 0
    for href in hrefs:
        if href.startswith(("#", "mailto:", "tel:", "javascript:")):
            continue
        resolved = urljoin(page_url, href)
        parsed = urlparse(resolved)
        if not parsed.scheme.startswith("http"):
            continue
        netloc = parsed.netloc.removeprefix("www.")
        if netloc != page_netloc:
            continue
        if resolved.split("#")[0].rstrip("/") == page_url.split("#")[0].rstrip("/"):
            continue
        count += 1
    return count


@dataclass
class PageAudit:
    url: str
    fetch_status: int | None
    title: str | None = None
    title_len: int = 0
    meta_desc: str | None = None
    meta_desc_len: int = 0
    meta_same_as_homepage: bool = False
    h1_count: int = 0
    visible_text_len: int = 0
    canonical: str | None = None
    og_missing: list[str] = field(default_factory=list)
    twitter_missing: list[str] = field(default_factory=list)
    jsonld: JsonLdInfo = field(default_factory=JsonLdInfo)
    internal_links: int = 0
    hard_fails: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


OG_REQUIRED = ["og:title", "og:description", "og:image"]
TWITTER_REQUIRED = ["twitter:card"]
GOOD_JSONLD_TYPES = {"Article", "TechArticle", "BlogPosting", "NewsArticle"}


def audit_page(url: str, homepage_meta_desc: str | None) -> PageAudit:
    # No pin flag: fetch_ex pins every request to its own host, whether the URL came from a
    # sitemap or from the operator. A page that redirects off-host reports that 3xx, which is
    # itself the finding ("declare the URL the site actually serves").
    status, body = fetch(url)
    result = PageAudit(url=url, fetch_status=status)
    if status != 200 or not body:
        result.hard_fails.append(f"page fetch failed (status={status})")
        return result

    parser = PageParser()
    parser.feed(body.decode("utf-8", errors="replace"))

    result.title = parser.title
    result.title_len = len(result.title) if result.title else 0
    if not result.title:
        result.hard_fails.append("missing <title>")

    result.meta_desc = parser.meta_content("name", "description")
    result.meta_desc_len = len(result.meta_desc) if result.meta_desc else 0
    if not result.meta_desc:
        result.hard_fails.append("missing meta description")
    else:
        if not (GOOD_META_LEN[0] <= result.meta_desc_len <= GOOD_META_LEN[1]):
            result.warnings.append(
                f"meta description length {result.meta_desc_len} outside {GOOD_META_LEN[0]}-{GOOD_META_LEN[1]}"
            )
        if homepage_meta_desc and result.meta_desc.strip() == homepage_meta_desc.strip():
            result.meta_same_as_homepage = True
            result.warnings.append("meta description same as site default (homepage)")

    result.h1_count = parser.h1_count
    if result.h1_count == 0:
        result.hard_fails.append("missing <h1>")
    elif result.h1_count > 1:
        result.warnings.append(f"{result.h1_count} <h1> tags (expected 1)")

    result.visible_text_len = len(parser.visible_text)
    if result.visible_text_len < MIN_VISIBLE_TEXT_CHARS:
        result.hard_fails.append(
            f"only {result.visible_text_len} visible text characters without JavaScript "
            f"(want {MIN_VISIBLE_TEXT_CHARS}+)"
        )

    result.canonical = parser.canonical
    if not result.canonical:
        result.warnings.append("missing canonical URL")

    for tag in OG_REQUIRED:
        if not parser.meta_content("property", tag):
            result.og_missing.append(tag)
    if result.og_missing:
        result.warnings.append(f"missing OG tags: {', '.join(result.og_missing)}")

    for tag in TWITTER_REQUIRED:
        if not parser.meta_content("name", tag):
            result.twitter_missing.append(tag)
    if result.twitter_missing:
        result.warnings.append(f"missing Twitter card tags: {', '.join(result.twitter_missing)}")

    result.jsonld = extract_jsonld(parser.ld_json_blocks)
    if not result.jsonld.found:
        if result.jsonld.parse_errors:
            result.warnings.append(
                f"{result.jsonld.parse_errors} JSON-LD block(s) present but none parsed as JSON"
            )
        else:
            result.warnings.append("no JSON-LD found")
    elif not (result.jsonld.types & GOOD_JSONLD_TYPES):
        result.warnings.append(f"JSON-LD @type {sorted(result.jsonld.types) or 'unknown'} not Article-shaped")
    if result.jsonld.found and not result.jsonld.has_date_published:
        result.warnings.append("JSON-LD missing datePublished")
    if not result.jsonld.has_organization:
        result.warnings.append("no Organization JSON-LD block on the page")
    elif result.jsonld.organization_missing:
        result.warnings.append(
            f"Organization JSON-LD missing: {', '.join(result.jsonld.organization_missing)}"
        )

    result.internal_links = count_internal_links(url, parser.links)
    if result.internal_links < MIN_INTERNAL_LINKS:
        result.warnings.append(f"only {result.internal_links} internal link(s), want {MIN_INTERNAL_LINKS}+")

    return result


@dataclass
class GroundworkAudit:
    domain: str
    robots_status: int | None = None
    robots_has_sitemap_directive: bool = False
    sitemap_status: int | None = None
    llms_status: int | None = None
    llms_has_guidance: bool = False
    llms_text: str = ""  # kept so the API tier can read it without a second fetch
    unknown_path: str | None = None
    unknown_path_status: int | None = None
    unknown_path_points_agent: bool = False
    markdown_content_type: str | None = None
    markdown_negotiated: bool = False
    markdown_vary: str | None = None
    homepage_meta_desc: str | None = None
    hard_fails: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def vary_includes_accept(vary: str | None) -> bool:
    """True when a `Vary` header actually varies on `Accept`. Token-aware, so that
    `Vary: Accept-Encoding` does not count as a match."""
    if not vary:
        return False
    tokens = {t.strip().lower() for t in vary.split(",")}
    return "accept" in tokens or "*" in tokens


def unknown_path_for(root: str) -> str:
    token = uuid.uuid4().hex[:12]
    return f"{root}/{token}-does-not-exist-{token}"


def audit_groundwork(base_url: str) -> GroundworkAudit:
    parsed = urlparse(base_url)
    root = f"{parsed.scheme}://{parsed.netloc}"
    g = GroundworkAudit(domain=parsed.netloc)

    status, body = fetch(f"{root}/robots.txt")
    g.robots_status = status
    if status != 200:
        g.hard_fails.append(f"robots.txt unreachable (status={status})")
    else:
        text = body.decode("utf-8", errors="replace").lower()
        g.robots_has_sitemap_directive = any(
            line.strip().startswith("sitemap:") for line in text.splitlines()
        )
        if not g.robots_has_sitemap_directive:
            g.warnings.append("robots.txt has no Sitemap: directive")

    status, _ = fetch(f"{root}/sitemap.xml")
    g.sitemap_status = status
    if status != 200:
        g.hard_fails.append(f"sitemap.xml unreachable (status={status})")

    status, body = fetch(f"{root}/llms.txt")
    g.llms_status = status
    if status != 200:
        g.hard_fails.append(f"llms.txt unreachable (status={status})")
    else:
        g.llms_text = body.decode("utf-8", errors="replace")
        text = g.llms_text.lower()
        g.llms_has_guidance = any(hint in text for hint in LLMS_GUIDANCE_HINTS)
        if not g.llms_has_guidance:
            g.warnings.append("llms.txt carries no agent guidance (bare link index, no orientation section)")

    g.unknown_path = unknown_path_for(root)
    status, body, _ = fetch_ex(g.unknown_path, follow_redirects=False)
    g.unknown_path_status = status
    if status not in NOT_FOUND_STATUSES:
        g.hard_fails.append(
            f"unknown path answered {status}, expected 404 or 410 (an agent reads every URL as a real page)"
        )
    else:
        text = body.decode("utf-8", errors="replace").lower()
        g.unknown_path_points_agent = any(p in text for p in NOT_FOUND_POINTERS)
        if not g.unknown_path_points_agent:
            g.warnings.append("404 body routes an agent nowhere (no sitemap.xml, llms.txt, or home link)")

    status, _body, headers = fetch_ex(root + "/", accept="text/markdown")
    g.markdown_content_type = headers.get("content-type")
    g.markdown_negotiated = bool(g.markdown_content_type and "markdown" in g.markdown_content_type.lower())
    if g.markdown_negotiated:
        g.markdown_vary = headers.get("vary")
        if not vary_includes_accept(g.markdown_vary):
            g.hard_fails.append(
                f"markdown served for Accept: text/markdown but Vary is {g.markdown_vary!r}, "
                "so a CDN will hand one variant to the wrong client"
            )

    status, body = fetch(root + "/")
    if status == 200 and body:
        home = PageParser()
        home.feed(body.decode("utf-8", errors="replace"))
        g.homepage_meta_desc = home.meta_content("name", "description")

    return g


def looks_like_sitemap(body: bytes) -> bool:
    stripped = body.lstrip()[:200]
    return stripped.startswith(b"<?xml") and b"rlset" in body[:2000]


def parse_sitemap(body: bytes, limit: int) -> list[str]:
    # ponytail: stdlib xml.etree is XXE/billion-laughs vulnerable via DOCTYPE/ENTITY;
    # defusedxml would add a dep the task forbids. A real sitemap.xml never declares
    # a DOCTYPE, so reject any body that does instead of parsing it. Upgrade to
    # defusedxml if this tool is ever pointed at a domain the operator does not own.
    # Scan the whole body, never a head window: XML comments are legal in the prolog, so a
    # padded prolog pushes the declaration past any fixed window and billion-laughs lands.
    # A real sitemap contains neither string anywhere, so the full scan costs nothing.
    if b"<!DOCTYPE" in body or b"<!ENTITY" in body:
        raise ValueError("refusing to parse sitemap XML with a DOCTYPE/ENTITY declaration")
    root = ElementTree.fromstring(body)
    locs = [el.text.strip() for el in root.iter(f"{SITEMAP_NS}loc") if el.text]
    if not locs:
        # namespace-less sitemap: fall back to a bare tag search
        locs = [el.text.strip() for el in root.iter("loc") if el.text]
    return locs[:limit]


# --- API tier -------------------------------------------------------------------
#
# Activates only on evidence: /openapi.json answers 200 with JSON, or llms.txt names an
# API base URL. With neither, the tier is not applicable and reports nothing, the way
# is-agentic.com excludes a check rather than failing a site the check cannot apply to.
#
# Request budget when active: one for the spec, one for a documented endpoint (which also
# proves servers[0] reachable and carries the rate-limit headers), one for the unrouted
# path. Detection alone costs the one spec request.

OPENAPI_PATH = "/openapi.json"
API_ERROR_FIELDS = ("error", "errors", "message", "detail", "title")
VERSION_SEGMENT = re.compile(r"/v\d+(?:/|$)")
URL_IN_TEXT = re.compile(r"https?://[^\s)>\]\"'`]+")
DEVELOPER_HEADING_WORDS = ("developer", "api")

# IETF draft-ietf-httpapi-ratelimit-headers structured fields, plus the legacy singular trio.
RATE_LIMIT_HEADERS = (
    "ratelimit",
    "ratelimit-limit",
    "ratelimit-remaining",
    "ratelimit-reset",
    "ratelimit-policy",
    "x-ratelimit-limit",
    "x-ratelimit-remaining",
    "x-ratelimit-reset",
)


@dataclass
class ApiAudit:
    domain: str
    applicable: bool = False
    skip_reason: str = ""
    spec_url: str | None = None
    spec_status: int | None = None
    openapi_version: str | None = None
    info_title: str | None = None
    path_count: int = 0
    servers: list[str] = field(default_factory=list)
    base_url: str | None = None
    base_source: str = ""
    reach_url: str | None = None
    reach_status: int | None = None
    error_probe_url: str | None = None
    error_probe_status: int | None = None
    error_probe_is_json: bool = False
    error_probe_error_field: str | None = None
    rate_limit_found: list[str] = field(default_factory=list)
    rate_limit_note: str = ""
    versioned_base: bool = False
    deprecation_policy: bool = False
    llms_developer_section: bool | None = None
    hard_fails: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def api_base_from_llms(text: str) -> str | None:
    """First URL in llms.txt that looks like an API base: an `api.` host or an `/api` path
    segment. Phrase-level, like the llms.txt guidance check; it only has to be good enough
    to say the tier applies."""
    for raw in URL_IN_TEXT.findall(text or ""):
        url = raw.rstrip(".,;:")
        parsed = urlparse(url)
        if parsed.netloc.startswith("api.") or re.search(r"/api(?:/|$)", parsed.path):
            return url
    return None


def has_developer_section(text: str) -> bool:
    """A markdown heading naming developers or the API. llms.txt is heading-structured by
    convention, so a heading is the section marker."""
    for line in (text or "").splitlines():
        stripped = line.strip()
        if not stripped.startswith("#"):
            continue
        low = stripped.lstrip("#").strip().lower()
        if any(word in low for word in DEVELOPER_HEADING_WORDS):
            return True
    return False


def parse_openapi(body: bytes) -> dict | None:
    try:
        spec = json.loads(body.decode("utf-8", errors="replace"))
    except (json.JSONDecodeError, ValueError):
        return None
    return spec if isinstance(spec, dict) else None


def first_probeable_get_path(spec: dict) -> str | None:
    """First documented GET path that needs no arguments: no path template, no required
    parameter. Anything else cannot be called blind, so there is nothing cheap to probe."""
    paths = spec.get("paths")
    if not isinstance(paths, dict):
        return None
    for path, item in paths.items():
        if not isinstance(item, dict) or "{" in path:
            continue
        op = item.get("get")
        if not isinstance(op, dict):
            continue
        params = list(op.get("parameters") or []) + list(item.get("parameters") or [])
        if any(isinstance(p, dict) and p.get("required") for p in params):
            continue
        return path
    return None


def json_error_field(body: bytes) -> tuple[bool, str | None]:
    """(body parses as a JSON object, name of the error-ish field it carries)."""
    try:
        data = json.loads(body.decode("utf-8", errors="replace"))
    except (json.JSONDecodeError, ValueError):
        return False, None
    if not isinstance(data, dict):
        return isinstance(data, list), None
    for name in API_ERROR_FIELDS:
        if data.get(name):
            return True, name
    return True, None


def rate_limit_headers_in(headers: dict[str, str]) -> list[str]:
    return sorted(k for k in headers if k.lower() in RATE_LIMIT_HEADERS)


def same_host_urls(urls: list[str], target: str) -> tuple[list[str], list[str]]:
    """Split sitemap URLs into (on the audited host, off it). A sitemap is
    remote content, so the fan-out must not follow it to another host."""
    host = urlparse(target).netloc
    on = [u for u in urls if fetchable(u, host)]
    off = [u for u in urls if not fetchable(u, host)]
    return on, off


def _join_api(base: str, path: str) -> str:
    return base.rstrip("/") + "/" + path.lstrip("/")


def _probe_allowed(candidate: str, audited_host: str) -> bool:
    """A derived URL (openapi servers[0], an llms.txt base) is remote content:
    a hostile site could point it at localhost or the LAN and turn the audit
    into an internal port probe. Probes therefore only follow http(s) URLs on
    the audited host itself; anything else is recorded but never fetched."""
    return fetchable(candidate, audited_host)


def audit_api(base_url: str, llms_text: str = "") -> ApiAudit:
    parsed = urlparse(base_url)
    root = f"{parsed.scheme}://{parsed.netloc}"
    a = ApiAudit(domain=parsed.netloc)

    a.spec_url = root + OPENAPI_PATH
    status, body, _ = fetch_ex(a.spec_url)
    a.spec_status = status
    spec = parse_openapi(body) if status == 200 else None

    llms_base = api_base_from_llms(llms_text)
    if spec is None and not llms_base:
        a.skip_reason = f"no JSON at {OPENAPI_PATH} (status={status}) and no API base URL in llms.txt"
        return a

    a.applicable = True

    if spec is None:
        a.base_url = llms_base
        a.base_source = "llms.txt"
        a.hard_fails.append(
            f"llms.txt names an API base ({llms_base}) but {OPENAPI_PATH} serves no JSON (status={status})"
        )
    else:
        a.openapi_version = spec.get("openapi") if isinstance(spec.get("openapi"), str) else None
        info = spec.get("info") if isinstance(spec.get("info"), dict) else {}
        a.info_title = info.get("title") if isinstance(info.get("title"), str) else None
        paths = spec.get("paths") if isinstance(spec.get("paths"), dict) else {}
        a.path_count = len(paths)
        servers = spec.get("servers") if isinstance(spec.get("servers"), list) else []
        a.servers = [s["url"] for s in servers if isinstance(s, dict) and isinstance(s.get("url"), str)]

        if not (a.openapi_version or "").startswith("3."):
            a.hard_fails.append(f"openapi version {a.openapi_version!r} is not 3.x")
        if not a.info_title:
            a.hard_fails.append("openapi spec has no info.title")
        if a.path_count == 0:
            a.hard_fails.append("openapi spec documents no paths")
        if not a.servers:
            a.hard_fails.append("openapi spec has no servers list")

        a.base_url = a.servers[0] if a.servers else llms_base or root
        a.base_source = "openapi servers[0]" if a.servers else "fallback"

        description = info.get("description") if isinstance(info.get("description"), str) else ""
        a.deprecation_policy = "deprecat" in description.lower()
        a.versioned_base = bool(a.servers and VERSION_SEGMENT.search(urlparse(a.servers[0]).path))
        if not (a.versioned_base or a.deprecation_policy):
            a.warnings.append(
                "canonical server URL carries no /v<n> segment and info.description names no "
                "deprecation policy, so a client cannot tell when the surface may change"
            )

    # One request doing double duty: it proves servers[0] answers, and it is the documented
    # GET whose response headers check 3 reads.
    # `and` on the LEFT would skip the guard whenever base_url is falsy, and an openapi
    # servers[0] of "" is a valid str the parser accepts. Guard first, then the value.
    if not (a.base_url and _probe_allowed(a.base_url, parsed.netloc)):
        a.warnings.append(
            f"api base {a.base_url} is off the audited host; recorded but not probed"
        )
        a.rate_limit_note = "base off the audited host, not probed"
        return a

    if a.servers:
        probe_path = first_probeable_get_path(spec) if spec else None
        a.reach_url = _join_api(a.base_url, probe_path) if probe_path else a.base_url
        # No redirect following: the initial URL passed the same-host guard,
        # but a redirect is more remote content and could hop off-host.
        a.reach_status, _body, headers = fetch_ex(a.reach_url, follow_redirects=False)
        if a.reach_status is None:
            a.hard_fails.append(f"openapi servers[0] {a.base_url} is unreachable (network error)")
        if probe_path:
            a.rate_limit_found = rate_limit_headers_in(headers)
            if not a.rate_limit_found:
                a.warnings.append(
                    f"no RateLimit headers on GET {a.reach_url}, so an agent cannot pace itself"
                )
        else:
            a.rate_limit_note = "no documented GET path without required parameters, nothing cheap to probe"
    else:
        a.rate_limit_note = "no openapi servers list, no documented endpoint to probe"

    if a.base_url:
        token = uuid.uuid4().hex[:8]
        a.error_probe_url = _join_api(a.base_url, f"nope-{token}")
        a.error_probe_status, body, _ = fetch_ex(a.error_probe_url, follow_redirects=False)
        a.error_probe_is_json, a.error_probe_error_field = json_error_field(body)
        if a.error_probe_status is None:
            a.hard_fails.append(f"unrouted API path {a.error_probe_url} is unreachable (network error)")
        elif not a.error_probe_is_json:
            a.hard_fails.append(
                f"unrouted API path answered {a.error_probe_status} with non-JSON, so a client "
                "parsing the API's own content type gets a parse error instead of an error"
            )
        elif not a.error_probe_error_field:
            a.hard_fails.append(
                f"unrouted API path answered {a.error_probe_status} with JSON carrying no error "
                f"field (want one of {', '.join(API_ERROR_FIELDS)})"
            )

    if llms_text:
        a.llms_developer_section = has_developer_section(llms_text)
        if not a.llms_developer_section:
            a.warnings.append("llms.txt has no developer or API section pointing an agent at the API")

    return a
