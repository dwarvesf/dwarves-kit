# Round 1 findings (K=4, max severity MAJOR)

Each finding judges the ARTIFACT (the kit's user-facing onboarding surface), never the probe. Evidence quotes are from `../room/transcript.jsonl`.

## MAJOR-1: hook activation gap is undocumented for the single-session agent shape

Hooks and gate enforcement activate only in a NEW Claude Code session; `install.sh` itself prints "Start a new Claude Code session to activate hooks." A headless `claude -p` consumer (exactly this gauntlet's shape, and any CI/agent adopter) never restarts, so every gate-ledger call the probe made was voluntary, inferred from docs, with no live hook enforcing anything. No user-facing doc flags this: an agent adopter can believe the gates are armed when they are not.

Suggested revision: one paragraph in README/onboard docs naming the restart requirement and the headless implication.

## MINOR-2: jq prerequisite has no documented no-root path

Probe burned ~10 tool calls (turns ~11-20): `jq: command not found`, `apt-get` permission denied, `sudo: command not found`, `touch /usr/local/bin/... Permission denied`, PATH probing, before fetching a static binary into `~/bin`. install.sh's guard hints "brew/apt, or a static binary on PATH" but no doc shows the no-root recipe.

Suggested revision: one line in the install docs: static-binary-to-`~/bin` as the no-root fallback.

## MINOR-3: WORKFLOW.md is a two-hop pointer chase

Adopted repo's WORKFLOW.md points to the kit's top-level WORKFLOW.md, itself a 19-line pointer to `docs/WORKFLOW.md` where the real lane matrix lives. The probe's first grep on the top-level file returned nothing; three more reads were needed (turns ~27-41 were the second-biggest sink).

Suggested revision: the adopted-repo pointer should name the terminal file directly.

## MINOR-4: gate-ledger CLI syntax is example-only

`gate-ledger.sh start <rid> <lane> ...` positional args are spelled out nowhere the probe read; it inferred usage from one example line in AGENTS.md and guessed `type=spec-feature` for a doc-only change with no enumerated alternatives visible.

Suggested revision: a usage block (or `--help`) reachable from the docs an adopter actually reads.
