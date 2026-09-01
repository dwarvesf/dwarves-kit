# Proof of done: kit-modularity sub-goal 04 (install-wire)

Layers `install.sh`: the SDD spine wires unconditionally; every other hook belongs to an
opt-in module, wired only via `install.sh --with <a,b,c>` and recorded in a `kit.toml
[modules]` manifest. A re-run is additive (never un-wires a hook a prior run, or an old
all-hooks install, already wired); `--prune --with <modules>` is the explicit trim path. A
reserved `team_mode` slot exists and is not installable. Executes Decision B (+ the
`team_mode` reservation of Decision C) from `ops-toolkit/_meta/megagoals/kit-modularity/
research/2026-07-05-kit-modularity-design.md`.

## Acceptance criteria

1. A spine-only temp-HOME install (`bash install.sh`, no flags) wires ONLY the 6 spine
   hooks; grepping the installed `settings.json` shows zero optional-module hooks.
2. `install.sh --with board,stats` wires exactly those modules' hooks (spine + board's
   `backlog-stage.sh`; `stats` is hookless) and records `board = true`, `stats = true` in
   `kit.toml [modules]`; a bare re-run (no `--with`) reproduces the identical wired set
   from the manifest.
3. An un-opted-in module's hook (cosmetic/session/advisor) never reaches `settings.json`.
4. `kit.toml [modules]` always carries `team_mode = false`; `--with team_mode` is a clean,
   non-zero-exit error (reserved, not installable; Decision C).
5. An unknown module name (`--with bogus`) is a clean, non-zero-exit error naming the
   unknown module, not a silent no-op.
6. Existing-consumer migration is additive: re-running `install.sh` on a consumer with an
   OLD all-hooks install (no `kit.toml` yet) drops nothing; `--prune --with <modules>` is
   the only path that trims a previously-wired hook.
7. Post-install smoke: every hook that IS wired runs cleanly (exit 0) on a no-op event.
8. Standing anti-drift lint: no file under `hooks/` reads `kit.toml` at runtime (the
   manifest is a shell-install record, never a runtime feature-registry).
9. Coverage-delta: every module named in the manifest maps to a real installable unit
   (an existing hook file, or a documented hookless command/skill/lib subsystem).
10. Full kit test suite stays green before and after (no regression from the layering).

## The spine/optional split (reconciled against the real tree)

