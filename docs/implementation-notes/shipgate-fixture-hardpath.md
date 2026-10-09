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

## Rework validate round 3 (7 reviewers, NEEDS REVISION, 1 critical, 33 warnings; round ceiling reached)

A fold-diff check before round 3 found that the first DEC-16 guard matched key names in changed lines, which an edit to only an entry's `paths =` line bypasses. The guard became file-level.

Critical, folded after the round closed: the `.kit.toml` rule inside `_merge_exclusion` would make `mark` report a held PR that is not held (Reviewers 5, 2, 3). Fold: a separate `_merge_config_guard`, called from `merge()` only, plus AC22 leg 6.

Warnings for the builder:

31. Race: `merge()` runs `gh pr merge` with no `--match-head-commit`. Read the head SHA with the file list and pass it, so a push between the check and the merge cannot slip in a `.kit.toml` edit (Reviewers 1, 2).
32. A notice cap must never hide an entry-sourced notice, and it must print the hidden total per kind and source. Test-path notices may collapse after 20 (Reviewer 1). This overrides item 20's plain cap.
33. Item 21 extends: fold non-ASCII bytes (bidi controls such as U+202E) in displayed paths to `?` too (Reviewer 1).
34. Item 25 extends: apply the `|` fold to the `WARNING` line and the JSON as well as the log (Reviewer 1).
35. SECURITY.md: the merge base comes from local remote-tracking refs, which a local agent can rewrite; name `wrap merge --apply` among the unguarded merge paths (Reviewers 1, 3).
36. Notice flood can exceed the 30 s hook timeout, and a timeout lets the push through. Write the log in one append, cap test-path notices, and add a timing case through `ship_rule_floor` to Verification. Point the "Reader slows the hook" Failure modes row at it (Reviewer 2).
37. Large PRs: `gh pr diff --name-only` may hit GitHub's diff limit and refuse as unclassifiable (fail-closed). Never swap in `gh pr view --json files`, which caps at 100 files and fails open. The safe alternative is `gh api --paginate .../pulls/<n>/files` or local `git diff --name-only` from `gate()`'s resolved base and head. Record the choice (Reviewers 2, 5).
38. On a successful mega merge, `gate_out` notices are discarded. Print the `[advisory]` lines on success too, or correct item 30 (Reviewers 2, 3).
39. Emit the exit-0 JSON from one `_exit_ok` helper or an EXIT trap gated on status 0, so the later `lane-suggest` advisory (`ship-gate.sh:451-454`) can join `SR_NOTICES` (Reviewer 5).
40. Cite `hooks/batch-debt-warn.sh:37` (a PreToolUse `additionalContext` emitter) as the precedent, not `context-budget.sh:132`, which is UserPromptSubmit (Reviewers 4, 5).
41. Add `MEGA_MERGE_PR_FILES_CMD` to `lib/config/module-registry.md` beside `MEGA_MERGE_PR_INFO_CMD` (Reviewer 5).
42. `tests/test-lanes-data.sh:334-336` runs the hook with `2>&1 >/dev/null`; change the helper so AC19 and AC20 can read stdout JSON (Reviewer 4).
43. Add AC20 legs for the framing line, the 300-char cut and the `?` fold of `|` in a path (Reviewer 4).
44. AC22 legs (1) and (2) reduce to the same file list; keep both for the record but assert the reason text `touches .kit.toml` (Reviewer 4).
45. CHANGELOG (TASK-8): every mega-goal PR that edits `.kit.toml` now needs a human merge (Reviewer 4).
46. TASK-10: put the commented `[[gate.hard_path_exempt]]` example at the end of the `[gate]` block; keys written after that header belong to the table (Reviewer 3).
47. Picture and Design diagrams do not draw the hook JSON emitter or `_merge_config_guard`; add them when TASK-6 rewrites the ADR (Reviewers 4, 6).
48. Mega-merge `ship_rule_floor` calls fill `SR_NOTICES` but emit nothing; intended for a script caller (Reviewer 6).

## Decisions made during the build

