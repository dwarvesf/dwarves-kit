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
