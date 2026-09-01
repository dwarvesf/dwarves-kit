# Proof of done: ledger-observatory feature `memory-lens` (harness-observatory mega-goal, SG-06)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `memory-lens` feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only, PROPOSE-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-136-memory-lens.md`](../specs/SPEC-136-memory-lens.md) |

## What shipped

A memory-verify SWEEP over the memory STORES (repo `.claude/memory/`, built-in auto-memory
`~/.claude/projects/*/memory/`), delivered as three consumers of ONE scan function
(`memory_lens.scan()`):

- `memory_lens.py`: the new module. Walks each store, conservatively extracts PATH references
  from inline code spans, tests them against the live filesystem, parses each `MEMORY.md` as a
  link index. **NEVER writes** (the load-bearing property; NC below).
- `memories` DuckDB table (`store, slug, written, last_verified, dead_ref_count`), single-
  sourced via `schemas.MEMORY_SCHEMA` exactly like every other table.
- `ledger memory-sweep [--json|--table]`: the rich per-reference paydown report.
- `anomalies._detect_memory_hygiene`: a propose-not-autofile hygiene anomaly (dead-ref RATE over
  threshold + min-sample floor), reading ONLY the materialized `memories` table.

## Test design

`tests/test-memory-lens.sh` builds two fixture stores at test time in `mktemp -d`: a REAL git
repo for the repo store (so `written_ts`'s git-commit path is exercised with a `GIT_AUTHOR_DATE`-
backdated 2020 note), and a plain non-git directory tree for the builtin store (mtime-backdated
for the mtime-fallback staleness path), plus a second builtin store whose MEMORY.md is a
free-prose scratchpad (the DEC-010 gate). Every OTHER `LEDGER_OBS_*` source is pointed at a
nonexistent path (the SG-05 cross-suite-pollution lesson). 39 assertions.

**The two biggest design corrections were found NOT by either review pass but by the FIRST real-
corpus `ledger memory-sweep` run** -- the same "probe the real data shape before trusting the
spec's assumptions" lesson SG-05 recorded. The draft's paths/flags/commands classifier flagged
135 of 248 real units, overwhelmingly junk:

- **DEC-008 (command-testing removed):** bare backtick words (`` `README.md` ``, `` `main` ``)
  and shell builtins/keywords (`trap`, `export`, `const`) are not commands `shutil.which()` can
  resolve; command-testing was cut entirely. v1 tests PATHS ONLY.
- **DEC-009 (leading-`/` gated to a real-root allowlist; relative paths not tested):** the
  dominant leading-`/` false positive was Claude Code slash-commands (`/goal`, `/kit:spec`) and
  REST path fragments (`/v1/chat/completions`), not filesystem paths. Gated to
  `_REAL_PATH_PREFIXES`. Result: 135 -> 33 units flagged, junk gone, real dead paths kept.
