# Verification -- adopt-agents-only

`[adopt] agents_only = true` makes `AGENTS.md` a repo's one instruction file: adopt, refresh and `wrap adopt` never write `CLAUDE.md` (spec: `docs/specs/SPEC-419-adopt-agents-only.md`).

## Green run

The suites that carry the new cases, on the repo's harness (real git, bare remotes, gh stub, real `adopt.sh`):

```
Command: bash tests/test-adopt.sh
Exit: 0
Output:
  ok - agents_only: fresh adopt writes the pointer and no CLAUDE.md, and names the knob
  ok - agents_only: --check exits 0 with no CLAUDE.md
  ok - agents_only: re-run and --refresh are clean no-ops and never restore CLAUDE.md
  ok - agents_only: existing CLAUDE.md untouched; AGENTS.md keeps its text plus one block with no self-import
  ok - agents_only: wins over --single-source (differing files adopt, CLAUDE.md untouched)
  ok - agents_only: an old kit AGENTS.md gets no block and still swaps to the pointer
  ok - agents_only: --refresh refuses two blocks and keeps the consumer text between them
  ok - agents_only = false (and unset) keeps the CLAUDE.md loader
  PASS=78 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-wrap-adopt.sh
Exit: 0
Output:
  test-wrap-adopt: all 225 passed
Verdict: PASS
```

The change touches adopt, wrap adopt, two hooks, board-run and docs, so the diff-selected set ran:

```
Command: RUN_ALL_TIMEOUT_SECS=1200 bash tests/run-all.sh --changed --time
Exit: 1
Output:
  run-all: --changed against 2e4b4e75: 22 changed files -> 74 suites (70 named, the rest always-on)
  test-adopt                                     ok (49s)
  test-board-run                                 ok (4s)
  test-clean-room                                ok (28s)
  test-gate-opt-out                              FAIL (rc=1) (12s)
  test-hooks                                     ok (247s)
  test-meta-docs-registry                        ok (14s)
  test-wrap-adopt                                ok (142s)
  run-all: FAILED -> test-gate-opt-out
Verdict: one real failure, fixed below
```

The failure: `test-gate-opt-out` forbids any file under `hooks/` from naming the kit config, comments included, and a comment in `hooks/context-readiness.sh` did. The comment was reworded (behavior unchanged) and the failed suites re-run:

```
Command: bash tests/test-gate-opt-out.sh ; bash tests/run-all.sh --failed
Exit: 0
Output:
  PASS no hooks/*.sh names the config file (leaked: none)
  ALL PASS
  run-all: all 9 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Committed first. The key was then made unreadable to `adopt.sh` (the `= "true"` test forced to `= "never"`), the suite re-run, and the file restored with `git checkout -- lib/adopt.sh`; the same for the key test in `lib/wrap/wrap-adopt.sh`:

```
Command: bash tests/test-adopt.sh   (key ignored by adopt.sh)
Exit: 1
Output:
  NOT ok - agents_only fresh adopt
  NOT ok - agents_only idempotency
  NOT ok - agents_only existing CLAUDE.md (s=0 e=0)
  NOT ok - agents_only touched a legacy CLAUDE.md block
  NOT ok - agents_only dry-run
  NOT ok - agents_only vs --single-source (rc=1)
  NOT ok - agents_only via operator kit.toml
  NOT ok - agents_only two blocks (rc=0)
  NOT ok - agents_only reversed markers (rc=0)
  PASS=69 FAIL=9
Verdict: RED as intended
```

```
Command: bash tests/test-wrap-adopt.sh   (key ignored by wrap-adopt.sh)
Exit: 1
Output:
  FAIL 41: dirty CLAUDE.md, key on: exits 0
  FAIL 41: dirty CLAUDE.md, key on: would adopt
  FAIL 42: exits 0
  FAIL 42: result row names the PR
  FAIL 43: exits 1
  FAIL 43: names CLAUDE.md as outside the scaffold set
  test-wrap-adopt: 217 passed, 8 FAILED of 225
Verdict: RED as intended
```

Restored: `git status --short` printed nothing after each `git checkout --`, and both suites are green on the restored files (above).

## Rollback

The key defaults to false, so the merge changes no repo until one sets it. To undo for a repo: set `agents_only = false` (or delete the line) in its `.kit.toml`, delete the `<!-- kit:adopt -->` block from its `AGENTS.md` by hand if it has one, and run `/kit:adopt --refresh` to restore the `CLAUDE.md` loader. To undo the change itself: revert the merge commit; no data, ledger or schema moves with it.

## Not proven

- No real Claude Code session was started on an `AGENTS.md`-only repo. The v2.1.277 behavior is the vendor's documented one (https://code.claude.com/docs/en/memory, section "AGENTS.md").
- CRLF marker lines in a consumer `AGENTS.md` are not handled (pre-existing for `CLAUDE.md`).
- The consumer repo (`consolelabs/playdate-agent`) was not touched or run.
