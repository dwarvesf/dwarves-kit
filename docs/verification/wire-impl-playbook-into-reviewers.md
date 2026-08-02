# Proof of done: wire impl-playbook into review-team agents

## Hypothesis

Adding pointers to `~/.claude/docs/impl-playbook/*.md` inside the review-team agent
definitions (`security-reviewer.md`, `code-reviewer.md`, `infra-reviewer.md`,
`frontend-reviewer.md`) makes those agents actually consult and apply the referenced rules,
not just carry inert prose nobody reads.

Files touched, one line each:
- `agents/security-reviewer.md`: checklist items now cite `security.md` (numbered rules),
  `threat-modeling.md` (STRIDE pass), `financial-data-handling.md` (money/ledger diffs).
- `agents/code-reviewer.md`: architecture lens cites `coding-hygiene.md`; test-coverage lens
  cites `testing-strategy.md` + `test-case-design.md`.
- `agents/infra-reviewer.md`: cites `cloudflare.md` when the diff touches CF.
- `agents/frontend-reviewer.md`: cites `frontend-design-engineering.md`'s reduced-motion rule.

Deliberately NOT wired: `api-reviewer.md`, `performance-reviewer.md`, `advisor.md` , no
impl-playbook file genuinely matches their lens; a forced citation would be padding.

## Test design

Dispatch `kit:security-reviewer` (the most consequential of the four) against a small
synthetic diff, twice: once with the wiring in place, once with `agents/security-reviewer.md`
reverted (`git stash`) to its pre-change state, same diff both times. If the wiring is
load-bearing, the wired run should differ from the unwired run in a way traceable to the
added pointers (an explicit citation, or a finding the checklist item specifically calls for).

## Runs

### Run 1 (wired): timing bug + `pip audit` typo, mixed in one file

Command: dispatch `kit:security-reviewer` against a staged `scratch-proof/auth.py` containing
a non-constant-time password compare, an undefined-function auth path, and a
`subprocess.run(["pip", "audit"])` call.
Result: found the timing bug (2 Critical), correctly identified `pip audit` as broken
(un-checked in Dependency risks). Did not cite `security.md` by name. Did not flag the
missing-security-logging rule (security.md rule 10 / OWASP A09) added to the Data-exposure
checklist item.

### Run 2 (negative control, unwired): same diff, `security-reviewer.md` reverted

Command: `git stash push -- agents/security-reviewer.md`, same dispatch, same diff.
Result: found the same timing bug (1 High, slightly different severity framing) and
independently flagged `pip audit` as dead/broken code , same conclusion, unprompted by the
wiring. This is the agent's own baseline Python knowledge, not the playbook citation.
Confirms Run 1's `pip audit` catch was NOT attributable to the wiring.
`git stash pop` restored the wiring after this run.

### Run 3 (wired): isolated single-issue snippet

Command: replaced the scratch file with a 7-line snippet using `hmac.compare_digest`
correctly, to remove the non-constant-time bug and isolate whatever else the checklist finds.
Result: still flagged a timing-enumeration issue (the `or` short-circuit skips
`hash_password()` on a miss, my snippet didn't actually fix that), AND this time explicitly
cited the wiring: High finding 1 says "confirm it uses argon2id or bcrypt... per
`docs/impl-playbook/security.md`." First run of the three where the citation appears.
Missing-security-logging rule still not surfaced as a standalone finding.

## Verdict

**Partial, honest result, not a clean pass.** The wiring is demonstrably consulted (Run 3
cites the file by path), and the four files' additions are structurally identical
(a real, existing file:section pointer, verified to exist by direct Read before writing).
But the specific new sub-item added to the Data-exposure checklist (OWASP A09 / security
logging) did not independently surface as a headline finding in any of the three runs , in
every synthetic snippet a more severe finding (timing side-channel) took priority, which is
arguably correct triage behavior for a real reviewer, not a wiring failure, but it means this
one sub-item's uptake is unproven by this test. Recorded here rather than papering over it.

Scratch test files (`scratch-proof/`) were never committed, only staged transiently during
each run and removed after. No repo state changed by the test itself.

## Scope note

`agents/security-reviewer.md`, `agents/code-reviewer.md`, `agents/infra-reviewer.md`,
`agents/frontend-reviewer.md` are the actual shipped change. This file is the proof.
