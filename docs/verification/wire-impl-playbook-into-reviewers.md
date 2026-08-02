# Proof of done: wire impl-playbook into review-team agents

## Hypothesis

Adding pointers to the impl-playbook reference files (at the time, the maintainer's
personal machine-local directory; moved into this repo under `docs/impl-playbook/` on
2026-08-03, see the follow-up section below) inside the review-team agent definitions
(`security-reviewer.md`, `code-reviewer.md`, `infra-reviewer.md`, `frontend-reviewer.md`)
makes those agents actually consult and apply the referenced rules, not just carry inert
prose nobody reads.

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

## 2026-08-03 follow-up: move impl-playbook into the repo

### Problem

The wiring above pointed every citation at `~/.claude/docs/impl-playbook/*.md`, the
maintainer's personal machine-local directory. dwarves-kit is a published, public repo
adopted by other engineers; for anyone but the maintainer that path does not exist, so the
citations were dead on install. Fix: move the actual playbook content into the kit repo
itself, so every adopter gets a working reference, not just the maintainer.

### What moved

All 24 rule files + `README.md` from `~/.claude/docs/impl-playbook/` copied to
`docs/impl-playbook/` in this repo. The source directory is untouched (a separate step
turns it into a symlink); this commit is copy-and-generalize, not move-and-delete.

### Generalization (personal references stripped per file)

Each file was checked for wording that only makes sense with the maintainer's personal
global CLAUDE.md or personal machine paths. No new content was added, only personal
references removed or reworded to state the rule standalone.

| File | What was removed/reworded |
|---|---|
| `README.md` | "routed from the root CLAUDE.md ... table" -> reworded to a standalone description of the folder's purpose |
| `architecture-decision.md` | dropped "per the root CLAUDE.md Tech stack preferences"; reworded "Pairs with the root CLAUDE.md 'Minimum infra first' rule" to a standalone "minimum infra first" reference |
| `bash.md` | dropped "(per the root CLAUDE.md Tech stack preferences)" |
| `go.md` | dropped "(per the root CLAUDE.md Tech stack preferences)" |
| `logging-observability.md` | dropped "and the root CLAUDE.md secret-handling rules" |
| `notification-design.md` | dropped the sentence routing a new scheduled job through the maintainer's personal `vps-mon` tool and `job-monitoring-onboarding` skill, neither of which ships with the kit |
| `python.md` | dropped "(per the root CLAUDE.md Tech stack preferences)" |
| `security.md` | dropped "on top of the root CLAUDE.md Security Rules"; dropped "per the root CLAUDE.md" from the `op://` secrets line; dropped "per the root CLAUDE.md Tech stack preferences" from the `pnpm audit` mention |
| `test-case-design.md` | reworded "past-Han when he reads it in a month" (a personal name) to "your future self reading it in a month" |
| `testing-strategy.md` | dropped "(per the root CLAUDE.md Self-verification rules)" |
| `tool-picks.md` | reworded "Extends the root CLAUDE.md 'Tech stack preferences' table" to a standalone description; reworded "already pinned there" to "already pinned in your own stack preferences" |
| `typescript.md` | dropped "(per the root CLAUDE.md Tech stack preferences)" |
| `frontend-design-engineering.md` | dropped the maintainer's personal skill-install path `~/.claude/skills/{...}` from both the intro paragraph and the Sources line; kept the skill names themselves as an "if installed" pointer |
| `cloudflare.md`, `coding-hygiene.md`, `dapp-frontend.md`, `elixir.md`, `exploratory-testing.md`, `financial-data-handling.md`, `red-team-engagement.md`, `requirements-gathering.md`, `rust.md`, `solana.md`, `solidity.md`, `threat-modeling.md` | no changes needed, already generic |

### Agent citation updates

`agents/security-reviewer.md`, `agents/code-reviewer.md`, `agents/infra-reviewer.md`,
`agents/frontend-reviewer.md`, `agents/test-writer.md`: every `~/.claude/docs/impl-playbook/<file>.md`
citation rewritten to the kit-relative `docs/impl-playbook/<file>.md` (resolved relative to
the kit's own repo root, so it works for any adopter, not just a checkout at the
maintainer's exact home directory).

### Docs inventory

Added one row to `docs/README.md`'s "What's here" table pointing at `impl-playbook/` and
naming the five agents that cite it, the existing analogous inventory table for this repo
(no new section invented). `CLAUDE.md` and `AGENTS.md` were checked; neither carries a
docs-inventory table of this shape, so neither was touched.

### Verification

`grep -r "claude/docs/impl-playbook" .` (excluding `.git`) after the change returns zero
hits in every functional file: the 5 agent definitions, the 25 `docs/impl-playbook/` files,
and every other doc in the repo. The only remaining matches are inside THIS file's own
historical narrative above, quoting the old dead path in prose to describe what changed;
that is expected and not a live reference. Re-run to confirm: search the repo (excluding
`.git`) for the literal string, then check every hit is inside this file's Hypothesis or
"What moved"/"Agent citation updates" sections, never in an agent definition or a playbook
file.
