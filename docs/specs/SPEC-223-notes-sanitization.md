# SPEC-223: sanitize board-sourced prompt text before an autonomous run reads it

Status: Draft · 2026-07-31 · Owner: Han
Lane: full (`lane-classify.sh classify` said `normal`; taken heavier because the change is a
security surface on `lib/queue/`, per the AGENTS.md "when in doubt, take the heavier lane" rule)
Relates-to: SPEC-217 (`queue watch`, the `#auto` path this hardens), SPEC-221 (the runaway guards
whose `gated` verdict this reuses), SPEC-148 (`queue run`, the conductor and the trust boundary),
SPEC-146 (`parse-board` allow-list), board row ID-459,
`docs/research/2026-07-31-orchestrator-loop-prior-art.md` (the survey the row came from)

References:
- `github/gh-aw`, `actions/setup/js/sanitize_content_core.cjs` (`sanitizeContentCore`): the ordered
  pre-model transform pipeline. Imitate the ORDER and the truncate-never-reject rule. Do not
  imitate its fenced-code exemption, which is deliberately inverted here.
- `github/gh-aw`, `actions/setup/md/xpia.md`: the untrusted-content preamble. Imitate the framing
  (outside content is data, embedded instructions are ignored), reshaped to one submission.
- `github/gh-aw` safe-outputs + threat detection: the END STATE, named here and deferred, not built.

## Problem

The `#auto` path ends at one line of bash. `_goal_line` in `lib/queue/queue.sh` reads a pointer
file's body, collapses it to one line, and `_mux_type` types it into a session launched with
`--dangerously-skip-permissions`. Whatever is in that file is what a model reads and acts on.

The row's own framing says the Notes cell is unsanitized. Reading the code, the Notes cell is not
the text that reaches the model. `parse-board.sh` already reduces a row to a charset-gated
`#queue{repo=,pointer=}` token, and the row's prose never leaves the parser. What reaches the model
is the POINTER FILE BODY, and the board row is what selects it. Sanitizing the Notes cell would
sanitize a string nobody reads.

So the surface is the pointer body on the watcher-planned path. Its confinement is already good:
the pointer must be relative, must contain no `..`, must live under `_meta/megagoals/` or
`.claude/goals/`, and the watcher re-checks containment with a symlink-aware `realpath`. All of
that decides WHICH file is read. Nothing decides what may reach the model out of it.

**Be honest about the threat level.** Today one operator edits this board and writes the `#auto`
marker by hand, so there is no live attacker. This is defense-in-depth on a schedule. It stops
being theoretical the moment either of these is true, and both are plausible: a second person can
edit `_meta/BACKLOG.md`, or the loop ingests text it did not author (a GitHub issue body, a PR
comment). OpenHands shipped the un-hardened shape and collected CVE-2026-33718 plus two published
prompt-injection-to-exfiltration chains for it. gh-aw is the only surveyed project with a
structural answer.

## Solution

### Approaches considered

1. **Port gh-aw's full separation now**: a read-only agent, NDJSON safe-outputs, a separate
   permission-controlled write job, gated by a model-judge threat detector. Tradeoff: it is the
   right end state and it is an architecture change to the whole loop, for a threat that cannot
   currently be executed by anyone.
2. **Do nothing until a second editor exists.** Tradeoff: honest about the threat level, and it
   means the hardening lands under time pressure on the day it is needed rather than calmly now.
3. **Sanitize the text where it enters the prompt, and name the rest as deferred.** Chosen.

### Chosen approach + why

One ordered transform over the untrusted text, one preamble in front of it, one check behind it.
Approach 1 is recorded as the end state with an explicit tripwire rather than half-built; a
safe-outputs pipeline nobody can currently attack would be a large diff defending a closed door.
Approach 2 trades a small diff today for a rushed one later.

