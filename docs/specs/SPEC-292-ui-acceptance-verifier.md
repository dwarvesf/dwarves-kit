# SPEC-292: `ui-acceptance-verifier`, the battery leg that drives the PR's preview

**Status:** DRAFT (contract only; no code in this PR)
Lane: full
**Source:** ops-toolkit `research/2026-09-14-pr-proof-gate-for-dev-team.md`, follow-ups 3 and 4. **Board:** ID-880. **Proof:** owed by the build PR at `docs/verification/ui-acceptance-verifier.md`.

## Problem

The kit verifies logic and reads diffs. `/kit:battery` re-executes verification commands;
`frontend-reviewer` reads a diff for a11y; `/kit:visual-team` critiques a screenshot and states
it generates none. No agent opens the rendered page and checks the feature against its
acceptance criteria. For a frontend PR the verifier therefore has the dev's own video, the
dev's own pasted output, and nothing independent.

The proof-capture skill (ops-toolkit SPEC-126) already holds the Playwright recipe: real
storage state, `recordVideo`, `trace.zip`, caption overlay, screenshot assertions. It is
author-side by design. This spec puts the same recipe on the verifier's side and gives it a
verdict shape.

## Solution

A read-only agent, `agents/ui-acceptance-verifier.md`, dispatched as a fourth battery leg when
the branch diff touches UI paths, and callable alone.

```
inputs                          agent                                   outputs
──────────────────────────      ──────────────────────────────────      ────────────────────────────
preview URL                     per Given/When/Then scenario:           per-AC PASS / FAIL / NO-CHECK
AC in Given/When/Then           set up state, act, observe,             screenshot per beat
storage state (optional)        assert the visible result,              trace.zip per scenario
token export (optional)         run the named negative case             token + layout findings
                                deterministic layers:                   one verdict block
                                  token conformance, layout invariants,
                                  pixel baseline when one is committed
```

### Inputs and where they come from

| Input | Source, in order | Missing |
|---|---|---|
| Preview URL | the PR's preview comment (`wrangler versions upload` shape), else `--url` | `NO-CHECK: no preview` and stop |
| Acceptance criteria | the PR body `## Acceptance criteria`, else the spec's `## Acceptance criteria`, else the card | `NO-CHECK: no AC`; the agent never invents criteria |
| Storage state | `tests/.auth/<role>.json` in the repo when present | scenarios needing login report `NO-CHECK: no session` |
| Token export | `tokens/*.json` or the Style Dictionary build output when present | token layer skipped, named as skipped |
| Pixel baselines | `**/__screenshots__/` or `*-snapshots/` when present | pixel layer skipped, named as skipped |

### The four layers

| Layer | Check | Blocks |
|---|---|---|
| Scenario | drive each Given/When/Then on the preview; assert the visible result the AC names; run the negative case; one screenshot per beat, one `trace.zip` per scenario | yes |
| Token conformance | walk the DOM with `getComputedStyle`; every color, font size, radius, and spacing value must be in the exported token set; report element, property, value | yes when a token export exists |
| Layout invariants | no overlapping siblings, no `scrollWidth > clientWidth` on containers, no unintended ellipsis truncation, x positions on the grid step, run across the viewport matrix `[390, 768, 1280]`; `@axe-core/playwright` for contrast and labels | yes |
| Pixel baseline | `expect(page).toHaveScreenshot()` against the committed baseline, in the pinned Playwright container, defaults kept (`threshold` 0.2, `animations: 'disabled'`, `caret: 'hide'`, `scale: 'css'`), a small `maxDiffPixels` budget | yes when a baseline exists |

A vision judgement (misalignment, hierarchy, "looks wrong") is a fifth, non-blocking section:
the agent receives the baseline, the candidate, the diff mask, and the token list together, and
ranks findings for the human. It never produces a FAIL on its own. Evidence: measured accuracy
of vision models on UI defects is low without a reference image (research note, follow-up 4).

### Verdict block

