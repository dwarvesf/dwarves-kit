# Implementation notes: the intake gate verb

Delta from the design source (`ops-toolkit/research/2026-09-06-knowledge-intake-contract.md`,
sections "The gate becomes a script" and "What lands where") and from the backlog row that
re-homed the gate into this kit. References, does not restate.

## 2026-09-13 the four overlay keys, their kinds, and the two the design named differently

- **Context:** the design lists the overlay keys as `url_ledger`, `verdicts`, `boards`,
  `runs_dir`. Two of those name a store this kit cannot read by path, and one has no consumer
  in a gate-only change.
- **Decision:** the section ships four keys, `url_ledger`, `verdicts`, `boards`, `notes`.
  `verdicts` and `boards` are file paths. `url_ledger` and `notes` hold a COMMAND name, not a
  path. `runs_dir` is not declared.
- **Why:** the URL ledger's dedup key is a normalized URL (tracking parameters stripped,
  YouTube collapsed to one canonical watch link), so a grep of the ledger file silently misses
  a variant of a link already consumed. Only the tool that owns the ledger can compute that
  key, so the key names that tool and the gate calls `<cmd> check <url>`. The note store is
  the same shape: recall over embeddings, not a file a grep can answer. `runs_dir` belongs to
  the per-run report, which this change does not build, and this kit rejects a config key with
  no live reader.
- **Impact:** an operator fills two paths and two command names. The registry's `## Seams`
  table carries the kinds (`file`, `file`, `binary`, `binary`) so `config seams` reports each
  one's state.

## 2026-09-13 the similarity floor the design left open

- **Context:** semantic recall returns k rows for any input, so wiring it as a gate source
  with no floor makes every item a hit and the gate always exits 0.
- **Decision:** the verb passes a fixed floor of 0.65.
- **Why:** measured on the operator's own corpus: a subject the verdict ledger had already
  decided scored 0.68, an unrelated control query scored 0.34. The floor sits between them.
- **Alternatives:** a fifth config key for the floor, rejected as speculative configuration
  until an operator reports the value is wrong; no floor, rejected because it makes the
  source meaningless.

## 2026-09-13 open pull requests are one search, not one call per board

- **Context:** the design says the gate runs `gh pr list --search` "in the repos the boards
  name". The operator's registry names twenty boards.
- **Decision:** one `gh search prs "<subject>" --state=open --involves=@me` call, no per-repo
  iteration and no repo names in the kit.
- **Why:** twenty sequential network calls per item, against a sweep of eighty items, is not a
  gate anyone will run. One search covers every repository the operator touches, including
  repositories no board lists, and needs no tenant configuration. A failure (no `gh`, no auth,
  a rate limit) is a skipped source, never a failed gate.
- **Impact:** the hit kind is `pr`. The design's name for it was `in-flight`; the plain word
  won, per this kit's naming rule.

## 2026-09-13 what this change deliberately leaves out

- No `commands/intake.md`, and no `card`, `report`, or `vocab` verb. Those belong to the
  `/kit:intake` cycle; this change is the gate the backlog row describes and nothing around it.
- The five intake skills keep their prose gate sections untouched. Shrinking each to one line
  is the operator-side row, and it lands in the operator's own repository, not here.

## 2026-09-13 adjacent pre-existing failure, not fixed here

- `tests/test-config-registry.sh` AC9 probes each command-autonomy key's shipped default
  WITHOUT pinning `KIT_CONFIG_OPERATOR`, so on a machine whose operator overlay sets
  `[wrap] drain_staged = true` two of its cases fail on the operator's real file rather than
  on the fixture. Every other suite in this repository pins that variable at a path that does
  not exist for exactly this reason. Reproduced before and after this change with identical
  results, so it is unrelated to this diff; left for its own fix.
