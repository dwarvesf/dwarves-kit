# SPEC-410: the ceremony a diff owes follows what the diff changes

**Status:** DRAFT
Lane: full
Type: spec-fix
**Proof:** `docs/verification/ceremony-fits-diff.md`; `tests/test-ceremony-fits-diff.sh`, `tests/test-classify-md-inert.sh`, `tests/test-lanes-data.sh`.
References: `lib/gate/proof-ledger.sh` (`classify`, `_nondoc_paths`); `lib/classify/lane-classify.sh` (`floor`, `_floor_comment_only`); `lib/gate/ship-rules.sh` (`ship_rule_floor`); `docs/SYSTEM-DESIGN.md` risks and drift register.

## Problem

Two gates charge ceremony for diffs that change no behavior.

1. The proof gate classed a docs-only PR as `behavioral` because the PR added a generated HTML drawing set under `docs/design/`, and the HTML holds JS. It needed an audited override, twice.
2. The hard-path floor demanded the full lane's nine extra gates for a comment-only edit to a file under `lib/gate/`, because the path matched `extra_hard_paths`.

Both gates key on a path, not on what the diff changes. A gate that cries wolf trains people to override it.

## Contract

Terms. A **docs tree** is a directory named exactly `docs`, at any depth, case-sensitive. A **change group** is a run of consecutive added or removed lines in `git diff -U1`.

| Gate | Rule |
|---|---|
| Proof class (`proof-ledger.sh classify`) | A diff made only of docs classes `inert` and owes no proof. A doc is `*.md`, `*.txt`, `*.markdown` anywhere, a `.kit.toml`, or a file in a docs tree with a documentation or asset extension (`rst adoc png jpg jpeg gif webp pdf csv`; `html htm svg` only under the repo-root `docs/`). A secret-shaped path (`credentials` in the name, a `secrets` dir, certificate or key files, `.env*`; case-insensitive) is never a doc. Build files in a docs tree (`package.json`, `Makefile`, compose, yaml, toml) keep their class. `requirements.txt` and other `*.txt` files stay docs, as before. Any other file keeps its class. A mixed diff is classed by its non-doc files |
| Hard-path floor, docs (`lane-classify.sh floor`) | A hard-path hit counts only for a file that is not a doc. A doc is `*.md`, `*.markdown`, `README.<md,markdown,txt,rst,adoc>`, or a file in a docs tree with a documentation or asset extension (`txt rst adoc png jpg jpeg gif webp pdf csv`; `html htm svg` only under the repo-root `docs/`). A symlink, a gitlink, and any path that matches the secret pattern are never docs. Code, config and SQL in a docs tree keep the floor. Docs are exempt from `extra_hard_paths` too |
| Hard-path floor, comment-only | A hit on a file whose changed lines are all blank or `#` comments is dropped. Applies to `*.sh *.bash *.zsh *.py *.toml *.yml *.yaml *.tf`, `Dockerfile` and `*.dockerfile` (by basename), only |
| Change-group rule | Every change group must start right after a comment line, the top of the file, or a blank line that itself follows a comment, a blank line or the top (`git diff -U2`). A `#` or blank line that follows a code or data line may sit inside a quoted string, a continuation or a bracket |
| Position-sensitive lines | When the first three lines of either image hold a shebang, a coding cookie, a modeline or a Dockerfile directive, any change group that starts within the first three lines of either image keeps the floor (a prepend pushes the line down; a deletion pulls a later one up). A directive on a context line next to a change keeps it too |
| Code, not comments | A changed `#!` line; a parser-steering comment (Dockerfile `syntax=`, `escape=`, `check=`; a coding tag; an emacs modeline); a comment naming a scanner or suppression (`ignore disable skip suppress allowlist nolint nosec noqa nosemgrep nosonar tfsec tflint checkov trivy kics hadolint shellcheck pylint lgtm codeql trufflehog gitleaks pragma lint: type:`, case-insensitive); any changed or neighbouring context line ending in a backslash |
| Data-line guard | A file whose base or head image holds a heredoc (`<<`), a triple quote, or a YAML block-scalar opener (`\|` or `>` with optional indicators, tag, anchor or trailing comment) keeps the floor |
| Fail safe | The floor stands when the check cannot decide: a submodule, a symlink, a path matching the secret pattern (whatever kind reported first), a file type outside the list above, a mode change, a binary diff (a NUL byte), an empty or unparsable diff, more than 50 comment-only hits in one diff, or more than 8 seconds spent on the check (the ship-gate hook times out at 30 seconds and fails open) |

