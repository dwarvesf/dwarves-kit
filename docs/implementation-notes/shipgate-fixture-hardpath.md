# Implementation notes: shipgate-fixture-hardpath

Delta from `docs/specs/SPEC-400-shipgate-fixture-hardpath.md` (the per-kind glob rework). The first build's notes are superseded; its decisions live in git history at `c28ef8c4`.

## Rework validate round (7 reviewers, NEEDS REVISION, 4 critical, 36 warnings)

Criticals, folded into the spec:

- Silent, PR-steerable test-path `auth` skip (Reviewer 4). Fold: the skip now prints a TAB notice and an `[advisory]` line (AC20).
- TASK-2 and TASK-3 too large (Reviewer 4). Fold: split into 2a/2b and 3a/3b; each code task carries its own AC cases.
- No migration-only test, so an empty pattern line could blank every `auth` path (Reviewer 2). Fold: empty-pattern invariant plus AC21.
- Glob tests missed `**/`, `a/**/b` and `?`, and a `sed` chain can corrupt an earlier rule's output (Reviewer 1). Fold: AC4 rows plus a one-pass translation rule.

Fold-side decisions not asked for by a critical:

- The notice moved to TAB-separated fields with the path last. Reviewers 1 and 2 showed a wildcard-matched path can forge an entry number or reason in the old parenthesised format. This rode the AC20 change because both touch the same line.
- An all-wildcard glob (`**`, `*/**`) is invalid. Reviewers 1, 2 and 5 noted a bare `**` had no defined translation.
- `cases` stays in the test-path list. Reviewers 1 and 5 asked to drop it as too generic, but the operator listed it explicitly. Open question for the operator.

## Warnings for the builder (not in the spec)

1. `--files` HEAD fallback: `_deesc_resolve_base` falls back to `git rev-parse HEAD` (`lane-classify.sh:412`). In `_load_exempt`, apply no exemption when no real merge base resolves (Reviewers 1, 2). Add a leg to `classify-files-exempt`.
2. `mktemp` failure in `ship_rule_floor` sets `errf=/dev/null` (`ship-rules.sh:113`), which drops notices and refusals. Pass the floor's stderr straight through instead (Reviewer 2).
3. Validate everything, then emit: a parser error after some records were printed must print no record (Reviewer 2).
4. Rejection lines name the line number and cause. CRLF, BOM, spaced headers, inline tables and trailing commas fail closed with a clear message (Reviewers 2, 3). `hard_path_canaries` after the tables is valid TOML: parse the whole file before validating entries (Reviewer 3).
5. Apply the one-line array rules to `hard_path_canaries`, and refuse the config when it is malformed or multi-line (Reviewer 1).
6. Refuse the exemption config when the base `.kit.toml` holds a `"""` or `'''` string, since a table inside one would parse as an entry (Reviewer 1).
7. Cap entries at 32 and refuse past that, or join each kind's EREs into one grep, so `_path_kind` cost stays flat (Reviewer 2).
8. Escape control bytes and `|` in printed paths, and forbid `|` in `reason`, so `ship-gate.log`'s 3-field format holds (Reviewer 1).
9. Canaries are a backstop for listed paths only. Consider more built-in canaries (`db/migrate/`, `alembic/versions/`, `prisma/migrations/`, a `.tsx` login form) (Reviewers 1, 3, 5).
10. Stale merge base: a branch cut from an old main reads that commit's exemptions. Name this ceiling in ADR-0039 and `SECURITY.md`; the same holds for `lane_gates` (Reviewer 3).
11. Revoking a bad entry reaches in-flight branches only after they rebase. Say so in the Failure modes row and ADR (Reviewer 2).
12. `SECURITY.md`: name a private reporting channel (GitHub private vulnerability reporting) and state that the floor is client-side review routing, bypassable by `--no-verify` (Reviewer 1).
13. The record field order is the contract; only the reader and `_floor_scan` consume it (Reviewer 5).
14. Declare dependencies for TASK-12 (after TASK-8 to TASK-11) and TASK-13 (after all) (Reviewers 3, 4).
15. Confirm the data-loss scan has no extension filter before AC16 pins `scripts/login-smoke.sh` (Reviewer 3).
16. `migration` exemptability has no grounded false positive (Reviewers 4, 5). It is in scope by operator decision; AC13 and AC21 cover it.

