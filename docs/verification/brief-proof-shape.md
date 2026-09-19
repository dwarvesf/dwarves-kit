# Verification -- brief-proof-shape

Doc-only change: the worker-facing contract (`docs/patterns/worker-brief.md`, the
`/kit:dispatch` worker prompt in `commands/dispatch.md`, the goal-file proof
expectation in `commands/mega.md`, and the stateful bullet in `commands/execute.md`)
now states the LITERAL markers the ship-gate greps, so a dispatched worker no longer
produces a results table the gate reads past.

## What the gate actually greps (the exact check)

`lib/gate/proof-ledger.sh check` (`stateful` leg, lines 293 and 320-322):

```bash
grep -qiE 'rollback|\[UNAVAILABLE' "$p" && { grep -qE 'Command:|Exit:' "$p" || _has_committed_image "$p" "$root"; }
```

`behavioral` leg (lines 290-291, 315-317): `grep -qi 'NEGATIVE CONTROL'` AND
`grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS'`, with the LAST
`Verdict:` line forbidden from being `INCONCLUSIVE`/`FAIL`.

**Heading-vs-substring note (brief vs gate, no disagreement):** the gate greps the
substrings `Command:`, `Exit:`, `rollback`/`[UNAVAILABLE`, `NEGATIVE CONTROL` -- it
never reads markdown headings. `## Recorded run` (what the lead hand-appended) and
`## Green run` (what `proof-gate.sh skeleton` emits) are equivalent to the gate; the
brief prescribes `## Recorded run` / `## Rollback` as the conventional headings so
the doc also reads correctly to a human, and the word `rollback` inside the section
is what satisfies the grep. `## Not proven` is a convention the gate does not check.

## Recorded run

The check was exercised standalone against a scratch git repo (`/tmp/kit-proof-shape-check-*`)
whose branch diff classifies `stateful` (a `deploy/rollout.sh` change), with four
proof-doc shapes:

Command: `bash lib/gate/proof-ledger.sh check <scratch-repo> main`   # no proof doc
Exit: 1  (BLOCKED: proof of done ... 'stateful' change)

Command: `bash lib/gate/proof-ledger.sh check <scratch-repo> main`   # results-table doc:
                                                                     # `| Check | Command | Exit | Result |`
Exit: 1  (BLOCKED -- reproduces the five-worker rejection; the table greps past)

Command: `bash lib/gate/proof-ledger.sh check <scratch-repo> main`   # new shape:
                                                                     # `## Recorded run` + `Command:`/`Exit:`/`Verdict:` + `## Rollback`
Exit: 0

Command: `bash lib/gate/proof-ledger.sh check <scratch-repo> main`   # run lines present,
                                                                     # no `rollback`/`[UNAVAILABLE` anywhere
Exit: 1  (BLOCKED -- the rollback marker is load-bearing, not decoration)

And on this branch (docs-only diff, so `inert` -- no ritual owed; this file is the
task-requested record, not a gate requirement):

Command: `bash lib/gate/proof-ledger.sh classify . master`
Exit: 0  -> prints `inert`

Command: `bash lib/gate/proof-ledger.sh check . master`
Exit: 0

Adjacent finding, fixed in-branch: `docs/FEATURES.md` had drifted on master
(`feature-registry.sh check` rc=1, stale spec/test reference counts). Because this
branch edits `commands/*.md` -- registry inputs -- `hooks/ship-gate.sh`'s freshness
leg would have refused the push, so the regenerated projection rides this commit
(the gate's own prescribed fix).

## Rollback

Docs-only diff; rollback is `git revert` of this branch's commit (or dropping the
branch). No code, config, hook, or gate behavior changed -- the check itself was
read, never edited.

## Not proven

- No dispatched worker was re-run against the new wording; the check was exercised
  directly in a scratch repo instead.
- The `commands/dispatch.md` prompt is a template read by the dispatching lead;
  whether a worker now writes the right shape is a behavioral claim only a live
  dispatch can prove.
