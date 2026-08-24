# SPEC-232: web-drift, an audit loop over live public websites

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Foundation:** `docs/patterns/audit-loop.md` (four slots, verdict grammar). **Mirrors:** `skills/doc-drift/SKILL.md` (general-purpose, always-PR apply). **Precedent:** `lib/bench/` (vendored stdlib-Python module), `hooks/money-gate.py` (`MONEY_GATE_REPOS`, the env-only no-default consumer knob). **Source:** `ops-toolkit/tools/seo-geo-check` (read-only origin), `ops-toolkit/research/2026-08-23-is-agentic-rubric-and-dwarves-baseline.md` (the fix recipes).

## Problem

Every audit-loop instance the kit ships points at the checkout: docs against code,
the registry against the path index, board rows against git. None of them can answer
"are our live public websites still readable by an agent". That question has a real
answer surface today, an HTTP probe, and a real cost when it drifts: a deploy that
gates the page body behind a client-side flag drops the site to zero visible text
for any agent that does not run JavaScript, and nothing in the repo notices.

The measurement already exists as a matured ops-toolkit tool. It is stdlib-only,
SSRF-hardened, and covers three tiers (page, groundwork, API). It is not reachable
from the kit, and it is coupled to one tenant's question bank on its geo half.

## Decision

Vendor the AUDIT half into `lib/webcheck/` and add `skills/web-drift/SKILL.md`, an
audit-loop instance whose Tier 1 IS that tool. The tenant list is a consumer knob with
no default. The geo-probe half stays in ops-toolkit.

### What graduates, what stays

| Origin file | Disposition | Why |
|---|---|---|
| `seo_geo_check/core.py` | graduates as `lib/webcheck/core.py`, unchanged logic | the whole audit half: page, groundwork, and API tiers plus the SSRF guards |
| `seo_geo_check/cli.py` | graduates as `lib/webcheck/webcheck.py`, geo subcommand dropped, `sites` verb added | the audit CLI path |
| `seo_geo_check/geo.py` | stays | shells out to the `claude` CLI, reads a tenant question bank, appends to a path inside a sibling ops-toolkit tool |
| `questions.toml` | stays | Dwarves pillars and tracked domains, tenant data |
| `pyproject.toml`, `uv.lock`, `.venv` | dropped | kit style is bare stdlib modules; no packaging ceremony |
| 61 of 71 tests | graduate as `lib/webcheck/tests/test_webcheck.py` | every test that does not import `geo` |
| 10 geo tests | stay | they test `geo.py` |

The SSRF hardening ports byte-for-byte: `_SameHostRedirectHandler`, the
`follow_redirects=False` probes, `pin_host` on sitemap fan-out, `same_host_urls`,
`_probe_allowed`, and the DOCTYPE/ENTITY refusal in `parse_sitemap`. Their tests port
with them.

### The four slots

| Slot | This instance |
|---|---|
| Item set | every URL in `WEB_DRIFT_SITES` (comma or whitespace separated). Unset means no sites are declared and the skill stops; the kit ships no tenant hostname. `python3 lib/webcheck/webcheck.py sites` is the enumerator. |
| Contract | each site stays readable and actionable by an agent that runs no JavaScript: the groundwork tier (robots, sitemap, llms.txt, unknown-path status, markdown negotiation with `Vary`), the page tier (title, meta description, one h1, 500+ visible characters, canonical, OG, JSON-LD, internal links), and the API tier when the site shows an API surface |
| Evidence class | live HTTP responses from `python3 lib/webcheck/webcheck.py audit <url>`. A hard fail and a warning are both quoted evidence. A site that does not answer is UNSURE, never REMOVE. |
| Apply mechanics | the kit repo cannot fix a live site. The apply is a report plus one board row per FIX in the CONSUMER repo that owns that site's source, in the shared kanban format. No code edit lands in this repo. |

### Verdict mapping

| Tool output | Verdict |
|---|---|
| hard fail | FIX, with the tool's own recommendation as the "say how" |
| warning, unambiguous fix | FIX |
| warning whose fix depends on intent (metadata length, internal-link count) | UNSURE |
| site unreachable, network error, non-200 groundwork fetch | UNSURE |
| tier reports not applicable | not a finding, excluded from the denominator |
| the site instructs something now wrong (a doc-shaped llms.txt pointing agents at a dead surface) | DANGER |

