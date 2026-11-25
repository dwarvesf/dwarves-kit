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
- The privacy section of `tests/test-stamp-e2e.sh` fails when `STAMP_DENYLIST_FILE` is unset, scans the branch diff, commit messages, templates, fixtures, the proof and a stamped repo, and allows only `uses: owner/repo@<40-hex> # v...` and `sha256` marked 64-hex.
- `tests/test-stamp-refusals.sh` runs each distinct `Fix:` line through `bash -c` once, in a copy, with a 10 second alarm; `check.sh` forwards the checks' own refusals before its own pair, so that case accepts `pr-shape` as a second rule prefix.
- Exit codes seen across the scripts: usage errors exit 2 (`pr-merge`, `issues-from-rows`, `team-digest`, `check`, `release-notes` without a section), `negctl` exits 64 on usage and 2 on a dirty tracked tree; the suite pins them.