- **DEC-010 (IS-IT-AN-INDEX gate):** a MEMORY.md with zero markdown-link bullets is a prose
  scratchpad (confirmed: `claude-guardrails`'s is 39 prose bullets, none a link), not a broken
  index -- flagging all 39 as orphans was noise. A file now contributes index refs only once it
  proves it IS a link index (>= 1 real link bullet). Guardrails 39 -> 0; the real ops-toolkit
  builtin MEMORY.md's MIGRATED tombstones stay flagged (they sit alongside real link bullets).

**`kit:code-reviewer` on the FINISHED diff** confirmed the never-write property holds for every
code path (the single most safety-critical property), and raised 2 LOW hardenings folded in: a
`_MAX_FILE_BYTES` read cap (a mis-placed binary is skipped, not read whole) and an index-parsing
docstring precision fix.

## Acceptance criteria

| # | Criterion | Status | Evidence (test id) |
|---|---|---|---|
| AC1 | `MEMORY_SCHEMA` -> exact 5-col list; `assert_parity` guards the load | PASS | M-lens + reused `test-schema-parity.sh` machinery |
| AC2 | a note with a DEAD path is flagged (`dead_ref_count >= 1`) | PASS | M-dead-path-note |
| AC3 | a note with a LIVE path is NOT flagged | PASS | M-live-path-note |
| AC4 | a >180d note is reported `stale=true` (git-commit AND mtime-fallback paths) | PASS | M-old-note (git), M-builtin-stale-note (mtime) |
| AC5 | **NEVER-DELETE NC (load-bearing, absolute):** every fixture memory file byte-identical (sha256) before/after sweep+rebuild+show+anomalies+propose; a deliberate mutation flips the SAME comparison to a mismatch (falsifiable), then `git checkout` restores | PASS | N-nc + N-nc-deliberate-break |
| AC6 | a plain-prose path-like string with NO backticks is NOT extracted | PASS | M-prose-path-note |
| AC7 | a flag-only inline span (`--dry-run`) does not crash / is not flagged | PASS | M-flag-fence-note |
| AC8 | a bare relative-path token is NOT flagged (both stores) | PASS | M-repo-relative-skip-note, M-builtin-relative-skip-note |
| AC9 | a MEMORY.md link to an existing file is NOT flagged; a missing link IS; a no-link orphan IS (in a real index) | PASS | M-repo MEMORY.md (dead=2), O8-real-index-flags-orphan |
| AC10 | `_detect_memory_hygiene` fires over rate + min-sample floors; not below either | PASS | M-anomaly + threshold sweep (real corpus, below) |
| AC11 | `--propose` stages the anomaly into the cc-backlog buffer, idempotent re-run | PASS | M-propose (staged + duplicate) |
| AC12 | a real `memory-sweep`/`rebuild`/`show memories` capture vs this repo's actual stores | PASS | Real-corpus capture (below) |
| AC13 | `ledger anomalies --help` lists both new threshold keys | PASS | M-anomaly --help x2 |
| AC14 | `scan()` skip-safe on a missing root (returns `[]`, never raises) | PASS | O1-missing-roots |
| (extra) | undecodable/oversized file -> empty text, never crashes the scan | PASS | O2-undecodable-file-no-crash |
| (extra) | bare word / slash-command / placeholder NOT tested; real-root path IS (DEC-008/009) | PASS | O4, O5, O6, O7 |
| (extra) | IS-IT-AN-INDEX gate: prose MEMORY.md flags nothing; real index still flags orphans (DEC-010) | PASS | M-prose MEMORY.md, O8 |
| (extra) | `~<unresolvable-user>` caught (RuntimeError) -> flagged dead, no crash | PASS | M-unresolvable-tilde-user-note |

## Confirmation (recorded runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| memory-lens suite | `bash tests/test-memory-lens.sh` | 0 | PASS (39/39) |
| never-delete NC falsifiability | deliberate `printf >> fixture` then `git checkout` restore | n/a | RED-as-expected (sha changes on the mutation), restored -> 39/39 |
| full regression | all 10 green suites re-run | 0 (x10) | PASS (266/266: 11+4+25+20+25+37+59+30+19+36) |
| real-corpus materialization | `uv run ledger rebuild` (no env overrides) | 0 | `memories: 248` |
| real-corpus sweep | `uv run ledger memory-sweep --table` | 0 | 248 units, 33 with dead refs, 0 stale (all notes actively maintained, <180d) |
| known MIGRATED tombstones caught | `ledger query "... WHERE slug='MEMORY' ... tieubao-ops-toolkit"` | 0 | dead_ref_count=3 (the 2 `MIGRATED to repo memory` lines + 1 more no-link bullet, alongside real link bullets) |
| DEC-010 gate on real corpus | `ledger query "... WHERE store LIKE '%guardrails%' AND slug='MEMORY'"` | 0 | dead_ref_count=0 (was 39 before the IS-IT-AN-INDEX gate; a prose scratchpad, correctly flags nothing) |
| anomaly threshold behavior (real corpus) | `ledger anomalies --threshold memory_dead_ref_rate_max=<t>` | 0 | 33/248 = 13.3%: no-fire at default 0.15, FIRES at 0.13/0.10 (mechanism live, honestly below the default threshold) |
| pre-existing, unrelated | `bash tests/test-feedback.sh` / `bash tests/test-ledger-cli.sh` | 1 | 30/39, 19/26 -- the same `kit_runs`/`lane-telemetry.sh` bash-3.2 issue root-caused in SG-04, untouched by this branch |

### Real-corpus capture (verbatim, top dead-ref units)

```
+--------------------------------------------------------+----------------------------------------+----------------+
| store                                                  | slug                                   | dead_ref_count |
+--------------------------------------------------------+----------------------------------------+----------------+
| builtin:...tieubao-family-office                       | project_hermes_family_topology         | 5              |
| builtin:...tieubao-trading                             | feedback_config_file_deletion          | 5              |
| builtin:...tieubao-ops-toolkit                         | project_pi_cockpit                     | 4              |
| builtin:...tieubao-ops-toolkit                         | project_telegram_plugin_cpu_orphan_bug | 4              |
| builtin:...tieubao-ops-toolkit                         | MEMORY                                 | 3              |  <- the MIGRATED tombstones
| repo:ops-toolkit                                       | hermes-install-sh-dir-flag             | 3              |
| repo:ops-toolkit                                       | mini-tailnet-subdomain-pattern         | 3              |
+--------------------------------------------------------+----------------------------------------+----------------+
```

These are genuinely-stale references: `project_hermes_family_topology` points at
`/Users/hermes-dwarves/.hermes` and `/Users/hermes-family/.hermes` paths that no longer exist;
`hermes-install-sh-dir-flag` references a `/Users/server/dev/hermes-agent` install dir since
moved. Propose-only: a human reviews the paydown table and decides.

## Never-delete negative control (the absolute requirement)

`N-nc` sha256s every file across BOTH fixture stores (`find "$GITREPO/.claude/memory" "$PROJROOT"
-type f | xargs shasum -a 256 | sort`) BEFORE running `memory-sweep` + `rebuild` + `show memories`
+ `anomalies` + `anomalies --propose`, and asserts the sorted digest list is byte-identical AFTER.
`N-nc-deliberate-break` then appends a real line to one fixture file, re-hashes, and asserts the
SAME comparison mechanism now reports a mismatch (proving it is falsifiable, not vacuous), then
`git checkout`-restores the file. Independently confirmed by the `kit:code-reviewer` static audit
of every code path for a write verb (none found).

## Coverage-delta

| Covered (v1) | Deferred | Why |
|---|---|---|
| repo `.claude/memory/` store | global `~/.claude/CLAUDE.md` reference sweeping | explicit v2 per the goal file scope fence; a single large file with a different structure than the note stores |
| built-in `~/.claude/projects/*/memory/` stores | relative-path resolution (both stores) | DEC-009: even repo-store notes reference other trees; "resolve against this repo" is unsafe, so a bare relative path is extracted-but-unverified |
| absolute paths under a real root (`_REAL_PATH_PREFIXES`) + `~/...` | command liveness | DEC-008: `shutil.which()` on bare words / builtins is 80% noise; removed from v1 |
| `MEMORY.md` link-index integrity (orphan + missing-link), gated by IS-IT-AN-INDEX | per-reference-kind anomalies | v1 dead_ref_count is a single kind-agnostic aggregate; a per-kind question needs a schema widen (documented) |

## Reproduce

```bash
cd tools/ledger-observatory && uv sync
bash tests/test-memory-lens.sh                 # 39/39
uv run ledger rebuild                           # memories: 248 (real corpus)
uv run ledger show memories --table             # the compact lens
uv run ledger memory-sweep --table              # the rich paydown report
uv run ledger anomalies --table                 # honest: memory_hygiene below default threshold today
uv run ledger anomalies --threshold memory_dead_ref_rate_max=0.10 --table  # fires (mechanism live)
```
