# Verification: observe-prompts-view

`session observe prompts --days N [--top K]` shows what the operator types most: the top short prompts (1 to 30 characters, whitespace-collapsed, lowercased) and the slash commands typed by hand, beside the same commands the model loaded through the Skill tool. A raw count of the `<command-name>` tag mixes typed and model-loaded commands; the split signal is `sourceToolUseID`.

| Check | Command | Result |
|---|---|---|
| Real flow on a synthetic transcript | `session-observe prompts --file tests/fixtures/prompts/proj/main.jsonl` | typed vs model columns below |
| Real flow on live transcripts (read-only) | `session-observe prompts --days 30` | `/kit:wrap` typed 95 / model 75; `/logs-sweep` typed 0 / model 92 |
| Module suite | `bash lib/session/observe/tests/smoke.sh` | `smoke: all 119 passed` |
| Report envelope | `bash lib/session/observe/tests/test-vps-report.sh` | `vps-report: all 14 passed` |
| Changed suites | `bash tests/run-all.sh --changed --time` | `run-all: all 19 suites passed` |
| Negative control | `lib/gate/negctl.sh` | Verdict: PASS |

## Green run

```
Command: python3 lib/session/observe/bin/session-observe prompts --file lib/session/observe/tests/fixtures/prompts/proj/main.jsonl
Exit: 0
Output:
  # prompts  (1 transcripts, 5 prompts, 4 short <= 30 chars)
    prompt                          count  share
    ------------------------------  -----  -----
    proceed                             2    50%
    ok                                  1    25%
    aaaaaaaaaa bbbbbbbbbb cccccccc      1    25%

  # slash commands  (typed = you entered it; model = the model loaded the skill)
    command       typed  model
    ------------  -----  -----
    /demo-skill       2      1
    /clear            1      0
    /other-skill      0      1
    /solo-skill       0      1

```

The fixture holds `/demo-skill` typed twice, one Skill `tool_use` plus its `sourceToolUseID` expansion entry (one load, not two), and a sidechain command and a meta command that count nowhere.

## Negative control

Mutation: the `sourceToolUseID` branch in `prompts_session` disabled. The expansion entries then stop counting as model loads, and the typed-vs-model test goes red.

```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0 (green before mutation)
Output:
    ok: demo-skill typed 2 / model 1; clear typed 1; other and solo model-only; sidechain and meta records absent
  [115] prompts: --days drops a transcript last written 60 days ago (and its prompt + command), --days 0 keeps it
    ok: --days 30: 2 transcripts, stale prompt and command gone; no --days: 3 transcripts, both present
  [116] prompts: --top caps each table; the text view carries both tables
    ok: --top 1 keeps proceed and /demo-skill; text view has both tables
  [117] prompts stays OUT of report (the operator's own words must not ride report --json to vps-mon)
    ok: report text and json carry no prompts section
  [118] prompts: a non-dict line and a non-dict message do not crash; the one valid string prompt is counted
    ok: nondict-edge: 1 plain prompt counted, bad line and bad messages skipped
  smoke: all 119 passed

Mutation: python3 -c "p='lib/session/observe/bin/session-observe';s=open(p).read();a='if e.get(\"sourceToolUseID\"):';assert a in s;open(p,'w').write(s.replace(a,'if False:',1))"
Changed: lib/session/observe/bin/session-observe
Exit: 1 (under mutation, RED expected)
Output:
  }
  [115] prompts: --days drops a transcript last written 60 days ago (and its prompt + command), --days 0 keeps it
    ok: --days 30: 2 transcripts, stale prompt and command gone; no --days: 3 transcripts, both present
  [116] prompts: --top caps each table; the text view carries both tables
    ok: --top 1 keeps proceed and /demo-skill; text view has both tables
  [117] prompts stays OUT of report (the operator's own words must not ride report --json to vps-mon)
    ok: report text and json carry no prompts section
  [118] prompts: a non-dict line and a non-dict message do not crash; the one valid string prompt is counted
    ok: nondict-edge: 1 plain prompt counted, bad line and bad messages skipped
  smoke: 118 passed, 1 FAILED

Restore: git checkout HEAD -- lib/session/observe/bin/session-observe
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

`git revert` the feature commit. The view, its fixtures and its tests leave together; no other view reads any of it.

## Reproduce

```bash
bash lib/session/observe/tests/smoke.sh                       # -> smoke: all 119 passed
python3 lib/session/observe/bin/session-observe prompts --days 30 --top 20   # live, read-only
```
