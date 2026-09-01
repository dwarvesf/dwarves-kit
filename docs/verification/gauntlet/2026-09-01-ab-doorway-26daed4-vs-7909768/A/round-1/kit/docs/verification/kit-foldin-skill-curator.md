# Proof of done: kit-foldin SG-04, skill-curator

Sub-goal: `ops-toolkit/_meta/megagoals/kit-foldin/goals/04-skill-curator.md`.
Moves `ops-toolkit/tools/cc-self-improve/` to `dwarves-kit/tools/skill-curator/`, renamed off
"self-improve" (reads as recursive-on-itself), plus one env-default flip and one skill promotion.

## Acceptance criteria (from the goal file)

1. The 11 existing tests pass at identical count post-move.
2. NC: unset `CC_SI_MEMORY_LEDGER`, invoke the ledger path, assert a clean error (not a silent
   write, not a confusing crash trace).
3. `grep -r 'workspace/<owner>' tools/skill-curator/` is empty.
4. `deploy/` (the personal macOS launchd artifacts) stays ops-toolkit-side.
5. The embedded `skills/skill-review/` is promoted to top-level `dwarves-kit/skills/skill-review/`.

## Implementation

- **Move mechanism:** `git format-patch --relative=tools/cc-self-improve` from ops-toolkit (5
  commits touching the subtree, oldest-first) replayed via `git am --directory=tools/skill-curator`
  in this worktree. Real per-commit history preserved (not squashed), see "History preservation"
  below.
- **Exclusion (deviation from a literal "move deploy/ nowhere"):** the goal's own DECISIONS.md P5
  CRITICAL 2 names the exclusion as "`deploy/` stays ops-toolkit-side (the `mini.cc-curator.plist` +
  `cc-curator-runbook.md` are personal deploy artifacts)". Taken as "the whole `deploy/` dir stays"
  literally, this self-contradicts the "11 tests pass at identical count" bar: `tests/test-install.sh`
  (6 of the 11 test files) exercises `deploy/install.sh` / `deploy/uninstall.sh`, which are generic
  settings.json-wiring logic, not personal deploy artifacts, and contain no `workspace/<owner>`
  hardcode. **Resolution:** split `deploy/` --  `deploy/macos/{mini.cc-curator.plist,
  cc-curator-runbook.md}` (the actual personal Mini launchd artifacts the DECISIONS text names)
  stayed in ops-toolkit untouched; `deploy/install.sh` + `deploy/uninstall.sh` (generic, tested,
  no personal hardcode) moved with the tool. This is the only way to satisfy both the literal
  exclusion's own justification and the "identical pass count" gate simultaneously.
