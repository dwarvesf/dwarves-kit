# Proof of done: registry-skill-dispatchers

## Acceptance criteria

| AC | Claim | Status |
|---|---|---|
| AC-1 | `dispatched_by` also greps `skills/*/SKILL.md`; skill dispatchers rendered as `<name> (skill)` | MET (run 1) |
| AC-2 | `audit-scanner` row shows `doc-drift (skill), feature-map (skill)` instead of `-` | MET (run 1) |
| AC-3 | Regenerated `docs/FEATURES.md` committed; freshness pin green | MET (run 2) |
| AC-4 | Test coverage: assertion that audit-scanner's dispatched-by cell names both skills | MET (run 2) |
| AC-5 | Determinism: double run byte-identical | MET (run 2) |
| AC-6 | Negative control: agent token renamed in one skill file drops that skill from the cell | MET (run 3) |

## Confirmation runs

| # | Check | Command | Result |
|---|---|---|---|
| 1 | before/after cell | `bash lib/registry/feature-registry.sh generate` then grep the row | before: `\| audit-scanner \| [D] \| - \|`; after: `\| audit-scanner \| [D] \| doc-drift (skill), feature-map (skill) \|` (also `agent-effectiveness` correctly gains `loop-engineering (skill)`) |
| 2 | full suite incl. freshness + determinism + new assertion | `bash tests/test-meta.sh` | 742/742 PASS, exit 0 |
| 3 | negative control | `sd 'audit-scanner' 'audit-scannerX' skills/doc-drift/SKILL.md`, regenerate to a temp outfile, grep, restore | cell drops to `feature-map (skill)` only; skill file restored via `git checkout --` |

## Run detail

Run 1: the regenerated projection changed exactly three rows: the header blurb (Dispatched-by scope now names `skills/*/SKILL.md`), `audit-scanner` (the target fix), and `agent-effectiveness` (picked up `loop-engineering (skill)`, a genuine skill dispatcher previously invisible). No other rows moved.

Run 2: the first `test-meta.sh` run after adding the new assertion FAILED the freshness pin, because the assertion's own tokens (`audit-scanner`, `doc-drift`, `feature-map`) added `test-meta.sh` to those rows' Tests columns. A second regeneration converged; re-run is 742/742 with the determinism double-run green.

Run 3: with the token renamed in `skills/doc-drift/SKILL.md`, a temp regeneration shows the cell as `feature-map (skill)` only, proving the derivation reads the skill files and discriminates per file.

## Reproduce

```
bash lib/registry/feature-registry.sh generate && grep '`audit-scanner`' docs/FEATURES.md
bash tests/test-meta.sh
sd 'audit-scanner' 'audit-scannerX' skills/doc-drift/SKILL.md
T=$(mktemp); bash lib/registry/feature-registry.sh generate "$T"; grep '`audit-scanner`' "$T"   # expect feature-map (skill) only
git checkout -- skills/doc-drift/SKILL.md
```
