# Gauntlet run: kit USER persona, row J1, omp + NeuralWatt probe

Probe-model sensitivity companion to `../2026-08-31-user-J1/` (the claude/sonnet round, same card, same day, same commit-era surface). The probe harness AND model both differ; the artifact and outcome contract are identical.

## Inputs (delta from the sonnet run)

| Input | Value |
|---|---|
| preset | onboarding (persona A, kit USER) |
| Probe harness | omp (`@oh-my-pi/pi-coding-agent` + bun, npm-installed inside the room) |
| Probe model | neuralwatt/deepseek-v4-flash (openai-completions, `api.neuralwatt.com/v1`) |
| Signal-validity caveat | flash tier is BELOW the mid-tier guidance; recorded per the frontier/off-tier rule. Observed workaround-not-diagnose behavior (see findings), yet friction it hit reproduces the sonnet round, so the shared findings are artifact signal, not probe noise |
| Everything else | as the sonnet run (card J1, doorway checker, container clean room, local runner) |

## Rounds

| Round | Tier 1 | Checker | K | Max severity | Tokens | Wall clock | Turns |
|---|---|---|---|---|---|---|---|
| 1 | GREEN (from the sonnet run's same-day pass) | GREEN | 4 | MAJOR | 3.09M (152.6k in / 12.9k out / 2.93M cache-read), NW flat-rate | 2m59s probe (+ ~1 min omp/bun install) | 46 |

`[[QL-VERDICT round=1 clean=false findings=4]]`

## Verdict: REVISE (same worklist as the sonnet round, evidence strengthened)

Checker GREEN unaided under a second harness+model. Cross-probe reproduction:

| Sonnet finding | This round |
|---|---|
| MAJOR hook-activation gap (headless adopters) | REPRODUCED, stronger: probe could not run `install.sh` (no jq), hand-mirrored the file layout, missed `docs/verification/task-types.md`, broke `proof-gate.sh` until a second copy; hooks never wired at all |
| MINOR no-root jq recipe | subsumed into the MAJOR (jq absence blocks the installer entirely for ANY headless user) |
| MINOR WORKFLOW.md two-hop pointer chase | REPRODUCED verbatim |
| MINOR gate-ledger syntax example-only | REPRODUCED verbatim (2 failed `record` grammar attempts) |
| (new) MINOR lane-classify subcommand guessed | weak signal, probe guessed before reading usage; noted, not added to the worklist |

Revision worklist unchanged: ID-490. This round's evidence upgrades its jq/installer item from "document the no-root path" to "the installer's jq dependency blocks headless adoption outright".

## Integrity + evidence

No coaching (only harness-internal nudges). One probe command catted its own launch script + live transcript head; nothing scoring-relevant revealed, no answer-key material exists in the room (mechanical grep zero on gauntlet paths). 5/47 bash calls errored (3 = doc-gap signal, 2 self-inflicted). Scrub: NW key confirmed absent from every persisted file (config holding it lived only inside the destroyed container). `round-1/room/` holds transcript (omp v3 session format) + logs; fixture repo/tarball untracked per the nested-repo rule, evidence exported to `round-1/submission/`.
