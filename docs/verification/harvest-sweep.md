# Verification log

## T1 shared stager. Factor `_stage_candidates` out of `_harvest_payload` in `hooks/harvest.py`. Files: `hooks/harvest.py`, `tests/test-hooks.sh`. AC: every existing harvest test passes unchanged.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 9/9, foldin 97/97; negctl flock removal red->green PASS
  ```
- Verdict: PASS

## T2 claude adapter. Lead plus subagents interleaved by timestamp, the 60/40 render budget, the `seen{}` delta key, self-harvest drop, min-messages skip. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a lead fixture, two subagent fixtures. AC: the claude parts of AC1.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 47/47, foldin 97/97; negctl 60/40 collapse red->green PASS
  ```
- Verdict: PASS

## T3 devin adapter. Read-only open, `working_directory` as cwd, `hidden` skip, main-chain walk with fallback, `system` drop, source failure `STATE` row and `source_fail`. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, `tests/fixtures/harvest-sweep/make-devin-db.sh`. AC: the devin parts of AC1 and AC26; AC14.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 82/82, foldin 97/97; negctl system rows kept red->green PASS
  ```
- Verdict: PASS

## T4 launch-record attribution. Brief-path match, nearest `ts`, null on no match. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a `launches.jsonl` fixture. AC: the attribution part of AC1.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 97/97, foldin 97/97; negctl first-match attribution red->green PASS
  ```
- Verdict: PASS

## T5a selection. hwm, `done{}`, `seen{}`, quiet window, scan cap, `max_sessions_per_run`, trivial and filtered sessions marked done outside the cap, oldest-first order, atomic writes. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC6, AC25, the `seen{}` part of AC20.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 146/146, foldin 97/97; negctl filtered-not-done, 24h unread drop, seen pruned with done: all red->green PASS (first commit a88411b1, run-wide cap fix 9b1cc057)
  ```
- Verdict: PASS

## T5b lag and drift. Per-source lag, `lag_runs`, the all-trivial drift rule, `--since`. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC20, AC21.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 172/172, foldin 97/97; negctl lag_runs never incremented and never reset: both red->green PASS
  ```
- Verdict: PASS

## T6 extractor call. `(ok, stdout, stderr)`, `extract_json_object`, the default flags (`--tools ""`, `--strict-mcp-config`, `--no-session-persistence`), extractor cwd and child env, the raw output cache with atomic writes, its modes, and the unparseable-file rule, the 100-slug prompt cap. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a stub extractor fixture. AC: the argv part of AC22; AC24; AC30.
- Command: `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  sweep 226/226, foldin 97/97; negctl drop --tools "" and drop chmod 0700: both red->green PASS
  ```
- Verdict: PASS
