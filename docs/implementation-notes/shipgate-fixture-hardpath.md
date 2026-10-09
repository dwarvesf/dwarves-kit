# Implementation notes: shipgate-fixture-hardpath

Delta from `docs/specs/SPEC-400-shipgate-fixture-hardpath.md` (the per-kind glob rework). The first build's notes are superseded; its decisions live in git history at `c28ef8c4`. The validate rounds are folded into the spec; this file keeps only what the spec does not hold.

## Open for the operator

- `cases` stays in the test-path list. Two reviewers asked to drop it as too generic; the operator listed it explicitly. Revisit if an adopter reports a real auth hit hidden under a `cases/` directory.

## Builder items from the validate rounds

Numbers keep the validate-round numbering. Items not listed were folded into the spec before the build.

| Item | What | Status |
|---|---|---|
| 1 | `--files` must not fall back to HEAD as the merge base | Resolved (leg in `classify-files-exempt`) |
| 2 | `mktemp` failure drops notices | Resolved (floor stderr passes straight through) |
| 3, 4, 5, 6, 7, 26 | Reader hardening: validate before emit, CRLF and BOM, canary array rules, triple quotes, 32-entry cap, TOML forms | Resolved (`exempt-reader-rejects`) |
| 8, 25, 33, 34 | Fold control bytes, non-ASCII and `\|` in printed paths, globs and reasons | Resolved (`_sr_relay`) |
| 9 | More built-in canaries (`db/migrate/`, `prisma/migrations/`) | Not done: the spec keeps the built-in list unchanged. File a follow-up if wanted |
| 10, 11, 12, 19, 22, 35 | Name the stale merge base, revocation lag, `--no-verify`, `extra_hard_paths`, silent `--files` skips, local remote refs and unguarded merge paths | Resolved in `docs/decisions/0039-hard-path-exempt-at-merge-base.md` and `SECURITY.md` |
| 15 | Data-loss scan has no extension filter | Confirmed by `floor-exempt-data-loss-still-hits` on a `.sh` file |
| 17, 18, 45 | Battery stderr leak, battery and proof-ledger answers change, `.kit.toml` PRs need a human merge | Resolved (code) and listed in `docs/CHANGELOG.md` |
| 20, 32 | Notice cap, one log append | Resolved (20 test-path notices, entries never cap) |
| 21 | Put the path last in the human line | Not done: the spec fixes path-before-reason; the TAB notice stays the machine contract (see below) |
| 23 | `_path_kind` keeps scanning past `auth` on a test path | Resolved (credentials-login leg in `floor-test-paths-other-kinds`) |
| 27 | Operator `kit.toml` ignores exemption keys | Resolved (comment in `kit.toml`) |
| 28 | Extra reader and notice cases | Resolved (`exempt-reader-rejects`, `floor-exempt-notice-rules`) |
| 30, 38, 48 | Codex and mega-merge notice reach | Resolved as documented: Codex logs only; mega-merge fills `SR_NOTICES` and prints nothing more |
| 31 | `--match-head-commit` on `gh pr merge` | Not done (see below); named in `SECURITY.md` |
| 36 | Timing case through `ship_rule_floor` | Not done: only `floor-timing` and `floor-timing-30k` cover the floor. The log is one append and test-path notices cap at 20 |
| 37 | Large PR file list | Resolved as fail closed (see below) |
| 39 | One exit helper for the hook JSON | Not done: the JSON is emitted once at the end of `_floor_check`; the later `lane-suggest` advisory stays on stderr |
| 40 | Cite `batch-debt-warn.sh:37`, not `context-budget.sh:132` | Not done: the precedent line stays in the spec; no doc cites either |
| 41, 42, 43, 44 | Registry line for `MEGA_MERGE_PR_FILES_CMD`, `HOOK_OUT` in `run_hook`, push-notice framing and cut legs, merge-guard reason text | Resolved |
| 46 | Put the `kit.toml` example last in `[gate]` | Resolved |
| 47 | Add the hook JSON emitter and merge guard to the diagrams | Resolved in the ADR; the spec's own diagrams stay as validated |

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
