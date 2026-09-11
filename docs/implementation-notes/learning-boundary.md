# Implementation notes: learning-boundary mega-goal

Delta from `_meta/megagoals/learning-boundary/ROADMAP.md` and its goal files. Decisions the roadmap left open, deviations, and things the next session should know.

## 2026-09-10 10:20 The axis replaced the first cut before any code

Context: the first roadmap draft (merged as #555) said "every learning-shaped surface moves to learning-kit" and listed `explain`, `quiz-gate`, `absorb` as moves. The operator asked how that squares with the dev kit's own auto-improvement half.
Decision: split by who changes (system: Reflect, engine; human about shipped work: Understand, gate in engine + teacher in learning-kit via `understand.teach`; human expanding: Study, learning-kit). `absorb` stays whole; `explain` and `quiz-gate` stay as gate-side entry points and only their pedagogy bodies move.
Why: ADR-0031 was right about the gate's placement; it never separated the gate from the teacher. Moving the commands would strand engine-only adopters with no gate at all.
Alternatives: move everything learning-shaped (rejected above); keep everything in the engine (violates SPEC-249, keeps the dotfiles reach-across).
Impact: sub-goal 02 renamed `understand-teacher`; seam key renamed `wrap.learn` to `understand.teach` across 01, 03, 05; ADR-0036 carries the axis table.
Open questions: none; the ADR is the operator's click.

## 2026-09-10 10:35 Two "dotfiles" skills live in a different repo

Context: a read-only verifier refuted the roadmap's claim that nine learning skills live as directories under `dotfiles/home/dot_claude/skills/`.
Decision: `knowledge-capture` and `learn-skill` are chezmoi `symlink_*` entries pointing at `~/workspace/claude-skills/skills/`; the roadmap and goals 03 and 04 now name claude-skills as the source repo for those two, and the dotfiles half of each move is removing the symlink entry, not a skill directory.
Why: a `git mv` from the wrong repo would move a symlink file and leave the body behind.
Impact: sub-goals 03 and 04 each touch three repos (source, destination, dotfiles) for those two skills instead of two.

## 2026-09-10 10:35 The main checkout carries the superseded roadmap until this PR merges

Context: the same verifier noted the main dwarves-kit checkout still holds the #555 draft (seam `wrap.learn`, `absorb` moving).
Decision: no action; it is the unmerged state of this branch. Anyone dispatching a sub-goal before this PR merges reads the wrong cut.
Impact: do not run `orchestrate.sh` on this mega-goal until the ADR PR is merged with Status Accepted.

## 2026-09-10 10:50 The Seams table lives in the registry, not in SPEC-249

Context: a read-only verifier on ADR-0036 refuted one line: the ADR, the roadmap, and goal 05 said a new seam row lands in "SPEC-249 `## Seams`". SPEC-249 has no such heading; it documents the table that `lib/config/module-registry.md` holds, outside the registry parser window.
Decision: all three now name `lib/config/module-registry.md` as the table and SPEC-249 as its documentation.
Why: sub-goal 01 would otherwise have edited a spec file and found nothing to add to.
Impact: goal 05 In-scope line reads "the seams-table row". No other change.

The same verifier confirmed: the axis table is byte-identical between ADR and roadmap; every characterization of ADR-0031 and ADR-0034 traces to a line in those files; `skipped: no teacher`, the `reflect` verbs, and "no engine file names a consumer skill" are prospective (sub-goal 01 builds them; `commands/explain.md` names `narrate-log` and `svg-knowledge-diagram` today).

## 2026-09-10 11:40 SG-01 built: the boundary lint's scan scope is narrower than the goal file's literal words

Context: the goal file says the lint "greps `lib/`, `commands/`, `tests/`, `kit.toml`". A literal full-`lib/` grep for `ops-toolkit/`/`dotfiles` or a fixed skill-name denylist hits 30+ pre-existing, legitimate, unrelated mentions: `lib/stats/`, `lib/prose-rag/`, `lib/sync/`, `lib/webcheck/`, `lib/plugin-check/` all document their own "graduated from ops-toolkit" history in READMEs and specs; `commands/pitch.md` composes `narrate-log` for an unrelated pitch-deck feature; `commands/ui-design.md` names the external `frontend-design` skill directly, an accepted, pre-existing pattern outside this axis; `tests/test-wrap.sh` uses the literal string `learning-ledger` as generic fixture text for `report-lint.sh`'s "names a skill" acceptance check.
Decision: the lint's path check runs over `lib/gate/`, `lib/reflect/`, `commands/`, `tests/`, `kit.toml` with two narrow patterns (`dotfiles/home`, `ops-toolkit/(tools|_meta)/`) that match the actual historical violation shape, not a bare word. The skill-name check runs over an explicit small file list (the seam-adjacent surfaces this sub-goal actually owns), not directory recursion.
Why: a lint that immediately fails the suite on introduction, over content this sub-goal has no mandate to touch, violates the repo's own "the engine's suite stays green with zero skips at every sub-goal boundary" bar. Full rationale + the measured hit counts: `docs/specs/SPEC-285-engine-learn-seam.md` DEC-003/DEC-004.
Alternatives: the literal full-directory scan (rejected, breaks green on unrelated content); fixing all 30+ unrelated mentions in this sub-goal (rejected, unbounded scope creep for a `normal`-lane sub-goal).
Impact: `lib/gate/boundary-lint.sh` is a disclosed narrower implementation than the goal file's literal words; flagged as an Open question in SPEC-285 for the operator to confirm or revise. A future sub-goal widening the scope needs its own cleanup pass over the unrelated mentions first.

## 2026-09-10 12:05 The subsystem rename touched three test files' names, not just their content

Context: the goal's Quality bar says "Every existing test passes unchanged except for the path of the thing it calls," read at first as "never rename a test file." Renaming `lib/learn/` to `lib/reflect/` alone left `tests/test-kit-contract.sh`'s C4 rule ("every module has a test") looking for `test-reflect-*` and finding only `test-learn-propose.sh`/`test-learn-drain.sh`/`test-learn-propose-precision.sh`, a genuine new gap `test-kit-contract.sh` correctly flagged.
Decision: renamed those three test files to `test-reflect-propose.sh`/`test-reflect-drain.sh`/`test-reflect-propose-precision.sh` (git mv, content substituted `learn`->`reflect` throughout) rather than adding a known-gap entry for a rename this sub-goal chose to make. `test-weekend-batch.sh` and `test-staging-stage.sh` keep their names (already generic); `test-bin-forwarders.sh` and `test-understanding-wiring.sh` keep their names and had their internal path/string references repointed.
Why: `tests/kit-contract-known-gaps.txt`'s own header says "no NEW debt can land"; adding a gap entry for self-inflicted debt from a rename this sub-goal is doing contradicts that.
Impact: `bin/reflect propose --help` now prints `usage: reflect propose` (the internal argparse `prog=` and every `Source: learn propose ...` citation string in `propose.py`/`drain.py` also renamed, since leaving them would reintroduce the retired word `learn` as literal output of the renamed subsystem). `LEARN_PROPOSE_RID` env var renamed to `REFLECT_PROPOSE_RID`.

## 2026-09-10 12:20 quiz-gate.sh's engine, not just its command file, hardcoded the consumer name

Context: the task instructions named `commands/quiz-gate.md` (the markdown prose) as the surface to fix; `lib/gate/quiz-gate.sh` (the bash engine) prints "ROUTE: deep-understand" and "engine: deep-understand skill" as literal stdout, which is a harder violation of "no engine file names a consumer skill" than the command prose.
Decision: `lib/gate/quiz-gate.sh` now sources `kit-config.sh` and resolves `understand.teach` at `cmd_route`/`cmd_tap`/`cmd_respond` time, emitting the resolved name (or "skipped: no teacher") instead of the literal string. `tests/test-quiz-gate.sh` AC3 rewritten with a fixture `KIT_CONFIG_OPERATOR` for both the filled and empty cases.
Why: the boundary lint's scope includes `lib/gate/` (in scope per the goal's literal words), so leaving the engine hardcoded would make the lint's own scope inconsistent with what it actually enforces.
Impact: `lib/gate/README.md`'s "gate quiz" table cell updated to describe the seam generically. `lib/explain.sh` (the sibling mechanical engine) was NOT touched: it lives at `lib/` root, not `lib/gate/` or `lib/reflect/`, a distinct architectural category per ADR-0034's 2026-08-27 amendment (deliberately bin-less, command-invoked internal libraries), so its header comment naming `narrate-log`/`svg-knowledge-diagram` is a stale-but-harmless architecture note, not a lint violation. Recorded as an Out of Scope line in SPEC-285.

