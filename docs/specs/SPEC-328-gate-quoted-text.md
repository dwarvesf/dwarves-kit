# SPEC-328: ship-gate engages on a real ship, never on text that quotes one

**Status:** DRAFT (pending validation)
Lane: full
Type: spec-bugfix
**Proof:** `docs/verification/gate-quoted-text.md`; `tests/test-hooks.sh`, the ship-gate engage block.

## Problem

`hooks/ship-gate.sh` decides whether a Bash call ships by one regex over the whole command string (line 36): `git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create`. It strips heredoc bodies first and reads nothing else about the command's shape. Two logged false positives followed:

1. A `git commit -F <file>` whose message file was written by a `printf` in the same call. The `printf` argument quoted a PR-create command. The gate engaged, found an incomplete ledger, and blocked a plain commit.
2. A PR-create call carrying `--dry-run`.

The same whole-string design has fail-open holes next to the false positives:

| Hole | Today |
|---|---|
| Line 38 skips the gate when `main`, `master`, or `--force` appears ANYWHERE in the command. The common ship line `<push> && <PR-create> --base main` therefore never engages. A commit message that mentions `main` also switches the gate off for a push in the same call. | fail open |
| `git -C <dir> push` and `git -c k=v push` put a word between `git` and `push`. The adjacency regex misses them. | fail open |
| `gh pr new` is gh's alias of `gh pr create`. The regex misses it. | fail open |
| A heredoc body is stripped whatever consumes it, so `bash <<EOF` with a push in the body never engages. | fail open |

The kit's memory note `guards-read-commands-not-behaviour` records the root: a guard that reads the command string sees words, not behaviour. The fix must read the command's structure, and it must FAIL SAFE: when the parser is unsure, the gate engages. A missed gate costs more than a false positive.

## Contract

A new companion parser `hooks/ship-gate-detect.py` (stdlib python3 only, installed beside the hook like `citation-guard.py`) reads the Bash command on stdin and exits:

| Exit | Meaning | Hook action |
|---|---|---|
| 0 | the command contains no ship action the gate owns | pass through (exit 0) |
| 10 | the command ships | engage the gate |
| any other (parse error, crash, python3 missing, file missing) | unknown | engage the gate |

Only an explicit exit 0 lets a command through. A Python traceback exits 1, a missing interpreter exits 127: both engage.

`hooks/ship-gate.sh` changes:

- A cheap prefilter stays in bash: the command, with newlines flattened to spaces, must match `git.*push|gh.*pr.*(create|new)`. No match exits 0 without spawning python. The prefilter is looser than today's regex, so it never drops a command today's gate engages on.
- The parser replaces line 36 (the engage regex) and line 38 (the main/master/force skip). Heredoc stripping (`CMD_CODE`) stays only as the input of the existing leading-`cd` resolution, unchanged.

Parser semantics:

