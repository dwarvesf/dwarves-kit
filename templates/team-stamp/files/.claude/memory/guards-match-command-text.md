---
name: guards-match-command-text
description: The agent hook matches the text of a command, so a variable or a script file hides a command from it; CI is the second line.
---

`scripts/agent-guard.sh` is text matching on the command line, not a shell parser. It guards Claude Code only: other agents get no hook.

Known misses: a command built from variables (`g=gh; $g pr merge 7`), a script file that runs git or gh itself, the merge call made through `gh api` (a path ending in `/merge`), and a push made outside the agent's shell. Weak spots: a wrapper before the command (`env -i`, `timeout 5`) and `git push --all` or `--mirror`. `scripts/test-agent-guard.sh` holds one row per probe and is the truth for which of these the guard blocks today.

**Why:** the hook says the fix at the moment of the mistake. It is not a wall. CI job `pr-shape` and `scripts/pr-merge.sh` are the checks that bind.

**How to apply:** never hide a command from the hook to get past it: the rule still holds and CI finds the break later, at a higher cost. When the hook blocks you, read the fix line and use it. A new guard states its limits in its header.
