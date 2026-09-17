# Proof of done: audit-cadence-trigger

**Spec:** `docs/specs/SPEC-295-audit-cadence-trigger.md`. **Board:** ID-487. **Branch:** `feat/audit-cadence-trigger`.

Every audit-loop instance declares a cadence in `docs/patterns/audit-loop.md`, and `bin/audit due`
reads the last-run markers back to say which passes the cadence has come around for. No scheduler
ships with it.

## Green run

| Command | Exit | What it covers |
|---|---|---|
| `bash tests/test-audit-cadence.sh` | 0 | 13 assertions: the instance census, the parse, DUE before and after a run, an aged marker, and the two refusals |
| `bash tests/test-bin-forwarders.sh` | 0 | 48/48, including the extended `bin/` census and the new `audit` dispatch block |
| `bash tests/run-all.sh --changed` | 0 | 50 suites, 0 failed |

```
== census: the Cadence table is exactly the in-kit instance set ==
  ok: cadence census matches (backlog-reconcile ci-drift doc-drift gauntlet-proof-audit memory-tidy repo-hygiene topology-drift web-drift)
== every declared instance has a skill directory ==
  ok: no cadence row without skills/<name>/SKILL.md ()
== parse: cadence words map to their period in days ==
  ok: backlog-reconcile is weekly (7d)
  ok: memory-tidy is biweekly (14d)
  ok: doc-drift is monthly (30d)
== parse NC: a table row outside the Cadence section is not an instance ==
  ok: instance names are slugs, not table prose (0 with a space)
== due: a never-run instance is DUE ==
  ok: doc-drift reports never / DUE
== due: recording a run clears it ==
  ok: doc-drift is no longer DUE
  ok: web-drift is still DUE
== due: an aged marker brings the instance back ==
  ok: doc-drift is DUE again at 31d
== NC: an undeclared instance is refused and writes no marker ==
  ok: audit ran refuses an undeclared instance
  ok: no marker was appended
== NC: an unknown verb refuses ==
  ok: audit sweep exits non-zero

test-audit-cadence: 13 passed, 0 failed
```

```
test-bin-forwarders: all 48 passed, 0 skipped
```

The primary flow, run end to end against a temp ledger root:

```
$ bash bin/audit due
INSTANCE               CADENCE    LAST RUN     AGE    DUE
backlog-reconcile      7d         never        -      DUE
web-drift              7d         never        -      DUE
memory-tidy            14d        never        -      DUE
ci-drift               30d        never        -      DUE
doc-drift              30d        never        -      DUE
repo-hygiene           30d        never        -      DUE
topology-drift         30d        never        -      DUE
gauntlet-proof-audit   30d        never        -      DUE

$ bash bin/audit ran doc-drift "smoke"
recorded: doc-drift at 2026-09-17T02:23:56Z

$ bash bin/audit due
doc-drift              30d        2026-09-17   0d     -

$ bash bin/audit ran nope
audit ran: 'nope' is not declared in the Cadence table of .../docs/patterns/audit-loop.md
rc=1
```

**Verdict: PASS**

## Negative control

Produced by `bash lib/gate/negctl.sh` on a clean tree after the feature commit. The mutation
changes the monthly period so the cadence table no longer means what the doc says, which is the
defect class the suite exists to catch.

```
## Negative control (negctl)
Command: bash tests/test-audit-cadence.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/monthly) echo 30/monthly) echo 9999/' lib/audit/audit.sh
Changed: lib/audit/audit.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/audit/audit.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```bash
cd .claude/worktrees/audit-cadence
bash tests/test-audit-cadence.sh
bash tests/test-bin-forwarders.sh
bash lib/gate/negctl.sh "$PWD" \
  "bash tests/test-audit-cadence.sh" \
  "sed -i '' 's/monthly) echo 30/monthly) echo 9999/' lib/audit/audit.sh"
```

## Not proven

- **That any instance actually records a marker.** The eight skills now carry the instruction, and
  nothing enforces it. An instance that runs and forgets to call `audit ran` stays DUE forever, and
  the report is then wrong in the safe direction. The first real pass is what will show whether the
  instruction is enough.
- **The cadence periods themselves.** Seven days for `backlog-reconcile` and thirty for the rest are
  a judgment from one hand pass, not a measurement. They are one table edit away from changing.
- **Any scheduled caller.** None ships. `due` was never run from cron, launchd, or a workflow.
- **`run-all --changed` in full.** Three slow suites (`test-config-seams`, `test-hooks`,
  `test-meta`) hit the runner's own 300s ceiling in the parallel run, which is a timeout, not a
  failure. `test-meta` was re-run alone and reported its own result; the other two are untouched by
  this diff.
