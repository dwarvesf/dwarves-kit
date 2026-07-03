# Proof of done: v2.0.0 release cut , PREPARED and HELD (SPEC-115, kit-face wave)

v2.0.0 is one click from shipped: changelog authored, three version surfaces aligned + pinned,
BREAKING rename map + consumer grep, HELD-pair review recorded, tag/Release text as files. The PR is
HELD for Han , the loop NEVER tags, merges, or publishes (gate + final).

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | HELD-pair review round (#117 + #124) done FIRST, findings recorded | PASS (both SHIP-AS-IS; `docs/releases/v2.0.0/held-review.md`) |
| 2 | CHANGELOG covers the waves + follow-ups in the v1.7.0 per-spec house style | PASS ([2.0.0] section) |
| 3 | BREAKING section maps all THREE renames + a consumer-repo grep capture | PASS |
| 4 | Three version surfaces at 2.0.0 (VERSION, plugin.json, tool.toml , the last was drifted at 1.6.0) | PASS |
| 5 | New three-surface parity pin (test-meta) locks them together | PASS |
| 6 | Tag narrative + GH Release body PREPARED as files, NOT executed | PASS |
| 7 | The [Unreleased] hold lifts (its condition, kit-hardening, is met) + fresh empty [Unreleased] | PASS |
| 8 | test-meta + all 12 CI green | PASS (662/662) |
| 9 | PR opened + HELD (loop never merges/tags/publishes) | HELD |

## Implementation

- `VERSION` 1.7.0->2.0.0; `.claude-plugin/plugin.json` 1.7.0->2.0.0; `tool.toml` 1.6.0->2.0.0.
- `tests/test-meta.sh`: the third-surface pin (`tool.toml version == VERSION`), joining the existing
  plugin.json==VERSION pin , the v1.7.0 cut missed tool.toml; this three-surface pin kills that class.
- `CHANGELOG.md`: `[Unreleased]` -> `[2.0.0] - 2026-07-03` (hold blockquote removed), a BREAKING
  section (3-rename table + consumer-grep result), per-spec kit-face bullets (#128-136), the prior
  accumulated waves retained; a fresh empty `[Unreleased]` on top.
- `docs/releases/v2.0.0/`: `tag-message.txt` (annotated-tag narrative), `release-body.md`
  (`gh release create` body), `held-review.md` (the #117/#124 findings).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| 3 surfaces at 2.0.0 | `cat VERSION; jq -r .version plugin.json; grep ^version tool.toml` | all 2.0.0 | all 2.0.0 |
| 3-surface pin | `bash tests/test-meta.sh` (tool.toml == VERSION) | PASS | PASS |
| BREAKING map | `grep -c 'integration-verifier\|code-reviewer\|security-reviewer' CHANGELOG.md` (in BREAKING) | 3 renames | present |
| consumer grep | `grep -rl integration-checker\|security-auditor ~/workspace/tieubao/* (excl kit)` | historical only | notes/templates, no live dispatch |
| tag/release files | `ls docs/releases/v2.0.0/` | 3 files | tag-message.txt, release-body.md, held-review.md |
| suite | `bash tests/test-meta.sh` | green | 662/662 |
| all CI | 12 suites | green | all pass |

## What Han does (the manual, gated step , NOT done by the loop)

```bash
git switch master && git pull                 # after merging this PR
git tag -a v2.0.0 -F docs/releases/v2.0.0/tag-message.txt
git push origin v2.0.0
gh release create v2.0.0 --title "v2.0.0 , production-facing + cost-measured" \
  --notes-file docs/releases/v2.0.0/release-body.md
```

## Reproduce

```bash
cd dwarves-kit
cat VERSION; jq -r .version .claude-plugin/plugin.json; grep '^version' tool.toml   # 3x 2.0.0
bash tests/test-meta.sh   # 662/662, incl. the 3-surface pin
```
