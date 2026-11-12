# project-merge-command: implementation notes

Spec: `docs/specs/SPEC-420-project-merge-command.md`. Only deltas from the spec.

## Build delta

- The first cut ran the command in the checkout and read the base with `origin/<default>`. Review found four ways around the trust rule: a tag named like the base, the HEAD fallback, the working-tree script, and an unreadable key reading as unset. The final shape reads fully qualified refs, has no HEAD fallback, runs the command in a clean detached checkout of the default branch, and returns exit 2 (refuse) for every unreadable case. R6 and R7 in the spec describe the final shape.
- `_gh_merge_retry` is untouched. A new `_merge_pr` wraps it, so the key-unset path is the same function with the same arguments.
- The head pin the plain path had (`--match-head-commit`) is rebuilt as a re-read of the PR head before the command starts (R3). stack-merge has no gated head and passes none, as before.
- mega-merge and stack-merge check MERGED after a zero exit (R5). wrap already did.
- stack-merge puts a retargeted child PR back on the parent branch when the project command refuses (R10).
- The value must be one simple command (R7). The toml reader strips `#` and keeps quotes literally, so a richer shell line would half-parse.
- Known cost: the clean checkout has no untracked local files, so a merge script that reads a `.env` or `node_modules` in the working tree will not find them.
- Not changed: `lib/wrap/report-lint.sh` keeps `gh pr merge` in its self-runnable pattern; a project command is not added to it.
- `docs/reference/FEATURES.md` is regenerated (spec-reference counts). It will conflict with any other branch that also adds a spec; regenerate with `feature-registry.sh check --fix`.

## Independent security review (SAFE WITH FIXES)

- A file that names `merge` in a form the reader cannot parse (dotted key, inline table, `[[merge]]`, other quoting, a repeated key, a `#` or backslash in the value) now exits 2 instead of reading as unset (R11). The shape check runs on the raw lines of the project, operator and kit-root files and on the slug path. The reader in `kit-config.sh` is untouched.
- The merged head is checked against the gated head after a zero exit in mega-merge (R5). wrap already compares the tree to the gated head; stack-merge has no gated head.
- `kit_merge_exec` no longer falls back to the live working tree; it returns 2 (R7).
- mega-merge and stack-merge take the default branch from `gh repo view` (R12). `wrap land` and `wrap merge` still use `_default_branch` (origin/HEAD, then main or master); the spec does not change them.
- Interrupt cleanup and the doc wording (denylist is not a boundary, the variables actually removed, no timeout, stale ref) are in R12 and the docs.
- Not changed: a failed fetch does not refuse. Making it refuse also refuses unset repos on a flaky network, and it still would not see a key added since the last good fetch; it is documented instead.
