# Implementation notes: ceremony lens

Only deviations, decisions and open questions that differ from the spec.

## Premise check

Every cited file and line held at build start (`anomalies.py`, `schemas.py`, `adapters.py`, `gate-ledger.sh:114`, `commands/execute.md:485`). Master is one commit ahead of the branch; that commit touches tests only, none under `lib/stats`.

## Decisions

- Two more tables than the spec names. `ledger_lines` (rid, starts, tokens, gates) feeds the excluded-rid counts and the `suspect fixtures` line, which need START and TOKENS counts the existing tables do not carry. `subagent_scan` (one row: files seen, files read, skipped, earliest mtime) carries the `skipped-files` and `transcripts: earliest` figures, which a row-per-dispatch table cannot hold.
- `git_lines` gains a `binary_files` column beside the spec's five, to carry the `binary-files` count.
- `git_lines.ts` is the committer date (`%cI`), because `git log --since` filters on committer date. `git_fixes` keeps `%aI`.
- Transcript tables load lazily. A 14-day transcript read is about 2 GB on this host, so `subagent_runs` and `subagent_scan` fill only when the SQL names them (or `rebuild`/`show` asks). Every other query keeps its old cost.
- Catches and known-caught rows count over every `ran`+`override` row in the window, not only ceremony phases. The spec defines them without a phase filter.
- A dispatch inside brackets of one rid twice counts as `window`. Only two distinct rids make it `ambiguous`.
- `query_many` in `materialize.py` runs several read-only queries on one lens build. The CLI needs about five result sets and one build takes minutes on the live corpus.
- `ceremony_share_max` stays 0.70. Live share is 0.76 and 0.77 per week; the live window has 49 catches in 178 known rows, so the anomaly does not fire on the live corpus.
- The `anomalies.py` import is two lines (`from . import ceremony`, then `from . import materialize`) because `test-anomalies-advisor.sh` O-one-path greps the literal `from . import materialize`.
- The `S-per-task` test compares `dispatches_per_task == 2` in jq, since jq prints `2.0` as `2`.
- Two code commits carry wrong subjects (`feat(board): work verb joins ...`, `docs(spec): ceremony lens round 2 ...`): a stale message file in the scratchpad was reused. Content is right, history cannot be amended here.
- Pre-existing failures outside Touches: `docs/FEATURES.md` drift in `test-meta.sh`, three skill trigger phrases in `test-docs-wiring.sh`.
