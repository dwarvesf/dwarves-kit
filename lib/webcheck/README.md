# webcheck

Audits a live public website for agent readiness: can an AI agent that runs no JavaScript
discover, fetch, understand, and act on this site. Stdlib-only Python, read-only HTTP, no
credentials.

This is Tier 1 of the `kit:web-drift` audit loop. It is mechanical and costs no model tokens.
The skill turns its output into verdicts.

## Use

```bash
python3 lib/webcheck/webcheck.py sites                              # what the consumer declared
python3 lib/webcheck/webcheck.py audit https://example.com          # one page + groundwork + api
python3 lib/webcheck/webcheck.py audit https://example.com/sitemap.xml --limit 20
python3 lib/webcheck/webcheck.py audit https://example.com --skip-groundwork
```

Exit 1 means at least one tier reported a hard fail. Warnings do not change the exit code.

## The site list is the consumer's

`WEB_DRIFT_SITES` names the sites to audit. It has no default: the kit ships no hostname, so
unset means no sites are declared and the loop has no item set.

```bash
export WEB_DRIFT_SITES='https://example.com,https://docs.example.com'
```

Separator is comma or whitespace, never colon. Every `https://` URL carries a colon, so the
colon-separated shape the other consumer knobs use cannot work here. A multi-line export with
one URL per line parses the same as a comma list.

## What it checks

| Tier | Checks |
|---|---|
| groundwork | robots.txt answers and names a Sitemap; sitemap.xml answers; llms.txt answers and carries an orientation section rather than a bare link index; an unknown path answers 404 or 410 and its body routes an agent somewhere; markdown negotiated for `Accept: text/markdown` carries `Vary: Accept` |
| page | title present; meta description present, 150 to 160 characters, not the site default; exactly one h1; 500 or more visible characters without JavaScript; canonical link; OG and Twitter card tags; Article-shaped JSON-LD with datePublished; a complete Organization block; two or more internal links |
| api | activates only on evidence (`/openapi.json` serves JSON, or llms.txt names an API base). Then: OpenAPI 3.x with a title, paths, and a servers list; the canonical server answers; an unrouted path returns JSON carrying an error field; RateLimit headers on a documented GET; a versioned base or a stated deprecation policy; an llms.txt developer section |

A tier that does not apply reports so and drops out of the denominator. It is never a failure.

## What it does not do

- It does not fix anything. It reads.
- It does not run JavaScript. That is the point: it sees what a non-browser agent sees.
- It does not measure answer-engine citations. That half stayed in ops-toolkit; see `docs/implementation-notes/SPEC-232-web-drift.md`.
- It does not follow a URL that came from remote content off the audited host. See `SPEC.md` for the full SSRF invariant table.

## Files

| File | What |
|---|---|
| `webcheck.py` | CLI: `sites` and `audit`, plus the printers |
| `core.py` | the three tiers, the fetch layer, and the SSRF guards |
| `SPEC.md` | the tool contract: surface, hard-fail-vs-warning rule, request budget, SSRF invariants |
| `tests/test_webcheck.py` | 66 plain-assert tests, pytest-discoverable and standalone-runnable |
| `docs/proof-of-done.md` | the recorded verification, including the two live runs |

## Tests

```bash
bash tests/test-webcheck.sh              # from the kit root, pytest via uv
python3 lib/webcheck/tests/test_webcheck.py   # standalone, no pytest needed
```

## Origin

Graduated from `ops-toolkit/tools/seo-geo-check` (the audit half). The rubric it encodes comes
from is-agentic.com's published framework; the per-check fix recipes live in the skill.
