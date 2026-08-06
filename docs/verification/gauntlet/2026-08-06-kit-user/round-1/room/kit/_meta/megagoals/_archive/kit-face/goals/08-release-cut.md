# Sub-goal 08: release cut v2.0.0 (PREPARED and HELD)

**Merge policy:** gate , outward publish; the loop prepares everything, Han tags and publishes.
**Time budget:** 3-4 hours (the changelog authoring IS the work: ~24 merged PRs have zero entries).
**Proof:** run-table: HELD-pair review round done first (fresh-context review over #117 + #124 diffs, findings surfaced) · CHANGELOG covers #101-#124 + follow-ups in the v1.7.0 per-spec house style · BREAKING section maps all THREE renames with a consumer-repo grep capture · three version surfaces bumped (VERSION, .claude-plugin/plugin.json, tool.toml , the last already drifted at 1.6.0) AND the new three-surface parity pin green · tag narrative + GH Release body PREPARED as files, NOT executed.
**Depends on:** ALL (01-07 merged; cut at HEAD so their SHAs + the wavefront docs ride).
Model: opus
Effort: high
**Branch:** feat/kit-face-08-release
**PR base:** master (created last)

## Outcome

v2.0.0 is one click from shipped. The `[Unreleased]` hold lifts (its stated condition, kit-hardening completing, is met); the changelog authors kit-hardening (#101-109), kit-telemetry (#112-117), the follow-ups (#118-124), and this wave, per-spec bullets grouped Added/Fixed/Changed with the wave named in each lead-in; a **BREAKING** lead maps `integration-checker->integration-verifier`, `reviewer->code-reviewer`, `security-auditor->security-reviewer` with a migration note, plus a grep across consumer repos for stale old-name references (captured); VERSION + plugin.json + tool.toml all read 2.0.0 and a test-meta pin keeps the three surfaces locked together (the v1.7.0 cut missed tool.toml , the pin kills that class); ADR-0030 + SPEC-106 (DAG-wavefront) ride as a design-only Docs bullet. The tag message narrative + `gh release create` body are prepared as files in the PR; executing them is Han's click (the convention stays manual, ship.md not extended for a once-per-cycle step).

## Quality bar

The changelog is authored from commit messages + specs, dense per-spec bullets matching v1.7.0's register , not three vague wave summaries. Cutting the tag BLESSES the two HELD commits: the review round runs FIRST and its findings go to Han before anything else in this sub-goal proceeds. Nothing in this sub-goal pushes a tag or creates a Release.

## How to close the loop

The HELD review round, then `/spec` + `/spec-validate` (light , the spec is mostly the checklist above), then authoring + bumps + pin. `bash tests/test-meta.sh` (new pin green) + the consumer grep capture + `gh pr checks`. Assumptions: ROADMAP 08 block.

**Done =** PR open with: HELD-review findings recorded, complete changelog, three surfaces at 2.0.0 + pin, BREAKING map + grep capture, tag/Release text as files , and the PR HELD for Han (gate; the loop never merges it, never tags).

## Scope edges

**In:** CHANGELOG.md, VERSION, .claude-plugin/plugin.json, tool.toml, the test-meta three-surface pin, tag/Release text files, the HELD review round.
**Out:** executing the tag/Release (Han); extending ship.md; retro (post-release, `/kit:retro` on its own).
**Not:** rewriting released sections; a semver policy doc (the renames are factual breaks, that suffices); squashing the ~24 entries into wave blurbs.

## Where to look

CHANGELOG.md (v1.7.0 section = the style target; the hold blockquote at :7-9), commands/ship.md (what it automates; Step 4a phantom-cut warning), `git log v1.7.0..HEAD --oneline`, git tag -l -n9 v1.7.0 (narrative shape), test-meta.sh:436 (the partial plugin.json==VERSION check to extend), #117 + #124 diffs.

## PR body

v2.0.0 prepared and HELD: full changelog for the two waves + follow-ups, BREAKING 3-rename map + consumer grep, three version surfaces bumped + pinned, HELD-pair (#117/#124) review findings attached, tag narrative + Release body as files. Han executes the tag + `gh release create`. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>
