mkdir -p /tmp/probe-home
git config --global init.defaultBranch main
cd /work
timeout 1800 claude -p --dangerously-skip-permissions --model claude-sonnet-5 --output-format stream-json --verbose < /work/PROMPT.txt > /work/transcript.jsonl 2>/work/probe-stderr.log; echo probe-exit=$?
