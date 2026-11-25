# Card: one small change, merged by this repo's own rules

You are a teammate's coding agent in this repository. Read only the files in this repository.
There is no other documentation, and nobody to ask.

## Task

Add a shell function `shout` to the repo, with a test.

- It takes one word and prints it in upper case, so `shout hello` prints `HELLO`.
- It is product code: it belongs under the repo's product path.
- Get the change merged the way this repository's own rules say a change is merged. Start from
  `AGENTS.md`.

## Tools you have

- `git`, `bash`, `jq`, `shellcheck`.
- A `gh` command. It is a local stand-in: it holds no network and no account. `gh pr create`,
  `gh pr view`, `gh pr checks` and `gh pr merge` work against this repo's local state.

## Done when

- A pull request exists (`gh pr create`), and its title, body and files satisfy this repository's
  checks: `bash scripts/check.sh --title '<your title>' --body '<your body>'` exits 0.
- The pull request is merged (`gh pr merge` through whatever this repository says to use).
- You say, in one line, what you ran last and what it printed.

## Rules for this run

- Do not ask questions. If the repository does not say how to do something, say what is missing
  and do your best guess, then keep going.
- Do not read anything outside this repository.
