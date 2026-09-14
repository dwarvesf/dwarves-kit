# SPEC-288: Codex hook parity for the essential dwarves-kit guardrail spine

**Status:** REVIEWED
Lane: full
**Source:** Operator request to run Claude Code and Codex together without vendor lock-in. Claude behavior remains the baseline and must not change.

## Problem

dwarves-kit ships a Claude plugin manifest and a Claude lifecycle hook manifest. Codex imports the plugin assets, but the package has no explicit Codex manifest or Codex-specific event allowlist. The installed package therefore depends on importer behavior and hook trust state. Operators cannot prove that Codex blocks the same destructive commands, secret reads, incomplete shipping, or unsupported completion claims.

The current project-level Codex hooks also rely on `CLAUDE_PROJECT_DIR`, which Codex does not guarantee. That consumer repair is outside this kit package change and follows after the plugin adapter ships.

## Design

Keep every policy decision in the existing Bash hook scripts. Add a Codex package adapter consisting of `.codex-plugin/plugin.json`, `hooks/codex-hooks.json`, and `hooks/codex-hook-adapter.sh`. The adapter normalizes Codex event fields before calling the shared policy script and returns a sanitized Codex block reason. It maps `last_assistant_message` to the shared Stop response field, maps Bash and `apply_patch` file targets into secret-path checks, and fails closed when a hard hook dependency is unavailable.

The Claude package surfaces remain unchanged. `hooks/hooks.json`, `.claude-plugin/plugin.json`, and Claude settings are pinned to baseline commit `e214ae5e7506dc0169ca03235a5ffe0e357b11e6`. Shared scripts may gain input compatibility, secret-log redaction, and additive denials for Codex and Cloudflare credential files. Those added secret denials also protect Claude because both runtimes share the policy.

The Codex adapter excludes lifecycle events that Codex does not support. Phase 1 enforces the five hard controls documented in `docs/architecture.md`: safety-gate, secrets-guard, ship-gate, commit-format, and anti-rationalization. Advisory and convenience hooks may ship when their event and output contracts pass the same adapter tests, but they do not expand the enforcement claim.

Phase 1 is not a complete data-loss-prevention boundary. It does not inspect prompt content, assistant output, hosted tools, or every specialized Codex tool path. The enforcement claim covers only the dispatch paths exercised by the acceptance suite. Documentation must preserve this limit and must not describe Codex hook coverage as exhaustive.

## Trust boundary

Codex requires explicit trust for non-managed project and plugin hooks. Installation alone does not activate enforcement. The live acceptance proof must confirm the current hook hash is trusted, execute real allow and deny cases through Codex, modify a disposable hook copy, and prove the changed hash is skipped until re-reviewed. Test fixtures must contain synthetic token shapes only and must never read live credential files. Full synthetic token values must not appear in stdout, stderr, or persisted logs.

## Non-goals

- No edit to Claude hook manifests or Claude settings. Existing Claude denials remain unchanged. The shared secret policy gains only the named additive credential paths.
- No migration of personal global hooks from dotfiles in this change.
- No automatic trust bypass in normal Codex use.
- No copy of policy logic inside the Codex adapter.
- No support claim for Gemini, Cursor, or OpenCode.

## Tasks

| # | Task | Files |
|---|---|---|
| 1 | Add a Codex plugin manifest, supported-event hook manifest, and event adapter | `.codex-plugin/plugin.json`, `hooks/codex-hooks.json`, `hooks/codex-hook-adapter.sh` |
| 2 | Add shared credential paths and make hard-hook security logs safe | `hooks/secrets-guard.sh`, `hooks/safety-gate.sh`, `hooks/commit-format.sh` |
| 3 | Add structural and behavioral parity tests with safe fixtures | `tests/test-codex-hooks.sh` |
| 4 | Document dual-runtime packaging, trust, and honest enforcement status | `README.md`, `docs/PHILOSOPHY.md`, `docs/architecture.md`, `docs/CHANGELOG.md` |
| 5 | Record offline tests, negative controls, and live Codex acceptance | `docs/verification/codex-hook-parity.md` |

## Acceptance criteria

