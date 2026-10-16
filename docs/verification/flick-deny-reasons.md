# Verification: flick-deny-reasons

`decide.jsonl` now names the egress layer that denied a pair (`cand`, `deny_word`, `hit_not_public`, `word_gate`) instead of the catch-all `guard`, with no candidate text. The SPEC-381 exit criterion measures eligible pairs plus the smoke set, with a 2026-12-15 time box. The egress guard is unchanged.

## Green run
```
Command: bash tests/test-flick.sh; bash tests/test-wrap-flick.sh
Exit: 0
Output:
  == denial reasons: each layer logs its own tag, never text ==
    ok: reasons batch: one sent, four denied
    ok: slug shape layer logs cand
    ok: deny_words layer logs deny_word
    ok: non-public hit layer logs hit_not_public
    ok: word gate layer logs word_gate
    ok: the sent row carries no reason
    ok: no denied candidate or hit text reaches the log
  flick: 346 passed, 0 failed
  test-wrap-flick: all 12 passed
Verdict: PASS (an earlier run under host load failed one clef timing assertion, 4518 ms against about 3000 ms; the re-run passed)
```

Real primary flow, live Jev, operator config, scratch log dir (`DWARVES_KIT_LOG_DIR`):

```
Command: printf 'backlog-flip-script board enhance\ncf-style-helper some-private-tool new\nzorbix-helper board new\n' | DWARVES_KIT_LOG_DIR=<scratch> bash bin/wrap flick-7b
Exit: 0
Output:
  flick wrap-7b: 1 answered, 2 denied, 0 error (jev)
  decide.jsonl: index 0 sent; index 1 reason=hit_not_public; index 2 reason=word_gate
Verdict: PASS
```

## Negative control
Command: bash tests/test-flick.sh (sections up to the new block)
Exit: 0 (green before mutation)
Output:
  ok: deny_words layer logs deny_word

Mutation: sed -i '' 's/GUARD_WHY=deny_word; return 1/GUARD_WHY=guard; return 1/' lib/decide/flick.sh
Changed: lib/decide/flick.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL: deny_words layer logs deny_word (got guard)

Restored with `git checkout -- lib/decide/flick.sh`; the tree was clean afterwards.
