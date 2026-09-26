# SPEC-328: ship-gate engages on a real ship, never on text that quotes one

**Status:** DRAFT, revision 2 (bash-only design, pending re-validation)
Lane: full
Type: spec-bugfix
**Proof:** `docs/verification/gate-quoted-text.md`; `tests/test-hooks.sh`, the ship-gate engage block.

## Problem

`hooks/ship-gate.sh` decides whether a Bash call ships with one regex over the whole command string (line 36): `git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create`. Heredoc bodies are stripped first, and nothing else about the command's structure is read. The logged false positive: a `git commit -F <file>` whose message file a `printf` in the same call had written. The `printf` argument quoted a PR-create command. The gate engaged, found an incomplete ledger, and blocked a plain commit.

A PR-create call with `--dry-run` also engaged. That is correct and stays: gh's own help says the flag "May still push git changes".

The whole-string design also has fail-open holes beside the false positive:

| Hole | Today |
|---|---|
| Line 38 skips the gate when `\b(main\|master)\b` or `--force` appears ANYWHERE in the command. The common ship line `<push> && <PR-create> --base main` never engages. A commit message that says `main` switches the gate off for a push in the same call. | fail open |
| That regex matches `--force-with-lease`, which `safety-gate.sh` deliberately allows. `git push --force-with-lease origin feat/x` escapes BOTH gates. | fail open |
| `\bmain\b` matches inside `feat/main-fix`, so a push of that branch escapes both gates too. | fail open |
| `git -C <dir> push` and `git -c k=v push` put words between `git` and `push`. The adjacency regex misses them. | fail open |
| `gh pr new` is gh's alias of PR create. The regex misses it. | fail open |
| A heredoc body is stripped whatever consumes it, so `bash <<EOF` with a push in the body never engages. | fail open |
| A backslash-newline between `git` and `push` breaks the adjacency. | fail open |

The kit memory note `guards-read-commands-not-behaviour` names the root: a guard that reads the command string sees words, not behaviour. The fix must read enough structure to exonerate quoted text, and it must FAIL SAFE: whatever the hook cannot prove inert engages the gate. A missed gate costs more than a false positive.

## Contract

The engage decision is an allowlist proof. The hook passes a command through only when it can prove every part of it is inert text. Anything else falls back to a widened regex over the full text and engages as today. All of it stays in bash plus one awk program inside `hooks/ship-gate.sh`. No Python.