The data-loss scan, submodule rule, `extra_hard_paths`, `[[gate.hard_path_exempt]]` and the test-path default are unchanged. The data-loss scan keeps its own, older doc rule (`.md .markdown .txt .rst .adoc` and any `docs/` path); it reads added lines only.

## Picture

```
 diff paths --> secret-shaped, symlink, gitlink? ---yes---> never a doc
                  | no
                  v
              doc? (md, README.<ext>, docs tree + doc extension) ---yes---> blank the path, never a hit
                  | no
                  v
        hard-path regex hit? ----no----> next path
                  | yes
                  v
   comment-only? (data-line guard, git diff -U1, change-group rule) ---yes---> blank the path, look again
                  | no / cannot decide
                  v
              full <kind>: <path>
```

## Design

`classify` swaps its two `.md|.txt|.markdown` greps for `_nondoc_paths`, one awk filter that also drops non-source, non-secret files in a docs tree. The floor gains three small helpers beside `_floor_scan`: `_floor_find` (the old first-hit search, now callable more than once), `_floor_drop` (blank one line in the path lists, so line numbers and the submodule index stay valid), and `_floor_comment_only` (a data-line guard of two `git show` greps, then one `git diff -U1` for the one hit path, parsed by one awk pass). Secret-shaped paths join the symlink and gitlink list (`nosoft`) before docs are blanked in one awk pass. The loop re-searches after each dropped hit, capped at 50 drops and 8 seconds. `ship_rule_floor` needs no logic change: it calls `floor` and sees fewer false hits.

## Failure modes

| Class | Mitigation |
|---|---|
| A `#` line inside a quoted string, heredoc, triple-quoted string or YAML block scalar is data | the change-group rule refuses a group that follows a code or data line; the data-line guard refuses files with a heredoc, triple quote or block-scalar opener. Residual: a string that already holds a comment-shaped line, or a blank line after another blank line, right where a new one is added |
| A `#` line after a backslash continuation | the backslash rule on changed and context lines |
| A prepend or deletion makes a shebang, coding cookie or Dockerfile directive stop working | the position-sensitive rule above |
| An attacker hides a change in a `docs/` path | the floor reads real paths from `diff --raw`, never from diff headers; code, config and SQL in a docs tree, and `README.sh`-style names, keep the floor; a symlink or gitlink is never a doc |
| A comment-only edit adds a leaked secret or a scanner suppression | a path matching the secret pattern never qualifies, even when auth reported first; suppression words make a line code; the data-loss scan still reads comment lines |
| Markdown that steers an agent (`agents/*.md`, command files) | the floor cannot gate it: Markdown is a doc for both gates, and docs are exempt from `extra_hard_paths` as the brief requires (a README under `lib/gate/` was the motivating case). A team that wants those gated needs a different mechanism |
| `classify`: a gitlink or symlink under a docs tree, and `*.txt` build inputs such as `requirements.txt` | `classify` sees names only and treats them as docs (the `*.txt` rule predates this spec); the floor still gates a gitlink or symlink. Residual, accepted for the proof gate |
| The check is slow and the hook fails open on its own timeout | bounded to 50 drops and 8 seconds; past either the floor stands. The bound is covered by the 51-file case, not by a timing test |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: proof class | `lib/gate/proof-ledger.sh` | a docs-tree diff classes `inert`; source and secret-shaped files keep their class |
| T2: floor | `lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh` | docs and comment-only edits do not hit; code edits and every undecidable case still hit |
| T3: tests | `tests/test-ceremony-fits-diff.sh` | each Contract row has a case; the suite goes red on the pre-change libs |
| T4: slow suites | `tests/test-config-registry.sh`, `tests/test-lanes-data.sh`, `tests/test-hooks.sh` | same assertions, fewer subprocesses; before and after seconds recorded in the proof file. No Contract row: this task changes tests only |

