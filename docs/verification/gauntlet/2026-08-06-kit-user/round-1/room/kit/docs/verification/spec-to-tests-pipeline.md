# Proof of done: spec-to-tests pipeline (SPEC-203/204)

The test-generation loop shipped by this branch: spec-less test-plan entry (Step 0), the
severity-aware `test-plan-review-team` revise loop, `/kit:test-write`, and the `test-writer`
agent. Dogfood target: `lib/goal/goal.sh`, a live dispatcher with zero prior spec or test
coverage; the loop reverse-engineered 11 acceptance criteria (SPEC-204) and materialized
`tests/test-goal-dispatch.sh` from the reviewed matrix.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | Materialized suite green | `bash tests/test-goal-dispatch.sh` | 0 | PASS (20/20) |
| 2 | test-write dispatch contract | `bash tests/test-test-writer-contract.sh` | 0 | PASS (11/11) |
| 3 | Negative control | break `goal.sh` draft routing (line 22), re-run suite | non-zero | RED (16/20, 4 FAIL) |
| 4 | Restore | `git checkout lib/goal/goal.sh`, re-run suite | 0 | PASS (20/20) |
| 5 | Meta suite post-merge with master | `bash tests/test-meta.sh` | 0 | PASS (732/732) |

## Run detail

Run 3 (the negative control) rewrote the `draft|drafts)` dispatch line in `lib/goal/goal.sh`
to exec a wrong target. Exactly the 4 draft-routing assertions went RED; the other 16 stayed
green, confirming the suite pins the behavior it claims to pin, not incidental state. Run 4
restored the file from the index and the suite returned to 20/20.

## Reproduce

```
bash tests/test-goal-dispatch.sh
bash tests/test-test-writer-contract.sh
# negative control: edit lib/goal/goal.sh line 22 (draft routing), re-run, expect 4 FAIL
git checkout lib/goal/goal.sh
```

Full narrative: SPEC-203 close-out + SPEC-204 `## Test plan critique` (two genuine critique
cycles, the second severity-aware). Known gap recorded at dogfood time: `agents/test-writer.md`
was not loadable as a registered subagent_type in the building session itself (frozen
plugin-snapshot loading, a kit limitation, not a defect in this spec).