```
## UI acceptance: <PR or branch>
Preview: <url>   Viewports: 390, 768, 1280   Container: mcr.microsoft.com/playwright:v<ver>-noble

| AC | Scenario | Result | Evidence |
|---|---|---|---|
| AC-1 | Given a logged-in member, when ... then ... | PASS | trace: ac-1.zip, shots: ac-1-{1,2,3}.png |
| AC-1 neg | ... the expired link ... | PASS | ... |
| AC-2 | ... | FAIL: expected "Saved", saw "Error 500" | ... |
| AC-3 | ... | NO-CHECK: no session | |

Tokens: 2 findings (button.primary color #3A3A3A not in palette; card padding 14px off the 4px step)
Layout: 0 findings across 3 viewports
Pixels: 1 of 4 baselines differ (home.png, 212 px > budget 120)
Vision (advisory): heading hierarchy skips h2 on /settings

VERDICT: FAIL (AC-2, tokens, pixels)
```

`VERDICT` is FAIL when any blocking layer fails, NO-CHECK when no scenario could run, PASS
otherwise. NO-CHECK rows never count as PASS.

### Wiring

- `/kit:battery`: a fourth leg, dispatched only when the diff touches UI paths (the same path
  set `frontend-reviewer` keys on). Model tier: mid. Its rows merge into the battery verdict.
- Standalone: `/kit:battery <target> --ui-only` for a taste pass without the other legs.
- The agent is read-only. Tools: `Read`, `Grep`, `Glob`, `Bash(npx playwright *)`,
  `Bash(git diff *)`, `Bash(gh pr view *)`. It writes evidence only under the scratchpad and
  never edits the repo.
- Determinism: the scenario, token, and layout layers run anywhere; the pixel layer runs only
  inside the pinned container and reports `NO-CHECK: not in container` otherwise.

### Out of scope

- The GitHub-side twin (`claude-code-action` on `pull_request` running the same prompt) is a
  follow-up once the local leg is proven. It needs the trusted per-repo container, never the
  `pr-shared` pool, because the job holds an API key and runs PR-controlled install scripts.
- A body check that blocks merge on missing evidence is a separate, smaller spec.
- Design-vs-Figma automated diff: nothing mainstream does it; a Figma REST frame export as an
  overlay for the human is the most this spec offers, later.

## Acceptance criteria

- AC-1: given a PR with a preview URL and three Given/When/Then criteria, the agent returns a
  verdict block with one row per criterion plus one per named negative case, each PASS, FAIL
  with the observed value, or NO-CHECK with a reason.
- AC-2: given no acceptance criteria, the agent returns `NO-CHECK: no AC` and no invented rows.
- AC-3: given a token export and a page with one off-palette color, the token layer reports the
  element, property, and value, and the verdict is FAIL.
- AC-4: given a committed baseline and a deliberate two-hundred-pixel change, the pixel layer
  reports the diff count and the verdict is FAIL; the same run inside a fresh container with no
  change is PASS.
- AC-5: the agent leaves `git status` clean in the target checkout.
- AC-6: `/kit:battery` on a diff with no UI paths does not dispatch the leg; on a diff with UI
  paths it does, and the battery verdict carries the UI rows.

## Verification

```
bash tests/run-all.sh                                   # kit suite stays green
bash tests/agents/ui-acceptance-verifier.sh             # AC-1 to AC-5 against a fixture app
bash tests/commands/battery-ui-leg.sh                   # AC-6, dispatch gating
```

Negative control for the build PR: remove the off-palette fixture color and confirm AC-3 flips
to PASS; restore it and confirm FAIL.

## Open questions for the operator

1. Fixture app for the tests: a static page served by `npx serve` inside the kit, or a real
   Dwarves app preview? A static fixture keeps the suite hermetic and is the default here.
2. Viewport matrix `[390, 768, 1280]` as the kit default, overridable per repo in `kit.toml`?
3. Storage-state convention `tests/.auth/<role>.json` is proposed, not yet used by any Dwarves
   repo. Confirm or name the existing one.
