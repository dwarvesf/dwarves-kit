# Proof of done: ship-gate blocks fixture git identities

## What changed

Commit `f630e940` on PR #930 was authored `han <x@x>`. The squash merge carried `Co-authored-by: han <x@x>`, so GitHub listed an unrelated account as a contributor. Commits `32ae9b2f` and `e7adc2a7` carried `tester <t@t.dev>`, the identity several test suites set in temp repos. The `x@x` source is not in the tree; its cause is unknown.

`ship_rule_identities` in `lib/gate/ship-rules.sh` scans `base..head` before a push (repos with an `origin` remote only). It blocks when an author, committer or `Co-authored-by` email has a no-dot domain, is `t@t.dev` or `test@example.com`, or uses an `example.*`, `.test`, `.invalid`, `.localhost` or `.local` domain. Real, GitHub noreply and bot noreply addresses pass. `hooks/ship-gate.sh` calls it right after the merge base is known.

## Gate table

| Claim | Evidence |
|---|---|
| author `x@x`, `t@t.dev`, `foo@example.com` blocked | run table |
| committer `x@x` blocked | run table |
| `Co-authored-by: tester <t@t.dev>` blocked | run table |
| noreply author with a Devin bot co-author passes | run table |
| a real address passes | run table |
| the check is load-bearing | negative control |

## Run table

```
Command: bash tests/test-ship-gate-identities.sh
Exit: 0
ok - author x@x blocked
ok - author t@t.dev blocked
ok - author foo@example.com blocked
ok - committer x@x blocked
ok - co-author t@t.dev blocked
ok - noreply author + devin bot co-author ok
ok - real address ok
pass=7 fail=0
Verdict: PASS
```

## Negative control

With the `ship_rule_identities` call in `hooks/ship-gate.sh` replaced by a no-op, the same command exits 1:

```
Command: bash tests/test-ship-gate-identities.sh   (check disabled)
Exit: 1
NOT ok - author x@x blocked (want exit 2)
NOT ok - author t@t.dev blocked (want exit 2)
NOT ok - author foo@example.com blocked (want exit 2)
NOT ok - committer x@x blocked (want exit 2)
NOT ok - co-author t@t.dev blocked (want exit 2)
ok - noreply author + devin bot co-author ok
ok - real address ok
pass=2 fail=5
Verdict: RED as expected; restored, then green as above
```

The existing ship-gate suites (`fail-closed`, `profiles`, `impl-notes`, `coverage-map`, `gate-opt-in`, `gate-opt-out`) exit 0 with the change.
