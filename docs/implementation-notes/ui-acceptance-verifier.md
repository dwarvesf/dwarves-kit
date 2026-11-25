# Implementation notes: ui-acceptance-verifier

Running log for `docs/specs/SPEC-292-ui-acceptance-verifier.md`. Delta from the spec, never a mirror.

## Live probe

Probe run on the build host (macOS, Node v22.23.1, npm 10.9.8) with load average between 40 and 84. All installs, fixtures and logs live in `<scratchpad>/05-probe`. The only write outside it is the Playwright browser cache at `~/Library/Caches/ms-playwright` (the default location). No repo file other than this one was touched, nothing was committed. Wall times are inflated by the host load. Anything marked "guess" was not run.

### Q1. Playwright on this host

Playwright was not installed anywhere before the probe. After `npm i -D @playwright/test @axe-core/playwright` plus `npx playwright install chromium`, headless Chromium ran: three viewports (390, 768, 1280), one screenshot each, one `trace.zip` each, one visible-string assertion, 3 passed. Installed versions: `@playwright/test` 1.65.1, `@axe-core/playwright` 4.14.1, Chrome Headless Shell 159.0.8154.6 (chromium-headless-shell v1255).

Install cost: npm step 17 s and 23 MB in `node_modules`; browser step 167 s and about 586 MB in `~/Library/Caches/ms-playwright` (chromium 377 MB, headless shell 206 MB, ffmpeg 3 MB). Other `-1228` browser directories also appeared in that shared cache during the probe; they are not from this probe (another process installed them), so the cache is shared and can grow under the kit's feet.

The kit has no `package.json` and no `node_modules`, so Playwright would be a new dependency of any consumer repo or of a kit-owned scratch install (guess: the agent would install per run under the scratchpad, paying roughly 3 minutes and 600 MB the first time).

Commands and results:

```bash
cd <repo worktree> && npx --no-install playwright --version
# npm error npx canceled due to missing packages and no YES option: ["playwright@1.65.1"]
ls ~/Library/Caches/ms-playwright
# ls: ... No such file or directory   (before the install)
cd <scratch> && time npm i -D @playwright/test @axe-core/playwright
# added 5 packages, and audited 6 packages in 16s   (17 s wall)
cd <scratch> && time npx playwright install chromium
# Chrome Headless Shell 159.0.8154.6 ... downloaded   (167 s wall)
cd <scratch> && PORT=49242 npx playwright test viewports.spec.js
# 3 passed (19.0s)   (27 s wall including npx start; each test 0.7 to 1.2 s)
```

The static server was Playwright's own `webServer` option, `python3 -m http.server 49242 --bind 127.0.0.1 --directory fixture`. `use.trace: 'on'` wrote `test-results/<test>/trace.zip`. The default output dir is `test-results/` in the cwd (see Q8, it matters for AC-5).

### Q2. The deterministic layers, on a static fixture

All four layers are feasible with a static fixture page. Fixture: `fixture/index.html` (one off-palette `#3A3A3A` button, a 200 px container holding a 400 px child, two absolutely positioned overlapping boxes, one `#aaaaaa` on white paragraph) and `fixture/tokens.json` (colors, radii, font sizes).

(a) Token conformance. API: `page.evaluate` over `document.querySelectorAll('body, body *')`, reading `getComputedStyle(el)` for `color`, `backgroundColor`, `borderTopLeftRadius`, `fontSize`, then comparing against the JSON. Colors come back as `rgb(r, g, b)` and need a hex conversion; fully transparent values (`rgba(0, 0, 0, 0)`) must be skipped or every element flags. Result: exactly one finding, `{"el":"button.primary","prop":"background-color","value":"rgb(58, 58, 58)"}`, which names element, property and value as AC-3 needs. Not tested: spacing against a 4 px step (computed padding and margin are per-side and need a rule for which sides count), and inherited or default browser styles on a real app (guess: a real app will produce hundreds of noise findings until the token set includes every default, so "every value must be in the token set" needs a scoping rule).

(b) Layout invariants. API: `el.scrollWidth > el.clientWidth` over `div` elements, and `getBoundingClientRect()` pairs with the standard rectangle intersection test. Result: `{"overflow":["narrow card"],"overlap":true}`, both planted defects found. Caveat: `scrollWidth > clientWidth` also fires on every intentional scroll container (carousels, code blocks, tables), so it needs an allowlist or an `overflow-x` check (guess).

(c) `@axe-core/playwright`. API: `new AxeBuilder({ page }).withRules(['color-contrast']).analyze()`, import is `require('@axe-core/playwright').default`. Result: `color-contrast:1` on `<p class="faint">`. This was the slowest layer, 3.1 s for a six-element page under load.

(d) Pixel baseline. API: `await expect(page).toHaveScreenshot('home.png', { maxDiffPixels: 120 })`. Behavior observed:

- Run 1 (no baseline): the test FAILS and writes `tests/pixel.spec.js-snapshots/home-darwin.png`. A first run is red, not green. A verifier must treat "baseline written" as a distinct state.
- Run 2: pass.
- After widening one box (a deliberate change): fail with `7200 pixels (ratio 0.03 of all image pixels) are different`, plus `Expected`, `Received` and `Diff` paths. The pixel count is in the output, so AC-4's "reports the diff count" is satisfiable by parsing that line.
- The baseline filename carries a platform suffix, `-darwin`. A baseline committed from a Mac is never matched by a Linux container, which would look for `-linux`. AC-4 ("committed baseline, same run inside the pinned container") therefore needs baselines generated inside the container, or `snapshotPathTemplate` set to drop the platform. This is a spec gap.
- The baseline lands next to the spec file, inside the repo checkout. See Q8.

Flaky or broken: nothing flaked in three or four runs, but fonts were the system `Arial` fallback, which is exactly why Playwright says to pin the container. The 14 to 16 s wall for one test is mostly browser start and the `webServer` probe under host load.

```bash
npx playwright test layers.spec.js
# TOKEN FINDINGS [{"el":"button.primary","prop":"background-color","value":"rgb(58, 58, 58)"}]
# LAYOUT {"overflow":["narrow card"],"overlap":true}
# AXE color-contrast:1 <p class="faint">Low contrast note</p>
# 3 passed (20.8s)
npx playwright test pixel.spec.js      # run 1: 1 failed (baseline written); run 2: 1 passed
npx playwright test pixel.spec.js      # after change: 7200 pixels (ratio 0.03 of all image pixels) are different.
```

### Q3. Container

AC-4 cannot be exercised on this host today without starting or pulling something. Report only, nothing was changed.