1. **Segments.** The parser splits the command into simple-command segments at unquoted `;`, `&`, `&&`, `|`, `||`, `|&`, newlines, `(` and `)`. It honours single quotes, double quotes, and backslash escapes the way bash does, so a separator inside quotes never splits.
2. **Substitutions execute.** `$(...)`, backticks, `<(...)` and `>(...)` parse recursively as full commands, in unquoted and double-quoted text alike. Their segments are judged on their own, whatever surrounds them.
3. **Heredocs.** `<<` and `<<-` attach the body to the segment that opened it. A here-string `<<<` is an ordinary argument word.
4. **Data segments.** A segment is DATA when its first word after `NAME=value` assignments is one of `echo`, `printf`, `cat`, `grep`, `egrep`, `fgrep`, `rg`, or `git` whose subcommand (the first word after git's own options, skipping the values of `-C` and `-c`) is `commit`, `tag`, `log`, or `grep`. A DATA segment's arguments and heredoc body never engage the gate. Every other segment is CODE.
5. **Demotion to CODE (fail safe).** A DATA segment is judged as CODE when any of these holds:
   - a later stage of its pipeline is CODE (`printf ... | bash`);
   - it writes a redirect target (`>`, `>>`, `>|`, `&>`) whose basename appears as a word in any CODE segment of the command (`printf ... >| x.sh && bash x.sh`);
   - it is `printf -v` (an assignment in disguise);
   - its heredoc delimiter is unquoted and the body contains `$(` or a backtick (the body expands).
6. **Assignments.** The value of every `NAME=value` word is scanned as CODE text (`X="<ship words>"; $X`).
7. **Ship test on a CODE segment.** Join the segment's words (quoted words keep their inner text) and its heredoc body with spaces. The segment ships when either holds:
   - word-level: a word whose basename is `git` is followed later by the word `push`; or a word whose basename is `gh` is followed by `pr`, then `create` or `new`;
   - text-level: the joined text matches `git[[:space:]]+push` or `gh[[:space:]]+pr[[:space:]]+(create|new)` (catches `bash -c "<ship words>"`, `ssh host '<ship words>'`).
8. **Safety-gate territory.** A shipping segment whose only match is a push, and whose own joined text matches today's `\b(main|master)\b|--force`, does not engage: `hooks/safety-gate.sh` owns push-to-main and force-push. The skip reads that one segment only. A PR-create segment never takes the skip.
9. **Dry runs stay gated.** `--dry-run` exempts nothing. gh's own help says PR-create `--dry-run` "May still push git changes". A push dry run is exempted neither: it precedes a real push that faces the same gate, and a flag parser for `-n`, `--dry-run`, and bundled short flags is new surface for no saving.

## Picture

```
 PreToolUse(Bash) --> hooks/ship-gate.sh
                          |
                          v
            flatten newlines; prefilter regex (loose)
                          |
               no match --+--> exit 0 (python never runs)
                          |
                        match
                          v
            python3 hooks/ship-gate-detect.py < command
                          |
          +---------------+-------------------+
          |               |                   |
       exit 0          exit 10          any other exit
     (no ship)         (ships)       (parse error, crash,
          |               |            python missing)
          v               v                   |
       exit 0     cd resolution, proof <------+
                  gate, lane gates (unchanged)
```

## Design

Design-bearing: a new parser on the hot path of every Bash call that names ship words, with a fail-safe exit contract.

How the parser judges one command:

```
  command text
       |
       v
  scan (quote/escape aware) ------------------> unbalanced quote: raise --> exit 3
       |
       v
  segments[] (words, heredoc body, redirect targets, pipeline id, subs[])
       |
       +--> subs[] ($(...), `...`, <(...), >(...)) -- recurse -- any ship? --> exit 10
       |
       v
  classify each segment:  first word (after NAME=v) in DATA set? --> DATA
       |                                   else ----------------------> CODE
       v
  demote DATA -> CODE:  piped into CODE | redirect target used by CODE
                        | printf -v | expanding heredoc with $( or `
       |
       v
  ship test on CODE segments (word-level OR text-level)
       |
       +--> push-only match + main/master/--force in that segment --> skip it
       |
       v
  any shipping segment? --> exit 10, else exit 0
```

Chosen approach: a small recursive-descent scanner in stdlib Python, one file, stdin in and an exit code out. It follows the kit's companion pattern (`citation-guard.py`, `money-gate.py`), which `install.sh` already copies beside the hooks. The DATA set is an allowlist: a command the parser does not know is CODE, so an unknown wrapper (`sudo`, `xargs`, `watch`, `tmux send-keys`, `python3 -c`) keeps today's recall.

Approaches considered:

| Approach | Why not |
|---|---|
| Unwrap quotes and key on the segment's binary, as `safety-gate.sh` does | That normalizer splits on `;` and `|` inside quotes. A commit message holding `; <ship words>` becomes a segment of its own and still engages. It also has no notion of substitutions. |
| Blank every quoted span, then run today's regex | It drops `bash -c "<ship words>"`, `ssh host '<ship words>'`, and `git "push"`. Fails open. |
| A denylist of code-running wrappers (`bash -c`, `eval`, `ssh`, ...) whose quoted args get scanned | The set of interpreters is open-ended. An unlisted one fails open. |
| `shlex` with `punctuation_chars` | It has no heredoc support and no command substitution, and it drops the newline boundary. The pre-pass needed to fix those is a scanner anyway. |
| Pure awk scanner in the hook | Possible, but a character-level recursive scanner in awk is hard to read and to review. The kit already runs stdlib Python companions from hooks. |
| Gate on the script body a command runs (`bash push.sh`) | Out of scope: the kit's own test files quote ship commands, so reading script bodies would engage the gate on every test run. The hole predates this spec and stays recorded under After state. |

The DATA set is kept small on purpose. Each entry must never execute its arguments: `echo`, `printf`, `cat` print; the grep family matches; `git commit/tag/log/grep` store or search text. `tee`, `sed`, `awk`, `jq`, `gh issue create`, and `git rebase` stay CODE: `tee` writes files that may run later, `sed` has an `e` command, `awk` has `system()`, `git rebase --exec` runs strings. A false positive on those shapes is accepted.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| python3 missing, companion file missing, parser crash | exit code other than 0 or 10 | hook engages (fail safe) |
| Unbalanced quote, unterminated substitution | scanner raises | exit 3, hook engages |
| Bypass: `printf '<ship words>' \| bash` | pipeline rule | printf demoted to CODE, engages |
| Bypass: write a script then run it in the same call | redirect-target rule | writer demoted when a CODE segment names the file |
| Bypass: `X="<ship words>"; $X` | assignment rule | value scanned as CODE |
| Bypass: `printf -v X '<ship words>'; eval "$X"` | `printf -v` rule | printf demoted to CODE |
| Bypass: `echo "$(<ship command>)"` or backticks | substitution recursion | substitution judged as a command, engages |
| Bypass: `cat <<EOF` body with `$(<ship command>)` | expanding-heredoc rule | cat demoted to CODE |
| Bypass: `bash <<EOF` with ship words in the body | `bash` is not DATA | body scanned, engages (closes today's hole) |
| Bypass: `bash -c "<ship words>"`, `ssh host '<ship words>'`, `sudo`, `env`, `xargs` | not DATA | text-level match, engages |
| Bypass: `git -C dir push`, `gh pr new` | word-level test | engages (closes today's holes) |
| Bypass: `main` in a commit message beside a real push | skip reads the push segment only | engages (closes today's hole) |
| Bypass: a script file already on disk (`bash push.sh`), a shell alias or function defined earlier in the session, a push through `gh api` | none | not covered; recorded under After state; unchanged from today |
| Bypass: `git push origin feat/main-fix` reads as safety-gate territory (`\bmain\b`) | none | unchanged from today; recorded under After state |
| False positive: `gh issue create --body "<ship words>"`, `python3 -c` printing ship words, `sed`/`awk`/`jq` scripts quoting them | CODE by allowlist | accepted: fail safe |
| False positive: a DATA writer whose target basename collides with an unrelated word in a CODE segment | redirect-target rule | accepted: fail safe |
| Parser latency | prefilter first | python runs only when the loose prefilter matches |

Threat model: an agent writing a command that happens to quote ship words, and an agent that routes a real ship through a wrapper. A deliberate adversary with a script file already beats every string-reading guard; that is recorded, not solved.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: parser | `hooks/ship-gate-detect.py` | the Contract's parser semantics; exit 0/10/other |
| T2: hook wiring | `hooks/ship-gate.sh` | prefilter, parser call, fail-safe exit handling; lines 36 and 38 replaced; `cd` resolution unchanged |
| T3: tests | `tests/test-hooks.sh` | every Test plan row, driven through the real hook against a fixture repo whose `Lane: full` spec has an empty ledger (engaged = exit 2, passed = exit 0) |
| T4: docs | `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated last), `docs/implementation-notes/gate-quoted-text.md`, `docs/verification/gate-quoted-text.md` | CHANGELOG names the behaviour change, including the `--base main` fix |

