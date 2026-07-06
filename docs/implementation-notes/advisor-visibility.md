# Impl notes: advisor-visibility (SPEC-145, gate-review-absorptions sub-goal 06)

Delta from the spec. Only off-spec calls live here.

## 2026-07-04 multi-lens review caught a real bug in the new test's own regression check

- Context: dispatched 4 real subagents (`kit:security-reviewer`, `kit:code-reviewer`
  architecture, `kit:code-reviewer` test-coverage, `kit:advisor` critique P5) against the
  actual diff, dogfooding `/kit:review-team`'s own dispatch shape.
- Decision: the test-coverage lens found (and I reproduced live before fixing) that
  `tests/test-advisor-ledger-emit.sh`'s `fail_open_call()` used sticky global awk flags
  (`found`/`ok` set once, never reset), so `commands/mega.md`'s TWO advisor call sites
  (P5 and P6) were checked as one blob: stripping the fallback from only the second call site
  still passed the "is it fail-open" assertion, because the first call site's match had
  already flipped the global flag. Rewrote the check to test each call site's own line range
  independently (`grep -n` each match, slice its own next-2-lines, no shared state across
  matches).
- Why: the whole point of the test file (per its own header comment) is "a future edit cannot
  silently drop... the fail-open fallback... from either dispatch site" -- a check that only
  catches a fully-bare file but not a partially-regressed one is exactly the gap the header
  comment claims is closed. Fixing it before ship, not after, is why the review round exists.
- Alternatives: leaving the sticky-global check and just noting the limitation -- rejected,
  the fix is small (a loop over `grep -n` matches instead of one awk pass) and the whole
  reason to run a real multi-lens review instead of self-declaring done is to act on what it
  finds.
- Impact: `tests/test-advisor-ledger-emit.sh` grew from 23 to 27 assertions (the rewritten
  fail-open check, plus the advisor critique's two findings and the test-coverage lens's other
  two: AC8 real-write-path test, AC5 rid-convention pin in `agents/advisor.md`). No production
  prose changed as a RESULT of this specific bug (the real `commands/mega.md` file already had
  both fallbacks present; only the TEST that was supposed to guarantee that was broken).

## 2026-07-04 advisor critique caught an inoperable RID reference in the convergence-gate text

- Context: the advisor critique (P5) pass found that `commands/mega.md`'s original
  convergence-gate paragraph said to reuse "the SAME `RID`" a per-sub-goal loop computes at
  Step 5 -- but that Step 5 loop runs once per sub-goal (in a fresh subagent or `claude -p`
  delegate under the two DEFAULT run modes), so the `$RID` shell variable from one iteration
  does not exist by the time the convergence gate runs at the very end of the whole chain.
- Decision: reworded the convergence-gate paragraph to name the final sub-goal's rid as a
  STATIC, already-known value (its `**Branch:**` header from `goals/NN-<slug>.md`, `type/`
  prefix stripped -- the exact transform `bash lib/gate/gate-ledger.sh rid` applies when run on
  that branch), never a live variable re-derivation. This matches a hint already present in
  Step 5's own existing bash comment (`RID=$(bash lib/gate/gate-ledger.sh rid)  # or the sub-goal's
  own branch slug`), so the fix is consistent with, not a departure from, the file's existing
  convention.
- Why: a convention that is inoperable under the DEFAULT run modes (only working by accident
  in INLINE mode, and even then only if the shell session's variable happens to survive to the
  end of a long loop) is worse than no convention at all -- it reads as correct prose but
  fails silently in the common case.
- Alternatives: instructing the conductor to re-`cd`/re-checkout the final sub-goal's branch
  and re-run `gate-ledger.sh rid` at convergence-gate time -- rejected as unnecessary ceremony
  when the value is already known statically from the roadmap/goal file with no git state
  needed.
- Impact: `commands/mega.md`'s convergence-gate paragraph now names `FINAL_RID` as a
  roadmap-derived literal, not a reused shell variable. No change to `lib/gate/gate-ledger.sh` or
  `lib/goal/mega-merge.sh` -- this is a documentation-precision fix, not a new mechanism.

## 2026-07-04 advisor critique also flagged an overclaim about convergence-gate parity

- Context: the same critique pass noted the mega.md paragraph's framing ("mirrors... the kit
  side catching up") could read as claiming full parity with the ops-toolkit
  `plan-for-mega-goal` skill's convergence gate, which is COMPOSED of `/kit:verify` +
  `/kit:review-team` + advisor P5/P6 together (`references/OPERATE.md`). This sub-goal wires
  only the advisor third; `commands/mega.md` still has zero `/kit:verify`/`/kit:review-team`
  dispatch of its own, a pre-existing gap this sub-goal did not create and was never scoped to
  close.
- Decision: reworded to say explicitly "the ADVISOR SLICE," and added an honest Out-of-Scope
  bullet in `docs/specs/SPEC-145-advisor-visibility.md` naming the gap plainly (mirroring the
  precedent in `docs/specs/SPEC-139-...`'s own "Known pre-existing gap, NOT closed by this
  pass" honesty convention).
- Why: AGENTS.md's honesty rule ("never over-claim portable enforcement") applies here too --
  a reader of `mega.md` alone should not come away believing the convergence gate is now
  feature-complete relative to the skill when only one of its three components landed.
- Alternatives: scope-creeping this sub-goal to also wire `/kit:verify`/`/kit:review-team`
  into `mega.md` -- rejected, out of the goal file's named scope edges (advisor P5/P6 only);
  a future sub-goal can own that gap explicitly.
- Impact: `commands/mega.md` prose + `docs/specs/SPEC-145-advisor-visibility.md` Out of Scope
  section only; no behavior change.

## 2026-07-04 never-diverge checklist: mirror direction was skill -> kit, not kit -> skill

- Context: the goal file instructed "if editing commands/mega.md triggers the never-diverge
  checklist (SPEC-142), mirror the change into the dotfiles skill source
  (`plan-for-mega-goal`), stage+commit in ONE shell call on dotfiles, scoped `chezmoi apply`."
  The assumed direction (as in SPEC-142's three prior knobs) was kit-writes-first,
  skill-catches-up.
- Decision: grepped the skill source before writing anything. Found the beat ALREADY present,
  verbatim grammar and all:
  - `~/workspace/tieubao/dotfiles/home/dot_claude/skills/plan-for-mega-goal/references/GUIDE.md`
    line 207-217, step 6a "Advisor pre-launch pass (standing beat)": "dispatch `kit:advisor`
    twice on the finished scaffold, in-harness: P5 critique... and P6 over-suggest... In a
    kit-adopted repo, record the advisor rows (`mode=P5|P6 findings=N actor=`)."
  - `references/invocation-template.md` line 156-157: "advisor P5 (critique) + P6
    (over-suggest), in-harness, ledger rows recorded (mode=P5|P6 findings=N actor=)."
  - `references/OPERATE.md` line 46-51: "The convergence gate is COMPOSED, not improvised. On
    the assembled stack, run: `/kit:verify`... + `/kit:review-team`... + an `advisor` P6
    over-suggest pass, each recording its ledger rows (advisor grammar: `mode=P5|P6 findings=N
    actor=`)."
  All three landed 2026-07-04 (same day), independently, during the harness-observatory
  mega-goal's dogfooding -- ahead of this kit's own `commands/mega.md`, which had zero
  mentions of `advisor` before this PR.
- Why no dotfiles edit was made: the never-diverge contract says the two sides must not
  diverge; it does not say the kit is always the source of truth. Since the skill's prose
  already states the exact grammar this spec independently pins, writing NEW content into
  dotfiles would either (a) duplicate what is already there verbatim, or (b) risk drifting
  from it by re-wording. Matching the skill's existing text in `commands/mega.md` (this PR's
  new convergence-gate paragraph explicitly names both P5/P6 and the same grammar) IS the
  mirror; no separate write is owed.
- Alternatives considered: writing a dotfiles commit anyway "to be safe" -- rejected, it would
  be a no-op diff at best (the content already exists) and a needless second write surface for
  a fact already true.
- Impact: `docs/specs/SPEC-145-advisor-visibility.md`'s "Never-diverge checklist" section
  documents this discovery with the exact skill-side line ranges, in the same table shape
  SPEC-142 established, so a future reader does not need to re-derive it.

## 2026-07-04 advisor's own findings=<N> is distinct from Step 3's merged findings=<K>

- Context: `commands/review-team.md`'s existing Step 3 `review ran "<verdict>
  findings=<K> suppressed=<S> rejected=<M> actor=..."` line already existed before this spec,
  and its `findings=<K>` counts ALL 3 specialists + the advisor's contributions, post-dedup.
