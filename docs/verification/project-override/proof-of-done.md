# Proof of done: project-override (SPEC-192, harness-ops sub-goal 06)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | `/kit:adopt` (`lib/adopt.sh`) seeds a starter `<project>/.kit.toml` on a fresh adopt | PASS | "fresh adopt seeds a starter .kit.toml with a [modules] section" |
| AC2 | The seeded `[modules]` values reflect the kit-root default when `--with` is not given | PASS | "fresh adopt wires kit-root-default-enabled modules' hooks (board/advisor in, cosmetic out)" |
| AC3 | `--with <modules>` on a FRESH project seeds those modules `true` even against a `false` kit-root default | PASS | "--with cosmetic on a fresh repo seeds cosmetic=true and wires its hook" |
| AC4 | `--with` is ignored (never clobbers) once `<project>/.kit.toml` already exists | PASS | "--with is ignored once .kit.toml already exists (never overwritten)" |
| AC5 (**Done=, clause 1**) | A project `.kit.toml` `[modules] board=false` results in that project NOT wiring board's hook, verified via its `settings.json` | PASS | "DONE=: project .kit.toml [modules] board=false -> board's hook is NOT wired (settings.json)" |
| AC6 | The board-only edit is surgical: an unrelated still-enabled module's hooks stay wired | PASS | "re-wiring after a board=false edit leaves the still-enabled session module's hooks wired" |
| AC7 (**Done=, clause 2**) | A `[ledger]` override in the project `.kit.toml` is honored by a command reading it (the resolver) | PASS | "DONE=: a [ledger] override in the project .kit.toml is honored by the resolver" |
| AC8 | Re-wiring is idempotent: an unchanged `.kit.toml` re-run is a clean settings.json no-op | PASS | "re-running adopt --refresh with an unchanged .kit.toml is a clean no-op on module wiring" |
| AC9 | No regression to the global install / manifest chain (`install.sh` untouched) | PASS | `tests/test-install-modules.sh` 37/37 unchanged |
| AC10 | No regression to the resolver | PASS | `lib/config/kit-config.sh selftest` 6/6 unchanged |

**Total: 21/21 PASS in `tests/test-adopt.sh` (11 pre-existing + 10 new SPEC-192 assertions). Regression: 37/37 (`test-install-modules.sh`) + 6/6 (`kit-config.sh selftest`) unchanged, 0 FAIL.**

## What this closes

The resolver (`lib/config/kit-config.sh`, sub-goal 01) already merged a project
`.kit.toml` over the kit-root default -- but nothing translated that merged value into
an actual settings.json change. This sub-goal wires `lib/adopt.sh` to (1) seed a starter
`.kit.toml` (opt-in, `--with`-aware, never overwritten after creation) and (2) recompute,
on every adopt run, which hook-bearing modules (`board`/`session`/`advisor`/`cosmetic`)
are enabled for THIS project and merge their hooks into
`<project>/.claude/settings.json` -- a targeted jq merge, never a wholesale file
rewrite. Command/skill modules (`queue`/`stats`/`quiz_gate`/`weekend_batch`/`bridge`)
are recorded in `.kit.toml` but never touch settings.json (they have no hook to gate).

## Confirmation run (positive: current tree)

Command: `bash tests/test-adopt.sh`
Exit: 0

