# Verification: thin-understand-commands (SG-02, learning-boundary)

Branch: `refactor/thin-understand-commands`. No behavioral diff: SG-01 (`bfd1334`) already
thinned `commands/explain.md` and `commands/quiz-gate.md` to gate-side entry points that
gather the diff/tests/DEBT material and dispatch through `understand.teach`, naming no
skill. This branch confirms that state is still correct after learning-kit shipped the
teacher (`tieubao/learning-kit#9`), and carries the SG-02 implementation-notes delta.

Docs-only: `bash lib/gate/proof-ledger.sh override 'thin-understand-commands' "..."` run
alone before this commit, per the megagoal's docs-only path.

## Run table (confirms the SG-01 state still holds)

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-explain.sh` | 0 | PASS (14 checks) |
| `bash tests/test-quiz-gate.sh` | 0 | PASS (31 checks) |
| `bash tests/test-boundary-lint.sh` | 0 | PASS |
| `bash lib/gate/boundary-lint.sh` | 0 | `boundary-lint: PASS` |

```
$ grep -c 'understand.teach' commands/explain.md commands/quiz-gate.md
commands/explain.md:2
commands/quiz-gate.md:1
$ grep -c 'deep-understand\|narrate-log\|svg-knowledge-diagram' commands/explain.md commands/quiz-gate.md
commands/explain.md:0
commands/quiz-gate.md:0
```

Both commands keep their original triggers (`$ARGUMENTS`, the ★-tap nudge, the three
responses) and name no consumer skill; the pedagogy they used to carry directly (compose
`narrate-log` for explain, invoke `deep-understand` for the quiz's engage step) now lives
in learning-kit's `understand` skill, reached only through `bash lib/gate/quiz-gate.sh
teacher`.

## Scope note: no new code needed here

SG-02's Outcome for dwarves-kit ("commands/explain.md and commands/quiz-gate.md keep
their names and their triggers and become gate-side entry points") describes work SG-01
already completed as part of building the `understand.teach` seam itself. The "routing
assertions #554 retired" now live in learning-kit's `tests/test_understand_skills.sh`
(this repo's own test suite never reaches into an operator's tree, unchanged since #554).
`lib/explain.sh`'s header/output strings still name `narrate-log`/`svg-knowledge-diagram`
directly (SG-01's implementation-notes flagged this as an explicit Out-of-Scope line in
SPEC-285 DEC-004, since it is architecturally a distinct bin-less internal library, not
`lib/gate/` or `lib/reflect/`); SG-02's own scope edges name only `commands/explain.md`
and `commands/quiz-gate.md` for thinning, so this branch leaves `lib/explain.sh`
unchanged, consistent with that decision.
