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

## 2026-08-24 12:10 Skill does not dispatch kit:audit-scanner

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
