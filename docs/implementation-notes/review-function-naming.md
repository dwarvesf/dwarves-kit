# Implementation notes: SPEC-090 review-function naming migration (kit-hardening SG-02)

Delta from SPEC-090 / ADR-0029. Decisions the spec/ADR did not fully pin down.

## 2026-07-02 Live-surface vs historical-exempt scoping

Context: ADR-0029's migration step 3 says "prose mentions in historical
`docs/research/` snapshots are exempt", but does not enumerate every historical
bucket, and the rename touches ~50 reference sites across a repo that also has
`docs/decisions/`, `docs/specs/`, `docs/implementation-notes/`, `docs/retro/`, and
`CHANGELOG.md`.
Decision: scoped the rename to the LIVE dispatch surface only , `agents/`,
`commands/`, `lib/`, `tests/`, and four canonical live docs (`MANUAL.md`,
`README.md`, `docs/architecture.md`, `WORKFLOW.md`). Everything under
`docs/decisions/`, `docs/specs/`, `docs/implementation-notes/`, `docs/retro/`,
`docs/research/`, and `CHANGELOG.md` keeps the old names untouched, including
ADR-0029 itself (which IS the rename map and must keep old names to be legible)
and the two real historical spec files `docs/specs/SPEC-021-integration-checker.md`
/ `SPEC-022-doc-verifier.md`.
Why: a historical record documents what shipped under the old convention at the
time; rewriting it to the new names would falsify the record and break any reader
tracing "what was this called when X happened". The live surface is what an agent
or command actually dispatches today, so that is where staleness is a real bug,
not a history edit.
Impact: two intentional residual hits survive the live-surface negative-control
greps, both citations rather than dispatch references , `agents/integration-verifier.md:106`'s
`Source:` line cites (a) the external GSD repo's actual filename
`agents/gsd-integration-checker.md` (not ours to rename) and (b) our own exempt
`docs/specs/SPEC-021-integration-checker.md` (the real, unrenamed filename; citing
it under any other name would be a broken pointer). Both are noted in
SPEC-090 AC4 rather than silently left.
Alternatives considered: blind-sed the whole repo (rejected , falsifies history,
and ADR-0029 explicitly warns against blind `sed s/reviewer/`); grep-exclude by
directory glob only (adopted, this note documents the exact boundary).

## 2026-07-02 `agent-effectiveness` + `advisor` named-noun exception in the enforcement rule

Context: ADR-0029's positive axis says every review-function name ends in
`-reviewer` (static) or `-verifier` (dynamic) or `-team` (panel command), plus
`advisor` as "the single cross-cutting generic lens...legitimately its own noun,
not per-artifact." `agent-effectiveness` (SPEC-088, kit-hardening SG-01) shipped
after ADR-0029 was drafted and does not end in any of the three suffixes.
Decision: `test-meta.sh`'s new `is_on_review_axis` check treats `agent-effectiveness`
as a second allowed named-noun exception, alongside `advisor`, and the test carries
an inline comment saying so (not just this note) so a future reader auditing the
enforcement code does not "fix" it into `agent-definition-reviewer` or similar.
Why: `agent-effectiveness` reviews an AGENT DEFINITION (a kit-authoring artifact),
not a V-model work artifact (spec/design/code/docs) the way every `-reviewer` /
`-verifier` does. It is a structurally different validator, one level up from the
V-model the naming axis was built to describe , the same reasoning ADR-0029
already applied to `advisor`.
Impact: the enforcement rule's positive-axis set is `{task-verifier, doc-verifier,
integration-verifier, code-reviewer, security-reviewer, agent-effectiveness}`,
enumerated explicitly in `tests/test-meta.sh` rather than derived from a glob, so
adding a future review agent requires a deliberate edit to that list (a legibility
choice matching the ADR's "fails closed" design, not a doc oversight).
Alternatives considered: renaming `agent-effectiveness` to fit the suffix (rejected ,
churn on a just-shipped, already-conforming-by-different-axis agent; also the ADR's
own SPEC-088 relates-to line treats it as a sibling of `advisor`, not a rename
candidate); deriving the review-agent set programmatically from a directory
convention (rejected , no such convention exists yet, and an explicit list is what
the ADR's "fails closed" design calls for at this scale).
