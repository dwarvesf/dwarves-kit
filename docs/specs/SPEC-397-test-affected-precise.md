# Spec: precise picks in bin/test-affected, guarded by a replay tool

Generated: 2026-10-05
Status: VALIDATED (design call made in the kit-speed run; no validation fan-out)
Lane: normal
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 08 (R22; NOTES item 3).

## Problem

`bin/test-affected` over-selects. A 20-file, mostly-docs diff picked 93 unique suites: 35 from "references kit.toml" for one added `load_warn` line, and 24 from `orchestrate.sh` for a three-line change. A suite that only mentions a basename in a string, a comment or a grep pattern is picked the same as one that runs the file. A larger diff still picks about 57 suites. The extra suites cost minutes per change and no signal.

## Design

- **Guard first.** `tests/lib/test-affected-replay.sh` replays the last N merged PRs. For each it diffs the merge commit against its first parent, runs a given `bin/test-affected --list --base <parent>` on a detached scratch worktree at the merge commit, and prints picked count, touched count and MISS count. A MISS is a suite an independent touched rule requires that the selection omitted. The touched rule: the PR edited the suite; a failed CI check names it; one of its non-comment lines runs or sources a changed source file; it names a changed non-source path in full; or, for kit.toml, it names kit.toml and a changed section or key. `--compare <copy>` adds the other copy's count as the before column. Exit 1 on any MISS.
- **kit.toml by section and key.** The kit.toml diff is split into hunks. Each changed line is attributed to the `[section]` in scope and, when it is a `key =` line or a comment continuation of one, to that key. A suite that names kit.toml qualifies when it names a changed key (bare, `section.key`, `KIT_<KEY>`) or, for a header or an unkeyed line, the section (`[section]`, `section.`). A hunk no section owns, a new or deleted kit.toml, or an empty attribution falls back to every suite naming kit.toml, never to nothing. The candidate set never grows beyond today's.
- **Sources by run, not mention.** A source file (lib/, tests/lib/, hooks/, bin/, commands/, skills/, agents/) qualifies a suite when a non-comment line names its full repo path, or names its basename (over 5 chars) in a run form: `bash|sh|source|. <name>`, `$VAR/<name>`, or a direct call at command position. A string, `echo`, comment or grep pattern holding only the basename no longer qualifies. The lib module rule, the wrap fan-out and the test-meta area picks are unchanged. Non-source paths keep the full-path rule.
- **Deterministic.** No model call in either part.

## Verification

```
bash tests/test-test-affected-replay.sh     # the guard: clean replay, MISS on an omitted suite, usage
bash tests/test-test-affected.sh            # kit.toml hunks, fallback, mention-only vs run/source
bash tests/test-test-affected-parallel.sh   # unchanged behavior of the runner
bash tests/test-test-affected-cache.sh
bash tests/test-run-all-changed.sh
bash tests/test-bin-forwarders.sh
# replay over the last 30 merged PRs, master's copy vs this one: MISS 0 for this one
# negative control: a saved copy that also drops full-path references; the replay reports MISS and exits 1
```