- Decision: the new `advisor ran "mode=P5 findings=<N> actor=..."` emit reads `<N>` off the
  advisor's OWN `ADVISORY: <N findings>` line, never the merged Step 3 count.
- Why: folding the advisor's dispatch-happened signal into the existing merged count would
  make it impossible to distinguish "advisor ran with 0 fresh findings" from "advisor never
  dispatched" -- exactly the honest-zero failure mode NC1 exists to prevent. A separate
  `| GATE | advisor |` row is the only shape that lets a reader answer both questions
  independently.
- Alternatives: overloading the existing `review ran` line's `findings=<K>` (rejected, see
  spec DEC-... "Approaches considered" #3); a new `gate-ledger.sh advisor` subcommand
  (rejected, `record()` already accepts an arbitrary phase string with no code change needed).
- Impact: none on existing behavior; `review ran`'s grammar is byte-for-byte unchanged, the
  advisor emit is purely additive.

## 2026-07-04 kit_gates parse verified against the real, unmodified ledger-observatory reader

- Context: the goal file required "grammar MUST parse with the kit_gates reader merged as
  harness-observatory PR #683 -- cross-check for real (emit a fixture line, run the ops-toolkit
  kit_gates query against `~/.local/state/dwarves-kit/logs/runs/`, paste the parse)."
- Decision: rather than pointing the real `DWARVES_KIT_LOG_DIR` (which holds live operator
  ledger data) at the fixture, created two committed fixture logs under
  `tests/fixtures/advisor-ledger-emit/runs/` and pointed a scratch `DWARVES_KIT_LOG_DIR` env
  var at that directory for the one-off `uv run ledger rebuild` / `gate-yield` / `query` calls
  (see `docs/verification/advisor-visibility.md` Run 1-2). This proves the parse without
  mutating or depending on the operator's real, larger ledger corpus.
- Why: the real corpus has 96 rid logs and zero `advisor` rows (the exact gap this spec
  closes); pointing at it directly would only reconfirm the gap, not prove the NEW grammar
  parses. A minimal, committed, two-rid fixture (one with advisor rows, one without) isolates
  the claim and is reproducible by anyone without needing 96 files of unrelated history.
- Alternatives: writing directly into the real log dir with a throwaway rid, then deleting it
  -- rejected, mutates a live operator artifact for a one-off proof, and "delete it after" is
  exactly the kind of manual step that erodes trust in a proof if forgotten.
- Impact: `tests/fixtures/advisor-ledger-emit/runs/*.log` are new, committed, inert fixture
  files; they are read-only inputs to `tests/test-advisor-ledger-emit.sh`'s offline AC7 checks
  and to the (uncommitted, terminal-captured) ledger-observatory cross-check. No production
  ledger path changes.
