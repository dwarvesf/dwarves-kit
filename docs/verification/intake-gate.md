# Verification log: the intake gate verb

Design source: `ops-toolkit/research/2026-09-06-knowledge-intake-contract.md` ("The gate
becomes a script"). Notes: `docs/implementation-notes/intake-gate.md`. Branch
`feat/intake-gate-verb`, base `ceccb02` (origin/master at start).

## Green run (f91d470)

| Check | Command | Exit | Result |
|---|---|---|---|
| the verb's own suite | `bash tests/test-intake.sh` | 0 | `test-intake: 27/27 passed` |
| bin census + dispatch | `bash tests/test-bin-forwarders.sh` | 0 | `test-bin-forwarders: all 47 passed, 0 skipped`, including the three new `intake` dispatch cases |
| structural integrity | `bash tests/test-meta.sh` | 0 | `Passed: 851 / 852` before regenerating `docs/FEATURES.md`; the one failure was the freshness pin, green after `bash lib/registry/feature-registry.sh generate` |
| config registry lints | `bash tests/test-config-registry.sh` | 0 | `48/50 passed`; AC10 (`root-only keys table == real call sites`) PASS with the four new `[intake]` keys. The two failures are `wrap.drain_staged`, a pre-existing live-machine leak in AC9 (it never pins `KIT_CONFIG_OPERATOR`), reproduced identically before and after this diff |
| scattered-id lint | `bash bin/lint --all` | 0 | no new zone violation |

## Real primary flow, run against the operator's live stores

The gate's whole job is to answer "did we already decide this", so the proof is the run
against the real ledgers, not the fixtures. Operator overlay pinned to a scratch
`kit.toml` naming the live stores.

| Input | Exit | Hits |
|---|---|---|
| `emdash cms` (a subject the verdict ledger decided NO-GO on 2026-08-27) | 0 | `board` (the parked row, `row_kind: eval`), `verdict` (the NO-GO row with its reason), `owned` (the absorption research note), `note` (the same note by recall) |
| `https://github.com/tuanddd/brand-design-system` (a link the URL ledger consumed on 2026-09-10) | 0 | `url` (`seen 2026-09-10 verdict keep` with the prior conclusion), `note` x2 (the absorption note) |
| `https://example.invalid/never-seen-2026-09-13-xyz` (a fresh link) | 1 | none, `hits: []` |

The first row is the exact miss the design source recorded: `precedent find --surface all
"emdash cms"` returns nothing although the verdict ledger carries the NO-GO row, because
precedent indexes neither the boards nor the verdict ledger. The gate cites both.

## NEGATIVE CONTROL (lead, mechanised)

Command: `bash lib/gate/negctl.sh <worktree> "bash tests/test-intake.sh" "sed -i '' '128s/|| continue/&& continue/' lib/intake/intake.sh"`
Mutation: inverts the board scan's per-file guard, so every board that EXISTS is passed over
Exit: 0 green before; 1 under the mutation; 0 after `git checkout HEAD -- lib/intake/intake.sh`
Output (excerpt): under the mutation the four board cases go red, `board row cited`, `the board hit names the registered board`, `the eval row reports row_kind eval`, `the skim row reports row_kind skim`; every other case stays green, so the control is scoped to the board source it broke
Verdict: `negctl` printed `Verdict: PASS`; the tree matched its snapshot after the restore

## Reproduce

```
bash tests/test-intake.sh
bash tests/test-bin-forwarders.sh
printf '[intake]\nurl_ledger = "<url-tool>"\nnotes = "<recall-tool>"\nverdicts = "<path>"\nboards = "<path>"\n' > "$D/kit.toml"
KIT_CONFIG_OPERATOR="$D" bash bin/intake gate "<a subject your ledger already decided>"   # exit 0
KIT_CONFIG_OPERATOR="$D" bash bin/intake gate "https://example.invalid/fresh"             # exit 1
```
