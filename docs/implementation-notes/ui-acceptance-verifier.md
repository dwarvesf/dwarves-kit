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
