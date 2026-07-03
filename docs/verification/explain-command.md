# Proof of done: /kit:explain literate-diff explainer (SPEC-124, understanding-gate SG-03)

A new `/kit:explain <ref>` emits the artifact a human READS to understand a change (ADR-0031 §2's
AFTER gate): background -> goal + intuition -> a PROSE-ordered diff -> a diagram. It composes
narrate-log + svg-knowledge-diagram and is grounded in the ACTUAL diff + recorded test results, never
the agent's narrative. The load-bearing proof is the grounded-in-diff negative control (AC4): the
reason this sub-goal exists.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | `/kit:explain <ref>` produces the 4-section literate explainer, sections in reading order | PASS |
| AC2 | the diff is PROSE-ordered, NOT git/alphabetical (background leads, tests trail) | PASS |
| AC3 | the diagram renders (a syntactically valid mermaid block, balanced fence + directive + edge) | PASS |
| AC4a | **grounded-in-diff NC (arg channel)**: a false narrative in the commit BODY + an untracked file is ignored; the explainer describes the DIFF (`subtract`, not `multiply`) | PASS |
| AC4b | **grounded-in-diff NC (subject channel, the strong one)**: even when the commit SUBJECT lies ("add multiply" over a diff that adds `subtract`), the explainer derives its Goal from the diff and surfaces the subject ONLY as UNVERIFIED metadata , never as the title or goal | PASS |
| meta | `tests/test-meta.sh` green incl. the new command frontmatter + architecture inventory + README count parity | PASS (664/664) |

## Implementation

- `lib/explain.sh`: grounding + ordering engine. Input is a git ref ONLY (no narrative channel , the
  architectural guarantee behind AC4). Subcommands `order` / `mermaid` / `tests` / `render`. Ranks
  changed files into reading order (background=docs/specs/ADRs -> new=added -> integration=modified ->
  verification=tests), pulls recorded verdicts from `docs/verification/` (honest absence marker when
  none), emits the 4-section skeleton + a valid mermaid change-map.
- `commands/explain.md`: the command prompt. Runs `explain.sh render` for the grounded floor, then
  composes narrate-log (prose arc) + svg-knowledge-diagram (richer figure) on top. States the hard
  constraint (the diff wins over the commit message and over memory) and that the quiz is SG-04.
- `tests/test-explain.sh`: AC1-AC4 (14 assertions). Fixture A = a multi-rank change (docs + new + two
  modified + test) so reading order and alphabetical order genuinely differ. Fixture B = the NC via the
  commit body + an uncommitted file. Fixture C = the STRONG NC: the diff adds `subtract` while the commit
  SUBJECT (the one channel the engine reads) lies "add multiply operation" , the engine must derive the
  Goal from the diff and label the subject UNVERIFIED (added after a review caught the subject-echo leak).
- Doc companions (CI-required): `docs/architecture.md` inventory row, README command summary count
  (27->28) + table + workflow list, `MANUAL.md` operator entry.

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| AC1 section order | `explain.sh render <refA>` , grep the `## ` headings | Background, Goal and intuition, The change in reading order, Diagram | exact order matched |
| AC2 prose != alpha | `explain.sh order <refA>` vs `git diff --name-only` | orders differ; docs/ leads, tests/ trails | reading `docs/guide.md,beta.js,alpha.js,zebra.js,tests/test-beta.sh` vs alpha `alpha.js,beta.js,docs/guide.md,tests/test-beta.sh,zebra.js` |
| AC3 mermaid valid | `explain.sh mermaid <refA>` | balanced fence + flowchart directive + >=1 `-->` | 2 fences, 1 directive, edges present; embedded in artifact |
| AC4a grounded NC (body/file) | `explain.sh render <refB>` (false narrative in commit body + untracked file) | names `subtract`, never `multiply` | `subtract` present, `multiply` absent |
| AC4b grounded NC (subject) | `explain.sh render <refC>` (subject lies "add multiply"; diff adds `subtract`) | Goal derived from diff; subject only UNVERIFIED | `subtract` present; 0 trusted `multiply` lines; title+Goal clean |
| suite | `bash tests/test-explain.sh` | all green | 14/14 PASS |
| meta | `bash tests/test-meta.sh` | green | 664/664 PASS, exit 0 |

## Run detail (captured 2026-07-03)

```
$ bash tests/test-explain.sh
  PASS AC1 sections present + ordered (got: Background|Goal and intuition|The change, in reading order|Diagram)
  PASS AC2 the two orders differ (prose ordering, not a raw diff)
  PASS AC2 background (docs/) leads the reading order
  PASS AC2 verification (tests/) trails the reading order
  PASS AC3 mermaid fence is balanced (open+close)
  PASS AC3 mermaid has a flowchart/graph directive
  PASS AC3 mermaid has >=1 edge
  PASS AC3 the artifact embeds a mermaid block
  PASS AC4a explainer describes the DIFF (names 'subtract')
  PASS AC4a explainer does NOT parrot the body/untracked narrative ('multiply')
  PASS AC4b (subject channel) explainer still describes the DIFF (names 'subtract')
  PASS AC4b false subject appears ONLY as UNVERIFIED metadata (leaked trusted lines: 0)
  PASS AC4b the derived-Goal line does NOT carry the false subject
  PASS AC4b the H1 title does NOT carry the false subject
  TOTAL: 14   PASS: 14   FAIL: 0

$ bash tests/test-meta.sh  ; echo exit=$?
Passed: 664 / 664 ; All meta tests passed.
exit=0
```

The negative control is load-bearing, and the subject-channel case (AC4b) is the one a review caught:
the engine used to echo the commit subject as the "Goal", so a lying message would teach the wrong model.
Now the Goal is DERIVED FROM THE DIFF and the subject is UNVERIFIED metadata only; AC4b would go red if
that regressed , exactly the failure ADR-0031 exists to prevent. Captured sample artifact (fixture A):
`docs/verification/explain-command/sample-explainer.md`.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-explain.sh   # 10/10, incl. the grounded-in-diff NC
bash tests/test-meta.sh      # 664/664 incl. inventory + README count parity
bash lib/explain.sh render HEAD | head -30   # runs against a real ref
```
