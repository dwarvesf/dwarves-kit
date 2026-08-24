---
name: web-drift
description: >-
  Use for the live-website agent-readiness audit, "run the web-drift loop", "audit our
  websites", "are our sites still readable by an agent", "web drift sweep", "check the public
  sites", or a scheduled site-audit cadence run. Enumerates every site the consumer declared in
  WEB_DRIFT_SITES, probes each over read-only HTTP with lib/webcheck (groundwork, page, and API
  tiers), verdicts each finding with evidence, and files the fixes as board rows in the repo
  that owns the site's source plus a report. NOT for auditing docs or code inside a checkout
  (that is kit:doc-drift), NOT for the kit's own registry (that is kit:topology-drift), NOT for
  page-speed, Lighthouse, or Core Web Vitals (a different tool and a different question), NOT
  for measuring whether answer engines cite the site (no engine probe ships here), NOT for
  fixing a site (the kit repo holds no website source; this loop files rows, it never edits a
  site).
disable-model-invocation: false
---

# Web drift

## Overview

Audit every declared public website against the agent-readiness contract and file the fixes.
This is the live-site instance of `docs/patterns/audit-loop.md`: enumerate, verdict with
evidence, apply, gate through the operator.

Every other in-kit audit loop points at the checkout. This one points outward. The evidence is
an HTTP response, not a file, and the fix lands in whichever repo builds that site, not here.

The contract this measures: an agent that runs no JavaScript should be able to find the site,
fetch a page, read its content, tell a dead URL from a live one, and call its API if it has
one. A deploy can break any of those silently, and nothing in a repo notices.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | the sites in `WEB_DRIFT_SITES`, enumerated by `python3 lib/webcheck/webcheck.py sites`. Comma or whitespace separated, never colon (every URL carries one). Unset means no sites are declared: report that and stop. The kit ships no hostname. |
| Contract | each site stays discoverable, fetchable, and understandable without JavaScript: the groundwork tier (robots, sitemap, llms.txt, unknown-path status, markdown negotiation with `Vary`), the page tier (title, meta description, one h1, 500+ visible characters, canonical, OG, JSON-LD, internal links), and the API tier where the site exposes an API |
| Evidence class | live HTTP responses, quoted from `webcheck audit` output. A hard fail and a warning are each quoted evidence. No response at all is not evidence. |
| Apply mechanics | no code edit lands in this repo. Each FIX becomes one board row in the CONSUMER repo that owns the site's source, in the shared kanban format (`\| ID \| Item \| Notes & source \| Status \|`, status `queued`), plus a report listing every verdict. UNSURE items go in the report for the operator, never into a row. |

## Verdict mapping

Tier 1 is the tool. Its hard fails and warnings map to the audit-loop grammar:

| Tool output | Verdict | Note |
|---|---|---|
| hard fail | FIX | the tool's own message carries the "say how"; add the recipe from the reference table below |
| warning with one obvious fix (missing canonical, missing OG tag, no Organization block, no llms.txt guidance section) | FIX | |
| warning whose fix depends on intent (meta description length, h1 count, internal-link count, unversioned API base) | UNSURE | someone decided that on purpose or did not; you cannot tell from outside |
| site unreachable, network error, groundwork fetch that did not answer | UNSURE | never REMOVE, and never FIX: with no response there is no checkable evidence |
| tier reports not applicable | not a finding | it drops out of the denominator, the way the rubric excludes a check rather than failing a site it cannot apply to |
| the site actively instructs something now wrong (llms.txt pointing agents at a dead surface, a developer page describing a flow that does not exist) | DANGER | quote the contradiction; an agent will follow it |

REMOVE has no meaning here. A live website is never superseded by a named artifact inside this
repo. If a site should be retired, that is an operator decision, not an audit verdict.

## Tier 2 does not dispatch kit:audit-scanner

The other in-kit instances hand their judgment pass to the shared read-only scanner. This one
does not, and the reason is mechanical rather than stylistic: `agents/audit-scanner.md` carries
a file-oriented roster (Read, Grep, Glob, and shell verbs over the checkout) with no network
verb. It cannot fetch a URL. Dispatching it would produce a verdict from no evidence, which the
pattern's own hard rule calls UNSURE.

So Tier 2 here is the lead reading the tool's output against the fix-recipe table below. That
is cheaper than the other instances, not more expensive: the mechanical pass already carries
every check, and judgment only decides FIX versus UNSURE.

## Process

