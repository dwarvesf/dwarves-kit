# Spec: one repo-root anchor for every dwarves-kit hook, across both dispatch tables
Generated: 2026-09-28
Status: VALIDATED
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
export DWARVES_KIT_INVOCATION_CWD="$PWD"
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

**`DWARVES_KIT_INVOCATION_CWD`**: exported BEFORE the `cd`, so it always carries the hook's true
invocation directory, the same value `$PWD` would have held with no anchor at all. `export`
means the wrapped hook process inherits it (through the `exec`, environment survives). This
gives any hook a source of truth for "where was I really invoked" that does not depend on
Claude Code's JSON payload carrying a `.cwd` field for that event, since the anchor itself
guarantees it whenever a hook runs through the wrapper. `ship-gate.sh` uses it as a second-tier
fallback below; any other hook needing the same thing can read it directly, without adding its
own indirection. It is unset (empty) for a hook invoked directly, bypassing both dispatch tables
and the wrapper, exactly as today's test suite already does for most existing cases.

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
  ...`.

**A real, not cosmetic, difference for the `settings.json` path, stated plainly rather than
waved away as "identical":** today, `settings.json`'s literal `bash $HOME/.../hooks/<name>.sh`
form runs the INNER hook under whatever `bash` resolves FIRST on PATH (potentially a newer
Homebrew bash). After this rewrite, the outer `bash` invokes only `anchor-root.sh`; the INNER
hook is reached via `anchor-root.sh`'s own `exec "$@"`, which runs it as a PROGRAM, i.e. under
ITS OWN SHEBANG line (`#!/bin/bash`, macOS system bash 3.2, for most hook files; `#!/usr/bin/env
bash`, PATH-resolved, for the rest), never under an explicit `bash` prefix for that inner script
anymore. This is exactly how `hooks/hooks.json`'s OWN path has ALWAYS invoked hooks (no explicit
`bash` prefix there today either), so it is a CONVERGENCE toward the plugin path's existing
behavior, not a new risk in shape. It is only safe in practice, not identical: we grepped every
`hooks/*.sh` file for bash-4-only constructs (associative arrays, `readarray`/`mapfile`,
`${var,,}`/`${var^^}` case-conversion expansion, `**` globstar) and found none, the two apparent
hits (`ship-gate.sh`, `batch-debt-warn.sh`) are Markdown bold syntax inside a comment and a `jq`
string literal, not bash glob syntax. Running under bash 3.2 is confirmed safe for this codebase
today; a future hook that DOES use bash-4-only syntax and is wired only into `settings.json`
(never `hooks.json`) would need `#!/usr/bin/env bash`, not `#!/bin/bash`, to keep working, exactly
as it already would without this change.

**Scope boundary, stated rather than silently missed:** the rewrite and `tests/test-hook-anchor.sh`
(below) cover `.hooks.*` entries in both files only. Root `settings.json` also carries a
top-level `statusLine.command` key (`bash $HOME/.claude/dwarves-kit/hooks/statusline.sh`), a
separate dispatch mechanism outside `.hooks`, not touched here and not checked by the lint.
`statusline.sh` has no cwd-relative read at all (grepped, none found), so leaving it unanchored
is harmless; it is named here so its absence from the rewrite reads as a decision, not a gap.

No other field in any `.hooks.*` entry, in either file, changes. `tests/test-hook-anchor.sh`
(below) checks BOTH files' `.hooks.*` entries, so the two dispatch tables cannot drift back out
of sync with each other on this one axis even though nothing else keeps them in sync.

### Rejected alternatives

- **A two-line anchor pasted into every hook file** (or the same idea factored as a helper each
  hook `source`s at its own top). Rejected, not because it is unlintable, a lint could grep every
  `hooks/*.sh` for the required line just as easily as it greps the two dispatch tables, but
  because it defaults OFF: a brand-new hook file is unanchored the moment it is created, and
  stays that way until either its author remembers the line or a lint happens to run and catch
  the omission. A dispatch-table wrapper defaults ON the moment a hook is wired in at all. See
  `## Design`, "Why a wrapper beats a per-hook convention", for the full restatement.
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

Seven hooks already resolve their own root the same way, independently, before this spec:
`ship-gate.sh` and `commit-format.sh` (`git rev-parse --show-toplevel`, falling back to their own
`$PWD`/`pwd`), `anti-rationalization.sh` (the IDENTICAL pattern, for its own `understanding_gate`
policy-config lookup, a separate line from the `.claude/debug` check this spec fixes in the same
file), `codebase-index.sh` (identical pattern), and `harvest.py`, `backlog-stage.py`,
`intake-sweep.py` (each has its own `_repo_root()` doing the same git call, falling back to
`os.getcwd()`). The anchor consolidates a pattern this codebase already reinvented seven times
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
`.cwd` over its own `$PWD` for the identical reason, extended with the anchor's own
`DWARVES_KIT_INVOCATION_CWD` as a second-tier fallback, see `## Solution`, "The anchor"):

- Add, right after `INPUT=$(cat)`, a three-tier fallback: the payload's `.cwd` first (Claude
  Code's own authoritative value when present), then the anchor-provided
  `DWARVES_KIT_INVOCATION_CWD` (guaranteed set whenever the hook runs through the wrapper,
  independent of whether this particular event's payload happens to carry `.cwd`), then bare
  `$PWD` last (for the case the hook runs outside both dispatch tables and the wrapper entirely,
  e.g. a direct manual invocation):
  ```sh
  REAL_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [ -n "$REAL_CWD" ] || REAL_CWD="${DWARVES_KIT_INVOCATION_CWD:-}"
  [ -n "$REAL_CWD" ] || REAL_CWD="$PWD"
  ```
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
| `auto-format.sh` | `tool_input.file_path` is absolute, so the file it formats is unaffected. Caveat: `find_prettier()`'s `./node_modules/.bin/prettier` probe is cwd-relative, so a monorepo package's own local prettier is no longer found from a package subdirectory once anchored; the hook then falls back to a global `prettier` or skips. Advisory-only (exits 0 always), accepted, see the audit above |
| `context-hints.py`, `notification.sh`, `permission-auto-approve.sh`, `output-offload.sh` | No cwd/pwd/`getcwd()` reference found in any of the four |

**Table 3: needed a scoped code fix to keep working correctly under the anchor**

| Hook | Fix |
|---|---|
| `ship-gate.sh` | See "ship-gate.sh needs its own scoped fix" above |

**Excluded from the anchor entirely:**

| Hook | Reason |
|---|---|
| `secrets-guard.sh` | See the audit table above, "Two hooks came out of this audit relying on the REAL invocation cwd on purpose"; a security-relevant, on-purpose dependency on the real invocation cwd |

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

### tests/test-install-modules.sh and tests/test-adopt.sh: one needs the same filter, one is safe

Both test files re-implement the identical `wired_hooks()` extraction shape as `lib/adopt.sh`
(`grep -oE '...hooks/[A-Za-z0-9._-]+\.sh' | sed 's#...hooks/##' | sort -u`), so both will ALSO
now see `anchor-root.sh` in their extracted set. They use it differently:

- `tests/test-install-modules.sh`'s `wired_hooks()` feeds THREE assertions
  (`WIRED1`/`WIRED2`/`WIRED6`) that compare the FULL extracted set against a fixed expected list
  by EXACT STRING EQUALITY (`[ "$WIRED1" = "$EXPECT_SPINE" ]`, and similarly for the board and
  prune cases). `anchor-root.sh` appearing as an extra, unexpected line breaks all three. **Fix**:
  add the same `| grep -v '^anchor-root\.sh$'` (matching the BARE filename, since this helper
  already strips the `hooks/` prefix before the comparison) to `wired_hooks()` in this file.
- `tests/test-adopt.sh`'s own `wired_hooks()` (line 109) feeds only `grep -qx <one-hook-name>`
  (membership: does the set CONTAIN X) and `! grep -qx <one-hook-name>` (does it NOT contain Y)
  checks, never a full-set equality. An extra, unrelated line in the set does not change whether
  any ONE named hook is present or absent. Verified by reading every call site; no code change.

### Codex trust pins (hooks/codex-hooks.json)

`hooks/codex-hooks.json` pins the sha256 content hash of five hooks (`codex-hook-adapter.sh`
itself, plus `safety-gate.sh`, `ship-gate.sh`, `commit-format.sh`, `secrets-guard.sh`,
`anti-rationalization.sh`), each command inline-checking
`hash_file ".../hooks/<name>.sh" | grep -q '^<sha256> '` before it will `exec` the adapter, and
refusing (`exit 2`, "trusted hook content changed") on a mismatch. This is a SEPARATE, Codex-only
trust mechanism (per AGENTS.md, enforcement is Claude-Code-only; Codex has its own narrower
boundary, `docs/architecture.md`, "Hook fallback layer"); `codex-hooks.json` is NOT rewritten with
the anchor (Codex anchoring stays out of scope, see `## Out of Scope`), and none of its own
commands change. But TASK-C3 changes `hooks/ship-gate.sh`'s CONTENT (the `REAL_CWD` fix), which
makes its pinned hash stale: `tests/test-codex-hooks.sh` would fail, and at runtime the Codex
trust command would `exit 2` on every use of `ship-gate.sh` until the pin is refreshed. **Fix**:
after TASK-C3 lands, run `bash lib/codex/repin.sh` (recomputes every pin, rewrites
`codex-hooks.json` in place; a no-op for the four unchanged files, since their content does not
change in this spec), then `bash lib/codex/repin.sh check` to confirm every pin is fresh before
committing.

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

### Failure modes

| Failure | Effect | Mitigation |
|---|---|---|
| `anchor-root.sh` missing, or present without its executable bit | Every anchored entry exits 126 (not executable) or 127 (not found) before the real hook runs. Claude Code treats any exit other than 2 as non-blocking, so every gate (safety-gate, ship-gate, commit-format, ...) goes dark silently instead of failing loud | `tests/test-meta.sh:147` asserts every `hooks/*.sh` carries the exec bit (it globs `anchor-root.sh` in automatically); `install.sh:483` copies every `hooks/*.sh` and runs `chmod +x` on each copy; test case 7 asserts no entry in either table exits 126/127 |

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
                               v
                    export DWARVES_KIT_INVOCATION_CWD="$PWD"   (true cwd, saved BEFORE the cd)
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

 ONE hook needed its own scoped fix, not just the wrapper: ship-gate.sh resolves REAL_CWD
 and uses it for a relative embedded `cd <path>` and for its no-cd ROOT fallback, instead of
 trusting its own (now possibly anchored) $PWD, the same pattern board-row-gate.sh used:

   payload .cwd --empty--> $DWARVES_KIT_INVOCATION_CWD --empty--> $PWD
        |                          |                                 |
        +--------------------------+---------------------------------+
                                   v
                               REAL_CWD
                                   |
             relative CDDIR -> "$REAL_CWD/$CDDIR";  no CDDIR -> git -C "$REAL_CWD"

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

**Why a wrapper beats a per-hook convention, stated honestly**: a per-hook `source`d anchor line
IS just as lintable, mechanically, as a dispatch-table prefix, a test could grep every
`hooks/*.sh` file for a required `source .../anchor-lib.sh` near its top exactly the way
`tests/test-hook-anchor.sh` greps the two dispatch tables. That is not the real tradeoff. The
real tradeoff is DEFAULT behavior BEFORE any lint runs: a per-hook convention is opt-IN per file,
a brand-new hook that never adds the `source` line is UNANCHORED until a lint happens to catch it
after the fact. A dispatch-table wrapper is opt-OUT per entry: a brand-new hook, the moment it is
wired into `hooks.json`/`settings.json` at all, is anchored BY DEFAULT, and would need someone to
deliberately strip the prefix to NOT be. Both are equally checkable after the fact; only one of
them fails safe before the check ever runs. The operator chose default-on for that reason.

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
- [x] TASK-B: Add `hooks/anchor-root.sh` per `## Solution`, committed with the executable bit set
  (mode 100755).
- [x] TASK-C: Rewrite every `command` entry in `hooks/hooks.json` per `## Solution`, "Two
  dispatch tables", except `secrets-guard.sh`'s entry (left unchanged).
- [x] TASK-C2: Rewrite every `command` entry in the root `settings.json` the same way, same
  exception.
- [x] TASK-C3: Apply the scoped `ship-gate.sh` fix per `## Solution`, "ship-gate.sh needs its own
  scoped fix" (the three-tier `.cwd` / `DWARVES_KIT_INVOCATION_CWD` / `$PWD` fallback).
- [x] TASK-C4: In `lib/adopt.sh`, add `| grep -v '/anchor-root\.sh$'` to the `before_wired` and
  `after_wired` extraction lines per `## Solution`, "install.sh and lib/adopt.sh".
- [x] TASK-C5: After TASK-C3 lands, run `bash lib/codex/repin.sh` then `bash lib/codex/repin.sh
  check` per `## Solution`, "Codex trust pins", so `hooks/codex-hooks.json`'s stale
  `ship-gate.sh` pin is refreshed before commit.
- [x] TASK-C6: In `tests/test-install-modules.sh`, add `| grep -v '^anchor-root\.sh$'` to
  `wired_hooks()` per `## Solution`, "tests/test-install-modules.sh and tests/test-adopt.sh".
  `tests/test-adopt.sh` needs no change (verified, membership-only checks).
- [x] TASK-D (depends on TASK-C, TASK-C2): Add `tests/test-hook-anchor.sh` (new, a sibling of `tests/test-hooks.sh`, picked up
  by `tests/run-all.sh`'s `tests/test-*.sh` glob): parses BOTH `hooks/hooks.json` and root
  `settings.json`, `.hooks.*` entries only (not the root `statusLine` key, see `## Solution`,
  "Two dispatch tables", scope boundary), asserts every command has the `anchor-root.sh` prefix
  except the one named exemption (a short, commented list, `secrets-guard.sh`), runs the same
  check function first against a small embedded fixture with one entry missing the wrapper
  (proving the checker itself catches a bypass, not merely vacuously true because the real files
  already comply), then against both real files.
- [x] TASK-E1 (depends on TASK-B, TASK-C, TASK-C3): In `tests/test-hooks.sh`, add cases 1-5 of
  `## Test plan` below, each invoking its hook THROUGH the wrapper
  (`bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/<hook>.sh" [args]`), not the bare hook.
  Existing cases that invoke hooks directly are untouched, they test a hook's own internal logic
  and are unaffected by this fix either way, since those fixtures already sit at their own repo
  root.
- [x] TASK-E2 (depends on TASK-B, TASK-C, TASK-C3; the settings.json half of case 7 also reads
  TASK-C2's output): In `tests/test-hooks.sh`, add cases 6a, 6b, 6c, and 7 of `## Test plan`,
  same wrapper-routed shape.
  For both E1 and E2: each assertion's name string MUST include the exact literal substring named
  in `## Test plan` (`subdir with content`, `worktree keeps own state`, `writer/reader pair`,
  `relative cd resolves`, `payload cwd resolves root`, `smoke exec`), matching, verbatim, what
  the negative controls below grep for; a test written with a different label silently breaks
  NC1/NC3's scoping.
- [x] TASK-E3: Docs projection per `## Solution`, "Docs projection": one new row each in
  `docs/architecture.md`'s Hook fallback layer table and `README.md`'s Hooks table, then
  `bash lib/registry/feature-registry.sh generate` to refresh `docs/FEATURES.md`.

### Phase 3: Polish
- [x] TASK-F: Commit TASK-B through TASK-E3, then run all three negative controls in
  `## Test plan` (bottom) and confirm each goes RED under its mutation, then GREEN again
  restored.

## After state
- [ ] Every hook in Table 1 reads and writes relative to the repo/worktree root when dispatched
  through either table, regardless of which subdirectory the session's cwd is in. (Today:
  relative to whatever subdirectory the session happens to sit in.)
- [ ] `anti-rationalization.sh`'s guess-fix guard (the `.claude/debug` ledger check) now fires
  correctly from a subdirectory session, where today it silently never finds a real ledger sitting
  at the root.
- [ ] `ship-gate.sh` resolves a relative embedded `cd <path>` against the tool's real invocation
  cwd (the payload's `.cwd`, falling back to the anchor-provided `DWARVES_KIT_INVOCATION_CWD`
  when `.cwd` is absent), not against its own (possibly anchored) `$PWD`, so a cross-repo
  `cd ../other-repo && git push` still gates `other-repo`, not the session repo.
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
- [ ] `hooks/codex-hooks.json`'s trust pin for `ship-gate.sh` matches its new content;
  `tests/test-codex-hooks.sh` and `bash lib/codex/repin.sh check` both pass.
- [ ] Every existing assertion in `tests/test-hooks.sh`, `tests/test-install-modules.sh`, and
  `tests/test-adopt.sh` still passes. (The assertions stay as written; only
  `tests/test-install-modules.sh`'s shared `wired_hooks()` helper gains the TASK-C6 filter.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] The nine new `tests/test-hooks.sh` cases pass: cases 1-5 (session-state
  subdirectory-with-content, session-state worktree, session-state outside-repo confirmation
  (wrapper-routed), pre-compact-backup subdirectory, post-compact-reinject writer/reader pair),
  cases 6a/6b/6c (ship-gate relative-cd cross-repo resolution via the payload `.cwd` and via the
  `DWARVES_KIT_INVOCATION_CWD` fallback, plus the no-cd `git -C "$REAL_CWD"` ROOT fallback), and
  case 7 (the every-entry smoke test over both dispatch tables).
- [ ] `tests/test-hook-anchor.sh` passes: every entry in both `hooks.json` and `settings.json` is
  wrapped except the one named exemption, and its embedded bypass fixture is correctly flagged.
- [ ] No regression in existing `tests/test-hooks.sh`, `tests/test-meta.sh`,
  `tests/test-install-modules.sh`, `tests/test-adopt.sh`, or `tests/test-codex-hooks.sh` cases.
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
   name). Assert exactly what `NOGIT2` already asserts, no more: the written `last-state.md` does
   NOT mention the fixture's `orphan.py` file (the recent-files SCAN is skipped outside a work
   tree; a `last-state.md` file is still written, since `STATE_DIR`/`STATE_FILE` are not
   themselves gated on being inside a repo). Proves the `ROOT="... || $PWD"` fallback plus the
   no-op `cd "$PWD"` keep this path identical when routed through the wrapper.
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
   anchored `$PWD` ("relative cd resolves").** A parent directory `PARENT` (`mktemp -d`)
   containing two sibling repos: `PARENT/session-repo/` (`git init -q`, one commit, a
   subdirectory `session-repo/sub/`) and `PARENT/other-repo/` (`git init -q`, one commit).
   - **6a, via payload `.cwd`.** Payload: `{"cwd":"<PARENT>/session-repo/sub","tool_input":
     {"command":"cd ../../other-repo && git push origin feat/x"}}` (the relative path
     `../../other-repo`, from `sub/`, correctly reaches `PARENT/other-repo`). Run
     `cd "$PARENT/session-repo/sub"` first, so the wrapper anchors `ship-gate.sh`'s own `$PWD`
     to `session-repo`'s root (NOT `other-repo`, matching what the anchor does today for a
     same-repo subdirectory), then pipe the payload with `DWARVES_KIT_PRINT_CDDIR=1` into
     `bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/ship-gate.sh"`. Assert, in order:
     the printed CDDIR is ABSOLUTE (`case "$RAW_CDDIR" in /*) ;; *) fail ;; esac`, so a
     relative value that happens to resolve from the test's own cwd cannot pass); then
     canonicalize BOTH the printed CDDIR and the expected path through an actual `cd`+`pwd -P`
     round trip started from a NEUTRAL directory, never the fixture's own tree
     (`OUT_CANON=$(cd / && cd "$RAW_CDDIR" && pwd -P)`,
     `EXPECT_CANON=$(cd / && cd "$PARENT/other-repo" && pwd -P)`), and assert `OUT_CANON`
     equals `EXPECT_CANON`, NOT a raw string comparison. `REAL_CWD/CDDIR` is a plain concatenation
     (`.../sub/../../other-repo`), never collapsed by the fix itself (the OS resolves `..`
     segments transparently, so the fix does not need to); a raw string compare against
     `$PARENT/other-repo` would fail even on a correct resolution. Round-tripping both sides
     through `cd`+`pwd -P` collapses the `..` segments AND resolves symlinks (macOS `/tmp` →
     `/private/tmp`) identically on both sides, so the comparison is exact and the earlier
     symlink concern (Edge Cases below) cancels out rather than needing to be reasoned about.
   - **6b, via `DWARVES_KIT_INVOCATION_CWD` (payload `.cwd` absent).** Identical fixture and
     command, but the payload carries NO `.cwd` field at all
     (`{"tool_input":{"command":"cd ../../other-repo && git push origin feat/x"}}`). Same
     assertion as 6a. Proves the anchor's own exported `DWARVES_KIT_INVOCATION_CWD` (see
     `## Solution`, "The anchor") correctly substitutes when the event's payload has no `.cwd`,
     not just when it does.
   - **6c, the `git -C "$REAL_CWD"` fallback branch (no embedded `cd`).** 6a and 6b stop at the
     `DWARVES_KIT_PRINT_CDDIR` early exit, so they never reach the ROOT resolution itself. 6c
     does, with no print affordance set. `PARENT/other-repo` gets a committed
     `_meta/BACKLOG.md` holding one table row that does NOT mention the branch slug, and is
     checked out on branch `feat/anchor-probe`; `session-repo` has no `_meta/BACKLOG.md`.
     Payload: `{"cwd":"<PARENT>/other-repo","tool_input":{"command":"git push origin
     feat/anchor-probe"}}` (no `cd`, so CDDIR is empty and the hook takes the fallback branch).
     Run from `cd "$PARENT/session-repo/sub"` through the wrapper, with `CLAUDE_PLUGIN_ROOT`
     pointed at an empty temp dir (no ledger, no proof lib: every other block fails open, and
     the real `~/.claude` ledger is never read). Assert stderr carries the board-registration
     advisory `appears nowhere in _meta/BACKLOG.md`, which fires only when ROOT resolved to
     `other-repo`, the payload's repo, not the anchored `session-repo`. Label substring:
     `payload cwd resolves root`.
7. **Smoke test: every wired entry in BOTH dispatch tables is exec'able through the wrapper.**
   Broader and shallower than cases 1-6: extract EVERY `.command` string from `hooks/hooks.json`
   via `jq -r '.hooks[][].hooks[].command'` and expand `${CLAUDE_PLUGIN_ROOT}` to `$KIT_DIR`;
   extract every `.hooks` command from root `settings.json` the same way and rewrite the literal
   `$HOME/.claude/dwarves-kit` prefix to `$KIT_DIR` (the settings.json path assumes an installed
   kit; the rewrite points it at this checkout without installing). Run each, one at a time, via
   `sh -c "$EXPANDED"` with a minimal, universal payload (`{"stop_hook_active":true}`, already
   special-cased to a fast exit by most Stop/SubagentStop hooks, and ignored harmlessly by the
   rest) piped on stdin, `cd`'d into a subdirectory of a throwaway repo first. The whole loop
   runs with side effects fenced off: `HOME` points at a throwaway temp dir (no write reaches the
   real `~/.claude`), and a stub directory prepended to `PATH` shadows `osascript`,
   `notify-send`, and `codebase-memory-mcp` with scripts that `exit 0` (no real desktop
   notification, no real index write). Assert the exit code is NEVER 126 (permission denied, not
   executable) or 127 (command not found) for any entry in either table, the shell's own "could
   not even launch the program" codes, never a hook's own logic. This is a plumbing check (right
   paths, the executable bit, correct argument splitting through the wrapper), not a per-hook
   behavior check, covering every wired hook at once instead of only the ones with dedicated
   cases above. Label substring: `smoke exec`.

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
  'bash tests/test-hooks.sh 2>&1 | grep -E "FAIL.*(relative cd resolves|payload cwd resolves root)" && exit 1 || exit 0' \
  'git show afb52d01:hooks/ship-gate.sh > hooks/ship-gate.sh'
```
Reverting just `ship-gate.sh` to its pre-fix content makes case 6 go RED (6a/6b: the printed
CDDIR stays relative and resolves against the anchored `$PWD`, landing on `session-repo`, not
`other-repo`; 6c: the bare `git rev-parse` resolves ROOT to the anchored `session-repo`, so the
BACKLOG advisory never fires); `negctl.sh` then restores the real `ship-gate.sh` and confirms
green again.

## Edge Cases
1. `git rev-parse --show-toplevel` returns the PHYSICAL path (symlinks resolved), not necessarily
   the LOGICAL path a shell's `$PWD` or the payload's `.cwd` would show. On macOS, `/tmp` is
   itself a symlink to `/private/tmp`, so a test fixture created under
   `mktemp -d "${TMPDIR:-/tmp}/..."` sees the anchor's resolved `ROOT` differ, as a STRING, from
   the fixture variable's own `/tmp/...` path, even though both name the same directory. Every
   test assertion above uses existence checks (`[ -f ]`/`[ -d ]`), content checks (`grep`,
   checksums), or, for case 6, a canonical comparison: both the printed CDDIR and the expected
   path go through a `cd` + `pwd -P` round trip (from a neutral directory) before the compare,
   which resolves `..` segments and the `/tmp` symlink identically on both sides. None compares
   a POST-`git rev-parse` absolute path by raw string equality against a `mktemp`-returned path.
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
- **Anchoring Codex's own dispatch** (`hooks/codex-hooks.json` rewritten with the wrapper the way
  `hooks.json`/`settings.json` are): out of scope. It is a separate runtime's wiring (Codex, not
  Claude Code); AGENTS.md already states enforcement is Claude-Code-only. If the same class of
  bug exists there, that is a follow-up, not this spec. **In scope, narrowly**: refreshing
  `codex-hooks.json`'s sha256 trust PIN for `ship-gate.sh`, since TASK-C3 changes that file's
  content and a stale pin would fail `tests/test-codex-hooks.sh` and block the Codex trust
  command at runtime (`bash lib/codex/repin.sh` + `check`, TASK-C5). The pin refresh touches only
  the hex digest already inline in the file; it does not add the anchor to any Codex command.
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
- hooks/codex-hooks.json (regenerated pin only, via `lib/codex/repin.sh`, not hand-edited)
- lib/adopt.sh
- tests/test-hook-anchor.sh (new)
- tests/test-hooks.sh
- tests/test-install-modules.sh
- docs/architecture.md
- README.md
- docs/FEATURES.md (regenerated, not hand-edited)

## Decision Log
- DEC-A: One shared wrapper referenced from both dispatch tables, not a per-hook pasted or
  sourced anchor. Rationale, restated honestly: a per-hook `source` line is equally lintable
  after the fact; the real difference is DEFAULT-ON (a new dispatch-table entry is anchored the
  moment it is wired, opt-out) versus DEFAULT-OFF (a new hook file is unanchored until it
  remembers to opt in). The operator chose default-on.
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
- DEC-F: `ship-gate.sh` gets a scoped, three-line fix (resolve `REAL_CWD` from the payload's
  `.cwd`, then the anchor-exported `DWARVES_KIT_INVOCATION_CWD`, then `$PWD`; join a relative
  CDDIR against it; fall back to `git -C "$REAL_CWD"` instead of bare `git rev-parse`) rather
  than being excluded from the anchor like `secrets-guard.sh`. An excluded entry never passes
  through the wrapper at all, so exclusion WOULD also keep today's behavior intact. The real
  tradeoff: exclusion costs no hook code change, no Codex trust repin, and no NC3, but leaves
  `ship-gate.sh` correct only by the accident of its own `$PWD`, and adds a second named
  exemption to the lint. The fix makes `ship-gate.sh` resolve the pushed repo from the payload's
  `.cwd` whether or not the wrapper runs (a hardening that holds under a direct invocation, the
  anchored path, and any future dispatcher that changes `$PWD`), keeps the exemption list at one
  entry, and ports `board-row-gate.sh`'s already-working `.cwd`-preferring pattern rather than
  inventing a mechanism. The operator chose the fix; its costs are the repin (TASK-C5) and NC3.
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