- Test-path notice case `floor-test-path-notice` landed with the matcher change, not with the output relay: the notice line is born in `_floor_scan`, so its stderr shape is pinned where the code is written.
- Legacy first-build exempt cases moved to `scripts/login-smoke.sh` and `^scripts/` entries so they stay green until the table reader replaces them.
- The reader refuses the file when `"""` or `'''` appears and a `[[gate.hard_path_exempt]]` header exists. A triple quote with no such header stays silent.
- A rejection that is not tied to one entry prints `config at <sha>` in place of `entry <n> at <sha>`. It covers bad headers, a stray `hard_path_canaries`, multi-line strings and the 32-entry cap (builder item 7).
- Only the first problem per entry prints, so a malformed entry gives exactly one line.
- BOM and CRLF are stripped, then parsed (builder item 26). The BOM is cut by `substr`, because the awk on macOS does not read `\357` octal escapes inside a regex.
- The reader skips the awk run when the file holds neither `hard_path_exempt` nor `hard_path_canaries`, so a repo with no config pays one `git show` and one grep.
- The all-wildcard glob rule is partly redundant with the canary check: `**` or `*` also matches a built-in canary. The test pins the all-wildcard message itself, so the rule stays covered if canaries change.
- Entry numbers count every `[[gate.hard_path_exempt]]` table in file order, valid or not. A kind listed twice in one entry collapses to one record.
- The floor cases for AC14, AC15 (floor legs), AC16 and AC17 and the cases `floor-exempt-glob-bounded` and `floor-exempt-notice-rules` landed with the helper rewrite in the floor-filter task, not in the later case tasks. They share the new `exempt_repo <paths> <kinds> [<reason>]` helper, so leaving the first-build versions red would have meant writing them twice.
- `floor-exempt-empty-match-rejected` is gone. Its job moves to the reader cases (`exempt-reader-rejects`) and to the floor-level rejection cases.
- Between the floor-filter and ship-rules tasks `ship-exempt-logged` is red: it still expects the first-build `floor: exempt` log line. The ship-rules task rewrites it.
- The floor builds one blanked list per exemptable kind (`pl_auth`, `pl_migration`) and one `grep -nE -e <ere>` per record. It does not use `grep -f`, so no pattern file can hold an empty line.
- `--files` finds the merge base with `git merge-base HEAD <default branch>` and applies no exemption when that fails. It does not call `_deesc_resolve_base`, whose last resort is HEAD itself (builder item 1). `_load_exempt` runs in `_files_hard_hit` before the per-path subshells, so the config is read once per call, not once per path.
- A rejected config prints nothing in `--files` mode (stderr dropped). The push shows the refusal through the floor.
- Spec and builder item 21 conflict: the spec fixes the advisory text as `hard-path exempt <kind>: <path> by ... entry <n> (paths: ...; reason: ...)`, path before reason. The spec wins. A wildcard-matched path with spaces can therefore imitate the trailing `(paths: ...)` text on that one human line. The TAB notice (path last) stays the machine contract, the framing line marks the block as data, and the `EXEMPT` log line puts the path inside the parenthesis before `entry`.
- Display folding follows builder item 33, wider than the spec: every byte outside printable ASCII and every `|` in a printed path, glob or reason becomes `?` in the advisory, the log and the JSON. The floor stdout and the BLOCKED text keep the real path.
- Test-path notices cap at 20 per push, then one `[advisory] hard-path skip auth: N more test paths` line (items 20 and 32). Entry notices and refusals never cap. The log holds the same lines, written in one append under one timestamp.
- The `WARNING` text carries `entry <n>` or `config` before the problem, so the line says which table was wrong.
- No scratch file from `mktemp`: the floor runs with its stderr unredirected, so the raw TAB lines reach the caller (builder item 2). Nothing is parsed.
- `battery-gate.sh` sends the floor call stderr to `/dev/null` (builder item 17), so raw TAB notices never leak into the size gate. No new test; `test-battery-gate.sh` stays green.
- The exit-0 JSON is emitted once, at the end of `_floor_check`. The later `lane-suggest` advisory in the hook (builder item 39) stays on stderr: it never rode `SR_NOTICES`. Mega-merge calls fill `SR_NOTICES` and print nothing more (items 38 and 48 accepted as intended).
- `run_hook` now returns the hook stdout in `HOOK_OUT` (builder item 42).
- Builder item 31 (pass `--match-head-commit` to `gh pr merge`) is not done. The spec names no head-sha read, and a second `gh` call would need its own stub in every merge test. The residual: a push between the file check and the merge can add a `.kit.toml` edit. The fail-open trust model already covers unguarded merge paths.
- Builder item 37: `gh pr diff --name-only` can fail on a very large PR. The guard then refuses as unclassifiable (fail closed). `gh pr view --json files` is not used because it caps at 100 files and fails open.
- An empty file list also counts as unreadable (return 2): a PR with no listed files cannot be classified.
- The unreadable-list refusal says `cannot classify`, a different text from the state-unreadable refusal, so the two causes read apart in the log.
- `MEGA_MERGE_PR_FILES_CMD` is in `lib/config/module-registry.md` beside `MEGA_MERGE_PR_INFO_CMD` (builder item 41). `tests/test-meta.sh` shows one failure, `docs/FEATURES.md is fresh`, a generated file the doc-refresh task owns.
- `floor-exempt-malformed-rejected` pins the rejection count (exactly one `lane-data:` line per bad entry) and the `full auth` stdout. The per-message wording is pinned at the reader in `exempt-reader-rejects`, so a message edit breaks one place.

