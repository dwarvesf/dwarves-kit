# Gauntlet campaign scheduling (phase 2, NOT installed)

Phase 1 is ssh-invoked rounds via `run-remote.sh` with `runner_host` pointing at
an always-on host; no new infra. This directory holds the phase-2 skeleton for a
scheduled campaign (one scenario row per night) and is deliberately NOT
installed anywhere: install it only when ssh-invoked runs demonstrably hurt
(the minimum-infra gate question).

- `gauntlet-campaign`, the launcher (no `.sh` extension, `#!/bin/bash`,
  BTM-friendly): picks the next un-run row from the campaign worklist, invokes
  `run-remote.sh`, appends to ROUNDS.md.
- `mini.gauntlet-campaign.plist`, LaunchAgent skeleton, `ProgramArguments[0]`
  is the launcher's own absolute path per the plist authoring rules.

Before any install: the launchd-context traps apply (verify egress + secret
cache IN launchd context, not over ssh; a cache warmed over ssh leaves a
.nostore marker that blocks the launchd retry).
