# Spec: one repo-root anchor for every dwarves-kit hook, across both dispatch tables
Generated: 2026-09-28
Status: DRAFT
Lane: full

## Problem

`hooks/session-state-save.sh` (Stop and SubagentStop) sets `STATE_DIR=".claude/session-state"`,
a path relative to the hook's `$PWD`. From a repo subdirectory (observed: a session sitting in
`ops-toolkit/.claude/handoffs/`) it writes a NESTED copy,
`ops-toolkit/.claude/handoffs/.claude/session-state/`, instead of the repo root every reader of
that file expects.

That one hook has two more cwd-relative sites beyond `STATE_DIR`: the active-spec lookup
(`ls docs/specs/SPEC-*.md`, empty from a subdirectory, so the state carries `Spec: none` even
when a spec is active at the root) and the recent-files scan (`find .`, too narrow from a
subdirectory). Pulling that thread past this one hook, the same shape recurs across at least
seven of the roughly two dozen hooks wired in `hooks/hooks.json`:
`pre-compact-backup.sh`, `post-compact-reinject.sh` (the READ half of a pair
`pre-compact-backup.sh` WRITES; both cwd-relative independently), `anti-rationalization.sh`
(its `.claude/debug` guess-fix guard), `spec-drift-guard.sh`, `context-readiness.sh`, and
`slop-cleaner.sh`. Full detail per hook: `## Solution`, "Full enumeration".

This is a repo-wide pattern, not two hooks. The git calls scattered through these same hooks
(`git branch --show-current`, `git log`, `git diff HEAD`, `git rev-parse --is-inside-work-tree`)
are unaffected either way, git climbs to `.git` from any subdirectory on its own; only the plain
relative reads and writes are wrong. Fixing two hooks would leave the rest of the class silently
broken and would not stop a NEW hook from reintroducing the bug. Operator decision: fix the class
once, with one shared anchor every hook goes through, self-enforced so a future hook cannot
bypass it silently. A second operator decision, made after the first review round surfaced it:
keep that universal anchor AND fix the one hook it would otherwise break
(`ship-gate.sh`, see `## Solution`, "ship-gate.sh needs its own scoped fix").

## Solution

### The anchor

A new file, `hooks/anchor-root.sh`, mode 100755:

```sh
#!/bin/bash
# anchor-root.sh -- cd to the repo (or worktree) root, then run the given hook command.
# Every hooks.json / settings.json entry routes through this (see the one named exclusion
# below), so no hook ever reads or writes relative to the wrong directory because a
# session's cwd happened to be a subdirectory.
#
# Usage: anchor-root.sh <hook-path> [args...]
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
cd "$ROOT" 2>/dev/null || true
exec "$@"
```

`git rev-parse --show-toplevel` returns the WORKTREE's own root inside a worktree (not the main
checkout's), so a worktree session still keeps its own state. Outside a git work tree the
command fails; the `||` falls back to `$PWD`, and the following `cd "$PWD"` is a no-op, so a
hook running outside any repo behaves exactly as it does today. `exec "$@"` replaces the wrapper
process with the target hook, so stdin (the hook's JSON payload), stdout, stderr, and the exit
code all pass through untouched, the same reasoning `citation-guard.sh` already gives for using
`exec` instead of a wrapped call.

A `.sh` hook that is itself a thin shim into a `.py` counterpart (`harvest.sh` → `harvest.py`,
`citation-guard.sh` → `citation-guard.py`, and likewise for `backlog-stage.sh`,
`context-hints.sh`, `intake-sweep.sh`, `money-gate.sh`) inherits the anchored cwd from its parent
process without any change to the `.py` file, both dispatch tables only ever name the `.sh` entry
point, so anchoring at that one dispatch layer covers `.sh` and `.py` hooks alike with nothing
language-specific.

### Two dispatch tables, both rewritten

Per ADR-0009 (`docs/decisions/0009-plugin-packaging-dual-ship.md`), dwarves-kit ships two
parallel hook-registration files that the ADR itself already flags as "kept in sync until
sunset": `hooks/hooks.json` (the Claude Code plugin path, `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh`
command strings) and the root `settings.json` (the legacy `bash install.sh` path,
`bash $HOME/.claude/dwarves-kit/hooks/<name>.sh` command strings). Both are hand-maintained;
there is no render script that keeps one in sync with the other. Every entry in BOTH files is
rewritten, in each file's own path-prefix convention:

- `hooks/hooks.json`: `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh ...` becomes
  `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh ...`.
- root `settings.json`: `bash $HOME/.claude/dwarves-kit/hooks/<name>.sh ...` becomes
  `bash $HOME/.claude/dwarves-kit/hooks/anchor-root.sh $HOME/.claude/dwarves-kit/hooks/<name>.sh
  ...` (the outer `bash` invocation is unchanged; `anchor-root.sh` itself is a bash script, so
  running it via an explicit `bash` prefix or via its own shebang is identical).

No other field in any entry, in either file, changes. `tests/test-hook-anchor.sh` (below) checks
BOTH files, so the two dispatch tables cannot drift back out of sync with each other on this one
axis even though nothing else keeps them in sync.

### Rejected alternatives

- **A two-line anchor pasted into every hook file** (or the same idea factored as a helper each
  hook `source`s at its own top). Rejected: touches roughly fifteen files individually across
  BOTH dispatch tables' worth of hooks, and nothing stops a NEW hook file from omitting the paste
  or the `source` line, the exact regression this fix must close off. A per-file convention
  cannot be mechanically checked the way one dispatch table (now two, both checked) can.
- **`$CLAUDE_PROJECT_DIR`.** Rejected, with a caveat on how firmly we can state why. Per Claude
  Code's own hooks documentation (not vendored in this repo, so not citable from inside it, and
  not independently re-verified against a live Claude Code process in this session),
  `CLAUDE_PROJECT_DIR` is set once, to the directory Claude Code was launched from; it is fixed
  for the session, not re-derived per hook invocation from the hook's actual cwd. If that holds,
  a worktree session (whose cwd differs from the main checkout Claude Code was launched from)
  would see it point at the MAIN checkout, not the worktree's own root, breaking "a worktree
  session keeps its own state". `git rev-parse --show-toplevel`'s worktree behavior, by contrast,
  is standard, well-documented git functionality (a worktree has its own top), which is the
  firmer half of this decision even where the `CLAUDE_PROJECT_DIR` half is not independently
  re-verified.

