# Implementation notes -- recall-peer-names

Deltas from SPEC-411. Nothing here repeats what the spec already states.

## Validation round 1: builder notes (not folded into the spec)

- JSON exposure (R4). `peer.pid` and `peer.status` reach a pasted view. Both are local labels, not credentials. Keep them in the payload, but run `status` through the same render steps as `name`. A caller should never need `pid` to address a peer: SendMessage takes the name.
- `procStart` format canary (R4). The live check in `## Verification` is the only detector for a harness change to the `procStart` format or zone. Add a small helper or test assertion that runs only when a real `~/.claude/sessions` exists. It checks that at least one entry whose pid is alive matches `ps` under `TZ=UTC LC_ALL=C`, and it skips cleanly otherwise. A silent all-rows-blank result then shows up as a named failure instead of a quiet one.

## Validation round 2: builder notes (not folded into the spec)

- Python 3.9 floor (R2). The module must run on 3.9. Do not use `isinstance(x, int | str)` at runtime, and do not use `match`. A `str | None` annotation is fine only because the module has `from __future__ import annotations`.
- Registry file count is unbounded (R2). The read loop has no cap on how many `<digits>.json` files it opens. Each one is capped at 64 KB, and a normal host holds about 10. Keep the loop simple. If a cap is ever added, count the overflow into `skipped`, so uniqueness reads unverified.
- Edge 6 is unsampled (R3). No sample shows that SendMessage accepts a user-set name with spaces or a slash (`neko desk for ops/sales`) as a bare `to`. The README should say "use the name as ListAgents shows it" rather than promise it works verbatim.
- Teaching drift (R3). `commands/wrap.md:210` teaches "`--sessions` names a peer's id, then `session recall --tail <id>`". After this ships, `--sessions` also names the peer. Update that sentence in the same PR, or flag it in the PR body for the next wrap pass.
