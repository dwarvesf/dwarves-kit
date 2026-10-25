# QUICKSTART

Install the kit, then run one full lifecycle. No clone and no installer.

1. Install the plugin in a Claude Code session:
   ```
   /plugin marketplace add dwarvesf/dwarves-kit
   /plugin install kit@dwarves-marketplace
   ```
2. Open your repo and run `/kit:onboard`. It adopts the repo and picks modules, previewing every write; a decline changes nothing.
   The default set is small on purpose: the spine's safety hooks plus `board`. Everything else (session capture, advisor hints, cosmetic hooks, money_gate, prose_rag) is opt-in; onboard lists the choices, and one table, `lib/config/modules.tsv`, defines them. The plugin already registers every hook, so on a plugin machine adopt wires no extra per-repo hooks, and a later `bash install.sh` refuses to add a second set (`--force-both` overrides, and every hook then fires twice).
   Adopt also turns two quality gates on for the repo by seeding `[gate] proof_of_done = true` and `lane_gates = true` in a fresh `.kit.toml` (a raw `install.sh` keeps all gates off). To turn either off, set it to `false` in `.kit.toml` and commit. An existing `.kit.toml` is never changed. Adopt and `install.sh` also run the one-time move of old kit logs into the durable ledger root; hooks never do.
3. Run `/kit:start` at the top of every session. It reads project state and names the single next command. Onboarding never finishes; `/kit:start` is the onboarding.
4. Describe a tiny change and follow the tiny lane through to `/kit:ship`.

That is the whole loop. The full command reference lives in [`MANUAL.md`](MANUAL.md); the operate-contract lives in [`../AGENTS.md`](../AGENTS.md).
