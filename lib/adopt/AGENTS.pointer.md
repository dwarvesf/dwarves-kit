<!-- kit:agents-pointer v1 -->
# AGENTS.md

This repo uses dwarves-kit. Full contract, advisory (nothing forces you to read it, read it before your first task): ~/.claude/dwarves-kit/AGENTS.md or https://github.com/dwarvesf/dwarves-kit/blob/master/AGENTS.md

Rules that hold without it:
1. Size the work: tiny, normal or full. Full when it touches auth, authz, hooks, data model, data loss, audit or security, an external provider, an API contract, or a migration.
2. A change to behavior or state needs a recorded proof of done under docs/verification/ before you push.
3. Work on a branch and open a PR. Never push to main.
4. Stop and ask a human before: an architecture or interface change, which file is canonical, weakening a test or guardrail, a lighter lane, secrets or access.

No kit on this machine: the rules still apply, nothing enforces them. Ask a human to install it: clone https://github.com/dwarvesf/dwarves-kit, review install.sh, then run it (never pipe it to a shell)