## Test plan

Engaged = the hook exits 2 naming `MISSING-GATE` against the fixture repo. Passed = exit 0. `<push>` and `<pr-create>` below stand for the real command words in the test file.

| # | Command shape | Expected |
|---|---|---|
| TP1 | `<push> origin feat/x` | engaged |
| TP2 | `cd <repo> && <push> -u origin feat/x` | engaged |
| TP3 | `git add -A && git commit -m x && <push>` | engaged |
| TP4 | `GIT_EDITOR=true <push>` and `env FOO=1 <push>` | engaged |
| TP5 | `git -C <repo> push` | engaged |
| TP6 | `<pr-create> --fill` and `gh pr new --fill` | engaged |
| TP7 | `<pr-create> --dry-run` | engaged |
| TP8 | `<push> origin feat/x && <pr-create> --base main` | engaged |
| TP9 | `git commit -m "note main" && <push> origin feat/x` | engaged |
| TP10 | `bash -c "<push>"`, `sudo <push>`, `ssh h '<push>'` | engaged |
| TP11 | `bash <<EOF` with `<push>` in the body | engaged |
| TP12 | `printf '<push>\n' \| bash` | engaged |
| TP13 | `printf '<push>' >\| x.sh && bash x.sh` | engaged |
| TP14 | `X="<push>"; $X` and `printf -v X '<push>'; eval "$X"` | engaged |
| TP15 | `echo "$(<push>)"` and `` echo `<push>` `` | engaged |
| TP16 | `cat <<EOF` body holding `$(<push>)` | engaged |
| TP17 | `<push> origin "feat/x` (unbalanced quote) | engaged |
| TP18 | the incident: `printf '%s\n' "fix: x" "<pr-create> --fill" >\| m && git commit -F m` | passed |
| TP19 | `git commit -m "docs: then <push> and <pr-create>"` | passed |
| TP20 | `git commit -m "$(cat <<'EOF'` ... body naming `<pr-create>`, with an apostrophe ... `EOF` `)"` | passed |
| TP21 | `echo "<push>"` and `echo "a; <push>"` | passed |
| TP22 | `cat <<'EOF' >\| notes.md` with `<push>` in the body | passed |
| TP23 | `grep -rn '<push>' docs/` and `rg "<pr-create>"` | passed |
| TP24 | `echo "<push>" \| grep push` | passed |
| TP25 | `<push> origin main` and `<push> --force origin feat/x` | passed (safety-gate territory) |
| TP26 | hook copied to a temp dir without `ship-gate-detect.py`, command TP1 | engaged (fail safe) |
| TP27 | existing ship-gate tests (F4 `cd` resolution, sg-demo, ID-062, ID-063, descent) | unchanged results |

