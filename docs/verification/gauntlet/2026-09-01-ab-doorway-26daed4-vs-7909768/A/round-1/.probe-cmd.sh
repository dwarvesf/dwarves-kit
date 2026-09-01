mkdir -p /tmp/probe-home
git config --global init.defaultBranch main
cd /work

mkdir -p "$HOME/.omp/agent"
printf "providers:\n  neuralwatt:\n    baseUrl: https://api.neuralwatt.com/v1\n    api: openai-completions\n    apiKey: %s\n    models:\n      - id: deepseek-v4-flash\n" "$ANTHROPIC_API_KEY" > "$HOME/.omp/agent/models.yml"
printf "tools:\n  approvalMode: yolo\n  enabled: true\nsetupVersion: 2\nmodelRoles:\n  default: neuralwatt/deepseek-v4-flash\n" > "$HOME/.omp/agent/config.yml"
timeout 1800 omp -p --auto-approve --mode json --model neuralwatt/deepseek-v4-flash "$(cat /work/PROMPT.txt)" < /dev/null > /work/transcript.jsonl 2> /work/probe-stderr.log
rc=$?; echo probe-exit=$rc; exit $rc

