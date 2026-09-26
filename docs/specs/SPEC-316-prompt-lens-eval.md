# SPEC-316: a repeatable treatment-vs-control eval for prompt-only lenses

**Status:** VALIDATED
Lane: full
Type: spec-feature
**Proof:** `docs/verification/prompt-lens-eval.md`; `tests/test-lens-eval.sh`.

## Problem

Many kit commands are reviewer text with no code behind them: `commands/spec-validate.md`, `commands/devs-team.md`, `commands/test-plan-review-team.md`, `commands/visual-team.md`, and the `agents/*.md` reviewers. Their tests grep structure. `tests/test-design-record.sh` says so in its header: it "cannot drive the live LLM judgment".

In the SPEC-314 session the lead proved a new lens by hand. Fresh subagents ran the branch's command text and master's command text against two fixture specs. The lead read each report and wrote down which findings appeared (`docs/verification/sustainability-lens.md`). Nothing in the repo can rerun that eval. The next lens change starts from zero, and the SPEC-314 result cannot be checked again after a model change.

## Contract

`bash lib/bench/lens-eval.sh <command-file> <base-ref> <cases.json> [--samples N] [--model M] [--live]`

- Treatment is the working-tree text of `<command-file>`. Control is the same path at `<base-ref>`, read with `git show <base-sha>:./<file>` from the file's directory. Identical control and treatment text is a usage error.
- `<cases.json>` lists cases. Each case carries a `name`, a fixture file (a path relative to the JSON file's directory, with no `..` segment and not absolute) and its signals. Each signal carries `name`, `pattern` (an extended regex, matched case-insensitively), an optional `reviewer` regex, and at least one of `treatment` and `control`. `treatment` is `hit` or `miss`. `control` is `hit`, `miss`, or `fewer`; `fewer` needs `treatment: hit`. Case and signal names use `[A-Za-z0-9._-]` and are unique within their scope.
- A sample hits a signal when one finding block of its output matches `pattern` and, if `reviewer` is set, that same block (or the `Reviewer N` heading it sits under) also matches `reviewer`. A block is a top-level list item, a heading, or a paragraph start, joined with its continuation lines. Models tag a finding on its first line and write the detail on indented lines below, so a single line would split the tag from the detail. A markdown table row is always its own block. Everything under a `Passed` heading is dropped up to the next heading, so a pass bullet never scores. A `Reviewer N` heading credits the blocks under it until a heading at the same or a higher level.
- An arm hits a signal when a majority of its N samples hit. N is 1 or odd, so no tie exists. A `hit` or `miss` expectation passes when the arm got that answer. A `control: fewer` expectation passes when control has fewer hits than treatment; its count is reported as info. A signal passes when every arm it names passed.
- An arm runs only when some signal of the case names it, so a case with no control expectation costs no control calls.
- Without `--live` the script makes no model call. It prints the planned call count, the sum over cases of `<arms named> x N`, and exits 3.
- With `--live` it first checks `command -v claude`, then runs every call one after another: `claude -p --safe-mode --no-session-persistence --tools "" --max-budget-usd 1 --model M --output-format json`, the prompt on stdin, from a fresh temp directory. The first failed sample stops the run. `--safe-mode` drops CLAUDE.md, skills, hooks, and plugins, so each call reads only the prompt. `--tools ""` means the model can run nothing and write nothing.
- The prompt is a fixed header, then the command text, then the fixture. The header tells the model to run the command once without pausing, run no tools, skip gate-ledger and Status steps, print only the final report, and tag every finding `Reviewer N`.
- Every sample's text is saved as `<dir>/<case>.<arm>.<i>.md` under one `mktemp -d` directory. The script prints that directory.
- Output: one markdown table, one row per case and signal, with columns `case`, `signal`, `treatment`, `control`, `result`. An arm cell reads `<hits>/<N> want <hit|miss>`, or `-` when the signal names no expectation for that arm. After the table: the samples directory, `base: <ref> <sha>`, `text sha256: treatment <12 hex> control <12 hex>`, `cost: $<sum of total_cost_usd> over <calls made> calls, <seconds>s`, and one verdict line.
- Default N is 1. Default model is `sonnet`.

| Exit | When | Verdict line |
|---|---|---|
| 0 | every signal passed | `verdict: PASS (<k>/<k> signals)` |
| 1 | one or more signals failed | `verdict: FAIL (<f>/<k> signals failed: <names>)` |
| 2 | a sample failed: claude missing, a non-zero exit, an envelope with `is_error: true`, or an empty `.result`; the run stops there | `verdict: ERROR (failed sample <case>.<arm>.<i>, see <dir>)` or `verdict: ERROR (claude not on PATH)` |
| 3 | no `--live` flag | `verdict: NOT RUN (dry run, 0 model calls)` |
| 64 | usage error: missing or extra argument, a base ref that starts with `-`, a command file that does not exist, a command file outside a git repo, a ref that does not resolve, a base ref without the file, identical control and treatment text, a fixture that does not exist or escapes the case file's directory, a JSON file that fails the schema check or repeats a case or signal name, a `pattern` or `reviewer` that is not a valid extended regex, N not a positive odd integer (or 1), an unknown flag | a distinct message, then the usage line |

Only a live run where every signal held exits 0. A failed sample is never scored as a miss, because a `miss` expectation would then pass on an auth failure. An `is_error` envelope counts as failed even when `.result` carries text, since that text is an error message such as a low credit balance.

The `reviewer` regex should accept the ways a model names a reviewer: `Reviewer 7|R7|Sustainability` rather than `Reviewer 7` alone.

`tests/fixtures/sustainability-lens/lens-eval.json` is the first real case file. Its signals come from the SPEC-314 eval table. The catch fixture expects liveness, retirement, and credential rotation from Reviewer 7 in treatment. For each of the three it also expects control to raise the gap fewer times than treatment (`control: fewer`): the old text may notice a planted gap now and then, and only the gap between arms says the lens added it. It expects run cost from Reviewer 7 in treatment and names no control expectation, because the recorded control 2 run raised cost under Reviewer 5. The quiet fixture expects no numbered finding tagged Reviewer 7 (a hard `treatment: miss`), since the lens contract gives a short-lived spec a one-line pass and no findings. The one-line pass itself sits under `Passed`, which the scorer drops, so the case file no longer checks for it.

## Picture

```
 operator: lens-eval.sh commands/spec-validate.md <base> cases.json --live
      |
      v
 lens-eval.sh ---- git show <base>:./spec-validate.md ----> control text
      |      ---- working tree -------------------------> treatment text
      |      ---- jq schema check -----------------------> cases.json + fixtures
      v
 for case, for arm the case names (treatment, control), for i in 1..N:
      header + command text + fixture  --stdin-->  claude -p --safe-mode --tools ""
                                                        |
      <dir>/<case>.<arm>.<i>.md  <--- jq .result -------+   cost += .total_cost_usd
      |
      v
 per signal, per arm: count samples whose line matches pattern (and reviewer)
      |
      v
 majority vs expectation --> table row PASS/FAIL --> verdict + exit code
```

## Design

Design-bearing: a new script that spends money on an external model call and turns its text into a verdict.

Control flow of one run:

```
 parse args --bad--> exit 64
     |
     v
 validate command, base, JSON, fixtures --bad--> exit 64
     |
     v
 --live? --no--> print plan, exit 3
     |
    yes
     v
 run calls in order ----> any failed sample? --yes--> no table, exit 2
                                 |
                                 no
                                 v
                          score signals --all pass--> exit 0
                                 |
                                 +--any fail--> exit 1
```

Chosen approach: one bash script in the bench plane (`lib/bench/`), jq for the case file and the claude envelope, grep for scoring. Scoring is a keyword test on one finding block. It drops a `Passed` section, but it cannot tell a finding from a pass line written elsewhere that names the same word; the case author picks the patterns and the `reviewer` scope. The script follows `lib/skill-curator/lib/reviewer-run.sh` for the headless call: stdin prompt, JSON envelope, `.result` and `.total_cost_usd`. It differs in two flags: `--safe-mode` instead of `--bare`, because `--bare` reads only `ANTHROPIC_API_KEY` and the operator authenticates with OAuth, and `--tools ""` in place of `--allowedTools ""`.

Approaches considered:

| Approach | Why not |
|---|---|
| A new executor and a variant dimension in `lib/bench/bench.py` | bench scores generated code by running a hidden `check.py` against `solution.py`, over frozen suites whose content hash pins a baseline. A lens eval builds its two prompts from git at run time and compares two arms per signal. Fitting it in means a new executor, a prompt-variant dimension, a text check type, and a two-arm summary: more Python than this whole script. The script sits in `lib/bench/` so both evals share one README. |
| A kit command that dispatches fresh subagents, as the SPEC-314 lead did | A subagent run cannot be stubbed offline, and a command cannot be tested in `run-all`. The ask is a repeatable run. |
| Ask a judge model whether each finding names the signal | That doubles the model calls and adds a second nondeterministic step to a check that exists to measure the first. A line-level grep is readable in the case file and free. |
| Parallel calls with `&` and `wait` | Faster at larger N, but the stub's call order and the rate limit both get harder. Sequential at N=1 is 3 calls for the SPEC-314 case. Revisit when a real run needs N above 3. |

### Interfaces (I/O contract)

- Input: the three positional arguments and the flags above. The case file's shape, checked by one `jq -e` expression:
  `{"cases":[{"name":"<id>","fixture":"<path>","signals":[{"name":"<id>","pattern":"<ERE>","reviewer":"<ERE, optional>","treatment":"hit|miss","control":"hit|miss"}]}]}`, with at least one case, at least one signal per case, and at least one of `treatment` or `control` per signal.
- Output: stdout carries the table and the summary lines; stderr carries progress, one line per call. The samples directory holds one text file per call.
- Invariant: the script writes only inside its own `mktemp -d` directory. It never writes to the repo.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| claude missing, logged out, or a flag renamed | a non-zero exit or an empty `.result` | exit 2, `ERROR`, the samples directory named; never scored |
| API error returned as text (credit, rate limit) | `is_error: true` in the envelope | exit 2, same as above |
| A base ref shaped like a git option (`--output=...`) | the ref starts with `-` | exit 64 before `git show` runs |
| One call hangs | none inside the script | the operator interrupts; the saved samples stay on disk. Not covered below. |
| Model output varies between runs | none; it is the thing measured | N samples and a strict majority; the default N=1 matches the SPEC-314 hand eval and the verdict says only "held at this N" |
| A pattern too broad matches a pass line | a signal passes in an arm it should fail | the scorer drops a `Passed` section; outside it, the case author scopes with `reviewer` and narrows `pattern`; the saved samples show which line matched |
| One call runs up cost | none before the call | `--max-budget-usd 1` per call; the run stops at the first failed sample |
| A base ref without the command file | `git show` fails | exit 64 before any call |
| An operator forgets the live flag in a script | exit 3, not 0 | only a live pass exits 0 |
| A large N or many cases runs up cost | the dry run prints the call count | `--live` is explicit; N and the case count are both the operator's own numbers |

## Sustainability (Reviewer 7 answers)

- Run cost: at most `<cases> x 2 x N` calls, each one command text plus one fixture, about 6k input tokens for `spec-validate.md`. The SPEC-314 case at N=1 is 3 calls; the proof records the measured cost and time. No path is unbounded: nothing schedules the script, the dry run prints the call count, every call needs `--live`, each call carries `--max-budget-usd 1`, and the first failed sample stops the run.
- Owner and liveness: the kit maintainer, who runs it by hand when a lens changes. Nothing runs on a schedule, so nothing can die silently. The offline suite `tests/test-lens-eval.sh` runs in `run-all`, and a CLI break shows up as exit 2 on the next live run.
- Dependency lifespan: the `claude` CLI flags (`-p`, `--safe-mode`, `--tools`, `--output-format json`) and the envelope fields `.result` and `.total_cost_usd` break first. A renamed flag gives an empty sample, so the run exits 2 and scores nothing. No new credential: the call uses the operator's existing Claude login.
- Retirement: remove `lib/bench/lens-eval.sh`, `tests/test-lens-eval.sh`, `tests/fixtures/sustainability-lens/lens-eval.json`, and the README section. No schedule, heartbeat, secret, or data store is left behind; sample directories live under `$TMPDIR`.
- Handover: `--help`, the `lib/bench/README.md` section, the saved samples, and the case file's plain regexes. Rerun the SPEC-314 case with the command in the After state.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: tests first | `tests/test-lens-eval.sh` | every Test plan row, a stub `claude` on PATH, red before T2 |
| T2: the script | `lib/bench/lens-eval.sh` | the Contract above; the T1 suite green |
| T3: SPEC-314 case | `tests/fixtures/sustainability-lens/lens-eval.json` | the Contract's signal list; T1 runs it against the stub |
| T4: docs | `lib/bench/README.md`, `lib/bench/tool.toml`, `docs/CHANGELOG.md`, regenerated `docs/FEATURES.md` | the README names the verb, the live flag, the exit codes, and the SPEC-314 command |
| T5: proof | `docs/verification/prompt-lens-eval.md`, `docs/implementation-notes/prompt-lens-eval.md` | green run, negative control, and a live N=1 run or `[UNAVAILABLE: reason]` |

## Test plan

Every case runs offline. A temp git repo holds a six-reviewer command at `HEAD` and a seven-reviewer command in the working tree. A stub `claude` on PATH logs its argv, counts its calls, and answers from the prompt: a report with Reviewer 7 findings when the prompt carries `### Reviewer 7`, a report without them when it does not. Env knobs make chosen calls leak, miss, or come back empty.

| Case | Setup | Expected |
|---|---|---|
| Usage | no args; `--samples 0`; `--samples x`; `--samples 2`; `--samples 4`; missing command file; a bad ref; a path missing at the ref; a command outside a repo; identical arm text; JSON with no cases; JSON with a signal lacking both arms; `control: fewer` without `treatment: hit`; missing fixture; a fixture with `..`; an absolute fixture; duplicate case names; duplicate signal names; a signal name with `\|`; an invalid regex; unknown flag | exit 64, stub never called; bad ref, missing path, and not-a-repo print distinct messages |
| Claude missing | a PATH with jq but no claude | exit 2, `verdict: ERROR (claude not on PATH)` |
| Dry run | the SPEC-314 case file, no `--live` | exit 3, `NOT RUN`, the plan names 3 calls (the short-lived case names no control), stub never called |
| Plan count | `--samples 3`, no `--live` | the plan names 9 calls |
| Live pass | the SPEC-314 case file, stub answers realistically with a `## Passed` section whose bullet names a heartbeat | exit 0, `verdict: PASS`, one row per signal, 3 calls, `-` in the short-lived control cells, control 0/1 on the pair row |
| Summary | live pass | `base: HEAD <sha>` and `text sha256: treatment <x> control <y>` match the temp repo |
| Call shape | live pass | the stub argv carries `-p`, `--safe-mode`, `--tools` with an empty value, `--max-budget-usd 1`, `--output-format json`, `--model sonnet`; `--model haiku` passes through |
| Isolation | live pass | the control prompt carries no `### Reviewer 7`; the treatment prompt does; both carry the fixture text |
| Control leak | the stub's control answer names a heartbeat at N=1 | exit 1, the pair row `1/1 want fewer` FAIL, the verdict names `liveness` |
| Control fewer | N=3, control leaks on 2 of 3 calls; then on 3 of 3 | 2/3 under treatment 3/3 passes; 3/3 fails |
| Treatment miss | the stub's treatment answer drops the Reviewer 7 findings | exit 1 |
| Noisy quiet case | the stub raises a Reviewer 7 cost warning on the short-lived fixture | exit 1, the quiet row FAIL |
| Reviewer scope | a treatment block names liveness under Reviewer 2 only | the Reviewer 7 liveness signal misses |
| Multi-line finding | the Reviewer 7 tag sits on the item's title line and `rotation` on an indented line below | the rotation signal hits |
| Majority | N=3, treatment hits on 2 calls; a hard control `miss` with 1 then 2 leaks | hit passes; hits on 1 call fails; the hard miss passes at 1/3 and fails at 2/3 |
| Table rows | a report with a findings table, one Reviewer 2 row naming a heartbeat | each row is its own block; the Reviewer 7 liveness signal misses |
| Passed section | pass bullets tagged Reviewer 7 naming a heartbeat and a retry, then a later heading | both miss; a Reviewer 7 finding under the later heading hits |
| Reviewer headings | findings grouped under `### Reviewer 2` and `### Reviewer 7`, then `### Verdict` | items under Reviewer 7 credit Reviewer 7; items under Reviewer 2 and Verdict do not |
| Empty sample | at N=3, call 2 returns an empty `.result`; another run where the stub exits 1; another where the envelope says `is_error: true` with text | exit 2, `ERROR` names the sample, the stub saw 2 calls, never PASS |
| Option-shaped base | base ref `--output=x` | exit 64, no file named `x` written |
| Cost sum | 3 calls at 0.01 each | `cost: $0.03 over 3 calls` |
| Samples saved | live pass | the printed directory holds 3 files named `<case>.<arm>.<i>.md` |
| Repo untouched | live pass | `git status --porcelain` in the temp repo is unchanged |

Negative control: `lib/gate/negctl.sh` deletes the line that drops the Passed section. The Live pass, Control fewer, Majority, and Passed section rows must go red.

## Verification

`bash tests/test-lens-eval.sh` exits 0. `bash tests/run-all.sh --changed` exits 0. `bash lib/gate/negctl.sh "$PWD" "bash tests/test-lens-eval.sh" "<mutation>"` reports the suite red under the mutation.

## After state

A lens change reruns its eval with one command:

`bash lib/bench/lens-eval.sh commands/spec-validate.md 118485af~1 tests/fixtures/sustainability-lens/lens-eval.json --live`

The run prints a per-case, per-signal table and a verdict, and it keeps the raw reports.

Not covered: a hung call has no timeout. A keyword grep cannot judge whether a finding is right, only whether it names the thing. A new command with no file at the base ref has no control arm. The other prompt-only commands get case files when their lenses next change; this spec wires only SPEC-314.

## Decision Log

- Bash in `lib/bench/`, not a verb of `bench.py`: see Approaches considered.
- Exit 3 for a dry run, so no script reads a dry run as a pass.
- `--safe-mode` over `--bare`: `--bare` never reads OAuth, which is how the operator logs in.
- Scoring by finding block, not by line: the first live run tagged each finding `Reviewer 7.` on its title line and put the detail on indented lines. The line grep missed a credential-rotation finding that was there.
- Validation (seven lenses, APPROVED, design record PASS, design-bearing=yes, Reviewer 7 long-lived with all five answers present) raised three warnings, all folded in: an `is_error` envelope counts as a failed sample (Reviewer 2), a base ref starting with `-` is refused before `git show` (Reviewer 1), and the `reviewer` regex should accept a reviewer's name as well as its number (Reviewer 3).
- Self-review found two silent passes, both fixed with a test: a repeated case name let one case's samples overwrite another's, and an invalid regex made grep exit 2, which scored as a miss and passed a `miss` expectation (the old script exited 0 on that case file). Both now exit 64 before any call.
- Design critique and code review (REVISE) folded in: the scorer drops a Passed section, splits table rows, and credits reviewer headings; a planted-gap pair compares control to treatment (`control: fewer`) instead of requiring a control miss; spend is capped per call and the run stops at the first failed sample. The quiet case keeps a hard `miss`. The `quiet-pass` signal left the case file, because its pass line sits under Passed.

## Design critique

Date: 2026-09-26. Lenses: simplicity 8, performance/cost 6, boundaries 8, data-model 5, operability 6. Verdict: REVISE.

- H1 (scorer segmentation): table rows merged into one block, Passed bullets scored as findings, and items under a `### Reviewer N` heading lost their reviewer. Fix: a table row is its own block, a Passed section is dropped to the next heading, and a reviewer heading credits the blocks under it.
- H2 (control semantics): a planted-gap pair required control to miss, so an old lens that notices a gap now and then failed the eval. Fix: `control: fewer` passes when treatment hits and control has fewer hits; `miss` stays for the quiet case.
- M1 (spend): no per-call cap, and a failed sample still spent the rest of the run. Fix: `--max-budget-usd 1` per call and exit 2 on the first failed sample.
- M2 (vacuous run): identical control and treatment text ran and scored. Fix: exit 64.
- M3 (provenance): the summary did not pin what ran. Fix: it prints the base sha and a 12-hex sha256 of each arm's text.
- M4 (claim scope): the README implied a production run. Fix: the Scoring section says one model plays every reviewer inline, so a PASS is evidence about the prompt text.
- M5 (ties): an even N allowed a tie. Fix: an even `--samples` above 1 exits 64.
- L1 (diagnostics): one message covered not-a-repo, a bad ref, and a missing path, and a missing claude surfaced as a failed sample. Fix: distinct messages and a `command -v claude` check before the first call.
- L2 (case-file hygiene): a fixture could escape the case directory, and signal names could repeat or break the table. Fix: refuse `..` and absolute fixture paths, duplicate signal names, and names outside `[A-Za-z0-9._-]`.
- L3 (registry honesty): `lib/bench/tool.toml` folded lens-eval into the bench.py summary. Fix: its own `[lens-eval]` table; bench.py keeps `entry`.

Resolved in-branch: H1, H2, M1, M2, M3, M4, M5, L1, L2, L3.