## 2026-09-10 12:40 SPEC number collision: origin/master had moved since the worktree branched

Context: `lib/spec/spec-next.sh next` returned 135 early in the build; `docs/specs/SPEC-135-docs-wiring-no-orphan-check.md` already existed on `origin/master` (merged after this worktree's base commit), so `tests/test-meta.sh`'s SPEC-number-collision guard caught the duplicate.
Decision: `git fetch origin master`, re-ran `spec-next.sh next` (returned 285), renamed the spec file and every internal cross-reference to SPEC-285.
Why: `spec-next.sh` scans the local checkout's specs, branches, and commit subjects; a stale local view of `origin/master` is exactly the trap `_meta/claude-md-history.md`-adjacent memory already names for backlog IDs, and the same class of bug applies to SPEC numbers.
Impact: none beyond the rename; caught before commit by `bash tests/test-meta.sh`, not by hand-inspection.

## 2026-09-11 18:40 Five lessons from the SG-01 run

Context: SG-01 merged as `bfd1334`, but it cost two agent deaths, four merges of master, one
bad verification, and two CI failures. The mechanics cost more than the code did.
Decision: record the five as standing practice for SG-02 onward.

1. **Freeze the branch head before dispatching a verifier.** A recheck ran while the sub-goal
   agent still held the worktree open. It reported four failing suites that were not the
   recorded three, one of them transient and one caused by an uncommitted fence. Push, stop
   editing, then dispatch.
2. **A sub-goal agent can die holding finished work.** This one was killed twice, once by a
   session limit and once by session teardown. Both times every change sat uncommitted and
   unpushed in its worktree. Check the worktree before believing the task landed, and resume
   the agent by its id rather than respawning it on the same branch.
3. **Give "pre-existing failure" one check.** An agent called a failing suite pre-existing.
   The suite did fail on master, but the cause was a path this mega-goal had itself introduced
   in `POINTER_PROMPT.md` one sub-goal earlier.
4. **A rename outruns a cleanup that touched only the old path.** `git mv bin/learn
   bin/reflect` carried the old header forward. Master's id-strip cleaned `bin/learn` alone,
   so five ids survived in the new file and the zone-4 gate rejected the branch. After any
   rename, run the lints that cover the destination, not only the source.
5. **Master moves under a long-lived branch.** This branch merged master four times. Every
   conflict had one shape: the branch moved `lib/learn` to `lib/reflect` while master edited
   the old path. Take master's text, then re-apply the rename. Expect the same in SG-02.

Why: each of the five cost a round trip that a written rule prevents.
Impact: SG-02 and SG-04 dispatch under these rules. `HANDOFF.md` is machine-local, because
`.gitignore` carries `HANDOFF*.md`, so this entry is the durable copy of the same material.
Open questions: none new.

## 2026-09-12 SG-04 built: no hand-kept index inside the context tree, and `config get` under-reports the seam

Context: `memorize`'s repo-scoped destination now resolves `knowledge.root` before falling
back to `<repo>/.claude/memory/`. The goal file's own precedent (the repo-local shape) pairs
every fact file with a hand-kept `MEMORY.md` index; a first pass carried that shape into the
filled-seam destination too, `<root>/projects/<repo-basename>/MEMORY.md`.
Decision: dropped the index for the filled-seam case only. An index file with no single
`last_verified` date fails context-kit's own `ctx-check` staleness finding (reproduced: a
fixture tree with such a file reports `NO-VERIFIED`, 1 finding; dropping the index and
writing only the fact page per SPEC-001 §2's contract reports `0 findings`). The unset-seam
default (`<repo>/.claude/memory/`) keeps its `MEMORY.md`, unchanged, since that shape predates
this seam and ctx-check never sees it.
Why: `ctx-graph`/backlinks already enumerate a tree directory's pages; a hand-kept index there
would be a second, driftable copy of what the tree derives for free, and it would fail the
receiving kit's own audit on day one.
Also recorded: the shared resolver (`context-kit skills/knowledge-root.sh`) calls dwarves-kit's
`bin/config seams`, not `bin/config get knowledge.root`, for its second resolution rung.
Reproduced: `config get`'s `_resolve` function never consults the operator `kit.toml` for any
key (only `cmd_seams`'s `_seam_resolve` calls `kit_config_get_root`), so `config get
knowledge.root` under-reports a root-only seam the operator has actually filled; `config
seams` is the one verb proven to read the operator layer. This is a `config get`/`config
explain` gap, not a `knowledge.root`-specific one, and out of SG-04's mandate to fix (the
shared contract permits editing only this file and the ROADMAP line in dwarves-kit).
Alternatives: keep the index everywhere for symmetry with the repo-local shape (rejected, it
fails the receiving kit's own gate); patch `config.sh`'s `_resolve` to add the operator layer
generally (rejected, a behavioral dwarves-kit change outside this sub-goal's touched-files
contract, and every OTHER key's `config get` behavior would change on an unrelated branch).
Impact: `memorize`'s Root resolution section documents the no-index rule; `docs/verification/feat-knowledge-writers.md`
(context-kit PR) carries the reproduction (both ctx-check runs, before and after dropping the
index) and the `config get` vs `config seams` finding, run table included.
Open questions: whether `config get`/`config explain` should gain the operator layer for every
root-only key is a real question for whoever next touches `lib/config/config.sh`; not decided
here.

## 2026-09-12 The til privacy gate was asserted, never verified

Context: the goal file's Outcome says "the til privacy gate moves with `knowledge-capture`
unchanged and stays the only path to a public note," and its Quality bar calls the rule list
"byte-identical." A fresh-context verifier grepped case-insensitively for "privacy" in both the
source and the moved copy and got zero hits either place, so neither the build nor the first
verification pass had actually checked the claim.
Decision: read the full source body for any strip enforcement under any wording (credentials,
tokens, account ids, client/NDA details, personal/financial data, embargoed material) before
concluding anything from the single-word grep. None existed: "Strip ALL conversational
artifacts" (Step 2) removes chat fluff, not sensitive data, and "Important rules" had a
content-quality gate and a confirm-before-push rule, neither a data-safety check. Took path (b):
a real gap, not a wording problem. Added a new `### Step 5.9: Privacy gate` to the moved
`knowledge-capture/SKILL.md`, sourced from the estate's own til privacy rule (the operator's
global CLAUDE.md "Privacy gate for `tieubao/til`" line: credentials/secrets, cloud account ids
tied to billing, client/NDA-bound details, personal financial data, family names/addresses/
phones, embargoed feature details), plus a suite-visible rule pointing at it so a batch push
cannot skip it per note.
Why: this skill is the only path a note takes to a public repo (per the goal's own framing);
asserting a gate that does not exist is worse than having none, because it reads as already
handled.
Alternatives: reword the goal's claim to describe the content-quality gate as if it were the
privacy gate (rejected -- that gate screens for thinness, not sensitivity, a different axis
entirely); leave the gap and only fix the goal file's wording (rejected -- the goal's own audit
path (a)/(b) split says a missing gate is a gap, not a doc problem, when the skill is the sole
public-write path).
Impact: `knowledge-capture/SKILL.md` gains Step 5.9 and Important-rules item 7, a real
behavioral addition at the destination -- NOT a byte-identical carry-over from source, disclosed
as such in `docs/verification/feat-knowledge-writers.md` (context-kit PR) rather than claimed
unchanged. `tests/test-privacy-gate.sh` (context-kit, added same-day on a precise follow-up spec)
closes the open question this entry originally left: three read-only assertions (the Step 5.9
heading exists; the gate body names each of the six privacy categories independently, on a short
distinctive substring per category; a scratch copy with the gate section mechanically deleted
fails the identical check), wired into `tests/all.sh`. Verdict pasted in
`docs/verification/feat-knowledge-writers.md`: `test-privacy-gate: all 8 passed`, including the
negative control.

## 2026-09-12 Scattered ids in this sub-goal's own new prose, the second time in this mega-goal

Context: the same audit found `SPEC-249`/`ADR-0036`/`SPEC-001` scattered inline across the two
moved skills' new root-resolution prose and the shared `knowledge-root.sh` resolver -- the exact
mistake this mega-goal's SG-01 already paid for once (learning-kit had no lint either), and
neither context-kit nor learning-kit had a lint that would ever catch it.
Decision: reworded every inline reference to state the behavior plainly (name the seam,
`knowledge.root`; describe the fence as "operator or kit-root file only, never a project file,"
never the spec number that says so), moved every id to one `<!-- provenance: ... -->` footer at
the bottom of each of the three files, and added `tests/test-no-scattered-ids.sh` to context-kit
(modelled on dwarves-kit's own zone 5, scoped to `skills/*/SKILL.md`, wired into `tests/all.sh`).
The audit also turned up one pre-existing hit in `skills/setup/SKILL.md` (predates this
sub-goal); fixed in the same pass so the new lint starts green.
Why: a written rule with no lint behind it is advice, not a rule, and this mega-goal had already
demonstrated that once is not enough to prevent a recurrence.
Impact: `docs/verification/feat-knowledge-writers.md` carries the lint's negative control
(planted-id fixture caught; the pre-existing hit caught before the fix, clean after), pasted
verbatim.
Open questions: none new; dwarves-kit's own `tests/test-no-scattered-ids.sh` (zones 1-5) is the
pattern to widen if a THIRD kit in this estate ever needs the same lint.

## Open questions

DEC-003's scope narrowing (this file's first entry above) is the operator's call to confirm; SPEC-285 carries the same question.
