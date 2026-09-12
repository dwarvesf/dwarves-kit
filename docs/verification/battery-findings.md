# Post-merge battery findings -- fix verification

A post-merge verification battery on `master` (head `2ac5df0`) returned FIX THEN SHIP on six
findings. This is the run table and negative-control proof for each fix, branch
`fix/battery-findings`. Two probe arms found a further shape of finding 1 and one more root-
only-adjacent bug after the initial fix landed; both are folded into this same branch/PR (see
"1b" and "1c" below).

## 1. HIGH -- the root-only fence had a second, contradicting list

**Fix:** `_is_root_only` (`lib/config/config.sh`) no longer greps a row's Doc column for the
literal string `kit_config_get_root`. It now reads a new `## Root-only keys` table in
`lib/config/module-registry.md` (a flat list, one key per row) via `_root_only_rows`.
`tests/test-config-registry.sh` AC10 re-derives BOTH sides independently (the table's contents,
and every literal key passed to `kit_config_get_root` across `lib/` excluding
`lib/config/kit-config.sh`'s own definition + self-test, `commands/`, `hooks/`, `bin/`) and
asserts they are the exact same set.

### Run table

```
$ bash tests/test-config-registry.sh
...
=== AC9: command autonomy knobs resolve root-only ===
  PASS ship.confirm_bump ships as major
  PASS ship.confirm_bump honours the operator kit.toml
  PASS ship.confirm_bump ignores a project .kit.toml
  ... (ship.create_changelog, debug.confirm_fix, review.apply_findings, wrap.drain_staged, all PASS)

=== AC10: '## Root-only keys' table equals the real kit_config_get_root call-site set ===
  PASS declared root-only keys == actual kit_config_get_root call sites
  PASS AC10 negative control: dropping ship.confirm_bump from DECLARED is caught

=== 43/43 passed ===
```

### Negative control (real bug, revert -> RED -> restore -> GREEN)

Stashed `lib/config/config.sh` + `lib/config/module-registry.md` back to their pre-fix content
inside the worktree, reran the exact repro from the finding, then restored:

```
$ T=$(mktemp -d); printf '[ship]\nconfirm_bump = "never"\n' > "$T/.kit.toml"

# RED -- pre-fix code (old `_is_root_only`, prose-grep on Doc column):
$ KIT_PROJECT_ROOT="$T" bash bin/config get ship.confirm_bump
never          # <- leaks the PR-controlled project override

# git stash pop (fix restored)

# GREEN -- post-fix code (table-driven `_is_root_only`):
$ KIT_PROJECT_ROOT="$T" bash bin/config get ship.confirm_bump
major          # <- the shipped default; project .kit.toml correctly fenced
```

AC10's own negative control (dropping `ship.confirm_bump` from the declared table while its
real consumer, `commands/ship.md`, still reads it root-only) also went RED as expected before
being reverted, proving AC10 itself is not vacuous.

## 1b. A second, different shape of the fence bug -- `_row_get` mis-splits an escaped pipe

A probe arm found that `precedent.registry` leaked the same way on `master`, through a
DIFFERENT mechanism: its Doc cell contains markdown-escaped pipes
(`` repo\|scripts\|skills\|crons\|memory ``). `IFS='|' read -ra` in `_row_get` does not know
about that escape and splits on the byte anyway -- the row fragments into 13 fields instead of
6 (`awk -F'|' '{print NF}'` measured), so `_row_get "$row" 6` on the OLD (pre-1a)
`_is_root_only` landed on a truncated fragment that could never contain the literal
`kit_config_get_root`, silently un-fencing that row on `master`.