- Codex discovers a valid `.codex-plugin/plugin.json` whose name and version match the Claude manifest.
- Codex loads `hooks/codex-hooks.json` without unsupported event names.
- Every command referenced by the Codex hook manifest exists and is executable.
- The Codex hard spine includes safety-gate, secrets-guard, ship-gate, commit-format, and anti-rationalization exactly once.
- A Codex-shaped Bash payload for a destructive command exits 2 through safety-gate.
- A Codex-shaped Bash payload for a harmless command exits 0 through safety-gate.
- Codex-shaped Bash payloads targeting `/workspace/app/.env`, `/workspace/app/.env.local`, `~/.docker/config.json`, `~/.config/gh/hosts.yml`, `~/.ssh/id_ed25519`, `~/.aws/credentials`, `~/.cloudflared/cert.pem`, `~/.config/cloudflared/config.yml`, `~/.codex/auth.json`, and `~/.codex/.codex-global-state.json` exit 2 without reading those paths. Equivalent `apply_patch` payloads for every path also exit 2.
- A Codex-shaped Stop payload using `last_assistant_message` and containing a known cop-out phrase causes anti-rationalization to request continuation.
- Missing `jq` makes each Codex hard-hook adapter refuse the operation with a dependency error.
- Synthetic token fixtures never appear in hook stdout, stderr, or isolated persisted logs.
- Documentation states that Phase 1 is not prompt/output DLP and that Codex tool-hook coverage is not exhaustive.
- Claude `hooks/hooks.json` and `.claude-plugin/plugin.json` remain byte-identical to baseline commit `e214ae5e7506dc0169ca03235a5ffe0e357b11e6`; the existing Claude hook suite stays green.
- The live acceptance run confirms trusted plugin hooks exercise allow and deny paths for safety-gate, secrets-guard, ship-gate, commit-format, and anti-rationalization.
- A disposable hook edit invalidates Codex trust and remains skipped until the modified hook is reviewed again.

## Test plan

| # | Case | Category | Covers | Expected | Proof |
|---|---|---|---|---|---|
| 1 | Codex manifest matches Claude identity | happy-path | AC-1 | Names and versions match | `bash tests/test-codex-hooks.sh` |
| 2 | Codex manifest uses only supported events | compatibility | AC-2 | No unsupported event appears | `bash tests/test-codex-hooks.sh` |
| 3 | Every referenced hook exists and is executable | integration | AC-3 | Zero missing targets | `bash tests/test-codex-hooks.sh` |
| 4 | Hard guard list is complete | boundary | AC-4 | Every required script appears once | `bash tests/test-codex-hooks.sh` |
| 5 | Destructive Bash payload | failure-injection | AC-5 | Exit 2 | `bash tests/test-codex-hooks.sh` |
| 6 | Harmless Bash payload | happy-path | AC-6 | Exit 0 | `bash tests/test-codex-hooks.sh` |
| 7 | Bash and apply-patch secret-path matrix | security | AC-7 | Every named path exits 2 with no file read | `bash tests/test-codex-hooks.sh` |
| 8 | Stop payload uses `last_assistant_message` | compatibility | AC-8 | Continuation decision | `bash tests/test-codex-hooks.sh` |
| 9 | Missing `jq` | dependency-failure | AC-9 | Hard adapter exits 2 | `bash tests/test-codex-hooks.sh` |
| 10 | Synthetic token fixture | data-leak | AC-10 | Token absent from outputs and logs | `bash tests/test-codex-hooks.sh` |
| 11 | Honest coverage statement | documentation | AC-11 | No complete-DLP or exhaustive-coverage claim | Documentation review |
| 12 | Claude package baseline | regression | AC-12 | No manifest diff and Claude tests remain green | Baseline diff plus suite |
| 13 | Real Codex hard-hook dispatch | acceptance | AC-13 | Five controls exercise allow and deny paths | Recorded live run |
| 14 | Hook hash changes after trust | trust-boundary | AC-14 | Modified hook is skipped pending review | Recorded live run |

## Verification

- `bash tests/test-codex-hooks.sh` exits 0.
- `bash tests/test-hooks.sh` exits 0.
- `bash tests/test-meta.sh` exits 0.
- `git diff --exit-code e214ae5e7506dc0169ca03235a5ffe0e357b11e6 -- hooks/hooks.json .claude-plugin/plugin.json` exits 0.
- Negative control: remove `safety-gate.sh` from `hooks/codex-hooks.json`; `bash tests/test-codex-hooks.sh` must fail.
- Live acceptance: install the branch package into an isolated Codex home, trust the exact hook hash through the supported trust flow, exercise the five hard controls, change a disposable hook, and prove Codex skips the changed hash pending review. Record outcomes without exposing credentials.

## After state

- Claude and Codex load separate runtime manifests from one dwarves-kit package.
- Both runtimes call the same Bash policy scripts through runtime-specific event adapters.
- Claude settings and manifests are unchanged. Claude also receives the additive Codex and Cloudflare credential-file denials from the shared policy.
- The package provides dual-runtime compatibility. A later source-of-truth migration can make the surrounding settings fully vendor-neutral.
- Codex hard-hook enforcement is claimed only after all five live trusted-hook acceptance cases pass.
