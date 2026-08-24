#!/usr/bin/env python3
"""webcheck: agent-readiness audit for a live public website.

Tier 1 of the kit:web-drift audit loop. Stdlib only, read-only HTTP, no credentials.

    python3 lib/webcheck/webcheck.py sites
    python3 lib/webcheck/webcheck.py audit https://example.com
    python3 lib/webcheck/webcheck.py audit https://example.com/sitemap.xml --limit 20

`audit` exits 1 when any tier reports a hard fail, 0 otherwise. Warnings never change the
exit code: they are judgment calls the skill's verdict mapping resolves, not failures.

Contract: SPEC.md. Checks and fix recipes: README.md.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import core  # noqa: E402

DEFAULT_LIMIT = 20

SITES_ENV = "WEB_DRIFT_SITES"
# Comma or whitespace, never colon. A colon is inside every https:// URL, so the
# colon-separated shape the other consumer knobs use cannot work here.
SITES_SEPARATOR = re.compile(r"[,\s]+")
SITES_UNSET_MESSAGE = (
    f"{SITES_ENV} is unset, so no sites are declared. The kit ships no site list; "
    "the consumer declares its own, e.g. "
    f"export {SITES_ENV}='https://example.com,https://docs.example.com'"
)


def declared_sites(raw: str | None) -> list[str]:
    """Parse the consumer's site list. Empty or unset yields no sites, never an error."""
    return [s for s in SITES_SEPARATOR.split((raw or "").strip()) if s]


def run_sites() -> int:
    sites = declared_sites(os.environ.get(SITES_ENV))
    if not sites:
        print(SITES_UNSET_MESSAGE)
        return 0
    for site in sites:
        print(site)
    return 0


def print_groundwork(g: core.GroundworkAudit) -> None:
    print(f"=== groundwork: {g.domain} ===")
    print(f"  robots.txt      : {g.robots_status} (Sitemap: directive={'yes' if g.robots_has_sitemap_directive else 'no'})")
    print(f"  sitemap.xml     : {g.sitemap_status}")
    print(f"  llms.txt        : {g.llms_status} (agent guidance={'yes' if g.llms_has_guidance else 'no'})")
    print(f"  unknown path    : {g.unknown_path_status} (points agent somewhere={'yes' if g.unknown_path_points_agent else 'no'}) {g.unknown_path}")
    md = "yes" if g.markdown_negotiated else "no"
    print(f"  markdown accept : {g.markdown_content_type} (markdown={md}, Vary={g.markdown_vary or 'n/a'})")
    for f in g.hard_fails:
        print(f"  HARD FAIL       : {f}")
    for w in g.warnings:
        print(f"  warn            : {w}")
    print()


def print_api(a: core.ApiAudit) -> None:
    print(f"=== api tier: {a.domain} ===")
    if not a.applicable:
        print(f"  not applicable  : {a.skip_reason}")
        print()
        return
    print(f"  openapi.json    : {a.spec_status} version={a.openapi_version} title={a.info_title!r} paths={a.path_count}")
    print(f"  servers         : {a.servers or 'none'}")
    print(f"  base            : {a.base_url} (from {a.base_source})")
    print(f"  reachability    : {a.reach_status} {a.reach_url}")
    print(f"  json errors     : {a.error_probe_status} json={a.error_probe_is_json} error field={a.error_probe_error_field or 'none'} {a.error_probe_url}")
    rl = ", ".join(a.rate_limit_found) if a.rate_limit_found else (a.rate_limit_note or "none")
    print(f"  rate limit      : {rl}")
    print(f"  versioned base  : {a.versioned_base} (deprecation policy documented={a.deprecation_policy})")
    dev = "n/a (no llms.txt)" if a.llms_developer_section is None else a.llms_developer_section
    print(f"  llms developer  : {dev}")
    for f in a.hard_fails:
        print(f"  HARD FAIL       : {f}")
    for w in a.warnings:
        print(f"  warn            : {w}")
    print()