The trust boundary is NOT moved. SPEC-148 already says operator authorship is the boundary: a
hand-authored tsv is exempt from the pointer allow-list, a board-sourced row is not. This change
puts the sanitizer on exactly the same line, so the untrusted path gains a pass and the operator
path is byte-identical to what shipped.

### Extensibility & boundaries

The load-bearing dimension is TRANSFORMS, and it is bounded by ORDER, not by count. Each step
exists to close a bypass the previous one leaves open, so a future addition has to name where in
the sequence it belongs and why. The size cap and the protected-glob set are environment variables,
so tuning is operator config rather than a code change.

Out of bounds by construction: nothing here can stop a running session from writing a file. The
launched session holds `--dangerously-skip-permissions`; no bash wrapper is between it and the
filesystem. This layer controls what text reaches the model, and it can make a protected write
TERMINAL and visible. It cannot make one impossible.

### Architecture

See `## Picture` and `## Design`.

## Picture

```
  _meta/BACKLOG.md          a queued row tagged #auto
        |                   the row's PROSE stops here: parse-board.sh only ever emits the
        |                   charset-gated #queue{repo=,pointer=} token
        v
 +-------------------------------------------------------------------------+
 | lib/board/parse-board.sh      WHICH FILE MAY BE READ        (shipped)    |
 |   charset gate . relative-only . no `..` . repo self-consistency         |
 |   containment under _meta/megagoals/ or .claude/goals/ . file exists     |
 +-------------------------------------------------------------------------+
        |  id <TAB> repo <TAB> resolved-pointer
        v
 +-------------------------------------------------------------------------+
 | lib/queue/watch-board.sh      THE TICK                      (shipped)    |
 |   symlink-aware realpath containment on its OWN plan                     |
 |   --apply now forwards ---------------------------> --sanitize-prompt    |
 +-------------------------------------------------------------------------+
        |  slug <TAB> repo <TAB> pointer   (+ --sanitize-prompt)
        v
 +-------------------------------------------------------------------------+
 | lib/queue/queue.sh  cmd_run                                             |
 |                                                                         |
 |   PREFLIGHT   repo clean? . pointer allow-listed? . sanitizer present?  |
 |                     no sanitizer -> journal `skipped`, NO window opens  |
 |                                                                         |
 |   _goal_line  reads the pointer body                                    |
 |        |                                                                |
 |        |   QUEUE_SANITIZE_PROMPT=0 (operator-authored tsv)              |
 |        +-----> body typed VERBATIM            (shipped path, unchanged) |
 |        |                                                                |
 |        |   QUEUE_SANITIZE_PROMPT=1 (board-sourced)                      |
 |        +-----> sanitize_cell, in this order:                            |
 |                  1 entity-decode      (&shy; -> a real codepoint)       |
 |                  2 invisible-strip    (ZWSP, bidi, Plane-14 tag chars)  |
 |                  3 ANSI-strip                                           |
 |                  4 control-strip      (newline -> space: ONE submission)|
 |                  5 comment-delete     (<!-- ... --> content DELETED)    |
 |                  6 fence-strip        (gh-aw's exemption, INVERTED)     |
 |                  7 pipe-escape        (a board row is a markdown table) |
 |                  8 url-policy         (https:// is the ONLY scheme)     |
 |                  9 size-cap           (truncate + a VISIBLE marker)     |
 |                 10 collapse + trim                                      |
 |                        |                                                |
 |                        v                                                |
 |                 xpia_preamble + the protected-path rule                 |
 |                 + BEGIN/END UNTRUSTED TASK TEXT fence                   |
 +-------------------------------------------------------------------------+
        |  ONE typed line
        v
   tmux send-keys -l --   ->   claude --dangerously-skip-permissions
                                        |
                                        |  the run does its work
                                        v
 +-------------------------------------------------------------------------+
 | THE WRITE SIDE  (detection, never prevention)                           |
 |                                                                         |
 |   _protected_touched: git diff <head-before>..HEAD  +  git status       |
 |        any path matching QUEUE_PROTECTED_GLOBS                          |
 |             .claude/*  CLAUDE.md  AGENTS.md  .github/*  _meta/BACKLOG.md|
 |                        |                                                |
 |                        v                                                |
 |        verdict := gated   (terminal: the watcher never re-plans it,     |
 |                            so the row stops and a human looks)          |
 +-------------------------------------------------------------------------+
```

