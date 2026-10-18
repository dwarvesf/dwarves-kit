# Implementation notes: ceremony fits the diff

The delta from `docs/specs/SPEC-410-ceremony-fits-diff.md`. The spec holds the contract; this holds what the build added or changed.

## Delta from the spec

| Area | Spec said | Build did | Why |
|---|---|---|---|
| Comment-only test | `#` lines only | also treats a Dockerfile directive (`# syntax=`, `# escape=`, `# check=`), a python coding tag and an emacs modeline as code | those comments steer a parser; a "comment-only" verdict on them is a hole |
| `proof-gate.sh` | listed as a possible owner of the classify logic | untouched | it classifies a task description by words, not a diff; it shares no code with `classify` |
| `ship-rules.sh` | listed as an owner | comment text only | `ship_rule_floor` calls `lane-classify.sh floor`, so the fix lands once, in the classifier |
| Review round 1 (adversarial probe plus code review) | doc = `.md`, `README*`, anything under `docs/`; comment-only = `#` lines | secret exclusion keys on the path pattern, not the winning kind; the diff is read from a file and a NUL byte keeps the floor; Ruby dropped; `README` narrowed to `README` and `README.<text ext>`; a file under `docs/` is a doc only with a documentation or asset extension; a file holding a heredoc, triple quote or YAML block opener keeps the floor; a backslash next to the change, and scanner-suppression comments, are code; the loop stops after 8 seconds; extras cache warmed once before the loop | the reviewers reproduced each hole: `src/auth/secrets/rotate.sh` reported as auth, a NUL-prefixed `#` line read as a comment, `README.sh` and `.github/workflows/README.yml` borrowed the docs exemption, `src/auth/docs/check.py` sat under a `docs/` dir, a `#` line inside a heredoc, triple-quote or `run: |` block was data, a `#` line after a `\` continuation turned an argument into a command, `# noqa` and `# SYNTAX=` slipped through. Two deviations from the lead's brief, both toward the fail-safe side: README and `docs/` are narrower than "README*" and "files under docs/" |
| Override remainder | not in the original brief | a file under `docs/` is skipped when `check` decides what an override excuses | otherwise a docs-tree `.js` file plus an inert remainder would still read as "source" and reject the override that the new inert class makes unnecessary |

## Slow suites

The host ran at a load average above 100 for the whole session, so wall seconds swing 3x between identical runs. The fair measure is CPU seconds (user plus sys), taken with the old and the new file side by side under the same load. The per-suite numbers are in `docs/verification/ceremony-fits-diff.md`.

| Suite | Hot spot | Change |
|---|---|---|
| `test-config-registry` | three `bin/config list` renders (about 13 CPU seconds each); a subshell per table cell in AC6 to AC8 | two renders started in the background before AC1 and collected where asserted; AC8's leak check reads the project/env-seeded render instead of a third default render; AC6 to AC8 read each table in one awk pass |
| `test-hooks` | the cosmetic-hook garbage battery ran twice (6 hooks x 10 inputs x 2) | one pass records both the worst exit code and any exit 2 |
| `test-lanes-data` | `record_gates` forked `gate-ledger.sh` once per phase for every ship case; `floor-exempt-malformed-rejected` ran the floor twice per config; `reader_run` built a fresh repo per call | `record_gates` records each distinct phase list once through the real writer and appends the template afterward; one floor run per config serves both the stdout and stderr legs; `reader_run` reuses one repo (only main's `.kit.toml` differs between calls) |

Not changed, and why: `bin/config list` itself is the real cost (321 rows, a fork per cell); fixing it belongs to the config slice. `test-config-seams` is 34 `bin/config seams` calls at about 0.4 CPU seconds each, too small to matter. `bin/test-affected.timeouts` waits for a quiet-host p95 re-measure.

## Review round 2

| Finding | Change |
|---|---|
| a `#` or blank line inside a multi-line quoted string, a YAML quoted scalar, or after a code line | change-group rule: a group must follow a blank line, a comment line or the top of the file |
| YAML block openers with an indentation indicator, a tag, an anchor or a trailing comment | the data-line opener regex covers them |
| scanner-suppression comments beyond the first list (`hadolint`, `tflint`, `lgtm`, `codeql`, `nosonar`, `trufflehog`) | the blocklist is broader and includes the generic words `ignore`, `disable`, `skip`, `suppress`; prose using those words keeps the floor, by design |
| `html`, `svg`, `json` under a nested docs dir (`src/auth/docs/login.html`, `package.json` in an action's `docs` dir) | those three extensions count as docs only under the repo-root `docs/` |
| bare `README` and `Dockerfile.c` | `README` needs a text extension; only `Dockerfile` and `*.dockerfile` are Dockerfile-shaped |
| `docs/credentials.json` classed inert and passed the floor | secret-shaped paths are never docs, in `classify` and in the floor |
| `classify` treated `src/docs/h.py` and `lib/docs/x.sh` as docs | a docs-tree file is a doc only when it is not source code; the override-remainder skip added in the first cut is gone because it is no longer needed |
