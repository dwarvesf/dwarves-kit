# SPEC-410: the ceremony a diff owes follows what the diff changes

**Status:** DRAFT
Lane: full
Type: spec-fix
**Proof:** `docs/verification/ceremony-fits-diff.md`; `tests/test-ceremony-fits-diff.sh`, `tests/test-classify-md-inert.sh`, `tests/test-lanes-data.sh`.
References: `lib/gate/proof-ledger.sh` (`classify`, `check`); `lib/classify/lane-classify.sh` (`floor`); `lib/gate/ship-rules.sh` (`ship_rule_floor`); `docs/SYSTEM-DESIGN.md` risks and drift register.

## Problem

Two gates charge ceremony for diffs that change no behavior.

1. The proof gate classed a docs-only PR as `behavioral` because the PR added a generated HTML drawing set under `docs/design/`, and the HTML holds JS. It needed an audited override, twice.
2. The hard-path floor demanded the full lane's nine extra gates for a comment-only edit to a file under `lib/gate/`, because the path matched `extra_hard_paths`.

Both gates key on a path, not on what the diff changes. A gate that cries wolf trains people to override it.

## Contract

| Gate | Rule |
|---|---|
| Proof class (`proof-ledger.sh classify`) | A diff made only of docs classes `inert` and owes no proof. Docs = `*.md`, `*.txt`, `*.markdown` anywhere, `.kit.toml`, and any file under a `docs/` tree whatever its extension (generated `.html`, `.svg`, `.png` included). Any other file keeps its class. A mixed diff is classed by its non-doc files |
| Override remainder (`proof-ledger.sh check`) | A file under a `docs/` tree is not application source when an override decides what it excuses |
| Hard-path floor (`lane-classify.sh floor`) | A hard-path hit counts only for a file that is not a doc and whose changed lines are not all comment or blank lines. A doc is `*.md`, `*.markdown`, `README` or `README.<md|markdown|txt|rst|adoc>`, or a file under a `docs/` tree with a documentation or asset extension (`txt rst adoc html htm svg png jpg jpeg gif webp pdf json csv`). Code, config and SQL under `docs/` keep the floor |
| Comment-only test | Applies to shell, python, toml, yaml, terraform and Dockerfile-named files (by basename). Every added and removed line is blank or starts with `#` after whitespace. These are code, not comments: a `#!` line; a parser-steering comment (Dockerfile `syntax=`, `escape=`, `check=`; a python coding tag; an emacs modeline); a scanner-suppression comment (`nosec`, `noqa`, `nosemgrep`, `tfsec`, `checkov`, `trivy`, `kics`, `shellcheck`, `pylint`, `pragma`, `gitleaks`, `lint:`, `type: ignore`); any changed line or neighbouring context line that ends in a backslash |
| Data-line guard | A file whose base or head image holds a heredoc (`<<`), a triple quote, or a YAML block-scalar opener keeps the floor, because a `#` line inside such a construct may be data |
| Fail safe | The floor stands when the check cannot decide: a submodule, a symlink, a path that matches the secret pattern (whatever kind reported first), a file type with no known `#` syntax, a mode change, a binary diff (a NUL byte), an empty or unparsable diff, more than 50 comment-only hits in one diff, or more than 8 seconds spent on the check |

The data-loss scan, submodule rule, `extra_hard_paths`, `[[gate.hard_path_exempt]]` and the test-path default are unchanged.

## Picture

```
 diff paths --> docs? (md, README, docs/) ----yes----> blank the path, never a hit
                  | no
                  v
         hard-path regex hit? ----no----> next path
                  | yes
                  v
   comment-only? (git diff -U1 + data-line guard, that one path) ---yes---> blank the path, look again
                  | no / cannot decide
                  v
              full <kind>: <path>
```

## Design