## Design

### Approaches considered + chosen

Point at `## Solution`. The design view adds one tradeoff the solution view did not: the write side
is detection only, so its value is entirely in making a protected write TERMINAL rather than in
preventing it.

### Why the order is the contract

Each step closes a bypass the previous one leaves open. Stated as pairs, because a pair is what a
future editor has to preserve:

| This step | Must run before | Or else |
|---|---|---|
| 1 entity-decode | 2 invisible-strip | `&shy;` stays an entity, survives the strip, and renders as an invisible character later |
| 1 entity-decode | 7 pipe-escape | `&#124;` smuggles a raw pipe past the escape |
| 2 invisible-strip | 5 comment-delete | `<!-` + zero-width space + `-` never matches the comment pattern |
| 2 invisible-strip | 8 url-policy | `ht` + zero-width space + `tp://` never matches the scheme pattern |
| 3 ANSI-strip | 4 control-strip | the escape byte is deleted first and the rest of the sequence is left as visible junk |
| 5 comment-delete | 6 fence-strip, 7 pipe-escape | a pipe or a fence inside a deleted comment gets processed instead of vanishing |
| 9 size-cap | 10 trim | (the reverse) the truncation marker itself is trimmed away |

### The four transforms that differ from gh-aw

1. **Fenced code is NOT exempt: the exemption is inverted.** gh-aw excludes fenced regions from
   every transform, deliberately, to protect patch content. A goal prompt carries no patch, so the
   exemption would be a hole with nothing behind it. Here the fence delimiters are removed and the
   content stays in the pipeline like everything else. This closes the one blind spot gh-aw
   knowingly keeps.
2. **The pipe is escaped.** gh-aw has no equivalent because its outputs are not tables. This kit's
   board IS a markdown table, and a verdict reason built from this text can be written back into a
   row, where a bare pipe silently adds a column.
3. **The size cap is scaled to this content.** gh-aw caps at 0.5 MB. A board cell would suggest
   something near 500 characters, and that number would be wrong here: real pointer prompts in this
   repo run to about 4 KB and one notes file reaches 15 KB, so a cell-sized cap would truncate
   honest work every night. `QUEUE_MAX_PROMPT_CHARS` defaults to 20000, roughly five times the
   largest real pointer prompt, and truncation leaves a visible marker so it is never silent.
4. **Newlines are removed, not preserved.** gh-aw keeps them. Here the prompt is typed as ONE
   submission, so an embedded newline would submit the prompt early and leave the rest of the
   payload sitting on a fresh input line. That makes newline removal a security property, not
   formatting.

### Why perl

Steps 1, 2, and 8 address Unicode CODEPOINTS and need lookbehind. bash 3.2 (the macOS system shell
this repo targets, per SPEC-221's own constraint) plus BSD `sed` can do neither. A byte-level `tr`
version of the invisible-strip was written and is unreadable, which is a bad property for a
security function nobody will re-derive later. `perl` ships with macOS and every Linux this kit
runs on, the same tier as the `awk` and `realpath` the queue already depends on. The payload never
reaches perl as code: the program is a fixed `-e` string and the text arrives as a file argument or
on stdin.

If perl is missing, the pass FAILS CLOSED in two places: the row is skipped at preflight with a
named reason and no window opens, and `_goal_line` returns nonzero so a launch that somehow got
past preflight refuses to type rather than typing an empty or unsanitized prompt.

### The write side, and what it does not claim

The launched session runs with `--dangerously-skip-permissions`. Nothing in bash sits between it
and the filesystem, so a deny-glob cannot PREVENT a write. What it can do is notice one. After the
run, `_protected_touched` compares against the pre-launch HEAD and reads the dirty tree, and a
match rewrites the verdict to `gated`. `gated` is terminal in the watcher's dedup rule (SPEC-217
DEC-002), so the row stops being re-planned and a human sees it. The deny-glob is also stated in
the typed prompt, which is the only half that can influence the run before it acts.