Negative control: `lib/gate/negctl.sh` empties the DATA set in `ship-gate-detect.py`. Every segment then reads as CODE, TP18 to TP24 engage, and the suite must go red.

## Verification

`bash tests/test-hooks.sh` exits 0. `bash tests/run-all.sh --changed` exits 0. The negative control above reports PASS.

## After state

A commit, echo, heredoc, or grep that quotes ship words passes through. A real push or PR create engages, including shapes today's regex missed: `git -C`, `gh pr new`, `bash <<EOF`, a push next to a commit message that says `main`, and a PR create with `--base main`. Anything the parser cannot read engages.

Not covered, unchanged from today: a script file already on disk (`bash push.sh`), a shell alias or function from earlier in the session, a push through `gh api`, a ref hidden in a variable, and the `\bmain\b` quirk that reads `feat/main-fix` as safety-gate territory.

Behaviour change to flag at review: a PR create with `--base main` engages for the first time. In an adopted repo with an incomplete ledger, that call now blocks. That is the gate's stated purpose; today's skip was the bug.

## Decision Log

- Python companion over awk: readability of a recursive scanner, and the kit's existing companion pattern. The prefilter keeps python off the path of every unrelated Bash call.
- Exit 0 is the only pass. The exit-code contract inverts the usual "0 = found" so a crash, a missing interpreter, or a missing file all engage.
- DATA is an allowlist and deliberately short. Growing it is cheap and safe. Each addition must show the command never executes its arguments.
- `--dry-run` stays gated for both ship shapes (Contract item 9).
- The main/master/force skip keeps today's regex but reads one segment. Tightening the regex (the `feat/main-fix` quirk) is a separate change.
- Script-body inspection is out of scope: reading test files that quote ship commands would engage the gate on every test run.