Read `install.sh`, `hooks/hooks.json`, `settings.json`, and every `hooks/*.sh` header
comment before classifying (not the design note's provisional names). Result:

**Spine (always wired, never gated):** `safety-gate.sh`, `ship-gate.sh`,
`spec-drift-guard.sh`, `secrets-guard.sh`, `commit-format.sh`, `anti-rationalization.sh`.
Essential per Decision B (`spec`/`execute`/`review`/`ship` + `gate-ledger`/`ship-gate` +
`lane-classify`/`proof-gate` + core verifiers); the four PreToolUse gates plus the Stop-hook
that catches false-completion rationalizing are the kit's non-negotiable floor. `lib/`
essentials (`lane-classify.sh`, `proof-ledger.sh`, `gate-ledger.sh`, the verifier agents)
are not hooks and are unaffected by module gating; they are always deployed.

**Optional modules (opt-in via `--with`), hook-bearing:**

| Module | Hook(s) gated | Rationale |
|---|---|---|
| `board` | `backlog-stage.sh` | Files backlog items; board-adjacent (kit-foldin `cc-backlog` port). |
| `session` | `context-readiness.sh`, `output-offload.sh`, `pre-compact-backup.sh`, `post-compact-reinject.sh`, `session-state-save.sh`, `harvest.sh`, `citation-guard.sh` | Session lifecycle/continuity + kit-foldin absorptions (`cc-harvest`, `cc-citation-guard`) grouped by their PreCompact/SessionStart/Stop/SubagentStop firing points. |
| `advisor` | `context-hints.sh` | Skill-trigger over-suggestion (kit-foldin `cc-context-hooks` port); matches Decision B's "advisor over-suggest". |
| `cosmetic` | `auto-format.sh`, `notification.sh`, `slop-cleaner.sh`, `statusline.sh` (+ the `statusLine` config key), `codebase-index.sh`, `permission-auto-approve.sh` | Named cosmetic in Decision B (`slop-cleaner`/`statusline`/`notification`/`auto-format`/`codebase-index`); `permission-auto-approve` added to this bucket as a judgment call (a convenience hook not explicitly named either way in the design note). |

**Optional modules, hookless (no `settings.json` entry to gate; still valid `--with` names,
recorded in the manifest for discovery/consistency):** `queue` (`lib/queue/`,
`dispatch`/`orchestrate`), `stats` (`lib/stats/`, the read-plane projection command),
`quiz_gate` (`commands/quiz-gate.md`), `weekend_batch` (the weekend-debt-paydown flow),
`bridge` (the board-writeback `bridge=on` per-project flag `lib/board/board.sh` already
generalizes).

**Reserved, not installable:** `team_mode`, always `false` in the manifest;
`--with team_mode` errors cleanly (Decision C: attestation-not-sync design exists, tripwire
to unpark has not fired).

## Non-obvious judgment calls (flagged for DECISIONS.md)

- `session` bundles two DIFFERENT things under one name: the continuity/harvest HOOKS
  (`context-readiness`, `output-offload`, `pre-compact-backup`, `post-compact-reinject`,
  `session-state-save`, `harvest`, `citation-guard`) vs. the `lib/session/` SUBSYSTEM
  (`session-observe`/`session-recall`/`session-intel`, the folded former `cc-observe`/
  `recall`/`intel` commands from SG-01). The lib subsystem has no hook to gate (it's a
  pull command), so it stays always-installed regardless of the `session` module toggle;
  only the hook set is gated. This is a defensible but non-obvious split worth naming.
- `permission-auto-approve.sh` and `citation-guard.sh` are not explicitly named in the
  design note's cosmetic/session lists; placed by inferred intent (permission-auto-approve
  -> `cosmetic`/convenience; citation-guard -> `session`, grouped with the other kit-foldin
  Stop/PreCompact absorptions) rather than a stated decision.
- `commit-format.sh` and `anti-rationalization.sh` are classified SPINE despite not being
  explicitly named essential in Decision B's list (which named `spec`/`execute`/`review`/
  `ship` + gates + verifiers, not individual hook files). Reasoning: commit-format enforces
  the `ship` discipline (conventional-commit hygiene at the push boundary) and
  anti-rationalization enforces the `review`/honesty discipline (catching false-completion
  claims), both are floor-level SDD behaviors, not conveniences, so they ride with the
  four PreToolUse gates rather than becoming opt-in.

## Confirmation run-table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Spine-only wires only 6 spine hooks | `HOME=$(mktemp -d) bash install.sh` then grep installed `settings.json` | PASS, exactly `anti-rationalization,commit-format,safety-gate,secrets-guard,ship-gate,spec-drift-guard.sh`, zero extra |
| 2 | `--with board,stats` wires exactly those + manifest | `HOME=... bash install.sh --with board,stats` | PASS, spine + `backlog-stage.sh`; `kit.toml` records `board=true stats=true`, rest `false` |
| 2b | Re-run reproduces | `HOME=... bash install.sh` (no flags, same HOME) | PASS, identical wired set to run above |
| 3 | Un-opted-hook-absent | grep installed `settings.json` for the 14 cosmetic/session/advisor hook basenames | PASS, 0 matches |
| 4 | `team_mode` reserved | `bash install.sh --with team_mode` | PASS, exit 1, "reserved" in stderr, no settings.json written |
| 5 | Unknown module | `bash install.sh --with bogus-module` | PASS, exit 1, names `bogus-module`, no settings.json written |
| 6 | Additive migration | seed settings.json = full kit settings.json (simulated old all-hooks install), then `bash install.sh` (no flags) | PASS, all 20 previously-wired hooks still present, 0 dropped |
| 6b | `--prune` explicit trim | same seed, then `bash install.sh --prune --with board` | PASS, trims to spine + board only |
| 7 | Post-install smoke | install `--with` all 9 modules; `echo '{}' \| bash <hook>` for all 21 wired hooks, from a throwaway git repo | PASS, 21/21 exit 0 |
| 8 | Anti-drift lint | `grep -rl kit.toml hooks/` | PASS, empty |
| 9 | Coverage-delta | every module maps to a real hook file or documented lib/command unit | PASS, 0 missing |
| 10 | Full suite before/after | `tests/test-hooks.sh` (452/452), `tests/test-meta.sh` (679/679), `tests/test-install-contract.sh` (3/3), `tests/test-install-compat.sh` (7/7), `tests/test-kit-foldin-hooks.sh` (49/49, updated for `--with`), `tests/test-adopt.sh` (12/12), `tests/test-e2e.sh` (20/20) | PASS, all green; test files unchanged except `test-kit-foldin-hooks.sh`'s install call, which now passes `--with board,session,advisor` since those hooks moved from always-wired to opt-in |

