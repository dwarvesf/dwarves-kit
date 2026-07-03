# SPEC-115: release cut v2.0.0 (PREPARED and HELD)

Status: VALIDATED
Lane: tiny
Type: spec-feature

## Problem

The `[Unreleased]` changelog has accumulated the kit-hardening + kit-telemetry waves + follow-ups
under a release HOLD ("deferred until the kit-hardening megagoal completes"), and the kit-face wave
(8 sub-goals) has now shipped on top with zero changelog entries. The hold's condition is met.
tool.toml drifted to 1.6.0 while VERSION/plugin.json read 1.7.0. The mega-goal (roadmap: ops-toolkit
`_meta/megagoals/kit-face/`, assumptions 08) resolves this: cut v2.0.0 , PREPARED and HELD for Han.

## Solution (a checklist; 08 is a GATE + the FINAL sub-goal , the loop prepares, never publishes)

1. **HELD-pair review FIRST** , a fresh-context re-review of #117 + #124 (merged "[HELD for Han]"),
   findings surfaced BEFORE any tag (`docs/releases/v2.0.0/held-review.md`).
2. **CHANGELOG** , `[Unreleased]` -> `[2.0.0] - 2026-07-03` (hold blockquote removed); a BREAKING
   section mapping the THREE renames (integration-checker->integration-verifier,
   reviewer->code-reviewer, security-auditor->security-reviewer) + a consumer-repo grep result;
   per-spec kit-face bullets (#128-136) in the v1.7.0 house style; prior accumulated waves retained;
   a fresh empty `[Unreleased]` on top.
3. **Three version surfaces** to 2.0.0 (VERSION, .claude-plugin/plugin.json, tool.toml) + a new
   `test-meta` THREE-surface parity pin (the v1.7.0 cut missed tool.toml; the pin kills that class).
4. **Tag narrative + GH Release body PREPARED as files** (`docs/releases/v2.0.0/{tag-message.txt,
   release-body.md}`), NOT executed , ship.md is not extended for this once-per-cycle step.
5. **Open the PR and HOLD it.** The loop never tags, merges, or publishes; Han runs the tag +
   `gh release create`.

## Verification

```bash
cd dwarves-kit
cat VERSION; jq -r .version .claude-plugin/plugin.json; grep '^version' tool.toml   # all 2.0.0
bash tests/test-meta.sh   # 662/662, incl. the tool.toml==VERSION three-surface pin
grep -q '## \[2.0.0\]' CHANGELOG.md && grep -q 'BREAKING' CHANGELOG.md
ls docs/releases/v2.0.0/   # tag-message.txt, release-body.md, held-review.md
```

## After state

- `VERSION`/`.claude-plugin/plugin.json`/`tool.toml` = 2.0.0; `tests/test-meta.sh` three-surface pin.
- `CHANGELOG.md` [2.0.0] section (BREAKING + per-spec bullets); fresh `[Unreleased]`.
- `docs/releases/v2.0.0/{tag-message.txt,release-body.md,held-review.md}`.
- The PR is OPEN and HELD (gate + final; never merged/tagged by the loop).

## Scope edges

**In:** CHANGELOG, the 3 version surfaces, the test-meta 3-surface pin, tag/Release/held-review
files, the HELD-pair review round.
**Out:** executing the tag / `gh release create` (Han); extending ship.md; the retro (post-release).
**Not:** rewriting released sections; squashing the ~waves into vague blurbs.

## Open questions

08 is deliberately terminal + gated: the loop opens the PR and stops. Everything a human needs to
ship is a file in the PR (tag message, release body, held-review findings, the three aligned +
pinned version surfaces). The tag + Release click stays the manual convention.
