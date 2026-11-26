# Proof of done: PR number parse survives gh hint lines

## Green run

| Command | Exit | Verdict |
|---|---|---|
| new parse on gh output with hint lines | 0 | PASS |

Command: printf gh-output-with-hints | grep -E '/pull/[0-9]+$' | tail -1
Exit: 0
Output:
```
new parse PR number: 6174
plain output (no hints) PR number: 12
patched sites: lib/wrap/wrap-land.sh:1
lib/wrap/wrap-merge.sh:1
```

Verdict: PASS

## Negative control

Command: the old parse (tail -1) on the same output
Exit: 0
Output:
```
old parse PR number: '  - Event subscriptions are in preview and may not be enabled for your account.' -> RED (the refusal "named no PR number" seen on ops-toolkit #6174 and #6179)
```

## Rollback

Revert this PR; the two lines return to tail -1.
