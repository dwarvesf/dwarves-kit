# Implementation notes: recall-session-tail (SPEC-309)

Delta from the spec only.

| Kind | Note |
|---|---|
| Decision | Home moved from a new `session tail` verb (the wrap report's first framing) to a `--tail` flag on `session-recall`, after `precedent find` named that tool and its helpers. |
| Decision | Lane is `full`: the classifier returns `full` for any change under `lib/`, even this read-only flag. |
