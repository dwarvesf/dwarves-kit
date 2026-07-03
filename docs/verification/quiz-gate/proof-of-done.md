# Proof of done -- quiz-gate (SPEC-125, SG-04)

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | a high×high change generates exactly 5 quiz questions FROM the actual diff + test results (not narrative) | PASS |
| AC2 | the three responses (engage/defer/wave) each land in the debt ledger | PASS |
| AC3 | engage routes through deep-understand's mastery-gate engine (dispatch, not a reimplementation) | PASS |
| AC4 | GROUNDED NC: a narrative that contradicts the diff -> the quiz is built from the DIFF (`subtract`, never `multiply`) | PASS |
| AC5 | WIRING NC: the tap FIRES on `tap`, is ABSENT on `wave` AND on `not-significant` (and on a non-gate PR) | PASS |
| AC6 | NEVER must-pass: a waved change still merges; no verb blocks, no hook gates the merge | PASS |
| CD | coverage delta: 0 -> 6 quiz-gate acceptance checks (29 assertions incl. edge cases) | PASS |
| review-fix | multi-lens review (SPEC-069): MAJOR-2 real code gap fixed (`_primary_file` docs/tests-only branch) + behavioral GATE-guard + 3 edge cases; 24 -> 29 assertions | PASS |
| regression | sibling suites (`test-significance-classify.sh`, `test-explain.sh`) + full corpus (`test-meta.sh`) unaffected | PASS |

## Confirmation run

```
$ bash tests/test-quiz-gate.sh
=== AC1: exactly 5 diff-grounded quiz questions ===
  PASS AC1 exactly 5 questions (Q1..Q5), got 5
  PASS AC1 each of Q1..Q5 appears exactly once (no dup/drop)
  PASS AC1 questions reference a real changed file (widget.js)
  PASS AC1 questions quote the actual added code (names 'widget')
  PASS AC1 questions carry the recorded test verdict (PASS from the proof)
=== AC2: three responses each land in the debt ledger ===
  PASS AC2 three | DEBT | response= lines written, got 3
  PASS AC2 engage logged
  PASS AC2 defer logged
  PASS AC2 wave logged
  PASS AC2 a DEBT-only ledger fails gate check (response lines never satisfy a required gate)
=== AC3: engage routes through deep-understand (dispatch, not reimplementation) ===
  PASS AC3 engage output names the deep-understand engine
  PASS AC3 engage output names the AskUserQuestion mastery gate
  PASS AC3 wave does NOT route to deep-understand
  PASS AC3 quiz-gate.sh reimplements no scorer (no answer-key/grade/score logic)
  PASS AC3 commands/quiz-gate.md names deep-understand (live dispatch path)
=== AC4: GROUNDED negative control (narrative differs from the diff) ===
  PASS AC4 quiz describes the DIFF (names 'subtract')
  PASS AC4 quiz does NOT parrot the false narrative ('multiply')
  PASS AC4 no recorded proof -> Q4 says '[no recorded test result]' (does not invent a verdict)
=== Edges: docs/tests-only change + a range ref ===
  PASS Edge docs/tests-only: still exactly 5 questions
  PASS Edge docs/tests-only: Q3 fires the 'touches only docs/tests' branch (no mis-labeled primary)
  PASS Edge range ref (A..B): 5 questions, still names the real changed file (widget.js)
=== AC5: WIRING negative control (fires on tap, absent on wave / not-significant / non-gate) ===
  PASS AC5 classifier sanity: tap/tap wave/wave ns/not-significant
  PASS AC5 tap FIRES on a tap-verdict gate PR (nudge printed)
  PASS AC5 tap ABSENT on a wave-verdict change (anti-fatigue)
  PASS AC5 tap ABSENT on a not-significant change
  PASS AC5 tap ABSENT on a non-gate PR even when the verdict is tap
=== AC6: NEVER must-pass (a waved change still merges; nothing blocks) ===
  PASS AC6 respond wave exits 0 (advisory, not a block)
  PASS AC6 tap exits 0 (never blocks the merge)
  PASS AC6 no hook blocks merge on the quiz (0 hook refs to quiz-gate, got 0)

  ---------------------------------------------
  TOTAL: 29   PASS: 29   FAIL: 0
Exit: 0
```

```
$ bash tests/test-meta.sh | tail -3
=== Results ===
Passed: 667 / 667
All meta tests passed.
Exit: 0
```

## Run detail

- Repo: `dwarves-kit`, worktree `.claude/worktrees/ug-04`, branch `feat/ug-04-quiz-gate`.
- Environment: macOS, bash 5.x (per shebang resolution), no network, no LLM calls inside the quiz-gate
  lib itself (pure bash: `git diff`, `grep`, and subprocess calls to the sibling libs `explain.sh`,
  `significance-classify.sh`, `gate-ledger.sh`). The quiz is DISPATCHED to the `deep-understand` skill;
  the kit scores nothing.
- The hard constraint is structural, not a prose promise: `quiz-gate.sh questions`/`route` accept a git
  ref ONLY (no narrative/intent argument), so a false story physically cannot leak into the quiz. AC4
  proves it (a fixture whose commit body + an untracked file claim `multiply` over a diff that adds
  `subtract`; the quiz names `subtract`, never `multiply`).
- The nudge is keyed on the SPEC-123 classifier's verdict (single source of the WHEN) plus a PR-kind
  guard; AC5 proves it fires only on `tap` + a gate PR, absent on `wave`/`not-significant`/non-gate.
- `tests/test-quiz-gate.sh` isolates every ledger write into a `mktemp -d` via `DWARVES_KIT_LOG_DIR`;
  no writes land in the real logs during the run. Fixture git repos are `mktemp -d`, cleaned on EXIT.
- Multi-lens review (SPEC-069, `lib/` touch): security CLEAN, architecture 10/10, test-coverage 7/10
  (2 MAJOR + 3 MINOR), all fixed. MAJOR-2 was a REAL code gap (`_primary_file` mis-labeled a doc as the
  primary on a docs/tests-only change); fixed + covered. Suite grew 24 -> 29 assertions. See
  `docs/implementation-notes/quiz-gate.md` for the fix log. Fresh re-run of both suites confirms no
  regression.

## Reproduce

```bash
cd dwarves-kit   # or the ug-04 worktree
bash tests/test-quiz-gate.sh
bash tests/test-meta.sh
```