```
ok - fresh adopt creates AGENTS.md + WORKFLOW pointer + CLAUDE pointer + proof marker
ok - re-run is a clean no-op (idempotent)
ok - --check exits 0 on an adopted repo
ok - --check exits 1 on a fresh repo
ok - existing AGENTS.md is not clobbered
ok - CLAUDE.md loader uses @AGENTS.md import + paired end marker
ok - --dry-run writes nothing
ok - --refresh keeps a single managed block
ok - --refresh refuses to truncate a block missing its END marker (file untouched)
ok - --refresh replaces a stale block body and preserves surrounding content
ok - --refresh preserves AGENTS.md + proof marker (never overwritten)
ok - --dry-run on an adopted repo writes nothing
ok - fresh adopt seeds a starter .kit.toml with a [modules] section
ok - fresh adopt wires kit-root-default-enabled modules' hooks (board/advisor in, cosmetic out)
ok - --with cosmetic on a fresh repo seeds cosmetic=true and wires its hook
ok - precondition: board's hook is wired before the override (kit-root default board=true)
ok - DONE=: project .kit.toml [modules] board=false -> board's hook is NOT wired (settings.json)
ok - re-wiring after a board=false edit leaves the still-enabled session module's hooks wired
ok - DONE=: a [ledger] override in the project .kit.toml is honored by the resolver
ok - --with is ignored once .kit.toml already exists (never overwritten)
ok - re-running adopt --refresh with an unchanged .kit.toml is a clean no-op on module wiring
---
PASS=21 FAIL=0
```

Full log: `/tmp/proof-run-192-adopt.log` (this run).

## The Done= run-table, isolated

The two literal Done= clauses, run by hand against a scratch project (mirrors what
`tests/test-adopt.sh` automates):

```
$ T=$(mktemp -d) && git -C "$T" init -q
$ bash lib/adopt.sh "$T" >/dev/null
$ jq -r '[.hooks[]?[]?.hooks[]?.command] | .[]' "$T/.claude/settings.json" \
    | grep -o 'backlog-stage.sh'
backlog-stage.sh          # board's hook IS wired (kit-root default board=true)

$ sed -i.bak 's/^board = true$/board = false/' "$T/.kit.toml" && rm "$T/.kit.toml.bak"
$ bash lib/adopt.sh --refresh "$T" >/dev/null
$ jq -r '[.hooks[]?[]?.hooks[]?.command] | .[]' "$T/.claude/settings.json" \
    | grep -o 'backlog-stage.sh' || echo "(absent)"
(absent)                  # board=false -> board's hook is NOT wired. Done= clause 1.

$ printf '\n[ledger]\nlocation = "isolated"\n' >> "$T/.kit.toml"
$ KIT_CONFIG_ROOT="$(pwd)" KIT_PROJECT_ROOT="$T" \
    bash -c "source lib/config/kit-config.sh; kit_config_get ledger.location"
isolated                  # project [ledger] override honored by the resolver. Done= clause 2.
```

## Negative control (revert the change, or plant a violation)

Two ways this would go RED, both exercised during authoring:

1. **Revert `lib/adopt.sh`'s step 6 (module wiring)**: with the wiring block removed,
   `<project>/.claude/settings.json` is never created/updated by adopt, so
   `backlog-stage.sh` (or any module hook) never appears regardless of `.kit.toml` --
   `tests/test-adopt.sh`'s AC2/AC5 assertions fail immediately (grep finds nothing to
   match, or matches when it should not).
2. **A settings.json rewrite instead of a merge** (e.g. `cp "$filtered" "$project_settings"`
   unconditionally, dropping the merge-with-existing branch): confirmed during authoring
   that this reintroduces non-idempotency -- re-running adopt against an
   already-populated settings.json reorders/duplicates entries and `git diff` on the
   idempotency test (test 2, and the new test 18) goes dirty. This is exactly the defect
   this sub-goal's `jq -S` + sorted-array canonicalization fixes; removing it is the
   negative control.

## Regression (global install + resolver unaffected)

```
$ bash tests/test-install-modules.sh
... (37 assertions unchanged) ...
== 37 passed, 0 failed ==

$ bash lib/config/kit-config.sh selftest
ok   project overrides kit-root
ok   kit-root default when no proj
ok   inline comment stripped
ok   commented key -> caller default
ok   missing key -> caller default
ok   missing section -> empty
PASS kit-config selftest
```

Full logs: `/tmp/proof-run-192-installmod.log`, `/tmp/proof-run-192-selftest.log`.

## Reproduce

```
cd <repo>
bash tests/test-adopt.sh            # new SPEC-192 assertions + all pre-existing ones
bash tests/test-install-modules.sh  # regression (install.sh untouched)
bash lib/config/kit-config.sh selftest  # regression (resolver untouched)
```
