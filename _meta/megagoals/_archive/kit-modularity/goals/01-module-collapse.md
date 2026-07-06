# Sub-goal 01: module-collapse

**Merge policy:** auto
**Time budget:** 3-5 hours of loop work
**Proof:** run-table, full kit suite green BEFORE and AFTER (identical pass count); the LOAD-BEARING no-alias NC (`find lib -maxdepth 1 -type l` returns EMPTY , shims gone, not hidden); the resolution NC (`orchestrate` + `mega-merge` run end-to-end post-restructure, cross-subsystem `$LIB_ROOT/...` calls resolve); a `.github/workflows/` path-audit; COVERAGE-DELTA (every updated call-site resolves). Rung 2 (named NCs); structural relocation + call-site refactor, no injection surface. Each collapsed module also satisfies the F bar (doc + firing point), audited here.
**Design:** bearing (a real call-site refactor + the resolution mechanism `LIB_ROOT` + the top-dir-name call `lib/` vs `modules/`; the spec picks + justifies. This is HIGH blast radius , every `bash "$DIR/x.sh"` caller moves , so it is opus + over-tested, per design note E3 + Han's no-alias directive)
**Depends on:** none (first; builds on kit-foldin's shipped `lib/` subsystem dirs)
Model: opus
**Branch:** refactor/kitmod-01-module-collapse
**PR base:** master

## Outcome

The `lib/`-vs-`tools/` split is retired AND the alias shims are eliminated , a PROPER restructure, not aliases everywhere (Han's directive 2026-07-05). **REALITY (verified 2026-07-05): kit-foldin's SG-01 already made the `lib/` subsystem dirs** (`board/ classify/ gate/ goal/ queue/ session/ spec/ telemetry/`), but it took the CHEAP shim route , it moved each file into a subsystem dir and left a **symlink alias at the old `lib/` root** (`lib/board.sh -> board/board.sh`, `lib/gate-ledger.sh -> gate/gate-ledger.sh`, ~all 34 flat files are these aliases or not-yet-grouped reals). Han does NOT want scattered aliases. So this sub-goal:
1. **Removes EVERY lib-root symlink alias** , the real file lives ONLY in its subsystem dir; nothing at `lib/` root is an alias.
2. **Updates EVERY call-site** to the proper path. The kit's scripts self-resolve siblings from their own `BASH_SOURCE`; the clean fix is a single `LIB_ROOT` anchor (each script computes the `lib/` root, then references `$LIB_ROOT/<subsystem>/<file>.sh`) , ONE mechanism, no scattered aliases. Update all callers in `lib/`, `hooks/`, `commands/`, `tests/`, `install.sh`.
3. **Folds the `tools/` subtrees** (`ledger-observatory`, `session-observe/recall/intel`, `skill-curator`, `plugin-check`) INTO the subsystem structure as self-contained modules (helpers + entry + tests + docs co-located).
4. **Groups any genuinely-ungrouped real files** still at `lib/` root into their subsystem.

`agents/`/`commands/`/`hooks/`/`skills/` stay top-level (loader-mandated). Keep `lib/` as the dir name unless a neutral `modules/` clearly wins. End state: `find lib -maxdepth 1 -type l` is EMPTY (zero alias symlinks); every call-site resolves through the real subsystem path.

## Quality bar

A reader sees subsystem modules, not two arbitrary buckets, and NO alias shims cluttering `lib/` root. "tool" vs "lib" is now a description of a module's surface, not a location. Every call-site resolves through the file's real subsystem path (one `LIB_ROOT` mechanism), not a scattered symlink. Nothing that worked before breaks after, the full suite is the gate, and the busiest cross-subsystem callers (`orchestrate`, `mega-merge`) run end-to-end to prove the resolution.

## How to close the loop

- Re-read the real merged state (grounded 2026-07-05, confirm no drift): `lib/` already HAS the subsystem dirs (board/classify/gate/goal/queue/session/spec/telemetry) + ~34 flat `.sh` at lib root; `tools/` = ledger-observatory/session-observe/recall/intel/skill-curator/plugin-check. The dirs are DONE , do not recreate.
- Decide the top-dir question (`lib/` vs `modules/`) in the spec (Design: bearing); default `lib/`.
- ENUMERATE every call-site first: `grep -rnE '\$[A-Z_]*DIR/[a-z-]+\.sh|source "\$[A-Z_]*DIR|lib/[a-z-]+\.sh' lib/ hooks/ commands/ tests/ install.sh` , this is the full set the restructure must update (the aliases exist to avoid exactly this; we do the work instead).
- Introduce ONE clean resolution mechanism: each script computes `LIB_ROOT` (the `lib/` dir) from its own `BASH_SOURCE`, then references cross-subsystem siblings as `$LIB_ROOT/<subsystem>/<file>.sh`. NO scattered per-file aliases.
- **Remove every lib-root symlink alias** (`find lib -maxdepth 1 -type l -name '*.sh' -delete` AFTER call-sites are updated) and move any genuinely-ungrouped real file into its subsystem.
- Fold each `tools/<x>/` into the module structure (co-located helpers/entry/tests/docs); update its call-sites the same way.
- Baseline the full suite; after the restructure, re-run , identical pass count.
- NC (no aliases): `find lib -maxdepth 1 -type l` returns EMPTY , the load-bearing check that the shims are gone, not just hidden.
- NC (resolution works): run `orchestrate` + `mega-merge` end-to-end post-restructure and confirm their cross-subsystem calls (`$LIB_ROOT/gate/gate-ledger.sh`, the FATAL-on-miss `source` of `kit-log-dir.sh`) resolve.
- NC (CI-path audit, advisor P6): grep `.github/workflows/*.yml` for any moved path (`tools/<x>`, `lib/<x>` hardcodes, cache keys) BEFORE finishing , a `git mv` doesn't break an inline `pytest`/`go test` but DOES break a workflow step that hardcodes the old path (it surfaces on the NEXT push, not in-loop). Update any hit in the SAME PR.
- F-bar for touched modules: each has a co-located usage doc + a named firing point (or flag the gap).

Kit-adopted: record build + review via `bash lib/gate-ledger.sh`; `lane-classify` this.

**Done =** `find lib -maxdepth 1 -type l` is EMPTY (zero alias symlinks) AND the full kit suite passes at the identical pre-restructure count AND `orchestrate` + `mega-merge` run end-to-end with their cross-subsystem calls resolving AND every touched module has a co-located doc + firing point, captured in `docs/proof/kitmod-module-collapse.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-02 + SG-03 may dispatch (they land within this structure).
3. DECISIONS.md: record the top-dir decision (`lib/` vs `modules/`) + any module-boundary judgment calls.
4. Report in records, EXIT.

## Scope edges

**In:** the `lib/` + `tools/` trees → subsystem modules; REMOVING the lib-root symlink aliases; the `LIB_ROOT` resolution mechanism; updating every call-site (lib/hooks/commands/tests/install.sh); co-located docs for touched modules.
**Out:** `agents/`/`commands/`/`hooks/`/`skills/` (loader-mandated, stay); the `stats` rename (SG-02); the command entries (SG-03); install wiring (SG-04).
**Not:** renaming any module's verbs/functions; "improving" logic while moving; a language rewrite (bash stays bash, Python stays Python); LEAVING any lib-root alias behind (the whole point is to remove them); a NEW abstraction beyond the single `LIB_ROOT` anchor (no per-file wrapper, no dispatcher , that would just be aliases by another name).

## Where to look

kit-foldin's merged `lib/` subsystem dirs + `tools/`, the SG-01 resolver, the design note E3 block, memory `harness-machinery-in-the-kit`.

## PR body

Retire the `lib/`-vs-`tools/` split into self-contained per-subsystem modules (helpers+entry+tests+docs co-located); loader-mandated dirs stay top-level; zero call-site breakage via the kit-foldin resolver.

Verify: full suite green at identical pre-collapse count; one migrated tool runs end-to-end; touched modules carry doc + firing point. Proof: `docs/proof/kitmod-module-collapse.md`.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes
