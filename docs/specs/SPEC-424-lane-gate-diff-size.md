# Spec: the hard-path floor sizes a change by its diff when the change adds a workflow file

Generated: 2026-11-25
Status: DRAFT (revised after the security validation: allow-list grammar for Rule A)
Lane: full (the build edits `lib/classify/lane-classify.sh` and `lib/gate/ship-rules.sh`, the push gate's own enforcement path, and narrows a hard-path trigger)
Depth: standard (every behavior below was reproduced with the real `floor` verb on scratch repos; the decision brief and the row fix the intent)
Type: spec-feature
References: `lib/classify/lane-classify.sh` (`floor`, `_floor_scan`, `_floor_comment_only`, `_floor_find`, `_floor_drop`); `lib/gate/ship-rules.sh` (`ship_rule_floor`, `_sr_relay`); `docs/specs/SPEC-410-ceremony-fits-diff.md` (the comment-only and docs rules this spec extends); `docs/briefs/DECISION-BRIEF-team-stamp.md` (build step 2, "Lane gate sizing" exit criterion); `tests/test-ceremony-fits-diff.sh` (the suite that gets the new rows).

## Problem

The full lane fires on any hard-path file whatever the change. In one two-day session on a private product repo, four small CI and config edits each owed twelve recorded phases, most of them overrides, and the repo turned `lane_gates` off. An override that nobody reads is not a gate. The repo lost the floor for every later change too, including the ones that deserve it.

Intent: keep the full lane when a change alters what a gate or a hook does. Size by the diff when the change only adds a workflow file, flips one config key, or edits a comment.

## Where the floor stands today

Real `floor` verb, scratch repo with a committed `.kit.toml` (`lane_gates = true`, `extra_hard_paths = "^hooks/|^lib/gate/"`), one existing workflow, one existing hook, base `main`, head one commit. Reproduced with `bash lib/classify/lane-classify.sh floor <root> main`.

| Case | Change | Floor today | Evidence |
|---|---|---|---|
| Add a workflow file | new `.github/workflows/lint.yml` | `full ci: .github/workflows/lint.yml` | `_HP_ci` matches any path under `.github/` (`lane-classify.sh:113`); no rule looks at status or content of a `ci` hit |
| Flip one config key | `wave_cap = 2` to `3` in `.kit.toml` | `full kit-config: .kit.toml` | `_HP_kitconfig` (`:115`); `_floor_comment_only` accepts only comment lines |
| Flip a gate key | `lane_gates = true` to `false` in `.kit.toml` | `full kit-config: .kit.toml` | same; must stay this way |
| Edit a comment, comment follows a comment or the top | `# guard two` reworded in a hook; `# ci notes` reworded at the top of a workflow; `# header` added at the top of `.kit.toml` | no hit | `_floor_comment_only` (`:628`) |
| Edit a comment, comment follows a code line | `# note` appended below code in `.kit.toml`; `# fresh` added under `name: ci` | `full kit-config` / `full ci` | the change-group rule keeps the floor on purpose (SPEC-410) |
| Turn code into a comment | `if [ ... ]` becomes `# if [ ... ]` in a hook | `full extra: hooks/guard.sh` | a changed non-comment line makes `bad = 1` (`:672`) |
| Change a hook's behavior | `exit 2` becomes `exit 0` | `full extra: hooks/guard.sh` | extras are matched in `_floor_find` (`:594`) |
| Workflow add plus hook change | both in one diff | `full ci` (first line wins) | the loop reports the earliest hit |
| Edit a markdown doc under `hooks/` | `hooks/NOTES.md` | no hit | docs are blanked first (`:787`) |

So: comment edits already pass where the change group follows a comment, a blank line after one, or the top of the file. The hook case already owes the full lane. The workflow add and the config-key flip owe the full lane today. Only the workflow add is needed for the Done line.

Two more facts the design leans on:

- A comment-only drop is silent today. Only `[[gate.hard_path_exempt]]`, the test-path default and the sqli carve-out write a `floor-exempt` line on stderr, which `_sr_relay` turns into an `[advisory]` line and a `EXEMPT | floor |` log line (`ship-rules.sh:120-157`).
- `proof-ledger.sh classify` treats a diff made only of `.kit.toml` as `inert`: it owes no proof (`proof-ledger.sh:129-140`). A workflow file classes `behavioral`.

## Terms

Delta only. The glossary `CONTEXT.md` is not touched.

- sized-down: the floor reports no hit for a path it would otherwise report, because the diff content proves the change adds no gate or hook behavior. The full lane's phase ledger is not owed. The proof gate still applies by its own rule.
- additive workflow: a workflow file the diff creates, with no other `.github/` path in the diff, whose whole text matches the closed line grammar of "Rule A". The rule sizes a small plain check workflow and nothing else; a refusal costs one phase ledger.

## Solution

### Approaches considered

1. Sizer inside the floor (chosen). Add one drop rule beside the existing comment-only drop in `_floor_scan`. No new verb, no new config, no change to the hook.
2. A new `[gate]` or `[lanes]` config key that lists path globs the floor may size down. Rejected: a PR could widen the list in the same diff, and the floor already reads config only at the merge base, so the list would only help on the next PR. It also gives the full-lane trigger a second, reviewable-by-nobody exemption path (the rule `_HP_testpath` already refuses: "a config hook here would be a second, unreviewed exemption path").
3. Size by changed-line count (`deescalate`'s approach). Rejected: a one-line `exit 2` to `exit 0` is the change that most needs the full lane.

### Chosen approach + why

The decision comes from the diff content and the path status, read by constants in `lane-classify.sh`. Nothing the PR writes (title, spec header, config, a comment in the file) can widen it. Every rule fails closed: a check that cannot decide leaves the floor standing, as `_floor_comment_only` does.

### Extensibility and boundaries

The load-bearing dimension is the list of shapes the sizer accepts. Today it is one added-workflow shape plus the existing comment-only shape. A new shape is a new drop rule with its own tests and its own `floor-sized` rule name; it edits `lane-classify.sh`, so it owes the full lane itself. The sizer never reads config.

## Picture

```
 git diff --raw base head (status + modes + paths)
        |
        v
  docs blanked --> comment-only drop (existing) --+
        |                                         |  each drop writes
        v                                         |  floor-sized <kind> <rule> <path>
  _floor_find: first hard-path hit                |  on stderr
        |                                         |
        +--> hit is kind ci, status A, ... ------>+--> Rule A (new): all of A1..A6 hold?
        |                                              yes: drop line, look again
        |                                              no / cannot tell: floor stands
        v
  any hit left --> `full <kind>: <path>` --> ship_rule_floor --> ledger check (full)
  no hit left  --> data-loss scan on added lines --> `full data-loss` or nothing
                                                          |
  ship_rule_floor relays floor-sized lines                v
  as [advisory] + `SIZED | floor |` log          nothing: no phase ledger owed;
                                                 proof gate still applies (workflow = behavioral)
```

## Design

### Rule A: a new workflow file is sized down only when its whole text matches a closed line grammar

The first draft used a deny list over free text. A deny list has to be right about every YAML feature, and the security validation found ten holes in it (escapes, `?` keys, aliases, matrix names, job-level `uses:`, a fail-open `git show` pipe, an author-chosen read point). Rule A is now an allow list by line: each line of the file must match one production below, and a line that matches none keeps the floor. The grammar only has to be right about the lines it admits.

Path and diff checks. All must hold; any failure, any read error, any doubt keeps the floor.

| # | Check | Closes |
|---|---|---|
| A1 | Raw status is `A` and head mode is `100644`. A modified, deleted, renamed (`--no-renames` gives delete plus add) or symlinked workflow never qualifies. | 10 |
| A2 | The path is `.github/workflows/<name>.yml` or `.yaml` with `<name>` in `[A-Za-z0-9._-]+`, and matches no other hard-path kind, no extra pattern and not the secret pattern. A newline in a name is folded to `?` by the scan and fails this. | 5 |
| A3 | Exactly one path in the UNBLANKED path list matches `(^|/)\.github/`, case-insensitive. A comment-dropped `.github/` file or a `.github/*.md` beside the workflow keeps the floor. | 9 |
| A4 | The head image is read once into a temp file under the floor's temp dir, with the exit status of `git show` tested. It must be non-empty, at most 20000 bytes, NUL-free. There is no pipe from `git show` into a test anywhere in Rule A, and every `grep` and `awk` status is tested explicitly: only the expected status admits, any other keeps the floor. | 5 |
| A5 | The file matches the grammar below. | 1, 2, 3, 4 |
| A6 | No collision, with the base files classified or refused. The names the new file defines (workflow `name:`, each job key, each job `name:`) are compared with the names of every workflow file at three revisions: the merge base, `KIT_FLOOR_CONFIG_AT` when set, and the default-branch tip `origin/<default>` (if it cannot be resolved, or is not an `origin/` ref, the floor stands). Base files are files we do not control, so each is read by "anything we cannot classify keeps the floor": the reader classifies every line of the `jobs:` key level and every workflow-name and job-name line, and a shape it cannot classify keeps the floor. A base name that holds `${{ ... }}` becomes a glob (each expression is `*`), a new name that matches the glob keeps the floor, and a base name that is only an expression matches every new name. Any `workflow_run` anywhere in a base workflow keeps the floor; its `workflows:` list is not parsed at all. At most 50 files per revision, 200000 bytes each, and every byte count must be all digits. | 3, 4, 7, review 1 to 3, 5 |

Grammar (A5). Every line is printable ASCII (space to `~`), has no trailing space, contains no backslash and no `${{`, and the file has at most 200 lines. Indentation is spaces, in steps of 2. Productions, by indent:

```
any indent   blank line (zero length) | a line whose first non-space byte is "#"
col 0        name: <plain>            once; <plain> = [A-Za-z0-9][A-Za-z0-9 ._-]*, not y n yes no on off true false null, not all digits
             on:                      once, block style; at least one event
             permissions:             once, followed by exactly one child  "  contents: read"
             permissions: {}          the one brace line admitted (instead of the block form)
             jobs:                    once; at least one job
on, indent 2   push: | pull_request: | workflow_dispatch:      each at most once, no value
on, indent 4   branches: | paths:     only under push or pull_request, each once per event
on, indent 6   - <item>               item = [A-Za-z0-9._/][A-Za-z0-9._/*-]*, only under branches or paths
jobs, indent 2 <key>:                 key = [A-Za-z0-9][A-Za-z0-9_-]*, not boolean-like, unique
job, indent 4  name: <plain> | runs-on: <plain> | runs-on: [self-hosted(, <plain>)*] | timeout-minutes: <digits, at most 4> | steps:
               each at most once; runs-on and steps required
step, indent 6 "- " then one step key (a new step)
step, indent 8 one step key:  name: <plain> | uses: actions/checkout@<40 lowercase hex> | actions/setup-<[A-Za-z0-9_-]+>@<40 lowercase hex> | with: |
               run: <single-line value> | run: | | shell: bash|sh | working-directory: <path>
               each at most once per step; exactly one of run and uses per step; at least one step per job
with, indent 10  <key>: <[A-Za-z0-9][A-Za-z0-9 ._/-]*>      only directly under with:
```

A single-line `run:` value starts with `[A-Za-z0-9._/-]` and continues with `[A-Za-z0-9 ._/=+,@"'$()&|;<>*-]`. It cannot hold `:`, `#`, `%`, `!`, `?`, `{`, `}`, `[`, `]`, a backtick or a backslash, so it cannot open a comment, a mapping, a flow collection, an alias, a tag or a directive.

Block scalar tracking (`run: |` exactly; `|-`, `|+`, `|2` and `>` are refused). After the `run: |` line the scanner is inside the block. Rules: the first non-blank line must be indented exactly 10 spaces; every later non-blank line stays inside the block while its indent is at least 10; blank lines are zero-length; the block needs at least one content line. A non-blank line indented less than 10 ends the block, and from then on it is read as an ordinary line under the grammar above, so a line at indent 8 or less must be a legal production. A line indented 10 or more cannot be anything but block text, because YAML itself reads it as scalar content. The scanner never ends a block earlier than YAML does, so a key cannot be smuggled in as "outside" the block. Any line inside a block still obeys the byte rules (printable ASCII, no backslash, no `${{`).

Base-side classification (A6), what keeps the floor. In a base workflow: any `workflow_run`; a document marker (`---`, `...`); a tab; a top-level line that is not a plain `key:`; `jobs:` with an inline value; a job key that is quoted, complex (`?`), anchored, aliased, a flow map, or not `[A-Za-z0-9_-]+:`; a job-level `uses:` (a reusable-call check name is `job / called job`); a job property line that is neither `- ` nor a plain key (a merge key `<<:`); a name value that is empty (a block follows), a `|` or `>` scalar, an anchor, an alias, a tag, a flow value, an unterminated `${{`, a quoted value with an escape, or a value holding `: `. Byte rule, checked first for each base file at each of the three read points with one `LC_ALL=C` pass whose exit status is tested: the file may hold only bytes 0x20 to 0x7E, LF, and CR when it ends a line; a bare CR, a tab, a NUL, NEL, LS, PS, a BOM or any byte from 0x80 up keeps the floor, so a repo whose existing workflows hold a tab or a non-ASCII byte never sizes a workflow add. A `name:` line, at the workflow level or the job level, must not be continued: the next non-blank, non-comment line must be indented no deeper than the `name:` line itself (a multi-line plain scalar would give a check name the reader never saw), and an empty name value keeps the floor. A glob that still holds `}}` or `${{` after the expressions are replaced keeps the floor. Every other place a value could continue on the next line is already refused: a quoted scalar left open, a plain value after a job key, a block or folded scalar, a value on the next line. A plain base is read as: the workflow `name:`, each job key, each job-level `name:`, each also cut before ` (` and at its last ` / ` segment.

Not admitted, so each keeps the floor: `if:`, `env:`, `needs:`, `strategy:`, `continue-on-error:`, `secrets`, `concurrency`, `defaults`, `container`, `services`, a job-level `uses:` or `permissions:`, any `permissions:` below the top level, `schedule`, `pull_request_target`, `workflow_run`, `repository_dispatch`, any step `uses:` that is not `actions/checkout@<40-hex>` or `actions/setup-<name>@<40-hex>` (`actions/cache`, `upload-artifact` and `github-script` included), any tab, CR, non-ASCII byte, `&`, `*` or `!` at a value start, `?` at a key start, `<<`, `{` (except the one line above), `[` (except the one `runs-on` form), `%`, `---`, `...`, and any duplicate key at any level.

Residual, stated plainly. For a sized diff the phase ledger, the battery (`battery-gate.sh` prints SKIP for a small diff with no floor hit) and the mega-merge floor all drop; only the proof of done still binds. A workflow on a self-hosted runner can run a script added in the same diff, as a test file can today, and that script can do what the runner's own login can do. The grammar limits what the workflow file says; it does not limit what the code it names does. A sized workflow on a hosted runner also spends minutes; `runs-on:` stays as the grammar admits it. The operator accepted this in the row's Done line ("a PR adding one CI workflow file passes with a proof and no phase ledger"). Nothing else is weakened to make the rule more useful.

The data-loss scan still runs on the added lines of a sized workflow and still returns `full data-loss` for a `drop table` line.

### Rule B: comment-only edits (existing, now logged)

Unchanged semantics: `*.sh *.bash *.zsh *.py *.toml *.yml *.yaml *.tf`, `Dockerfile`, `*.dockerfile`, under the change-group, position, suppression and data-line rules of SPEC-410. A change that turns code into a comment is a changed non-comment line and keeps the floor. JSON has no comment syntax, so a JSON change always keeps the floor. Markdown is a doc and is never a hit. The new part is the audit line, see below.

### Rule C: flipping one config key is not sized in this spec

The row names it, the Done line does not need it, and three facts argue against building it now:

1. The config edit that started the row (turning `lane_gates` off) is a gate change. The brief's own rule keeps it full. Every `[gate]` and `[proof]` key, `commit_format`, `board_row_gate`, `[[gate.hard_path_exempt]]`, `[lanes]` and `[lane.*]` is in that class.
2. A `.kit.toml`-only diff classes `inert`, so a sized `.kit.toml` change would owe neither the phase ledger nor a proof. That breaks the bar that a sized change still owes its proof. Fixing it means changing the proof class of `.kit.toml`, a separate gate change.
3. No key in `kit.toml` is both behavior-neutral and worth the surface. The only candidates are advisory thresholds (`[ledger] delivery_ratio_warn`, `delivery_real_floor`). `[mega]`, `[merge]` and `[wrap]` keys change how PRs merge.

If the operator wants it, the follow-on spec adds a closed `(section, key)` constant list in `lane-classify.sh`, requires the diff to be exactly one changed `key = value` line, and first makes `.kit.toml` diffs owe a proof. Any key not on the list, any added or removed key, any change inside `[gate]`, `[proof]`, `[lanes]`, `[lane.*]` or `[[gate.hard_path_exempt]]` keeps the floor.

### Floor-verb hardening from the review round

- Every git call the floor makes ignores replace refs (`--no-replace-objects` in `_floor_git`, `GIT_NO_REPLACE_OBJECTS=1` for the verb), so a `git replace` ref cannot show the grammar one blob while the push sends another or hide a required workflow at the origin tip.
- If a tool the verb runs is missing (`git awk sed tr grep wc head cut cmp mktemp cp mv rm cat sort paste basename env`, read from the verb's functions and the config readers it calls; `dirname` is run before the verb can start, so it cannot be checked there), or the temp dir cannot be made, the verb prints `full tools-missing: <name>` and returns. Before, a missing tool made the floor print nothing. The check sits at the verb's entry only.

### The audit line

Every drop by Rule A or Rule B writes one TAB line on the floor's stderr, path last (a path cannot forge a field):

```
floor-sized<TAB><kind><TAB><rule><TAB>-<TAB><reason><TAB>-<TAB><path>
rule = additive-workflow | comment-only
```

`_sr_relay` maps it to `A<TAB>[advisory] hard-path sized <kind>: <path> (<rule>)` and `L<TAB>SIZED | floor | <rid> (<kind>: <path>; <rule>)`, with the same folding of non-ASCII bytes and `|`. Rule A lines are never capped. Comment-only lines are capped at 20; the overflow writes one `[advisory]` count line and one `L` count line (`SIZED | floor | <rid> (comment-only: N more files)`), so the workflow drop is never lost behind 20 earlier drops. `_floor_check` already carries `SR_NOTICES` into the exit-0 hook message, so `hooks/ship-gate.sh` needs no change. A sized-down diff that still ends in `full ...` (a mixed diff) prints the notices and then the BLOCKED message, as exemptions do today.

### Where the config is read

The sizer reads none. Rule A and Rule B are constants in `lane-classify.sh`. `ship_rule_floor` keeps reading `lane_gates` and the exemptions at the merge base (`ship-rules.sh:172`, `KIT_FLOOR_CONFIG_AT`), so a PR that adds a workflow and sets `lane_gates = false` is a `kit-config` hit in the same diff and the floor reads the switch from the base.

### Callers

`lane-classify.sh floor` has four callers: `ship_rule_floor` (the hook and the mega gate, twice), `_negctl_required` in `proof-ledger.sh` and `battery-gate.sh`. All of them see the new answer. Intended effects: a sized workflow add owes no phase ledger and, in a mega run, passes the merge gate's floor; `battery-gate.sh` may print `SKIP: small change` for it (it owes a proof, not the battery). `_negctl_required` also asks `explain --files`, which still flags `.github/` as a hard path, so under `negative_control = full` a sized workflow keeps its negative-control requirement. That is the stricter side and stays.

## Failure modes

| Class | Mitigation |
|---|---|
| A workflow claims it is trivial (title, spec `Lane: tiny`, a comment saying so) | no rule reads those; a comment holding a deny word keeps the floor; `ship_rule_floor` ignores the spec lane |
| A PR adds a workflow and turns `lane_gates` off in the same diff | the `.kit.toml` change is its own `kit-config` hit; the switch is read at the merge base |
| A PR edits an existing workflow to weaken a check | status `M` fails A1 (pinned with every name changed, so A6 cannot be the cause) |
| A PR renames a workflow and weakens it | `--no-renames` gives a delete plus an add; the delete keeps the floor |
| A new workflow shadows a required check name, including a matrix name, a reusable-call name, a `workflow_run` target, or a base that predates the required workflow | A6 (three read points, prefix and last-segment variants) and the name charset |
| A new workflow runs on `pull_request_target` or `workflow_run`, holds a write grant, a secret, a deploy step, a job-level `uses:`, an unpinned step action | the A5 grammar admits none of them |
| A YAML escape (`"\x77rite"`), a `?` key, an alias, a tag, a second document, a flow map | the A5 grammar and the byte rules admit none of them |
| A block scalar ends early and a key hides after it | the block tracker ends a block only where YAML does; a line outside it must be a legal production |
| A hidden or odd byte, a CR, an oversized file, an unreadable blob, a newline in the name | A2, A4 and tested exit statuses |
| Mixed diff: sized file plus any other hard-path change | the loop drops the sized line and looks again; any other hit decides the answer |
| Two sized workflows, or a workflow beside any `.github/` file, in one diff | A3 on the unblanked path list |
| Sizer slow on a pathological diff | shares the 50 drop and 8 second budget of the comment-only loop; past either, the floor stands |
| A workflow still executes arbitrary code on the runner | accepted and stated above; the phase ledger was never the control for that |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: tests first | `tests/test-ceremony-fits-diff.sh` | every Test plan row is a case; the suite is red on the merge-base libs for the sizing rows |
| T2: status, mode and unblanked path list | `lib/classify/lane-classify.sh` | `_floor_scan` writes `status`, `hmode` and `paths.all` beside `paths` |
| T3: Rule A | `lib/classify/lane-classify.sh` | `_floor_workflow_additive` returns 0 only when A1 to A6 hold; the grammar is one awk program; every check is one tagged line so a mutation can switch it off |
| T4: audit line | `lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh` | both drop rules write `floor-sized`; `_sr_relay` relays it, Rule A uncapped, comment-only capped with a count line |
| T5: mutation rows | `tests/test-ceremony-fits-diff.sh` | each finding's rows go red when that finding's tagged lines are neutralised, green on the real libs |
| T6: docs | `lib/gate/README.md`, `docs/MANUAL.md`, `docs/WORKFLOW.md`, `CHANGELOG.md`, `docs/reference/FEATURES.md` | each says the rule sizes a small plain check workflow and nothing else; `docs/WORKFLOW.md` states the residual in plain words |

## Test plan

Date: 2026-11-25
Source: this spec's Acceptance Criteria and the security validation (findings 1 to 10)

All rows are cases in `tests/test-ceremony-fits-diff.sh`. Fixture: scratch repo with an `origin` remote at the base, a committed `.kit.toml` (`lane_gates = true`, `extra_hard_paths = "^hooks/|^lib/gate/"`), one existing workflow, one existing hook. A refusal row asserts `floor` prints `full ci: <path>` (or the kind named). The last row, `rule-a-checks-are-load-bearing`, rebuilds the libs with each finding's tagged lines switched off and requires the rows of that finding to go RED.

| # | Case | Category | Covers | Expected |
|---|------|----------|--------|----------|
| 1 | `floor-additive-workflow-is-sized` | happy-path | AC-1 | one plain workflow: no hit; stderr has one `floor-sized ci additive-workflow` line |
| 2 | `ship-rule-floor-sizes-workflow-add` | happy-path | AC-1, AC-6 | `ship_rule_floor` rc 0 with a ledger that lists unmet gates; log has `SIZED | floor |` |
| 3 | `sized-workflow-still-owes-proof` | happy-path | AC-3 | class `behavioral`; `check` fails with no proof file, passes with one |
| 4 | `floor-hook-behavior-change-keeps-full` | happy-path | AC-2 | `full extra: hooks/guard.sh`; `ship_rule_floor` blocks even with a `Lane: tiny` spec |
| 5 | `floor-workflow-mixed-diffs-keep-full` | security | AC-4, AC-5 | workflow plus hook change, plus `lane_gates = false`, plus a second workflow, plus a comment-only `.github/` file, plus `.github/NOTES.md`: each keeps the floor (finding 9) |
| 6 | `floor-workflow-existing-workflow-keeps-full` | security | AC-4 | a modified workflow with every name changed; a rename with new names: each `full ci` (finding 10) |
| 7 | `floor-workflow-escapes-keep-full` | security | AC-4 | `contents: "\x77rite"`, `"id-\x74oken": "\x77rite"`, `"${{ \x73ecrets.X }}"` (finding 1) |
| 8 | `floor-workflow-on-block-tricks-keep-full` | security | AC-4 | `? pull_request_target`, `on: *t`, a `---` document, `on: {push: null}`, `on: [push]`, `pull_request_target:`, `schedule:` (finding 2) |
| 9 | `floor-workflow-name-tricks-keep-full` | security | AC-4 | base job `name: test (${{ matrix.os }})`: new `name: test`, `name: test (ubuntu-latest)`, `name: build / test`, `name: ${{ 'te' }}st` (finding 3) |
| 10 | `floor-workflow-reuse-and-privilege-keep-full` | security | AC-4 | job-level `uses: ./.github/workflows/release.yml`; `uses: foo/bar@v1`; `uses: actions/checkout@v4`; a name equal to a base `workflow_run` target (finding 4) |
| 11 | `floor-workflow-read-failures-keep-full` | failure-injection | AC-4 | a newline in the file name; an empty file; a NUL byte; `git show` of the head fails (finding 5) |
| 12 | `floor-workflow-collision-read-points` | security | AC-4 | a branch cut before the required workflow landed collides with the origin tip; no `origin` ref keeps the floor; a collision at `KIT_FLOOR_CONFIG_AT` (finding 7) |
| 13 | `floor-workflow-block-scalar-cannot-smuggle` | security | AC-1, AC-4 | a `run: |` block with deeper lines is sized; a key at indent 8 or 6 after the block, a first content line at indent 12, `|-`, an empty block: each keeps the floor |
| 14 | `floor-workflow-odd-path-keeps-full` | boundary | AC-4 | nested path, `.yml.off`, `login.yml`, `.github/actions/a/action.yml`, `CODEOWNERS`, `dependabot.yml`, a new `.github/x.json` |
| 15 | `floor-workflow-odd-file-keeps-full` | failure-injection | AC-4 | symlink, mode 100755, CR, tab, non-ASCII, 201 lines |
| 16 | `floor-workflow-grammar-refusals` | security | AC-4 | `if:`, `env:`, `needs:`, `strategy:`, `continue-on-error:`, job-level `permissions:`, `permissions: write-all`, `contents: write`, `secrets`, `&a`, `!!str`, `<<`, `%`, duplicate keys, `runs-on: [ubuntu]`: each keeps the floor |
| 17 | `floor-workflow-data-loss-line-keeps-full` | security | AC-4 | a `drop table` in a `run` step: `full data-loss` |
| 18 | `floor-code-to-comment-keeps-full` | security | AC-4 | code turned into a comment in a hook; a JSON change under `.github/`; a `.kit.toml` comment below code |
| 19 | `floor-comment-edit-is-sized-and-logged` | regression | AC-1, AC-6 | no hit; stderr has `floor-sized ... comment-only` |
| 20 | `floor-config-key-flip-keeps-full` | regression | AC-5 | `wave_cap = 3`, `lane_gates = false`: `full kit-config` |
| 21 | `sized-notices-relay-and-cap` | boundary | AC-6 | 25 comment-only plus one workflow drop: the workflow `SIZED` line is present, comment lines are capped at 20 with a count line on both channels (finding 6) |
| 22 | `floor-sized-flood-keeps-floor` | boundary | AC-4 | 51 comment-only files plus a workflow add: a hit remains |
| 23 | `rule-a-checks-are-load-bearing` | regression | AC-1, AC-4, AC-6 | per finding and per review row, the rows above go red with its tagged lines neutralised; the single-fault rows are checked by label |
| 24 | `floor-workflow-base-expression-names` | security | AC-4 | base name `lint-${{ matrix.lang }}`, `${{ matrix.target }}`, `a-${{ x }}-z`: a matching new name, or any new name for a bare expression, keeps the floor; a non-matching name is sized |
| 25 | `floor-workflow-base-workflow-run-anywhere` | security | AC-4 | a base `workflow_run` as a one-line list, a multi-line list, a scalar, a comment, any case: the floor stands even for an unrelated new name |
| 26 | `floor-workflow-base-unclassifiable-keeps-full` | security | AC-4 | quoted or complex or anchored or flow job key, folded or literal or empty or anchored name, inline `jobs:`, job-level `uses:`, merge key, tab, document marker, flow document |
| 27 | `floor-workflow-replaced-objects-keep-full` | security | AC-4 | a `git replace` ref that shows the grammar benign text for a `contents: write` file keeps the floor |
| 28 | `floor-workflow-byte-count-must-be-digits` | failure-injection | AC-4 | a `wc` that prints garbage or nothing keeps the floor |
| 29 | `floor-tools-missing-prints-a-hit` | failure-injection | AC-4 | each of git awk sed tr grep wc missing, and an unusable temp dir: `full tools-missing: <name>` |
| 30 | `floor-workflow-action-allowlist` | security | AC-4 | `actions/cache`, `upload-artifact`, `github-script`, `download-artifact`, a third-party action keep the floor; `checkout` and `setup-node` pins are sized |
| 33 | `floor-workflow-base-name-continues` | security | AC-4 | a base job or workflow name continued on a deeper next line (also after a comment or a blank line): the floor stands; a same-indent next key is sized |
| 34 | `floor-workflow-base-glob-braces` | security | AC-4 | a base name that still holds `}}` or `${{` after the glob step keeps the floor |
| 35 | `floor-workflow-base-byte-rule` | security | AC-4 | a base file with a bare CR or NEL that hides a name, a tab, a UTF-8 letter in a comment, a BOM, or a bare CR inside a comment keeps the floor; a CRLF file still classifies and sizes |
| 31 | `floor-workflow-single-fault-rows` | security | AC-4 | the one valid fixture with one change each: quoted permission value and key, expression in a comment, unpinned checkout, third-party action, empty file, executable mode, a `---` line, an extra hard path that also matches |
| 32 | regression: `bash tests/test-lanes-data.sh`, `bash tests/test-classify-md-inert.sh`, `bash tests/test-hooks.sh`, `bash tests/run-all.sh --changed` | regression | AC-7 | exit 0 |

### Coverage notes
- Categories skipped: none.
- The Done line end to end (real `hooks/ship-gate.sh` from the worktree, a scratch repo): one plain workflow plus a proof pushes with no phase ledger; a hook behavior change is blocked for the full lane. Captured in the proof file.
- This is a coverage target, not an exhaustive list.

## Verification

Each acceptance criterion holds, `bash tests/test-ceremony-fits-diff.sh` passes with the new cases, three negative controls through `lib/gate/negctl.sh` report PASS (remove the whole Rule A drop; remove the grammar check; remove the audit line), the mutation row shows each finding's rows red, and `bash tests/run-all.sh --changed` exits 0.

## After state

A PR that adds one read-only CI workflow file passes the push gate with a proof and no phase ledger. A PR that changes what a hook or gate does, edits an existing workflow, adds a second one, or turns a gate off still owes the full lane. Every drop the sizer makes is an `[advisory]` line on the push and a `SIZED | floor |` line in the audit log, next to the `EXEMPT` lines.

## Acceptance Criteria (global)

- AC-1: a diff that adds one workflow file passing A1 to A6 yields no `floor` hit; comment-only edits stay sized.
- AC-2: a diff that changes a hook's behavior yields `full extra: <path>` and `ship_rule_floor` blocks it without the full lane's gates.
- AC-3: a sized workflow add still classes `behavioral` and owes its proof.
- AC-4: every check that cannot decide, every mixed diff, and every row of the failure-modes table keeps the floor.
- AC-5: the sizer reads no config; the floor reads `lane_gates` at the merge base; no config-key flip is sized.
- AC-6: every sized drop writes one `floor-sized` line and the push shows one `[advisory]` and one `SIZED` log line, capped at 20.
- AC-7: the existing floor, exemption, data-loss and comment-only suites stay green.

## Out of Scope

- Sizing a config-key flip (Rule C): deferred, with the reasons above.
- Sizing a modified existing workflow, a second workflow in one diff, `CODEOWNERS`, `dependabot.yml`, composite actions, and any workflow feature outside the grammar.
- Changing `hooks/ship-gate.sh`, the proof class of `.kit.toml` diffs, `_negctl_required` or `battery-gate.sh`.
- `//` and `/* */` comment syntax (SPEC-410's decision stands).

## Touches

`lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh`, `tests/test-ceremony-fits-diff.sh`, `lib/gate/README.md`, `docs/MANUAL.md`, `docs/WORKFLOW.md`, `CHANGELOG.md`, `docs/reference/FEATURES.md`, `docs/verification/lane-gate-diff-size.md`, `docs/implementation-notes/lane-gate-diff-size.md`.

An open draft PR for an external design citation verb edits `lib/gate/ship-rules.sh` (the BLOCKED block of `ship_rule_floor` and a new helper) and one `hooks/ship-gate.sh` line. This spec edits `_sr_relay` and leaves that block alone, so a later rebase meets only the shared docs files.

## Decision Log

- Scope is Rule A plus the existing Rule B logged, not the three cases in the row. The Done line names two pinned rows; the comment case already passes, and the config-key case conflicts with the proof bar (the `.kit.toml` proof class is `inert`) and with the row's own motivating edit. The smallest honest design that meets the Done line is "add the workflow-file case, log the drops, add the tests".
- Rule A is an allow list by line, not a deny list (lead decision after the security validation). A deny list must be right about every YAML feature; the allow list only has to be right about the lines it admits. It refuses many honest workflows on purpose: a refusal costs one phase ledger.
- Block scalars are tracked by indentation (fixed content indent of 10), because a real workflow needs `run: |`. The tracker ends a block only at a line YAML would also treat as outside it.
- Residual accepted by the operator (the row's Done line): a sized diff drops the phase ledger, the battery and the mega-merge floor; only the proof binds. A workflow on a self-hosted runner can run a script added in the same diff. Recorded in `docs/WORKFLOW.md`.
- Collision names are read at three revisions and the default-branch tip must be an `origin/` ref; with none, the floor stands. This is stricter than the first draft and costs scratch repos an `origin` remote.
- At most one sized workflow per diff, and any other `.github/` path in the diff keeps the floor. This is stricter than the Done line needs and trivial to relax later.
- Name collision (A6) is in because a new workflow whose job reuses a required check's name defeats branch protection without touching any gate file.
- The sizer is constants in `lane-classify.sh`, never config, so a PR cannot widen it and the merge-base rule needs no new branch.
- `hooks/ship-gate.sh` stays untouched: notices ride `SR_NOTICES` already. This also avoids the one-line overlap with the open design-citation PR.
- Comment-only drops now log too, so "every decision the sizer makes" is true of both rules, not only the new one.
- Review round (security review of the built code, BLOCK): the line grammar held; the base-side scraper did not. Principle: the new file is checked by an allow list, base files we do not control by "anything we cannot classify keeps the floor". So the scraper is now a classifier with globs for expression names, `workflow_run` anywhere is a hard stop (no list parsing), replace refs are ignored for every floor read, byte counts must be digits, the verb refuses to answer without its tools, and step actions are limited to `checkout` and `setup-*` (a cache action can write cache entries the base CI reads).
- The ten rows that stayed full with their named check off were split: each single-fault fixture starts from the one valid sized fixture and changes one thing. A few checks are layered (an empty file is stopped by a size test and by the grammar's required sections), so their mutation id switches off every check that refuses that fixture. The older multi-fault rows stay as plain refusals.
- Left as is: a local rewind of `origin/main` also sizes, and the hook's own base follows the same ref (older than this change).
- Review round 2: a base `name:` continued on a deeper line is read as one name by a YAML parser and as a shorter one by a line reader, so the reader refuses any deeper next line instead of trying to join it. The tool list was derived by reading every function on the floor's code path, not guessed.
- Review round 3: the same class came back three times (a base shape YAML honors and the line reader does not), so it ends with a byte rule over the base file instead of one more shape. The cost is stated: a repo whose existing workflows hold a tab or a non-ASCII byte never sizes a workflow add.
