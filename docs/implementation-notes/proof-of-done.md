# Implementation notes -- proof-of-done

Extends the execution-backed-verify work on this branch: make the **negative control** a
required, kit-produced part of a proof-of-done (not just README prose), and prove it
behaviorally by driving the verify flow end-to-end via an independent agent.

## 2026-06-06 Plan / scope reading
- Context: `/goal proof-of-done`, built on `feat/verify-by-execution` (commit 7fb23ce).
- Decision: two deliverables , (1) wire negative-control into `task-verifier` + `execute` + `verify` + the convention, pinned by meta-tests; (2) one genuine end-to-end proof produced by an independent agent driving the verify flow on a real demo spec, with RED/GREEN captured.
- Why: Han named the gap , the prior proof was green-only and hand-followed, not kit-produced. Proof of done = green + a negative control that bites + reproducible.

## 2026-06-06 task-verifier cannot run a bash test suite (real gap)
- Context: `agents/task-verifier.md` tool allowlist is `Bash(npm test*|go test*|pytest*|cargo test*)` + git. dwarves-kit's own suite is `bash tests/test-meta.sh`.
- Decision/Change: widen the allowlist minimally to also permit a project's bash/make/just suite runner, so the read-only verifier can actually run the suite on non-npm/go/pytest/cargo stacks.
- Why: a verifier that cannot run the project's tests is broken for bash-stack repos (dwarves-kit included); it also blocks the behavioral proof here.
- Alternatives considered: drive verify only via the orchestrator (full Bash) and leave the agent narrow (rejected: leaves the agent genuinely unable to verify bash repos, the actual bug); broad `Bash(*)` (rejected: too wide for a read-only role).
- Impact: `task-verifier` can now run `bash tests/*` / `make test*` / `just test*`.

## 2026-06-06 Behavioral proof = independent worktree agent
- Context: "kit-produced, not hand-authored" requires the records to come from a real execution in a context that is not me narrating.
- Decision/Change: dispatch one `isolation:worktree` agent that follows the verify flow on a tiny real demo spec (`lib/proof-demo.sh`), runs the real check, performs the negative control (revert -> RED -> restore -> GREEN), and returns the captured records; I transcribe them into `docs/verification/proof-of-done-demo.md`.
- Why: the worktree isolates its revert/restore from the shared checkout; the agent's returned command/exit/excerpt are real, not authored.
- Alternatives considered: a standalone non-isolated run (rejected: reverting in the shared tree is unsafe); a foreign pytest/go demo (rejected: pollutes the bash-stack repo).