`classify` swaps its two `.md|.txt|.markdown` greps for one shared `doc_re` that adds `(^|/)docs/`. The floor gains three small helpers beside `_floor_scan`: `_floor_find` (the old first-hit search, now callable more than once), `_floor_drop` (blank one line in the path lists, so line numbers and the submodule index stay valid), and `_floor_comment_only` (a data-line guard (two `git show` greps) and one `git diff -U1` for the one hit path, parsed by one awk pass). Docs are blanked up front in one awk pass. Symlinks and gitlinks are recorded in a `nosoft` list at path-list time and never blanked. The loop re-searches after each dropped hit, capped at 50 drops and 8 seconds, so a flood keeps the floor and the cost stays flat. `ship_rule_floor` needs no logic change: it calls `floor` and now sees fewer false hits.

## Failure modes

| Class | Mitigation |
|---|---|
| A `#` line inside a heredoc, triple-quoted string, YAML block scalar or after a backslash continuation is data or part of a command | the check refuses any file that holds such an opener, and any change next to a backslash |
| An attacker hides a change in a `docs/` path | the floor reads real paths from `diff --raw`, never from diff headers; a symlink or gitlink under `docs/` is not a doc |
| A comment-only edit adds a leaked secret | a path matching the secret pattern never qualifies, even when an earlier kind (auth) reported it; the data-loss scan still reads comment lines |
| `docs/` matches a code dir (`src/docs/login.py`, `.github/actions/docs/action.yml`) | a file under `docs/` is a doc only with a documentation or asset extension, so code there keeps the floor |
| An `extra_hard_paths` entry names Markdown (an LLM instruction file) | docs are exempt from extras too, as the original brief requires (a README under `lib/gate/` was the motivating case); a team that wants Markdown gated needs a different mechanism |
| The check is slow and the hook fails open on its own timeout | bounded to 50 drops and 8 seconds; past either the floor stands |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: proof class | `lib/gate/proof-ledger.sh` | a docs-tree diff classes `inert`; other files keep their class |
| T2: floor | `lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh` | docs and comment-only edits do not hit; code edits and every undecidable case still hit |
| T3: tests | `tests/test-ceremony-fits-diff.sh` | each contract row has a case; the suite goes red on the pre-change libs |
| T4: slow suites | `tests/test-config-registry.sh`, `tests/test-lanes-data.sh`, `tests/test-hooks.sh` | same assertions, fewer subprocesses; before and after seconds recorded |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-ceremony-fits-diff.sh` | every case passes |
| P2 | `bash tests/test-classify-md-inert.sh`, `bash tests/test-lanes-data.sh` | exit 0 (existing floor and classify pins hold) |
| P3 | `bash tests/run-all.sh --changed` | exit 0 |

Negative control, through `lib/gate/negctl.sh` with P1 as the test command: restore `proof-ledger.sh` and `lane-classify.sh` from the merge base. P1 must go red.

## Verification

P1 to P3 hold and the negative control reports PASS.

## After state

A docs-only PR owes no proof whatever its file types. A comment-only edit to a hard-path file owes no full-lane gates. Every hard-path hit that remains is a change a reviewer should see.

## Decision Log

- The proof gate treats any file under a `docs/` tree as a doc, as the brief asked (a generated drawing set is the case). The floor is stricter: a file under `docs/` is a doc only with a documentation or asset extension, because the floor is a security boundary and `src/auth/docs/check.py` must not borrow the name.
- The comment-only rule covers `#`-comment file types only. `//` and `/* */` languages keep the floor until someone asks, because a wrong "comment-only" verdict there is a real hole (`/* ... */` spans lines).
- A path matching the secret pattern never qualifies, even with a comment-only diff and even when auth reported first, because a comment is the usual place a leaked credential lands.
- `README.sh` and `README.py` are code, not docs: only `README` and `README.<text extension>` count, so an executable cannot borrow the name.
- Ruby is not covered: its magic comments (`frozen_string_literal`) change behavior, and no hard path in this estate is Ruby.
- A diff with a NUL byte keeps the floor; the check reads the diff from a file because bash 3.2 drops NULs in a substitution.
- `bin/test-affected.timeouts` is left alone: new ceilings need a quiet-host p95 re-measure, and this host ran at load above 100.
