# Implementation notes: context-budget absolute token thresholds

No spec; the task brief is the contract. This note holds only the decisions the brief left open.

- **Mode switch.** Percent mode turns on when either `KIT_CTX_WARN_PCT` or `KIT_CTX_STRONG_PCT` is non-empty; the unset one keeps its old default (65 / 70). `KIT_CTX_WINDOW` alone does not switch modes, because the brief says the percentage variables work "only when explicitly set".
- **Precedence.** When a `_PCT` variable and a `_TOKENS` variable are both set, the `_PCT` one wins and the `_TOKENS` ones are ignored. The header and the registry say so.
- **One message format.** Both modes print tokens and the threshold in tokens. The legacy mode lost its "N% of its window" wording; the CHANGELOG names it. The `CONTEXT BUDGET` / `CONTEXT CEILING` labels stay, since docs and tests match on them.
- **Rounding.** Percent thresholds convert to tokens with a ceiling division, so `CTX >= AT` equals master's `CTX*100 >= PCT*WINDOW` for every integer window (cases E.3, E.4).
- **Base 10.** Validated numbers pass through `10#` before arithmetic, so a leading zero no longer reads as octal. This also fixes the same pre-existing flaw for the `_PCT` variables and `KIT_CTX_WINDOW`.
- **Window file.** Only percent mode reads `<state dir>/<session_id>.window`. Its writer is the operator's dotfiles statusline, outside the kit; no kit file writes it.
- **Trade (open for the operator).** A true 200k-window model never reaches the 200k default, so it gets no notice. The CHANGELOG and registry name it, with the override to use.
