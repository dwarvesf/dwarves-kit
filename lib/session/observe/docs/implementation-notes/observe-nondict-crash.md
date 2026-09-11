# Implementation notes: transcript readers crash on a non-object JSONL line

Delta from the bug report only.

## 2026-09-10 Root fix lands in the shared parser, not per caller

Context: a transcript line that decodes to valid JSON but not an object (e.g. `["x"]`) crashed `session-observe cost`/`report` and `session-semantic` with `AttributeError: 'list' object has no attribute 'get'`. `lib/session/parse_transcript.py` `iter_entries()` is the shared parser session-observe, session-semantic, session-recall, and session-intel all route through; its docstring and `Iterator[dict]` annotation already declared the contract as one JSON *object* per line, and every caller reads an entry with `.get(...)`.
Decision: `iter_entries()` (`lib/session/parse_transcript.py:73-75`) now skips a decoded value that is not a dict, the same way it already skips a `json.JSONDecodeError` line. Docstring updated to say so explicitly.
Why: all four callers assume dict entries; a non-object line is exactly as unusable to them as a malformed one, so the fix belongs where the untrusted-input boundary already lives, once, instead of an `isinstance` guard duplicated in each caller's read loop.
Alternatives: guard per caller (rejected, this bug had already recurred as burn_collect's own `isinstance(entry, dict)` guard in session-observe; the recurrence is the evidence the guard belongs upstream).
Impact: no caller's output changes for valid input, verified by negative control (reverting only this fix reproduces the crash and the new smoke cases fail).
Open questions: none.

## 2026-09-10 Second-level shape: a non-dict message/usage must not crash either

Context: even with the top-level fix, a *valid object* line whose `message` field is itself non-dict (e.g. `"message": "oops"`) still crashed `collect()` in session-observe (`msg.get("usage")`/`.get("content")` on a string) and `session-semantic`'s `collect_prompts()` (`(e.get("message") or {}).get("content")`).
Decision: `blocks()` and `collect()` in `lib/session/observe/bin/session-observe`, and `collect_prompts()` in `lib/session/observe/bin/session-semantic`, now check `isinstance(msg, dict)` before calling `.get()` on it, matching the pattern `burn_collect()` already used for `entry`/`msg`/`usage`.
Why: the transcript schema is untrusted input at every nesting level, not just the top level; the burn view's existing guards were the precedent to extend, not a one-off.
Alternatives: none considered; this is the same class of bug one level deeper.
Impact: no caller's output changes for valid input. `session-recall`'s own `_role`/`searchable_text`/`opening_ask` have the same latent non-dict-message shape but were left untouched (out of the reported bug's scope); its `load()` was covered for the top-level fix only.
Open questions: whether session-recall's second-level message-shape paths should get the same guard in a follow-up.

## 2026-09-11 session-recall gets the same second-level guard

Context: the open question above.
Decision: `_msg(entry)` in `lib/session/recall/session_recall.py` returns the message when it is a dict and `{}` otherwise; `_role`, `searchable_text` and `opening_ask` all read through it.
Why: one helper instead of three inline checks, so the untrusted-shape rule lives once per module, matching how `iter_entries()` owns the top-level case.
Impact: no output change for valid input; proof in `docs/verification/recall-message-shape.md`.
Open questions: none.
