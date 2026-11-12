# observe answers "how did the last kit job run go": verification

`skills/observe/SKILL.md` gains a section that tells an agent how to read the last run of the scheduled kit jobs (`memory-tidy`, `kit-weekly`, `harvest-sweep`) from the audit marker, the kit-weekly log and the harvest status, with no rerun. The description gains one sentence so the skill loads on that question. No code changes.

## Green run

- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output: `Passed: 930 / 930` and `All meta tests passed.`
- Verdict: PASS

Each read the section names, run on the Mini that hosts these jobs:

- Command: `bin/audit due | grep memory-tidy`
- Exit: 0
- Output: `memory-tidy            14d        2026-11-01   11d    -`
- Verdict: PASS

- Command: `tail -n 6 "$(bin/config data path state intel)/kit-weekly.log"`
- Exit: 0
- Output: `kit-weekly: 'kit-retro' ok` ... `kit-weekly: 'prose-rag-index' FAILED (exit 1), continuing` / `kit-weekly: done (ran=2 skipped=0 failed=1)`
- Verdict: PASS (the read answers the question; it also surfaced a live failure, below)

- Command: `python3 hooks/harvest_sweep.py --status; tail -n 2 ~/Library/Logs/dwarves-kit/<label>.log`
- Exit: 0
- Output: `.../sweep/runs/run-1794443346/report.md candidates=4 queued=2543` and `end rc=0`
- Verdict: PASS

## NEGATIVE CONTROL

Mutation: delete the new section from `skills/observe/SKILL.md` and ask the same question of the skill text (`rg -c "Scheduled kit jobs" skills/observe/SKILL.md`).

- Exit: 1 with the section removed (count 0); 0 with it present (count 1).
- Verdict: the skill answers the question only with the section; RED without it.

## Finding

`kit-weekly` job `prose-rag-index` fails every week on this host: `prose-rag: engine not installed`. The week still reports `ran=2 failed=1`. Out of scope here; the consumer installs the engine or drops the job line.

## Rollback

Revert the PR; the skill returns to fleet and spend queries only.