1. **Enumerate.** `python3 lib/webcheck/webcheck.py sites`. Write the list down before probing
   anything; it is the queue, and a resumed run picks up from it. No sites declared: say so,
   name `WEB_DRIFT_SITES`, and stop. That is a clean result, not a failure.

2. **Tier 1, mechanical, zero model cost, every site.**
   `python3 lib/webcheck/webcheck.py audit <url>` per site. Read the exit code and the three
   blocks. For a site with a sitemap, pass the sitemap URL and a `--limit` so the page tier
   samples rather than crawls; the groundwork and API tiers run once regardless.

3. **Tier 2, judgment, only on what Tier 1 raised.** Map each hard fail and warning through the
   verdict table. Attach the recipe from the reference table to every FIX. Do not re-derive a
   check the tool already ran, and do not open a browser to confirm what the response body
   already says.

4. **Verdict each item** with the audit-loop grammar. A verdict with no checkable evidence
   downgrades to UNSURE. An unreachable site is UNSURE and the run continues to the next site.

5. **Check the evidence is not stale** before filing anything. Compare when you scanned against
   when the site last deployed. A finding measured before the fix deployed is not a finding.
   Name both timestamps in the report.

6. **Apply.** For each FIX, file one row on the board of the repo that owns that site's SOURCE,
   not the repo that owns the domain. A static site built from a separate engine repo takes its
   fix in the engine, and the content repo cannot carry it. Say which repo and why in the row's
   Notes column. Never edit a site from here.

7. **Report.** One table: site, check, verdict, evidence, target repo. List every UNSURE
   separately for the operator. If every site came back clean, file no rows and report CLEAN
   with the enumeration list.

## Fix recipes (reference)

Distilled from a real estate-wide run. Each row is what the fix actually is, not what the check
is named.

| Finding | The fix | The rule behind it |
|---|---|---|
| unknown path answers 200 or 3xx | serve a real 404 status with a body listing sitemap, llms.txt, and home | needs request-time code. A static export alone cannot negotiate or answer a status it did not pre-render; the fix belongs in the worker or server in front of it |
| markdown negotiated without `Vary: Accept` | add `Vary: Accept` at the same layer that negotiates | without it a CDN hands one variant to the wrong client. If the site does not negotiate at all, build the negotiation first, then the header |
| under 500 visible characters without JavaScript | server-render the body: heading plus prose in the raw HTML | a client-side `isClient` gate that returns null on the server exports an empty root div. Bisect by building, not by reading: remove the gate and count `<h1>` and visible characters in the built output |
| no sitemap.xml, no llms.txt | generate both at build time | they are build artifacts, not hand-written files |
| llms.txt is a bare link index | add a "When to use" orientation section | a link list tells an agent what exists, not when to reach for it |
| no canonical, no JSON-LD, no Organization block | emit canonical plus one Organization block per page from the site's own config | read every value from config. Omit a field the content genuinely lacks rather than inventing one |
| API has no /openapi.json, or errors are not JSON | publish an OpenAPI 3.1 spec and make every error route return the same JSON error schema | one schema, referenced consistently, or a client cannot parse failures |
| no RateLimit headers | emit IETF RateLimit headers from the real limiter | count, do not guess. A header stating a budget the server does not enforce is worse than none |
| unversioned API base | put a `/v<n>` segment in the canonical server URL, or state the deprecation policy in `info.description` | a client needs to know when the surface may change |

Three honesty rules that override any score:

- **Never serve JSX-shaped MDX as markdown twins.** If the markdown twin reads worse than the HTML, it is metric gaming and it makes the site worse for the agent it claims to serve.
- **Never fake a sandbox, a key-issuance flow, or a developer surface that does nothing.** A page that looks like an onboarding flow and is not one is a DANGER finding, not a fix.
- **Count, do not guess.** Rate-limit budgets, page counts, and coverage numbers come from the system that enforces them.

And one evidence rule: **a scan is only as fresh as the deploy behind it.** Compare `scanned_at`
against the last deploy of the site's source before you believe a finding.

## Cadence

Run after a deploy of any declared site, before an announcement that points agents at one, or
on a schedule per the audit-loop driver ladder. One pass per invocation, bounded by the
enumeration list.

## Red flags

- Reporting a finding for a site that did not answer: that is UNSURE, always.
- Filing a row against the repo that owns the domain when a different repo owns the site's source.
- Dispatching `kit:audit-scanner` for the HTTP pass: it has no network verb and will answer from nothing.
- Re-running the checks by hand in a browser when the tool already quoted the response.
- Believing a finding measured before the fix deployed.
- Hardcoding a site list anywhere in this repo. The list is the consumer's, and it has no default.