- `docker info`: the client answers (Docker Engine - Community 29.9.3) but the daemon does not: `failed to connect to the docker API at unix:///var/run/docker.sock ... no such file or directory`. `docker images` fails the same way, so no `mcr.microsoft.com/playwright` image can be seen through Docker, and none is likely present.
- `container system status` (Apple runtime): `status running`, client 1.7.1. `container image list` shows eight images, none of them a Playwright image.
- So the Apple runtime is up but has no Playwright image, and Docker is down. Running the pinned image (guess: `mcr.microsoft.com/playwright:v1.65.1-noble`, the tag shape the spec's verdict block uses) needs an image pull, which this probe was not allowed to do.

```bash
timeout 15 docker info          # Server: failed to connect to the docker API at unix:///var/run/docker.sock
timeout 15 container system status   # status running
timeout 20 container image list      # 8 images, none playwright
```

### Q4. How the kit launches a browser today

The kit uses no Playwright and no Puppeteer anywhere. `lib/system-design/shots.mjs` spawns a Chromium-family binary directly and drives it over raw CDP: `spawn(chrome, ['--headless=new', '--remote-debugging-port=0', ...])`, parses the `ws://` URL from stderr, and talks JSON over Node 22's global `WebSocket`. It finds the binary from the `CHROME` env var, else the first existing path in a fixed macOS list (Google Chrome, Helium, Chromium, Brave, Edge `.app` bundles), else a Google Chrome default path. There is no Linux or Windows path list.

Its test, `tests/test-doc-figures.sh`, uses the SKIP convention: it prints `  SKIP node not installed`, `  SKIP no Chrome or Edge found (set CHROME)` or `  SKIP no network (...)` and does not fail, so the render part only runs when node and a browser are present. `tests/lib/node-fixture.sh` also exists as a Node helper (not read).

Other browser or Node hits from `rg -l "playwright|puppeteer|chrome" lib tests commands skills agents`: `tests/test-tool-policy-guard.sh` (strings about an MCP plugin policy), `lib/plugin-check/**` (fixtures naming a `playwright` plugin), `lib/bench/dashboard.py` and its docs (the word "chrome" in a UI sense). None launches a browser.

PHILOSOPHY rule to weigh: hooks are bash plus jq, "no Python, no Node, no compiled code in a hook" (`docs/reference/PHILOSOPHY.md` line 136). `lib/system-design/shots.mjs` is the precedent for a Node tool under `lib/` outside hooks.

```bash
rg -l "playwright|puppeteer|chrome" lib tests commands skills agents -g '!node_modules'
# tests/test-doc-figures.sh, tests/test-tool-policy-guard.sh, lib/plugin-check/..., lib/system-design/shots.mjs, lib/bench/dashboard.py, ...
```

### Q5. Test layout

`tests/agents/` and `tests/commands/` would NOT be picked up. `tests/lib/suites.sh` `is_suite` accepts only `tests/test-*.sh` (directly under `tests/`) and `lib/<m>/tests/test-*.sh` or `smoke.sh` (one or two module levels). `bin/test-affected` maps a changed `agents/*.md` or `commands/*.md` file to suites by full path, or by a basename over five characters, appearing in a suite, plus the `test-meta` area suites (`agents-commands`, `review-verifiers`, `vmodel-dispatch`, `docs-registry`, `plugin-hooks`) for any `commands/*` or `agents/*` change. `--changed` then keeps only paths matching the suite shape.

I checked `is_suite` on four paths: `tests/agents/ui-acceptance-verifier.sh` NOT-SUITE, `tests/commands/battery-ui-leg.sh` NOT-SUITE, `tests/test-ui-acceptance-verifier.sh` SUITE, `lib/uiverify/tests/test-x.sh` SUITE. House naming is `tests/test-<name>.sh`. The spec's two paths need renaming, for example `tests/test-ui-acceptance-verifier.sh` and `tests/test-battery-ui-leg.sh`, or a module suite under `lib/<module>/tests/` if the kit ships a runner there.

How suites test an agent or command: structurally, never by running the LLM. `tests/test-agent-effectiveness.sh` says "we cannot dispatch a live Claude reviewer in CI" and greps prompt completeness. `tests/test-break-it.sh` (the closest precedent: an agent plus a battery wiring) splits into MECHANISM (real exit codes on a fixture pair, wiring read out of `commands/battery.md` and `docs/WORKFLOW.md`) and PROMPT (section-scoped token greps), and records a live dispatch in `docs/verification/`, not in the suite. `tests/test-meta-review-verifiers.sh` pins frontmatter, tiers and the `generated-by` roster. `rg "claude -p"` over the suites finds only mock-based tests (`claude` is stubbed), no suite that really calls an LLM.

Consequence: AC-1, AC-2 and AC-5 (what the agent does) cannot be asserted by `bash tests/...` against a live agent. Only the deterministic layers can run as real mechanism tests, and only if they live in a script the kit ships (see Q8). The spec's "AC-1 to AC-5 against a fixture app" line has no precedent as written.

```bash
source tests/lib/suites.sh; is_suite tests/agents/ui-acceptance-verifier.sh   # NOT-SUITE
is_suite tests/test-ui-acceptance-verifier.sh                                  # SUITE
```

### Q6. What a new agent owes mechanically

Tracer: `rg -n "frontend-reviewer" --hidden -g '!.git' .` plus the tests that loop over `agents/*.md`. A new `agents/ui-acceptance-verifier.md` owes:

| Surface | Why | Checked by |
|---|---|---|
| `agents/ui-acceptance-verifier.md`: `---` first line, `name:`, `description:`, `model:` of `sonnet`, `haiku` or `opus` | frontmatter loop over every agent | `tests/test-meta-agents-commands.sh` |
| a row `| \`ui-acceptance-verifier\` |` in the `## Agents (dispatched, not invoked)` table of `docs/MANUAL.md`, both directions | table row per agent file | `tests/test-meta-agents-commands.sh`, `tests/test-meta-vmodel-dispatch.sh` |
| a row in the "Command and agent V-phase inventory" table of `docs/reference/architecture.md` | row count must equal `commands/*.md` plus `agents/*.md` | `tests/test-meta-vmodel-dispatch.sh` |
| `docs/reference/FEATURES.md` regenerated: `bash lib/registry/feature-registry.sh generate` | generated projection, byte-compared | `tests/test-meta-docs-registry.sh`, and `hooks/ship-gate.sh` refuses a push when stale. It is fresh today (`feature-registry: docs/reference/FEATURES.md is fresh`). |
| a `[D]` line in `docs/reference/workflow-paths.md` (sibling: `[D] frontend-reviewer <- /kit:review-team (UI diffs) -> a11y lens -> findings merged`) | path index | I found no test that pins agent `[D]` lines (guess: only the drift audits catch it); add it anyway |
| read-only tools: no `Write`, `Edit`, `NotebookEdit`, `MultiEdit` or bare `Bash` in `tools:` | the read-only gate | `tests/test-agent-effectiveness.sh` gate, run by `commands/draft-agent.md` step 7 on a new agent definition |
| agent name must not end in `-checker`, `-auditor`, `-validate` or be `reviewer` | naming axis | same gate. `ui-acceptance-verifier` passes. |
| `generated-by: draft-agent <date> ...` ONLY when the agent is drafted by `/kit:draft-agent` | the key set must equal `GEN_ROSTER` | `tests/test-meta-review-verifiers.sh` line 632. Either leave the key out (hand-written) or add the name to `GEN_ROSTER`. |
| `commands/battery.md` wiring row | the dispatch edge | no test pins the three-legs text (see Q7), `tests/test-break-it.sh` is the model for adding one |
| prose mentions: `docs/WORKFLOW.md` line 415 (domain reviewers via review-team), `CHANGELOG.md` | not enforced | not checked |

Not owed (searched, no hit): `lib/config/modules.tsv` has no `agents` entry; `.claude-plugin/plugin.json` lists `subagents` generically and `install.sh` copies `agents/*.md` by glob (lines 150 and 571), so there is no per-agent manifest line. No literal agent counts exist in README or MANUAL (the no-counts policy in `tests/test-meta-vmodel-dispatch.sh` rejects them). `role-classify.sh` has no agent table: it maps keywords to domain names only (Q7).

`docs/specs/SPEC-292-...` is already named in the `frontend-reviewer` row of `FEATURES.md` under Specs, so the generator already links this spec number.

### Q7. Battery wiring

There is no script and no path set that decides the UI lens. The spec says "the same path set `frontend-reviewer` keys on"; no such set exists. In `commands/battery.md` the UI lens is one prose row of the "Lens escalation" table (line 74), selected by the lead's judgment:

```
## Lens escalation
Add specialized lenses when the diff touches their domain; each is its own agent:
| UI | kit:frontend-reviewer | mid |
```

The only mechanical selector in the kit is `lib/classify/role-classify.sh classify "<changed paths + diff summary>"`, which `commands/review-team.md` (line 44) uses for the domain lens. It is a keyword regex over free text, not a path glob. The frontend rule (line 36) is: `frontend|front-end|\bui\b|\bux\b|component|\bcss\b|tailwind|stylesheet|button|modal|form (field|input|layout)|accessib(le|ility)|\ba11y\b|\baria\b|render(ing)?|viewport|responsive|dark mode|\bdom\b` and it returns `frontend<TAB>ui/component/css/a11y`. A diff of `src/App.tsx` alone has none of those words, so it classifies `generic` unless the diff summary says so. `lib/gate/proof-gate.sh` (lines 139 to 148) has a second keyword list for `[proof] visual` (`ui|page|component|screen|layout|front-?end|stylesheet|css|html|dashboard`), also text, not paths. `lib/gate/battery-gate.sh` only counts changed lines and hard paths (via `lane-classify.sh floor`), not UI.

So AC-6 ("a diff with no UI paths does not dispatch the leg; with UI paths it does") needs a new deterministic path classifier (for example `lib/classify/ui-paths.sh` with globs `*.tsx *.jsx *.vue *.svelte *.css *.scss *.html` and component directories), because the existing one cannot answer by path.

Attachment points:

- A fourth leg: `commands/battery.md` has "## The three legs" (a 3-row table) and the line "Dispatch legs 1 and 2 IN PARALLEL". A UI leg cannot run in parallel with leg 1 if it needs a deployed preview (guess: the preview exists before the battery runs, so parallel is fine, but the NO-CHECK path covers it). It fits better as one more row in "Lens escalation" (mid tier) or as a second-dispatch rung like `## Probe rung`, than as a renumbered "four legs".
- `--ui-only`: `## Target (optional argument)` is the only argument parser (a path, `owner/repo#N` or a PR URL). A flag needs a new sentence there, and it must skip the Size gate (a UI taste pass on a 20-line CSS change would be SKIPped at 150 lines otherwise) and the gate-ledger `battery` bracket semantic (the ledger counts `battery` as the review gate, so a `--ui-only` run must not record `battery ran`).
- Tests that pin battery text: `tests/test-break-it.sh` (greps `## Probe rung` and the ladder order), `tests/test-meta-spec-depth.sh` line 450 (leg 2 tier text), `tests/test-battery-gate.sh` (gate script only). Nothing pins the three-legs table, so adding a row will not break an existing test, and a new suite should pin the new row.

### Q8. Agent tool limits

With `Read, Grep, Glob, Bash(npx playwright *), Bash(git diff *), Bash(gh pr view *)` the agent cannot create the Playwright scenario file it needs. The gap is exact: there is no `Write` or `Edit`, and `Bash(npx playwright *)` is prefix-scoped to commands that start with `npx playwright`, so a shell redirect or heredoc to create a `.spec.js` is not granted (guess on the matcher's exact compound-command handling). `npx playwright test <file>` can only run a file that already exists.

What the grant does allow without a script, verified: `npx playwright screenshot --viewport-size=390,800 <url> <file>` works (15 s wall), and `pdf`. That gives one screenshot, with no assertions, no trace, no token or layout walk. So the CLI alone covers none of the four layers except a screenshot.

Three more gaps in the same line:

- `Bash(npx playwright *)` is wider than "read-only": it also matches `install` (network download), `open`, `codegen`, `cr`, `ff`, `wk` (headed browsers, forbidden by the house rule for headless-only runs), `mcp`, and `test` (which executes whatever the target repo's `playwright.config` and specs contain, including its `webServer.command`; that is repo-controlled code execution).
- AC-5 (`git status` clean in the target checkout) conflicts with Playwright defaults: `test-results/` is created in the cwd (observed in the scratch project), `toHaveScreenshot` writes a missing baseline into `<spec>-snapshots/` next to the spec (observed), and `--update-snapshots` overwrites committed baselines. A run needs `--output <scratchpad>`, `--config <scratch config>`, and a rule that a missing baseline is `NO-CHECK`, never a write.
- `npx playwright` resolves from the target repo's `node_modules`; if absent, plain `npx` would try to install from the network (the probe saw exactly this: `npx canceled due to missing packages` only because `--no-install` was used).

How sibling read-only agents run something that is not a stock command:

1. A kit-shipped or path-named runner under a path-scoped grant. `agents/devops-triage.md` tools: `Read, Grep, Glob, Bash(git log*), Bash(git diff*), Bash(git show*), Bash(wl-query*), Bash(bash */cf-worker-state.sh*)`. The agent calls a named script with arguments and never authors one. For this spec: `lib/ui-verify/run.mjs` (or `.sh`) with `Bash(node */ui-verify/run.mjs *)`, taking a JSON scenario and a token file, writing evidence to a scratchpad path argument.
2. The lead authors the file before dispatch. `commands/battery.md` brief ingredient: "Fixtures to build: <list or none>", and `agents/acceptance-verifier.md` has `Read, Grep, Glob, Bash(npm test*), Bash(go test*), Bash(pytest*), Bash(bash tests/*), Bash(git diff*)`: it runs committed scripts and the lead builds what is missing. For this spec the lead (or a builder) would write `scenarios.json` from the AC before dispatch.
3. Committed tests run by prefix. Same `acceptance-verifier` shape: `Bash(bash tests/*)` runs files already in the repo. The UI analogue is a repo-committed `playwright.config` and `tests/e2e/*` run by `Bash(npx playwright test *)`, which only works for repos that already have them (the spec's own storage-state convention says no Dwarves repo does yet).

A fourth option exists but conflicts with the kit's own gate: add `Write` limited to the scratchpad. `tests/test-agent-effectiveness.sh` flags `Write`, `Edit` and bare `Bash` on a review-class agent, and `commands/draft-agent.md` step 7 runs it on every new agent (guess: a path-scoped `Write(...)` entry might pass the grep, which only matches a bare `- Write` line, but it would still break the spec's "read-only" claim).

Pre-existing, noticed and not investigated: `agents/break-it.md` has only `Read, Grep, Glob, Bash(git diff *), Bash(git log *)` yet its battery brief says "Run it against the code, quote the output". The same tool-versus-job mismatch is what SPEC-292 would inherit if it copies that shape.

### Q9. Spec template gap

`bash lib/spec/spec-depth.sh check docs/specs/SPEC-292-ui-acceptance-verifier.md` printed `spec-depth: warning: no Depth line ... (older spec, counts as standard)` and exited 0. It is a warning, not a failure, but a full-lane spec under `/kit:spec-validate` Reviewer 4 gets a CRITICAL for a deeper level without a reason, and a `standard` Depth must still name why nothing deeper is needed.

SPEC-292 has: Problem, Solution (with an ASCII diagram and tables), Out of scope, Acceptance criteria, Verification, Open questions. It lacks, against `commands/spec.md` and `commands/spec-validate.md`:

| Missing | Rule |
|---|---|
| `Generated:` and a plain `Status:` line (it uses bold `**Status:** DRAFT`); `Board:` on its own line (it is inside the `**Source:**` line) | header shape; whether the bold form is parsed was not tested |
| `Depth:` line under `Lane:` | `spec-depth.sh check` (warning today). Natural value: `Depth: research (repo: whether a UI path set and a runner seam exist) + blind-spot (failure: the agent cannot author its scenario file)`; both unknowns are answered by this probe, so `standard` with that grounding is also defensible. |
| `## Picture` | MUST be non-empty on full lane (Reviewer 4, mechanical). The `inputs / agent / outputs` diagram inside `## Solution` does not count by heading. |
| `## Design` | BLOCKING Reviewer 6: a design-bearing spec (new component, external integration, 2+ approaches) with a missing `## Design` is NEEDS-REVISION |
| `### Approaches considered` and `### Chosen approach + why` (under Solution) | Solution depth pattern. Real alternatives here: kit-shipped runner vs agent-authored script vs consumer repo's own e2e suite. |
| `## Terms` | delta glossary, "none" allowed |
| `## Task Breakdown` | atomic tasks with AC; the spec says "no code in this PR" but has no tasks for the build PR |
| `## After state` | observable end-state bullets |
| `## Quality requirements` | cite `docs/QUALITY.md` IDs or "none" |
| `## Edge Cases` | scenario-gen; the failure cases (preview 404, preview behind auth, flaky animation, no baseline) are only half-named in the inputs table |
| `## Failure modes` | expected for full lane touching an external provider |
| `## Touches` | only if run via `/kit:dispatch` |
| `## Decision Log` | optional shape |
| `## Test plan` | default for normal/full via `/kit:test-plan`, written after validate |
| `## Grounding` | full-lane Reviewer 4 addendum: one live sample per external data shape plus a dry trace per negative control. A missing one is a warning. This probe supplies material: the Q1 and Q2 command output, the Q3 container state. |

Good shape model: `docs/specs/SPEC-403-mega-gate-pr-head.md` (Lane: full, Status: VALIDATED, has Depth with a named failure, Picture, Design, Approaches considered, Task Breakdown, After state, Failure modes and Grounding). `SPEC-416-wrap-ship-verb.md` is a second full-section example. `SPEC-340-auto-approve-writes.md` is the one with a `## Test plan`.

```bash
bash lib/spec/spec-depth.sh check docs/specs/SPEC-292-ui-acceptance-verifier.md
# spec-depth: warning: no Depth line in docs/specs/SPEC-292-ui-acceptance-verifier.md (older spec, counts as standard)   rc=0
```

### Q10. Where the preview URL comes from

No existing kit code or doc reads a PR preview comment. `rg -n -i "wrangler versions|preview url|preview comment|preview_url|--json comments"` over `lib commands agents skills docs hooks` returns nothing relevant (the only `wrangler versions` hit is a secrets note in `docs/impl-playbook/cloudflare.md`). `preview` elsewhere means a dry run (`wrap apply`, `onboard`). The nearest reusable piece is `commands/battery.md` line 26, `gh pr view N -R owner/repo --json headRefName,baseRefName,headRefOid`, which already shows the `gh pr view --json` read; adding `comments` to that field list would work under the spec's `Bash(gh pr view *)` grant (guess: not run, no PR to read).

The "`wrangler versions upload` shape" is unspecified in the spec. wrangler's upload output prints a version preview URL, but whether a CI step posts it as a PR comment, in what wording, and from which bot, is repo-specific and unknown here. The agent needs a documented comment format or a named regex, plus the author filter (a PR comment is untrusted data, and any commenter can post a URL; the agent would then drive a browser to an attacker-chosen host). That is a trust-boundary question the spec does not address (the kit's own rule: external content is DATA). A fixed allowlist of preview hostnames per repo (for example in `.kit.toml`) would close it (guess).

```bash
rg -n -i "wrangler versions|preview url|preview comment|preview_url|--json comments" lib commands agents skills docs hooks
# no hit outside docs/impl-playbook/cloudflare.md (secrets note) and SPEC-292 itself
```

## Probe verdict

### Feasible as specified

- Headless Chromium on this host: yes. 3 viewports, screenshots and traces, 27 s wall under load average above 40.
- Token conformance by `getComputedStyle` against a JSON token file: yes, finds the planted element, property and value (AC-3's report shape).
- Layout invariants (`scrollWidth > clientWidth`, overlapping siblings) and `@axe-core/playwright` contrast: yes.
- Pixel baseline with a count in the failure output: yes (`7200 pixels ... are different`), so AC-4's "reports the diff count" is parseable.
- A kit-side structural test for the agent file and battery wiring: yes, in the `tests/test-break-it.sh` mold.

### Not feasible as specified, and the smallest spec change

| Gap | Evidence | Smallest spec change |
|---|---|---|
| The agent cannot author its scenario file with the stated tools | Q8 | Ship a kit runner (`lib/ui-verify/run.mjs` plus a JSON scenario schema), grant `Bash(node */ui-verify/run.mjs *)` instead of `Bash(npx playwright *)`, and have the agent emit the scenario as JSON text for the lead or the runner's stdin. Keep the agent read-only. |
| `Bash(npx playwright *)` also allows `install`, headed `open` and `codegen`, and `test` runs repo-controlled code; Playwright writes `test-results/` and baselines inside the checkout, so AC-5 fails by default | Q8 | Name the runner as the only entry point; it sets `--output` and a scratch config, forbids `--update-snapshots`, and reports a missing baseline as `NO-CHECK`. |
| AC-4 cannot run on this host today: Docker daemon is down, the Apple `container` runtime is up but holds no Playwright image, and pulling is out of bounds. Baselines are also platform-suffixed (`home-darwin.png`), so a Mac-made baseline never matches a Linux container | Q2d, Q3 | Add to AC-4 that baselines are generated inside the pinned image, or set `snapshotPathTemplate` without the platform; mark AC-4 as "container-only, verified in CI or on a host with a runtime and the image", and let the suite SKIP when no runtime or image is present (the `test-doc-figures.sh` convention). |
| The "UI path set `frontend-reviewer` keys on" does not exist; the kit's classifier is a free-text keyword regex, so `src/App.tsx` classifies `generic` | Q7 | Add a deterministic path classifier (a few lines of globs) and cite it in the spec, or change AC-6 to "dispatched when the lead's `role-classify.sh` returns `frontend`". Also say `--ui-only` skips the size gate and does not record `battery ran`. |
| The spec's two test paths are not discovered by `tests/run-all.sh`; and no suite in the kit runs a live LLM agent, so AC-1, AC-2 and AC-5 cannot be asserted by a suite against the live agent | Q5 | Rename to `tests/test-ui-acceptance-verifier.sh` and `tests/test-battery-ui-leg.sh`. Split the ACs: mechanism ACs (AC-3, AC-4, the AC-5 `git status` check) run the shipped runner against a fixture; prompt-structure and wiring ACs are greps; AC-1 and AC-2 are recorded once as a live dispatch in `docs/verification/ui-acceptance-verifier.md`, as `test-break-it.sh` does. |
| The preview-comment reader does not exist, and a PR comment is untrusted input that names a host the agent will browse | Q10 | Pin the comment format and a per-repo preview-host allowlist, or accept `--url` only for the first version. |
| Playwright is a new Node dependency (about 600 MB and 3 minutes on first use) in a bash-plus-jq kit | Q1, Q4 | State where it installs (the scratchpad, never the kit or the target repo) and add the SKIP-when-absent rule; the `shots.mjs` precedent covers Node under `lib/`, not Playwright. |
| SPEC-292 lacks the full-lane sections (Depth, Picture, Design, Approaches, Task Breakdown, After state, Failure modes, Grounding, Test plan) | Q9 | Rewrite to the `SPEC-403` shape before `/kit:spec-validate`; this file's Q1 to Q8 output is the `## Grounding` material. |

Also owed on the build PR, mechanically (Q6): a `docs/MANUAL.md` agents row, an `architecture.md` inventory row, a regenerated `FEATURES.md`, a `workflow-paths.md` `[D]` line, and the read-only tools gate. Open questions 1 to 3 in the spec are partly answered: a static fixture is feasible and hermetic (Q1, Q2); the storage-state convention was not probed here (no Dwarves repo was inspected).

## Spec rewrite (round 1 answers)

Each row answers one finding of the round 1 validation report. The spec carries the answer; this table only points at it.

| Finding | Answer |
|---|---|
| R1-1 | fixed in Design (decisions) and Interfaces: no comment discovery; URL, head SHA and `allow_hosts` ride in the lead-written scenario file; off-list host exits 3 with no browser (AC-3). The `.kit.toml` part is rejected: a project `.kit.toml` rides inside the pull request; an operator-file-only knob moves to follow-up 292d. Comment parsing and the author filter move to 292d. |
| R1-2 | fixed in Interfaces (rules) and Design: https only, loopback only by an explicit file field, resolved-address check, per-request host check, downloads off, service workers blocked, permissions empty, popups closed, fresh context per scenario and viewport (AC-3, AC-4). DNS rebinding after the launch check is named as a residual in Failure modes, with the pin candidate moved to 292b. |
| R1-3 | moved to follow-up 292d: no storage state in this slice. A criterion needing a session uses a `skip` entry and returns NO-CHECK. The 292d constraints (test accounts, exact-host cookie domains, runner-only loading) are recorded in Out of scope. |
| R1-4 | fixed in Interfaces (result.json, row rules, runner stdout) and AC-5: the runner derives every status, sanitizes and truncates `observed`, the agent fences it and may not raise a status. |
| R1-5 | fixed in Solution and Design: the `npx playwright` grant is gone; the grant is `Bash(node */lib/ui-verify/run.mjs*)` and the runner exposes no install, codegen or update mode. The residual of a planted path and `*` spanning flags is named in Design and Failure modes. |
| R2-1 | fixed in Interfaces (identity, head SHA, `mismatch` makes every row NO-CHECK, `unverified` printed) and AC-7. Binding by comment timestamp moves to 292d. |
| R2-2 | fixed in Interfaces (verdict rule and mapping table): PASS only when at least one row exists and every row is PASS; worst-row rule; NO-CHECK is never PASS (AC-1, AC-2, AC-7). |
| R3-1 | fixed in Solution and Interfaces: the agent authors no code; the lead writes `scenario.json`; the agent has no `Write` (AC-12, AC-14 records that the tools were enough). |
| R3-2 | fixed in Acceptance Criteria and Verification: suite renamed `tests/test-ui-acceptance-verifier.sh`; ACs split into MECHANISM, PROMPT and LIVE; the live dispatch is recorded in `docs/verification/` (AC-14). The `battery-ui-leg` suite is folded in as case `battery-row`. |
| R4-1 | fixed in Scope: slice 292a only; 292b to 292e are named in Out of scope with a reason each, and a gate that one real consumer run precedes them. |
| R6-1 | fixed in Picture and Design (diagram, chosen approach, decisions, philosophy alignment). Diagram is ASCII, not mermaid, as the repo's picture rule asks. |
| R1-6 | fixed in Failure modes and Design: no trace or video in this slice, screenshots local under `--out`, never uploaded or committed, the proof record names files only. |
| R1-7 | fixed in Design and Interfaces: no `gh pr view` grant and no `git diff` grant (the lead supplies URL and head SHA); the leading-star glob residual is named, not hidden. The kit-wide `git diff --output` note is not this spec's to fix. |
| R1-8 | fixed in Infrastructure changes, Interfaces (`--doctor`) and Design: exact pin plus lockfile, `--ignore-scripts`, install root outside the checkout and the target repo, the runner never installs. |
| R2-3 | fixed in Interfaces (row rules, `ready.text` required) and Edge Cases 3 and 4: unreachable, not ready and access-wall cases are NO-CHECK, never FAIL (AC-7). |
| R2-4 | fixed in Failure modes (flaky row): wait for load and fonts, one retry, `flaky: true`. Masks and animation settings belong to the pixel layer and move to 292c. |
| R2-5 | moved to follow-up 292c: platform-suffixed baselines and the pinned image. |
| R2-6 | moved to follow-up 292c (missing baseline as NO-CHECK, never written into the checkout). The repo-write half is fixed here: the runner writes only under `--out` and refuses it inside a git work tree (AC-8). |
| R2-7 | fixed in Interfaces (`--doctor` exit codes 20, 21, 22) and AC-9: NO-CHECK rows with the reason, suite SKIP with a reason, installing is an operator step. |
| R2-8 | fixed in Interfaces (defaults 10 s, 30 s, 300 s, lower-only flags) and AC-6: per-step, per-scenario and run budgets, NO-CHECK on exhaustion, browser closed on every exit path. |
| R2-9 | moved to follow-up 292b: token and layout checks stay advisory and scoped until a false-positive rate is measured on a real app. |
| R2-10 | fixed in Design (browser cache inside the install root) and Failure modes (concurrent runs): port 0 for the fixture, per-run out dir, read-only install during a run. |
| R3-3 | fixed in Interfaces: a scenario is explicit data (step verbs, role locators, expect text); a criterion that cannot be mechanized gets a `skip` entry or an agent-added NO-CHECK row; the lead names negative cases from the criteria and the agent checks them. |
| R3-4 | fixed in Solution and Grounding sample 4: the non-existent path set is dropped; one table row, selected by the lead; the path classifier moves to follow-up 292e. |
| R3-5 | fixed in Design (distribution honesty) and Scope: the default input is a lead-supplied URL; the Cloudflare preview shape is the consumer's example, not the interface. A local branch with no pull request has no preview (Edge Cases 11). |
| R3-6 | moved to follow-up 292d together with R1-3. |
| R4-2 | fixed in the whole rewrite: header in the model spec's form with a real named-failure Depth line, Picture, Terms, Design, Approaches, Chosen approach, Interfaces, Task Breakdown, After state, Quality requirements, Edge Cases, Failure modes, Grounding, Decision Log. `## Test plan` is left for the later test-plan step. |
| R4-3 | fixed in Acceptance Criteria: every criterion has a named suite case or a recorded live dispatch, and a negative control. |
| R4-4 | fixed in Scope and Design: no config knob, no `--ui-only`, no vision pass; the viewport matrix is a runner default overridable inside the scenario file only. |
| R4-5 | fixed in Design (philosophy alignment): named consumer, lens-versus-lane argument with the `ui` namespace weighed, the gstack `/qa` question answered without describing a tool that was not inspected, Playwright as a declared dependency that degrades to SKIP or NO-CHECK. Honest limit recorded: no consumer has run it yet. |
| R4-6 | fixed in Solution and Design: one row in the Lens escalation table, no fourth leg, no `--ui-only`; the Size gate edge case is Edge Cases 10; the leg adds no gate-ledger record. |
| R5-1 | fixed in Solution (Approaches considered, five options with tradeoffs) and the Chosen approach, including why an agent still earns its dispatch. |
| R5-2 | fixed in Interfaces: exact `scenario.json`, `result.json`, runner flags, exit codes, `--doctor` output, stdout lines, and the agent's output and mapping. |
| R5-3 | fixed in Extensibility & boundaries: a verb per layer (`run.mjs scenario`), a `layer` field per row; only `scenario` ships. |
| R5-4 | fixed in Interfaces (output and mapping table): acceptance-verifier grammar reused, per-criterion table inside the Verification record, and how each runner result merges into `## Review`. |
| R5-5 | fixed in Grounding and References: the recipe facts are inlined; the research note is a marked maintainer reference, not required. |
| R7-1 | fixed in Quality requirements and Interfaces: caps of 12 scenarios, 4 viewports, 20 steps and a 5 minute budget; the model reads no images; cost order of magnitude stated. |
| R7-2 | fixed in Infrastructure changes and Failure modes (the pin ages): one pin file plus lockfile, `--doctor` shows pinned against installed, a bump reruns the suite and the live record, and the report prints NO-CHECK counts so a host that always skips is visible. |
| R7-3 | fixed in After state and Failure modes: all runtime state under one install root, the orphan list is in the README and After state, removal reports paths and deletes nothing by script. |
| R1-9, R2-11, R3-7, R3-8, R4-7, R5-6, R5-7, R7-4 (notes) | R1-9 moved to 292c (container hardening); R2-11 fixed in Edge Cases 3 (bounded backoff); R3-7 fixed in Design (the config name `.kit.toml` is named only to reject the knob); R3-8 fixed in Solution (the three old open questions are answered); R4-7 fixed by file-borne trust inputs; R5-6 moved to 292e; R5-7 fixed in Design (alignment, with the leg advisory inside the battery); R7-4 fixed by the README and the live record. |

### Decisions taken, as the delta from the original contract

- Scope is slice 292a only: the agent, the runner (scenario layer), the JSON scenario contract, `result.json`, a runner-derived verdict, one battery table row, a static fixture, one suite and one live dispatch record. Token, layout, axe, pixel, preview-comment discovery, storage state, `--ui-only`, a path classifier, vision and the GitHub twin are follow-up slices 292b to 292e.
- Approach A: the lead writes `scenario.json`; the agent has no `Write`, no `Edit`, no `npx playwright` and no `gh pr view` grant; the agent earns its dispatch by the coverage cross-check and a bounded report.
- The three old open questions are answered: a static fixture served on loopback; viewport matrix 390, 768 and 1280 as a runner default overridable only in the scenario file; the storage-state convention moves to 292d. Open questions end at `None.`.
- Playwright is pinned in `lib/ui-verify/package.json` plus a lockfile and installed by the operator with `--ignore-scripts` into an install root that the kit's data-path resolver names (`cache ui-verify`, env `UI_VERIFY_HOME`, new entry owed in `lib/config/data-path.sh` and a registry row). Browsers live inside that root.
- Delta from the brief, with the reason: the URL, head SHA, allowed hosts and loopback permission ride in the lead-written scenario file, not argv, because the agent types argv and page text from an earlier step can steer it. The runner refuses a scenario file or out dir inside a git work tree so a pull request cannot supply either. The brief still repeats the head SHA so the agent can cross-check it.
- The allowed-host list is a lead-supplied list in the scenario file, not a `.kit.toml` knob (a project `.kit.toml` rides inside the pull request).
- Unsampled in the probe and marked so in `## Grounding`: request abort, service-worker block, permissions, downloads, popups, the resolved-address check, the `playwright` library package (the probe used the test package), and the permission matcher's treatment of the grant glob.
- Honest limit recorded: the downstream-lane bar is argued as lens-not-lane, and no consumer has run it yet, so follow-ups wait for one real consumer run.

## Spec revision (round 2 answers)

Each row answers one finding of the round 2 validation report. The spec carries the answer; this table only points at it. New criteria: AC-15 (`browser-sandbox`), AC-16 (`fixture-serves`), AC-17 (`internal-error`). The suite tasks were split and renumbered (old TASK-9 and TASK-10 are now TASK-9 to TASK-13).

| Finding | Answer |
|---|---|
| S1-1 | applied with change: sandbox on, no `--no-sandbox`, NO-CHECK `browser sandbox unavailable` with no unsandboxed retry (Design, Picture, Failure modes, AC-15). The report's check lists processes while `/hang` runs, which needs a live browser at an exact moment; the runner instead scans its own run-id processes after launch and records `browser.sandbox`, `no_sandbox_seen`, `launch_attempts` in `result.json`, and a test-only fault hook covers the failed-sandbox path. |
| S1-2 | applied with change: grant text, Failure modes row, Chosen approach and DEC-6 follow the report; the runner's own-path self-check is kept per the lead decision, scoped honestly as a guard against honest mistakes (the report notes it cannot stop planted code). Because the kit checkout is itself a git work tree, the check also refuses a run with the kit checkout as the current directory; Edge Case 15 and the README say so. The bare-command shim grant is named in Out of scope 292b, not built. |
| S1-3 | applied in Interfaces (result.json, stdout, brief), AC-1, Task 6 |
| S1-4 | applied in Design, Picture, AC-4, Failure modes (WebRTC), Grounding |
| S1-5 | applied in Interfaces (result.json sanitizer) and AC-5 |
| S2-1 | applied with change: exit 4 and the wrapper as written; the unresolvable allowed host sits in the exit 2 row and in the allow_hosts rule, not in the exit 3 row, because exit 3 means "refused, nothing written". AC-3 gains the unreadable path; AC-17 is the exit 4 case. |
| S2-2 | applied with change: run-id marker, launch cap 60 s, `duration_ms` from launch, pgrep by run id as written. The report's flags (2000/5000/12000) do not force "a following scenario ends `run budget spent`" (one hang costs 2 s of a 12 s budget), and a clock from launch lets a loaded host decide the first row. The run budget clock now starts at the first scenario, and AC-6 uses three hang scenarios plus one normal scenario with a 5000 ms budget and asserts only the first and last row reasons, exit 2, recorded `browser.pids` and `browser.leftover_pids`, a 40 s backstop and the pgrep poll. DEC-14. |
| S2-3 | applied in Terms, AC-7, Failure modes |
| S3-1 | applied with change: the entry is rejected at validation as the report says, but per the lead decision its row is NO-CHECK `scenario asserts nothing` (exit 2, other entries still run) instead of exit 3 for the whole file. The case lives in AC-2 (`no-ac`). DEC-13. |
| S3-2 | applied in Interfaces (Step semantics block); AC-1 gains an `element not found` control |
| S3-3 | applied in Interfaces (role list), Task 1 README list, AC-11 |
| S4-1 | applied with change: the new PASS-plus-agent-row row and the exit 4 row as written, plus an exit 3 and any-other-exit row so every exit code maps; the FAIL rows are keyed on any NO-CHECK row from the runner or the agent. Seven rows; AC-12 says seven. DEC-15. |
| S4-2 | applied in Task Breakdown (TASK-1 depends on TASK-2, listed first; AC-2 moved to TASK-5; AC-16 for the fixture) and Picture |
| S4-3 | applied with change: the report's TASK-9b would carry nine criteria, over the five-criterion cap, so the suite is four tasks (TASK-9 to TASK-12), each with four criteria, and the live record is TASK-13. A criterion-to-task table was added. |
| S4-4 | applied in AC-9, AC-11 and the Grounding dry traces |
| S4-5 | applied in AC-9 and Verification (`UI_VERIFY_REQUIRE=1`, the last-line count) |
| S5-1 | applied in TASK-7 and AC-13 |
| S5-2 | applied in TASK-8 (kit-health line, PHILOSOPHY paragraph); the PHILOSOPHY sentence cites the spec by path, not by bare ID |
| S7-1 | applied in Infrastructure changes, `--doctor` output, TASK-1 README list, Failure modes, AC-9 |
| S1-6 | skipped (NOTE): checked and acceptable, no change |
| S2-4 | skipped (NOTE): accepted by the retry design, no change |
| S5-3 | skipped (NOTE): advisory; the position and the gate on 292b to 292e are already in Design, and S5-2 adds the kit-health line |
| S5-4 | applied in API changes and TASK-2 (legacy value is the empty string) |
| S5-5 | applied in TASK-8 (rebase, then regenerate `FEATURES.md` last) |
| S5-6 | applied in Design (Philosophy alignment, N4 bullet) |
| S7-2 | applied in Quality requirements (4-viewport maximum stated) |

## Build notes from round 3

Round 3 returned APPROVED with no CRITICAL. The spec carries the nine WARNING changes (T1 to T9) and the decisions below. Read this list before coding. Line numbers are of the VALIDATED spec.

Decisions already in the spec text (a builder reads the spec section, not this list):

- Launch failure versus crash (spec line 243, Decision Log DEC-18): a `launch()` that throws or passes the 60 s cap is exit 2; the error text decides `browser sandbox unavailable` (matches `sandbox`) or `browser did not start`. Exit 4 is only an uncaught exception or a browser that died after launch with no row.
- `--doctor` skips the own-path check and every scenario guard (spec line 205, DEC-19). Run it from the kit checkout.
- The `UI_VERIFY_TEST_FAULT` hook is split: `internal-error` in TASK-1, `sandbox-unavailable` in TASK-4 (DEC-23). The sandbox fault reports the failure without starting a browser and records `launch_attempts` 1.
- A scan that finds no run-id process after a successful launch is an unverified sandbox: every row NO-CHECK `browser sandbox unavailable`, `browser.pids` empty (DEC-21). No fault value covers this branch; it shares the row path of the sandbox fault.
- WebSocket handling (spec line 126, DEC-24): pass an allowed host through with `connectToServer()`, close an off-list host with `ws.close()` and never connect it. `offsite.html` writes `offsite done` when both attempts settle, and the AC-4 scenario ends on `expect_text` `offsite done`.
- Clocks (spec line 228, DEC-20): only time inside a step counts against the scenario clock and the run budget. The `hang-bounded` backstop is 100000 ms.
- Bounds and names paragraph (spec line 220, DEC-25), which closes Buildability points 5 to 11: reason `scenario timeout`; retry per scenario and viewport; screenshot names `ac-<n>[-neg]-<width>-<name>.png`; preflight gaps of one fifth then two fifths of the step timeout; a missing `within` element is FAIL `element not found`; identity read from the document response of `target.url`; `lib/config/data-path.sh` found at `../config/data-path.sh` from the runner's real path.
- Hand mutations (Verification section, DEC-26), which closes Buildability point 12: AC-6, AC-15 and AC-17 controls and the AC-9 pin-age case run on a temp copy of `run.mjs` outside any git work tree, with `UI_VERIFY_HOME` set, recorded in the proof file. The pin-age case puts the copy next to a temp `package.json`.
- The live dispatch (TASK-13, AC-14, DEC-22) runs from a scratch directory outside any git work tree, after the agent is installed. Record that directory.

NOTE findings, not in the spec text:

- T11, suite breadth: add to the `guard-refusals` case these extra refusal rows of the same case: `schema` not 1, missing `ready.text`, a `head_sha` that is not 40 lowercase hex, a duplicate (`id`, `kind`), `steps` together with `skip`, a role outside the twelve, a string over 200 characters, `identity` with both keys (spec line 438 lists the base set). The test plan carries them as rows.
- T11, load: the browser cases that are not about viewports (AC-1, AC-4, AC-5, AC-7) set `"viewports": [1280]`, so a loaded host runs one context per scenario, not three.
- T13, weak scenario: a scenario with only `expect_no_text` or `expect_url` passes with little checked (spec line 204). The agent's strength check is the cover. Optional tightening if the lead wants it: a `criterion` scenario must hold at least one `expect_text`. Not applied; AC-2's mutation stays valid either way.
- T12, applied as a contradiction fix: the Picture "also built" line and the orphan list now name the README, `package.json`, the lockfile, `--doctor`, the suite and the live record.
- T14, applied: Grounding sample 7 now says the depth check on the rewritten header printed nothing and exited 0.
- T15, no change: on a plain Cloudflare preview the identity is `unverified` until slice 292d, so a typical PASS carries only that printed word. The claim that the agent grant cannot set `UI_VERIFY_TEST_FAULT` rests on matcher behaviour that is in the Grounding "not sampled" list; it is not load-bearing, because the hook can only lower a result.

## Build log (A1: contract, guards, fixture)

Delta from the spec for the first build half (data-path entry, runner contract and guards, fixture, suite skeleton and the no-browser cases). Nothing here restates the spec.

Decisions the spec did not make:

- The runner never opens the install check, DNS or a browser when no entry is runnable (every entry is a `skip`, or asserts nothing, or the file has no scenarios). Those runs need no install, so they work on a host with no Playwright and the rows keep their own reasons.
- An environment fault (`install absent`, `playwright version differs from the pin`, `preview unreachable`) is applied to the runnable rows only. A `skip` row keeps `skipped by scenario: ...` and an asserts-nothing row keeps its own reason. The spec says "every row" for a `mismatch`; the next builder decides whether a skip row should take it too (the helper is `applyEnvironmentFault`).
- Order inside the runner: read and validate the scenario file, own-path check, `--out` check, DNS check of every allowed host (private address refuses with exit 3), then create `--out`, then the install check. An allowed host that does not resolve becomes `preview unreachable` before the install check, so it needs no Playwright to show.
- A timeout flag above its default is a usage error (exit 3), not a silent clamp.
- Rows that never ran carry `viewports: []`. A run with no browser records `browser.sandbox` false and `launch_attempts` 0. Top-level `reason` is the environment fault text, else `no AC` for an empty row set, else empty.
- Exit 4 writes `result.json` with `rows: []` and `reason` `internal error: <one line>`, whatever rows existed before the fault.
- `title` is optional, `fill.value` may be empty, and `goto` / `expect_url` paths may not hold whitespace or a backslash. `allow_hosts` entries are lowercased and may be a bracketed IPv6 literal; literal addresses are classified without DNS.
- A stdout `row` line ends after the evidence field with trailing spaces trimmed, so an empty reason prints as two adjacent separators.
- `UI_VERIFY_TEST_FAULT` values other than `internal-error` are ignored by the runner for now.
- The suite takes optional case names as arguments (`bash tests/test-ui-acceptance-verifier.sh guard-refusals`), so a browser case can be run alone on a loaded host. Browser cases are looked up as `case_<name with _>` functions listed in `BROWSER_CASES` and are simply absent until written; nothing placeholder passes.
- The doctor's "good install" exit 0 is proven with a fake install (a `node_modules/playwright/package.json` at the pin plus a `browsers/chromium-1` directory), because the doctor only reads files. It needs no real Playwright.
- The no-node case re-runs this suite with a PATH of symlinks to common tools and no node, on three cheap cases, and the same cases again with node as the control.

Seams the next builder fills (all in `lib/ui-verify/run.mjs`):

- `driveBrowser(context)` is the one seam. It currently throws, so a host that has the pinned install and a runnable scenario exits 4 until it is built. It receives `{ spec, runnable, rows, timeouts, runId, outDir, installRoot, playwright }` and returns `{ outcomes: Map<rowKey, {status, reason, observed, flaky, viewports, evidence}>, identity, blocked_requests, browser, duration_ms, environmentReason }`. `spec` holds the parsed and validated file (`url` as a URL object, `allowHosts` as a Set of normalized hosts, `allowLoopback`, `headSha`, `readyText`, `viewports`, `identity` as `{kind, name}` or null). `runnable[i]` is `{ key, entry, row }`, the key being `<id>|<kind>`. `timeouts` is `{ stepMs, scenarioMs, runBudgetMs }`.
- Helpers already there: `sanitize`, `normalizeHost`, `classifyAddress`, `inspectInstall`, `resolveInstallRoot`, `readPin`, `deriveSummary`, `emptyBrowserRecord`. The `UI_VERIFY_TEST_FAULT=sandbox-unavailable` branch belongs at the top of `driveBrowser`.
- The suite helpers for browser cases: `browser_gate <case>` (SKIP with the doctor's reason), `start_fixture` / `stop_fixture` (sets `FIX_PORT`, `FIX_PORT2`), `run_runner`, `jget`, `mutate`, `next_out`, `$BASE`.

Negative controls run in this half (hand mutations on a temp copy of `run.mjs` outside any git work tree, next to a copy of `package.json`, selected with `UI_VERIFY_RUNNER`; the case run alone each time). The in-suite controls (data-path entry removed, agent file and battery copies, MANUAL and README copies, fixture copy without `wall.html`, no-node PATH) are asserted by the suite itself.

| Mutation | Case | Red line |
|---|---|---|
| delete the `target.url` host check | `guard-refusals` | `FAIL refused: a URL host missing from allow_hosts (exit 2, 0 stderr lines: )` |
| delete the own-path self-check call | `guard-refusals` | `FAIL refused: a runner copy inside the scratch git repo that is the current directory (exit 2)` |
| run `main` without the wrapper and handlers | `internal-error` | `FAIL the injected fault exits 4 (exit 1)` |
| delete the pin compare | `doctor-and-skip` | `FAIL doctor with another installed version exits 21 (exit 0)` |
| make a pin older than 120 days change the doctor exit | `doctor-and-skip` | `FAIL a pin 121 days old prints the bump note and still exits 0 (exit 5)` |
| count NO-CHECK rows as PASS in the verdict | `doctor-and-skip` | `FAIL the verdict is NO-CHECK, never PASS` (and four more) |

Open at the end of this half: `docs-rows` stays red on `feature-registry check` (FEATURES.md has drifted; the lead regenerates it last). The seam `driveBrowser` throws, so a host with the pinned install exits 4 on a runnable scenario until the browser half lands.

## Build log (A2: browser, steps, bounds)

Delta from the spec for the second build half. Nothing here restates the spec.

Install: the documented one-liner from `--doctor` was right and complete (copy `package.json` and the lockfile, `npm ci --ignore-scripts`, local `playwright install chromium` with `PLAYWRIGHT_BROWSERS_PATH`). Wall time 24 s on this host (fast CDN, load average 30 to 45), `node_modules` 19 MB, `browsers/` 606 MB (chromium, headless shell 159.0.8154.6 and ffmpeg). `playwright install chromium` installs the full chromium as well as the headless shell; the doctor only needs a `chromium*` directory.

Sandbox: the sandboxed headless launch works on this host (macOS). One launch took about 1.2 s. The runner recorded `sandbox` true, `no_sandbox_seen` false, `launch_attempts` 1 and one pid carrying the run id. A `chromiumSandbox: false` control makes `no_sandbox_seen` true.

Decisions the spec did not make:

- A step in flight yields to the scenario clock: its wait is the smallest of the step timeout, the scenario time left and the run budget left. Whichever binds names the reason (`scenario timeout`, `run budget spent`, else the step's own finding: FAIL for click, fill and expects, NO-CHECK `page did not settle` for goto). Ties go to the step. This pins test-plan row 33 to `scenario timeout`.
- The scenario clock restarts per attempt (a retry is a new attempt); the run budget is shared by every attempt including retries.
- Retry keeps the first FAIL when the retry does not pass (a retry that ends NO-CHECK for budget never turns a FAIL into NO-CHECK).
- A FAIL row has an empty `reason`; the finding is in `observed`. A `click` or `fill` on an element that matches but never becomes actionable is FAIL `element not actionable: role=<role> name=<name>`.
- `expect_text` `observed` follows the spec literally (first `[role=alert]` or `[role=status]` element even when it is empty).
- Preflight reads the ready text from `<body>` `innerText`, whitespace collapsed. Order of its findings: status 4xx or 5xx or a navigation error is `preview unreachable` (retried), ready text missing is `preview not ready` (retried), a top-level hop off the allowed hosts is `redirected off an allowed host` (not retried), then identity `mismatch` is `preview is not the head`. A skip row keeps `skipped by scenario` under a mismatch (A1 left this open; applyEnvironmentFault applies to runnable rows only).
- `browser.sandbox` is true only after the scan found at least one process with the run id and none with `--no-sandbox`. A fault or an unverified scan leaves it false.
- Test-plan row 43: no third fault value. The suite puts a `ps` stub that lists nothing first on `PATH` for one real run; the runner's scan then finds no process carrying the run id, so the unverified-sandbox branch runs for real, with a real browser, and the suite checks with the real `pgrep` that the runner still closed it. Control: a temp copy that treats an empty scan as sandbox-ok turns the case red.
- Test-plan row 33: pinned as above; control is a temp copy with the scenario clock removed from the step limit (`hang-bounded` red on the `scenario timeout` row).
- Identity padding (test-plan row 37, "a value with spaces around it") is not testable through a response header, because the HTTP layer strips it; the trim is in `judgeIdentity` and is exercised only by the upper-case case.
- The fixture gained `/redirect` (302 to the second listener as `localhost`) and `/redirect-ok` (302 to `/`), and `fixture-serves` checks both.
- `hang-bounded` passes `--step-timeout-ms 2000` as the spec says, and the preflight is bounded by the step timeout too, so a very loaded host could fail that case on the preflight. Not seen on this host (load 30 to 100).

Request guard (security review of the containment commit, two gaps fixed in the same task):

- Redirect bypass: Playwright does not run the route handler again for the hop of a `route.continue()` request. A first design used `route.fetch({ maxRedirects: 0 })` and fulfilled the 3xx. Observed on the real browser: a fulfilled 302 is not routed again either (one handler call, then Chromium follows the hop itself), and fulfilling every response made Chromium block the page's own WebSocket to `localhost` (the fulfilled document has no remote address, so it counts as a public page reaching a private one), so that design was dropped. What stops the hop is the DNS pin below: every name and every IP literal not on the list fails at name resolution (observed: `MAP * ~NOTFOUND` also blocks `http://127.0.0.1:<port>/` unless that literal is mapped, so allowed IP literals are mapped to themselves). A failed request for a host off the list with `ERR_NAME_NOT_RESOLVED` is counted in `blocked_requests` like a blocked request, and a failed top-level navigation gives the row NO-CHECK `redirected off an allowed host`.
- DNS rebinding: the runner already resolved each allowed host once; it now keeps the validated address (IPv4 first) and launches Chromium with `--host-resolver-rules=MAP <host> <address>, ..., MAP * ~NOTFOUND`, recorded in `browser.args`. No Node-side fetch exists, so there is no second resolver to dodge it. Residual: a hop after the first, or a hop to an allowed host that itself redirects off the list, is not routed and shows as `page did not settle` or a counted blocked request rather than always `redirected off an allowed host`; it still cannot reach the host.
- Consequence for the spec's controls: with the pin in place the route guard is not the only layer, so removing the route (or the WebSocket check) alone leaves the offsite listener at 0 hits. That is the pin working, and it was observed. The control for the route needs the pin removed too (below).
- Rebinding itself cannot be tested hermetically (no controllable DNS), so the suite asserts the launch arguments the runner recorded, plus the real redirect and offsite requests against the fixture.

Negative controls run in this half (hand mutations on a temp copy of `run.mjs` outside any git work tree next to a copy of `package.json`, `UI_VERIFY_RUNNER` selecting it, the case run alone each time). Red lines:

| Mutation | Case | Red line |
|---|---|---|
| browser status forced to PASS | `rows-and-planted-bug` | `FAIL the planted bug (/?bug=1) exits 1 (exit 0)` |
| empty row set no longer NO-CHECK | `no-ac` | `FAIL an empty scenarios array exits 2 (exit 0)` |
| expect-step rule removed | `no-ac` | `FAIL a goto-and-screenshot scenario exits 2 (exit 0)` |
| `observed` stored raw | `hostile-text-fenced` | `FAIL observed holds no line break, U+2028, U+202E, pipe or backtick and is 1 to 200 characters` |
| screenshots written to the cwd | `git-status-clean` | `FAIL git status --porcelain is empty after the run` |
| request route always continues and no resolver pin | `offsite-request-aborted` | `FAIL the second listener saw no plain hit and no WebSocket upgrade ({"hits":2,"upgrades":0})` |
| WebSocket check always connects and no resolver pin | `offsite-request-aborted` | `FAIL the second listener saw no plain hit and no WebSocket upgrade ({"hits":0,"upgrades":2})` |
| resolver pin removed (route kept) | `offsite-request-aborted` | `FAIL the second listener saw no hit through the redirect ({"hits":1,"upgrades":0})` and the launch-argument check |
| request route always continues (pin kept) | `offsite-request-aborted` | green, 13 passed: the pin alone keeps the listener at 0 hits |
| `chromiumSandbox: false` | `browser-sandbox` | `FAIL a normal run exits 0 (exit 2)` |
| an empty scan treated as sandbox-ok | `browser-sandbox` | `FAIL a scan that finds no process carrying the run id (a ps stub that lists nothing) exits 2 (exit 0)` |
| browser not closed | `hang-bounded` | `FAIL browser.leftover_pids is empty` (Playwright's exit hook still ends the process, so the pgrep poll stays green) |
| run budget not enforced | `hang-bounded` | `FAIL the last row is NO-CHECK 'run budget spent'` |
| scenario clock does not cap a step | `hang-bounded` | `FAIL the scenario clock caps a step in flight: the row is NO-CHECK 'scenario timeout'` |
| `mismatch` read as `unverified` | `identity-and-readiness` | `FAIL a different 40-hex value -> mismatch (exit 0, got: unverified/ffffffffffff/PASS/)` |
| a UUID read as a build id | `identity-and-readiness` | `FAIL a UUID -> unverified (exit 2, got: mismatch/123e4567-e89/NO-CHECK/preview is not the head)` |