`hooks/*` is deliberately NOT in the default set. This repo's own autonomous rows legitimately edit
hooks, and gating every one of them would train the operator to click past the signal.

### ADR link(s)

No new ADR. Every decision here is reversible: drop `--sanitize-prompt` and the path is exactly
what shipped. The transforms, the cap, and the glob set are all environment variables.

### Boundaries & failure modes

See `## Failure modes`. The pass never edits a board, never blocks a running session, and never
rejects input (it truncates).

## Technical Design

### Interfaces (I/O contract)

- **Inputs**: the pointer file body (untrusted on the board-sourced path); `QUEUE_PROTECTED_GLOBS`,
  `QUEUE_MAX_PROMPT_CHARS`, `QUEUE_PERL_CMD` as operator config.
- **Outputs**: `sanitize_cell` prints ONE sanitized line on stdout, or nothing with exit 1;
  `xpia_preamble` prints the framing; `protected_path_reason` prints a reason or nothing; the
  journal keeps its four-column shape and its existing verdict vocabulary.
- **Invariants**:
  - with `QUEUE_SANITIZE_PROMPT=0` the typed line is byte-identical to what shipped
  - the sanitized output contains no newline, so the prompt is always exactly one submission
  - a sanitizer that cannot run never degrades into an unsanitized prompt
  - no new journal verdict is introduced; a protected write reuses `gated`

### Data model changes

None. No new file, directory, or ledger.

### Infrastructure changes

None. No daemon, no scheduled job. One runtime dependency (`perl`) that is already present on every
supported host, with a fail-closed path when it is not.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-001: `lib/queue/sanitize.sh` with `sanitize_cell`, `xpia_preamble`,
  `protected_path_reason`. AC: each transform is observable on a real payload; clean prose round
  trips unchanged.

### Phase 2: Core
- [x] TASK-002: `--sanitize-prompt` on `queue.sh run` (implied by `--from-boards`), consumed by
  `_goal_line`, with the preamble and the begin/end fence. AC: with the flag no payload reaches the
  typed line; without it the line is unchanged.
- [x] TASK-003: fail-closed preflight plus the launch-time guard. AC: with no sanitizer the row is
  journaled `skipped` and no window opens.
- [x] TASK-004: `_protected_touched` and the verdict rewrite. AC: a run that writes `CLAUDE.md` on
  the untrusted path ends `gated` naming the path; an ordinary write does not.
- [x] TASK-005: `watch-board.sh --apply` forwards the flag. AC: asserted in the test.

### Phase 3: Polish
- [x] TASK-006: `tests/test-notes-sanitization.sh`, real injection fixtures, one negative control
  per section. AC: green from a clean state.

## After state

- [ ] A board-selected pointer body reaches the model with HTML comments deleted, invisible
  characters stripped, fences removed, pipes escaped, and non-https URLs redacted. (Today: verbatim.)
- [ ] The typed prompt on that path opens with an untrusted-content preamble and fences the
  untrusted region. (Today: no framing at all.)
- [ ] An autonomous run that writes `CLAUDE.md`, `.claude/`, `AGENTS.md`, `.github/`, or the board
  ends `gated` instead of shipping. (Today: nothing notices.)
- [ ] A host without the sanitizer skips the row instead of launching it unsanitized. (Today: no
  such concept.)