**Step 1: prefilter.** Build the flattened text: join backslash-newline continuations, delete every `"`, `'` and `\`, turn newlines into spaces. Heredoc bodies stay in. If the flattened text does not match the ship regex below, exit 0 (not a ship).

Ship regex (ERE): `git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+(create|new)`. It allows git's global options between `git` and `push` (`-C <dir>`, `-c k=v`, `--no-pager`).

**Step 2: the inert proof (awk character walk).** The walk reads the raw command once. It tracks single quotes, double quotes, and backslash escapes the way bash does, so a separator inside quotes or after a backslash never splits. It splits segments at unquoted `;`, `&`, `&&`, `|`, `||`, `|&`, newlines, `(` and `)`. It reads `>`, `>>`, `>|`, `&>`, `<`, and `N>&M` as redirects, never as separators. The proof FAILS (the walk prints `CODE`) on any of:

- an unterminated quote or heredoc delimiter;
- `$(` anywhere outside single quotes, except the special case below;
- a backtick anywhere outside single quotes;
- `<(` or `>(` outside quotes;
- a heredoc whose delimiter is unquoted and whose body contains `$(` or a backtick;
- a second heredoc on one line;
- any segment that is not a DATA segment.

The proof PASSES (the walk prints `DATA`, the hook exits 0) only when none of those hold.

**DATA segments.** The first word decides. A segment is DATA only when it has no leading `NAME=value` assignment (an env prefix such as `GIT_EDITOR=` or `GIT_SSH_COMMAND=` can run code), and its first word is one of:

| First word | Condition |
|---|---|
| `echo`, `cat`, `grep`, `egrep`, `fgrep`, `cd` | none |
| `printf` | no argument starting `-v` |
| `rg` | no `--pre` or `--pre=...` argument |
| `git` | the next word is `commit`, `tag`, `log`, or `add`, or it is `-C <dir>` followed by one of those. Any other global option (`-c k=v`, `--exec-path`, `--no-pager`) fails the proof. |

A DATA segment's arguments, redirect targets and heredoc body are never read for ship words.

**Special case: the commit-message idiom.** `$(cat <<'X'` + newline + body + a line that is exactly `X` + optional whitespace + `)` counts as inert word text. The delimiter must be quoted (`'X'` or `"X"`), so bash does not expand the body; `<<-` strips leading tabs before comparing the delimiter line. Any other `$(` fails the proof. Where the substitution sits in a DATA segment (`git commit -m "$(cat <<'EOF' ... EOF)"`), the segment stays DATA.

**Step 3: the safety-gate skip.** When the proof fails, the hook checks one narrow skip before it engages. `hooks/safety-gate.sh` already blocks a plain push to main and a force push. The skip applies only when ALL of these hold:

- the command contains no `<<`, `$(`, backtick, `<(` or `>(`, and no unterminated quote, so both hooks split it the same way;
- at least one segment starts with the words `git push` (no assignment, no wrapper, no global option);
- every such segment carries one of the exact tokens `safety-gate.sh` blocks on: `--force`, `-f`, a word starting `+`, `main`, `master`, `*:main`, `*:master`;
- the text of every other segment does not match the ship regex.

Otherwise the hook engages. `--force-with-lease`, `--force-if-includes`, and `feat/main-fix` are not skip tokens, so those pushes engage the ship-gate. A PR-create segment never takes the skip.

**Dry runs stay gated.** `--dry-run` exempts nothing, for both ship shapes. The PR-create dry run may push, per gh's help. A push dry run precedes a real push that faces the same gate, and a flag parser for `-n`, `--dry-run`, and bundled short flags is new surface for no saving.

**Unchanged.** The leading-`cd` repo resolution keeps reading `CMD_CODE`. Everything after the engage decision (proof gate, board advisory, doc-projection, registry freshness, lane gates) is untouched.

## Picture

```
 PreToolUse(Bash) --> hooks/ship-gate.sh
                           |
                           v
     flatten (join \<nl>, drop quotes and backslashes, bodies kept)
                           |
                           v
            ship regex matches? --no--> exit 0
                           |
                          yes
                           v
            awk inert walk over the raw command
                           |
             DATA ---------+---------- CODE
               |                        |
               v                        v
            exit 0          safety-gate skip applies? --yes--> exit 0
                                        |
                                        no
                                        v
                        engage: cd resolution, proof gate,
                        lane gates (unchanged)
```

## Design

Design-bearing: the engage decision of a hard gate moves from a regex to a structural proof, with a fail-safe fallback.

The awk walk, one character at a time:

```
            +---------+  '   +---------+
    +-----> |  PLAIN  | ---> | SQUOTE  | -- ' --> PLAIN   (everything literal)
    |       +---------+      +---------+
    |        |  |  |  \
    |        |  |  |   +-- \x : x is literal, skip it
    |        |  |  +------ " --> DQUOTE: \x literal, $( or ` = check, " ends
    |        |  +--------- ;  &  |  (  )  newline --> end segment
    |        |                (newline also reads a pending heredoc body)
    |        +------------ $(  `  <(  >(  --> CODE (unless the cat <<'X' idiom)
    |
    +-- end segment: classify first word --> not DATA --> CODE
```

Chosen approach: an inert-proof allowlist in one awk program inside the hook. It keeps the kit's rule that hooks are bash plus jq (`docs/PHILOSOPHY.md`, "All 9 hooks are bash scripts... No Python"). The allowlist direction is what makes it fail safe: the walk never has to understand code, only to prove that a command is made of inert commands. Anything it does not recognise (`sudo`, `xargs`, `bash -c`, `ssh`, `eval`, an alias, a function) takes the old regex path.

Approaches considered:

| Approach | Why not |
|---|---|
| Python recursive-descent parser as a hook companion (revision 1) | `docs/PHILOSOPHY.md` rejects Python in hooks: a runtime dependency, slower start, harder debugging. It also judged CODE segments by their own words, which made the pass decision depend on parser completeness. |
| `sed` quote-stripping, then today's regex | Naive quote handling fails open: in `echo \" ; <push> ; echo \"` the escaped quotes pair up as one quoted span and hide the push. |
| Unwrap quotes and key on each segment's binary, as `safety-gate.sh` does | That normalizer splits on `;` and `\|` inside quotes and knows no substitutions. It suits a blocklist of verbs, not a proof that text is inert. |
| A denylist of code-running wrappers whose quoted args get scanned | The set of interpreters is open-ended. An unlisted one fails open. |
| Gate on the body of a script the command runs (`bash push.sh`) | The kit's own test files quote ship commands, so every test run would engage the gate. The hole predates this spec; After state records it. |

The DATA allowlist is short on purpose. Each entry must never execute its arguments. `echo`, `printf`, and `cat` print. The grep family matches. `cd` changes directory. `git commit/tag/log/add` store or read text. The per-command options that do run code (`printf -v` assigns, `rg --pre` runs a program, `git -c` sets `core.editor` or an alias) fail the proof. `tee`, `sed` (`e` command), `awk` (`system()`), `jq`, `head`, `tail`, and `git grep` (`-O` opens a pager command) stay out. A false positive on those shapes is accepted. `cd` and `git add` go past the lead's list because `cd <repo> && git add -A && git commit -m "..."` is the dominant commit idiom, and neither runs its arguments.

`ship-gate.sh`'s header says the hook "FAILS OPEN on any ambiguity". This spec splits that claim: the engage decision fails SAFE (ambiguity engages), and the checks after engagement still fail open on missing tooling, repo, spec or lane. The header comment is rewritten to say both.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| `echo \" ; <push> ; echo \"` | backslash escapes tracked | the middle segment is `git`, not DATA: engages |
| `printf '<push>' >\| x && sh -c "$(cat x)"` | `$(` outside the idiom; `sh` not DATA | engages |
| `echo '<push>' > >(bash)` | `>(` | engages |
| `printf '<push>' \| bash` | `bash` not DATA | engages |
| `X="<push>"; $X` | assignment segment not DATA | engages |
| `printf -v X '<push>'; eval "$X"` | `printf -v`; `eval` not DATA | engages |
| `echo "$(<push>)"`, `` echo `<push>` `` | substitution | engages |
| `cat <<EOF` body holding `$(<push>)` | unquoted delimiter, expanding body | engages |
| `bash <<EOF` with the push in the body | `bash` not DATA; body kept in the flattened text | engages (closes today's hole) |
| `git -c core.editor='<push>' commit` | `git -c` fails the proof | engages |
| `git grep -O'<push>' x` | `git grep` not DATA | engages |
| `rg --pre ./x "<push>"` | `rg --pre` | engages |
| `git \<newline> push` | continuation joined before the regex | engages (closes today's hole) |
| `git -C dir push`, `gh pr new` | widened ship regex | engages (closes today's holes) |
| `--force-with-lease`, `feat/main-fix`, `main` in a commit message beside a push | exact-token skip on plain push segments only | engages (closes today's holes) |
| `echo "<<X"; <push> origin main` | skip refused when the command contains `<<` | engages: `safety-gate.sh` strips from a quoted `<<`, so it may not see that push |
| unterminated quote or heredoc | walk end state | CODE, engages |
| A script already on disk, an alias or function from earlier in the session, a push through `gh api`, a ref in a variable | none | not covered; unchanged from today |
| zsh-only constructs (`=(...)`, glob qualifiers) | none | out of scope: Claude Code runs Bash calls under bash semantics; a zsh construct reaching the walk parses as plain words, and the regex path still sees ship words |
| False positive: `gh issue create --body "<push>"`, `python3 -c` printing ship words, a `sed`/`awk`/`jq` script quoting them, `git log \| head` beside quoted ship words | not DATA | accepted: fail safe, same as today |
| Walk cost | prefilter first | awk runs only when the ship regex matches |

Threat model: an agent writing a command that happens to quote ship words, and an agent that routes a real ship through a wrapper. A deliberate adversary with a script file already beats every string-reading guard; that is recorded, not solved.

## Task Breakdown

Two build commits, so the behaviour change reviews and reverts on its own.

| Task | Commit | Files | Acceptance |
|---|---|---|---|
| T1: inert proof | A (false-positive fix) | `hooks/ship-gate.sh`, `tests/test-hooks.sh` | the awk walk and DATA allowlist run before today's line 36 and 38 logic; a DATA verdict exits 0; a CODE verdict falls through to today's logic unchanged. TP18 to TP27 pass; TP1 to TP4, TP10 to TP17 still engage |
| T2: hole closures | B (behaviour change) | `hooks/ship-gate.sh`, `tests/test-hooks.sh` | flattened text with bodies and joined continuations; widened ship regex; line 38 replaced by the exact-token skip; header comment rewritten. TP5 to TP9, TP28 to TP32 engage; TP33 passes |
| T3: records | with B | `docs/CHANGELOG.md`, `docs/implementation-notes/gate-quoted-text.md`, `docs/verification/gate-quoted-text.md`, `docs/FEATURES.md` (regenerated last) | CHANGELOG names the behaviour change: a PR create with `--base main`, a `--force-with-lease` push, and a `feat/main-fix` push now engage |

## Test plan

Every row runs through the real hook against a fixture repo whose `Lane: full` spec has an empty ledger. Engaged = exit 2 naming `MISSING-GATE`. Passed = exit 0. `<push>` and `<pr-create>` stand for the real command words in the test file.

| # | Command shape | Expected | Commit |
|---|---|---|---|
| TP1 | `<push> origin feat/x` | engaged | A |
| TP2 | `cd <repo> && <push> -u origin feat/x` | engaged | A |
| TP3 | `git add -A && git commit -m x && <push>` | engaged | A |
| TP4 | `GIT_EDITOR=true <push>` and `env FOO=1 <push>` | engaged | A |
| TP5 | `git -C <repo> push` | engaged | B |
| TP6 | `<pr-create> --fill` and `gh pr new --fill` | engaged | A / B |
| TP7 | `<pr-create> --dry-run` | engaged | A |
| TP8 | `<push> origin feat/x && <pr-create> --base main` | engaged | B |
| TP9 | `git commit -m "note main" && <push> origin feat/x` | engaged | B |
| TP10 | `bash -c "<push>"`, `sudo <push>`, `ssh h '<push>'` | engaged | A |
| TP11 | `bash <<EOF` with `<push>` in the body | engaged | B |
| TP12 | `printf '<push>\n' \| bash` | engaged | A |
| TP13 | `printf '<push>' >\| x.sh && bash x.sh` | engaged | A |
| TP14 | `X="<push>"; $X` and `printf -v X '<push>'; eval "$X"` | engaged | A |
| TP15 | `echo "$(<push>)"` and `` echo `<push>` `` | engaged | A |
| TP16 | `cat <<EOF` body holding `$(<push>)` | engaged | A |
| TP17 | `<push> origin "feat/x` (unterminated quote) | engaged | A |
| TP18 | the incident: `printf '%s\n' "fix: x" "<pr-create> --fill" >\| m && git commit -F m` | passed | A |
| TP19 | `git commit -m "docs: then <push> and <pr-create>"` | passed | A |
| TP20 | `git commit -m "$(cat <<'EOF'` + body naming `<pr-create>` with an apostrophe and a `$(` + `EOF` + `)"` | passed | A |
| TP21 | `echo "<push>"` and `echo "a; <push>"` | passed | A |
| TP22 | `cat <<'EOF' >\| notes.md` with `<push>` in the body | passed | A |
| TP23 | `grep -rn '<push>' docs/` and `rg "<pr-create>"` | passed | A |
| TP24 | `echo "<push>" \| grep push` | passed | A |
| TP25 | `cd <repo> && git add -A && git commit -m "<push> later"` | passed | A |
| TP26 | `echo \" ; <push> ; echo \"` | engaged | A |
| TP27 | existing ship-gate tests (F4 `cd` resolution, sg-demo, ID-062, ID-063, descent) | unchanged | A, B |
| TP28 | `<push> --force-with-lease origin feat/x` and `<push> origin feat/main-fix` | engaged | B |
| TP29 | `printf '<push>' >\| x && sh -c "$(cat x)"` | engaged | A |
| TP30 | `echo '<push>' > >(bash)` | engaged | A |
| TP31 | `git -c core.editor='<push>' commit`, `git grep -O'<push>' x`, `rg --pre ./x "<push>"` | engaged | A |
| TP32 | `git \<newline> push origin feat/x` | engaged | B |
| TP33 | `<push> origin main`, `<push> --force origin feat/x`, `<push> origin +feat/x`, `<push> origin HEAD:master` | passed (safety-gate territory) | B |

Negative controls, both through `lib/gate/negctl.sh`:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | empty the DATA allowlist (every segment reads CODE) | TP18 to TP25 |
| NC2 | disable the substitution check (`$(`, backtick, `<(`, `>(`, expanding heredoc body no longer fail the proof) | TP15, TP16, TP30 |

## Verification

`bash tests/test-hooks.sh` exits 0 after commit A and again after commit B. `bash tests/run-all.sh --changed` exits 0. NC1 and NC2 report PASS.

## After state

A commit, echo, printf, cat heredoc, or grep that quotes ship words passes through. A real push or PR create engages, including shapes today's regex missed: `git -C`, `gh pr new`, `bash <<EOF`, a backslash-newline split, a push beside a commit message that says `main`, a `--force-with-lease` push, a `feat/main-fix` push, and a PR create with `--base main`. Anything the walk cannot prove inert takes the regex path.

Not covered, unchanged from today: a script file already on disk (`bash push.sh`), a shell alias or function from earlier in the session, a push through `gh api`, and a ref hidden in a variable. Out of scope: zsh-only constructs (`=(...)`, glob qualifiers); the hook reads commands as bash.

Behaviour change to flag at review (commit B): a PR create with `--base main`, a `--force-with-lease` push, and a `feat/main-fix` push engage for the first time. In an adopted repo with an incomplete ledger, those calls now block. That is the gate's stated purpose; today's skip was the bug.

## Decision Log

- Revision 2 replaces the Python parser with a bash-only inert proof, per validation (three criticals) and the lead's call. `docs/PHILOSOPHY.md` rules out Python in hooks.
- PASS needs a proof; everything else engages. The walk never has to understand code, only recognise inert commands.
- The DATA allowlist is short and each entry must show it never runs its arguments. `cd` and `git add` extend the lead's list for the dominant commit idiom.
- The one `$(` allowed is `cat <<'X'` with a quoted delimiter, the commit-message idiom.
- The safety-gate skip matches `safety-gate.sh`'s exact push tokens on plain `git push` segments, and refuses whenever the two hooks could split the command differently (`<<`, substitutions, unterminated quotes).
- `--dry-run` stays gated for both ship shapes.
- Two build commits: the false-positive fix (A) and the hole closures (B), so the behaviour change reviews and reverts alone.
- Script-body inspection stays out of scope: reading test files that quote ship commands would engage the gate on every test run.