REMOVE has no meaning here: a live site is never superseded by a named artifact from
inside this repo.

### Tier 2 does not dispatch kit:audit-scanner

`agents/audit-scanner.md` carries a file-oriented read-only roster with no network
verb. HTTP evidence is unreachable from it. The skill says so and keeps Tier 2 as the
lead reading the tool's output against the fix-recipe table.

## Wiring (one edit per surface)

| Surface | Edit |
|---|---|
| `lib/webcheck/` | new module: `core.py`, `webcheck.py`, `tool.toml`, `README.md`, `SPEC.md`, `docs/proof-of-done.md`, `tests/test_webcheck.py` |
| `skills/web-drift/SKILL.md` | new skill, auto-namespaced `kit:web-drift`, frontmatter `name` + long-form `description` with NOT-for clauses + `disable-model-invocation: false` |
| `tests/test-webcheck.sh` | root wrapper running the Python suite under `uv run --with pytest`, mirroring `tests/test-sync.sh` |
| `.github/workflows/test.yml` | one step running that wrapper |
| `lib/config/module-registry.md` | one `WEB_DRIFT_SITES` row, env-only, no default |
| `commands/onboard.md` | section D names `WEB_DRIFT_SITES` among the env-only knob examples |
| `docs/patterns/audit-loop.md` | the Known instances section gains web-drift |

## Non-goals

- No `bin/webcheck`. ADR-0034 decision 7 admits subsystem entries and module CLIs only; webcheck is neither.
- No auto-fix of any website. The apply is a report plus board rows.
- No geo-probe, no answer-engine citation measurement, no question bank.
- No new install module, no new hook, no scheduled job.
- No tenant hostname anywhere in the tree.

## After state

- `python3 lib/webcheck/webcheck.py audit <url>` runs the three tiers and exits non-zero on a hard fail.
- `python3 lib/webcheck/webcheck.py sites` prints the declared sites, or prints the inert message and exits 0 when `WEB_DRIFT_SITES` is unset.
- `kit:web-drift` is discoverable and states its own four slots, its verdict mapping, and its fix-recipe reference table.
- `bash tests/test-webcheck.sh` runs 61 ported tests plus the new resolver tests, all green.
- `tests/test-kit-contract.sh` gains no new C3 or C4 offender.
- The kit tree still contains no tenant hostname (`tests/test-no-personal-paths.sh` green).

## Test plan

| Category | Case | Where |
|---|---|---|
| Ported behavior | all 61 non-geo tests from the origin suite | `lib/webcheck/tests/test_webcheck.py` |
| SSRF | off-host redirect refused on a pinned page fetch | ported |
| SSRF | reach probe never follows a redirect | ported |
| SSRF | off-host and non-http API base recorded, never fetched | ported |
| SSRF | sitemap URLs split on host before fan-out | ported |
| SSRF | sitemap XML with a DOCTYPE refused | ported |
| Consumer knob | `WEB_DRIFT_SITES` unset: `sites` exits 0 with the inert message and no URL | new |
| Consumer knob | comma separated, whitespace separated, and mixed lists all parse | new |
| Consumer knob | a colon inside a URL never splits | new |
| Negative control | break the same-host redirect guard, the SSRF tests go red, restore | recorded in proof-of-done |
| Live | `audit https://memo.d.foundation` | recorded in proof-of-done |
| Live | `audit https://dwarves.foundation` | recorded in proof-of-done |

## Verification

- `bash tests/test-webcheck.sh` exits 0 and reports the full ported count.
- `WEB_DRIFT_SITES` unset, `python3 lib/webcheck/webcheck.py sites` prints the documented inert line and exits 0.
- `python3 lib/webcheck/webcheck.py audit https://memo.d.foundation --limit 1` prints a groundwork block, an api-tier block, and a page block, with a SUMMARY line.
- `python3 lib/webcheck/webcheck.py audit https://dwarves.foundation --limit 1` prints the same three blocks.
- `bash tests/test-kit-contract.sh` C3 and C4 offender lists are unchanged from the pre-branch baseline.
- `bash tests/test-no-personal-paths.sh` exits 0.
- `grep -r 'd.foundation' lib/webcheck skills/web-drift` returns nothing.
