mkdir -p /tmp/probe-home
git config --global init.defaultBranch main
cd /work

export PATH="$HOME/omptool/node_modules/.bin:$PATH"
npm install --no-fund --no-audit --prefix "$HOME/omptool" @oh-my-pi/pi-coding-agent bun > /work/omp-install.log 2>&1 || { echo omp-install-failed; cat /work/omp-install.log; exit 0; }
mkdir -p "$HOME/.omp/agent"
printf "providers:\n  neuralwatt:\n    baseUrl: https://api.neuralwatt.com/v1\n    api: openai-completions\n    apiKey: %s\n    models:\n      - id: deepseek-v4-flash\n" "$ANTHROPIC_API_KEY" > "$HOME/.omp/agent/models.yml"
printf "tools:\n  approvalMode: yolo\n  enabled: true\nsetupVersion: 2\nmodelRoles:\n  default: neuralwatt/deepseek-v4-flash\n" > "$HOME/.omp/agent/config.yml"
timeout 1800 omp -p --auto-approve --mode json --model neuralwatt/deepseek-v4-flash "$(cat /work/PROMPT.txt)" < /dev/null > /work/transcript.jsonl 2> /work/probe-stderr.log
rc=$?; echo probe-exit=$rc; exit $rc