## Test plan

| # | Contract row | Check | Case |
|---|---|---|---|
| P1 | proof class | docs tree, markdown, subject words, source and secret-shaped files under docs, mixed diffs | `class-*`, `check-docs-tree-owes-no-proof` |
| P2 | floor docs | docs never hit; code or doc-named code in a docs tree still hits; secret-shaped docs path hits | `floor-docs-never-hit`, `floor-code-under-docs-or-doc-named-still-hits`, `floor-readme-exec-is-code` |
| P3 | comment-only, change-group, position-sensitive, code-not-comments, data-line guard | comment edits drop; code edits, quoted-string, heredoc, triple-quote, block-scalar, continuation, suppression and after-code comments hit | `floor-comment-only-edit-is-not-a-hit`, `floor-code-change-is-a-hit`, `floor-hash-that-is-not-a-comment-keeps-the-floor` |
| P4 | fail safe | mode change, binary, NUL, symlink, secret pattern, unknown type, gitlink, 51 files, line-number alignment, stderr notice | `floor-cannot-decide-keeps-the-floor`, `floor-nul-byte-keeps-the-floor`, `floor-secret-pattern-beats-first-kind`, `floor-cap-keeps-the-floor-on-a-flood`, `floor-blanking-keeps-line-numbers-aligned`, `floor-exempt-notice-survives-drops` |
| P5 | gate answer | `ship_rule_floor` passes comment-only and docs, blocks code | `ship-rule-floor-follows-the-diff` |
| P6 | regressions | `bash tests/test-classify-md-inert.sh`, `bash tests/test-lanes-data.sh`, `bash tests/run-all.sh --changed` | exit 0 |

Negative control, through `lib/gate/negctl.sh` with `bash tests/test-ceremony-fits-diff.sh` as the test command: restore `proof-ledger.sh` and `lane-classify.sh` from the merge base. The suite must go red.

Not covered by a dedicated case: a committed `.gitattributes` that hides a change. The floor pins `--text`, `core.attributesFile=/dev/null` and a fixed prefix on every git call, and the existing `floor-diff-hardening` case in `tests/test-lanes-data.sh` covers the `-diff` attribute.

## Verification

P1 to P6 hold and the negative control reports PASS.

## After state

A docs-only PR owes no proof whatever its file types. A comment-only edit to a hard-path file owes no full-lane gates. Every hard-path hit that remains is a change a reviewer should see.

## Decision Log

- Both gates use an allowlist of documentation and asset extensions in a docs tree, so a generated drawing set (the motivating case) owes nothing while `docs/package.json`, `docs/Makefile` and `docs/Dockerfile` keep their class. `html htm svg` count only under the root `docs/`, so `src/auth/docs/login.html` is code. The floor additionally never exempts a symlink, a gitlink or a secret-shaped path.
- The comment-only rule covers `#`-comment file types only. `//` and `/* */` languages keep the floor until someone asks, because a wrong "comment-only" verdict there is a real hole (`/* ... */` spans lines). Ruby is out too: `frozen_string_literal` and friends change behavior.
- The change-group rule trades reach for safety: a comment added right after a code line keeps the floor. It makes a `#` line inside a multi-line string unreachable without a pre-existing comment-shaped line, which no blocklist of openers can promise.
- A path matching the secret pattern never qualifies, even with a comment-only diff and even when auth reported first, because a comment is the usual place a leaked credential lands.
- `README.sh` and a bare `README` are code-shaped names, not docs: only `README.<text extension>` counts.
- A diff with a NUL byte keeps the floor; the check reads the diff from a file because bash 3.2 drops NULs in a substitution.
- `bin/test-affected.timeouts` is left alone: new ceilings need a quiet-host p95 re-measure, and this host ran at load above 100.
- Three rounds of adversarial probing, one code review and two fresh-context spec validations each found holes the previous text left open; the Contract above is the text after those rounds. The floor stays a heuristic over `#`-comment files; the rows above name what it refuses, and what is left is listed under Failure modes.
