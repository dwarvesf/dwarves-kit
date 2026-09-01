# Impl notes: output-offload + deterministic-verify (SG-06)

Delta from the goal. Only off-spec calls live here.

## 2026-06-29 PostToolUse cannot strip the current turn's output
- Context: the naive reading of "offload the payload to a file and leave a pointer in context"
  implies the hook shrinks the in-context output.
- Reality: PostToolUse runs AFTER the tool result is captured into the transcript; a hook's
  `additionalContext` ADDS context, it cannot replace/remove `tool_response` (modifying it is
  non-portable, per the existing secret-guard-post hook).
- Decision: split the mechanism honestly ->
  - **Bash**: `BASH_MAX_OUTPUT_LENGTH` caps output AT THE SOURCE (before it enters context). This
    is the real per-turn token saver. Documented + a recommended value in WORKFLOW.md; the
    consumer sets it in settings.json `env` (kit does not force a global env).
  - **Non-Bash + Bash backstop**: the hook `output-offload.sh` detects an oversized
    `tool_response`, writes the FULL payload to a recoverable file, and emits a TERSE pointer
    (one line, ~30 tokens) nudging the agent to read the file / narrow scope next time, not
    re-request the whole output. The win is behavioral + durable recovery, not stripping.
- Why this still matters: it makes the bloat visible, gives a reversible full copy on disk, and
  trains scope-narrowing. The aggregate token win is BASH_MAX_OUTPUT_LENGTH + behavior change.

## 2026-06-29 threshold = OFFLOAD_MAX_TOKENS (default 2000), ~4 chars/token
- Token count is estimated as chars/4 (standard rough heuristic; no tokenizer in a shell hook).
- Fast path: if the WHOLE stdin payload is <= budget, exit 0 before any jq (keeps the common
  case to a string-length check, so the hook is cheap on every tool call).

## 2026-06-29 response-extraction reused from secret-guard-post
- The jq that coerces `tool_response` (string | {content...} | {stdout,stderr} | array) to a flat
  string is copied from the dotfiles secret-guard-post hook (already battle-tested across tool
  shapes). Not re-derived.

## 2026-06-29 offload dir out-of-repo
- Full payloads go to `${XDG_CACHE_HOME:-$HOME/.cache}/dwarves-kit/offload/`, not the repo, so
  the offload never dirties the working tree or needs a gitignore entry. Pointer is an abs path.

## 2026-06-29 adding a hook = 4-file parity (CI caught it)
- Adding a hook is not just hooks.json. The meta test enforces hook-count + doc parity, so a new
  hook also needs: `settings.json` (installed hook list, count must equal hooks.json),
  `README.md` (the `<summary>Hooks (N)` count + a table row), `docs/architecture.md` (the
  SPEC-084 "Hook fallback layer" table row + class), and the hardcoded count assertion in
  `tests/test-hooks.sh`. Missed on first push (ran test-hooks.sh but not test-meta.sh locally);
  CI went red on parity. Fix: run BOTH `test-hooks.sh` AND `test-meta.sh` before pushing a hook.
- output-offload classed `advisory` (backstops context bloat; offloads + nudges, never blocks).

## 2026-06-29 matcher = all tools
- The PostToolUse entry uses a match-all matcher (the hook self-filters by size), so MCP tools
  and future tools are covered without editing hooks.json. Cheap because of the fast path.
