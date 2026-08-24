# Implementation notes: SPEC-232 web-drift

Delta from the spec only. Each entry records a decision the spec left open, a deviation, a
tradeoff, or an open question for the operator.

## 2026-08-24 10:20 No bin/ shim for webcheck

Context: the brief asked whether ADR-0034 decision 7 demands a `bin/` entry at this status.
Decision: no `bin/webcheck`.
Why: decision 7 admits exactly two classes into `bin/`. Subsystem entries (`board`, `gate`,
`spec`, ...) are subsystems of the always-on engine. Module CLIs (`prose-rag`,
`worktree-provision`) are opt-in install units whose name is the module key in
`install.sh KIT_KNOWN_MODULES`. `webcheck` is neither. It is a vendored audit tool one skill
calls, the same shape as `lib/bench`, which also ships no `bin/` entry.
Alternatives: adding `bin/webcheck` as a third class. Rejected, it erases the module/subsystem
distinction the installer relies on, which decision 7 names as its own rejected option.
Caveat the ADR does not cover: its bin-less list reads "internal libs, command-invoked, not
operator CLIs", and webcheck IS an operator CLI. The precedent that actually covers this shape
is `lib/bench`, an operator-typed CLI inside a `lib/` module with a `tool.toml` and no `bin/`
entry. That shape is the citation, not the ADR's bin-less sentence.
Impact: the invocation is `python3 lib/webcheck/webcheck.py audit <url>`, as the skill states.
Open questions: if webcheck ever becomes a `--with` install module, it earns a `bin/` entry
under the module-CLI class at that point.

## 2026-08-24 10:35 The geo-probe half stays behind

Context: the brief allowed taking `geo.py` only if it cost nothing.
Decision: leave `geo.py`, `questions.toml`, and their ten tests in ops-toolkit.
Why: the cost is not zero. `geo.py` reads a tenant-specific question bank (Dwarves pillars,
`memo.d.foundation` tracked domains), shells out to the local `claude` CLI, and appends to
`MEASURE_LOG_PATH`, a relative path into a sibling ops-toolkit tool
(`../../content-radar/docs/measure-log.md`). Each of those three is a tenant coupling the kit
forbids under the adapter-default invariant. Porting them means inventing a kit-side question
bank and a kit-side measure log, which is new work, not a graduation.
Impact: 61 of the 71 tests port. The ten geo tests stay behind with `geo.py`.
Open questions: an answer-engine citation probe is a plausible future kit skill. It needs its
own spec, not a silent ride along on this one.

## 2026-08-24 11:05 lib/webcheck/SPEC.md exists alongside docs/specs/SPEC-232

Context: `tests/test-kit-contract.sh` C3 requires every `lib/*/tool.toml` module to carry a
README, a SPEC, and `docs/proof-of-done.md`. The cycle spec lives at repo level per CLAUDE.md.
Decision: `docs/specs/SPEC-232-web-drift.md` is the cycle spec; `lib/webcheck/SPEC.md` is the
tool contract.
Why: they carry different content. The cycle spec covers the graduation and the skill. The tool
contract covers what the tool checks, its request budget, and its SSRF invariants, which is
what a future editor of `core.py` needs and what `lib/bench` is currently missing (it is the
named C3 offender on master).
Alternatives: skipping the module SPEC and accepting a new lint offender. Rejected, the run
would ship the repo dirtier than it found it.
Impact: two files, no duplicated prose.

## 2026-08-24 11:40 WEB_DRIFT_SITES separator is whitespace or comma, not colon

Context: the brief flagged that the `MONEY_GATE_REPOS` precedent is colon-separated but URLs
carry colons.
Decision: split on commas and whitespace. A colon never separates.
Why: `https://memo.d.foundation` contains a colon in a position no splitter can distinguish
from a separator. Comma is the ordinary list separator; whitespace makes a multi-line
`export` readable.
Impact: documented in the registry row, the skill, and `lib/webcheck/README.md`. `webcheck
sites` is the one resolver, so no second parser can drift from it.