New test file: `tests/test-install-modules.sh` (21 assertions covering checks 1-9 above),
wired into CI (`.github/workflows/test.yml`).

## Run detail

```
$ HOME=$(mktemp -d) bash install.sh
...
[ok] Wrote module manifest: .../dwarves-kit/kit.toml
[ok] Enabled modules: <spine-only>
$ jq -r '[.hooks[]?[]?.hooks[]?.command]|.[]' $HOME/.claude/settings.json | grep -oE 'hooks/[a-z-]+\.sh' | sort -u
hooks/anti-rationalization.sh
hooks/commit-format.sh
hooks/safety-gate.sh
hooks/secrets-guard.sh
hooks/ship-gate.sh
hooks/spec-drift-guard.sh

$ bash tests/test-install-modules.sh
...
== 21 passed, 0 failed ==
```

## Reproduce

```
cd dwarves-kit
bash tests/test-install-modules.sh
bash tests/test-hooks.sh && bash tests/test-meta.sh
bash tests/test-install-contract.sh && bash tests/test-install-compat.sh
bash tests/test-kit-foldin-hooks.sh && bash tests/test-adopt.sh && bash tests/test-e2e.sh
```

## Ship-gate back-compat run (folded from prior docs/verification/kitmod-install-wire.md)

This section carries the gate's required green run + NEGATIVE CONTROL in the flat
single-file shape (`docs/verification/README.md`'s back-compat form); kept verbatim
alongside the fuller narrative above so no evidence is lost in the fold.

### Green run

Command: `bash tests/test-install-modules.sh`
Exit: 0
Output: `== 21 passed, 0 failed ==`
Verdict: PASS

Command: `bash tests/test-hooks.sh`
Exit: 0
Output: `Passed: 452 / 452`
Verdict: PASS

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 679 / 679`
Verdict: PASS

Command: `bash tests/test-install-contract.sh` / `test-install-compat.sh` / `test-kit-foldin-hooks.sh` (updated for `--with`) / `test-adopt.sh` / `test-e2e.sh`
Exit: 0 / 0 / 0 / 0 / 0
Output: `3/3` / `7/7` / `49/49` / `12/12` / `20/20`
Verdict: PASS

Command: `grep -rl kit.toml hooks/` (standing anti-drift lint: no hook reads the manifest at runtime)
Exit: 1 (grep found nothing)
Output: (empty)
Verdict: PASS

### NEGATIVE CONTROL

Reverted `install.sh` to its pre-SG-04 (parent commit) content, re-ran, restored:

```
$ command cp -f /tmp/install.sh.pre install.sh   # revert to the all-hooks installer
$ HOME=$(mktemp -d) bash install.sh
$ jq -r '[.hooks[]?[]?.hooks[]?.command]|.[]' $HOME/.claude/settings.json \
    | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh' | sort -u | wc -l
20                                                # RED: all 20 hooks wired, no layering

$ bash tests/test-install-modules.sh
...
== 6 passed, 15 failed ==                         # RED: 15/21 NCs fail without the layering

$ command cp -f /tmp/install.sh.new install.sh    # restore
$ git diff --stat install.sh
(empty)                                           # byte-identical to the committed version
$ bash tests/test-install-modules.sh
...
== 21 passed, 0 failed ==                         # GREEN again
```

Verdict: PASS (negative control confirms the layering is load-bearing, not a no-op: without
it, every optional hook wires unconditionally and 15 of the 21 new NCs fail).
