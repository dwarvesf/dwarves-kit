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
