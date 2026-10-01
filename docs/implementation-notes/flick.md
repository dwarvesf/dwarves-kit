# Impl notes: flick (SPEC-381)

Delta from the spec. Only off-spec calls and review warnings live here. The builder reads this before TASK-1.

## Warnings from validation round 1 (tests or the builder catch these)

| Warning | Call |
|---|---|
| Log rotation | `decide.jsonl` is append-only and unrotated. One line per question and one call per wrap keeps growth small. Add rotation when the file passes a size the operator notices. |
| Token rotation or expiry | A rotated or expired token shows as repeated `http_401` in the log. Add a count of consecutive `http_401` to the wrap FYI row only if it happens. |
| Recorded live Jev sample | The spec has no live sample. When a token exists, TASK-12 records one real response (probabilities only, no token) in this file and compares it with the Grounding shape. |
| Runner tool availability | `curl`, `jq` and `python3` on the hosted images are believed present and unverified. The test skips with a printed reason when one is missing. No workflow change. |
| Approaches considered | Two alternatives were not built. A Haiku subagent arm would answer in seconds at a small cost and needs no egress, so it is the fair comparison arm for the shadow log. Doing nothing keeps the 20 to 60 s judgment. The operator chose the API path to measure it. |
| `mode = "decide"` has no consumer | `wrap-7b` runs as shadow only, so `decide` mode returns answers nothing reads. It exists for a later point. |

## Entries

(none yet; the zero-deviation line goes here when the build closes)
