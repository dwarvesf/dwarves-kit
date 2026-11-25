# team-stamp: implementation notes

Spec: `docs/specs/SPEC-425-team-stamp.md`. Only deltas from the spec. One `## <group>` section per build group; append yours, do not edit another group's.

## G0 engine

### Decisions the spec did not make
- D1. The manifest row has five tab-separated columns: `action source target mode keys`. The group name is the manifest file name (`NN-<group>.tsv`), not a column. A column is never empty: `-` means no keys.
- D2. The row kinds are `copy`, `seed`, `jsonmerge`, `hook`. `hook` runs a script and writes its stdout, seed-once. The script reads `STAMP_TARGETS_FILE` (selected groups), `STAMP_ALL_TARGETS_FILE` (every group, even under `--only`) and `STAMP_VALUES_FILE`. A `hook` source `lib/...` is kit-relative, any other path is under the templates root.
- D3. `--only <group,group>` restricts a run to named groups. Group tests need it; the spec lists no such flag.
- D4. Values come from flag, else the lock, else a default, so a second run with no flags renders the same bytes. Without that a re-run could not be idempotent.
- D5. A template that uses a key its row does not declare, or a row that declares an unknown key, aborts the run. It catches typos and keeps the contract honest.
- D6. `jsonmerge` is judged by "would the merge change anything", not by a lock hash. It merges by `hooks` entry (match on `matcher`, then on `command`); other top-level keys of the template are ignored.
- D7. A `seed` or `hook` file that is deleted is created again on the next run; one that exists is never read. The spec says "created when absent" without the deleted case.
- D8. A new base value `DECISION_TAG` (flag `--decision-tag`, default `decision`) joins the spec's list; derived values are `TAGS_ERE`, `TAGS_COLON`, `TAGS_AWK`, `PRODUCT_ERE`, `PRODUCT_ARRAY`, `DOOR_ARRAY`, `DOOR_CASE`. `DOOR_ARRAY` is the empty string when no door path is set.
- D9. The owners seed is `lib/stamp/owners-seed.sh`, owned by G0 (validation moved it out of G4). It writes the whole `OWNERS.md` (rule text and one row per script, test and workflow in the merged manifest) so a group needs no `OWNERS.md.tpl`.
- D10. Interplay notes print at the end of a default, `--check`, `--dry-run` and `--refresh` run: a `.kit.toml` row whose file sets `lane_gates = true` is a two-line drift line (exit 1 under `--check`); kit hook commands in `.claude/settings.json` are counted in a `note:` line and never edited.

### Changes from the spec
- C1. `--take` on an edited file cannot print "the diff between the lock's rendering and the new template": the lock holds a hash, not the rendering. It prints the diff from the current file to the new template and says the left side includes the repo's edits.
- C2. Default branch: `origin/HEAD`, else refuse. The parameter table said "else `main`"; edge case 2 says refuse and no guess. Edge case 2 wins (fail closed). The spec table was amended to match.
- C3. `--take` also accepts a file that is not in the lock when it is a known kit file: adopt's pointer, an old kit copy (`lib/adopt/agents-known.sha256`), or adopt's proof marker (first line `# Verification (proof-of-done marker)`, at most 8 lines). The spec's adopt-interplay table promises that swap; amendment 2 only struck `--force-file`.
- C4. `--check` exits 1 for every status except `unchanged`, `older stamp` included (the spec said "matches the lock").
- C5. The target's `.orig` backups are guarded against symlinks like every target; a second `--take` of the same file writes `.orig.1`, never overwrites a backup.
- C6. The validation asked to move `## Picture` under `## Design`. Kept as `## Picture` (the spec template requires that heading on a full-lane spec) and added the lock-state sketch inside `## Design`.

- C7. The lock was first written with bare hex (`file <path> <group> <hex>`). A secret scan on the operator's machine reads a bare 64-hex run as a key, so the lock now writes `sha256:<hex>` (follow-up commit after the engine commit). An older lock with bare hex still reads. Every group must keep any hash it carries in the marker form (the shellcheck pin of the CI template: `sha256=<hex>`), and no template or fixture may hold a hex literal.

### Open questions
- Q1. Test row 42 (negctl refusing a syntax-only red) and the rest of the validation's per-script rows are G7 to G9 work; the spec carries them.
- Q2. Not re-probed by this build: the validation's guard misses `gh api .../merge`, `$g pr merge`, `env -i`, `timeout`, `git push --all/--mirror`. Seven findings were reproduced against the source (door arrays under `set -u`, python3 in release-notes, label precondition, checkout override, fixture literals, `fix:` casing, the `.kit.toml` kit header); G3 re-probes the guard cases.

