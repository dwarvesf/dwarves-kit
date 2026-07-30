#!/usr/bin/env bash
mkdir -p /private/tmp/demo/project2/_meta
git -C /private/tmp/demo/project2 init -q >/dev/null 2>&1
cd /private/tmp/demo/project2
time \
  REPO_ROOT=/private/tmp/demo/project2 \
  HARVEST_EXTRACTOR=/private/tmp/demo/demo-extractor.sh \
  HARVEST_MIN_INTERVAL=0 \
  HARVEST_STATE_DIR=/private/tmp/demo/state2 \
  claude -p "Reply with exactly OK, no tools." --model haiku \
  --setting-sources project --settings /private/tmp/demo/settings-demo-fixed.json