### Precedent already in this codebase

Eight hooks already resolve their own root the same way, independently, before this spec:
`ship-gate.sh` and `commit-format.sh` (`git rev-parse --show-toplevel`, falling back to their own
`$PWD`/`pwd`), `anti-rationalization.sh` (the IDENTICAL pattern, for its own `understanding_gate`
policy-config lookup, a separate line from the `.claude/debug` check this spec fixes in the same
file), `codebase-index.sh` (identical pattern), and `harvest.py`, `backlog-stage.py`,
`intake-sweep.py` (each has its own `_repo_root()` doing the same git call, falling back to
`os.getcwd()`). The anchor consolidates a pattern this codebase already reinvented eight times
into one place, rather than introducing something novel.

### ship-gate.sh needs its own scoped fix

`ship-gate.sh` (PreToolUse, matcher `Bash`) parses a leading `cd <path>` out of the COMMAND TEXT
about to run (its own comment: "A command that cd's elsewhere ships THAT repo, not the session
cwd, the cross-repo misfire: a `cd other-repo && git push` was gated against the SESSION repo's
spec"). When that `cd` target is RELATIVE, the hook resolves it with a bare `[ -d "$CDDIR" ]`
test and `git -C "$CDDIR" rev-parse --show-toplevel`, both implicitly relative to the HOOK's OWN
`$PWD` (bash resolves a relative path against the process's cwd with no explicit join needed).
Today, with no anchor, that `$PWD` already equals the tool's real invocation cwd, so this happens
to work. Under the universal anchor, the hook's own `$PWD` becomes the ANCHORED repo root instead
(of whatever repo the session's true subdirectory belongs to), so a relative `cd ../other-repo`
resolves against the WRONG base directory: `[ -d ]` fails (the path does not exist from the new
base), the code falls to `ROOT=$(git rev-parse --show-toplevel ...)` from the hook's own
(anchored) `$PWD`, which resolves to the SESSION repo, not `../other-repo`. **This reintroduces
the exact cross-repo misfire ship-gate.sh's own comment says it was built to prevent**, as a
direct side effect of anchoring every hook uniformly.

**Fix** (mirrors `board-row-gate.sh`'s existing pattern, which already prefers the JSON payload's
`.cwd` over its own `$PWD` for the identical reason):

- Add, right after `INPUT=$(cat)`:
  `REAL_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -n "$REAL_CWD" ] ||
  REAL_CWD="$PWD"`
- Right after the existing `CDDIR="${CDDIR/#\~/$HOME}"` line (before the
  `DWARVES_KIT_PRINT_CDDIR` test affordance, so that affordance keeps printing the fully-resolved
  value): `case "$CDDIR" in ""|/*) ;; *) CDDIR="$REAL_CWD/$CDDIR" ;; esac`
- Change the fallback branch from `ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)` to
  `ROOT=$(git -C "$REAL_CWD" rev-parse --show-toplevel 2>/dev/null || true)`.

This is the ONE hook file whose OWN code changes in this spec (a scoped, three-line exception to
"no hook file's own code changes", named explicitly rather than left implicit).

**Audit: every other hook that resolves a tool_input path/command operand against `$PWD`,**
checked by reading each hook's actual source, not just the earlier grep:

| Hook | Operand resolved against cwd | Verdict |
|---|---|---|
| `ship-gate.sh` | a relative `cd`-prefix parsed from `tool_input.command` | Broken by the anchor; fixed above |
| `secrets-guard.sh` | a relative path in `tool_input` (Read/Edit path, or a Bash operand), canonicalized in `normpath()` via `$PWD/$p` | Would break the same way; **excluded from the anchor entirely** (below), not patched, since it never needs the fix if it never runs anchored |
| `safety-gate.sh` | none: `targets_all_safe()` and every rule (`rm`, `find -delete`, `git push`, `kubectl delete`, `DROP TABLE`) is pure lexical pattern matching on the operand TEXT, never a filesystem or cwd-relative check (`[ -d ]`/`git -C`) | Unaffected, verified by reading the full rule set |
| `commit-format.sh` | its own `git rev-parse --show-toplevel \|\| pwd` is a SELF-lookup (which repo's gate-policy config applies), not a `tool_input` operand; it never parses an embedded `cd` at all | Unaffected either way: before or after anchoring, this lookup resolves to whichever repo the process is IN, and it was already blind to an embedded `cd` before this spec (a pre-existing, separate gap, not introduced or worsened here) |
| `board-row-gate.sh` | already prefers `.cwd` from the payload, falling back to `$PWD` only when `.cwd` is absent | Unaffected in the normal case; the rare fallback moves from "true invocation cwd" to "resolved root", not expected to fire for a PreToolUse Bash hook |
| `spec-drift-guard.sh`, `money-gate.py` | `tool_input.file_path`, already ABSOLUTE (per the Write/Edit/MultiEdit tool schema) | No relative-path resolution happens at all |
| `auto-format.sh` | `tool_input.file_path` (absolute) for the file itself; separately, its OWN `./node_modules/.bin/prettier` lookup is cwd-relative | The file path is unaffected; the prettier lookup is a real but low-severity dependency, see below |

Two hooks came out of this audit relying on the REAL invocation cwd on purpose:

- **`secrets-guard.sh`** (PreToolUse, matcher `Read|Edit|Bash`): must canonicalize a relative path
  OPERAND exactly as the tool call itself would, against the real invocation directory, not the
  repo root. A security-relevant correctness regression otherwise: a relative path could dodge,
  or wrongly trip, the secret-file denylist. **Excluded**: its entry in BOTH `hooks.json` and
  `settings.json` is the one named exception, left exactly as it runs today.
- **`auto-format.sh`** (PostToolUse, matcher `Write|Edit`): `find_prettier()`'s
  `./node_modules/.bin/prettier` check, for a monorepo package's own local formatter. Lower
  severity than `secrets-guard.sh`: the hook already "exits 0 always" and is advisory-only, it
  never blocks or gates anything; a miss just falls back to a global `prettier` or skips
  silently. Accepted as a minor, out-of-scope cosmetic tradeoff; **not excluded** from the anchor.

### Full enumeration

Every hook wired in EITHER dispatch table, checked two ways: the exact grep the validator named,
`grep -n '\.claude/\|docs/specs\|CLAUDE\.md\|find \.' hooks/*.sh hooks/*.py`, plus a broader sweep
for `$PWD`/`` `pwd` ``/`os.getcwd()` to catch reads the first pattern's literal strings miss (this
second sweep is what surfaced `secrets-guard.sh` and `ship-gate.sh`, neither of which the first
pattern would have found).

**Table 1: fixed by the anchor (today's bug class, no code change to the hook file itself)**

| Hook | Event | cwd-relative site | Effect of anchoring |
|---|---|---|---|
| `session-state-save.sh` | Stop, SubagentStop | `STATE_DIR`, the spec glob, `find .` | The reported bug; state lands at the root with the right Spec/Files sections |
| `pre-compact-backup.sh` | PreCompact | `BACKUP_DIR`, the spec glob, `find .` (unpruned) | Backup lands at the root; see the PreCompact-timeout edge case below |
| `post-compact-reinject.sh` | PostToolUse (`compact`) | `CLAUDE.md`, the spec glob, `.claude/backups` reader | Now reads the SAME root `pre-compact-backup.sh` just wrote (the writer/reader pair); see the firing-verification note below |
| `anti-rationalization.sh` | Stop | `.claude/debug` check + `find .claude/debug` | The guess-fix guard now fires correctly from any subdirectory; a `$(pwd)` log line becomes cosmetic-only |
| `spec-drift-guard.sh` | PreToolUse (`Write`) | the spec glob | The drift check stops silently no-op'ing from a subdirectory (today: empty glob, whole check exits with nothing checked) |
| `context-readiness.sh` | SessionStart | `CLAUDE.md`, the spec glob, `find .` | Readiness warnings stop misfiring ("no CLAUDE.md", "no spec") from a subdirectory where both exist at the root |
| `slop-cleaner.sh` | Stop | `find .` (already pruned, already work-tree-guarded) | Scans the whole repo instead of the cwd's subtree, same class of fix as case 1; no new test case added (structurally covered by the same mechanism) |

**Table 2: already self-anchored or immune, the wrapper is a no-op (no code change)**

| Hook | Why unaffected |
|---|---|
| `commit-format.sh` | Already does `git rev-parse --show-toplevel 2>/dev/null \|\| pwd` for its own policy-root lookup |
| `codebase-index.sh` | Already does `REPO="$(git rev-parse --show-toplevel 2>/dev/null \|\| pwd)"` |
| `safety-gate.sh` | `$(pwd)` appears only in its audit `log_block` line, never in a gating decision (confirmed by reading the full rule set, see the audit table above) |
| `board-row-gate.sh` | `.cwd` from the JSON payload wins whenever present (the normal case); anchoring only touches the rare fallback where `.cwd` is absent |
| `batch-debt-warn.sh` | `ledger_root` resolves via a `$HOME`-scoped ledger path, not cwd-derived |
| `tool-policy-guard.sh` | Policy path is `$HOME`/`KIT_TOOL_POLICY`; tool name comes from the payload; no cwd read at all |
| `money-gate.py` | Reads `payload.get("cwd")` only, never `os.getcwd()` |
| `context-budget.sh` | Reads `.cwd` from the payload with NO `$PWD` fallback at all; an absent `.cwd` just skips two settings-file checks |
| `citation-guard.py` | `payload.get("cwd")` wins before its `os.getcwd()` fallback; anchoring only touches that last resort, and only makes it MORE correct |
| `harvest.py`, `backlog-stage.py`, `intake-sweep.py` | Each already has its own `_repo_root()` doing `git rev-parse --show-toplevel`, falling back to `os.getcwd()` only on failure |
| `prose-rag.sh` | Its `pwd` resolves the SCRIPT's own directory (`cd "$(dirname ...)" && pwd`), not the session cwd, an unrelated use |
| `context-hints.py`, `notification.sh`, `permission-auto-approve.sh`, `output-offload.sh` | No cwd/pwd/`getcwd()` reference found in any of the four |

**Table 3: needed a scoped code fix to keep working correctly under the anchor**

| Hook | Fix |
|---|---|
| `ship-gate.sh` | See "ship-gate.sh needs its own scoped fix" above |

**Excluded from the anchor entirely:**

| Hook | Reason |
|---|---|
| `secrets-guard.sh` | See "Rejected alternatives" table above; a security-relevant, on-purpose dependency on the real invocation cwd |

### install.sh and lib/adopt.sh: audited, one small fix

Both scripts filter or diagnose the two dispatch tables by pattern-matching each entry's
`.command` string; neither does an EXACT match, so prepending `anchor-root.sh` does not silently
break either, verified by reading the actual code:

- `install.sh`'s module filter (`jq --arg re "$KIT_HOOK_RE" ... select(.command | test($re))`,
  the `KIT_SETTINGS_FILTERED=` block) uses `test()`, a SUBSTRING search. `$KIT_HOOK_RE` is built
  from enabled hook BASENAMES (e.g. `session-state-save\.sh`), which still appears, unchanged,
  inside the anchored command string (`bash .../anchor-root.sh .../session-state-save.sh`).
  Verified unaffected; no code change.
- `install.sh`'s wired-module probe (`grep -q "dwarves-kit/hooks/${_h}"` inside the
  `KIT_EXISTING_WIRED_MODULES` loop) is the same kind of substring existence check, against a
  KNOWN hook basename, never an exact match. Verified unaffected; no code change.
- `lib/adopt.sh`'s diagnostic EXTRACTION (`grep -oE 'dwarves-kit/hooks/[A-Za-z0-9._-]+\.sh'`,
  feeding `before_wired`/`after_wired`, used only for the printed "wired hook-module" message and
  the `did=1` drift flag) is different: it extracts EVERY matching substring, not just a known
  one, so it will now ALSO extract `dwarves-kit/hooks/anchor-root.sh` from every anchored
  command, one line per distinct hook file, `sort -u` collapses the repeats to one. This is a
  constant, always-present line in both the before AND after snapshot once this fix lands, so the
  `did=1` drift-detection boolean stays correct (unaffected on the axis that matters), but the
  printed diagnostic would misleadingly list `anchor-root` as if it were a discrete, per-module
  hook. **Fix**: add `| grep -v '/anchor-root\.sh$'` to both the `before_wired` and `after_wired`
  extraction lines, so the diagnostic only ever names real, addressable hooks.

### Docs projection

Three docs are pinned to the `hooks/*.sh` file count or list by tests that will fail once
`hooks/anchor-root.sh` exists, and one gate checks freshness at push:

- `docs/architecture.md`'s "## Hook fallback layer" table: `tests/test-meta.sh` (~line 2833)
  asserts `HOOK_ROWS == HOOK_FILES` (one table row per `hooks/*.sh` file). Add one row for
  `anchor-root.sh`, classed like `codex-hook-adapter` (infrastructure, "owns no allow or deny
  rule"), not `hard`/`advisory`/`convenience`: `| \`anchor-root\` | every hooks.json/settings.json
  event except secrets-guard's PreToolUse entry | infrastructure | none (cds to the resolved
  root before exec'ing the real hook; owns no allow or deny rule) |`.
- `README.md`'s `<summary><b>Hooks</b>` table: same parity check (~line 2858), same fix, one new
  row.
- `docs/FEATURES.md`: regenerate via `lib/registry/feature-registry.sh generate` (its
  `feature-registry.sh:169`-area freshness is what `ship-gate.sh`'s own registry-freshness check
  enforces at push for a diff touching `hooks/[^/]+\.sh` or `hooks/hooks.json`). The generator's
  `hook_events()` matches by `select(.command | endswith($f))`, `$f = "hooks/<name>.sh"`. Every
  OTHER hook's anchored command still ENDS with its own `hooks/<name>.sh` (the anchor prefix
  comes first), so their rows stay accurate. `anchor-root.sh`'s OWN row is the one exception: no
  command ever ENDS with `hooks/anchor-root.sh` (its own path is always followed by the real
  hook's path), so `hook_events()` returns no match and the generated row shows `-` for Event,
  under-representing that it fires on nearly every event. This is a real, narrow gap in the
  generator's own matching, pre-existing in shape (the same `endswith()` limitation already
  under-reports any hook invoked with trailing arguments, e.g. `harvest.sh --lab-log`'s
  SessionEnd entry), not introduced by this fix and not fixed here; named as a follow-up to
  `lib/registry/feature-registry.sh`, not this spec.

## Picture

```
 Claude Code                                    bash install.sh path
 hooks/hooks.json                                root settings.json
 ${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh       bash $HOME/.claude/dwarves-kit/hooks/anchor-root.sh
 ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh [args]     $HOME/.claude/dwarves-kit/hooks/<name>.sh [args]
        |                                                    |
        +----------------------+-----------------------------+
                               v
                    anchor-root.sh (one file, both tables point at it)
                               |
              git rev-parse --show-toplevel --fails (no work tree)--> ROOT = $PWD (fail-open)
                               |
                               | succeeds (repo or worktree top, PHYSICAL path, see Edge Cases)
                               v
                    cd "$ROOT" 2>/dev/null || true
                               |
                               v
                    exec "$@"  -->  <hook>.sh runs with cwd = ROOT
                                    exit code / stdio pass through untouched

 ONE named exception, in BOTH hooks.json and settings.json: secrets-guard.sh's entry has
 no anchor-root.sh prefix. It keeps running at the tool's real invocation cwd (needed to
 canonicalize a relative path OPERAND the same way the tool call itself would).

 ONE hook needed its own scoped fix, not just the wrapper: ship-gate.sh now reads the
 payload's .cwd (REAL_CWD) to resolve a relative embedded `cd <path>`, instead of trusting
 its own (now possibly anchored) $PWD, the same pattern board-row-gate.sh already used.

 tests/test-hook-anchor.sh (the lint)
        |
        v
 parses BOTH hooks.json and settings.json --> every command has the anchor-root.sh prefix,
 except the one named exemption --> a bypass (real or a fixture case) fails the test
```

## Design

This is a design-bearing change: a new dispatch-layer indirection touching every wired hook
across two files, plus a scoped fix to one hook's own logic. It is not "obvious" in the sense of
a single-line, judgment-free patch; the choice of MECHANISM (one shared wrapper vs. per-hook
patches vs. an env var) is the actual design decision, and it has a real, identified failure mode
(`ship-gate.sh`) that had to be found and fixed, not assumed away.

**Chosen approach**: DEC-A (below), a single wrapper script referenced from every entry in both
dispatch tables, self-enforced by a lint that parses both files. See the dispatch diagram in
`## Picture` for the concrete flow (Claude Code / bash-install → anchor-root.sh → cd → exec), and
the "Rejected alternatives" subsection above for why the two other candidates (a per-hook pasted
or sourced anchor; `$CLAUDE_PROJECT_DIR`) do not hold up.

**Why a wrapper beats a per-hook convention, concretely**: only a single dispatch table (now two,
both checked by the same lint) can be MECHANICALLY verified for a bypass. A convention living
inside N hook files depends on every future hook author remembering it; nothing but code review
would catch an omission, and code review is exactly the kind of "prose instruction" this
codebase's own hook-fallback philosophy (`docs/architecture.md`, "Hook fallback layer") says a
hook exists to backstop once it stops being reliable.

**The exemption policy** (what earns a hook the right to skip the anchor): a demonstrated,
security- or correctness-relevant dependency on the REAL invocation cwd that anchoring would
actively break, established by reading the hook's own source, not asserted from its name or
matcher. `secrets-guard.sh` clears this bar (a denylist decision would silently change). A merely
inconvenient or cosmetic dependency (`auto-format.sh`'s monorepo-local prettier lookup) does NOT
clear it, and stays anchored with the tradeoff named instead. The bar is recorded in exactly two
places that must never drift apart: this spec's Decision Log, and `tests/test-hook-anchor.sh`'s
own exemption list (a short, commented array, not a bare allowlist with no reason attached).

**Cost, named rather than assumed away**: every hook invocation now forks two extra short-lived
processes it did not before (`anchor-root.sh`'s own bash process, plus the `git rev-parse
--show-toplevel` it runs), on EVERY matching event, several of which (PreToolUse, PostToolUse)
fire many times per session. This is a real, per-fire latency cost, not zero. Accepted here: a
`git rev-parse --show-toplevel` against a warm working tree is a low-single-digit-millisecond
operation, small next to the hook bodies' own work (their own git calls, `jq` parses, file I/O),
and the correctness the class of bug this fixes is worth more than that cost. Not benchmarked in
this spec; if it becomes measurable in practice, batching multiple hooks behind one `cd` (a
Claude-Code-level change, not available today) would be the next lever, not something this spec
attempts.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-A: Write this spec.

### Phase 2: Core
- [ ] TASK-B: Add `hooks/anchor-root.sh` per `## Solution`, committed with the executable bit set
  (mode 100755).
- [ ] TASK-C: Rewrite every `command` entry in `hooks/hooks.json` per `## Solution`, "Two
  dispatch tables", except `secrets-guard.sh`'s entry (left unchanged).
- [ ] TASK-C2: Rewrite every `command` entry in the root `settings.json` the same way, same
  exception.
- [ ] TASK-C3: Apply the scoped `ship-gate.sh` fix per `## Solution`, "ship-gate.sh needs its own
  scoped fix".
- [ ] TASK-C4: In `lib/adopt.sh`, add `| grep -v '/anchor-root\.sh$'` to the `before_wired` and
  `after_wired` extraction lines per `## Solution`, "install.sh and lib/adopt.sh".
- [ ] TASK-D: Add `tests/test-hook-anchor.sh` (new, a sibling of `tests/test-hooks.sh`, picked up
  by `tests/run-all.sh`'s `tests/test-*.sh` glob): parses BOTH `hooks/hooks.json` and root
  `settings.json`, asserts every command has the `anchor-root.sh` prefix except the one named
  exemption (a short, commented list, `secrets-guard.sh`), runs the same check function first
  against a small embedded fixture with one entry missing the wrapper (proving the checker itself
  catches a bypass, not merely vacuously true because the real files already comply), then
  against both real files.
- [ ] TASK-E: In `tests/test-hooks.sh`, add the six cases in `## Test plan` below, each invoking
  its hook THROUGH the wrapper (`bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/<hook>.sh"
  [args]`), not the bare hook. Existing cases that invoke hooks directly are untouched, they test
  a hook's own internal logic and are unaffected by this fix either way, since those fixtures
  already sit at their own repo root.
- [ ] TASK-E2: Docs projection per `## Solution`, "Docs projection": one new row each in
  `docs/architecture.md`'s Hook fallback layer table and `README.md`'s Hooks table, then
  `bash lib/registry/feature-registry.sh generate` to refresh `docs/FEATURES.md`.

### Phase 3: Polish
- [ ] TASK-F: Commit TASK-B through TASK-E2, then run all three negative controls in
  `## Test plan` (bottom) and confirm each goes RED under its mutation, then GREEN again
  restored.

## After state
- [ ] Every hook in Table 1 reads and writes relative to the repo/worktree root when dispatched
  through either table, regardless of which subdirectory the session's cwd is in. (Today:
  relative to whatever subdirectory the session happens to sit in.)
- [ ] `ship-gate.sh` resolves a relative embedded `cd <path>` against the tool's real invocation
  cwd (from the payload's `.cwd`), not against its own (possibly anchored) `$PWD`, so a
  cross-repo `cd ../other-repo && git push` still gates `other-repo`, not the session repo.
- [ ] `secrets-guard.sh` is unchanged in both dispatch tables: it keeps resolving relative path
  operands against the tool's real invocation cwd.
- [ ] A worktree session's hooks still write to that worktree's OWN `.claude/...` directories,
  not the main checkout's.
- [ ] A hook run outside any git work tree still behaves exactly as it does today.
- [ ] `tests/test-hook-anchor.sh` fails if a future entry, in either dispatch table, is added
  without routing through `anchor-root.sh`, unless it joins the same named exemption list with a
  reason.
- [ ] `docs/architecture.md`, `README.md`, and `docs/FEATURES.md` all carry `anchor-root.sh` as a
  hook file; the two row-count parity tests in `tests/test-meta.sh` stay green.
- [ ] Every existing case in `tests/test-hooks.sh` still passes unchanged.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] The six new `tests/test-hooks.sh` cases pass (session-state subdirectory-with-content,
  session-state worktree, session-state outside-repo confirmation (wrapper-routed), pre-compact-
  backup subdirectory, post-compact-reinject writer/reader pair, ship-gate relative-cd
  cross-repo resolution).
- [ ] `tests/test-hook-anchor.sh` passes: every entry in both `hooks.json` and `settings.json` is
  wrapped except the one named exemption, and its embedded bypass fixture is correctly flagged.
- [ ] No regression in existing `tests/test-hooks.sh` or `tests/test-meta.sh` cases.
- [ ] All three negative controls go RED under their mutation and GREEN again restored.
- [ ] `bash tests/run-all.sh` passes.

## Verification
`bash tests/run-all.sh`

## Test plan

All new cases live in `tests/test-hooks.sh`, reusing its existing fixture style: a throwaway git
repo under `mktemp -d "${TMPDIR:-/tmp}/dk-....XXXXXX"`, JSON piped on stdin, cleaned up with
`rm -rf`. Every new case invokes its hook THROUGH the wrapper:
`bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/<hook>.sh" [args]`, not the bare hook.

1. **`session-state-save.sh`, subdir with content (the reported bug).** A throwaway repo
   `SUBDIR_REPO` (`git init -q`, one commit), a fixture spec
   `SUBDIR_REPO/docs/specs/SPEC-001-x.md` containing `Status: DRAFT`, a nested directory
   `SUBDIR_REPO/.claude/handoffs/`, and `DWARVES_KIT_SESSION_MARKER` set to a marker file timed
   in the past (matching the existing SPEC-086 block's convention). Add a root-level
   `SUBDIR_REPO/touched.py` newer than the marker. Run the wrapper with
   `cd "$SUBDIR_REPO/.claude/handoffs"`. Assert:
   - `SUBDIR_REPO/.claude/session-state/last-state.md` exists (landed at the toplevel).
   - `SUBDIR_REPO/.claude/handoffs/.claude/session-state/` does NOT exist (no nested copy).
   - `last-state.md` contains `Spec: DRAFT` (the spec glob read the root's `docs/specs/`).
   - `last-state.md` contains `touched.py` under `## Files modified this session` (the `find .`
     scan reached the root, not just the subdirectory).
2. **`session-state-save.sh`, worktree keeps own state (no regression).** From `SUBDIR_REPO`,
   `git worktree add "$WT_DIR" -b <branch>` where `WT_DIR` is a SIBLING mktemp directory
   (`mktemp -d "${TMPDIR:-/tmp}/dk-wt.XXXXXX"`, outside `SUBDIR_REPO`'s own tree), with its own
   nested subdirectory `WT_DIR/sub/`. Before running, checksum
   `SUBDIR_REPO/.claude/session-state/last-state.md`
   (`shasum "$SUBDIR_REPO/.claude/session-state/last-state.md"`). Run the wrapper with
   `cd "$WT_DIR/sub"`. Assert:
   - `WT_DIR/.claude/session-state/last-state.md` exists (the worktree's OWN toplevel).
   - The checksum of `SUBDIR_REPO/.claude/session-state/last-state.md` is UNCHANGED, proving no
     cross-contamination between the main checkout and the worktree.
3. **`session-state-save.sh`, outside a git repo, wrapper-routed.** A NEW case, structurally
   identical to the existing `NOGIT2` case at `tests/test-hooks.sh:855`, but invoked THROUGH the
   wrapper this time (own fixture directory, e.g. `NOGIT3`, not a reuse of the existing variable
   name). Assert the same thing `NOGIT2` already asserts (no scan, no state written outside a
   repo), proving the `ROOT="... || $PWD"` fallback plus the no-op `cd "$PWD"` keep this path
   identical when routed through the wrapper.
4. **`pre-compact-backup.sh`, subdir.** A throwaway repo `PCB_REPO` (`git init -q`, one commit),
   a fixture spec `PCB_REPO/docs/specs/SPEC-001-x.md`, and a nested directory
   `PCB_REPO/.claude/handoffs/`. Run the wrapper with `cd "$PCB_REPO/.claude/handoffs"`. Assert:
   - `PCB_REPO/.claude/backups/` contains a file matching `*-backup-*.md` (the real naming shape,
     `<N>-backup-<timestamp>.md`; NOT the hook's own broken `backup-*.md` glob, see Out of Scope).
   - `PCB_REPO/.claude/handoffs/.claude/backups/` does NOT exist (no nested copy).
   - The backup file's content contains `Spec: docs/specs/SPEC-001-x.md`.
5. **The writer/reader pair.** From the same `PCB_REPO` and subdirectory as case 4, immediately
   run `post-compact-reinject.sh` through the wrapper (same cwd). Assert:
   - Its JSON `additionalContext` output contains `BACKUP: .claude/backups/` (it found the file
     `pre-compact-backup.sh` just wrote, at the same resolved root).
   - `PCB_REPO/.claude/backups/` (the path the assertion above names) exists at the REPO ROOT.
   - `PCB_REPO/.claude/handoffs/.claude/backups/` does NOT exist (no nested copy from this
     hook's own read side either).
6. **`ship-gate.sh`, a relative embedded `cd` resolves against the real invocation cwd, not the
   anchored `$PWD`.** A parent directory `PARENT` (`mktemp -d`) containing two sibling repos:
   `PARENT/session-repo/` (`git init -q`, one commit, a subdirectory `session-repo/sub/`) and
   `PARENT/other-repo/` (`git init -q`, one commit). Payload:
   `{"cwd":"<PARENT>/session-repo/sub","tool_input":{"command":"cd ../../other-repo && git push
   origin feat/x"}}` (the relative path `../../other-repo`, from `sub/`, correctly reaches
   `PARENT/other-repo`). Run `cd "$PARENT/session-repo/sub"` first, so the wrapper anchors
   `ship-gate.sh`'s own `$PWD` to `session-repo`'s root (NOT `other-repo`, matching what the
   anchor does today for a same-repo subdirectory), then pipe the payload with
   `DWARVES_KIT_PRINT_CDDIR=1` into `bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/
   ship-gate.sh"`. Assert the printed CDDIR equals `$PARENT/other-repo`. The assertion reads the
   value at the point the fix joins `REAL_CWD` + the relative text, BEFORE `git -C "$CDDIR"
   rev-parse --show-toplevel` runs, deliberately: `git rev-parse --show-toplevel` returns the
   PHYSICAL (symlink-resolved) path (see Edge Cases below), and on macOS `/tmp` is itself a
   symlink to `/private/tmp`, so comparing a POST-git-resolution value by raw string equality
   against a `mktemp`-returned `/tmp/...` path would be a false negative unrelated to the actual
   bug. Reading the pre-resolution joined value sidesteps that entirely, and matches how the
   existing `F4` test (`tests/test-hooks.sh:138-139`) already reads this same affordance for an
   absolute cd-target.

**Negative control 1 (the anchor's own cd).** `hooks/anchor-root.sh` is a new file with no
pre-fix revision to pin to, so its mutation is a no-op passthrough rather than a `git show` pin:
```sh
bash lib/gate/negctl.sh "$PWD" \
  'bash tests/test-hooks.sh 2>&1 | grep -E "FAIL.*(subdir with content|worktree keeps own state|writer/reader pair)" && exit 1 || exit 0' \
  "printf '#!/bin/bash\nexec \"\$@\"\n' > hooks/anchor-root.sh"
```
This overwrites the wrapper with a version that execs straight through, no `cd`, the exact
regression this fix guards against. Scoped to the three named cases (not the whole suite's exit
code), so an unrelated pre-existing flake elsewhere in the suite cannot mask, or fake, this
result. `negctl.sh` requires those three cases' relevant assertions to fail under the mutation,
then restores the real `anchor-root.sh` and confirms green again.

**Negative control 2 (the bypass lint).** `hooks/hooks.json` DOES exist at `afb52d01`, in its
pre-fix form where no entry has the wrapper:
```sh
bash lib/gate/negctl.sh "$PWD" 'bash tests/test-hook-anchor.sh' 'git show afb52d01:hooks/hooks.json > hooks/hooks.json'
```
Reverting `hooks.json` to that revision removes the wrapper from every entry; `negctl.sh`
requires `tests/test-hook-anchor.sh` to go RED (every `hooks.json` entry now lacks the prefix),
then restores the real `hooks.json` and confirms green again. Running the whole (small, dedicated)
lint file is itself already scoped, no separate grep needed. This one file is enough to prove the
check function works; the lint's real run checks both dispatch tables every time it runs, not
just under this control.

**Negative control 3 (the ship-gate fix).** `hooks/ship-gate.sh` DOES exist at `afb52d01`, before
the `REAL_CWD`/CDDIR-join/fallback change:
```sh
bash lib/gate/negctl.sh "$PWD" \
  'bash tests/test-hooks.sh 2>&1 | grep -E "FAIL.*relative cd resolves" && exit 1 || exit 0' \
  'git show afb52d01:hooks/ship-gate.sh > hooks/ship-gate.sh'
```
Reverting just `ship-gate.sh` to its pre-fix content makes case 6 go RED (the printed CDDIR
resolves against the anchored `$PWD`, landing on `session-repo`, not `other-repo`); `negctl.sh`
then restores the real `ship-gate.sh` and confirms green again.

## Edge Cases
1. `git rev-parse --show-toplevel` returns the PHYSICAL path (symlinks resolved), not necessarily
   the LOGICAL path a shell's `$PWD` or the payload's `.cwd` would show. On macOS, `/tmp` is
   itself a symlink to `/private/tmp`, so a test fixture created under
   `mktemp -d "${TMPDIR:-/tmp}/..."` sees the anchor's resolved `ROOT` differ, as a STRING, from
   the fixture variable's own `/tmp/...` path, even though both name the same directory. Every
   test assertion above uses existence checks (`[ -f ]`/`[ -d ]`), content checks (`grep`,
   checksums), or a PRE-git-resolution string comparison (case 6), all of which are symlink-safe;
   none compares a POST-`git rev-parse` absolute path by raw string equality against a
   `mktemp`-returned path.
2. A bare repository, or a cwd already inside the `.git` directory itself: `git rev-parse
   --show-toplevel` FAILS in both cases (no work tree to report), so `ROOT` falls back to `$PWD`
   and the following `cd` is a no-op; unchanged fail-open behavior, not a special case.
3. Two Stop hooks fire back-to-back from two different subdirectories of the SAME repo (main
   agent in one, a subagent in another): both anchor to the identical `ROOT`, so both read and
   write the SAME state files and the SAME spec glob, as if both ran at the repo root today. No
   new race, the file was already meant to be shared repo-wide.
4. **`pre-compact-backup.sh`'s `find .` is unpruned** (it filters heavy directories with post-hoc
   `grep -v` rather than pruning them during traversal, unlike `session-state-save.sh` and
   `slop-cleaner.sh`, both already fixed by SPEC-086). Anchoring it to the repo root from a
   subdirectory session makes this scan walk MORE of the tree than it does today (today it is
   accidentally bounded by whatever subtree the session's cwd happens to sit in). On a large repo
   this risks pushing the hook closer to, or past, its own 15-second PreCompact timeout. Not
   fixed here (the prune-during-traversal rewrite is a separate, scoped change to that one hook's
   own scan); named so it is not a silent regression.
5. **Per-fire fork cost** (see `## Design`, "Cost"): every anchored hook invocation now forks two
   extra short-lived processes (the wrapper itself, plus `git rev-parse --show-toplevel`).
   Accepted, not benchmarked in this spec.
6. **Does `post-compact-reinject.sh`'s `PostToolUse` matcher `compact` ever actually fire?** We
   found no test in this repo that exercises Claude Code's REAL dispatch of such an event
   (existing and new tests invoke the script directly with a hand-built JSON payload, which
   proves the script's own logic, never that Claude Code sends this event shape at all), and no
   changelog or decision doc recording that this was independently verified against a live
   session; the hook's own header cites an external pattern ("Nick Porter's PostToolUse(compact)
   pattern") as its source, not an in-repo confirmation. This is ORTHOGONAL to the fix in this
   spec: whether or not it fires, the fix only ensures it reads/writes at the right root WHEN it
   runs. Stated as a finding, not resolved here.

## Out of Scope
- Switching any hook to read `.cwd` instead of anchoring from `$PWD` (no in-repo mechanism found
  that would make them differ for these events; `.cwd` would still need the identical `git
  rev-parse --show-toplevel` step afterward, so it buys nothing over anchoring from `$PWD`
  directly, except for `ship-gate.sh`, which DOES need `.cwd`, fixed above for the specific,
  demonstrated reason).
- `pre-compact-backup.sh`'s NEXT-count glob bug: `COUNT=$(find "$BACKUP_DIR" -name
  "backup-*.md" ...)` never matches an existing file (every backup is actually named
  `<N>-backup-<timestamp>.md`), so `COUNT` is always 0 and `NEXT` is always 1. Pre-existing,
  independent of cwd resolution, not fixed here (our own test case 4 uses the correct
  `*-backup-*.md` pattern to avoid the same mistake).
- `post-compact-reinject.sh`'s lexical `sort | tail -1`: `find .claude/backups -name "*.md" |
  sort | tail -1` breaks past nine backups (`"10-backup-..."` sorts before `"2-backup-..."`
  lexically). Pre-existing, independent of cwd resolution, not fixed here.
- Whether `post-compact-reinject.sh`'s `PostToolUse` matcher `compact` ever fires at all (Edge
  Case 6): named, not resolved here.
- `feature-registry.sh`'s `hook_events()` under-reporting `anchor-root.sh`'s own row (and, as a
  pre-existing, separate gap, any hook invoked with trailing arguments): named in `## Solution`,
  "Docs projection", not fixed here.
- `codex-hooks.json`: a separate runtime's wiring (Codex, not Claude Code); AGENTS.md already
  states enforcement is Claude-Code-only. If the same class of bug exists there, that is a
  follow-up, not this spec.
- `hooks/intake-sweep.sh`: not wired via either dispatch table today (invoked some other way; it
  still gets its own row in the architecture.md/README.md hook-count parity tables, since those
  count `hooks/*.sh` FILES, not dispatch-table entries), so the anchor mechanism does not apply
  to it.
- `auto-format.sh`'s prettier-lookup caveat (named above): accepted, not fixed.
- `commit-format.sh`'s pre-existing blindness to an embedded `cd` in its own gate-policy lookup
  (named in the audit table above): a separate, narrower gap than `ship-gate.sh`'s (its check is
  advisory config, not a repo-identity decision the push targets), not introduced or worsened by
  this spec, not fixed here.

## Touches
- hooks/anchor-root.sh (new)
- hooks/hooks.json
- settings.json (root)
- hooks/ship-gate.sh
- lib/adopt.sh
- tests/test-hook-anchor.sh (new)
- tests/test-hooks.sh
- docs/architecture.md
- README.md
- docs/FEATURES.md (regenerated, not hand-edited)

## Decision Log
- DEC-A: One shared wrapper referenced from both dispatch tables, not a per-hook pasted or
  sourced anchor. Rationale: only a dispatch table (now two, both checked by one lint) can be
  mechanically checked for a bypass; a per-file convention cannot.
- DEC-B: `secrets-guard.sh` is excluded from the anchor in BOTH dispatch tables. It resolves a
  relative path OPERAND from `tool_input` against the tool's real invocation cwd, a
  security-relevant use the repo root would break. `auto-format.sh` has a similar but
  lower-severity dependency (a monorepo's local prettier lookup); kept anchored, flagged as an
  accepted tradeoff, because it is advisory-only and already fails soft. The exemption bar
  itself: a demonstrated, security- or correctness-relevant dependency on the real invocation
  cwd, established by reading the hook's source, recorded in this Decision Log AND in
  `tests/test-hook-anchor.sh`'s own exemption list, never just one of the two.
- DEC-C: No hook file's own code changes, EXCEPT `ship-gate.sh` (DEC-F below), a named, scoped
  exception, not a silent one. Every other fix lives in the wrapper plus the two dispatch-table
  rewrites, so the class stays fixed in one place instead of drifting across per-hook patches.
- DEC-D: Dropped an earlier, unverified claim that the hook JSON payload's `.cwd` field always
  equals the hook's own `$PWD`. No citable source for that equality exists in this repo; the
  decision to anchor from `$PWD` rests instead on there being no in-repo indirection that would
  make them differ for most events, and on `.cwd` needing the identical `git rev-parse
  --show-toplevel` step regardless. `ship-gate.sh` is the demonstrated exception, where they DO
  need to differ, fixed via DEC-F.
- DEC-E: Softened an earlier claim that `/kit:start` reads `last-state.md`. No code reader of
  that file exists in this repo today (`lib/adopt.sh` only lists it as part of the `session`
  install module's file manifest); the audience for a correctly-placed state file is crash
  recovery and a human skimming the repo, not a verified `start` code path.
- DEC-F: `ship-gate.sh` gets a scoped, three-line fix (read the payload's `.cwd` as `REAL_CWD`,
  join a relative CDDIR against it, fall back to `git -C "$REAL_CWD"` instead of bare `git
  rev-parse`) rather than being excluded from the anchor like `secrets-guard.sh`. Rationale: the
  hook's OWN root resolution (not a tool_input operand read) is what breaks, and the fix is a
  same-shape port of `board-row-gate.sh`'s already-working `.cwd`-preferring pattern, not a novel
  mechanism; excluding it would still leave it anchored-but-wrong for the CDDIR-relative case
  specifically, since the wrapper's `cd` still runs before it either way.
- DEC-G: Both dwarves-kit dispatch tables (`hooks/hooks.json`, root `settings.json`) are rewritten
  and both are checked by the same lint. Rationale: ADR-0009 already commits to keeping them in
  sync manually until sunset; fixing only one would silently un-fix the bash-install path the
  moment a consumer used it, and the lint would give a false green by only ever checking the file
  this spec happened to remember.
- DEC-H: `lib/adopt.sh`'s wired-hook diagnostic gets one line added (`grep -v` excluding
  `anchor-root.sh`), not left as a cosmetic wart. Rationale: the drift-detection BOOLEAN it feeds
  stays correct either way, but the printed message is read by a human running `install.sh`/adopt,
  and a phantom "hook" with no owning module would be confusing noise every single run, forever,
  for a one-line fix.

## Open questions
(none)
