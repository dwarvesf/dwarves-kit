---
name: kit-precedent
description: >
  Look up what already exists before proposing a new tool, script, skill, cron, or memory note,
  using the dwarves-kit `precedent` command. Triggers: "should we build X", "do we already have
  something for X", "is there a script that does X", "have we done this before", or any plan that
  would add a new tool. Read-only: it searches and quotes the hit, it builds nothing.
version: 0.1.0
metadata:
  hermes:
    tags: [kit, precedent, inventory, reuse]
    related_skills: [kit-board]
---

# kit-precedent

The kit owns the search. This skill only says when to run it.

```
 about to propose something new  -->  precedent find --surface inventory --quiet <words>
                                          |
                          hit  -->  quote the hit's one-line summary, propose enhancing that thing
                          none -->  say "no precedent found" and continue
```

## When to use

Before you propose a NEW tool, script, skill, cron job, or memory note. Also when asked whether something already exists.

## How to answer

1. Run `~/.claude/dwarves-kit/bin/precedent find --surface inventory --quiet <two to five words naming the idea>`.
2. If a hit comes back, quote its summary line as printed and say the work belongs in that thing, in its own repo.
3. If nothing comes back, say so in one line. Do not claim certainty beyond the search you ran.
4. For past decisions, specs, or retros, use `--surface records` instead of `inventory`.

## Never

- Never search other repos by hand to answer this. The command is the lookup.
- Never create the new thing in the same turn because the search came back empty. Report, then wait for the operator.
