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
- An operator installs the skills by copying `adapters/hermes/skills/<name>/` into the agent's skills directory. The kit does not ship an installer.