## Negative controls

| Case | Mutation | FAIL seen |
|---|---|---|
| `floor-test-paths-other-kinds` | floor greps non-auth kinds over the test-path-blanked list | yes |
| `floor-test-paths-not-auth` | `apaths` reset to the full list (rule not wired) | yes |
| `floor-test-paths-not-auth` | `_path_kind` auth skip deleted | yes |
| `floor-test-paths-other-kinds` | `_path_kind` skips test paths for every kind | yes (credentials-login leg) |
| `exempt-reader-rejects` | kind allowlist removed | yes |
| `exempt-reader-rejects` | reason and missing-key checks removed | yes |
| `exempt-reader-rejects` | single-bracket header accepted | yes |
| `exempt-reader-rejects` | trailing comma accepted | yes |
| `exempt-reader-rejects` | `\|` in reason allowed | yes |
| `exempt-glob-semantics` | record ERE left unanchored | yes |
| `exempt-glob-semantics` | `*` translated to `.*` | yes (after adding the `login-a/b.sh` and `a/b/cases` rows; the first rows missed it) |
| `exempt-glob-semantics` | `?` rewritten after `**/` in a second pass | yes |
| `exempt-reader-rejects` | canary comparison disabled | yes |
| `exempt-reader-rejects` | all-wildcard check disabled | yes (message leg) |
| `exempt-reader-rejects` | `**` inside a segment allowed | yes |
| `exempt-reader-rejects` | user canaries not loaded | yes |
| `floor-exempt-per-kind` | migration reads the auth-blanked list | yes |
| `floor-exempt-migration-only` | a kind with no records blanks every path via an empty pattern | yes (legs 2 and 3) |
| `floor-exempt-notice-rules` | test-path scan reads the original list, so an entry does not win | yes (notice count 2) |
| `floor-exempt-notice-rules` | per-line entry numbers not deduplicated, so the highest entry wins | yes |
| `floor-exempt-real-auth-still-hits` | any non-empty record set blanks the auth list | yes |
| `floor-exempt-working-tree-ignored` | reader reads the working-tree `.kit.toml` | yes |
| `classify-files-exempt` | `--files` reads the exemption at HEAD | yes (branch-only leg) |
| `classify-files-exempt` | merge base falls back to HEAD | yes (no-merge-base leg) |
| `classify-files-exempt` | auth entries not applied | yes |
| `classify-files-exempt` | auth skip reads the migration entries | yes (needed the `sql/auth/login.ts` leg) |
| `ship-test-path-skip-visible` | relay drops test-path notices | yes |
| `ship-exempt-logged`, `ship-test-path-skip-visible` | hook keeps notices on stderr (no JSON) | yes |
| `ship-exempt-logged` | reader rejection lines not relayed | yes |
| `ship-exempt-logged` | notices logged, not printed | yes |
| `ship-test-path-skip-visible` | test-path cap removed | yes |
| `ship-test-path-skip-visible` | `\|` in a path not folded | yes |
| `ship-test-path-skip-visible` | 300-character cut removed | yes |
| `ship-exempt-in-pr-blocks` | `_floor_check` disabled | yes |
| `test-codex-hooks` | `ship-gate.sh` edited without a repin | yes (2 FAIL) |
| `mega-merge-refuses-exempt-change` | `merge()` without the guard call | yes (legs 1, 2, 5) |
| `mega-merge-refuses-exempt-change` | guard matches `.kit.toml` as a substring | yes (leg 4) |
| `mega-merge-refuses-exempt-change` | guard moved into `_merge_exclusion` | yes (legs 1, 2, 5, 6) |
| `mega-merge-refuses-exempt-change` | unreadable list treated as clear | yes (leg 5) |
| `floor-exempt-forbidden-kinds-rejected` | kind allowlist removed | yes |
| `floor-exempt-forbidden-kinds-rejected`, `floor-exempt-reason-required` | refusal ignored, valid entries still apply | yes |
| `floor-exempt-reason-required` | reason and missing-key checks removed | yes |
| `floor-exempt-canary-rejected` | canary comparison off | yes |
| `floor-exempt-canary-rejected` | user canaries not loaded | yes (leg B) |
| `floor-exempt-malformed-rejected` | `**` inside a segment allowed | yes |
| `floor-exempt-malformed-rejected` | single-bracket header accepted | yes |
