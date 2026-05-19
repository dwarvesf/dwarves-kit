# Spec: v1.5.0 Polish (CI + README hero + demo + contributing)
Generated: 2026-04-21
Status: VALIDATED
Note: Previous v1.4 spec preserved in git history at commit 711b8a9.

## Problem

After v1.4 plugin packaging shipped, 4 adoption-cost gaps remain from the audit (2026-04-21):

1. **No CI**: regressions in hooks or tests can ship undetected. No automated trust signal.
2. **README opens with utility tables**: visitors who don't scroll see no value prop. First-screen conversion is poor.
3. **No demo / examples**: new users can't see what a real `.planning/SPEC.md` or `CLAUDE.md` looks like in context. They have to install the kit and infer the format from `commands/spec.md`.
4. **No CONTRIBUTING.md**: the kit has opinionated rejection criteria in PHILOSOPHY.md but no contributor-facing surface. AI-generated PRs (the rising threat for any popular AI-tooling repo) have no rejection wall.

## Solution

Four additive changes. No breaking changes. No removals.

| Task | Files | Type |
|---|---|---|
| TASK-B1 | `.github/workflows/test.yml` (new) + `README.md` badge | New CI |
| TASK-B2 | `README.md` (top section rewrite) | Modify |
| TASK-B3 | `examples/hello-spec/` (new dir + 3 files) | New demo |
| TASK-B4 | `CONTRIBUTING.md` (new at repo root) | New |

All independent, no inter-dependencies.

## Task Breakdown

- [ ] **TASK-B1: GitHub Actions test workflow + status badge**
  - Files: `.github/workflows/test.yml` (new), `README.md` (badge URL)
  - Workflow: runs `bash tests/test-hooks.sh` on `push` to `master` and on `pull_request`. Matrix: macos-latest + ubuntu-latest. Installs `jq` on Ubuntu (preinstalled on macOS runners).
  - Acceptance criteria:
    - [ ] `.github/workflows/test.yml` exists, valid YAML
    - [ ] Triggers: `push` (master) + `pull_request` (any branch)
    - [ ] Runs on both `macos-latest` and `ubuntu-latest`
    - [ ] Step that installs jq on Ubuntu (`apt-get install jq` or similar)
    - [ ] Step that runs `bash tests/test-hooks.sh` and asserts exit 0
    - [ ] README has a CI status badge linking to the workflow

