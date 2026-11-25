---
name: guards-match-command-text
description: The agent hook matches the text of a command, so a variable or a script file hides a command from it; CI is the second line.
---

`scripts/agent-guard.sh` is text matching on the command line, not a shell parser. It guards Claude Code only: other agents get no hook.

Known misses: a command built from variables, functions, aliases or command substitution; a script, make target or tool that runs git or gh itself; a push set up through a git alias or config; a merge from the GitHub site or any client other than gh; a `gh api` merge that does not spell the method PUT as a word; a commit made by an editor or a GUI. `scripts/test-agent-guard.sh` holds one row per probe and shows what the guard blocks today.

**Why:** the hook says the fix at the moment of the mistake. It is not a wall. CI job `pr-shape` and `scripts/pr-merge.sh` are the checks that bind.

**How to apply:** never hide a command from the hook to get past it: the rule still holds and CI finds the break later, at a higher cost. When the hook blocks you, read the fix line and use it. A new guard states its limits in its header.
