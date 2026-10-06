# Hermes layering: kit commands, thin skills, one agent

The kit holds every rule and every number. A Hermes agent only needs to know when to run which kit command. So the Hermes layer is a set of short SKILL.md files, and nothing else.

```
 operator's repo (config + poster)         dwarves-kit (the logic)               Hermes agent (the voice)
 ---------------------------------         -----------------------               ------------------------
 board.json  (flags as JSON)  ----read---> bin/board brief|health|sweep|status
 poster      (where it posts) <--payload-- lib/sync/sweep/board-brief
 incident hook (one JSON obj) ----feeds--> lib/sync/sweep/board-health
                                           bin/precedent find
                                                  ^
                                                  | the agent runs the command in a terminal turn
                                                  |
                                           adapters/hermes/skills/
                                             kit-board       when to run board brief|health|status|sweep
                                             kit-precedent   when to run precedent find
```

Two flows share one engine:

| Flow | Who runs the command | Result |
|---|---|---|
| Scheduled | a cron job calls `board brief run` with the operator's poster | one message per cluster per day, posted by the poster |
| On demand | the agent in a chat turn calls `board brief|health run --dry-run` through the skill | the agent explains the same numbers, posts nothing |

Rules for this layer:

- A skill holds no logic: no counting, no thresholds, no formatting. If a skill needs a number, the kit command prints it.
- A skill only runs read-only forms (`--dry-run`) of a command that can post.
- The operator's flags come from the kit config file (`--config`, `$DWARVES_BOARD_CONFIG`, or `~/.config/dwarves-kit/board.json`), so a skill never carries an operator's boards, channels, or paths.
- `board hermes link` installs the skills into one profile (the master or spokesperson), stamps the install with a digest of the skill files, records the link and the cluster's rail and boards in `~/.config/dwarves-kit/hermes-links.json`, and proves it with one agent turn (the agent must run `board health run --dry-run --force` and answer a nonce). `/kit:onboard` offers it. Re-running refreshes.
- `board sweep` runs `board hermes check --record` every tick. A linked profile whose stamp differs from the installed kit is stale, and `board brief` raises one decision line, `kit skills on <label> are stale: re-run board hermes link`.

```
 board hermes link ----> profile/skills/{kit-board,kit-precedent}  +  .dwarves-kit-skills.json (digest)
        |                                  ^
        +-> hermes-links.json              | compared every sweep tick
                                           |
 board sweep --> board hermes check --record --> health state --> board brief  "kit skills on X are stale"
```
