# Implementation notes -- recall-peer-names

Deltas from SPEC-411. Nothing here repeats what the spec already states.

## Validation round 1: builder notes (not folded into the spec)

- JSON exposure (R4). `peer.pid` and `peer.status` reach a pasted view. Both are local labels, not credentials. Keep them in the payload, but run `status` through the same render steps as `name`. A caller should never need `pid` to address a peer: SendMessage takes the name.
- `procStart` format canary (R4). The live check in `## Verification` is the only detector for a harness change to the `procStart` format or zone. Add a small helper or test assertion that runs only when a real `~/.claude/sessions` exists. It checks that at least one entry whose pid is alive matches `ps` under `TZ=UTC LC_ALL=C`, and it skips cleanly otherwise. A silent all-rows-blank result then shows up as a named failure instead of a quiet one.
