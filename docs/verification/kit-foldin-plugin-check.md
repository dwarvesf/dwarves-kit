# Proof of done: kit-foldin SG-05, plugin-check

**Acceptance criteria** (from `ops-toolkit/_meta/megagoals/kit-foldin/goals/05-plugin-check.md`):

1. `ops-toolkit/tools/cc-plugin-check/` moved to `dwarves-kit/tools/plugin-check/` (drop `cc-`).
2. Any hardcoded plugin-dir path becomes an arg/env default, opt-in (no ops-toolkit-layout assumption).
3. A fixture plugin dir under `tests/fixtures/` with a fresh variant and a stale variant.
4. Run-table: fresh fixture -> verdict `current`; stale fixture -> verdict `OUTDATED` (the named NC).
5. Done gate: `grep -rn 'workspace/<owner>' tools/plugin-check/` empty.

## Implementation

Straight port, no new logic. `bin/cc-plugin-check` -> `bin/plugin-check`; every in-script
self-reference (`die()` prefix, usage banner, table header, `--help` text) renamed
`cc-plugin-check` -> `plugin-check`. Verdict logic, comparison rules, table format, and CLI
surface (`status`, `update [name] [--apply]`) are byte-identical to the source tool.

The plugin-state directory was already opt-in before the move: `PLUGINS_DIR="${CC_PLUGINS_DIR:-$HOME/.claude/plugins}"`
(`bin/plugin-check:24`) defaults to the standard per-user Claude Code plugin directory, not
an ops-toolkit path, so there was no hardcoded ops-toolkit path in the executable to
replace. The two doc-only mentions of `~/workspace/<owner>/dwarves-kit` (in the ported
`docs/specs/SPEC-105-cc-plugin-check.md` and `docs/implementation-notes/cc-plugin-check.md`,
describing Han's own `directory`-marketplace dev checkout as a worked example) were
generalized to "the local dwarves-kit checkout" so the grep-clean gate holds across the
whole moved subtree, docs included.

## Confirmation run-table

| # | Command | Fixture | Expected verdict | Result |
|---|---|---|---|---|
| 1 | `bin/plugin-check status` (ponytail row) | `tests/fixtures/*` , ponytail's installed sha rewritten in-test to match its marketplace clone HEAD (a real git repo, not mocked) | `current` | PASS , `tests/smoke.sh` [3]: "ponytail current (sha proven)" |
| 2 | `bin/plugin-check status` (superpowers row) | `tests/fixtures/plugin-catalog-cache.json` pins `superpowers`'s catalog `source_sha` to a value that differs from the fixture's `installed_plugins.json` `gitCommitSha` | `OUTDATED` (the named NC: a stale plugin is flagged, not silently passed as current) | PASS , `tests/smoke.sh` [4] (AC3 negative control): "OUTDATED row present for pinned-old superpowers" |

Both rows come from the same fixture set and the same `status` invocation (one `claude`
roster + one catalog + one set of marketplace clones), so the fresh and stale verdicts are
proven side-by-side in a single run, not two separately-staged fixtures.

Full suite (27 assertions covering every verdict path: current/OUTDATED/unknown, offline
degrade, `--no-refresh`, dry-run vs `--apply`, injection-defense, absent-CLI, torn JSON):

```
$ cd tools/plugin-check && bash tests/smoke.sh
[setup] ponytail HEAD=3ae2704c1  workdir=/var/folders/.../plugin-check-smoke.XXXXXX
[1] status: all 6 fixture plugins each appear with a STATUS (AC1)
  ok: 6 plugin rows present
...
[3] status: ponytail (single-plugin mp, clone HEAD == installed sha) shows current (AC2)
  ok: ponytail current (sha proven)
[4] status (AC3 negative control): superpowers pinned-old in fixture -> OUTDATED
  ok: OUTDATED row present for pinned-old superpowers
...
[27] update <outdated> --apply on an already-latest plugin -> 'already latest' no-op, NOT 'applied', exit 0
  ok: --apply already-latest reported as no-op (not 'applied'), exit 0

smoke: all 27 passed
```

## Done-gate check

```
$ grep -rn 'workspace/<owner>' tools/plugin-check/
(no output, exit 1)
```

## Reproduce

```bash
cd dwarves-kit/tools/plugin-check
bash tests/smoke.sh          # hermetic, 27/27
bin/plugin-check status      # live, over your real installed plugins ($CC_PLUGINS_DIR)
```
