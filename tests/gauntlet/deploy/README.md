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

- `gauntlet-ab <ref-A> <ref-B> <persona> <row> <N>` (SPEC-241), an on-demand
  driver, never scheduled: runs one card against two committed artifact
  variants (rule-7 `git archive` tarballs through the runner's
  `GAUNTLET_SRC_TAR` slot), N rounds each, scored by the row's own checker, and
  writes `AB-ROUNDS.md` with a `[[AB-VERDICT ...]]` marker. A winner needs
  N >= 2 and a sweep; thinner leads report `AB-WEAK`/`AB-TIE`. Use it to pick
  between two contested revisions of an artifact; it does not revise (that is
  the gauntlet loop, run after the pick).
