# ADRs , cc-self-improve

Why the load-bearing choices were made. Each ADR is a past decision where alternatives were weighed
and one was picked for a reason. The behaviour contract lives in `../specs/SPEC-103-...`; these are
the WHY behind it.

| ADR | Decision | One-line why |
|---|---|---|
| [0001](./0001-model-has-no-write.md) | the model has no filesystem write (`--allowedTools ""`) | a prompt-injected transcript can't escalate to an arbitrary write; staging-by-path becomes structural |
| [0002](./0002-propose-and-stage.md) | propose-and-stage, not auto-apply | cockpit blast radius (NDA/SDD/ops); the human `/skill-review` is the only normal writer of `skills/` |
| [0003](./0003-per-session-trigger.md) | per-session trigger reusing cc-harvest's events | cc-harvest already ships the memory half; per-turn would duplicate the most expensive piece |
| [0004](./0004-mkdir-atomic-lock.md) | atomic `mkdir` lock, not `flock` | macOS has no `flock(1)`; this ADR retires the stale `flock` text in the spec |
| [0005](./0005-curator-never-deletes.md) | curator never deletes (`git mv` + restore) | an LLM-proposed deletion would be unrecoverable; archive is the max action |
| [0006](./0006-reviewer-test-seam.md) | `SKILL_CURATOR_REVIEWER_CMD` / `SKILL_CURATOR_CURATOR_CMD` test seam | test every parse/stage/archive path with no live model or quota spend |
| [0007](./0007-wrapper-side-secret-drop.md) | wrapper-side secret-drop | makes "no draft carries a secret" a hard, testable guarantee, not a prompt hope |
| [0008](./0008-bash-for-everything.md) | bash for everything (no Go/Python) | the surface is shell + `claude -p` + `jq` + `git mv`; no daemon, no perf path |
| [0009](./0009-two-layer-parse-exit-0.md) | two-layer JSON parse + always-exit-0 | extract cost + answer from the envelope; a self-improvement run must never break a session |
