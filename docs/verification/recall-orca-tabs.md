# Verification -- recall-orca-tabs

`session recall --orca [--json] [--max-chars N]` lists every Orca agent tab (workspace, tab name, state, updated time) with the full final reply from its Claude transcript, found through Orca's own journal db, with a text-needle fallback.

## Green run
```
Command: cd lib/session/recall && python3 -m unittest discover -s tests
Exit: 0
Output:
Ran 83 tests in 3.785s
OK

Command: bash tests/test-session-recall.sh
Exit: 0
Output:
PASS: session-recall

Command: ./lib/session/recall/bin/session-recall --orca --json   (live Orca, 29 tabs; only counts shown)
Exit: 0
Output:
Counter({'journal': 27, 'needle': 1, 'self': 1})
Verdict: green. 9 new TestOrca cases (fake orca exe, fixture ps JSON, built journal db, fixture transcripts); 74 prior tests unchanged.
```

## Negative control
```
Command: mutate collect_orca so the calling session is unknown (self_ids, self_orca = set(), ""), then
         cd lib/session/recall && python3 -m unittest tests.test_recall.TestOrca
Exit: 1
Output:
FAIL: test_cli_json_and_text (tests.test_recall.TestOrca.test_cli_json_and_text)
FAIL: test_needle_fallback_skips_self_and_subagent_transcripts (tests.test_recall.TestOrca.test_needle_fallback_skips_self_and_subagent_transcripts)
FAIL: test_self_tab_excluded_by_orca_session_id (tests.test_recall.TestOrca.test_self_tab_excluded_by_orca_session_id)
FAIL: test_self_tab_is_excluded_and_shows_preview (tests.test_recall.TestOrca.test_self_tab_is_excluded_and_shows_preview)
Ran 9 tests in 1.448s
FAILED (failures=4)
Verdict: red as required. The mutation was reverted (byte-identical to the pre-mutation copy, `cmp` clean) and the green run above was captured after the restore.
```

## Not proven
- The needle fallback ran live on one non-structured tab only; its correctness there was not cross-checked by hand.
- Orca's journal schema (`agent_session_records.record_json.providerHandleChain`) is an Orca internal, not a documented API; an Orca upgrade that renames it degrades every tab to the needle fallback.
- Output was not run through a secret scanner beyond the shared redaction regexes.
