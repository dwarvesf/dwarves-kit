# HOT HANDOFF (overwritten each sub-goal transition)

Next sub-goal: SG-04 distilled subagent returns.
First action: add the return-contract block to `agents/worker.md` and `agents/reviewer.md`.

Read-pointers (verified this run):
- `lib/queue/orchestrate.sh:56` -- `_build_prompt`, where injection happens
- `docs/specs/SPEC-087-context-hygiene.md:104` -- Mechanism C (the contract to implement)
- `agents/worker.md:1` -- the agent def to extend

Dead-end hit this run: do NOT try to cap returns in `/kit:execute` prose; the cap belongs in
the agent def so every dispatcher inherits it. See DECISIONS.md.
