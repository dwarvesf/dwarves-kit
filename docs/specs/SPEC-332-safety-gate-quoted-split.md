# SPEC-332: safety-gate splits segments the way bash does

**Status:** DRAFT
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

The same normalizer has more fail-open shapes. Each one returns rc 0 on master:

| Shape | Cause |
|---|---|
| `<push> -o a\;b origin main`, `<push> -o $'a\';b' origin main` | backslash and ANSI-C quoting are not read |
| `<push> \` + newline + `origin main` | a continuation line is a new segment |
| `echo "<<X"; <push> origin main` | a quoted `<<` opens a heredoc; the rest of the line and every later line are dropped |
| `cat <<EOF; <push> origin main` + body | the text after a heredoc marker on its own line is dropped |
| `bash -c "cd x; <push> origin main"` | the second segment keeps a stray quote, so its ref token is `main"` |
| `echo "$(<push> origin main)"`, `` echo `<push> origin main` `` | a command substitution mid-segment is not a segment |
| `x \|& <push> origin main`, `sleep 1 & <push> origin main` | a single `&` is not a boundary |

`<push>` stands for the two words `git push`. The ship-gate and the branch-guard hook match those words in any command text, so this spec and its tests keep them out of literal prose where they would engage.

SPEC-328 (ship-gate reads commands, not quoted text) stopped on this hole. Its Step 3 skips the ship-gate for a push that safety-gate blocks. That skip is only safe when safety-gate splits the command correctly.

## Contract

Two passes print segments. The rules read every segment from both passes, as today.

**Pass 1: the quote-aware walk.** One awk program reads the command one character at a time. A stack of open contexts decides what each character means:

