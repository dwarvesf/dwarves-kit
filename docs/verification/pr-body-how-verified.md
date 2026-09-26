# Proof of done: PR bodies always carry a fenced "How I verified it"

2026-09-27. Lane: normal. Files: `commands/ship.md`, `commands/wrap.md`, `tests/test-ship-pr-body-verified.sh`, this file.

## Problem

`dwarvesf/foundation-apps`' PR evidence check (`tieubao/pr-evidence-check`, a reusable
workflow) converted PRs #153, #164, #169 and #175 to draft on 2026-09-26. Its `VERIFIED`
rule requires an exact `## How I verified it` heading whose body has a fenced ``` code
block, a `$` line, or a known tool name (`pnpm|npm|bash|node|go|cargo|make|curl|wrangler`).
Confirmed against the four PRs' first failing run (`gh run view <id> --log-failed`,
`RESULT_JSON`):

| PR | Heading used | Why VERIFIED failed |
|---|---|---|
| 153 | `## Verify` | wrong heading; check found none |
| 164 | `## How I verified it` | bullet-list prose, no fence/`$`/tool-name at line start |
| 169 | `## Test plan` | wrong heading; check found none |
| 175 | `## How I verified it` | 4-space indented block (not fenced) with `rg`, which is not in the known-tool list; this is the repo's OWN `.github/PULL_REQUEST_TEMPLATE.md` example verbatim |

Root cause: nothing in dwarves-kit (`rg -l "How I verified it"` across the whole repo,
before this change: no hits) named the required heading or the fenced-block convention.
Every PR body above was hand-composed per session, each one either guessing a heading or
copying the target repo's template example literally, including its indented (non-fenced)
code block.

## Fix

`commands/ship.md` step 8 (the PR-description-generation step used by `/kit:ship`, which
`/kit:execute` step 3 also calls): prefer the target repo's own `.github/PULL_REQUEST_TEMPLATE.md`
headings when one exists; the fallback template now heads the section `## How I verified it`;
and a new rule pins the format regardless of which heading is in play: a fenced ``` code
block, one command per line prefixed with `$ `, ending in the result. It calls out explicitly
that an indented block does not count even when a repo's own template shows one as its example
(the exact trap PR #175 fell into).

`commands/wrap.md` step 10's build/finish worker instruction (the commit that `--fill-first`
turns into the PR body) now cites the same rule and requires the same heading in the commit.

## Green run

```
Command: bash tests/test-ship-pr-body-verified.sh
Exit: 0
Output: 7/7 passed
Verdict: PASS
```

## Negative control

```
Command: git stash && bash tests/test-ship-pr-body-verified.sh; echo "exit=$?"; git stash pop
Before restore (mutation = the fix reverted via git stash): 0/7 passed, exit=1 -- RED
After restore (git stash pop): 7/7 passed -- GREEN
Verdict: PASS
```

## Not proven

- Whether the actual sessions that opened PRs #153/#164/#169/#175 route through
  `commands/ship.md` step 8 verbatim, or hand-compose the body via `gh pr create --body`
  reading the target repo's template directly, was not traced session-by-session; the fix
  covers both paths (the kit's own template, and the general rule that applies "whatever it
  is headed").
- No live foundation-apps PR was reopened or re-run against the real `pr-evidence-check`
  workflow; this proof only covers the kit-side producer text, not an end-to-end rerun.
