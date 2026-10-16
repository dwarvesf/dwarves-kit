# Retro: harvest runs as bash plus jq (SPEC-409)
Date: 2026-10-16
Sprint: one session, last of the four remaining Python hook ports

Answers below were drafted by the lead from the session record, not collected one question at a time.

## Metrics
- Goldens: 171 cases generated from the Python before the port, each with the exact prompt and its byte count
- Real transcripts: see the verification record
- Fresh review rounds: none; the proof is the corpus, the real-data replay, and the negative controls
- Negative controls: 9

## What worked
- Reusing the previous ports' parts whole: the transcript walk, the bracket scan, the shlex splitter, the detach, the helpers. The port's new logic was the dedup, the ledger lock, and the stop-trigger counters.
- Splitting `harvest.py` instead of deleting it. The sweep keeps the library it imported, and no file named like a hook is Python.
- Rerunning the corpus after each class of fix. One awk idiom accounted for 77 of the 171 first failures.

## What hurt
- A worker ran out of context with the port at 94 of 171 and no records. The first red run named one bug (`NR == FNR` against an empty file) that explained most of it; reading the shared awk program first would have saved the hour.
- The goldens carried two things that could never match: the epoch of the run that generated them, and the scratch path inside a Python traceback. Both only show once the corpus runs a second time.
- Two suites still imported `hooks/harvest.py` as a module. A green parity corpus does not cover the suites that name the old file.

## Action items
- None for the operator. Porting `hooks/harvest_sweep.py` (a 2,100-line scheduled job, not a hook) is a separate decision.
