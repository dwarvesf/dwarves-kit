# Implementation notes -- recall-peer-names

Deltas from SPEC-411. Nothing here repeats what the spec already states.

## Validation round 1: builder notes (not folded into the spec)

- JSON exposure (R4). `peer.pid` and `peer.status` reach a pasted view. Both are local labels, not credentials. Keep them in the payload, but run `status` through the same render steps as `name`. A caller should never need `pid` to address a peer: SendMessage takes the name.
- `procStart` format canary (R4). The live check in `## Verification` is the only detector for a harness change to the `procStart` format or zone. Add a small helper or test assertion that runs only when a real `~/.claude/sessions` exists. It checks that at least one entry whose pid is alive matches `ps` under `TZ=UTC LC_ALL=C`, and it skips cleanly otherwise. A silent all-rows-blank result then shows up as a named failure instead of a quiet one.

## Validation round 2: builder notes (not folded into the spec)

- Python 3.9 floor (R2). The module must run on 3.9. Do not use `isinstance(x, int | str)` at runtime, and do not use `match`. A `str | None` annotation is fine only because the module has `from __future__ import annotations`.
- Registry file count is unbounded (R2). The read loop has no cap on how many `<digits>.json` files it opens. Each one is capped at 64 KB, and a normal host holds about 10. Keep the loop simple. If a cap is ever added, count the overflow into `skipped`, so uniqueness reads unverified.
- Edge 6 is unsampled (R3). No sample shows that SendMessage accepts a user-set name with spaces or a slash (`neko desk for ops/sales`) as a bare `to`. The README should say "use the name as ListAgents shows it" rather than promise it works verbatim.
- Teaching drift (R3). `commands/wrap.md:210` teaches "`--sessions` names a peer's id, then `session recall --tail <id>`". Round 3 moved this into the spec (TASK-4, `## Touches`).

## Validation round 3: builder notes (not folded into the spec)

- TASK-3 split (R4). TASK-3 carries `render_peer`, the `render_sessions` wiring, `main`, and 15 test rows. If it runs long, split it at the seam: `render_peer` with rows 30 to 32 first, then the `main` wiring with the rest. The spec keeps one task because both halves ship in one commit anyway.
- The `kind` field (R2). Every sampled entry has `kind: "interactive"`. The spec ignores `kind`. If a non-interactive kind ever shows up (a headless or bridge session), it still gets a name when its pid start-matches. That is correct, since SendMessage can address it too. Do not filter on `kind` without a sample showing a kind that cannot receive messages.
- One bad file degrades every name (R2, R5). Any skipped registry file makes every named peer read `, name unverified`, because the skipped file's name is unknown. That is the fail-closed choice. Its cost: one corrupt file left by a crash marks every row until the file goes away. The stderr line names the count, so the operator can find and move the file. Do not soften the rule in code; raise it with the operator if it fires often.

## Validation round 4: builder notes (not folded into the spec)

- Sandboxed `ps` is unsampled (R3). Every `ps` sample came from an unsandboxed shell. Under the Claude Code Bash sandbox, `/bin/ps` may be denied or may not see other users' or other sessions' processes. Run the live check in `## Verification` from a sandboxed Bash call too, and record whether `ps` returned `alive` for the caller's own pid. If the sandbox blocks it, every entry reads `unchecked`, so no names and a `K registry entries unchecked` reason. Record that in the proof rather than calling it a pass.
- Zombies. A session that crashed but was not yet reaped shows in `ps` with its real start time, so it start-matches and gets a name. It cannot receive a message. This is rare and short-lived; SendMessage errors in that case, and Edge case 15 already says a name is a hint.
- Torn reads. A registry file read while the harness is rewriting it can parse as invalid JSON. That counts as skipped, so every name that run reads `name unverified` and stderr names `1 of M`. It clears on the next run. Do not retry inside one run.
- Non-interactive kinds. Same as the round 3 `kind` note: not filtered. A kind that cannot receive messages would need a sample before any filter.
- File-count cap. Still none (round 2 note). With the memo and the deadline, the cost that grows with the file count is the reads, each at most 64 KB.
- TASK-4 sentence count. TASK-4 touches four files. Keep each edit short: the README gains one usage block plus at most five one-sentence notes (shape and parse rule, macOS only, old transcripts, ListAgents name, global collision); `commands/wrap.md:210` changes one sentence; `docs/SYSTEM-DESIGN.md` gains one node line and one edge line.
