# Implementation notes: Codex hook parity

## Reviewer-driven contract correction

Context: The first design assumed Claude-shaped Stop and secret payloads were already portable.

Decision: Add an explicit Codex event adapter, fail closed on missing hard-hook dependencies, test trust invalidation, and narrow phase 1 to dual-runtime compatibility.

Why: Codex uses `last_assistant_message`, reports file edits as `apply_patch`, and binds hook trust to the exact definition hash.

Alternatives: Directly reuse the Claude manifest was rejected because synthetic unit calls could pass while real Codex dispatch remained uncovered.

Impact: Phase 1 adds one adapter and stronger live acceptance. Full vendor-neutral settings generation remains a later migration.

Open questions: None.

## Full-suite baseline failures

Context: The optional 148-suite project run exposed failures outside the Codex adapter scope.

Decision: Re-run each observed failure on the unchanged baseline and keep the scoped verification commands as the acceptance proof.

Why: The baseline reproduced the same reflect, repo-hygiene, and detached-process failures. The hook color failure disappears when the documented TTY environment unsets `NO_COLOR`.

Alternatives: Fixing unrelated baseline suites would mix separate purposes into this security change.

Impact: The three spec verification suites pass. The full project runner remains red for pre-existing environment and compatibility failures.

Open questions: None.

## Scope boundary correction

Context: The security review found that one SSH fixture could overstate secret-read coverage and that hook tests cannot prove full DLP.

Decision: Require a named secret-path matrix through Codex-shaped dispatch. State that Phase 1 does not inspect prompts, assistant output, hosted tools, or every specialized tool path.

Why: Tested hook paths can support a narrow enforcement claim. They cannot support an exhaustive token-leak claim.

Alternatives: Full prompt and output DLP was deferred because it changes the approved Phase 1 scope and requires a separate trust-boundary design.

Impact: The implementation and documentation must report exact covered paths and leave broader DLP as future work.

Open questions: None.

## Shared denylist expansion

Context: Codex credentials and common Cloudflare credentials were absent from the shared secret-path policy.

Decision: Add exact deny globs for Codex and Cloudflare credential files to the shared policy.

Why: A Codex-only duplicate denylist would split the security source of truth. Shared additive denials protect both runtimes.

Alternatives: Adapter-only path rules were rejected because they would duplicate policy logic.

Impact: Claude settings and manifests stay byte-identical. Claude will newly block reads of the added credential files.

Open questions: None.

## Installed-hook smoke compatibility

Context: CI invokes every installed hook script with an empty JSON object and no adapter target.

Decision: Treat only the exact empty-object probe as a standalone no-op. Keep non-empty untargeted events fail-closed.

Why: The adapter must follow the existing install smoke contract without weakening real hook dispatch validation.

Alternatives: Excluding the adapter from the shared smoke test would create a special-case coverage gap.

Impact: The install suite passes while malformed Codex events still return exit code 2.

Open questions: None.
