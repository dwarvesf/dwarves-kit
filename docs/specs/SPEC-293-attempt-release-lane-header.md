# SPEC-293: dispatch releases settled attempt records, and the ship-gate reads a bold Lane header

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Source:** two follow-ups left by SPEC-290 and SPEC-289 in this session. **Board:** ID-885. **Proof:** `docs/verification/attempt-release-lane-header.md`.

## Problem

Two leaks, one PR.

SPEC-290 added `lib/goal/attempt-state.sh` and wired most of its verbs into `commands/dispatch.md`.
Step 6 never calls `release`, so every dispatched task leaves a `<task>.task` file behind in
`kit-attempts/` and the store grows for the life of the checkout.

`hooks/ship-gate.sh` parses a spec's lane with `grep -m1 -iE '^Lane:'`. A worker this session wrote
`**Lane**: full`, matching the bold style the surrounding header block uses, and the push was
BLOCKED with "Spec has no 'Lane:' header". The spec declared its lane; the parser could not see it.
Two other files parse the same header with the same expression, so a fix in one alone would let
them disagree.

## Solution

**Release.** `commands/dispatch.md` Step 6 calls `bash lib/goal/attempt-state.sh release <slug>` as
the first line of the per-goal GC sequence, once the task is settled: its result committed and
merged, or the task abandoned as lost. `release` deletes the record whole, attempt history
included, so Step 6 states plainly that nothing survives it and that the durable trail is the
merged branch and the run ledger.

**Bold header.** The three parsers (`hooks/ship-gate.sh`, `commands/ship.md`,
`commands/mega.md`) accept `Lane:`, `**Lane**:` and `**Lane:**` through one grep plus one sed:

```
grep -m1 -iE '^(\*\*)?Lane(\*\*)?:'
sed -E 's/^(\*\*)?[Ll]ane(\*\*)?:(\*\*)?[[:space:]]*//; s/[[:space:]].*$//'
```

A leading `- ` list marker is refused on purpose. Specs use `- **Lane:** ...` inside prose
bullets, so accepting the marker would parse a sentence fragment as the lane, which is worse
than the block it would prevent. Plain `Lane: <lane>` stays canonical, and `commands/spec.md`
now emits that plain line in the spec template it writes, which it did not before.

The BLOCKED message is unchanged. It already names the plain form, which is the form an author
should write.

## Verification

```
bash tests/run-all.sh
```

`tests/test-ship-gate-fail-closed.sh` covers the three accepted header shapes and keeps the
missing-header BLOCKED case. `tests/test-meta.sh` pins the `attempt-state.sh release` call in
`commands/dispatch.md`. `tests/test-attempt-state.sh` case 21 already covers the `release` verb
itself.

## After state

A dispatch run that converges leaves no attempt records behind. A spec whose Lane header is bold
ships instead of blocking, and the three parsers agree on what a lane header looks like.
