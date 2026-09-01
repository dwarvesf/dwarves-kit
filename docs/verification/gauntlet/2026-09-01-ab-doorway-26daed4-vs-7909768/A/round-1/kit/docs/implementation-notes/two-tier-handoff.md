# Impl notes: two-tier feed-forward handoff (SG-02)

Delta from SPEC-087 Mechanism B. Only off-spec calls live here.

## 2026-06-29 hot/warm split: HANDOFF.md full-injected + capped, DECISIONS.md pointer-only
- Decision: the orchestrator injects `HANDOFF.md` in full (hot, capped to `HANDOFF_MAX_LINES`,
  default 80) and injects only a POINTER to `DECISIONS.md` (warm: path + line count), never its
  body. The session reads the ledger on demand.
- Why: injecting the whole append-only ledger every transition recreates the marathon the spec
  is trying to kill. The cap bounds a runaway hot handoff too.
- Roles: the sub-goal SESSION writes both files (overwrite HANDOFF, append DECISIONS); the
  orchestrator only injects. Matches SPEC-087's "session writes HANDOFF" grounded-completion.

## 2026-06-29 prompt injected via stdin (temp file), not an argv arg
- Decision: build the prompt into a temp file and pipe it (`claude -p ... < "$tmp"`), instead of
  passing it as the last positional arg. (pi-swarm borrow; verified `claude -p` reads the prompt
  from stdin.)
- Why: removes the backtick/`${}`/secret-guard bug class when the prompt body contains shell
  metachars, and dodges ARG_MAX on a large injected handoff.
- Consequence (test harness): the existing mocks read the prompt as `prompt="${!#}"` (last arg).
  Switched every mock to `prompt=$(cat)`. This is the only reason the prior tests' mock bodies
  changed; their assertions are unchanged.

## 2026-06-29 cap is a head-truncate + notice, not a hard fail
- Decision: if HANDOFF.md exceeds the cap, inject the first N lines + a `[... truncated, read
  the file]` notice rather than erroring. Keeps the loop moving; the file path is still pointed at.
