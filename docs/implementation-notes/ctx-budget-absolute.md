# Implementation notes: context-budget absolute token thresholds

No spec; the dispatch brief below is the design record and the contract. The notes after it hold only the decisions the brief left open.

## Design record: the dispatch brief (verbatim)

> Task: fix the kit's context-budget hook so workers stop at a sane absolute size, not at 74% of a window it guessed wrong.
>
> Evidence (Mini): hooks/context-budget.sh assumes a 200,000-token window unless a "1m" marker appears. The model is claude-opus-5-5 (settings model "opus"), with no marker. Three heat-rank workers got "CONTEXT CEILING: 74%/77% of its window (148k/154k tokens)" and stopped to hand off, yet the same transcripts later reached 279k, 282k and 358k tokens, so the real window is larger than 200k. Each worker lost its run at about 150k and needed a fresh worker.
>
> Owner's intent: the hook exists for cost (every turn re-reads the context from cache), and his standing rule is to retire a chat past about 250k context.
>
> Change (repo dwarves-kit, hooks/context-budget.sh plus its tests and docs):
> 1. Thresholds in absolute tokens: KIT_CTX_WARN_TOKENS default 200000, KIT_CTX_STRONG_TOKENS default 250000. Keep the percentage variables working only when explicitly set, for backward compatibility; say so in the header.
> 2. The message prints tokens, not a percentage of a guessed window.
> 3. Tests: below 200k silent; 200k warns once; 250k strong once; reset after dropping under warn; the old 148k case no longer fires. Negative control: with KIT_CTX_STRONG_PCT=70 and KIT_CTX_WINDOW=200000 set explicitly, the old behavior returns.
> 4. Check whether dotfiles carries a sibling personal context-budget hook with the same 200k assumption (the header says the kit copy came from it); if so, fix it the same way in a dotfiles PR.

## Decisions the brief left open

- **Mode switch.** Percent mode turns on when either `KIT_CTX_WARN_PCT` or `KIT_CTX_STRONG_PCT` is non-empty; the unset one keeps its old default (65 / 70). `KIT_CTX_WINDOW` alone does not switch modes, because the brief says the percentage variables work "only when explicitly set".
- **Precedence.** When a `_PCT` variable and a `_TOKENS` variable are both set, the `_PCT` one wins and the `_TOKENS` ones are ignored. The header and the registry say so.
- **One message format.** Both modes print tokens and the threshold in tokens. The legacy mode lost its "N% of its window" wording; the CHANGELOG names it. The `CONTEXT BUDGET` / `CONTEXT CEILING` labels stay, since docs and tests match on them.
- **Rounding.** Percent thresholds convert to tokens with a ceiling division, so `CTX >= AT` equals master's `CTX*100 >= PCT*WINDOW` for every integer window (cases E.3, E.4).
- **Base 10.** Validated numbers pass through `10#` before arithmetic, so a leading zero no longer reads as octal. This also fixes the same pre-existing flaw for the `_PCT` variables and `KIT_CTX_WINDOW`.
- **Window file.** Only percent mode reads `<state dir>/<session_id>.window`. Its writer is the operator's dotfiles statusline, outside the kit; no kit file writes it.
- **Trade (open for the operator).** A true 200k-window model never reaches the 200k default, so it gets no notice. The CHANGELOG and registry name it, with the override to use.
