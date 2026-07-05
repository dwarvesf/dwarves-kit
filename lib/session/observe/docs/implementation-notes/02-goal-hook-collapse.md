# Implementation notes: collapse /goal Stop-hook rows (ID-229)

Deltas / non-obvious decisions only. The what + proof live in `docs/proof-of-done.md` (ID-229 section).

## 2026-06-28 14:00 first-two-token script guard (not a position/length cutoff)
- Context: a `/goal` Stop hook's `command` is the long goal prose; the old `hook_label()` script-regex scanned the WHOLE command, so a `*.sh`/`*.py` mentioned in the prose mislabelled the goal as that file.
- Decision: restrict the script-filename match to `" ".join(toks[:2])` (the executable, optionally after a runner like `bash`/`node`).
- Why: an earlier idea (match only within `command[:120]`) breaks real hooks whose script lives behind a long absolute path (`node /Users/.../experiments/.../x.js` can push `.js` past char 120). Token position is path-length-independent: real hooks name the script in token 1 or 2; prose never does.
- Alternatives considered: char-offset cutoff (rejected: breaks long-path hooks); detecting "is this prose" via word count (rejected: fuzzier than the token rule, no added safety).
- Impact: `hook_label()` only. Empirically (all 116 distinct real hook commands) every real script hook keeps its basename; phantom rows (build.sh/lib.sh/marked.js/freeze.py/lane-classify.sh/...) that were goal-prose matches disappear.

## 2026-06-28 14:05 `len(c) > 120` as the long-inline trigger
- Decision: hash a command into `inline-echo:<hash>` when `c.startswith("echo") or len(c) > 120`.
- Why: real /goal prose is 170-3780 chars; the only legit non-script, non-echo hooks observed are short (the `"${CMUX...}" hooks claude stop` line at ~50 chars, pointer-style `@.claude/last-goal.md` at ~20). Diffing old-vs-new labels over all 116 real commands: 93 change, and ALL 93 are >120 chars (0 short commands change), so 120 cleanly separates prose from real short commands without touching any legit hook.
- Impact: the threshold is a heuristic, not a contract. If a future legit single-line hook exceeds 120 chars without naming its script early, it would be hashed; that matches the task's intent ("any other long inline Stop hook" should also collapse).

## 2026-06-28 14:10 many inline-echo rows is the intended outcome, not over-fragmentation
- The fix turns ~13 phantom first-word/mislabelled goal rows into ~94 stable `inline-echo:<hash>` rows on 60-day real data. That is correct: each UNIQUE goal command is genuinely a distinct inline hook and gets exactly one row (its N firings collapse into it). The sample column carries the goal text so rows stay distinguishable. The bug was conflation (distinct goals merged under "Drive") + mislabel (goals shown as script files), not row count.
