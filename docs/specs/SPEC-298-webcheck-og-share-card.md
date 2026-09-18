# SPEC-298: webcheck flags a share card that social crawlers drop

**Status:** VALIDATED (revised after one validation lens; the check lands in the same PR)
Lane: full
**Proof:** `lib/webcheck/tests/test_webcheck.py`, the SPEC-298 block.

## Problem

The page tier checks that `og:title`, `og:description` and `og:image` exist. It never checks that the image is usable. memo.d.foundation shipped posts whose `og:image` was an SVG. Facebook, LinkedIn and X reject an SVG preview image, so every share rendered a text-only card while webcheck reported the page clean. The Facebook Sharing Debugger also flags a missing `og:url` as a required property, and the page tier does not check it.

## Contract

- `og:url` joins the required OG tags. A page without it reports `missing OG tags: og:url` in the existing warning.
- A page's `og:image` counts as an SVG when any of three holds:
  - `urlsplit(value.strip()).path.lower().endswith(".svg")`. This covers absolute and relative URLs, any case, and ignores a query or fragment.
  - `value.strip().lower().startswith("data:image/svg+xml")`.
  - the page's `og:image:type` meta, stripped and lowercased, equals `image/svg+xml`.
- An SVG `og:image` adds exactly one warning with this fixed text and no page-derived value: `og:image is an SVG, which Facebook, LinkedIn and X drop from share cards`.
- Both findings are warnings. Neither is a hard fail, which matches how missing OG tags already report.
- No new HTTP request. The check reads tag values only and never fetches the image.
- `skills/web-drift/SKILL.md` maps the SVG warning to FIX, beside "missing OG tag".

## Design record

Checking tag values alone keeps the page tier at its fixed request budget (`lib/webcheck/SPEC.md`, budget section). Reading `og:image:type` is free and catches an SVG served from a non-`.svg` path when the page declares it. Sniffing the served content type would catch an undeclared one too, but it costs one request per page and that case was not seen in the wild. A warning, not a hard fail, keeps the verdict grammar consistent with the other OG findings. The warning carries no page value, so it cannot forge a report line.

## Test plan

| Case | `og:image` input | Expected |
|---|---|---|
| raster, all tags | `https://docs.example.com/img.png` (GOOD_HTML, which now carries `og:url`) | no OG warning at all |
| absolute SVG | `https://x/a/fig.svg` | the SVG warning, no hard fail |
| uppercase with query | `https://x/fig.SVG?v=2` | the SVG warning |
| fragment | `https://x/fig.svg#x` | the SVG warning |
| relative | `/img/fig.svg` | the SVG warning |
| padded | `  https://x/fig.svg  ` | the SVG warning |
| data URI | `data:image/svg+xml,<svg/>` | the SVG warning |
| declared type | `https://x/card.png` plus `og:image:type` = `image/svg+xml` | the SVG warning |
| `svg` mid-path only | `https://x/svg/fig.png` | no SVG warning |
| missing og:url | GOOD_HTML without `og:url` | `missing OG tags: og:url` |

## Verification

`python3 -m pytest -q lib/webcheck/tests` runs the SPEC-298 block with the rest of the suite. Live check: `python3 lib/webcheck/webcheck.py audit https://memo.d.foundation/macbook-notch-macos-27` reports no SVG warning and no missing `og:url` after foundation-apps#126 and #127.

## Out of scope

No image fetch, no content-type sniff of the served image, no `fb:app_id` check. `fb:app_id` only enables Facebook Insights and is not a share-card defect.
