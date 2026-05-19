# ADR-0004: Adversarial spec validation as a separate command

## Status: accepted

## Context
Spec generation (/spec) and spec validation (/spec-validate) could be one command or two. ClaudeKit bundles validation into the plan phase. GSD keeps them separate.

## Decision
Two separate commands. /spec generates, /spec-validate attacks. User chooses whether to validate.

## Alternatives considered
- Auto-validate after spec generation: adds 5+ minutes to every spec. Not always wanted for quick features.
- Validation as a hook (PreToolUse on implementation): too late. Validation should happen before coding starts.

## Consequences
- User might skip validation. That's fine for small features, risky for large ones.
- /spec ends with a reminder to run /spec-validate.
- The 4-reviewer pattern (security, failure, assumptions, scope) is thorough but takes time.