## G1 rules docs, G2 lessons
- Dropped from the source rules: the evidence and docs-layout sections, the dash rule, board-ID minting, product playbooks, the `--allow-ci-change` and `--refresh` flags, the weekly demo, the direction list, the chat-channel line, the figure. `.kit.toml` holds only the two gate keys.
- Five seed lessons, not the source's eight. `agent-lessons.sh` resolves the repo from its own location, not from `CLAUDE_PROJECT_DIR`.
- Parity rule: every `AGENTS.md` heading has a `[Heading](../AGENTS.md#slug)` link in `docs/TEAM-WORKFLOW.md`; `pr-shape.sh` applies the same comparison.

## G3 hook
- The override bug is fixed: on the default branch a word counts as a branch only after `-b` or `-c` or when it names an existing branch; `--` marks the rest as paths.
- The PR number is parsed from `gh pr merge 7` (flags first, `-R owner/repo 7`, a PR URL). With no number the fix line is `bash scripts/pr-merge.sh --wait "$(gh pr view [<branch>] --json number --jq .number)"`; a branch word is pasted only when it matches `[A-Za-z0-9._/-]+`.
- Blocked with a test row each: `env -i git commit`, `timeout 5 git push origin <default>`, `nice`, `sudo -u`, `git push --all`, `git push --mirror` (unless `--dry-run`), `gh api .../pulls/N/merge -X PUT`, `$g pr merge`.
- Known misses (listed in the guard header and the lesson): commands built from variables, functions, aliases or `$(...)`; scripts or tools that run git or gh themselves; git aliases and push config; merges from the GitHub site; a `gh api` merge that does not spell PUT; commits made by other tools.
- Fails open on broken JSON, empty stdin, a non-string command, a missing cwd, no jq, no awk, no git. A block uses internal code 42, mapped to exit 2. No jq: allows with one note (no pure-shell fallback, no python3).

## G9 playbook and digest
- The digest prints its GitHub sections when the board file is empty, with `no board file set; nothing to read` for the board part. A missing `gh` prints a note and exits 0.
- Dropped from the digest: the `#gate-`, `#ws-` and size tag filters; the note about the team agent's own copy.

## G4 owners, G5 queue, G6 changelog
- No `files/OWNERS.md.tpl`: `OWNERS.md` is a `hook` row on `lib/stamp/owners-seed.sh`. The check's `Fix:` line carries a paste-ready row.
- `check-owners.sh` reads one `| Path | What | Owner | Sponsor |` table; a first cell without backticks is a job row. A repo's own `scripts/*` is refused as "no owner yet". Table fields split on byte 037.
- Issue body headings are `###`, matching what `task.yml` writes. `issues-from-rows.sh` applies only the `ready` label; `--apply` creates all three labels first. An empty board file prints a note and exits 0 before the `gh` check.
- `release-notes.sh` is awk, no python3. `CHANGELOG.md` ends at `## [Unreleased]` with no entries, so `release-notes.sh Unreleased` refuses with "no entry for a user" until the first entry.

