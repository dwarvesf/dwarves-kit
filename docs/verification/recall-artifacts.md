# Verification -- recall-artifacts

`session recall --artifacts` lists the claude.ai Artifacts a session published: one row per URL, version count, account, description. Replaces hand-rolled rg and python over the transcript JSONL.

| Check | Method | Result |
|-------|--------|--------|
| Real flow, session 5d13392b | `--artifacts --session 5d13392b --project ops-toolkit` | 5 artifacts; republished ones show `v2`, `v3` |
| Real flow, session 11e3d1d1 | `--artifacts --session 11e3d1d1 --project ops-toolkit` | 1 artifact, `v2` (2 distinct publishes; one tool_use id is logged twice) |
| Unit tests | `python3 -m unittest discover -s tests` in `lib/session/recall` | 68 tests OK, 7 of them `--artifacts` |
| Negative control | drop the tool_use id dedupe | the duplicated-line test fails, `v3` instead of `v2` |

## Green run
```
Command: python3 -m unittest discover -s tests   (cwd lib/session/recall)
Exit: 0
Output:
Ran 68 tests in 2.049s
OK
Verdict: PASS

Command: python3 lib/session/recall/session_recall.py --artifacts --session 5d13392b --project ops-toolkit
Exit: 0
Output (emails masked):
2026-10-26 19:05  5d13392b  series-frame.html  https://claude.ai/code/artifact/ed24d66e-bc38-40f4-9939-d4e763609d29  nnt…@gmail.com  Frame of the agentic engineering series: 13 pillars, 29 algorithm deep dives, r…
2026-10-26 18:39  5d13392b  agentic-software.html  https://claude.ai/code/artifact/c7df897e-1fea-44a2-b82f-a2771725febe  v3  nnt…@gmail.com  Lifecycle guide for building agentic software: layer-by-layer comparison with c…
2026-10-26 18:32  5d13392b  agent-owned-work.html  https://claude.ai/code/artifact/27e7b61b-d23a-45ac-b670-988240eec471  v2  nnt…@gmail.com  Step a work item through an agent-owned lifecycle (router, owner, verifier, esc…
2026-10-26 18:31  5d13392b  agents-vs-workflows.html  https://claude.ai/code/artifact/b1e8df2c-251f-4c0b-bbcd-9ef57be03f58  v2  nnt…@gmail.com  Interactive decision ladder for when a home lab job should be a function, a wor…
2026-10-25 12:36  5d13392b  memo-inline-highlights.html  https://claude.ai/code/artifact/8c709a66-2a6a-4a9a-85eb-e7827ce8ba44  nnt…@gmail.com  Review page for two new memo inline styles, a tinted highlight and accent-color…
Verdict: PASS

Command: python3 lib/session/recall/session_recall.py --artifacts --session 11e3d1d1 --project ops-toolkit
Exit: 0
Output (email masked):
2026-10-29 09:50  11e3d1d1  series-call.html  https://claude.ai/code/artifact/5ec41959-8bd6-4890-8be2-399fe452bb9a  v2  peo…@gmail.com  Sign-up page for the agentic engineering series: pick one pillar or deep dive, …
Verdict: PASS (was v3 before the tool_use id dedupe fix)
```

## Negative control
```
Command: sed -i 's/ and b\["id"\] not in seen:/:/' session_recall.py; python3 -m unittest discover -s tests
Exit: 1
Output:
FAIL: test_artifacts_duplicated_tool_use_line_counts_once
AssertionError: Lists differ: [(True, 3)] != [(True, 2)]
Ran 68 tests in 2.088s
FAILED (failures=1)
Verdict: RED as required
```
The dedupe guard was removed, the new test failed with the over-count, then `git checkout -- session_recall.py` restored it and the run went back to 68 tests OK.

## Not proven
- The account email is read from `attachment.context.userEmail` and from system-reminder text; a transcript carrying it elsewhere shows `account unknown`.
- Project-wide walks (no `--session`) stop at `--limit` rows, so `versions` there covers only the transcripts read.
- Live runs cover two sessions of one project; other transcript shapes are covered by synthetic fixtures only.
