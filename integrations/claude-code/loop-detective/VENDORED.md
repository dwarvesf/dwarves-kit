# Vendored

Source: github.com/YeonwooSung/my-claude-code-mods, `loop-detective`, commit `f7da140f3fc63aa5c083f75cd48700517e882c68` (Apache-2.0, `LICENSE` beside this file; the upstream repo ships no NOTICE file).

Read in full before vendoring (security review): it keeps state in memory only, makes no network, process or file-write calls, and only observes `tool.call` results.

Kept: manifest and icon, `hooks/`, `tests/`, `tsconfig.json`, `README.md`. Dropped: `README_KR.md` and `.claude-plugin/types/` (written by Claude Code each time it loads the mod; gitignored here).
To update: re-read the upstream diff against this commit, copy the same files, then re-apply the patches below.

Modified files (Apache-2.0 section 4(b)): `hooks/register.tsx`, `hooks/core/fingerprint.ts`, `hooks/core/detector.ts`, `hooks/core/report.ts`, `tsconfig.json`, `tests/adapter.test.ts`, `tests/fingerprint.test.ts`, `tests/report.test.ts`, `README.md`. Added: `.gitignore`, this file. Upstream text, including its typography, is kept verbatim outside these patches.

Local patches:

1. The `Failure:` excerpt is gone. It was raw tool output that can run before the secrets-veil mod masks it. `classifyResult` no longer returns `excerpt`, `Case` no longer stores one, and `/loop-report` and the pane print no `Failure:` line. The failure still feeds the repeat fingerprint (a hash) and nothing else. Pinned by the report, fingerprint and adapter tests, which assert the line and the text are absent.
2. The always-on `$.ui.status` row is gone (a status entry holds a row under the prompt), with `statusLine` in `report.ts`. The case toast and the pane stay. The adapter test counts `ui.status` calls and expects none.
3. The `tool.call` hook ends in `.catch(($, e, next) => next(e))`, matching context-inspector. The catch handler's `next` replays the settled answer and runs nothing beneath again, so the tool cannot run twice.
4. `tsconfig.json` extends the types Claude Code writes to `.claude-plugin/types/tsconfig.json`, the way `board-pane/tsconfig.json` does, and keeps `allowImportingTsExtensions` because the sources import `.ts` files.
5. `README.md` drops the status line and `Failure:` example text that patches 1 and 2 removed.