- **`RUNBOOK.md` / `MANUAL.md`:** the 2 hardcoded `~/workspace/<owner>/ops-toolkit/...` lines
  rewritten generic (RUNBOOK incident 9 path example; MANUAL's install `cd` example). RUNBOOK's
  personal-Mini incident 6 (referencing `mini.cc-curator` launchd + its log path, both artifacts
  that stayed behind in ops-toolkit) genericized to scheduler-agnostic language.
- **`lib/surface.sh:9` env-default flip:** `CC_SI_MEMORY_LEDGER` default changed from
  `$HOME/workspace/<owner>/ops-toolkit/_meta/learned-ledger.md` to empty (required-explicit, per
  the kit's adapter-default two-class split -- this path is tenant config, not kit-internal). Added
  `memory_ledger_count()` as the explicit call site: unset -> one clear stderr line + `return 1`,
  never a guessed path read. The passive SessionStart-safe wrapper (`surface_counts`/`surface_line`)
  still degrades to `0` on failure (architecture invariant: a hook must never abort a session), it
  just no longer silently pretends "unconfigured" is "confirmed zero" -- the diagnostic exists, it's
  just routed to the tool log instead of stdout in that one non-interactive path.
- **Skill promotion:** `git mv tools/skill-curator/skills/skill-review skills/skill-review`
  (top-level, loader-mandated). Confirmed no remaining reference to the old nested path; the one
  stale self-reference inside `SKILL.md` ("next to this skill in the tool") rewritten to point at
  `tools/skill-curator/bin/skill-review`. `install.sh`'s hardcoded single-skill (`get-api-docs`)
  copy is untouched (SG-02's glob-loop generalization; not this sub-goal's scope).
- **Renames (surgical):** user-facing prose/identity across README/MANUAL/RUNBOOK/SPEC/
  architecture.md, `tool.toml` (`name`, `description`), `.gitignore` comment, `config.example.toml`
  comment, `hooks/skill-review.sh` comment, `skills/skill-review/SKILL.md`, and the SessionStart
  surface line all renamed `cc-self-improve` -> `skill-curator`. The default RUNTIME STATE DIR
  (`~/.claude/cc-self-improve` -> `~/.claude/skill-curator`) and its log filename were also renamed
  to match (no test hardcodes the old default -- every test overrides via `CC_SI_STATE_DIR` -- so
  this is a pure identity fix). `CC_SI_*` env var NAMES, `bin/cc-improve` / `bin/skill-review` CLI
  binary names, and historical docs (`docs/decisions/`, `docs/implementation-notes/`,
  `docs/specs/SPEC-103-cc-self-improve.md`, `docs/proof-of-done.md`) were left untouched: renaming
  the CLI binary or the env-var prefix would churn the 11-test suite and every consumer-facing
  invocation for no behavioral gain (explicitly out of scope per the goal's "Not:" list); the
  historical docs describe the tool's original build and stay historically accurate.
- **Install/uninstall round-trip fix (a rename side-effect, not itself asked for but required to
  keep the tests green):** `deploy/uninstall.sh`'s hook-removal regex and `tests/test-install.sh`'s
  assertion helper both matched the literal substring `cc-self-improve`, which the tool's own
  directory path supplied for free before the rename. Post-rename the path contains `skill-curator`
  instead, so both were updated to match the new substring, restoring the install/uninstall
  round-trip (`test-install.sh` cases 2 and 6 failed until this fix; see run-table).

## History preservation: format-patch + git am (not subtree/squash)

Tried, in the design-note's stated preference order: `git format-patch --relative=<subtree>` (to
rewrite diff paths as if the subtree were the repo root) piped through `git am --directory=<new
path>` (to re-prefix onto the new location) in the target worktree. This worked cleanly for all 6
commits (5 general + 1 deploy/install.sh-only follow-up), no conflicts, no manual resolution.
**Method used: `git format-patch` + `git am` (full per-commit history, not a subtree split, not a
single squashed commit).**

```
$ git -C ops-toolkit log --reverse --format='%H %ad %s' --date=short -- tools/cc-self-improve
8dbde6c6 2026-06-19 docs(cc-self-improve): plan the Hermes self-improvement adaptation (#413)
7f966441 2026-06-19 feat(cc-self-improve): no-write skill-draft reviewer + staging (#425)
91a7fdec 2026-06-19 feat(cc-self-improve): promote gate + surfacing + install (#429)
057d032e 2026-06-19 feat(cc-self-improve): curator + full doc set + round close-out (#430)
e1c20617 2026-07-02 feat(cc-self-improve): opt-in signal-marker pre-gate before the reviewer model (#617)

$ git format-patch --relative=tools/cc-self-improve -1 <each-of-the-5-above> \
    -o <patchdir> -- tools/cc-self-improve ':!tools/cc-self-improve/deploy'
$ git am --directory=tools/skill-curator <patchdir>/p1..p5.patch     # 5 commits, clean apply

# deploy/install.sh + deploy/uninstall.sh were excluded from the bulk 5 (deploy/ pathspec
# exclusion above) but are NOT personal artifacts (see "Exclusion" above); replayed separately
# from the one commit that introduced them:
$ git format-patch --relative=tools/cc-self-improve -1 91a7fdec -o <patchdir2> \
    -- tools/cc-self-improve/deploy/install.sh tools/cc-self-improve/deploy/uninstall.sh
$ git am --directory=tools/skill-curator <patchdir2>/*.patch          # clean apply
```

Result: 6 real commits in `dwarves-kit` history under `tools/skill-curator/`, each with its
original author, date, and message (prefixed `cc-self-improve:` from the original ops-toolkit
commits -- left as-is, it is the historical record), followed by 2 new commits for the rename +
generalization work and this proof.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| 11-test suite, post-move | `for f in tests/test-*.sh; do bash "$f"; done` | all 11 files green, **70/70 assertions** (identical to the pre-move baseline run in ops-toolkit) |
| Done-gate grep | `grep -r 'workspace/<owner>' tools/skill-curator/` | empty (PASS) |
| NC: unset-ledger clean error at the call site | `unset CC_SI_MEMORY_LEDGER; bash -c '. lib/surface.sh; memory_ledger_count'` | `skill-curator: CC_SI_MEMORY_LEDGER is not set -- set it to your knowledge/learning ledger path to surface staged-memory counts (see MANUAL.md)`, exit 1 (clean error, no crash trace) |
| NC: hook-safe wrapper never breaks the session | `unset CC_SI_MEMORY_LEDGER; bash hooks/sessionstart-surface.sh < /dev/null` | valid `additionalContext` JSON, `skill-curator loop: 0 staged memory ...`, exit 0 |
| NC: no silent write anywhere (old ops-toolkit default, or the unset var's would-be path) | `find <fresh CC_SI_STATE_DIR> -type f` after the above | empty -- surface.sh is read-only by design; nothing was written |
| deploy/ (macos personal artifacts) stayed ops-toolkit-side | `ls ops-toolkit/tools/cc-self-improve/deploy/macos/` | `cc-curator-runbook.md`, `mini.cc-curator.plist` -- both untouched, not part of this branch's diff |
| skill-review promoted top-level | `ls dwarves-kit/skills/skill-review/` (this worktree) | `SKILL.md` present at `skills/skill-review/`, no longer nested under `tools/skill-curator/` |

### Full per-file test run (post-move, post-rename)

```
test-async: all 2 passed
test-curate: all 9 passed
test-hook-async: all 4 passed
test-install: all 6 passed
test-promote: all 9 passed
test-reentrancy: all 3 passed
test-reviewer: all 10 passed
test-signal-gate: all 12 passed
test-staging-gate: all 5 passed
test-surface: all 4 passed
test-transcript-parse: all 6 passed
```

Pre-move baseline (run in `ops-toolkit/tools/cc-self-improve/`, same 11 files, before any change)
was identical: 2+9+4+6+9+3+10+12+5+4+6 = 70.

## Reproduce

```
cd dwarves-kit/tools/skill-curator
for f in tests/test-*.sh; do bash "$f"; done
grep -r 'workspace/<owner>' .. -- .    # from tools/skill-curator, or:
grep -r 'workspace/<owner>' /path/to/dwarves-kit/tools/skill-curator/
unset CC_SI_MEMORY_LEDGER
bash -c '. lib/surface.sh; memory_ledger_count; echo exit=$?'
```

## Kit-adopted gate ledger

Lane: chosen `normal` (per the goal file's steer), classifier suggested `tiny` (recorded, not
overridden as fact -- both are on the START line). `build` and `review` phases recorded `ran`;
`spec` recorded an `override` (the goal file's own `Design: obvious` field -- wholesale subtree
move + one env-default flip, design note confirmed exactly one hardcoded line -- makes a separate
spec doc redundant); `ship` recorded at PR-open time.
