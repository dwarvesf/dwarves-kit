# Verification -- design-shape-line

`/kit:design` Step 1 now asks for a `Shape:` line (the problem without the system's names -> field -> standard tool) beside the one-sentence restatement, before approaches are compared. No new step, question or ledger record.

## Green run
The probe hands a model the command file plus a toy problem and asks for its Step 1 output only. Script:

```bash shape-probe.sh
#!/bin/bash
# Behavioral probe: give a model /kit:design (one version) plus a toy problem,
# ask for its Step 1 output only, and count Shape lines.
# Usage: shape-probe.sh <path to design.md>
set -u
CMD_FILE="$1"
PROBLEM='Our nightly backup job sometimes runs twice when the scheduler retries after a timeout, and then the second run overwrites the first archive with a partial one.'
PROMPT="You are running the command below in a non-interactive dry run. There is no brief and no code; the problem is: ${PROBLEM}
Produce ONLY what Step 1 (Orient) tells you to present to the user, as plain text. Do not call tools. Do not go past Step 1.

----- COMMAND -----
$(cat "$CMD_FILE")"
out=$(cd "$(mktemp -d)" && printf '%s' "$PROMPT" | claude -p --model sonnet --disallowedTools "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch,Agent" 2>/dev/null)
printf '%s\n' "$out"
echo "---"
echo "shape_lines=$(printf '%s\n' "$out" | grep -c 'Shape:')"
```

```
Command: bash shape-probe.sh commands/design.md   (this branch)
Exit: 0
Output:
Problem: When the scheduler retries a timed-out nightly backup, the second run can overwrite the first archive with a partial one.

Shape: a retry after an ambiguous timeout repeats a write, and incomplete output replaces an earlier result -> distributed systems -> idempotent operations with atomic publish

Slug: backup-retry-overwrite. I have no brief and no code, and I did not check the shape catalog.

Do the problem and the shape both match what you see, or what would you correct?

---
shape_lines=1
Verdict: PASS, the Step 1 output carries one Shape line naming a field and a standard tool.
```

## Negative control
```
Command: bash shape-probe.sh design-master.md   (git show origin/master:commands/design.md)
Exit: 0
Output:
Slug: nightly-backup-retry-overwrite

Brief: none exists and there is no code to read, so Step 5 will create docs/briefs/DECISION-BRIEF-nightly-backup-retry-overwrite.md.

Problem: When the scheduler retries a timed-out nightly backup, a second run can overwrite the first archive with a partial one.

Is this the problem you want to solve? Reply yes, or correct the sentence.

---
shape_lines=0
Verdict: RED as expected, master's Step 1 gives the restatement with no Shape line.
```
The branch file was untouched by the control; only the master copy was probed.

## Affected tests
```
Command: bin/test-affected --base origin/master
Exit: 0
Output:
PASS tests/test-design-record.sh
PASS tests/test-install-plugin-detect.sh
PASS tests/test-meta-agents-commands.sh
PASS tests/test-meta-docs-registry.sh
PASS tests/test-meta-plugin-hooks.sh
PASS tests/test-meta-review-verifiers.sh
PASS tests/test-meta-vmodel-dispatch.sh
test-affected: 7 selected, 7 pass, 0 cached, 0 fail, 0 timeout, 0 uncovered
Verdict: PASS
```

Both Output blocks omit one trailing line, a sign-off the operator's global instructions add to every reply.

## Not proven
- One probe per side on one toy problem, model sonnet; the line's quality across problems is not measured.
- The interactive `AskUserQuestion` path was not driven; the probe ran headless.