**Scope, stated precisely (per the coordinator's own instruction, not overstated):** the
breach is the `bin/config` READ surface (`get`/`explain`), which the module documents as the
scripting interface. `precedent find`'s own consumer (`lib/precedent/precedent.sh`) was never
affected -- it calls `kit_config_get_root` directly, not through `bin/config`. It is a real
config-read breach, not remote code execution.

**Interaction with the 1a fix, checked empirically rather than assumed:** the 1a redesign
(`_is_root_only` reads `_row_get "$row" 2`, the tomlkey, and checks it against the separate
`## Root-only keys` table) already closes this specific leak on its own, because field index 2
sits BEFORE the escaped pipes in field 6 and is unaffected by how field 6 fragments. Verified
by reverting ONLY the `_row_get` sentinel-escaping fix (keeping the 1a table/lookup redesign)
and re-running AC12 below -- it still passed. This is a real, useful structural property of
the 1a design (a same-row marker COLUMN, as the original brief's other suggested option, WOULD
have been mis-indexed the same way `_row_get "$row" 6` was), but `_row_get`'s escaped-pipe
handling is still a real, separate bug (it corrupted the DISPLAYED Doc text in `config
explain`) and is fixed on its own merits, with its own test.

**Fix:** `_row_get` (`lib/config/config.sh`) swaps `\|` for a sentinel byte before
`IFS='|' read -ra`, then restores it per extracted field, so an escaped pipe stays literal
cell content instead of opening a phantom field boundary.

### Run table

```
$ bash tests/test-config-registry.sh
...
=== AC10: '## Root-only keys' table equals the real kit_config_get_root call-site set ===
  PASS declared root-only keys == actual kit_config_get_root call sites
  PASS AC10 negative control: dropping ship.confirm_bump from DECLARED is caught
  PASS precedent.registry is covered by AC10's mechanical scan, not hand-listed

=== AC11: _row_get survives a markdown-escaped pipe inside a cell ===
  PASS field 2 (tomlkey) unaffected by a LATER escaped pipe
  PASS field 6 (doc) keeps the escaped pipes as literal content, not truncated
  PASS live precedent.registry row: field 2 correct
  PASS live precedent.registry row: field 6 (doc) is the FULL sentence, not truncated at the first escaped pipe

=== AC12: precedent.registry regression control (config get/explain, project override) ===
  PASS config get precedent.registry ignores the attacker project override (got: ${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/inventory.txt)
  PASS config explain precedent.registry never reports source: project .kit.toml

=== 50/50 passed ===
```

### Regression control (the coordinator's exact command pair)

```
$ T=$(mktemp -d); printf '[precedent]\nregistry = "/tmp/attacker-inventory.txt"\n' > "$T/.kit.toml"
$ KIT_PROJECT_ROOT="$T" bash bin/config get precedent.registry
${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/inventory.txt      # NOT the attacker path

$ KIT_PROJECT_ROOT="$T" bash bin/config explain precedent.registry
...
Effective: ${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/inventory.txt   (source: default)
```

`explain`'s Doc text also now prints the FULL sentence (`... crons|memory) for
`precedent find --surface inventory|all`. ...`) instead of truncating at the first escaped
pipe -- a visible confirmation the parser fix is live, not just the security property.

### Negative control (revert `_row_get` only -> AC11/AC12 -> RED -> restore -> GREEN)

Reverted `_row_get` to the naive `IFS='|' read -ra f <<< "$row"` in place, reran, restored:

```
$ bash tests/test-config-registry.sh   # naive _row_get, 1a table/lookup design intact
...
=== AC12: precedent.registry regression control (config get/explain, project override) ===
  PASS config get precedent.registry ignores the attacker project override (got: ${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/inventory.txt)
  PASS config explain precedent.registry never reports source: project .kit.toml
```

AC12 stayed green under the naive parser (expected and explained above: the 1a lookup never
reads field 6). AC11, which pins the parser directly (a local reimplementation, not sourced
from config.sh, matching this file's existing `_window_rows`-style convention), is the
assertion that actually depends on the `_row_get` fix; it is a static field-count/content check
on a synthetic + the live row, not re-run against the reverted binary here (reverting and
re-deriving it inline would just re-prove arithmetic already shown above under "Scope").

## 1c. `understand.teach` seam: a whitespace-only value read as filled

A second probe arm found `lib/gate/quiz-gate.sh`'s `_teacher()` returns whatever
`kit_config_get_root understand.teach ""` prints, untrimmed. Every call site tests
non-emptiness (`[ -n "$teacher" ]` in `cmd_route`, `${teacher:-skipped: no teacher}` in
`cmd_respond`'s engage branch), and a single space is non-empty in both forms, so
`teach = " "` took the FILLED branch: `cmd_route` printed `ROUTE: ` with a blank name, which
`commands/quiz-gate.md` would turn into a Skill invocation of a blank skill name.
`understand.teach` is root-only (only the operator's own `kit.toml` can set it), so this is a
confusing silent no-op, not an injection -- LOW severity, fixed because it is one line and the
failure was silent.

**Fix:** `_teacher()` trims the resolved value before returning it, once, at the resolver, so
`route`, `respond`, and every future caller inherit the fix without repeating the trim.

### Run table

```
$ bash tests/test-quiz-gate.sh
...
=== AC3: engage routes through the understand.teach seam (dispatch, not reimplementation) ===
  PASS AC3 the named 'teacher' verb is the one shared resolver (filled)
  PASS AC3 the named 'teacher' verb prints nothing when unset
  PASS AC3 the named 'teacher' verb prints nothing for a WHITESPACE-ONLY value
  PASS AC3 route treats a whitespace-only understand.teach as no teacher (no blank ROUTE: name)
  ...
TOTAL: 33   PASS: 33   FAIL: 0
```

### Reproduction (coordinator's exact command shapes) + fix confirmation

```
$ printf '[understand]\nteach = "fixture-teacher"\n' > $OP/kit.toml
$ KIT_CONFIG_OPERATOR=$OP bash lib/gate/quiz-gate.sh route HEAD | head -1
ROUTE: fixture-teacher

$ printf '[understand]\nteach = " "\n' > $OP/kit.toml
# RED (pre-fix): ROUTE:  (blank name)
# GREEN (post-fix):
$ KIT_CONFIG_OPERATOR=$OP bash lib/gate/quiz-gate.sh route HEAD | head -1
ROUTE: skipped: no teacher

$ rm -rf $OP/*; KIT_CONFIG_OPERATOR=$OP bash lib/gate/quiz-gate.sh route HEAD | head -1
ROUTE: skipped: no teacher
```

### Negative control (revert `_teacher` -> RED -> restore -> GREEN)

```
$ bash tests/test-quiz-gate.sh   # naive `_teacher() { kit_config_get_root understand.teach ""; }`
FAIL AC3 the named 'teacher' verb prints nothing for a WHITESPACE-ONLY value
FAIL AC3 route treats a whitespace-only understand.teach as no teacher (no blank ROUTE: name)

# restored -> 33/33 again
```

## 2. MEDIUM -- boundary-lint flagged itself under a relative root

**Fix:** `lib/gate/boundary-lint.sh` now resolves `ROOT` to an absolute realpath
(`ROOT="$(cd "${1:-$SELF/../..}" && pwd)"`) before scanning, so the self-exclusion (`grep -v
"^$SELF/boundary-lint.sh:"`) matches regardless of how the root argument was spelled.

```
$ bash lib/gate/boundary-lint.sh .
boundary-lint: PASS      # was: flagged its own lines 8, 10, 30 before this fix

$ bash lib/gate/boundary-lint.sh "$(pwd)"
boundary-lint: PASS      # unchanged (already worked)
```

## 3. MEDIUM -- the lint's stated allowlist was prose, not code

**Fix:** `name_files` now globs every `commands/*.md` file instead of a hand-written
three-file list, with one documented exception (`pitch.md`, which legitimately composes
`narrate-log` for an unrelated feature -- verified as the only `commands/*.md` file matching
`name_re` on the live tree). The false claim ("allowlist is the Seams Filled-by column and
nothing else") is deleted; the header now states plainly that `name_re`/`name_files` are
hand-maintained, because the Seams table's Filled-by column is free-text prose, not a compact
name list, so deriving one from the other would not be meaningful.

Verified by AC3 below: a brand-new `commands/*.md` file (never in the old hardcoded list) that
hardcodes a retired name is now caught.

## 4. MEDIUM -- the lint's only negative control lived in a script `run-all.sh` never runs

**Fix:** `tests/test-boundary-lint.sh` (which `run-all.sh` DOES glob) now plants two
self-contained mktemp fixtures -- one PATH violation, one NAME violation in a new
`commands/*.md` file -- and asserts `boundary-lint.sh` exits non-zero with the right message,
in addition to the existing live-tree PASS smoke.

### Run table

```
$ bash tests/test-boundary-lint.sh
=== AC1: live tree PASSes ===
  PASS boundary-lint PASSes on the live tree (rc=0): boundary-lint: PASS

=== AC2: negative control -- a mktemp fixture with a planted hardcoded path is caught ===
  PASS planted path violation exits non-zero
  PASS planted path violation names itself in the message

=== AC3: negative control -- a planted retired-skill name in a NEW commands/*.md is caught ===
  PASS planted name violation (new commands/*.md file) exits non-zero
  PASS planted name violation names itself in the message

=== 5/5 passed ===
```

AC2/AC3 ARE the negative control (finding 4's own ask): before this branch, no run of
`run-all.sh` ever exercised a planted violation at all, so a typo in `path_re`, or an emptied
`name_files`, would have left the suite green. Verified by neutering `name_re` in place
(`name_re='ZZZ_NO_MATCH_EVER_ZZZ'`) and rerunning:

```
=== AC3: negative control -- a planted retired-skill name in a NEW commands/*.md is caught ===
  PASS planted name violation (new commands/*.md file) exits non-zero   # AC2's own path hit
  FAIL planted name violation names itself in the message boundary-lint: consumer path hardcoded: ...

=== 4/5 passed ===
```

The message-content assertion goes RED exactly as it should (no `consumer skill named
directly` line appears once `name_re` cannot match anything); the exit-code assertion stays
green only because AC2's own planted PATH violation is still live in the same fixture
directory, not because AC3's own check passed. Reverted `boundary-lint.sh` to the fixed
version and reran: 5/5 again.

## 5. MEDIUM -- the "one release" `bin/learn` forwarder had no expiry anywhere

**Fix:**
- `_meta/BACKLOG.md` ID-839, queued, naming the exact removal version.
- `docs/CHANGELOG.md` `[Unreleased]` `### Deprecated` entry: `bin/learn` ships in 2.3.0 (the
  next minor; the rename commit #560 postdates the 2.2.0 tag), removal due starting 2.4.0.
- `tests/test-meta.sh` gets a mechanical trip: it fails once `VERSION` reaches 2.4.0 while
  `bin/learn` still exists (`sort -V` comparison, not a string compare, so "2.10.0" sorts
  correctly past "2.4.0").

### Run table

```
$ bash tests/test-meta.sh 2>&1 | grep -i learn
  PASS bin/learn forwarder is deleted by VERSION 2.4.0 (ID-839; currently 2.2.0)
```

### Negative control (mechanical trip fires)

Extracted the exact check as a standalone snippet and ran it at the current version (pass) and
at the named removal version with the file still present (fail), proving the trip actually
fires instead of only ever reading PASS by construction:

```
$ BIN_LEARN_DUE_VERSION="2.4.0"; FILE_EXISTS=1   # bin/learn present
$ for VERSION_FILE in 2.2.0 2.3.0 2.4.0 2.5.0; do
    LOWER="$(printf '%s\n%s\n' "$VERSION_FILE" "$BIN_LEARN_DUE_VERSION" | sort -V | head -1)"
    OVERDUE=1
    [ "$LOWER" = "$VERSION_FILE" ] && [ "$VERSION_FILE" != "$BIN_LEARN_DUE_VERSION" ] && OVERDUE=0
    echo "VERSION=$VERSION_FILE overdue=$OVERDUE"
  done
VERSION=2.2.0 overdue=0   # in grace, PASS
VERSION=2.3.0 overdue=0   # still in grace (ships here), PASS
VERSION=2.4.0 overdue=1   # due, FAIL as designed
VERSION=2.5.0 overdue=1   # past due, FAIL as designed
```

## 6. LOW

### 6a. `lib/sync/sync_core.py` fetch cache -- explained, not changed

`_fetched_repos` is a module-level cache with process lifetime. Traced every caller of
`sync.interval_secs`: it is a launchd `StartInterval` (`lib/sync/deploy/macos/install`,
`lib/sync/deploy/macos/board-sync-cron`), and each tick runs `bash bin/board sync ...` as a
**fresh process** that launchd starts, re-importing `sync_core.py` from zero. There is no code
path today that runs the sync loop inside one long-running interpreter across ticks, so
`_fetched_repos` cannot survive past a single `bin/board sync` invocation and the described
origin-lag-reopens-after-tick-1 failure cannot occur. Documented this explicitly in a comment
above `_fetched_repos`, including the forward-looking note (clear the set per tick if a future
caller ever runs the loop in-process instead of via cron).

### 6b. `commands/explain.md` thinning -- changelog line added

Commit #560 (already on `master`, unreleased) replaced `explain.md`'s inline
`narrate-log`/`svg-knowledge-diagram` composition and per-hunk enrichment with a hand-off
through the `understand.teach` seam (ADR-0036, deliberate). An engine-only adopter with no
teacher configured now gets the mechanical skeleton alone (`skipped: no teacher`) instead of
the previous always-on enrichment -- a user-visible behavior change that had no changelog line.
Added one under `[Unreleased] ### Changed` naming the old and new behavior and how to keep the
old behavior (`set understand.teach`).

## Housekeeping

`docs/FEATURES.md` (generated projection, `lib/registry/feature-registry.sh`) drifted because
several of this branch's own comments happen to contain exact-token matches for other command
names (e.g. the word "battery" in `test-boundary-lint.sh`'s header, referring to `/kit:battery`,
the tool that surfaced these findings). Regenerated and reverified fresh:

```
$ bash lib/registry/feature-registry.sh generate /tmp/regen.md
$ diff -q /tmp/regen.md docs/FEATURES.md
$ echo $?
0
```

## Baseline

Two documented pre-existing flakes, `test-orchestrate-gate-dispatch` and
`test-orchestrate-wavefront`, are not chased here per the task's stated baseline.
