# Vendored

Source: github.com/YeonwooSung/my-claude-code-mods, `context-inspector`, commit `f7da140f3fc63aa5c083f75cd48700517e882c68` (Apache-2.0, `LICENSE` beside this file; the upstream repo ships no NOTICE file).

Read in full before vendoring (security review): it keeps a ledger in memory, reads the session messages and usage, and writes only the `/context-export` JSONL files. No network or process calls.

Kept: manifest and icon, `hooks/`, `tests/`, `tsconfig.json`, `README.md`. Dropped: `README_KR.md` and `.claude-plugin/types/` (written by Claude Code each time it loads the mod; gitignored here).
To update: re-read the upstream diff against this commit, copy the same files, then re-apply the patches below.

Modified files (Apache-2.0 section 4(b)): `hooks/register.tsx`, `hooks/core/report.ts`, `hooks/core/export.ts`, `tsconfig.json`, `tests/export.test.ts`, `tests/report.test.ts`, `README.md`. Added: `.gitignore`, this file. Upstream text, including its typography, is kept verbatim outside these patches.

Local patches:

1. `/context-export` writes a content hash for every non-file target (Bash command, Grep or WebSearch pattern, WebFetch URL, agent description) in place of the redacted, truncated text, so no command line or URL reaches disk. File paths stay. Equal targets still share a hash. Pinned by `tests/export.test.ts`.
2. The always-on `$.ui.status` row is gone (a status entry holds a row under the prompt), with `statusLine` in `report.ts`. The per-turn `$.session.usage()` read that only fed it is gone too. The pane and the one advice toast stay.
3. `tsconfig.json` extends the types Claude Code writes to `.claude-plugin/types/tsconfig.json`, the way `board-pane/tsconfig.json` does, and keeps `allowImportingTsExtensions` because the sources import `.ts` files.
4. `README.md` describes the hashed export and drops the status line text.