## 2026-08-24 12:10 Skill does not dispatch kit:audit-scanner (SUPERSEDED at 13:15)

Context: every other in-kit audit-loop instance dispatches the shared read-only scanner for
Tier 2.
Decision: web-drift dispatches no scanner. It says so explicitly in its Process section.
Why: `agents/audit-scanner.md` carries a file-oriented, read-only tool roster (Read, Grep,
Glob, and shell verbs over the checkout). It has no network verb. HTTP evidence is not
reachable from that roster, so dispatching it would produce a confident verdict from no
evidence, which the audit-loop grammar calls UNSURE.
Impact: Tier 1 is the Python tool and carries the whole mechanical pass. Tier 2 is the lead
reading the tool's output plus the fix-recipe table. Cheaper than the other instances, not
more expensive.
Open questions: a network-capable read-only scanner agent would let web-drift join the shared
Tier 2 path. Out of scope here.

## 2026-08-24 13:15 Design critique reversed four decisions

Context: the design-critique gate (`kit:advisor`, critique mode over the spec) returned 13
findings. Four changed the design rather than the prose.

1. **The item is a `(site, check)` pair, not a site.** The first draft declared the item set at
site granularity while verdicting tool outputs and excluding not-applicable tiers from the
denominator. Those cannot both be true. A site with one hard fail and eight warnings has no
single verdict.

2. **The apply gained a closing rule.** A board row filed in another repo is a proposal, and
nothing re-tested it, so no run could ever fail. A FIX row now closes only when a later audit
shows that pair green, and the next run re-audits every site carrying an open row first.

3. **The refusal to dispatch `kit:audit-scanner` was a rationalization.** The draft argued HTTP
evidence is unreachable from the scanner's roster. `ci-drift` disproves that: its Tier 1 is
`gh api` over the network and it still dispatches the scanner, because the lead gathers and the
scanner reads. The correct statement is narrower, the scanner cannot FETCH. web-drift now saves
Tier 1 output to a file and dispatches the scanner over it for multi-site runs, inline for one
or two sites where a subagent costs more than the table lookup.

4. **UNTESTABLE is a real verdict and the draft collapsed it into UNSURE.** The pattern names it
and `agents/audit-scanner.md` emits it. UNSURE means only the operator can answer; routing every
transient 503 there escalates a network hiccup to a human forever.

Also corrected: DANGER had no producing mechanism (Tier 1 never reads the llms.txt body, so the
skill now says the verdict requires the lead to read it); REMOVE does apply, against the
consumer's `WEB_DRIFT_SITES` entry rather than against a live site; the Problem statement claimed
every instance points at the checkout, which `ci-drift` contradicts; and
`tests/test-no-personal-paths.sh` was cited as the tenant-hostname guard when it greps operator
home paths only, a vacuous citation now replaced with a real grep.

Deliberately not acted on: the drifted `bin/` census in ADR-0034 (18 live entries against a
stated target of 13) and `ci-drift`'s absence from the pattern's Known-instances section beyond
the one line this branch adds. Both are pre-existing drift in files this branch does not own,
and a doc-drift run is their home.

Open questions for the operator: the closing rule assumes the consumer repo has a kit board.
For a consumer repo with no board the skill falls back to the report alone, which loses the
closing evidence. Worth deciding whether web-drift should refuse to file against a boardless
repo or keep a local ledger.

## 2026-08-24 13:40 Skill frontmatter description is a flat scalar, not a block scalar

Context: the description was first written as a `>-` block scalar for readability.
Decision: flat one-line scalar, matching every other skill in `skills/`.
Why: `lib/registry/feature-registry.sh` reads the description with a line-oriented parser. A
block scalar makes it emit the literal `>-` as the description into `docs/FEATURES.md`, which
`tests/test-meta.sh` then pins as fresh. The generator, not taste, decides this.
Impact: one long line in the frontmatter. Fixing the generator is a separate change.

