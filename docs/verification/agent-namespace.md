# Proof of done: kit-internal agent dispatch references are `kit:`-qualified

2026-09-19. Acceptance: every dispatchable agent-name reference in `commands/`, `skills/`,
`agents/`, and `MANUAL.md` resolves through the plugin namespace (`kit:<agent>`), so plugin
installs never fall through to stale `~/.claude/agents/` copies; legitimately bare contexts
(file paths, `name:`/`generated-by:` frontmatter, the `advisor` gate-ledger phase, the
kit.toml module tuple, non-agent English like "product advisor") are untouched and
whitelisted by the pin. Lane: normal. Files: 18 commands, 15 agents, 1 skill, `install.sh`,
`tests/test-meta.sh`, `docs/FEATURES.md` (regenerated).

## Why this is needed

Claude Code registers plugin agents only as `plugin:name` (`kit:advisor`, never bare
`advisor`). A bare `subagent_type` fails or falls through to whatever `~/.claude/agents/`
copy happens to exist, which was exactly the stale-snapshot class ID-905 reports (29 of 31
agents shadowed by pre-plugin copies carrying spec/ADR id tags the kit versions had since
stripped). The kit's own commands already spoke the `kit:` namespace for commands
(`/kit:verify`, `/kit:review-team`); agent references were the remaining half of the contract.

`install.sh` full-install (`KIT_FORCE_FULL=1`) still copies agents to `~/.claude/agents/`
bare, deliberately: those copies serve non-kit callers (Codex/Gemini agents, external
tools, a human's Task call), and kit-internal cross-dispatch in that mode already required
the plugin (`/kit:` command refs have never resolved there). The plugin-compat branch
continues to retire stale bare copies; `tests/test-install-compat.sh` covers it.

## Verification

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-meta.sh` | 0 | PASS, 854/854 incl. the new `Plugin-qualified agent dispatch` pin |
| `bash tests/test-hooks.sh` | 0 | PASS, 498/498 |
| `bash tests/test-install-compat.sh` | 0 | PASS, stale bare-agent retirement + full-install copy path unchanged |
| `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | 0 | PASS, registry regenerated, freshness pin green |
| bare-name scan over `commands/ skills/ agents/ MANUAL.md` (worktree) | 0 hits | PASS, zero non-whitelisted bare references |

### Negative control

| Command | Exit | Verdict |
|---|---|---|
| same bare-name scan against `origin/master` tree (`git archive` to tmpdir) | 248 hits | RED as designed, the pin fails on the pre-change tree |

Reproduce: the scan is embedded in `tests/test-meta.sh` ("Plugin-qualified agent dispatch
(ID-905)"); run it against any checkout, master reports ~248 bare hits, this branch zero.

## Not attempted

- Live Claude Code dispatch of a `kit:<agent>` from a real session (needs the harness;
  covered by the roster contract + upstream issue anthropics/claude-code#33689 semantics).
- Rewriting `kit:` prefixes for `KIT_FORCE_FULL` installs, that mode's `/kit:` command
  references were already non-resolving; plugin is the supported dispatch path.
