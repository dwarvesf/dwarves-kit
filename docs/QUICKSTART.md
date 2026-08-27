# QUICKSTART

Install the kit, then run one full lifecycle. No clone, no installer, no choices.

1. Install the plugin in a Claude Code session:
   ```
   /plugin marketplace add dwarvesf/dwarves-kit
   /plugin install kit@dwarves-marketplace
   ```
2. Open your repo and run `/kit:onboard`. It adopts the repo and picks modules, previewing every write; a decline changes nothing.
3. Run `/kit:start` at the top of every session. It reads project state and names the single next command. Onboarding never finishes; `/kit:start` is the onboarding.
4. Describe a tiny change and follow the tiny lane through to `/kit:ship`.

That is the whole loop. The full command reference lives in [`../MANUAL.md`](../MANUAL.md); the operate-contract lives in [`../AGENTS.md`](../AGENTS.md).
