# 0035. The durable ledger root: one resolver, one precedence chain

Date: 2026-07-15
Status: Accepted. Records a decision already implemented and shipped (SPEC-097, 2026-07-02; extended by SPEC-182 and the `[ledger]` config wiring proved at `docs/verification/wire-ledger.md`). This ADR is the retroactive record the telemetry module never had: the machinery was built, the reasoning lived only in code comments and two specs, and the 2026-07-14 doc sweep listed `telemetry` as having "an origin SPEC but zero ADR / proof / implementation notes of its own" (`tests/kit-contract-known-gaps.txt`). Nothing here changes behavior; it names the invariant so a future change cannot quietly break it.
Relates-to: SPEC-097 (ledger durability, the origin), SPEC-182 (stats plane; D2 `KIT_LEDGER_DIR` as the one root), SPEC-061 (lane-telemetry, the module's other half), SPEC-200 C6 (the contract lint that enforces this), ADR-0024 (gate-ledger + ship enforcement, the biggest consumer), ADR-0034 decision 10 (append-only retention stands), `docs/verification/wire-ledger.md` (the `[ledger]` config layer; its SPEC-186 ID has no spec file in `docs/specs/`)

## Decision (one line)

Every durable ledger the kit writes resolves its root through exactly ONE function, `kit_resolve_log_dir` in `lib/telemetry/kit-log-dir.sh`, whose default lives OUTSIDE `~/.claude/` (the plugin reinstall blast zone), whose precedence is `KIT_LEDGER_DIR` -> `DWARVES_KIT_LOG_DIR` -> `kit.toml [ledger].location` -> XDG state, and which FAILS LOUD rather than resolve a root it cannot trust.

## Context

**The incident.** Until SPEC-097 the run corpus defaulted to `~/.claude/dwarves-kit/logs`, inside the plugin's own state directory. That directory holds the real `logs/` beside symlinks (`lib`, `AGENTS.md`, `WORKFLOW.md`) that a plugin reinstall regenerates. On **2026-07-01 a plugin reinstall recreated the directory and wiped the entire run corpus.** Telemetry that cannot survive a reinstall cannot feed `/kit:retro` or the SPEC-073 effectiveness eval, which is the only reason the corpus exists. This was not a near-miss; the history was gone.

**Why a resolver and not just a better default.** The corpus is written by many hands: the gate ledger, the proof ledger, the lane classifier's downgrade log, the precedent index, mega-merge, and (since 2026-07-14) the overnight queue's journal. A path constant copied into six libs is six places for the next default to drift, and drift here is silent: nothing errors, the writes just land somewhere the readers do not look. The property that matters is not "the default is good" but "there is exactly one place the default lives."

**Three failure modes the root can have, all silent.** Each is why a corresponding rule exists below.

| Failure mode | What it looks like | Why it is silent |
|---|---|---|
| Root inside the blast zone | reinstall wipes the corpus | nothing errors; the ledgers are simply gone next read |
| Root resolves to empty | every writer appends to a RELATIVE `runs/...` path in the caller's cwd | the writes succeed, scattered across whatever directory each tool ran in |
| Legacy dir is a symlink | `cp -R legacy/.` dereferences it and fans the link target into the corpus | the migration "succeeds"; the corpus that `/kit:retro` reads is now attacker-seeded |

## Decision

**1. One resolver.** `lib/telemetry/kit-log-dir.sh` exposes `kit_resolve_log_dir` (the root), `kit_legacy_log_dir` (the pre-SPEC-097 path), and `kit_migrate_log_dir` (one-time additive migration). Corpus-bearing libs SOURCE it instead of hard-coding a path. It is a lib-layer file with no output on load, safe under `set -euo pipefail`, and guarded against double-sourcing.

**2. The precedence chain.** Four levels, in order. The first three exist so a consumer can relocate the root without editing the kit; the fourth is the durable default.

| # | Source | Resolves to | Why it is at this level |
|---|---|---|---|
| 1 | `$KIT_LEDGER_DIR` | the literal value | the canonical knob (SPEC-182 D2). Essential-tier config, one root per consumer. Wins over everything. |
| 2 | `$DWARVES_KIT_LOG_DIR` | the literal value | back-compat alias, the pre-SPEC-182 name. Kept because every existing test pin and the live corpus resolve through it; retiring it would be churn with no gain. |
| 3 | `kit.toml` / `.kit.toml` `[ledger].location` | `isolated` -> `$PWD/.kit/logs`; `shared` or unset -> level 4; any other value -> that explicit path | the config layer, read via `lib/config/kit-config.sh` (project `.kit.toml` overrides kit-root `kit.toml`). Sits BELOW the env vars so a test or a one-off run can always override a project's committed config. |
| 4 | `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs` | the hardcoded default | the whole point: XDG state is the canonical home for persistent state, and it is **entirely outside `~/.claude`**, so no `~/.claude/dwarves-kit*` reinstall can reach it. |

**3. Set-but-empty is FATAL, never a fall-through.** A `KIT_LEDGER_DIR` that is SET but EMPTY makes `kit_resolve_log_dir` print a diagnostic to stderr and `return 1`. It does not fall through to the next level. The distinction is deliberate: a genuinely UNSET variable means "I have no opinion, use the chain" (erroring there would break every existing consumer), while a set-but-empty one means a caller computed a root and got nothing, and continuing would append to a relative path. Callers use the `LOG_DIR="$(kit_resolve_log_dir)" || exit 1` form so the failure is clean. `lib/queue/queue.sh` adds a second belt for the same footgun: it refuses a journal path of `/queue-journal.tsv` or `queue-journal.tsv` outright, because it is the one launcher that runs unattended overnight and a silently-misplaced journal there means the whole night's history lands in the filesystem root.

**4. Migration is additive, one-time, and refuses a symlink.** `kit_migrate_log_dir` copies the legacy corpus into the durable root with `cp -Rn` (recursive, no-clobber, never deletes the legacy dir), then drops a `.migrated` sentinel. It no-ops when either env knob is set (an explicit root means the caller owns the path, which is what stops a test pointing at a mktemp dir from ingesting the real machine corpus). Two hardening rules, both from the SPEC-097 security review:
- **Symlink refusal.** If the legacy dir is a symlink, migration refuses to copy THROUGH it, warns, and sentinels. `cp` dereferences a `/.`-suffixed symlink, so `-P` does not help; the guard is an explicit `[ ! -L ]` test. Without it, an attacker-planted link fans its target's contents into the corpus that `/kit:retro` and the eval read.
- **Sentinel only on success.** The `.migrated` sentinel is written only inside the `cp`-success branch, so a partial or failed copy (permissions, disk) leaves no sentinel and the next access retries. This is what preserves the additive guarantee.
- Migration always returns 0 (every fallible op is guarded), because a migration hiccup must never abort a lib load under `set -e`: that would make `gate-ledger check` exit nonzero and fail-CLOSE the ship gate on unrelated work.

**5. The consumer list is closed and enforced.** Every module that persists state resolves through the resolver; SPEC-200's C6 lint fails the build on any `lib/` code line hardcoding the pre-SPEC-097 path.

| Consumer | What it persists | Source discipline |
|---|---|---|
| `lib/gate/gate-ledger.sh` | the run ledgers (`runs/<rid>.log`), the ship gate's evidence | FATAL on missing resolver |
| `lib/gate/proof-ledger.sh` | proof-of-done records, overrides | FATAL |
| `lib/gate/proof-table-gen.sh` | generated proof run-tables | FATAL |
| `lib/telemetry/lane-telemetry.sh` | reads the corpus (SPEC-061 aggregator) | FATAL |
| `lib/classify/lane-classify.sh` | `completeness.log` LANE-CHECK downgrades | FATAL. In the set because it WRITES what lane-telemetry READS; leaving it behind would split-brain the downgrades. |
| `lib/precedent.sh` | the precedent index | FATAL |
| `lib/goal/mega-merge.sh` | mega-merge records | FATAL |
| `lib/ledger/ledger.sh` | the SPEC-182 append substrate (row-append + root in ONE place) | FATAL |
| `lib/learn/weekend-batch.sh` | the debt ledger | FATAL |
| `lib/mega.sh` | sources the resolver and EXPORTS `KIT_LOG_DIR` for child tools | FATAL |
| `lib/queue/queue.sh` | the overnight queue journal (`queue-journal.tsv`); **joined 2026-07-14**, commit `8475ace` | soft-source + a `declare -f` check, because queue runs without `set -e`: an unguarded call would substitute empty and put the journal at `/queue-journal.tsv` |
| `lib/spec/spec-next.sh` | (optional) | best-effort source; degrades if the resolver is absent |

Hook **diagnostic** logs (`ship-gate.log`, `slop-cleaner.log`, `citation-guard.log`) are deliberately OUT of this set and stay on the legacy default: they are ephemeral breadcrumbs that regenerate, not corpus. This is not a leak in the enforcement path, and that is worth stating precisely because it looks like one: `hooks/ship-gate.sh` uses its `LOG_DIR` ONLY to append its own `ship-gate.log` line, and delegates the actual ledger read to `bash "$LEDGER" check ...` (gate-ledger.sh), which resolves through the resolver like everything else.

**6. Retention: append-only stands.** Restated from ADR-0034 decision 10 so it is visible from the root's own record: ledgers are never rewritten, and rotation is revisited only at a measured threshold (shared root over 100 MB, or `stats digest` wall-time over 10 s), never as silent TTL deletion.

## Consequences

- **The corpus survives a reinstall.** The default root is outside `~/.claude` entirely, so the 2026-07-01 failure cannot recur through that path. Verified by `lib/telemetry/tests/smoke.sh` case P4c, which asserts the default never resolves inside the blast zone whatever `$HOME` is.
- **A new persistent store must source the resolver.** Not a convention, a lint: SPEC-200 C6 greps `lib/` for the hardcoded legacy path (code lines only, comments exempt) and fails the contract test. Adding a store that opens its own path is a red build, not a review comment.
- **Consumers can relocate the root without forking the kit**, via the env knob (per-run) or `[ledger].location` (committed per-project). `isolated` gives a project its own `./.kit/logs`.
- **The failure is loud, so a misconfigured root costs one error message, not a scattered corpus.** The cost is that a caller MUST handle the nonzero return; the `|| exit 1` form is the contract.
- **KNOWN DIVERGENCE: the read plane does not implement level 3.** `lib/stats/src/stats/config.py::kit_log_dir` is a second, Python implementation of this precedence, and it implements only levels 1, 2 and 4. It never reads `kit.toml [ledger].location`, though its docstring claims it "mirrors the shell resolver exactly (SPEC-182)". The shell resolver gained the config layer later (the `[ledger]` wiring at `docs/verification/wire-ledger.md`) and the Python copy was never updated. Consequence: with `[ledger].location` set to `isolated` or an explicit path and no env var set, the WRITE plane writes to the toml location while the `stats` READ plane reads the XDG default. That is precisely the split-brain SPEC-182 D2 exists to forbid ("the writer writes and `stats` reads the SAME root"). It is latent, not currently firing: the shipped `kit.toml` default is `location = "shared"`, which both planes resolve to XDG. It bites the moment a consumer uses the `isolated` mode the config surface openly offers. Reproduced 2026-07-15 (evidence in `lib/telemetry/docs/proof-of-done.md`). Two exits exist: have `stats` shell out to the one resolver, or teach it the toml layer and lint the two implementations against each other. Choosing between them is a behavior change and belongs in its own spec, not in this record.
