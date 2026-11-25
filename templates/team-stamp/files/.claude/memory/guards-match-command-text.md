---
name: guards-match-command-text
description: The agent hook matches the text of a command, so a variable or a script file hides a command from it; CI is the second line.
---

`scripts/agent-guard.sh` is text matching on the command line, not a shell parser. It guards Claude Code only, and without `jq` or `awk` it is off.

Known misses: a command built from variables, functions, aliases or command substitution; a script, make target or tool that runs git or gh itself; a push set up through a git alias, `git -c alias.x=push`, or config; a merge from the GitHub site or any client other than gh; a `gh api` merge that does not spell PUT as a word, or a graphql call other than a literal `mergePullRequest`; a commit made by an editor or a GUI. `scripts/test-agent-guard.sh` holds one row per probe.

**Why:** the hook says the fix at the moment of the mistake. It is not a wall. CI job `pr-shape` and `scripts/pr-merge.sh` bind.

**How to apply:** never hide a command from the hook to get past it. When it blocks you, read the fix line and use it.
