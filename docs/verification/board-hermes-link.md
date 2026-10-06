# Verification -- board hermes link and the stale-skill check

`board hermes link` (`lib/sync/sweep/board-hermes`) installs the kit's Hermes skills into one agent profile with a digest stamp, records the link, and proves it with one real agent turn. `board hermes check` finds linked profiles whose skills are stale; `board sweep` records the check every tick and `board brief` turns a stale link into one decision line. `/kit:onboard` offers the link (step D3).

## Gate table

| Claim | Evidence |
|---|---|
| no Hermes home found is one skip line, exit 0, nothing written | green run, case none |
| homes need a config.yaml; several homes or profiles with no terminal is a usage error that lists the choices | green run, case detect |
| `--dry-run` writes nothing; no terminal and no `--yes` writes nothing | green run, case dry-run; negative control 4 |
| every kit skill is installed with a stamp (skills digest, kit version) and the link is recorded with the cluster's rail, hub, boards | green run, case install |
| a named profile installs under `profiles/<name>/skills`; an unknown one is refused | green run, case profile |
| re-running refreshes a locally edited skill and keeps one record per home and profile | green run, case re-run |
| `linked` needs the agent to run `board health run` and answer the nonce | green run, case verify; negative control 3 |
| `--sudo-user` reads and writes another account's home through sudo | green run, case sudo-user |
| a changed digest, a missing stamp, or a missing skill is stale; a fresh link is not | green run, case check; negative control 2 |
| the sweep records the check each tick | green run, case sweep; negative control 5 |
| a stale link is one decision line in its cluster's brief (the first cluster when none is named) | green run, case brief; negative control 1 |

## Green run

```
Command: bash tests/test-board-hermes.sh && bash tests/test-board-brief.sh && bash tests/test-board-health.sh && bash tests/test-board-sweep.sh
Exit: 0
Output:
  ok   board hermes link --help

board-hermes: 79 passed, 0 failed
board-brief: 87 passed, 0 failed
board-health: 96 passed, 0 failed
PASS=55 FAIL=0
Verdict: PASS
```

## Negative controls

Each mutation was applied on a committed tree and reverted with `git checkout --`.

```
Control 1: a stale link adds no decision (`if link.get("stale") and` became `if False and`)
Command: bash tests/test-board-hermes.sh
Exit: 1
Output:
  FAIL a stale link is a decision line for its cluster
  FAIL under the decision head
board-hermes: 75 passed, 4 failed
```

```
Control 2: a changed digest counts as fresh (`elif stamp.get("skills_digest") != digest:` became `elif False:`)
Command: bash tests/test-board-hermes.sh
Exit: 1
Output:
  FAIL a changed digest is stale (got 'false', want 'true')
  FAIL and says the kit's skills changed
```

```
Control 3: verify accepts an answer without the command run (`if not ran:` became `if False:`)
Command: bash tests/test-board-hermes.sh
Exit: 1
Output:
  FAIL an answer without the command run is not linked (got '0', want '1')
board-hermes: 77 passed, 2 failed
```

```
Control 4: link writes with no terminal and no --yes (the `if not interactive:` guard became `if False:`)
Command: bash tests/test-board-hermes.sh
Exit: 1
Output:
  FAIL no terminal and no --yes: exit 64 (got '1', want '64')
board-hermes: 77 passed, 2 failed
```

```
Control 5: the sweep does not record the check (the `board-hermes check --record` line commented out)
Command: bash tests/test-board-hermes.sh
Exit: 1
Output:
  FAIL the sweep recorded the link check (got '0', want '1')
board-hermes: 77 passed, 2 failed
```

## Reproduce

```
bash tests/test-board-hermes.sh
bash tests/test-board-brief.sh
```
