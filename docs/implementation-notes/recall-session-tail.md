# Implementation notes: recall-session-tail (SPEC-309)

Delta from the spec only.

| Kind | Note |
|---|---|
| Decision | Home moved from a new `session tail` verb (the wrap report's first framing) to a `--tail` flag on `session-recall`, after `precedent find` named that tool and its helpers. |
| Decision | Lane is `full`: the classifier returns `full` for any change under `lib/`, even this read-only flag. |
| Deviation | Declined design-critique finding 7 (share one text-extraction helper with `opening_ask`): the new drop rules would change `--sessions` output, which AC6 pins byte-identical. Tail gets its own filter. |
| Deferred | `SECRET_SHAPE_RE` misses `github_pat_`, `gho_`, `sk_live_`, JWTs, `API_KEY=`, Bearer tokens and PEM bodies (design-critique probe). The pattern is byte-shared with `lib/precedent/inventory.py`; widening it is a separate change. |
| Decision | `--limit` validation (int of 1 or more, else exit 2) applies to every mode, not only `--tail`: the old parser threw a traceback on `abc`. |