## 2026-08-24 15:30 The port inherited an SSRF hole, and my own claim hid it

Context: the security-review gate reproduced a working SSRF against the vendored tool using two
loopback servers.
Decision: `fetch_ex` pins every fetch by default; there is no cross-host mode.
Why: the origin guarded the three DERIVED-URL classes (sitemap entries, openapi `servers[0]`, an
llms.txt base) and stopped there. The six fetches against the audited host's own robots.txt,
sitemap.xml, llms.txt, homepage, markdown negotiation, and `/openapi.json` fell through to a bare
`urlopen`, which follows a 302 anywhere. Since the threat model already calls the audited site
hostile, that turns the auditor into an internal port scanner whose findings get printed: the
repro read an internal service and printed its banner as `info.title`.

The root cause was the shape of the fork, not any one call site. `fetch_ex` chose an unpinned
opener whenever no `allowed_host` was passed, so unpinned was the DEFAULT and each of the six
call sites was merely exercising it. Patching six call sites would have left the seventh to
whoever adds a check next. The pin now derives from the requested URL, so an unpinned fetch is
not expressible.

What made this worse than an inherited bug: the module docstring I wrote for the port claimed
"Every outward fetch is host-pinned or redirect-refusing", and the `SPEC.md` invariant table I
wrote listed only the three derived-URL rows. The claim was broader than the table, and the
table was narrower than the code needed. A reader checking the guard would have read the
docstring and stopped. Writing an invariant is a promise to test it; the table now names a test
per row, and the two rows that did not exist are the two that were missing.

Alternatives: patch the six call sites (rejected, leaves the default wrong); add an
`allow_cross_host` escape for the operator-named target so an apex-to-www redirect still follows
(rejected, it reintroduces the hole for the exact input the threat model distrusts, and an audit
tool reporting "your declared URL 302s to X, declare X" is better behavior than silently
following).
Impact: `audit_page`'s `pin_host` parameter became a no-op and is gone. The port-fidelity claim
in the proof-of-done is retired: the port was faithful, and faithful was not safe.
Open questions: **the same hole is live in `ops-toolkit/tools/seo-geo-check`, which this branch
treated as read-only source.** It needs the same fix, and that is a separate change in a
separate repo. Flagged for the operator, not silently fixed from here.

## 2026-08-24 15:45 Two negative controls, because one of them would have passed

Context: the pre-fix suite reported a green 66 while the SSRF was live.
Decision: the proof records a control on the redirect handler AND a control on the default pin.
Why: reverting the handler class fails one test on both the vulnerable and the fixed code, so it
proves nothing about this fix. Reverting the default pin fails exactly the six tests that encode
the fixed invariant. A negative control has to target the line the fix changed, not the nearest
component with a test on it, or it certifies the wrong thing. This is the concrete reason the
original green run was not evidence.
Impact: `docs/proof-of-done.md` carries both, and says which one is load-bearing.

## 2026-08-24 15:55 Accepted the architecture review; two findings noted, not fixed

Acted on: the `agents/audit-scanner.md` contradiction (its body said "You gather and judge
evidence" against the gather-then-judge rule this branch added to the pattern, and a dispatched
scanner reads its own body, not the pattern doc); `JsonLdInfo.parse_errors` counted but never
read, so a page whose JSON-LD all failed to parse reported "no JSON-LD found", which is a lie the
counter was written to prevent; the write-only `ApiAudit.rate_limit_url`; a third copy of the
findings-printer; a hardcoded test count in the README; an undefined `$KIT` in the skill; and the
standalone runner now runs in CI so it cannot rot behind the pytest path.

Not fixed, deliberately: `core.py` carries four responsibilities in 776 lines, and splitting it
today buys nothing while each tier is already independently callable and tested. `WEB_DRIFT_*`
sits outside the config drift lint's fixed prefix family, so a future `WEB_DRIFT_*` orphan would
go uncaught; widening that family is a change to a test this branch does not own, and it belongs
with whoever next touches the lint.
