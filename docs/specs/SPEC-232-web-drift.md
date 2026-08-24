# SPEC-232: web-drift, an audit loop over live public websites

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Foundation:** `docs/patterns/audit-loop.md` (four slots, verdict grammar). **Mirrors:** `skills/doc-drift/SKILL.md` (general-purpose, always-PR apply). **Precedent:** `lib/bench/` (vendored stdlib-Python module), `hooks/money-gate.py` (`MONEY_GATE_REPOS`, the env-only no-default consumer knob). **Source:** `ops-toolkit/tools/seo-geo-check` (read-only origin), `ops-toolkit/research/2026-08-23-is-agentic-rubric-and-dwarves-baseline.md` (the fix recipes).

## Problem

No audit-loop instance the kit ships audits a public HTTP surface. Four of the five
point at the checkout (docs against code, the feature registry against the path index,
a module's spec against its source, board rows against git). The fifth, `ci-drift`,
does reach the network, but at GitHub's control plane, not at anything a visitor sees.
So none of them answers "are our live public websites still readable by an agent".

That question has a real answer surface, an HTTP probe, and a real cost when it drifts:
a deploy that gates the page body behind a client-side flag drops the site to zero
visible text for any agent that does not run JavaScript, and nothing in the repo notices.

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
| Item set | one `(site, check)` pair. Site axis: `WEB_DRIFT_SITES`, comma or whitespace separated, enumerated by `python3 lib/webcheck/webcheck.py sites`. Check axis: fixed by the contract. The item is not the site, because a site with one hard fail and eight warnings has no single verdict and a not-applicable tier has to leave the denominator. Unset `WEB_DRIFT_SITES` means no sites are declared and the skill stops; the kit ships no hostname. |
| Contract | each site stays readable and actionable by an agent that runs no JavaScript: the groundwork tier (robots, sitemap, llms.txt, unknown-path status, markdown negotiation with `Vary`), the page tier (title, meta description, one h1, 500+ visible characters, canonical, OG, JSON-LD, internal links), and the API tier when the site shows an API surface |
| Evidence class | live HTTP responses from `python3 lib/webcheck/webcheck.py audit <url>`, saved to a file so Tier 2 can read them. A hard fail and a warning are both quoted evidence. No response is not evidence. |
| Apply mechanics | this repo holds no website source, so no code edit lands here. The apply is a report plus one row per FIX appended to the `_meta/BACKLOG.md` of the CONSUMER repo that owns that site's source, in the shared kanban format. `bin/board` has no add verb, so the row is written directly and `board board --backlog-file` / `board set` operate on it from there. |
| Closing evidence | a FIX row closes only when a later `audit <url>` shows that `(site, check)` pair green, and the next run re-audits every site carrying an open row before anything else. Without this the loop cannot fail: a filed row is a proposal, and nothing re-tests a proposal. |

### Verdict mapping

| Tool output | Verdict |
|---|---|
| hard fail | FIX, with the tool's own recommendation as the "say how" |
| warning, unambiguous fix | FIX |
| warning whose fix depends on intent (metadata length, internal-link count) | UNSURE |
| site unreachable, network error, non-200 groundwork fetch | UNTESTABLE, the pattern's own class for evidence you cannot test from where you run. Not UNSURE, which reserves the operator's attention for questions only the operator can answer; a transient 503 is not one. |
| tier reports not applicable | not a finding, excluded from the denominator |
| a declared site is permanently gone and a successor is named | REMOVE, against the consumer's `WEB_DRIFT_SITES` entry, never against the site |
| the site instructs something now wrong (a doc-shaped llms.txt pointing agents at a dead surface) | DANGER |

DANGER never comes from Tier 1: the tool checks that llms.txt answers and carries an
orientation section, and never follows the links inside it. The verdict requires the
lead to read those bodies and quote the contradiction, and the skill says so rather
than implying a check that does not exist.

### Tier 2: the lead gathers, the scanner judges

`agents/audit-scanner.md` cannot FETCH (no network verb), but it has `Read`, so it can
judge saved evidence. `ci-drift` already runs exactly this split: a network Tier 1 over
`gh api`, a file-reading Tier 2. web-drift follows it. Tier 1 saves its output to a
file; Tier 2 dispatches the scanner over those files plus this instance's contract for
a multi-site run, and the lead reads them inline for a one or two site run, where a
subagent would cost more than the table lookup it performs.

## Wiring (one edit per surface)

| Surface | Edit |
|---|---|
| `lib/webcheck/` | new module: `core.py`, `webcheck.py`, `tool.toml`, `README.md`, `SPEC.md`, `docs/proof-of-done.md`, `tests/test_webcheck.py` |
| `skills/web-drift/SKILL.md` | new skill, auto-namespaced `kit:web-drift`, frontmatter `name` + long-form `description` with NOT-for clauses + `disable-model-invocation: false` |
| `tests/test-webcheck.sh` | root wrapper running the Python suite via `uv run --no-project --with pytest`, mirroring `tests/test-sync.sh` |
| `.github/workflows/test.yml` | one step running that wrapper. The workflow is `workflow_dispatch` only, so this buys a manual-run slot, not gating CI; the runnable entry that `tests/test-kit-contract.sh` C4 looks for is the wrapper itself |
| `lib/config/module-registry.md` | one `WEB_DRIFT_SITES` row, env-only, no default, with the separator deviation stated |
| `commands/onboard.md` | section D names `WEB_DRIFT_SITES` among the env-only knob examples and quotes its separator |
| `docs/patterns/audit-loop.md` | the Known instances section gains web-drift, and the "all instances dispatch audit-scanner" line is amended to name web-drift's gather-then-judge order |
| `docs/FEATURES.md` | regenerated (`bash lib/registry/feature-registry.sh generate`); it is a generated projection whose freshness `tests/test-meta.sh` pins |

## Non-goals

- No `bin/webcheck`. ADR-0034 decision 7 admits subsystem entries and module CLIs only; webcheck is neither. `lib/bench` is the precedent for the third shape: an operator-typed CLI inside a `lib/` module with a `tool.toml` and no `bin/` entry.
- No auto-fix of any website. The apply is a report plus board rows.
- No geo-probe, no answer-engine citation measurement, no question bank.
- No new install module, no new hook, no scheduled job.
- No tenant hostname in shipped code, defaults, fixtures, or the skill. Prose that names a site as an example (this spec's own Verification section) is not a default and does not ship in a code path.

## After state

- `python3 lib/webcheck/webcheck.py audit <url>` runs the three tiers and exits non-zero on a hard fail.
- `python3 lib/webcheck/webcheck.py sites` prints the declared sites, or prints the inert message and exits 0 when `WEB_DRIFT_SITES` is unset.
- `kit:web-drift` is discoverable and states its own four slots, its verdict mapping, and its fix-recipe reference table.
- `bash tests/test-webcheck.sh` runs 61 ported tests plus the new resolver tests, all green.
- `tests/test-kit-contract.sh` gains no new C3 or C4 offender.
- `docs/FEATURES.md` regenerates clean, so `tests/test-meta.sh` gains no new failure.
- No file this branch adds carries a tenant hostname.

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
- `bash tests/test-kit-contract.sh` C3 and C4 offender lists are unchanged from the pre-branch baseline (both already red on master for `lib/bench`).
- `bash tests/test-meta.sh` fails the same seven assertions as the pre-branch baseline, no more.
- `bash tests/test-no-personal-paths.sh` exits 0. Note that this test greps for the operator's home paths only, so it is NOT the guard for a tenant hostname; the guard for that is the grep below.
- `git diff --name-only origin/master | xargs grep -l 'd.foundation'` returns nothing outside this spec's own prose and the proof-of-done's recorded live runs.