- [ ] **TASK-B2: README hero rewrite**
  - Files: `README.md` (insert new top section above current "What it does")
  - Changes: tagline, 2-3 sentence value prop, 4-6 badges, "who this is for" + "who this is NOT for", quick install pointer to the existing Install section.
  - Acceptance criteria:
    - [ ] First 30 lines of README contain: a tagline, a value-prop paragraph, the badge row, and an install pointer
    - [ ] Badges include: CI status, version, license, Claude Code compatibility (or shields.io variant)
    - [ ] "Who this is for / not for" section present (mirrors PHILOSOPHY's target user discipline)
    - [ ] Existing tables/sections retained below; no destructive rewrite
    - [ ] No fabricated stats or claims (no "used by X teams", no "X% adoption" — we don't have that data)

- [ ] **TASK-B3: Demo project at `examples/hello-spec/`**
  - Files: `examples/hello-spec/README.md`, `examples/hello-spec/CLAUDE.md`, `examples/hello-spec/.planning/SPEC.md`
  - Demo subject: a tiny CLI tool feature (chosen so the spec is small but non-trivial — e.g., "add a `--version` flag to a Python CLI"). Realistic enough to show the format, small enough to read in under 5 minutes.
  - The walkthrough README explains: what each file is, what command would generate it (`/user:spec` produces the SPEC, etc.), and where the kit picks it up next (`/user:execute` reads it).
  - Acceptance criteria:
    - [ ] `examples/hello-spec/README.md` exists with a "what this shows" intro and a 3-section "the files" walkthrough
    - [ ] `examples/hello-spec/CLAUDE.md` exists, follows the kit's CLAUDE.md template structure (Project, Tech Stack, Commands, Repository Structure, Code Quality Rules, Workflow, Spec Location)
    - [ ] `examples/hello-spec/.planning/SPEC.md` exists with all the standard sections (Problem, Solution, Technical Design, Task Breakdown, Acceptance Criteria, Edge Cases, Out of Scope, Decision Log)
    - [ ] All 3 files are <120 lines each (small enough to read; lean per PHILOSOPHY)
    - [ ] No mock-up disclaimers like "this is just an example" inside the files themselves — they should look real (the meta-explanation lives in the README only)

- [ ] **TASK-B4: CONTRIBUTING.md in rejection-wall voice**
  - Files: `CONTRIBUTING.md` (new at repo root)
  - Adapts superpowers' AGENTS.md framing: direct address to AI agents, numbered MUST list before opening a PR, "what we will not accept" enumeration. Specifics come from PHILOSOPHY.md's actual rejection criteria, not lifted verbatim from superpowers.
  - Acceptance criteria:
    - [ ] `CONTRIBUTING.md` exists at repo root
    - [ ] Has an "If You Are an AI Agent" section addressing AI-generated PRs directly
    - [ ] Has a numbered "Before opening a PR you MUST" list (3-6 items)
    - [ ] Has a "What we will not accept" section enumerating PHILOSOPHY's rejection criteria (compiled binaries, no source citation, single-purpose features, can't-be-explained-in-one-sentence, duplicate of external tool, etc.)
    - [ ] References PHILOSOPHY.md as the source of truth (not a re-statement)
    - [ ] Cites superpowers v5.0.7 AGENTS.md as the framing source
    - [ ] Does NOT lift fabricated stats (no "94% rejection rate" — we don't have that data)

### Phase 2: Verify, docs, ship

- [ ] All 4 task acceptance criteria met
- [ ] `bash tests/test-hooks.sh` exit 0
- [ ] CHANGELOG entry under `[1.5.0]`
- [ ] No new ADR needed (no philosophy deviations; all changes additive within existing principles). If TASK-B3 reveals a missing principle (e.g., "examples must be real, not mocked"), add to PHILOSOPHY in a follow-up.
- [ ] `VERSION` → `1.5.0`
- [ ] Atomic commits: 1 per TASK + 1 docs + 1 version bump = 6 commits
- [ ] Tag `v1.5.0`

## Acceptance Criteria (global)

- [ ] All 4 task ACs met
- [ ] tests still 42/42
- [ ] No existing file deleted; no breaking changes
- [ ] CI workflow file is syntactically valid YAML (`yq eval . .github/workflows/test.yml > /dev/null` if yq available, else jq-on-the-yaml-parsed-via-helper or visual review)

## Edge Cases

1. **CI fails on first push** because of platform-specific path issue (e.g., bash version differences between macOS and Ubuntu). Mitigation: matrix runs both; first failure tells us which to fix. Acceptance criterion is "workflow file exists and is syntactically valid", not "CI green on first run". The actual run happens on push.
2. **README hero feels marketing-y** (overpromising). Mitigation: AC explicitly forbids fabricated stats. Tone matches kit voice (opinionated, factual, no theater).
3. **Demo project SPEC.md inception** — the demo SPEC will be a different scale than the kit's own SPECs. Mitigation: demo subject deliberately scoped to 2-3 small tasks (single feature in a hypothetical Python CLI); the kit's own SPECs cover larger phases.
4. **CONTRIBUTING accidentally re-states PHILOSOPHY**. Mitigation: AC "References PHILOSOPHY.md as source of truth (not re-statement)". Use one-line summaries that link to the section, don't copy.

## Out of Scope

- Animated GIF / asciinema in README (audit decided to skip — high recurring maintenance cost).
- SECURITY.md (audit decided to skip — solo maintainer, pure cargo-cult signal).
- Issue templates / PR template under `.github/` (deferred — would be a follow-up if we want; not core to v1.5).
- QUICKSTART.md for contractors (deferred — different audience, larger doc, separate task).
- GitHub Releases mirroring (cosmetic; tag annotations already have full notes).
- Multi-harness packaging (still deferred per PHILOSOPHY).
- Submitting to Anthropic's official marketplace (still manual step the maintainer does).

## Decision Log

- **DEC-001**: CI matrix is macOS + Ubuntu only, no Windows.
  - **Rationale**: hooks are bash scripts; Windows would need WSL or git-bash. PHILOSOPHY's target user is on macOS; contractors are on macOS or Linux. Adding Windows is theater for a user we don't serve.

- **DEC-002**: Demo project subject is "Python CLI `--version` flag".
  - **Rationale**: small (2-3 tasks), realistic (every CLI has a `--version`), language-neutral enough to be readable to a Go/TS engineer, doesn't require non-default deps.
  - **Rejected alternative**: dogfooding the kit's own v1.4 spec as the example. Would be elegant but the spec is 200+ lines — too much to read in 5 minutes. Demo needs its own small subject.

- **DEC-003**: CONTRIBUTING.md lives at repo root, not under `docs/` or `.github/`.
  - **Rationale**: GitHub auto-discovers `CONTRIBUTING.md` at repo root and surfaces it on the PR new-issue flow. Putting it under `.github/CONTRIBUTING.md` also works but root is more visible to humans browsing the repo.

- **DEC-004**: No new ADR for v1.5 (all changes additive within existing principles).
  - **Rationale**: ADRs document non-obvious decisions and philosophy deviations. v1.5 has no deviations. Skipping the ceremony for ceremony's sake.

## Source citations

- CI workflow pattern: standard GitHub Actions matrix testing (no novel approach).
- README hero structure: standard OSS README pattern (badges + value prop + audience). No specific source needed.
- Demo project pattern: standard "examples/" directory convention used by countless OSS projects.
- CONTRIBUTING.md voice: obra/superpowers v5.0.7 `AGENTS.md` (already adopted in v1.3 for kit-health; same source, different application).