| Top of stack | Meaning of characters |
|---|---|
| none, `$(`, or backtick (code) | `\` escapes the next character. `'`, `"`, and `$'` open a quote. `$(` and a backtick open a substitution and end the segment. `)` closes a `$(` and ends the segment. `(`, `;`, `\|`, `&` end the segment. An unquoted `<<` (not `<<<`) records a heredoc marker, and the walk continues on the same line. |
| `'` | every character is literal until the next `'` |
| `$'` | `\` escapes the next character; `'` closes |
| `"` | `\` escapes the next character; `$(` and a backtick open a substitution and end the segment; `"` closes |

A newline ends the segment in a code context. Inside a quote, or after a trailing backslash, the newline joins the next line. After a line that recorded heredoc markers, the walk skips body lines until each marker line appears in order (leading and trailing blanks trimmed, as today).

**Pass 2: the naive split.** For each non-body line, the hook also prints today's split: `&&`, `||`, `;`, `|` become boundaries whatever the quoting. A quoted string can be a script (`bash -c "..."`, `eval "..."`, `ssh h "..."`), and this pass reads a command after a separator inside such a string. It can only add blocks.

**Tokens.** For each segment, the hook deletes every `'`, `"`, and `\` (keeping the content), then word-splits. The current `strip_quotes` unwraps only paired quotes, so a naive-pass segment kept a stray mark (`main"`). Deleting every mark closes that. Both passes replace `$`, `(`, `)`, and backtick with spaces, as today.

**Unchanged.** The rules, their tokens, their messages, the wrapper skip, the log, and the exit codes.

## Picture

```
 PreToolUse(Bash) --> hooks/safety-gate.sh
                           |
                           v
                  one awk pass per line
                  |                   |
        heredoc body line?  --yes--> skip (both passes)
                  | no
          +-------+--------+
          v                v
   pass 2: naive      pass 1: quote-aware walk
   split on           stack: code / ' / $' / " / $( / `
   && || ; |          boundaries only in code context
          |                |
          +-------+--------+
                  v
       segments (union, one per line)
                  |
                  v
   delete ' " \  -->  word split  -->  wrapper skip  -->  rules (unchanged)
```

## Design

Design-bearing: the normalizer of a hard gate changes how it reads a command.

Approaches considered:

| Approach | Why not |
|---|---|
| Block any push segment that contains a quote or backslash | Smallest diff, but it blocks `git -C "$WT" push -u origin fix/x`, a shape agents write daily. It also leaves the heredoc, `&`, and substitution holes open. |
| Quote-aware walk only | Precise for the handoff hole. It reads a quoted `bash -c` script as one opaque segment, so `bash -c "cd x; <push> origin main"` stays open. |
| Python or another parser | `docs/PHILOSOPHY.md` rules out Python in hooks; the SPEC-328 revision 1 parser was rejected on that ground. |
| Quote-aware walk plus the naive split (chosen) | The walk closes the quoted-separator hole. The naive pass keeps today's coverage and adds the `bash -c` compound case. A missed gate costs more than a false positive. |

The walk and the naive pass share one awk program, so heredoc bodies are skipped the same way for both. The heredoc detector moves into the walk, because only an unquoted `<<` opens a heredoc.

Extensibility: a new separator or quote form is one more row in the walk's context table. The rules keep reading argv, so a new rule needs no change to the normalizer.

## Failure modes

| Class | Mitigation |
|---|---|
| Quoted or escaped separator in a push segment | pass 1 keeps the segment whole: blocks |
| Nested quotes inside `$(...)` inside `"..."` | the stack tracks each context: blocks |
| Quoted `<<` | not a heredoc in pass 1: the rest is read |
| Push after a separator inside a `bash -c` / `eval` string | pass 2 reads it; the stray mark is deleted: blocks |
| Prose after a separator inside a quote (`-m "x; <push> origin main"`) | pass 2 blocks. Accepted false positive: today already blocks `-m "x; rm -rf y"` the same way. A heredoc commit message is never read. |
| A separator inside quotes inside a wrapped script (`bash -c "cd x; <push> -o 'a;b' origin main"`) | not covered. Recorded in the header as a variant of the script-body hole. |
| A ref in a variable, a script file, a pipe into `bash` | not covered, unchanged; the header comment names them |
| Unterminated quote | the walk ends in a quote context and prints what it holds; pass 2 still prints its split |
| Walk cost | one character loop per command. A 28 KB command takes 0.4 s against master's 17 s, because the per-segment strip no longer forks a subshell |
| awk dialect | only POSIX awk features: verified under BSD awk 20200816, gawk 5.4.1, and mawk 1.3.4 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: walk + naive pass + token strip | `hooks/safety-gate.sh` | the Test plan rows pass; the existing safety-gate rows stay green |
| T2: tests | `tests/test-hooks.sh` | rows Q1 to Q26 added, each through the real hook |
| T3: records | `docs/CHANGELOG.md`, `docs/verification/safety-gate-quoted-split.md`, `docs/implementation-notes/safety-gate-quoted-split.md` | CHANGELOG names the closed holes and the accepted false positive |

## Test plan

Every row runs the real hook with `run_hook`. Block = rc 2. Allow = rc 0.

| # | Command | Expect |
|---|---|---|
| Q1 | `<push> -o 'a;b' origin main` | block |
| Q2 | `<push> -o 'a\|b' origin main` | block |
| Q3 | `<push> -o 'a;b' --force origin feat/x` | block |
| Q4 | `<push> -o "a;b" origin main` | block |
| Q5 | `<push> -o a\;b origin main` | block |
| Q6 | `<push> -o $'a\';b' origin main` | block |
| Q7 | `<push> \` + newline + `origin main` | block |
| Q8 | `echo \" ; <push> origin main ; echo \"` | block |
| Q9 | `echo "<<X"; <push> origin main` | block |
| Q10 | `echo "<<X"` + newline + `<push> origin main` | block |
| Q11 | `cat <<EOF; <push> origin main` + body + `EOF` | block |
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
| Q22 | `git commit -m "$(cat <<'EOF'` + body naming `<push> origin main; rm -rf /` + `EOF` + `)"` | allow |
| Q23 | `cat > f <<EOF` + body `<push> origin main` + `EOF` + `echo done` | allow |
| Q24 | `git log --format="%(refname) x"` | allow |
| Q25 | `rm -rf "my dir"` | block |
| Q26 | `rm -rf "node_modules"` | allow |

Negative controls, through `lib/gate/negctl.sh`:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | pass 1 treats `;` as a boundary inside quotes (the old split) | Q1 to Q6 |
| NC2 | drop pass 2 (the naive print) | Q12, Q13 |

## Verification

`bash tests/test-hooks.sh` exits 0. NC1 and NC2 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

A push to main or a force push blocks whatever quoting, escaping, heredoc, `&`, or substitution surrounds it, except the recorded holes: a ref in a variable, a script file or pipe, and a quoted separator inside a wrapped script. SPEC-328's Step 3 skip can rely on safety-gate's split.

Behavior change to flag at review: a quoted string whose text after a separator reads as a push to main now blocks (`git commit -m "x; <push> origin main"`). Today the same shape with `rm -rf` already blocks.

## Decision Log

- Two passes, not one: the walk for precision, the naive split for scripts inside quotes. Fail safe.
- Delete every quote mark and backslash, not only paired quotes, so a naive-pass segment reads clean.
- A single `&` is a boundary. `2>&1` then splits into two harmless segments.
- The heredoc detector moves into the walk: only an unquoted `<<` opens a heredoc, and the rest of its line is read.
- Bash and awk only, per `docs/PHILOSOPHY.md`.