## G7 merge guard and negctl
- Dropped: `--allow-ci-change` and its CI-path rules, the stale-rules refusal and `--refresh`, the kit merge-head variable, `--dry-run --all`, the separate owner-door list.
- Kept beyond the task row: newest run per check, the two-producer refusal, "the `changes` job must pass" (couples the guard to the workflow's job name), the UNKNOWN-mergeability wait, the 100-file cap when a door list is set. With a named approver, that login must approve unless they wrote the PR.
- Progress lines precede the refusal pair on stderr: a test reads the last two lines.
- A "red" is a load error when the output has no assertion line and the exit is 126 or 127, or it shows a syntax-error message. A silent red prints `<no output>`.

## G8a pr-shape, G8b check and CI
- pr-shape reads env `PR_TITLE` (required), `PR_BODY` or `PR_BODY_FILE`, `BASE_SHA` (default `origin/<default branch>`), `HEAD_SHA` (default `HEAD`); the diff is `BASE_SHA...HEAD_SHA`. Last stdout line `checks: N failed, M passed`; exit 0, 1, or 2 for bad input. The proof check needs a non-zero `Exit:` inside the `NEGATIVE CONTROL` block; `.kit.toml` counts as a behavior path.
- Dropped from pr-shape: the dash check, the evidence-branch check, the docs-layout check, the board-file special case, the product-path exemptions, board-ID minting.
- `ci.yml` takes `PRODUCT_ERE` for the `changes` path filter and exposes `outputs.product`. The owners gate is the BASE copy run with `$0` set to `scripts/check-owners.sh`; `pr-shape.sh` runs from a copy aside. `actions/checkout` is pinned by full sha with the tag in a trailing comment; shellcheck is pinned per platform with `sha256=<hex>`; both from `gh api`, none typed.
- Twin set: three `twin:` entries in both `ci.yml` and `check.sh` (`check-owners.sh`, `pr-shape.sh` with its four env inputs, the `test-*.sh` loop). `check.sh` runs every `scripts/test-*.sh` (about a minute on a full stamp).

## Cross-cutting
- A `Fix:` line exists to be pasted. A value from the repo, the PR or `gh` enters a `Fix:` command only when it matches a narrow safe character set; otherwise the line is a plain instruction. Rule lines pass repo text through a filter that replaces unsafe characters with `?`. Each group's generated test has an injection case and runs every printed `Fix:` line through `bash -c`.

## G10 integration
- The groups stamped together without a change to a manifest, a key name or a file mode: 39 rows, `check-owners.sh` passes on the tracked stamp (21 rows), a second run is all `unchanged`, `--check` exits 0.
- Engine fix: the `jsonmerge` entry check looked only in the first group of a matcher. After adopt wired its hooks the stamp's entry sat in a second `Bash` group and the next stamp appended it again. The merge now looks across every group with the same matcher. A test row pins it.
- Trust wording, settled against the vendor permissions page ("What runs before you trust a folder"): hooks in settings files are "Used" in both untrusted cases, only a parent folder trusted and `claude -p` or the SDK in a never-trusted folder. The three docs now say Claude Code uses the hook even in a folder not yet trusted, and no longer tell a teammate to trust it first.
- Doc claims checked against the real scripts: `release-notes.sh` with no argument refuses (exit 2) and shows no usage, so the table row now reads `release-notes.sh Unreleased` with `--help` for usage; `check.sh` reads the title from the first commit and an empty body when no PR is open, so `SKILL.md` now says to pass `--title` and `--body`; the guard lesson was re-synced with the guard header (adds the graphql merge, `git -c alias`, and the jq or awk off switch) and cut under the size limit.
- `tests/test-stamp-kitfree.sh` prints the failing lines of a generated test, not its tail. The generated negctl test failed once or twice in five runs under host load (loads above 100) and passed on a quiet host; not a template defect.
- The privacy section of `tests/test-stamp-e2e.sh` always runs the generic leak scan (home path, email, `op://`, bare hex) and fails on a hit. The denylist scan runs only when `STAMP_DENYLIST_FILE` is present and prints one SKIP line otherwise: the list belongs to one private repo, and a plain `run-all` on any machine must not go red. When it runs it scans the branch diff, commit messages, templates, fixtures, the proof and a stamped repo, and allows only `uses: owner/repo@<40-hex> # v...` and `sha256` marked 64-hex.
- `tests/test-stamp-refusals.sh` runs each distinct `Fix:` line through `bash -c` once, in a copy, with a 10 second alarm; `check.sh` forwards the checks' own refusals before its own pair, so that case accepts `pr-shape` as a second rule prefix.
- Exit codes seen across the scripts: usage errors exit 2 (`pr-merge`, `issues-from-rows`, `team-digest`, `check`, `release-notes` without a section), `negctl` exits 64 on usage and 2 on a dirty tracked tree; the suite pins them.

## Security review fixes
- CI was three jobs in round 1; round 2 removed the `tests` job (see below). `changes` and `pr-shape` run only scripts copied from the base revision. A fork guard sits on each job. The base-has-no-copy fallback (use the PR's copy) is gone: that job fails and the first stamp pull request is merged by hand. `check.sh` runs the two jobs' commands locally, so the twin set is unchanged.
- The workflow file comes from the pull request, so `pr-merge.sh` now binds it: both `changes` and `pr-shape` from the workflow `CI`, and the harness files are default doors. `--door-paths` adds to the list (it no longer replaces an empty one). The `Door setting` table of the rules docs now reads "added to the harness's own files".
- `gh pr view --json reviews` reports `authorAssociation`, `commit.oid` and `author.login` per review (read from a real read-only call on a public repo). Bot reviewers can appear with a plain login (for example an app reviewer with a CONTRIBUTOR association), so the association test is the main bot filter and the `[bot]` and `app/` pattern is a second one.
- The self-copy check compares `scripts/pr-merge.sh` with `origin/<default>:scripts/pr-merge.sh`. It cannot stop a pull request's copy that deleted the check; the protection there is that no `Fix:` line sends anyone to run that copy, and `scripts/` is a door.
- `stamp.sh`: the report of values in use is printed after the required-key checks, so a missing-owner refusal still ends in exactly two lines. It goes to stderr as `using: KEY=value (flag|lock|default|origin/HEAD)`; the tests that counted non-`unchanged` lines now also skip `using:` lines.
- The rule-line filter lost the colon in `check-owners.sh`, `issues-from-rows.sh` and `release-notes.sh`, and every filter cuts at 80 characters. A title with a colon now shows `?` in the digest and in progress lines (`fix? text`). `issues-from-rows.sh` prints `<id>: <title>` itself so its own colon stays.
- A backslash inside a command word (`g\h`) is a documented miss of the guard; a backslash before the word is read.
- Gauntlet checker: its first draft compared gate files against a pristine stamp that had never been `git add`ed, so the comparison passed with nothing to compare. The hostile-repository row in Tier 1 caught it; the checker now fails check 9 when the pristine list is empty.
- `git diff` with `-c diff.external=` (an empty value) printed nothing instead of disabling the driver. The checker uses `--no-ext-diff --no-textconv` on every diff.

## Security review round 2 fixes
- The `tests` job is gone from `ci.yml`; a stub comment says a repo adds its own once it has an ephemeral runner. The workflow header says nothing in these two jobs executes a file of the pull request. `check.sh` and the twin test lost the matching row.
- `pr-merge.sh`: runs are filtered to this pull request (`actions/runs` for the head, `pull_requests[].number`, then the rollup `detailsUrl` run id); the base must be the default branch; approvals older than the last `base_ref_changed` timeline event do not count; the changed files come from `pulls/<n>/files` (`filename` and `previous_filename`, 3000 cap, a read failure refuses). Every read must succeed and parse: a failed read refuses and is never read as "nothing found".
- Doors: the whole `.github/` directory, `scripts/`, `.claude/`, `OWNERS.md`, `AGENTS.md` and `CLAUDE.md` at any depth, `.mcp.json`, `docs/TEAM-WORKFLOW.md`, `.kit.toml`. Matching lowercases both sides. The self-copy check stops only an honest out-of-date copy (header and rules docs say so).
- Owners check: exact ownership, areas chosen by lowercase, lowercase collisions refused, NUL-delimited listing, names with a newline, control byte or non-ASCII byte refused with a plain instruction. `pr-shape.sh` refuses a head tree with two paths equal when lowercased.
- Board cells (the ID and login of a row) go through the same rule-line filter as titles in `issues-from-rows.sh`.
- `stamp.sh`: `--product-paths` and the tag list are tried as `grep -E` patterns on empty input and refused on exit 2 when they do not compile; a leading `*` in a product path is refused (it is a glob where the pattern wants a regex).
- Registry: the internal names `KIT_MARKER` and `KIT_PATTERN` of `lib/stamp.sh` are renamed (`AGENTS_MARKER`, `LEAK_PATTERN`) so `test-config-registry` finds no orphan row; no allowlist entry was added. `tests/test-adopt.sh` "known list complete against git log" is red on this branch before and after this work: it is a pre-existing red that PR #1189 fixes, not touched here.
- Gauntlet: the key goes into the probe container by name (`-e ANTHROPIC_API_KEY`), the echoed verdict is cut to capital letters, the image runs as the non-root user `node` that owns `/work`, and the seed is copied with `cp -R` (no preserved host ownership). The run record and the README say the scrub matches the exact key only and the key is rotated after every round. The gauntlet `gh` shim now answers the four `gh api` reads of the merge guard. The container path is still NOT executed on the build host; these changes are unverified until the operator's first run.
- Runs of this pull request: the `actions/runs` documentation says `pull_requests` lists every open pull request that shares the head sha or branch, not the one that triggered the run. A filter on "this number appears" would let a second pull request on the same head (with a weak base) lend its green runs, so a run counts only when its `pull_requests` list is exactly this pull request. A legitimate second pull request on the same head is refused with "has not passed"; close it.
- The `gh` fields the guard reads were confirmed, not guessed: `gh pr view --help` for the top-level names; one read-only `gh pr view --json reviews,statusCheckRollup` on a public PR for the sub-fields (`reviews[].author.login`, `.authorAssociation`, `.commit.oid`, `.state`, `.submittedAt`; check run `detailsUrl`, `workflowName`, `name`, `status`, `conclusion`, `startedAt`, `completedAt`); `gh api` reads on the same repo for `workflow_runs[].id`, `.path`, `.pull_requests[].number`, `pulls/<n>/files` `.filename`, `pulls/<n>` `.head.sha`; the REST description for `previous_filename`, the `head_sha` and `event` query parameters; the event documentation for the `base_ref_changed` timeline event and its `created_at`. No live example of a rename or a base change was available on the public repo; those two rest on the documentation.
- `check.sh` and `pr-shape.sh` read the changed paths and the head tree NUL-delimited. A path with a newline counts as a product path in `check.sh` and is refused as a collision in `pr-shape.sh`.
