# operator-defaults-out: implementation notes

No spec: the brief was the contract (the kit ships neutral defaults, the operator's values live in `~/.config/dwarves-kit/kit.toml`). Only decisions and deltas.

## Decisions

- **Reuse, no new mechanism.** Every new key is read with `kit_config_get_root` (operator file, then kit root, never a project `.kit.toml`). A key that names a host to sign requests for or a command to run must not ride in an untrusted PR. Shell callers use the function directly. The two Python readers (`session-report`, `stats`) shell out to `kit-config.sh` with the same one-liner `hooks/harvest_sweep.py` already uses.
- **Python-read keys are not in the registry's `## Root-only keys` table.** `tests/test-config-registry.sh` AC10 pins that table to the literal `kit_config_get_root <key>` call sites, and the Python helpers pass the key as an argument. `harvest.sources` already sits in the same gap. The fence is real in behavior (the helpers call `kit_config_get_root`); only `bin/config explain` would not label these keys root-only. Each registry row says "Read through `kit_config_get_root`".
- **Command values cannot contain `#` or a single quote.** `kit-config.sh` strips from the first `#` and unquotes only double quotes. A command that needs either goes in a script the key points at.
- **Secrets as commands, not refs.** `tool.toml` listed two `op://` refs as metadata that nothing read. The kit now holds no vault reference: `tool.toml` names the env vars, and `[session_report] hmac_key_cmd` / `hb_token_cmd` carry a command whose stdout is the secret (the shape `[decide] jev_token_cmd` already uses). The env var wins; the command is the fallback. Argv is split like shlex and never run through a shell.
- **`host_id` defaults to the short hostname**, not empty. A signed request with a wrong id is a silent 401 at the worker, and an empty id would make `--dry-run` useless. The worker registers the id it expects, so an operator who reports to a worker sets the key.
- **`url` has no default.** Empty exits 2 with one line naming the three places to set it (`--url`, `$SESSION_REPORT_URL`, `[session_report] url`). `--dry-run` is offline and does not need it.
- **`stats.home_repo` empty omits the `Home:` line** of the staged block (`staging-format.py` already treats an empty home that way). The operator picks the board on promote, which is what the `home` field's comment says it is for.
- **`sync.notion_title` defaults to `Backlog`**, matching the Reminders list default. It only matters when `board sync` creates a database; binding an existing one by id never reads it.
- **Forge API endpoint stays a product default.** `bin/activate` and `bin/release` point at the forge API, the product's own license and update service, not an operator's host. A standalone copy of the kit must be able to activate with no config, so the default stays. `bin/activate` already honored `FORGE_API`; `bin/release` now honors it too, so moving off the staging host is an env change in both. The host name is not in the deny list.
- **Registry precedence.** `--registry` flag, then `KIT_BOARDS_REGISTRY`, then `<repo-root>/_meta/boards.txt`, in every reader. `reflect/propose.py` keeps `LEARN_PROPOSE_COCKPIT` above all three because its tests and callers already use it.

## boundary-lint deny list

- The scan walks the working tree, not `git ls-files`, so an untracked scratch file in the tree can fail it locally. A scan that cannot run (no python3, a crash) fails the lint; a first version printed PASS in that case (found in review).
- Scope is every text file under the tree except markdown, `docs/`, `.git`, `.claude`, `node_modules`, `.venv`. The four PATH-check module exclusions do not apply: the point is that no module is exempt.
- A comment line (first non-blank `#` or `//`) is provenance prose and is skipped. A Python docstring is skipped, found with `ast`. A line carrying `boundary-ok: <reason>` is skipped. No live line needed the marker; the lint ships it for the next legitimate case.
- The pattern lives in the lint split into halves, so the lint is not its own hit. The test builds the tokens the same way.
- The scan runs on the filesystem, not `git ls-files`, because the negative-control fixtures are plain directories.
- `han.ws` (the proof asset domain) is not in the deny list; the brief named four tokens. It was replaced in `tests/test-proof-visual-gate.sh` anyway. The operator's display name (`actor=Han Ngo`) in the dashboard render and the review-yield fixtures became `Dev Tester`.

## Fixtures made neutral

- `lib/bench/examples/renders/dashboard-2026-07-25.html`, `allocation-report-2026-W30.md`, `run-viewer-2026-07-25.html`, `session-board-tool.html`: project slugs, branch names (full and the 26-char truncated forms the dashboard prints), run ids from other projects, and domain words (`payout`, `ICY`) replaced with `acme-app`, `demo-*`, `sample-*`. Amounts and token counts were not changed: with the names gone they identify nothing, and editing them would break the sums and shares the render derives. Free-text spec titles in the dashboard may still carry domain vocabulary that is not a slug or a name; no rewrite of that prose was attempted.
- `lib/session/observe/docs/proof-of-done.md` and `lib/stats/docs/verification/memory-lens.md`: the real-corpus tables now use neutral slugs, padded to the original column widths.
- Tests: `acme`, `acme-app`, `acme-dev`, `dev@users.noreply.github.com`, `op://Vault/...`, `proof.example.test`.
- `tests/test-board.sh` NC-e compared the render against a real sibling cockpit named in the test. It now reads `$KIT_SIBLING_ROOT/$KIT_COCKPIT_REPO`; with `KIT_COCKPIT_REPO` unset it skips with a message naming both variables. An operator who ran that check locally sets `KIT_COCKPIT_REPO`.
- `lib/stats/tool.toml` `consumers` is now empty. Nothing in the kit reads it.
- Not touched: `docs/` and other markdown. They carry real provenance prose ("ported from ..."), and the lint excludes them by design. Git history is untouched.

## Open questions

- None that block. The Root-only table gap above is the one inconsistency worth a follow-up in `test-config-registry.sh` (let AC10 scan Python call sites), but it is a lint design change, not part of this move.