## Rework validate round 2 (7 reviewers, NEEDS REVISION, 6 critical, 33 warnings)

Criticals, folded into the spec after operator approval:

- Exit-0 hook stderr reaches no one (Reviewers 1, 3). Fold: exit-0 JSON `systemMessage` plus `additionalContext` (DEC-15), Codex pin update in TASK-4.
- Nothing enforced human review of an exemption PR under mega-goal auto-merge (Reviewer 3). Fold: TASK-14, AC22, DEC-16.
- TASK-3a and TASK-5 over the AC limit (Reviewer 4). Fold: AC14 and AC16 moved; TASK-5 split into 5a and 5b.
- SECURITY.md would invent a disclosure channel (Reviewer 4). Fold: the operator approved GitHub private vulnerability reporting, now enabled on `dwarvesf/dwarves-kit`.
- No test that a migration entry leaves other migrations in force (Reviewer 2). Fold: AC21 leg 3 on `db/migrations/0001_init.sql`.

Warnings for the builder:

17. `lib/gate/battery-gate.sh:36` runs `floor` without hiding stderr, so raw TAB notices leak there. Send that call's stderr to `/dev/null`. The test-path default also flips battery RUN to SKIP for a diff with only login-named tests; list it in the CHANGELOG (Reviewers 2, 5).
18. `proof-ledger.sh:376,378` calls `floor` and `explain --files`; its negative-control answer changes under the new default. Name it in the CHANGELOG (Reviewer 5).
19. Name `[lanes] extra_hard_paths` in Edge case 2 text, ADR-0039 and SECURITY.md as the way to keep strict `auth` on a test directory (Reviewer 5).
20. Cap notices: print the first 20, then `and N more`. Write the log lines in one append with one timestamp. Add a timing leg with many login-named test paths through `ship_rule_floor` (Reviewer 2).
21. The human-facing `[advisory]` line and the `EXEMPT` log line put the path before the reason. Put the path last in both, as in the TAB notice (Reviewer 1).
22. `--files` skips are silent yet `risk --files` sizes `/kit:wrap` auto-merge (`commands/wrap.md:353`). Accept and name it in Edge case 2 text, or emit the notice (Reviewer 1).
23. `_path_kind` stops at the first kind. A test path that also hits `secret` (`tests/fixtures/credentials-login.json`) must keep scanning past `auth`. Add a `classify --files` leg (Reviewer 1).
24. Fold TAB in a path to `?` in the floor, or take the path as the rest of the line after field 6 (Reviewer 1).
25. Fold `|` and control bytes in refusal problem text before the `EXEMPT-REFUSED` log line (Reviewer 3).
26. Pin the TOML forms: no-space `paths=["a"]`, trailing comma, tabs around `=`, CRLF (strip a trailing `\r` or refuse loudly). Refuse the whole config when the token `hard_path_canaries` appears outside the recognised `[gate]` form (Reviewers 2, 3).
27. `hard_path_canaries` or exemption tables in the operator `kit.toml` are ignored. Say so in the TASK-10 comment, or warn (Reviewer 3).
28. Add tests: entry notice beats test-path notice, lowest entry number wins, duplicate kinds collapse, once per (kind, path), malformed canaries refused, duplicate key and single-quoted string refused (Reviewer 4). List AC12's parser legs under TASK-2a too.
29. TASK-7's AC: each line names a choice or fact the spec does not hold. `docs/WORKFLOW.md` range is 75-81 (Reviewer 4).
30. Notices also show in mega-merge runs, which call `ship_rule_floor`; that is intended (Reviewer 6). Check that `hooks/codex-hook-adapter.sh` passes stdout JSON through; if not, Codex users see only the log, so record it.

## Decisions made during the build

(none yet)