- [ ] The operator-authored path is byte-identical to what shipped, asserted by a test. (Today:
  the same, and it must stay that way.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Every section carries a negative control: honest input is not mangled, the trusted path is not touched
- [ ] No regressions: `bash tests/test-runaway-guards.sh`, `bash tests/test-self-grill-watcher.sh`

## Verification

- `bash tests/test-notes-sanitization.sh` (exit 0 = all checks green).
- `bash tests/test-runaway-guards.sh` and `bash tests/test-self-grill-watcher.sh` stay green: the
  shipped queue and watcher behavior is unchanged when the flag is off.
- `bats tests/test-queue.bats` shows no NEW failures versus `origin/master` (three cases, 9 / 13 /
  14, fail identically on both; they are pre-existing and unrelated).
- `bash lib/queue/watch-board.sh` over this repo's real board still prints an empty plan and exits
  0 (the real board carries no `#auto` rows).
- Live revert-to-RED on two mechanisms, recorded in `docs/verification/`: remove the comment-delete
  step and watch A3 go RED; remove the pipe-escape step and watch A6 go RED; restore both, watch
  them go GREEN.

## Test plan

| Case | Tier | Why |
|---|---|---|
| clean prose round trips byte-identical (NEGATIVE CONTROL) | script | a sanitizer that mangles honest text breaks the loop it defends |
| a zero-width space inside `<!-` cannot hide a comment | script | the ordering rule between steps 2 and 5 |
| a soft hyphen inside a word is removed | script | entity-decode feeding invisible-strip |
| an HTML comment's body is deleted, not escaped | script | the primary payload class |
| a nested comment leaves no delimiter behind | script | the form that defeats one non-greedy match |
| a comment inside a fenced block is still deleted | script | the inverted exemption, the whole point of step 6 |
| every pipe is escaped | script | markdown-table safety on the writeback path |
| an entity-encoded pipe cannot smuggle a raw one | script | the ordering rule between steps 1 and 7 |
| plain, javascript, percent-encoded, and protocol-relative URLs are all redacted | script | the single-scheme allow-list |
| an `https://` URL survives (NEGATIVE CONTROL) | script | the allow-list allows something |
| ANSI escapes stripped; newline and tab become spaces | script | one submission is a security property here |
| an oversize payload truncates with a VISIBLE marker | script | truncate-never-reject, never silent |
| the default cap does not truncate a realistic prompt (NEGATIVE CONTROL) | script | the cap is scaled to real content |
| no payload reaches the typed `/goal` line, and the preamble does | script | the integration, end to end through the stub mux |
| without the flag the typed line is verbatim (NEGATIVE CONTROL) | script | the trust boundary did not move |
| `watch-board.sh --apply` forwards the flag | script | otherwise the whole feature is dead code |
| `--from-boards` implies the flag | script | a board emit is untrusted for the same reason |
| a run writing `CLAUDE.md` ends `gated` naming the path | script | the write-side gate |
| an ordinary write is not gated (NEGATIVE CONTROL) | script | the gate is not a blanket |
| the same protected write on the trusted path is not gated (NEGATIVE CONTROL) | script | scoped to untrusted runs |
| a custom `QUEUE_PROTECTED_GLOBS` gates too | script | operator config, not a hardcoded list |
| no sanitizer means the row is skipped and no window opens | script | fail closed |
| with the sanitizer present the same row runs to done (NEGATIVE CONTROL) | script | fail-closed did not become fail-always |
| whether a real model obeys the XPIA preamble | NOT TESTED | it is a prompt, not code; the structural transforms are what this spec can assert |
| whether the transform set is COMPLETE against a novel payload | NOT TESTED | no test proves the absence of an unknown bypass; the honest claim is a bounded, ordered set |

## Edge Cases

1. A pointer body that is entirely a comment: the sanitized text is empty, the preamble and fence
   still frame it, and the run gets an empty task. It stalls and reaches a human through the
   shipped SPEC-221 ladder rather than acting on a payload.
2. An unbalanced nested comment: the inner text can remain as PLAIN VISIBLE prose. That is the safe
   direction. The threat is a hidden instruction channel, and visible sanitized text is not one.
3. A legitimate plain-scheme link in an honest prompt (a local dev URL): redacted, with the host
   kept in the marker. Accepted cost of an allow-list of one; the operator sees what was dropped.
4. A rename in `git status --porcelain` prints `old -> new`, which simply fails to match a glob
   rather than matching the wrong path. It can miss a rename INTO a protected path; the diff leg
   catches that case whenever the run committed.
5. The pointer file is unreadable at launch: `sanitize_cell` yields empty output, the prompt is
   preamble-only, and the run stalls into the shipped ladder. It never types a raw path or an error.
6. Two transforms disagree about a payload (a pipe inside a comment): step 5 runs first, the whole
   comment is gone, and step 7 never sees it. This is why the order is the contract.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A hidden instruction reaches the model | a run does something the row never asked for | the ordered pipeline deletes the known hidden channels; the preamble frames the rest as data |
| A payload splits the prompt into two submissions | the pane shows a second prompt line | every whitespace control becomes a space, so the sanitized text cannot contain a newline |
| The sanitizer mangles an honest prompt | a row that used to work now fails or truncates | the negative controls assert byte-identical clean text; the cap is five times the largest real pointer and its truncation is visible |
| The sanitizer silently does not run | an unsanitized prompt on the untrusted path | fail closed in two places: preflight skip with a named reason, and a launch-time refusal |
| An autonomous run rewrites the rules it runs under | a diff touching `CLAUDE.md` / `.claude/` / `.github/` / the board | detected after the run and forced to `gated`, which is terminal; NOT prevented, and never claimed to be |
| A novel bypass nobody enumerated | nothing; that is the point | NOT DEFENDED. This is a bounded ordered transform set, not a proof. The structural answer is the deferred safe-outputs separation below |
| A run edits a protected path, commits, then rewinds HEAD | neither leg sees it | NOT DEFENDED, named honestly (security review, HIGH). Both legs read end state, not history. Severity is bounded by the fact that rewinding also reverts the tracked write; what survives a rewind is a write that was never tracked |
| A run writes a GITIGNORED protected path (`.claude/settings.local.json`) | neither leg sees it | NOT DEFENDED. Both legs read git's view, and git does not report an ignored file. Closing it means `--ignored`, which reports every pre-existing ignored file too and would fire on rows that wrote nothing |
| A run writes OUTSIDE the repo (`~/.ssh`, another repo, `/etc`) | nothing here | NOT DEFENDED and out of scope by construction (security review, MEDIUM). The check reads one repo's git state. This is the largest residual surface after this change, and the deferred safe-outputs separation is what actually addresses it |
| The operator path regresses | the trusted tsv starts behaving differently | asserted by two negative controls; the flag defaults off |

## Out of Scope

- **Homoglyph mapping (Unicode TR#39 confusables).** Scoped out, DEC-004. A Cyrillic lookalike does
  not create a hidden channel here; it only misspells a word a human already reads. gh-aw needs it
  because it feeds a secret-leak detector; this path has no such consumer.
- **The domain allow-list.** gh-aw's third URL stage limits hosts to GitHub's own. The scheme
  allow-list is the load-bearing half; a domain list needs an egress consumer this path does not have.
- **Mention and GitHub-reference neutralization, bot-trigger rate limiting, template-delimiter
  escaping.** These defend GitHub's own rendering and notification surfaces. This text is typed into
  a local TUI and never posted.
- **min-integrity author trust.** There is no author association offline. The transferable idea, the
  operator-set `#auto` marker as the promotion label, already ships in SPEC-217.
- **The read-only agent, NDJSON safe-outputs, and the model-judge threat-detection job.** DEFERRED,
  not rejected: it is the correct end state and it is an architecture change to the whole loop.
  **Tripwire, either one is enough to make it real work:** (a) a second person can edit a board this
  loop watches, or (b) the loop ingests text the operator did not author (an issue body, a PR
  comment, an email). File it as its own board row when either fires.
- **Preventing a protected write.** Impossible while the session holds
  `--dangerously-skip-permissions`. Detection plus a terminal verdict is what this spec claims.

## Decision Log

- DEC-001: the sanitized surface is the POINTER BODY, not the Notes cell the row names. Rationale:
  reading the code, `parse-board.sh` already reduces the row to a charset-gated token, so the cell's
  prose never reaches a model, while the pointer body is typed verbatim into the session. Rejected:
  sanitizing the cell as written on the row, which would have shipped a transform over a string
  nothing consumes and left the real surface open.
- DEC-002: the pass is scoped to the board-sourced path, not applied everywhere. Rationale: SPEC-148
  already fixed the trust boundary at operator authorship, and the pointer allow-list sits on that
  same line. Rejected: sanitizing unconditionally, which would strip fences and escape pipes in
  hand-authored prompts an operator deliberately wrote that way, breaking working rows to defend a
  path that has no attacker.
- DEC-003: the fenced-code exemption is INVERTED rather than ported. Rationale: gh-aw exempts fences
  to keep patch content intact, and a goal prompt has no patch. Keeping the exemption would import
  their one deliberate blind spot with none of the reason for it.
- DEC-004: homoglyph mapping is not ported. Rationale: it defends a downstream secret-leak detector
  that does not exist here; on this path a confusable character misspells a word rather than opening
  a channel. Cost of being wrong is low and the mapping is large; revisit if a detector lands.
- DEC-005: `hooks/*` is not in the default protected set. Rationale: this repo's own autonomous rows
  legitimately edit hooks, and a gate that fires on routine work teaches the operator to ignore it.
  A consumer that wants it says so through `QUEUE_PROTECTED_GLOBS`.
- DEC-006: perl, not bash plus sed. Rationale: three of the ten steps need codepoint classes and
  lookbehind, which bash 3.2 and BSD sed cannot express; the byte-level alternative was written and
  is unauditable. Cost, accepted: one runtime dependency, mitigated by failing closed when absent.
- DEC-007: the write side is detection, not prevention, and says so. Rationale: the session holds
  `--dangerously-skip-permissions`, so a prevention claim would be false. Rejected: dropping the
  check for being unenforceable, which would leave a rules-rewriting run indistinguishable from a
  successful one.
- DEC-008: the size cap is 20000 characters, not gh-aw's 524288 and not a board-cell 500. Rationale:
  derived from this repo's real pointer files (about 4 KB typical, 15 KB largest), so the cap sits
  roughly five times above real content and still bounds a hostile file.

- DEC-009: `_protected_touched` reads two git surfaces (the diff since the pre-launch HEAD, and the
  dirty tree) and accepts one known gap: a RENAME into a protected path prints as `old -> new` in
  `git status --porcelain`, which matches no glob, so an uncommitted rename slips through. The diff
  leg catches it once the run commits. Rejected: parsing rename syntax, which adds a second parser
  for a case the committed path already covers. Named here rather than left in a code comment
  (architecture review, LOW).

- DEC-010: invisible characters are stripped by Unicode PROPERTY, not by an enumerated range list.
  Rationale: the first implementation used a list, and the security review broke it in one line with
  U+034F (combining grapheme joiner), which is not a format character, sits in no obvious range, and
  renders at zero width everywhere; `<!` + CGJ + `--` then read as a comment to a human and to a
  model while matching no comment pattern. `\p{Cf}` plus `\p{Default_Ignorable_Code_Point}` is a
  class, so a codepoint nobody thought of is covered by construction. Accepted cost: an emoji
  zero-width-joiner sequence is split into its parts. Rejected: extending the list, which would have
  been the same defect one codepoint later.

## Open questions

(none)
