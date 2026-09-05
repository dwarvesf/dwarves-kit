# board promote: --backlog-file translation (issue #443)

Date: 2026-08-27
Class: behavioral (changes what `board promote` does, and where it writes)

## Restated claim

`board promote` is correct when, invoked through the shim `board init` scaffolds:
(a) **numeric selection works** — `promote <n>` promotes exactly candidate n, measured by the
promoted row landing on the board while the unselected candidate stays staged; and
(b) **the addressed board is the one written** — measured by running repoA's shim from inside
repoB and checking repoA's BACKLOG.md gains the row while repoB's gains nothing.

Both were false before this change.

## Defect

The shim always appends `--backlog-file <path>`. `lib/board/board.sh` forwarded argv to
`lib/board/bin/add-backlog` verbatim, and that engine takes no flags at all — it resolves its
targets from `BACKLOG_STAGE_BACKLOG` / `BACKLOG_STAGE_STAGING` with a cwd-derived fallback. Two
consequences compounded:

1. The flag reached the selection parse, `int("--backlog-file")` raised, and every
   `promote <n>` / `promote reject <n>` failed with a usage message about candidate numbers.
   `list` returns before that parse and `all` short-circuits past it, so those two kept working
   — which is the worst possible failure shape here: the only surviving promote path is the one
   that promotes *everything*, reducing a documented human review gate to all-or-nothing.
2. The operator's explicit target was discarded, so promote resolved its write target from cwd.
   In the cross-repo cockpit this kit exists to provide, that means promoting into the wrong
   repo's board with no warning.

`cmd_sync` already documents and handles exactly this shim behaviour
(`lib/board/board.sh`: "Consumer shims append `--backlog-file`; translate it to the engine's
`--backlog`"). `promote` never got the same treatment.

## Run

```
Command: bash tests/test-board.sh
Exit: 0
Output (excerpt):

  === AC7: promote translates --backlog-file (issue #443) ===
    PASS AC7a: numeric selection works through the shim's --backlog-file (was: usage error)
    PASS AC7b: the addressed repo is written, not the cwd repo
    PASS AC7c: promoted the SELECTED candidate (A-first), not all of them
    PASS AC7d: unselected candidate stays staged -- the review gate is not all-or-nothing
    PASS NC-f: unrecognised flag is named explicitly, not reported as a bad candidate number

  TOTAL: 42   PASS: 41   FAIL: 0   SKIP: 1
```

The single SKIP is the pre-existing NC-e ops-toolkit render comparison, absent on this machine.

## Negative control

Fix stashed, same suite re-run against unmodified sources:

```
Command: git stash push lib/board/board.sh lib/board/bin/add-backlog && bash tests/test-board.sh
Exit: 1
Output (excerpt):
    FAIL AC7a: numeric selection works through the shim's --backlog-file (was: usage error)
    PASS AC7b: the addressed repo is written, not the cwd repo
    FAIL AC7c: promoted the SELECTED candidate (A-first), not all of them
    PASS AC7d: unselected candidate stays staged -- the review gate is not all-or-nothing
    FAIL NC-f: unrecognised flag is named explicitly, not reported as a bad candidate number

  TOTAL: 42   PASS: 38   FAIL: 3   SKIP: 1
```
Verdict: RED-as-expected. Sources restored and byte-compared afterwards.

**Honest limit on two of the five.** AC7b and AC7d pass on the *unfixed* code too, because when
`promote <n>` dies at the usage error nothing is written anywhere — so "repoB gained no rows" and
"A-second is still staged" are vacuously true. They do not discriminate this particular defect.
They are kept because they DO discriminate a plausible wrong fix: one that makes numeric
selection work but still resolves the target from cwd, or that promotes the whole staging file.
AC7a, AC7c and NC-f are the three that actually go red.

## Rollback

Revert the commit. The change is confined to a dispatch branch in `lib/board/board.sh`, a new
`cmd_promote`, and a flag guard in `lib/board/bin/add-backlog`; no state, no migration, no
on-disk format change. Consumer shims are untouched and need no regeneration — the fix is
deliberately on the kit side so existing scaffolded shims are fixed without the consumer
doing anything.
