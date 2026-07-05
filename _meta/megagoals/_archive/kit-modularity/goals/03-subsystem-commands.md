# Sub-goal 03: subsystem-commands

**Merge policy:** auto
**Time budget:** 3-5 hours of loop work
**Proof:** run-table, each subsystem's standalone `<subsystem> <verb>` entry runs correctly (one row per subsystem, `board`/`stats`/`gate`/`classify`/`spec`/`goal`/`session` at least); a delete-the-`kit`-dispatcher NC proving every module still works standalone without it; every existing `bash lib/<x>.sh` call-site still resolves (grep + a spot-run). COVERAGE-DELTA. Rung 2 (named NCs). Each subsystem entry satisfies the F bar (doc + firing point).
**Design:** bearing (which subsystems earn a grouped entry vs stay bare; whether the optional `kit` dispatcher is built at all, spec decides per design note A)
**Depends on:** 01, 02 (entries wrap the collapsed modules incl. `stats`)
Model: sonnet
**Branch:** feat/kitmod-03-subsystem-commands
**PR base:** master (rebased after 02)

## Outcome

Each subsystem is an independently installable STANDALONE command with its own sub-verbs, the shape `board`/`orchestrate` already have: `board <render|next|queue|mirror|writeback>`, `stats <gate-yield|durations|...>`, `gate <record|plan|proof|...>`, `classify <lane|role|task-type|significance>`, `spec <index|next>`, `goal <draft|registry|merge>`, `session <observe|recall|intel>`. An OPTIONAL thin `kit` dispatcher (`kit list`, `kit <sub> <verb>` forwards) is discovery-sugar only, delete it and every module still works. Single-purpose orphans (`adopt`, `explain`, `pitch`) stay bare. Every `bash lib/<x>.sh` call-site keeps working (entries are additive; internal call-by-path stays).

## Quality bar

The human surface is per-subsystem standalone commands, install `session` without `bridge`, `gate` without `board`. No uber-binary owns them; the optional `kit` dispatcher never becomes a required front door. Only subsystems with 2+ verbs earn a grouped entry (ponytail, no wrapping a one-off script in a verb).

## How to close the loop

- For each subsystem module (from SG-01/02), add a thin `<subsystem>` entry (`board`-style: `<subsystem> <verb> "$@"` → the module's `<verb>` script). ~15 lines each.
- Decide (spec) whether the optional `kit` dispatcher is worth building; if yes, ~20 lines (`kit list` + forward); if it doesn't earn its keep, skip it and say so.
- Keep `/kit:*` slash commands untouched (separate Claude Code surface).
- Run-table: run each standalone entry's primary verb over a fixture; confirm output.
- NCs: delete the `kit` dispatcher (if built) → every standalone still works; grep + spot-run that `bash lib/<x>.sh` call-sites still resolve.
- F-bar: each subsystem entry ships a usage doc + a named firing point.

Kit-adopted: record build + review via `bash lib/gate-ledger.sh`.

**Done =** every subsystem has a working standalone `<subsystem> <verb>` entry, deleting the optional `kit` dispatcher breaks nothing, and all `bash lib/<x>.sh` call-sites still resolve, captured in `docs/proof/kitmod-subsystem-commands.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-04 wires these commands/modules into the layered install.
3. DECISIONS.md: record which subsystems got entries, and the `kit`-dispatcher build/skip decision.
4. Report in records, EXIT.

## Scope edges

**In:** per-subsystem standalone entries; the optional `kit` dispatcher (or a documented skip); their usage docs.
**Out:** install wiring (SG-04); the module collapse (SG-01); `/kit:*` slash commands (untouched).
**Not:** making `kit` a required front door; wrapping single-purpose orphans in verbs; changing any verb's behavior; touching the resolver.

## Where to look

the collapsed subsystem modules (SG-01/02), the existing `board`/`orchestrate` entry shape, design note Decision A.

## PR body

Per-subsystem standalone `<subsystem> <verb>` commands over the collapsed modules (the `board`/`orchestrate` shape) + an optional thin `kit` discovery dispatcher (delete-able, never required). Additive, every `bash lib/<x>.sh` call-site still works.

Verify: each standalone entry runs; delete-`kit`-dispatcher NC; call-sites resolve. Proof: `docs/proof/kitmod-subsystem-commands.md`. Stacked on #<SG-02>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes
