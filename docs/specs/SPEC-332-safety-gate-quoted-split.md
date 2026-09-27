# SPEC-332: safety-gate splits segments the way bash does

**Status:** DRAFT, revision 2 (validation round 1 and a break-it pass folded in)
Lane: full
Type: spec-bugfix
**Proof:** `docs/verification/safety-gate-quoted-split.md`; `tests/test-hooks.sh`, the safety-gate `Q` rows.

## Problem

`hooks/safety-gate.sh` normalizes a Bash command before its rules read it. Line 63 splits segments with `gsub(/&&|\|\||;|\|/, "\n")` over the raw text, before any quote handling. A `;` or `|` inside quotes therefore cuts a quoted span in two. The push rule reads only the first half, so the ref after the cut is lost.

Verified on master `2044b00d` through the real hook (rc 0 = allowed, rc 2 = blocked):

| Command | Master rc | Right rc |
|---|---|---|
| `<push> -o 'a;b' origin main` | 0 | 2 |
| `<push> -o 'a\|b' origin main` | 0 | 2 |
| `<push> -o 'a;b' --force origin feat/x` | 0 | 2 |
| `<push> origin main` | 2 | 2 |

`<push>` stands for the two words `git push`. The ship-gate and the branch-guard hook match those words in any command text, so this spec and its tests keep them out of literal prose where they would engage.

A fresh validator and an adversarial break-it pass found more fail-open shapes in the same normalizer and in the segment-start loop. Every one returns rc 0 on master:

| Class | Examples |
|---|---|
| escapes and continuations | `-o a\;b`, `-o $'a\';b'`, `<push> \` + newline + `origin main`, `ma\` + newline + `in` |
| false heredocs that hide every later line | a quoted `<<`, `<<` in a comment, a here-string `<<<x`, `$((1<<x))`, `${x#<<y}`, `<<'E'OF` read as `E`, a body started before the logical line ends |
| comment desync | `# don't` opens a single quote the shell never opens |
| a boundary that is not one | a single `&`, `\|&`, `$(...)` or a backtick mid-segment, a `(` inside `$(` |
| segment starts | `if`/`then`/`do`/`{`/`!`, a leading redirection, `timeout`, `nice`, `sudo -u root`, `bash -lc`, `/usr/bin/git` |
| push tokens | `-fu`, `HEAD:refs/heads/main`, `git -c k=v push`, `--mirror`, `--all`, `ma{in,x}` |
| other rules | `rm -Rf`, `kubectl -n ns delete`, DROP TABLE in a psql heredoc |

SPEC-328 (ship-gate reads commands, not quoted text) stopped on this hole. Its Step 3 skips the ship-gate for a push that safety-gate blocks. That skip is only safe when safety-gate reads the command correctly.

## Contract

Two passes print segments. The rules read every segment from both passes, as today. All logic stays in bash plus one awk program.

**Pass 1: the quote-aware walk.** The awk program reads the command one character at a time. A stack of open contexts decides what each character means:

| Top of stack | Meaning of characters |
|---|---|
| none, `$(`, `(`, or backtick (code) | `\` escapes the next character; a trailing `\` deletes the newline (no space). An unquoted `#` at a word start ends the line. `'`, `"`, `$'` open a quote. `$(`, `(`, and a backtick open a frame and end the segment. `)` closes a `$(` or `(` frame and ends the segment. `;`, `\|`, `&` end the segment. An unquoted `<<` (not part of `<<<`) records a heredoc delimiter, and the walk continues on the same line. |
| `'` | literal until the next `'` |
| `$'` | `\` escapes the next character; `'` closes |
| `"` | `\` escapes the next character; `$(` and a backtick open a frame and end the segment; `"` closes |

A newline ends the segment in a code context. Inside a quote, it joins the next line.

**Heredocs.** The delimiter is the full word after `<<` or `<<-`, with quotes and backslashes removed, as bash reads it (`<<'E'OF` is `EOF`). The body starts after the logical line ends, which means the line ends in a code context with no continuation. Body lines are skipped until each delimiter appears in order, compared after trimming blanks. If the input ends before the last delimiter appears, the walk misread a `<<`, and it replays the skipped lines through both passes. Fail safe.

**Pass 2: the naive split.** For each logical line outside a heredoc body, the hook also prints today's split: `&&`, `||`, `;`, `|` become boundaries whatever the quoting. A quoted string can be a script (`bash -c "..."`, `eval "..."`), and this pass reads a command after a separator inside such a string. It can only add blocks.

**Tokens.** For each segment, the hook deletes every `'`, `"`, and `\` (keeping the content) with a parameter expansion, then word-splits. Both passes replace `$`, `(`, `)`, and backtick with spaces, as today.

**Segment start.** Before it picks the binary, the loop skips:

| Word | Skip |
|---|---|
| `NAME=value` | the word |
| a redirection: `>f`, `2>f`, `&>f`, `<f`; `N>&M` | the word; a bare operator (`>`, `2>`) also takes the next word |
| wrappers: `sudo command exec nohup time env eval xargs builtin coproc bash sh zsh timeout nice stdbuf ionice caffeinate doas chronic unbuffer` | the word |
| grammar: `if then else elif while until do { } !` | the word |
| `-u -g -U -C -D -T -I -a` | the word and its operand (`sudo -u root`, `env -C dir`, `xargs -I {}`) |
| any other `-flag`, a number or duration (`10`, `5m`) | the word (`bash -lc`, `nice -n 10`, `timeout 5m`) |

Wrappers and the binary match on the word's basename, so `/usr/bin/git` is `git`.

**Rule tokens.**

| Rule | Change |
|---|---|
| git subcommand scan | `-c`, `--namespace`, `--config-env`, `--super-prefix` skip their operand, like `-C` |
| force push | `-f*` and `-[!-]*f*` (bundled `-fu`, `-uf`) block |
| push all | `--mirror`, `--all`, a glob `*` or brace `{` in a push token block as `push-all` |
| push to main | `refs/heads/main`, `refs/heads/master`, and `*:refs/heads/main\|master` block |
| rm | `-R` counts as recursive |
| kubectl | `-n`, `--namespace`, `--context`, `--cluster`, `--user`, `--kubeconfig`, `-s`, `--server`, `-l`, `--selector` skip their operand before the subcommand |
| DROP TABLE | reads the whole command, because the SQL often arrives as a heredoc body |

**Unchanged.** Rule messages, the log, and the exit codes.

## Picture

```
 PreToolUse(Bash) --> hooks/safety-gate.sh
                           |
                           v
                  one awk pass per line
                  |                   |
        heredoc body line?  --yes--> buffer (replayed at END if unterminated)
                  | no
          +-------+--------+
          v                v
   pass 2: naive      pass 1: quote-aware walk
   split on           stack: code / ( / $( / ` / ' / $' / "
   && || ; |          boundaries only in code context
          |                |
          +-------+--------+
                  v
       segments (union, one per line)
                  |
                  v
   delete ' " \ --> word split --> skip assignments, redirections,
                                   wrappers, grammar, flags
                                          |
                                          v
                                basename --> rules
```

## Design

Design-bearing: the normalizer of a hard gate changes how it reads a command. The diagram is in `## Picture` above.

Approaches considered:

| Approach | Why not |
|---|---|
| Block any push segment that contains a quote or backslash | Smallest diff, but it blocks `git -C "$WT" push -u origin fix/x`, a shape agents write daily. It also leaves the heredoc, `&`, and substitution holes open. |
| Quote-aware walk only | Precise for the handoff hole. It reads a quoted `bash -c` script as one opaque segment, so `bash -c "cd x; <push> origin main"` stays open. |
| Python or another parser | `docs/PHILOSOPHY.md` rules out Python in hooks; the SPEC-328 revision 1 parser was rejected on that ground. |
| Quote-aware walk plus the naive split (chosen) | The walk closes the quoted-separator hole. The naive pass keeps today's coverage and adds the `bash -c` compound case. A missed gate costs more than a false positive. |

The walk and the naive pass share one awk program, so heredoc bodies are skipped the same way for both. The replay backstop makes every heredoc misread fail safe: a false delimiter that never appears costs nothing.

Extensibility: a new quote form or boundary is one more row in the walk's context table. A new wrapper or grammar word is one more word in the segment-start `case`. The rules keep reading argv.

## Failure modes

Detection for every fail-open row is none: the remote branch protection is the backstop, as for any hole in this gate.

| Class | Mitigation |
|---|---|
| Quoted or escaped separator in a push segment | pass 1 keeps the segment whole: blocks |
| Nested quotes inside `$(...)` inside `"..."` | the stack tracks each context: blocks |
| A misread `<<` (arithmetic, parameter expansion) | the delimiter never appears, so the skipped lines replay: blocks |
| A misread `<<` whose false delimiter does appear later | lines between are skipped. Not covered; needs a delimiter-shaped line to follow |
| Push after a separator inside a `bash -c` / `eval` string | pass 2 reads it; the stray mark is deleted: blocks |
| Prose after a separator inside a quote (`-m "x; <push> origin main"`) | pass 2 blocks. Accepted false positive: master already blocks `-m "x; rm -rf y"` the same way. A heredoc commit message is never read. |
| Prose in a comment after a separator (`# x; <push> origin main`) | pass 2 blocks, as master does. Accepted false positive. |
| A heredoc body line that equals the delimiter after trimming blanks (`<<EOF` body line `  EOF`) | the body ends early and the rest is read. Fail safe. |
| An unterminated real heredoc | its body replays and may block. Fail safe. |
| A separator inside quotes inside a wrapped script; a `)` in a `case` pattern inside `"$(...)"`; an escape in a ref (`$'\x6dain'`) | not covered, recorded in the hook header |
| A ref in a variable, a script file, a pipe into `bash` | not covered, unchanged |
| `sudo -s`, `timeout -s SIG` and other flags with an operand outside the table | the operand becomes the binary; not covered |
| Unterminated quote | the walk ends in a quote context and prints what it holds; pass 2 still prints its split |
| Walk cost | one character loop per command; string concatenation per character is quadratic in one segment's length. A 28 KB command takes 0.4 s against master's 17 s, because the per-segment strip no longer forks a subshell |
| awk dialect | POSIX awk only: the suite passes under BSD awk 20200816, gawk 5.4.1, and mawk 1.3.4 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: walk, heredoc replay, naive pass, token strip | `hooks/safety-gate.sh` | Q1 to Q34 and Q50 to Q54 pass; the existing safety-gate rows stay green |
| T2: segment start and rule tokens | `hooks/safety-gate.sh` | Q35 to Q49 pass |
| T3: tests | `tests/test-hooks.sh` | rows Q1 to Q54, each through the real hook |
| T4: records | `docs/CHANGELOG.md`, `docs/verification/safety-gate-quoted-split.md`, `docs/implementation-notes/safety-gate-quoted-split.md` | CHANGELOG names the closed holes and the accepted false positives |

## Test plan

Every row runs the real hook through `q_hook`, which builds the JSON with jq. Block = rc 2. Allow = rc 0. `~` marks a newline.

| # | Command | Expect |
|---|---|---|
| Q1 | `<push> -o 'a;b' origin main` | block |
| Q2 | `<push> -o 'a\|b' origin main` | block |
| Q3 | `<push> -o 'a;b' --force origin feat/x` | block |
| Q4 | `<push> -o "a;b" origin main` | block |
| Q5 | `<push> -o a\;b origin main` | block |
| Q6 | `<push> -o $'a\';b' origin main` | block |
| Q7 | `<push> \~  origin main` | block |
| Q8 | `echo \" ; <push> origin main ; echo \"` | block |
| Q9 | `echo "<<X"; <push> origin main` | block |
| Q10 | `echo "<<X"~<push> origin main` | block |
| Q11 | `cat <<EOF; <push> origin main~body~EOF` | block |
| Q12 | `bash -c "cd x; <push> origin main"` | block |
| Q13 | `bash -c "cd x && <push> origin \"main\""` | block |
| Q14 | `echo "$(<push> -o "a;b" origin main)"` | block |
| Q15 | `` echo `<push> origin main` `` | block |
| Q16 | `x \|& <push> origin main` | block |
| Q17 | `sleep 1 & <push> origin main` | block |
| Q18 | `(<push> -o "a;b" origin main)` | block |
| Q19 | `<push> -o "a;b" origin feat/x` | allow |
| Q20 | `git -C "$WT" push -u origin fix/x` | allow |
| Q21 | `git commit -m "feat(x): a; b \| c"` | allow |
| Q22 | `git commit -m "$(cat <<'EOF'~fix: never <push> origin main; rm -rf /~EOF~)"` | allow |
| Q23 | `cat > f <<EOF~<push> origin main~EOF~echo done` | allow |
| Q24 | `git log --format="%(refname) x"` | allow |
| Q25 | `rm -rf "my dir"` | block |
| Q26 | `rm -rf "node_modules"` | allow |
| Q27 | `echo hi # don't~<push> -o 'a;b' origin main` | block |
| Q28 | `cat <<A # see <<B~body~A~<push> origin main` | block |
| Q29 | `cat <<<hello~<push> origin main` | block |
| Q30 | `echo $((1<<x))~<push> origin main` | block |
| Q31 | `cat <<'E'OF~x~EOF~<push> origin main` | block |
| Q32 | `cat <<A \~; <push> origin main~A` | block |
| Q33 | `echo "$( (true) & <push> origin main )"` | block |
| Q34 | `<push> origin ma\~in` | block |
| Q35 | `if true; then <push> origin main; fi` | block |
| Q36 | `{ ! <push> origin main; }` | block |
| Q37 | `for x in 1; do <push> origin main; done` | block |
| Q38 | `timeout 5m nice -n 10 <push> origin main` | block |
| Q39 | `sudo -u root <push> origin main` | block |
| Q40 | `bash -lc "<push> origin main"` | block |
| Q41 | `/usr/bin/git push origin main` | block |
| Q42 | `git -c a.b=c push origin main` | block |
| Q43 | `2>/dev/null <push> origin main` | block |
| Q44 | `<push> -fu origin feat/x` | block |
| Q45 | `<push> origin HEAD:refs/heads/main` | block |
| Q46 | `<push> --mirror origin` | block |
| Q47 | `<push> origin ma{in,x}` | block |
| Q48 | `rm -Rf ~/x` | block |
| Q49 | `kubectl -n prod delete pod x` | block |
| Q50 | `psql <<SQL~DROP TABLE x;~SQL` | block |
| Q51 | `# don't forget~git commit -m "$(cat <<'EOF'~rm -rf ~ was the bug~EOF~)"` | allow |
| Q52 | `sudo -E <push> -u origin feat/x` | allow |
| Q53 | `cat <<<hello; <push> -u origin feat/x` | allow |
| Q54 | `rm -rf \~  node_modules dist` | allow |

Negative controls, through `lib/gate/negctl.sh`:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | pass 1 treats `;` and `\|` as boundaries inside quotes (the old split) | Q1 to Q6 |
| NC2 | drop pass 2 (the naive print) | Q12, Q13 |
| NC3 | drop the heredoc replay | Q30 |
| NC4 | drop the comment rule | Q27, Q28, Q51 |

## Verification

`bash tests/test-hooks.sh` exits 0 under BSD awk, gawk, and mawk. NC1 to NC4 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

The push, force-push, delete, reset, kubectl, and DROP TABLE rules read the command the way bash splits it. Quotes, escapes, continuations, heredocs, comments, `&`, substitutions, shell grammar, redirections, and the common wrappers no longer hide a command from its rule.

Not covered, recorded in the hook header: a ref in a variable or an escape (`$'\x6dain'`), a script file or a pipe into `bash`, a quoted separator inside a wrapped script, and a `)` in a `case` pattern inside `"$(...)"`. SPEC-328's Step 3 skip may rely on safety-gate for a plain push segment. It must refuse the skip for these shapes, as its own Contract already does for `<<`, substitutions, and unterminated quotes.

Behavior changes to flag at review:

| Change | Why it is intended |
|---|---|
| A quoted string whose text after a separator reads as a push to main now blocks (`git commit -m "x; <push> origin main"`) | master already blocks the same shape with `rm -rf` |
| `--all`, `--mirror`, and a glob or brace refspec block | each can push main |
| DROP TABLE anywhere in a psql, mysql, or sqlite3 command blocks, heredoc body included | the SQL is the command's input |
| An unterminated heredoc's body is read | the walk cannot tell it from a misread `<<` |

## Decision Log

- Two passes, not one: the walk for precision, the naive split for scripts inside quotes. Fail safe.
- Delete every quote mark and backslash, not only paired quotes, so a naive-pass segment reads clean.
- A single `&` is a boundary. `2>&1` then splits into two harmless segments.
- The heredoc detector moves into the walk: only an unquoted `<<` opens a heredoc, and the rest of its line is read.
- Revision 2: a heredoc that never closes replays. This one backstop covers every way the walk can misread a `<<` (arithmetic, parameter expansion, a comment, a here-string), so the walk needs no arithmetic or `${}` frames.
- Revision 2: the segment-start and rule-token fixes ride this spec. They sit in the same loop, they are one line each, and SPEC-328 needs the gate to hold for a plain push segment.
- Bash and awk only, per `docs/PHILOSOPHY.md`.