def print_page(p: core.PageAudit) -> None:
    print(f"=== {p.url} ===")
    print(f"  title           : {p.title!r} (len={p.title_len})")
    print(f"  meta description: {p.meta_desc!r} (len={p.meta_desc_len})")
    print(f"  h1 count        : {p.h1_count}")
    print(f"  visible text    : {p.visible_text_len} chars (no JavaScript)")
    print(f"  canonical       : {p.canonical}")
    print(f"  og missing      : {p.og_missing or 'none'}")
    print(f"  twitter missing : {p.twitter_missing or 'none'}")
    jl = p.jsonld
    print(f"  json-ld         : found={jl.found} types={sorted(jl.types)} datePublished={jl.has_date_published} dateModified={jl.has_date_modified}")
    print(f"  organization    : found={jl.has_organization} missing={jl.organization_missing if jl.has_organization else 'n/a'}")
    print(f"  internal links  : {p.internal_links}")
    for f in p.hard_fails:
        print(f"  HARD FAIL       : {f}")
    for w in p.warnings:
        print(f"  warn            : {w}")
    print()


def run_audit(target: str, limit: int, skip_groundwork: bool) -> int:
    status, body = core.fetch(target)
    if status is None:
        print(f"fetch failed for {target}: network error (DNS/timeout/refused)")
        return 1

    urls: list[str]
    if status == 200 and core.looks_like_sitemap(body):
        try:
            urls = core.parse_sitemap(body, limit)
        except ValueError as e:
            print(f"could not parse sitemap at {target}: {e}")
            return 1
        if not urls:
            print(f"sitemap at {target} had no <loc> entries (nested sitemapindex not supported)")
            return 1
        # A sitemap is remote content; only fan out to the audited host so a
        # hostile sitemap cannot point the audit at localhost or the LAN.
        urls, offhost = core.same_host_urls(urls, target)
        if offhost:
            print(f"skipping {len(offhost)} off-host sitemap URL(s) (first: {offhost[0]})")
        if not urls:
            print("sitemap listed no URLs on the audited host")
            return 1
    else:
        urls = [target]

    groundwork_hard_fail = False
    homepage_meta_desc = None
    api_state = "skipped"
    api_hard_fail = False
    if not skip_groundwork:
        groundwork = core.audit_groundwork(urls[0])
        print_groundwork(groundwork)
        groundwork_hard_fail = bool(groundwork.hard_fails)
        homepage_meta_desc = groundwork.homepage_meta_desc

        api = core.audit_api(urls[0], groundwork.llms_text)
        print_api(api)
        api_hard_fail = bool(api.hard_fails)
        api_state = ("FAIL" if api_hard_fail else "ok") if api.applicable else "n/a"

    hard_fail_count = 0
    warn_count = 0
    for url in urls:
        page = core.audit_page(url, homepage_meta_desc, pin_host=len(urls) > 1 or url != target)
        print_page(page)
        hard_fail_count += len(page.hard_fails)
        warn_count += len(page.warnings)

    total_hard_fails = hard_fail_count + (1 if groundwork_hard_fail else 0) + (1 if api_hard_fail else 0)
    print(
        f"SUMMARY: {len(urls)} URL(s) audited, {hard_fail_count} page hard fail(s), "
        f"{warn_count} warning(s), groundwork {'FAIL' if groundwork_hard_fail else 'ok'}, "
        f"api tier {api_state}."
    )
    return 1 if total_hard_fails else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="webcheck", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("sites", help=f"print the sites declared in {SITES_ENV}")

    p_audit = sub.add_parser("audit", help="run the three tiers against a URL or a sitemap")
    p_audit.add_argument("target", help="a page URL, or a sitemap.xml URL")
    p_audit.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help=f"max URLs from a sitemap (default {DEFAULT_LIMIT})")
    p_audit.add_argument("--skip-groundwork", action="store_true", help="skip the domain-level and API tiers")

    args = parser.parse_args(argv)
    if args.command == "sites":
        return run_sites()
    return run_audit(args.target, args.limit, args.skip_groundwork)


if __name__ == "__main__":
    sys.exit(main())
