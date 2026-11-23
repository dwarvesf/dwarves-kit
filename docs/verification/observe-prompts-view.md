# Verification: observe-prompts-view

`session observe prompts --days N [--top K]` shows what the operator types most: the top short prompts (1 to 30 characters, whitespace-collapsed, lowercased) and the slash commands submitted as user turns, beside the same commands the model loaded through the Skill tool.

Signal for typed vs model-loaded, from inspecting real transcripts read-only: a typed command is a string user entry carrying `<command-name>`; a model load is a Skill `tool_use` plus an untagged `isMeta` expansion entry carrying `sourceToolUseID`. They are different record types, so the view counts them in separate columns. A count of the Skill `tool_use` (the `skills` view) is what inflates a command's "typed" number when read as typed.

| Check | Command | Result |
|---|---|---|
| Real flow on a synthetic transcript | `session-observe prompts --file tests/fixtures/prompts/proj/main.jsonl` | typed / sdk / model columns below |
| Real flow on live transcripts (read-only) | `session-observe prompts --days 30` | both tables print; typed, sdk and model differ per command |
| Module suite | `bash lib/session/observe/tests/smoke.sh` | `smoke: all 119 passed` |
| Report envelope | `bash lib/session/observe/tests/test-vps-report.sh` | `vps-report: all 14 passed` |
| Changed suites | `bash tests/run-all.sh --changed --time` | `run-all: all 19 suites passed` |
| Negative controls | `lib/gate/negctl.sh` x3 | Verdict: PASS x3 |

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

  # slash commands  (typed = submitted as a user turn; sdk = of those, via an SDK client such as Orca; model = Skill tool loads)
    command       typed  sdk  model
    ------------  -----  ---  -----
    /demo-skill       2    1      1
    /clear            1    1      0
    /other-skill      0    0      1
    /solo-skill       0    0      1

```

The fixture holds `/demo-skill` submitted twice (one through an SDK client), loaded by the model once through a Skill `tool_use` with its real-shape expansion entry, plus a sidechain command, a meta command and a sidechain Skill call that count nowhere.

## Negative controls

Three mutations, each turning one assertion red. Each block is the `negctl.sh` output with each run's captured output folded to its last line.

1. Skill `tool_use` branch disabled: model loads vanish, the typed-vs-model test goes red.
2. `sourceToolUseID` guard disabled: a tag-bearing expansion entry stops counting as a load. This shape is not seen in real transcripts; the control proves the guard, not the real data.
3. The `turnOrigin: sdk` test flipped to `human`: the `sdk` column changes, the same test goes red.

```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0 (green before mutation)
Output:
  smoke: all 119 passed

Mutation: edit bin/session-observe: the Skill tool_use branch in prompts_session matches a tool name that never occurs
Changed: lib/session/observe/bin/session-observe
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 118 passed, 1 FAILED

Restore: git checkout HEAD -- lib/session/observe/bin/session-observe
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0 (green before mutation)
Output:
  smoke: all 119 passed

Mutation: edit bin/session-observe: the `if e.get("sourceToolUseID"):` guard in prompts_session replaced by `if False:`
Changed: lib/session/observe/bin/session-observe
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 118 passed, 1 FAILED

Restore: git checkout HEAD -- lib/session/observe/bin/session-observe
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0 (green before mutation)
Output:
  smoke: all 119 passed

Mutation: edit bin/session-observe: the `turnOrigin == "sdk"` test in prompts_session flipped to `== "human"`
Changed: lib/session/observe/bin/session-observe
Exit: 1 (under mutation, RED expected)
Output:
  smoke: 118 passed, 1 FAILED

Restore: git checkout HEAD -- lib/session/observe/bin/session-observe
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

`git revert` the feature commits. The view, its fixtures and its tests leave together; no other view reads any of it.

## Reproduce

```bash
bash lib/session/observe/tests/smoke.sh                       # -> smoke: all 119 passed
python3 lib/session/observe/bin/session-observe prompts --days 30 --top 20   # live, read-only
```
